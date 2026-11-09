#!/usr/bin/env bash
# =====================================================================
# UPLN | MIT 8103 | Portfolio 5
# File    : Akosa_Antonella_301929153_P5_03_replication_tests.sh
# Purpose : Streaming replication from the primary to the replica:
#           is it running, is it encrypted, how far behind is the copy,
#           is the copy really read-only, and what changes when the primary
#           must wait for the replica (synchronous commit)?
# Run     : bash portfolio-5-distributed-cloud/Akosa_Antonella_301929153_P5_03_replication_tests.sh
# =====================================================================
set -u
source "$(dirname "$0")/Akosa_Antonella_301929153_P5_lib.sh"
begin_scenario "03_replication"
echo "== Replication tests: primary -> replica =="

hdr "Is the replica attached and healthy?"
R="$(asql primary "select state||'/'||sync_state from pg_stat_replication where application_name='replica1'")"
echo "   pg_stat_replication on the primary: replica1 is $R"
check R1 "the replica is a standby (in recovery, read-only)" "$(yes_if '[ "$(asql replica "select pg_is_in_recovery()")" = t ]')"
check R2 "the primary sees the replica streaming (asynchronous by default)" "$(yes_if '[ "$R" = "streaming/async" ]')"
check R3 "the replication connection itself is encrypted with TLS" \
  "$(yes_if '[ "$(asql primary "select s.ssl from pg_stat_ssl s join pg_stat_replication r using (pid) where r.application_name='"'"'replica1'"'"'")" = t ]')"
check R4 "a replication slot keeps the WAL the replica still needs" \
  "$(yes_if '[ "$(asql primary "select active from pg_replication_slots where slot_name='"'"'replica1'"'"'")" = t ]')"

hdr "Does a write on the primary reach the replica, and how fast?"
TAG="r-$(date +%s%N)"
asql primary "insert into p5_ledger(note) values ('$TAG')" >/dev/null
T0="$(now_ms)"; seen=false
for i in $(seq 1 200); do
  if [ "$(asql replica "select count(*) from p5_ledger where note='$TAG'")" = 1 ]; then seen=true; break; fi
  sleep 0.05
done
LAG=$(( $(now_ms) - T0 ))
echo "   the row was visible on the replica ${LAG} ms after the insert returned (includes the cost of the check itself)"
check R5 "a row written on the primary appears on the replica" "$seen"

hdr "Is the copy really read-only?"
ERR="$(asql replica "insert into p5_ledger(note) values ('should-fail')" 2>&1 || true)"
echo "   writing on the replica says: $(echo "$ERR" | head -1)"
check R6 "writing to the replica is refused (read-only transaction)" "$(yes_if 'echo "$ERR" | grep -qi "read-only transaction"')"
CNT="$(np replica p5_report "" -c "select count(*) from title" 2>&1 || true)"
check R7 "the reporting account can read the catalogue from the replica (offloading reads)" "$(yes_if '[ "$CNT" = 10 ]')"

hdr "How far behind is the replica when idle?"
for i in $(seq 1 40); do
  B="$(asql primary "select pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)::bigint from pg_stat_replication where application_name='replica1'")"
  [ "$B" = 0 ] && break; sleep 0.25
done
echo "   replication lag: ${B} bytes"
check R8 "once the primary is idle the replica has replayed everything (0 bytes behind)" "$(yes_if '[ "$B" = 0 ]')"

hdr "Consistency versus availability: synchronous commit"
admin primary -c "alter system set synchronous_standby_names = 'replica1'" -c "select pg_reload_conf()" >/dev/null
for i in $(seq 1 40); do [ "$(asql primary "select sync_state from pg_stat_replication where application_name='replica1'")" = sync ] && break; sleep 0.25; done
check R9 "with synchronous_standby_names set, the replica becomes the synchronous standby" \
  "$(yes_if '[ "$(asql primary "select sync_state from pg_stat_replication where application_name='"'"'replica1'"'"'")" = sync ]')"
T0="$(now_ms)"; asql primary "insert into p5_ledger(note) values ('sync-ok')" >/dev/null; OKMS=$(( $(now_ms) - T0 ))
echo "   commit with the replica up: ${OKMS} ms"
check R10 "commit with the replica up is quick (under 2 seconds)" "$(yes_if '[ "$OKMS" -lt 2000 ]')"

echo "   now the replica is switched off. The primary is healthy, but a commit has nobody to confirm it..."
node_stop replica
T0="$(now_ms)"
( sleep 3; asql primary "select pg_cancel_backend(pid) from pg_stat_activity where query like '%sync-blocked-$TAG%' and pid <> pg_backend_pid()" >/dev/null 2>&1 ) &
OUT="$(admin primary -c "insert into p5_ledger(note) values ('sync-blocked-$TAG')" 2>&1 || true)"
wait
BLK=$(( $(now_ms) - T0 ))
echo "   the commit waited ${BLK} ms until it was cancelled (3 s): $(echo "$OUT" | grep -i "synchronous" | head -1)"
check R11 "with the replica down, a synchronous commit hangs until cancelled (consistency chosen over availability)" \
  "$(yes_if '[ "$BLK" -ge 2500 ]')"

echo "   returning to asynchronous replication and restarting the replica..."
admin primary -c "alter system reset synchronous_standby_names" -c "select pg_reload_conf()" >/dev/null
node_start replica; wait_node replica 60
for i in $(seq 1 80); do [ "$(asql primary "select state||'/'||sync_state from pg_stat_replication where application_name='replica1'")" = "streaming/async" ] && break; sleep 0.5; done
for i in $(seq 1 40); do [ "$(asql replica "select count(*) from p5_ledger where note='sync-blocked-$TAG'")" = 1 ] && break; sleep 0.5; done
check R12 "after the restart the replica catches up and also holds the row that was committed locally while it was away" \
  "$(yes_if '[ "$(asql replica "select count(*) from p5_ledger where note='"'"'sync-blocked-$TAG'"'"'")" = 1 ]')"
summary
