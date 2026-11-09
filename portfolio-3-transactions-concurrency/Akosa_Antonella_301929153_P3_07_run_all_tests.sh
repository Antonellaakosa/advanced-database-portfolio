#!/usr/bin/env bash
# =====================================================================
# Unity Public Library Network (UPLN) | MIT 8103 | Portfolio 3
# File    : Akosa_Antonella_301929153_P3_07_run_all_tests.sh
# Purpose : Rebuilds the test database and runs every Portfolio 3 test in
#           order, then prints ONE summary table. Takes about 1.5 minutes.
# Run     : bash portfolio-3-transactions-concurrency/Akosa_Antonella_301929153_P3_07_run_all_tests.sh   (from the repo root)
# =====================================================================
set -u
source "$(dirname "$0")/Akosa_Antonella_301929153_P3_lib.sh"

echo "Rebuilding $DB ..."
bash "$HERE/Akosa_Antonella_301929153_P3_00_setup.sh" > /dev/null 2>&1 || { echo "Setup failed. Run Akosa_Antonella_301929153_P3_00_setup.sh on its own to see why."; exit 1; }

echo "Running the tests (each one prints its own PASS/FAIL lines to a log, only the summary is shown here)..."
psqlx -v ON_ERROR_STOP=0 < "$HERE/Akosa_Antonella_301929153_P3_02_acid_basics.sql" > /dev/null 2>&1;  echo "   done: 02 ACID basics"
for f in Akosa_Antonella_301929153_P3_03_double_borrow_race Akosa_Antonella_301929153_P3_04_isolation_levels Akosa_Antonella_301929153_P3_05_deadlock Akosa_Antonella_301929153_P3_06_two_cashiers; do
  bash "$HERE/$f.sh" > "$TMPD/$f.log" 2>&1; echo "   done: $f"
done

echo
echo "=== Portfolio 3: all tests ==="
show_table "SELECT test_group, pass, fail, total FROM (
  SELECT scenario AS test_group, count(*) FILTER (WHERE ok) AS pass, count(*) FILTER (WHERE NOT ok) AS fail, count(*) AS total, 0 AS ord
  FROM p3_results GROUP BY scenario
  UNION ALL
  SELECT 'ALL TESTS', count(*) FILTER (WHERE ok), count(*) FILTER (WHERE NOT ok), count(*), 1 FROM p3_results) t
ORDER BY ord, test_group"
echo
FAILS="$(sql 'SELECT count(*) FROM p3_results WHERE NOT ok')"
if [ "$FAILS" = "0" ]; then echo "Every check passed."; else echo "$FAILS check(s) failed. The failing ones:"; show_table "SELECT code, label FROM p3_results WHERE NOT ok ORDER BY at"; fi
[ "$FAILS" = "0" ]
