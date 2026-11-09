#!/usr/bin/env bash
# =====================================================================
# Unity Public Library Network (UPLN) | MIT 8103 | Portfolio 3
# File    : Akosa_Antonella_301929153_P3_06_two_cashiers.sh
# Purpose : The "two cashiers" test promised in the Portfolio 1 README.
#           Two cashiers take a payment on the SAME fine at the same moment.
#   Part 1  A payment check with NO lock (test only)  -> the fine is overpaid
#   Part 2  The real Portfolio 1 guard (locks the fine) -> the second payment is refused
# Run     : bash portfolio-3-transactions-concurrency/Akosa_Antonella_301929153_P3_06_two_cashiers.sh   (from the repo root)
# Requires: Akosa_Antonella_301929153_P3_00_setup.sh
# =====================================================================
set -u
source "$(dirname "$0")/Akosa_Antonella_301929153_P3_lib.sh"
S=cashiers
sql "DELETE FROM p3_results WHERE scenario='$S'" > /dev/null

restore_guard() {   # always leave the Portfolio 1 guard switched on, even if this script is interrupted
  sql "DROP TRIGGER IF EXISTS trg_guard_nolock ON payment;
       DROP FUNCTION IF EXISTS guard_payment_nolock();
       ALTER TABLE payment ENABLE TRIGGER trg_guard_payment;" > /dev/null 2>&1
}
trap 'restore_guard; rm -rf "$TMPD"' EXIT

# A fine of NGN 1,500 on a returned loan, with NGN 500 already paid: NGN 1,000 is still owed.
fixture() {
  sql "SELECT p3_cleanup(); SELECT p3_member('cash'); SELECT p3_copy('P3-CASH-1');
       INSERT INTO loan (copy_id, member_id, issued_by_staff_id, checkout_branch_id, return_branch_id, loaned_at, due_at, returned_at)
       VALUES (p3_copy_id('P3-CASH-1'), p3_member_id('cash'), $STAFF_ID, 1, 1, now() - interval '30 days', now() - interval '16 days', now() - interval '2 days');
       INSERT INTO fine (loan_id, amount, reason) SELECT loan_id, 1500, 'overdue' FROM loan WHERE copy_id = p3_copy_id('P3-CASH-1');
       INSERT INTO payment (fine_id, received_by_staff_id, amount, method)
       SELECT f.fine_id, $STAFF_ID, 500, 'cash' FROM fine f JOIN loan l USING (loan_id) WHERE l.copy_id = p3_copy_id('P3-CASH-1');" > /dev/null
}
paid_total() { sql "SELECT COALESCE(sum(p.amount),0) FROM payment p JOIN fine f USING (fine_id) JOIN loan l USING (loan_id) WHERE l.copy_id = p3_copy_id('P3-CASH-1')"; }
show_balance() { show_table "SELECT f.fine_id, f.amount AS fine_amount, COALESCE(sum(p.amount),0) AS paid, f.amount - COALESCE(sum(p.amount),0) AS balance
   FROM fine f JOIN loan l USING (loan_id) LEFT JOIN payment p USING (fine_id) WHERE l.copy_id = p3_copy_id('P3-CASH-1') GROUP BY f.fine_id, f.amount"; }

cashier() {   # $1 = label, $2 = amount, $3 = seconds to print the receipt before COMMIT
cat <<SQL
\\echo $1: cashier $1 takes NGN $2 for the fine (NGN 1,000 is still owed)
BEGIN;
INSERT INTO payment (fine_id, received_by_staff_id, amount, method)
SELECT f.fine_id, $STAFF_ID, $2, 'cash' FROM fine f JOIN loan l USING (loan_id) WHERE l.copy_id = p3_copy_id('P3-CASH-1');
\\if :ERROR
  ROLLBACK;
  \\echo $1: payment REFUSED by the database, NGN $2 handed back to the customer
\\else
  \\echo $1: payment accepted, printing the receipt
  SELECT pg_sleep($3) \\g /dev/null
  COMMIT;
  \\echo $1: COMMIT done
\\endif
SQL
}

hdr "PART 1: a payment check WITHOUT a lock (test database only): both cashiers take NGN 800"
echo "   Replacing the Portfolio 1 guard with a version that does not lock the fine, and is slow (1.5 s)."
sql "ALTER TABLE payment DISABLE TRIGGER trg_guard_payment;
CREATE OR REPLACE FUNCTION guard_payment_nolock() RETURNS trigger LANGUAGE plpgsql AS \$\$
DECLARE f_amount NUMERIC; paid NUMERIC; owed NUMERIC;
BEGIN
  SELECT amount INTO f_amount FROM fine WHERE fine_id = NEW.fine_id;               -- no FOR UPDATE
  SELECT COALESCE(SUM(amount),0) INTO paid FROM payment WHERE fine_id = NEW.fine_id;
  owed := f_amount - paid;
  PERFORM pg_sleep(1.5);                                                           -- slow card terminal
  IF NEW.amount > owed THEN RAISE EXCEPTION 'UPLN-016 payment of NGN % exceeds the outstanding balance of NGN %', NEW.amount, owed; END IF;
  RETURN NEW;
END \$\$;
CREATE TRIGGER trg_guard_nolock BEFORE INSERT ON payment FOR EACH ROW EXECUTE FUNCTION guard_payment_nolock();" > /dev/null
fixture; begin_scenario
session A 0   "$(cashier A 800 0.5)"
session B 0.3 "$(cashier B 800 0.5)"
timeline
echo "   The fine afterwards:"; show_balance; echo
check "SELECT p3_check('$S','C1','without a lock BOTH payments of NGN 800 were accepted',  $(count_of 'payment accepted') = 2)"
check "SELECT p3_check('$S','C2','the fine of NGN 1,500 is OVERPAID: NGN $(paid_total) received (the bug is reproduced)', $(paid_total) > 1500)"
restore_guard
check "SELECT p3_check('$S','C3','the Portfolio 1 guard is switched back on', EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_guard_payment' AND tgenabled = 'O'))"

hdr "PART 2: the real Portfolio 1 guard (locks the fine row): both cashiers take NGN 800"
fixture; begin_scenario
session A 0   "$(cashier A 800 2)"
session B 0.4 "$(cashier B 800 0)"
session OBS 1 "$(observer_sql)"
timeline
echo "   The fine afterwards:"; show_balance; echo
WAITED_MS="$(printf '%s' "$CAPTURED" | grep 'UPLN-016' | head -1 | cut -d'|' -f1 | sed 's/^0*//')"; WAITED_MS="${WAITED_MS:-0}"
check "SELECT p3_check('$S','C4','exactly one payment accepted and one refused with UPLN-016', $(count_of 'payment accepted') = 1 AND $(count_of 'UPLN-016') = 1)"
check "SELECT p3_check('$S','C5','the second cashier WAITED for the first, then was told only NGN 200 was still owed', $WAITED_MS >= 1500 AND $(saw 'balance of NGN 200.00'))"
check "SELECT p3_check('$S','C6','the fine is never overpaid: NGN $(paid_total) received on a NGN 1,500 fine', $(paid_total) <= 1500)"
check "SELECT p3_check('$S','C7','the observer saw the second cashier blocked on the fine row', $(saw 'OBSERVER'))"
sql "SELECT p3_cleanup()" > /dev/null
summary "two cashiers"
