#!/usr/bin/env bash
# =====================================================================
# Unity Public Library Network (UPLN) | MIT 8103 | Portfolio 3
# File    : Akosa_Antonella_301929153_P3_05_deadlock.sh
# Purpose : A deadlock: two staff each hold one copy's row and wait for the
#           other's. PostgreSQL detects the cycle and cancels one of them.
#   Part 1  Opposite lock order  -> deadlock
#   Part 2  Same lock order      -> no deadlock (the standard fix)
# Run     : bash portfolio-3-transactions-concurrency/Akosa_Antonella_301929153_P3_05_deadlock.sh   (from the repo root)
# Requires: Akosa_Antonella_301929153_P3_00_setup.sh
# =====================================================================
set -u
source "$(dirname "$0")/Akosa_Antonella_301929153_P3_lib.sh"
S=deadlock
sql "DELETE FROM p3_results WHERE scenario='$S'" > /dev/null
fixture() { sql "SELECT p3_cleanup(); SELECT p3_copy('P3-DL-1'); SELECT p3_copy('P3-DL-2');" > /dev/null; }

# Two staff doing a stock-check at the same time. One goes shelf 1 then shelf 2, the other 2 then 1.
unsafe_staff() {   # $1 = label, $2 = first barcode, $3 = second barcode, $4 = condition to set
cat <<SQL
SET deadlock_timeout = '1500ms';
\\echo $1: stock-check, shelf $2 first and then $3
BEGIN;
UPDATE copy SET copy_condition = '$4' WHERE barcode = '$2';
\\echo $1: holds the lock on $2
SELECT pg_sleep(1) \\g /dev/null
\\echo $1: now needs $3
UPDATE copy SET copy_condition = '$4' WHERE barcode = '$3';
\\if :ERROR
  ROLLBACK;
  \\echo $1: was cancelled by the database and rolled back (it must try again later)
\\else
  COMMIT;
  \\echo $1: COMMIT done
\\endif
SQL
}

hdr "PART 1: A takes P3-DL-1 then P3-DL-2.  B takes P3-DL-2 then P3-DL-1."
fixture; begin_scenario
session A 0   "$(unsafe_staff A P3-DL-1 P3-DL-2 fair)"
session B 0.2 "$(unsafe_staff B P3-DL-2 P3-DL-1 poor)"
session OBS 1.9 "$(observer_sql)"
timeline
check "SELECT p3_check('$S','D1','exactly one session was chosen as the deadlock victim ($(count_of 'deadlock detected') error)', $(count_of 'deadlock detected') = 1)"
check "SELECT p3_check('$S','D2','the other session was not harmed and its COMMIT succeeded', $(count_of 'COMMIT done') = 1)"
check "SELECT p3_check('$S','D3','the observer saw both sessions waiting on each other ($(count_of 'OBSERVER') waiting)', $(count_of 'OBSERVER') = 2)"

hdr "PART 2: the fix. Both lock P3-DL-1 first and P3-DL-2 second, always in the same order."
fixture; begin_scenario
ordered_staff() {   # $1 = label, $2 = condition to set
cat <<SQL
SET deadlock_timeout = '1500ms';
\\echo $1: stock-check, locking both copies in copy_id order
BEGIN;
SELECT 'locked: ' || barcode FROM copy WHERE barcode IN ('P3-DL-1','P3-DL-2') ORDER BY copy_id FOR UPDATE;
SELECT pg_sleep(1.5) \\g /dev/null
UPDATE copy SET copy_condition = '$2' WHERE barcode IN ('P3-DL-1','P3-DL-2');
COMMIT;
\\echo $1: COMMIT done
SQL
}
session A 0   "$(ordered_staff A fair)"
session B 0.3 "$(ordered_staff B poor)"
session OBS 1 "$(observer_sql)"
timeline
check "SELECT p3_check('$S','D4','no deadlock this time', $(count_of 'deadlock detected') = 0)"
check "SELECT p3_check('$S','D5','both sessions committed (B simply waited its turn)', $(count_of 'COMMIT done') = 2)"
check "SELECT p3_check('$S','D6','the later transaction won: both copies end up with condition poor',
   (SELECT count(*) FROM copy WHERE barcode LIKE 'P3-DL-%' AND copy_condition = 'poor') = 2)"
sql "SELECT p3_cleanup()" > /dev/null
summary "deadlock"
