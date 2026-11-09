#!/usr/bin/env bash
# =====================================================================
# Unity Public Library Network (UPLN) | MIT 8103 | Portfolio 3
# File    : 03_double_borrow_race.sh
# Purpose : Two librarians try to lend the SAME copy at the SAME moment.
#   Part 1  Naive code (check, then write) with the Portfolio 1 rule in place
#   Part 2  The same naive code with that rule removed (test database only)
#   Part 3  The safe version: lock the copy first
# Run     : bash portfolio-3-transactions-concurrency/03_double_borrow_race.sh   (from the repo root)
# Requires: 00_setup.sh
# =====================================================================
set -u
source "$(dirname "$0")/lib.sh"
S=race
sql "DELETE FROM p3_results WHERE scenario='$S'" > /dev/null

fixture() {
  sql "SELECT p3_cleanup();
       SELECT p3_copy('P3-RACE-1');
       SELECT p3_member('alice');
       SELECT p3_member('bob');" > /dev/null
}

# Two librarians, "check first, write later", with no lock. The 2 s gaps stand in for
# the time it takes a real person and a real network.
naive_session() {   # $1 = A or B, $2 = member tag
cat <<SQL
\\echo $1: opens a borrow for copy P3-RACE-1 for member $2
BEGIN;
SELECT '$1: looked at the copy, status is ' || status FROM copy WHERE barcode = 'P3-RACE-1';
SELECT pg_sleep(2) \\g /dev/null
\\echo $1: status was available, so $1 writes the loan
INSERT INTO loan (copy_id, member_id, issued_by_staff_id, checkout_branch_id, due_at)
VALUES (p3_copy_id('P3-RACE-1'), p3_member_id('$2'), $STAFF_ID, 1, now() + interval '14 days');
\\if :ERROR
  \\echo $1: the DATABASE REFUSED this loan, so $1 rolls back and tells the librarian
  ROLLBACK;
\\else
  UPDATE copy SET status = 'on_loan' WHERE barcode = 'P3-RACE-1';
  \\echo $1: printing the receipt (2 s)...
  SELECT pg_sleep(2) \\g /dev/null
  COMMIT;
  \\echo $1: COMMIT done, the loan is saved
\\endif
SQL
}

echo
hdr "PART 1: naive code, Portfolio 1 rule in place (uq_one_active_loan_per_copy)"
fixture
begin_scenario
session A 0   "$(naive_session A alice)"
session B 0.5 "$(naive_session B bob)"
timeline
check "SELECT p3_check('$S','R1','exactly ONE active loan exists for the copy (the Portfolio 1 rule stopped the second)',
   (SELECT count(*) FROM loan WHERE copy_id = p3_copy_id('P3-RACE-1') AND returned_at IS NULL) = 1)"
check "SELECT p3_check('$S','R2','the loser got the unique-index error, not silent corruption', $(saw 'uq_one_active_loan_per_copy'))"
check "SELECT p3_check('$S','R3','copy status agrees with the loans (on_loan)', (SELECT status FROM copy WHERE barcode='P3-RACE-1') = 'on_loan')"

echo
hdr "PART 2: the same naive code, with the rule REMOVED (test database only)"
echo "   Removing the rule in $DB to see what it was protecting us from..."
sql "DROP INDEX uq_one_active_loan_per_copy" > /dev/null
fixture
begin_scenario
session A 0   "$(naive_session A alice)"
session B 0.5 "$(naive_session B bob)"
timeline
check "SELECT p3_check('$S','R4','without the rule BOTH loans are accepted: one copy, two borrowers (the bug is reproduced)',
   (SELECT count(*) FROM loan WHERE copy_id = p3_copy_id('P3-RACE-1') AND returned_at IS NULL) = 2)"
echo
echo "   Trying to put the rule back while the bad data exists:"
printf '%s\n' "CREATE UNIQUE INDEX uq_one_active_loan_per_copy ON loan (copy_id) WHERE returned_at IS NULL;" \
  | psqlx -v ON_ERROR_STOP=0 2>&1 | sed 's/^/      /'
echo "   It refuses: the data must be repaired first. Repairing (keeping the earliest loan), then restoring the rule."
sql "DELETE FROM loan WHERE copy_id = p3_copy_id('P3-RACE-1') AND loan_id <> (SELECT min(loan_id) FROM loan WHERE copy_id = p3_copy_id('P3-RACE-1'));
     CREATE UNIQUE INDEX uq_one_active_loan_per_copy ON loan (copy_id) WHERE returned_at IS NULL;" > /dev/null
check "SELECT p3_check('$S','R5','the Portfolio 1 rule is back in place after the experiment',
   EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'uq_one_active_loan_per_copy'))"

echo
hdr "PART 3: the safe version: checkout_copy() locks the copy first"
fixture
safe_session() {   # $1 = A or B, $2 = member tag
cat <<SQL
\\echo $1: opens a borrow for copy P3-RACE-1 for member $2 (calls checkout_copy)
BEGIN;
SELECT '$1: checkout_copy succeeded, loan id ' || checkout_copy(p3_copy_id('P3-RACE-1'), p3_member_id('$2'), $STAFF_ID);
\\if :ERROR
  \\echo $1: refused with a clear message, so $1 rolls back
  ROLLBACK;
\\else
  \\echo $1: printing the receipt (2 s)...
  SELECT pg_sleep(2) \\g /dev/null
  COMMIT;
  \\echo $1: COMMIT done, the loan is saved
\\endif
SQL
}
begin_scenario
session A 0   "$(safe_session A alice)"
session B 0.5 "$(safe_session B bob)"
session OBS 1.2 "$(observer_sql)"
timeline
WAITED_MS="$(printf '%s' "$CAPTURED" | grep 'UPLN-021' | head -1 | cut -d'|' -f1 | sed 's/^0*//')"; WAITED_MS="${WAITED_MS:-0}"
check "SELECT p3_check('$S','R6','exactly ONE active loan exists for the copy',
   (SELECT count(*) FROM loan WHERE copy_id = p3_copy_id('P3-RACE-1') AND returned_at IS NULL) = 1)"
check "SELECT p3_check('$S','R7','the second librarian got the friendly rule UPLN-021, not a raw index error', $(saw 'UPLN-021'))"
check "SELECT p3_check('$S','R8','the second librarian was held back until the first one finished (answer came at $((WAITED_MS/1000)).$(( (WAITED_MS%1000)/100 )) s, not at once)', $WAITED_MS >= 1500)"
check "SELECT p3_check('$S','R9','the observer saw a session waiting on a lock', $(saw 'OBSERVER'))"
sql "SELECT p3_cleanup()" > /dev/null
summary "double-borrow race"
