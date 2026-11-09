#!/usr/bin/env bash
# =====================================================================
# UPLN | MIT 8103 | Portfolio 5
# File    : Akosa_Antonella_301929153_P5_07_failover.sh
# Purpose : High availability drill. The primary is killed without warning,
#           the replica is promoted, and we measure how long that takes (RTO)
#           and whether any committed work was lost (RPO). Then we show the
#           danger of "split brain" (two servers that both think they are
#           the primary) and fence the old one.
# NOTE    : This script changes the cluster (the replica becomes the primary).
#           Rebuild afterwards with:  bash Akosa_Antonella_301929153_P5_01_start_cluster.sh --reset
# Run     : bash portfolio-5-distributed-cloud/Akosa_Antonella_301929153_P5_07_failover.sh
# =====================================================================
set -u
source "$(dirname "$0")/Akosa_Antonella_301929153_P5_lib.sh"
begin_scenario "07_failover"
echo "== Failover drill =="

hdr "Before the crash"
TAG="fo-$(date +%s)"
asql primary "insert into p5_ledger(note) select '$TAG-' || g from generate_series(1,200) g" > /dev/null
EXPECT="$(asql primary "select count(*) from p5_ledger where note like '$TAG-%'")"
STATE="$(asql primary "select state||'/'||sync_state from pg_stat_replication where application_name='replica1'")"
echo "   200 rows committed on the primary just now. Replica link: $STATE"
check F1 "before the crash the replica is streaming from the primary" "$(yes_if '[ "$STATE" = "streaming/async" ]')"

hdr "The crash"
T0="$(now_ms)"
node_stop primary immediate
DOWN="$(asql primary "select 1" 2>&1 || true)"
echo "   primary killed (no clean shutdown). Trying to connect: $(echo "$DOWN" | head -1 | cut -c1-90)"
check F2 "the primary is unreachable" "$(yes_if 'echo "$DOWN" | grep -qi "refused\|could not\|not running\|No such\|Error"')"

hdr "Promote the replica"
asql replica "select pg_promote(wait => true, wait_seconds => 30)" > /dev/null
W=false
for i in $(seq 1 100); do
  if asql replica "insert into p5_ledger(note) values ('$TAG-first-write-on-new-primary')" >/dev/null 2>&1; then W=true; break; fi
  sleep 0.2
done
RTO=$(( $(now_ms) - T0 ))
echo "   the replica accepted its first write ${RTO} ms after the crash (script-measured recovery time)"
check F3 "the promoted replica is writable (no longer in recovery)" "$(yes_if '[ "$(asql replica "select pg_is_in_recovery()")" = f ] && '"$W")"
check F4 "recovery time was under 30 seconds (${RTO} ms, with a human-free, scripted promotion)" "$(yes_if '[ "$RTO" -lt 30000 ]')"
FOUND="$(asql replica "select count(*) from p5_ledger where note like '$TAG-%' and note not like '%first-write%'")"
echo "   rows committed before the crash: $EXPECT, found on the new primary: $FOUND  (lost: $((EXPECT-FOUND)))"
check F5 "no committed row was lost (RPO observed = 0 rows; asynchronous replication does not guarantee this)" "$(yes_if '[ "$FOUND" = "$EXPECT" ]')"

hdr "Is the rest of the system still working through the new primary?"
CNT="$(asql replica "select count(*) from branch_loan" 2>&1 | head -1)"
echo "   cross-shard loan count through the new primary: $CNT"
check F6 "the new primary still reaches both shards (50,000 loans)" "$(yes_if '[ "$CNT" = 50000 ]')"
RP="$(np replica p5_report "" -c "select count(*) from title" 2>&1 || true)"
check F7 "the reporting account works against the new primary" "$(yes_if '[ "$RP" = 10 ]')"

hdr "Danger: split brain"
node_start primary; wait_node primary 60
OLDW="$(asql primary "select pg_is_in_recovery()")"
asql primary "insert into p5_ledger(note) values ('$TAG-written-on-OLD-primary')" > /dev/null 2>&1
ON_OLD="$(asql primary "select count(*) from p5_ledger where note='$TAG-written-on-OLD-primary'")"
ON_NEW="$(asql replica "select count(*) from p5_ledger where note='$TAG-written-on-OLD-primary'")"
echo "   the old primary restarted and accepts writes (in_recovery=$OLDW). A row written there: on old=$ON_OLD, on new=$ON_NEW"
check F8 "split brain is possible: the restarted old primary happily accepts writes that the new primary never sees" "$(yes_if '[ "$OLDW" = f ] && [ "$ON_OLD" = 1 ] && [ "$ON_NEW" = 0 ]')"
node_stop primary
GONE="$(asql primary "select 1" 2>&1 || true)"
check F9 "the old primary is fenced off (stopped); only the new primary takes writes" "$(yes_if 'echo "$GONE" | grep -qi "refused\|could not\|not running\|No such\|Error"')"
echo
echo "   Failback (rebuilding the old primary as a replica) is documented in the README, not scripted."
summary
