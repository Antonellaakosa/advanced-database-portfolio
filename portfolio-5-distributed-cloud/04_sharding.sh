#!/usr/bin/env bash
# =====================================================================
# UPLN | MIT 8103 | Portfolio 5
# File    : 04_sharding.sh
# Purpose : Horizontal partitioning ("sharding") of loan history by branch.
#           shard_north keeps Abuja (ABJ) and Kano (KAN); shard_south keeps
#           Lagos (LOS), Port Harcourt (PHC) and Enugu (ENU).
#           The primary acts as the coordinator: `branch_loan` looks like one
#           table, but each branch's rows live on a different server
#           (postgres_fdw foreign tables used as partitions).
# Run     : bash portfolio-5-distributed-cloud/04_sharding.sh
# =====================================================================
set -u
source "$(dirname "$0")/lib.sh"
begin_scenario "04_sharding"
echo "== Sharding loan history by branch =="

NH="$(peer_host shard_north)"; NP="$(peer_port shard_north)"
SH="$(peer_host shard_south)"; SP="$(peer_port shard_south)"

make_shard() {   # node "branch list"
  local node="$1"; shift
  admin "$node" > /dev/null <<SQL
DROP TABLE IF EXISTS branch_loan;
CREATE TABLE branch_loan (
  branch_code  text NOT NULL,
  loan_id      bigint NOT NULL,
  member_ref   text NOT NULL,
  copy_ref     int  NOT NULL,
  loaned_at    timestamptz NOT NULL,
  due_at       timestamptz NOT NULL,
  returned_at  timestamptz,
  fine_ngn     numeric(10,2) NOT NULL DEFAULT 0,
  PRIMARY KEY (branch_code, loan_id)
);
INSERT INTO branch_loan
SELECT b.code, b.idx * 100000 + g, 'M' || (1 + g % 3000), 1 + (g * 7) % 5000,
       timestamptz '2026-01-01' + (g % 250) * interval '1 day',
       timestamptz '2026-01-15' + (g % 250) * interval '1 day',
       CASE WHEN g % 7 = 0 THEN NULL ELSE timestamptz '2026-01-10' + (g % 250) * interval '1 day' END,
       CASE WHEN (g + b.idx) % 11 = 0 THEN 50 * (1 + (g + b.idx) % 6) ELSE 0 END
FROM (VALUES $1) AS b(code, idx), generate_series(1, 10000) AS g;
CREATE INDEX ix_branch_loan_member ON branch_loan (member_ref);
GRANT SELECT, INSERT, UPDATE, DELETE ON branch_loan TO fdw_user;
ANALYZE branch_loan;
SQL
}
echo "   building the north shard (ABJ, KAN) and the south shard (LOS, PHC, ENU), 10,000 loans per branch..."
make_shard shard_north "('ABJ',1),('KAN',2)"
make_shard shard_south "('LOS',3),('PHC',4),('ENU',5)"

echo "   connecting the coordinator (primary) to both shards over TLS..."
admin primary > /dev/null <<SQL
CREATE EXTENSION IF NOT EXISTS postgres_fdw;
DROP TABLE  IF EXISTS branch_loan CASCADE;
DROP SERVER IF EXISTS shard_north CASCADE;
DROP SERVER IF EXISTS shard_south CASCADE;
CREATE SERVER shard_north FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host '$NH', port '$NP', dbname 'shard', sslmode 'require');
CREATE SERVER shard_south FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host '$SH', port '$SP', dbname 'shard', sslmode 'require');
CREATE USER MAPPING FOR library_admin SERVER shard_north OPTIONS (user 'fdw_user', password '$FDW_PW');
CREATE USER MAPPING FOR library_admin SERVER shard_south OPTIONS (user 'fdw_user', password '$FDW_PW');
CREATE TABLE branch_loan (
  branch_code text NOT NULL, loan_id bigint NOT NULL, member_ref text NOT NULL, copy_ref int NOT NULL,
  loaned_at timestamptz NOT NULL, due_at timestamptz NOT NULL, returned_at timestamptz, fine_ngn numeric(10,2) NOT NULL DEFAULT 0
) PARTITION BY LIST (branch_code);
CREATE FOREIGN TABLE branch_loan_north PARTITION OF branch_loan FOR VALUES IN ('ABJ','KAN') SERVER shard_north OPTIONS (table_name 'branch_loan');
CREATE FOREIGN TABLE branch_loan_south PARTITION OF branch_loan FOR VALUES IN ('LOS','PHC','ENU') SERVER shard_south OPTIONS (table_name 'branch_loan');
GRANT SELECT ON branch_loan TO p5_report;
SQL
# the reporting account reads through the coordinator too
admin primary -c "CREATE USER MAPPING IF NOT EXISTS FOR p5_report SERVER shard_north OPTIONS (user 'fdw_user', password '$FDW_PW')" \
              -c "CREATE USER MAPPING IF NOT EXISTS FOR p5_report SERVER shard_south OPTIONS (user 'fdw_user', password '$FDW_PW')" > /dev/null
admin primary -c "GRANT USAGE ON FOREIGN SERVER shard_north, shard_south TO p5_report" > /dev/null

hdr "Where does each branch's data live?"
NB="$(asql shard_north "select string_agg(distinct branch_code, ',' order by branch_code) from branch_loan")"
SB="$(asql shard_south "select string_agg(distinct branch_code, ',' order by branch_code) from branch_loan")"
echo "   shard_north holds: $NB"
echo "   shard_south holds: $SB"
check H1 "shard_north holds only Abuja and Kano" "$(yes_if '[ "$NB" = "ABJ,KAN" ]')"
check H2 "shard_south holds only Lagos, Port Harcourt and Enugu" "$(yes_if '[ "$SB" = "ENU,LOS,PHC" ]')"

hdr "One logical table over two servers"
TOTAL="$(asql primary "select count(*) from branch_loan")"
SUMSH=$(( $(asql shard_north "select count(*) from branch_loan") + $(asql shard_south "select count(*) from branch_loan") ))
echo "   rows through the coordinator: $TOTAL    rows on the two shards added up: $SUMSH"
check H3 "the coordinator sees all 50,000 loans and they equal the shards added together" "$(yes_if '[ "$TOTAL" = 50000 ] && [ "$SUMSH" = 50000 ]')"

hdr "Does a query for one branch touch only its shard? (partition pruning)"
PLAN="$(admin primary -c "EXPLAIN (COSTS OFF) SELECT count(*) FROM branch_loan WHERE branch_code = 'LOS'")"
echo "$PLAN" | sed 's/^/   | /'
check H4 "a Lagos query is sent only to shard_south; shard_north is not touched" \
  "$(yes_if 'echo "$PLAN" | grep -q branch_loan_south && ! echo "$PLAN" | grep -q branch_loan_north')"
PLAN2="$(admin primary -c "EXPLAIN (COSTS OFF) SELECT branch_code, sum(fine_ngn) FROM branch_loan GROUP BY branch_code")"
check H5 "a network-wide report (no branch filter) has to ask both shards" \
  "$(yes_if 'echo "$PLAN2" | grep -q branch_loan_south && echo "$PLAN2" | grep -q branch_loan_north')"

hdr "Cross-shard report must agree with the shards"
VIA="$(asql primary "select string_agg(branch_code||'='||t, ',' order by branch_code) from (select branch_code, sum(fine_ngn) t from branch_loan group by 1) x")"
DIRECT="$( (asql shard_north "select branch_code||'='||sum(fine_ngn) from branch_loan group by branch_code"; asql shard_south "select branch_code||'='||sum(fine_ngn) from branch_loan group by branch_code") | sort | paste -sd, )"
echo "   fines per branch (NGN) via the coordinator: $VIA"
check H6 "fines per branch through the coordinator equal the totals computed on each shard" "$(yes_if '[ "$VIA" = "$DIRECT" ]')"

hdr "Writing through the coordinator"
asql primary "insert into branch_loan values ('KAN', 999999, 'M-demo', 1, now(), now() + interval '14 days', null, 0)" > /dev/null
ON_N="$(asql shard_north "select count(*) from branch_loan where loan_id=999999")"
ON_S="$(asql shard_south "select count(*) from branch_loan where loan_id=999999")"
echo "   a Kano loan inserted through the coordinator: on north=$ON_N, on south=$ON_S"
check H7 "the insert was routed to the Kano shard (north) and nowhere else" "$(yes_if '[ "$ON_N" = 1 ] && [ "$ON_S" = 0 ]')"
asql primary "delete from branch_loan where loan_id=999999" > /dev/null

hdr "Reading shards from the replica (read scale-out)"
for i in $(seq 1 40); do [ "$(asql replica "select count(*) from pg_foreign_server")" = 2 ] && break; sleep 0.5; done
RC="$(np replica p5_report "" -c "select count(*) from branch_loan" 2>&1 || true)"
echo "   reporting account, connected to the REPLICA, counts loans: $RC"
check H8 "the reporting account can run the cross-shard count from the replica" "$(yes_if '[ "$RC" = 50000 ]')"

hdr "Availability when one shard is down"
node_stop shard_south
A="$(asql primary "select count(*) from branch_loan where branch_code='ABJ'" 2>&1 || true)"
L="$(asql primary "select count(*) from branch_loan where branch_code='LOS'" 2>&1 || true)"
ALL="$(asql primary "select count(*) from branch_loan" 2>&1 || true)"
echo "   shard_south is OFF.  Abuja query: $A   |   Lagos query: $(echo "$L" | head -1)"
echo "   network-wide count: $(echo "$ALL" | head -1)"
check H9 "Abuja and Kano still work while the south shard is down (partial availability)" "$(yes_if '[ "$A" = 10000 ]')"
check H10 "Lagos queries fail while its shard is down" "$(yes_if 'echo "$L" | grep -qi "error"')"
check H11 "a network-wide report fails completely rather than returning a wrong, partial total" "$(yes_if 'echo "$ALL" | grep -qi "error"')"
node_start shard_south; wait_node shard_south 60
for i in $(seq 1 30); do [ "$(asql primary "select count(*) from branch_loan" 2>/dev/null)" = 50000 ] && break; sleep 1; done
check H12 "after the shard returns, the network-wide count is 50,000 again" "$(yes_if '[ "$(asql primary "select count(*) from branch_loan")" = 50000 ]')"
summary
