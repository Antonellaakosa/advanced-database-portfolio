#!/usr/bin/env bash
# =====================================================================
# UPLN | MIT 8103 | Portfolio 5
# File    : 08_run_all_tests.sh
# Purpose : Builds the cluster from nothing, runs every test in a safe
#           order and prints one summary. Takes about 5 minutes.
#           (The failover test runs last because it changes the cluster.)
# Run     : bash portfolio-5-distributed-cloud/08_run_all_tests.sh
# =====================================================================
set -u
source "$(dirname "$0")/lib.sh"
rm -f "$RESULTS"; : > "$RESULTS"
bash "$HERE/01_start_cluster.sh" --reset   || exit 1
bash "$HERE/02_load_primary.sh"            || exit 1
for t in 03_replication_tests 04_sharding 05_security_checks 06_backup_pitr 07_failover; do
  bash "$HERE/$t.sh"
done
echo
echo "================ SUMMARY ================"
printf "%-18s %5s %5s\n" scenario PASS FAIL
awk -F'\t' '{ if ($3=="PASS") p[$1]++; else f[$1]++; s[$1]=1 }
  END { for (k in s) printf "%-18s %5d %5d\n", k, p[k]+0, f[k]+0 }' "$RESULTS" | sort
echo "-----------------------------"
awk -F'\t' '{ if ($3=="PASS") p++; else f++ } END { printf "%-18s %5d %5d\n", "ALL P5 TESTS", p, f }' "$RESULTS"
