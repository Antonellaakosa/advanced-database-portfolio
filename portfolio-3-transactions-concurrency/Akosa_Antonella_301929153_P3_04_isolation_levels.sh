#!/usr/bin/env bash
# =====================================================================
# Unity Public Library Network (UPLN) | MIT 8103 | Portfolio 3
# File    : Akosa_Antonella_301929153_P3_04_isolation_levels.sh
# Purpose : What other sessions can and cannot see, and what goes wrong
#           when two people read-then-write at the same time.
#   Part 1  Dirty read / non-repeatable read: READ COMMITTED, REPEATABLE READ, READ UNCOMMITTED
#   Part 2  Lost update: two renewals of the same loan (unsafe vs one atomic UPDATE)
#   Part 3  Write skew: the 5-loan limit broken by two borrows at once,
#           under READ COMMITTED, REPEATABLE READ and SERIALIZABLE (with retry),
#           then the safe checkout_copy()
# Run     : bash portfolio-3-transactions-concurrency/Akosa_Antonella_301929153_P3_04_isolation_levels.sh   (from the repo root)
# Requires: Akosa_Antonella_301929153_P3_00_setup.sh
# =====================================================================
set -u
source "$(dirname "$0")/Akosa_Antonella_301929153_P3_lib.sh"
S=isolation
sql "DELETE FROM p3_results WHERE scenario='$S'" > /dev/null

# ---------------------------------------------------------------------
# PART 1
# ---------------------------------------------------------------------
reader() {   # $1 = isolation level, $2 = seconds between the two reads
cat <<SQL
\\echo R: a front-desk screen reads the status of copy P3-ISO-1 twice (isolation level: $1)
BEGIN ISOLATION LEVEL $1;
SELECT 'R: first read  -> ' || status FROM copy WHERE barcode = 'P3-ISO-1';
SELECT pg_sleep($2) \\g /dev/null
SELECT 'R: second read -> ' || status FROM copy WHERE barcode = 'P3-ISO-1';
COMMIT;
SQL
}
writer() {   # $1 = seconds to hold the change before committing
cat <<SQL
\\echo W: a librarian withdraws copy P3-ISO-1 (damaged)
BEGIN;
UPDATE copy SET status = 'withdrawn' WHERE barcode = 'P3-ISO-1';
\\echo W: change made inside the transaction, NOT committed yet
SELECT pg_sleep($1) \\g /dev/null
COMMIT;
\\echo W: COMMIT done, the change is now permanent
SQL
}
fix_iso() { sql "SELECT p3_cleanup(); SELECT p3_copy('P3-ISO-1');" > /dev/null; }

echo
hdr "PART 1a: READ COMMITTED (PostgreSQL default): a non-repeatable read"
fix_iso; begin_scenario
session R 0   "$(reader 'READ COMMITTED' 2)"
session W 0.5 "$(writer 0)"
timeline
check "SELECT p3_check('$S','I1','READ COMMITTED: the same query gave two different answers inside one transaction (non-repeatable read)',
   $(saw 'first read  -> available') AND $(saw 'second read -> withdrawn'))"

hdr "PART 1b: REPEATABLE READ: the reader keeps a frozen snapshot"
fix_iso; begin_scenario
session R 0   "$(reader 'REPEATABLE READ' 2)"
session W 0.5 "$(writer 0)"
timeline
check "SELECT p3_check('$S','I2','REPEATABLE READ: both reads agree, the later commit is invisible to this transaction',
   $(saw 'first read  -> available') AND $(saw 'second read -> available'))"

hdr "PART 1c: READ UNCOMMITTED: PostgreSQL still never shows uncommitted data"
fix_iso; begin_scenario
session R 0   "$(reader 'READ UNCOMMITTED' 1.5)"
session W 0.4 "$(writer 2)"
timeline
check "SELECT p3_check('$S','I3','READ UNCOMMITTED: no dirty read, the reader never saw the half-finished change',
   $(saw 'first read  -> available') AND $(saw 'second read -> available'))"
check "SELECT p3_check('$S','I4','the change became visible only after the writer committed',
   (SELECT status FROM copy WHERE barcode='P3-ISO-1') = 'withdrawn')"

# ---------------------------------------------------------------------
# PART 2: lost update
# ---------------------------------------------------------------------
fix_renew() {
  sql "SELECT p3_cleanup(); SELECT p3_copy('P3-REN-1','on_loan'); SELECT p3_member('renew');
       INSERT INTO loan (copy_id, member_id, issued_by_staff_id, checkout_branch_id, loaned_at, due_at, renewals)
       VALUES (p3_copy_id('P3-REN-1'), p3_member_id('renew'), $STAFF_ID, 1, now() - interval '7 days', date_trunc('day', now()) + interval '7 days', 1);" > /dev/null
}
renew_unsafe() {   # $1 = A or B
cat <<SQL
\\echo $1: front desk $1 renews the loan (read the count, decide, then write it back)
BEGIN;
SELECT renewals AS r, (renewals < 2) AS ok FROM loan WHERE copy_id = p3_copy_id('P3-REN-1') AND returned_at IS NULL \\gset
\\echo $1: read renewals = :r (limit is 2), so $1 decides: renewal allowed = :ok
SELECT pg_sleep(1.5) \\g /dev/null
\\if :ok
  UPDATE loan SET renewals = :r + 1, due_at = due_at + interval '7 days' WHERE copy_id = p3_copy_id('P3-REN-1') AND returned_at IS NULL;
  COMMIT;
  \\echo $1: renewal APPROVED, due date moved 7 days
\\else
  ROLLBACK;
  \\echo $1: renewal REFUSED
\\endif
SQL
}
renew_safe() {   # $1 = A or B
cat <<SQL
\\echo $1: front desk $1 renews the loan with ONE atomic UPDATE that checks the limit itself
BEGIN;
WITH u AS (
  UPDATE loan SET renewals = renewals + 1, due_at = due_at + interval '7 days'
  WHERE copy_id = p3_copy_id('P3-REN-1') AND returned_at IS NULL AND renewals < 2
  RETURNING renewals)
SELECT '$1: renewal APPROVED, renewals is now ' || renewals FROM u
UNION ALL SELECT '$1: renewal REFUSED (the limit was already reached)' WHERE NOT EXISTS (SELECT 1 FROM u);
SELECT pg_sleep(1.5) \\g /dev/null
COMMIT;
\\echo $1: COMMIT done
SQL
}

hdr "PART 2a: lost update: read the count, decide in the app, write it back"
echo "   The loan has been renewed once. The limit is 2, so exactly ONE more renewal is allowed."
fix_renew; begin_scenario
session A 0   "$(renew_unsafe A)"
session B 0.4 "$(renew_unsafe B)"
timeline
check "SELECT p3_check('$S','L1','unsafe: BOTH front desks were told the renewal was approved (only one was allowed)',
   $(saw 'A: renewal APPROVED') AND $(saw 'B: renewal APPROVED'))"
check "SELECT p3_check('$S','L2','unsafe: the loan was extended twice (+14 days) although only one renewal was left',
   (SELECT due_at::date - (date_trunc('day', now()) + interval '7 days')::date FROM loan WHERE copy_id = p3_copy_id('P3-REN-1') AND returned_at IS NULL) = 14)"

hdr "PART 2b: the same two renewals with one atomic UPDATE"
fix_renew; begin_scenario
session A 0   "$(renew_safe A)"
session B 0.4 "$(renew_safe B)"
session OBS 1 "$(observer_sql)"
timeline
check "SELECT p3_check('$S','L3','atomic UPDATE: exactly one renewal approved and the other refused',
   $(saw 'A: renewal APPROVED') AND $(saw 'B: renewal REFUSED'))"
check "SELECT p3_check('$S','L4','atomic UPDATE: renewals = 2 (the limit) and the loan was extended exactly once',
   (SELECT renewals = 2 AND due_at::date - (date_trunc('day', now()) + interval '7 days')::date = 7
    FROM loan WHERE copy_id = p3_copy_id('P3-REN-1') AND returned_at IS NULL))"

# ---------------------------------------------------------------------
# PART 3: write skew (the loan limit)
# ---------------------------------------------------------------------
fix_limit() {
  sql "SELECT p3_cleanup(); SELECT p3_member('limit');
       SELECT p3_copy('P3-LIM-' || g, CASE WHEN g <= 4 THEN 'on_loan' ELSE 'available' END) FROM generate_series(1,6) g;
       INSERT INTO loan (copy_id, member_id, issued_by_staff_id, checkout_branch_id, due_at)
       SELECT p3_copy_id('P3-LIM-' || g), p3_member_id('limit'), $STAFF_ID, 1, now() + interval '14 days' FROM generate_series(1,4) g;" > /dev/null
}
active_loans() { sql "SELECT count(*) FROM loan WHERE member_id = p3_member_id('limit') AND returned_at IS NULL"; }

unsafe_borrow() {   # $1 = label, $2 = copy number, $3 = isolation level, $4 = pause inside the function
cat <<SQL
\\echo $1: borrows copy P3-LIM-$2 for the member who already has 4 of 5 loans (isolation level: $3)
BEGIN ISOLATION LEVEL $3;
SELECT '$1: no lock version, loan created: ' || checkout_unsafe(p3_copy_id('P3-LIM-$2'), p3_member_id('limit'), $STAFF_ID, $4);
\\if :ERROR
  \\echo $1: this transaction FAILED, rolling back
  ROLLBACK;
\\else
  COMMIT;
  \\if :ERROR
    \\echo $1: the COMMIT itself was refused
  \\else
    \\echo $1: COMMIT done
  \\endif
\\endif
SQL
}

for LEVEL in "READ COMMITTED" "REPEATABLE READ"; do
  hdr "PART 3: two borrows at once, member has 4 of 5 loans, level = $LEVEL (no locks)"
  fix_limit; begin_scenario
  session A 0   "$(unsafe_borrow A 5 "$LEVEL" 1.5)"
  session B 0.4 "$(unsafe_borrow B 6 "$LEVEL" 1.5)"
  timeline
  N="$(active_loans)"
  case "$LEVEL" in "READ COMMITTED") CODE=W1;; *) CODE=W2;; esac
  check "SELECT p3_check('$S','$CODE','$LEVEL: both borrows succeeded, the member now has $N active loans (limit 5): the rule is broken', $N = 6)"
done

hdr "PART 3: the same race under SERIALIZABLE"
fix_limit; begin_scenario
session A 0   "$(unsafe_borrow A 5 SERIALIZABLE 1.5)"
session B 0.4 "$(unsafe_borrow B 6 SERIALIZABLE 1.5)"
timeline
N="$(active_loans)"
check "SELECT p3_check('$S','W3','SERIALIZABLE: the database detected the conflict and cancelled one transaction (could not serialize)', $(saw 'could not serialize'))"
check "SELECT p3_check('$S','W4','SERIALIZABLE: the limit holds, the member has $N active loans', $N = 5)"
FAILED="$(printf '%s' "$CAPTURED" | grep 'could not serialize' | head -1 | cut -d'|' -f2)"
if [ -n "$FAILED" ]; then
  [ "$FAILED" = "A" ] && CN=5 || CN=6
  echo "   Standard practice: the application RETRIES the cancelled transaction ($FAILED retries copy P3-LIM-$CN)."
  begin_scenario
  session RTY 0 "$(unsafe_borrow "$FAILED (retry)" $CN SERIALIZABLE 0)"
  timeline
  N="$(active_loans)"
  check "SELECT p3_check('$S','W5','after the retry the rule is applied correctly (UPLN-023, limit reached) and the member still has $N loans', $(saw 'UPLN-023') AND $N = 5)"
else
  check "SELECT p3_check('$S','W5','a retry was needed but no transaction failed', false)"
fi

hdr "PART 3: the safe checkout_copy() at the DEFAULT level (it locks the member row)"
fix_limit; begin_scenario
safe_borrow() {   # $1 = label, $2 = copy number
cat <<SQL
\\echo $1: calls checkout_copy for copy P3-LIM-$2
BEGIN;
SELECT '$1: checkout_copy succeeded, loan ' || checkout_copy(p3_copy_id('P3-LIM-$2'), p3_member_id('limit'), $STAFF_ID);
\\if :ERROR
  \\echo $1: refused with a clear rule message, rolling back
  ROLLBACK;
\\else
  SELECT pg_sleep(1.5) \\g /dev/null
  COMMIT;
  \\echo $1: COMMIT done
\\endif
SQL
}
session A 0   "$(safe_borrow A 5)"
session B 0.4 "$(safe_borrow B 6)"
session OBS 1 "$(observer_sql)"
timeline
N="$(active_loans)"
check "SELECT p3_check('$S','W6','checkout_copy(): the second borrow waited for the member lock, saw 5 loans and was refused with UPLN-023', $(saw 'UPLN-023'))"
check "SELECT p3_check('$S','W7','checkout_copy(): the member has exactly 5 active loans (limit respected) at the default isolation level', $N = 5)"
sql "SELECT p3_cleanup()" > /dev/null
summary "isolation levels"
