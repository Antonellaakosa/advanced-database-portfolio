#!/usr/bin/env bash
# =====================================================================
# UPLN | MIT 8103 | Portfolio 5
# File    : Akosa_Antonella_301929153_P5_01_start_cluster.sh
# Purpose : Builds and starts the four-node lab cluster (primary, replica,
#           shard_north, shard_south). Use --reset to throw everything away
#           and start from nothing (needed before a clean full test run).
# Run     : bash portfolio-5-distributed-cloud/Akosa_Antonella_301929153_P5_01_start_cluster.sh [--reset]
# =====================================================================
set -u
source "$(dirname "$0")/Akosa_Antonella_301929153_P5_lib.sh"
bash "$HERE/Akosa_Antonella_301929153_P5_00_make_certs.sh" >/dev/null || exit 1
source "$ENVF"; export ADMIN_PW REPL_PW APP_PW REPORT_PW FDW_PW

echo "== Starting the UPLN lab cluster =="
if [ -n "$LOCAL" ]; then
  bash "${UPLN_P5_HOOK:?}" ${1:-up}
else
  [ "${1:-}" = "--reset" ] && { echo "   removing the old cluster and its data..."; dc down -v >/dev/null 2>&1; }
  dc up -d 2>&1 | sed 's/^/   /'
fi
for n in primary replica shard_north shard_south; do
  printf "   waiting for %-12s " "$n"; wait_node "$n" 180 && echo "ready" || exit 1
done
echo
echo "== Cluster status =="
printf "   %-12s %-26s %-12s %s\n" NODE VERSION IN_RECOVERY TLS
for n in primary replica shard_north shard_south; do
  v="$(asql "$n" "select split_part(version(),' ',2)")"
  r="$(asql "$n" "select case when pg_is_in_recovery() then 'standby' else 'writer' end")"
  t="$(asql "$n" "select coalesce(ssl::text,'f')||' '||coalesce(version,'-') from pg_stat_ssl where pid=pg_backend_pid()")"
  printf "   %-12s %-26s %-12s %s\n" "$n" "PostgreSQL $v" "$r" "$t"
done
echo
echo "Cluster is up."
