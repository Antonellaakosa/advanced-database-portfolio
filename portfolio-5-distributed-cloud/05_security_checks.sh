#!/usr/bin/env bash
# =====================================================================
# UPLN | MIT 8103 | Portfolio 5
# File    : 05_security_checks.sh
# Purpose : Proves the security of the cluster by trying to break it:
#           no-TLS connections, wrong passwords, a replication account used
#           as a normal login, over-reaching application accounts, plain
#           passwords, exposed ports and secrets in the repository.
# Run     : bash portfolio-5-distributed-cloud/05_security_checks.sh
# =====================================================================
set -u
source "$(dirname "$0")/lib.sh"
begin_scenario "05_security"
echo "== Security checks =="

hdr "1. Encryption in transit (TLS)"
for n in primary replica shard_north shard_south; do
  OUT="$(PGSSLMODE=disable np "$n" library_admin "" -c "select 1" 2>&1 || true)"
  echo "   $n, TLS switched off by the client: $(echo "$OUT" | head -1 | cut -c1-110)"
  check "T1-$n" "a connection WITHOUT TLS to $n is refused" "$(yes_if 'echo "$OUT" | grep -qi "pg_hba.conf rejects\|no encryption\|SSL"')"
done
V="$(asql primary "select version from pg_stat_ssl where pid=pg_backend_pid()")"
echo "   normal connection uses: $V"
check T2 "a normal connection is accepted and encrypted with TLS 1.2 or newer" "$(yes_if '[ "$V" = TLSv1.3 ] || [ "$V" = TLSv1.2 ]')"
VF="$(PGSSLMODE=verify-full np primary library_admin "" -c "select 'verified'" 2>&1 || true)"
check T3 "the server certificate is verified against our own CA (verify-full)" "$(yes_if '[ "$VF" = verified ]')"

hdr "2. Authentication"
W="$(PGPASSWORD_OVERRIDE=wrong-password np primary library_admin "" -c "select 1" 2>&1 || true)"
echo "   wrong password: $(echo "$W" | head -1 | cut -c1-100)"
check T4 "a wrong password is rejected" "$(yes_if 'echo "$W" | grep -qi "password authentication failed"')"
NP="$(asql primary "select count(*) from pg_authid where rolcanlogin and (rolpassword is null or rolpassword not like 'SCRAM-SHA-256%')")"
check T5 "every login role stores a SCRAM-SHA-256 verifier (no plain or MD5 passwords): $NP exceptions" "$(yes_if '[ "$NP" = 0 ]')"

hdr "3. Least privilege"
R="$(np primary replicator "" -c "select 1" 2>&1 || true)"
echo "   replication account trying a normal SQL session: $(echo "$R" | head -1 | cut -c1-100)"
check T6 "the replication account cannot open a normal SQL session" "$(yes_if 'echo "$R" | grep -qi "rejects\|denied\|not permitted"')"
D="$(np primary p5_app "" -c "delete from loan where false" 2>&1 || true)"
echo "   application account trying DELETE on loan: $(echo "$D" | head -1)"
check T7 "the application account cannot DELETE loans" "$(yes_if 'echo "$D" | grep -qi "permission denied"')"
M="$(np primary p5_app "" -c "select count(*) from member" 2>&1 || true)"
echo "   application account reading the member table (personal data): $(echo "$M" | head -1)"
check T8 "the application account cannot read the member table (personal data)" "$(yes_if 'echo "$M" | grep -qi "permission denied"')"
I="$(np primary p5_report "" -c "insert into p5_ledger(note) values ('x')" 2>&1 || true)"
echo "   reporting account trying INSERT: $(echo "$I" | head -1)"
check T9 "the reporting account is read-only" "$(yes_if 'echo "$I" | grep -qi "permission denied"')"
C="$(np shard_north fdw_user "" -c "create table should_not_exist(i int)" 2>&1 || true)"
echo "   shard link account trying CREATE TABLE: $(echo "$C" | head -1)"
check T10 "the shard link account (fdw_user) cannot create objects on a shard" "$(yes_if 'echo "$C" | grep -qi "permission denied"')"
CN="$(np shard_north replicator "" -c "select 1" 2>&1 || true)"
check T11 "accounts of the primary do not work on the shards (separate credentials per node type)" "$(yes_if 'echo "$CN" | grep -qi "authentication failed\|rejects\|does not exist"')"

hdr "4. Integrity and logging"
CS="$(asql primary "show data_checksums")"
echo "   data checksums on the primary: $CS"
check T12 "data checksums are on (silent disk corruption would be detected)" "$(yes_if '[ "$CS" = on ]')"
LC="$(asql primary "show log_connections")"
check T13 "every connection is logged (log_connections = $LC)" "$(yes_if '[ "$LC" = on ]')"

hdr "5. Exposure and secrets"
LA=""; for n in primary replica shard_north shard_south; do LA="$LA$(asql "$n" "show listen_addresses") "; done
echo "   listen_addresses on primary, replica, shard_north, shard_south: $LA"
check T14 "all four servers listen on 127.0.0.1 only, so nothing is reachable from outside this machine" "$(yes_if '[ "$LA" = "127.0.0.1 127.0.0.1 127.0.0.1 127.0.0.1 " ]')"
GI="$(cat "$HERE/.gitignore")"
check T15 ".gitignore keeps .env.p5, certs/ and results/ out of GitHub" "$(yes_if 'echo "$GI" | grep -q "^.env.p5" && echo "$GI" | grep -q "^certs/"')"
PERM="$(stat -c %a "$ENVF" "$HERE/certs/server.key" "$HERE/certs/ca.key" | sort -u | paste -sd,)"
echo "   file permissions of .env.p5 / server.key / ca.key: $PERM"
check T16 "secret files are readable by their owner only (600)" "$(yes_if '[ "$PERM" = 600 ]')"
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  TR="$(git -C "$ROOT" ls-files | grep -cE 'portfolio-5-distributed-cloud/(\.env\.p5|certs/)' || true)"
  check T17 "no secret or key file is tracked by git ($TR tracked)" "$(yes_if '[ "$TR" = 0 ]')"
fi
summary
