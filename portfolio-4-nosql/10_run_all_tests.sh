#!/usr/bin/env bash
# =====================================================================
# Unity Public Library Network (UPLN) | MIT 8103 | Portfolio 4
# File    : 10_run_all_tests.sh
# Purpose : Runs the whole portfolio from scratch, in order, and prints one
#           summary table. Safe to repeat: every script cleans up first.
# =====================================================================
set -u
source "$(dirname "$0")/lib.sh"

echo "== Portfolio 4: full run =="
bash "$HERE/00_start_mongo.sh"                    || exit 1
bash "$HERE/01_export_from_postgres.sh"           || exit 1
for f in 02_schema_validation 03_load_migrated 04_generate_data 05_queries 06_aggregation 07_indexes_explain 08_modelling_patterns; do
  mongorun "$f.js"
done
bash "$HERE/09_reconcile.sh"

echo
echo "================ SUMMARY ================"
mongoeval '
  var rows = db.p4_results.aggregate([
    { $group: { _id: "$scenario", pass: { $sum: { $cond: ["$ok", 1, 0] } }, fail: { $sum: { $cond: ["$ok", 0, 1] } } } },
    { $sort: { _id: 1 } } ]).toArray();
  var tp = 0, tf = 0;
  print("scenario".padEnd(20) + "PASS".padStart(6) + "FAIL".padStart(6));
  rows.forEach(function (r) { tp += r.pass; tf += r.fail; print(String(r._id).padEnd(20) + String(r.pass).padStart(6) + String(r.fail).padStart(6)); });
  print("-".repeat(32));
  print("ALL MONGODB TESTS".padEnd(20) + String(tp).padStart(6) + String(tf).padStart(6));
'
