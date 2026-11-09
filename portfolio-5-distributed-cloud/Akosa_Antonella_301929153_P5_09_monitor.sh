#!/usr/bin/env bash
# =====================================================================
# UPLN | MIT 8103 | Portfolio 5
# File    : Akosa_Antonella_301929153_P5_09_monitor.sh
# Purpose : A one-screen health report for the cluster: who is the writer,
#           how far behind the replica is, whether archiving works, who is
#           connected (and over TLS), and whether the shards answer.
#           In a cloud deployment these are the numbers you would put on
#           a dashboard and attach alarms to.
# Run     : bash portfolio-5-distributed-cloud/Akosa_Antonella_301929153_P5_09_monitor.sh
# =====================================================================
set -u
source "$(dirname "$0")/Akosa_Antonella_301929153_P5_lib.sh"
echo "== UPLN cluster health report  ($(date '+%a %d %b %Y %H:%M:%S')) =="
W=""
for n in primary replica; do
  r="$(asql "$n" "select pg_is_in_recovery()" 2>/dev/null)"
  [ "$r" = f ] && W="$n"
done
echo
printf "%-12s %-10s %s\n" NODE ROLE STATUS
for n in primary replica shard_north shard_south; do
  if r="$(asql "$n" "select case when pg_is_in_recovery() then 'standby' else 'writer' end" 2>/dev/null)"; then
    sz="$(asql "$n" "select pg_size_pretty(pg_database_size(current_database()))")"
    printf "%-12s %-10s up, database size %s\n" "$n" "$r" "$sz"
  else
    printf "%-12s %-10s DOWN\n" "$n" "-"
  fi
done
[ -z "$W" ] && { echo; echo "No writer is available!"; exit 1; }
echo
echo "== Writer is: $W =="
echo "-- replication (is a standby attached, how far behind?)"
NS="$(asql "$W" "select count(*) from pg_stat_replication")"
[ "$NS" = 0 ] && echo "   (no standby is attached to the writer right now)"
admin "$W" -c "select coalesce(application_name,'-') as standby, state, sync_state, pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)::bigint as bytes_behind, coalesce(replay_lag::text,'-') as replay_lag from pg_stat_replication" | sed 's/^/   /' | sed 's/|/ | /g'
echo "-- WAL archiving (failed_count should stay 0)"
admin "$W" -c "select 'archived='||archived_count||'  failed='||failed_count||'  last='||coalesce(last_archived_wal,'-') from pg_stat_archiver" | sed 's/^/   /'
echo "-- connections by account, and whether they are encrypted"
admin "$W" -c "select coalesce(a.usename,'(background)') as account, count(*) as sessions, bool_and(coalesce(s.ssl,false)) as all_tls from pg_stat_activity a left join pg_stat_ssl s using (pid) where a.backend_type in ('client backend','walsender') group by 1 order by 1" | sed 's/^/   /' | sed 's/|/ | /g'
echo "-- shard reachability through the coordinator"
for b in ABJ LOS; do printf "   branch %s: " "$b"; admin "$W" -c "select count(*)||' loans readable' from branch_loan where branch_code='$b'" 2>&1 | head -1; done
