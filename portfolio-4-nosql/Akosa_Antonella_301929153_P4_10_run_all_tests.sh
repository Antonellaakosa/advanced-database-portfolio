#!/usr/bin/env bash
# =====================================================================
# Unity Public Library Network (UPLN) | MIT 8103 | Portfolio 4
# File    : Akosa_Antonella_301929153_P4_10_run_all_tests.sh
# Purpose : Runs the whole portfolio from scratch, in order, and prints one
#           summary table. Safe to repeat: every script cleans up first.
# =====================================================================
set -u
source "$(dirname "$0")/Akosa_Antonella_301929153_P4_lib.sh"

echo "== Portfolio 4: full run =="
bash "$HERE/Akosa_Antonella_301929153_P4_00_start_mongo.sh"                    || exit 1
bash "$HERE/Akosa_Antonella_301929153_P4_01_export_from_postgres.sh"           || exit 1
for f in Akosa_Antonella_301929153_P4_02_schema_validation Akosa_Antonella_301929153_P4_03_load_migrated Akosa_Antonella_301929153_P4_04_generate_data Akosa_Antonella_301929153_P4_05_queries Akosa_Antonella_301929153_P4_06_aggregation Akosa_Antonella_301929153_P4_07_indexes_explain Akosa_Antonella_301929153_P4_08_modelling_patterns Akosa_Antonella_301929153_P4_11_other_nosql_models Akosa_Antonella_301929153_P4_13_media_formats; do
  mongorun "$f.js"
done
bash "$HERE/Akosa_Antonella_301929153_P4_09_reconcile.sh"

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
