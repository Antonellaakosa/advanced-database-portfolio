-- =====================================================================
-- Unity Public Library Network (UPLN)  |  MIT 8103  |  Portfolio 3
-- File    : 02_acid_basics.sql
-- Purpose : ACID, one property at a time, on the real borrow operation.
--           A  Atomicity   - a borrow is two writes (loan + copy status): all or nothing
--           B  Atomicity   - the same failure, protected by a transaction
--           C  Savepoint   - undo one part of a transaction, keep the rest
--           D  Consistency - the database refuses data that breaks the rules
--           E  Durability  - a COMMIT is written to the write-ahead log first
-- Run     : docker compose exec -T postgres psql -U library_admin -d upln_tx < portfolio-3-transactions-concurrency/02_acid_basics.sql
-- Requires: 00_setup.sh
-- =====================================================================
\set ON_ERROR_STOP off
\pset pager off
\pset footer off
SET client_min_messages = warning;

SELECT p3_cleanup() \g /dev/null
DELETE FROM p3_results WHERE scenario = 'acid';
SELECT p3_member('atom') AS member_id \gset
SELECT p3_copy('P3-ACID-1') AS copy_a \gset
SELECT p3_copy('P3-ACID-2') AS copy_b \gset

\echo
\echo ====================================================================
\echo  A. WITHOUT a transaction: a borrow is two writes, and one can fail
\echo ====================================================================
\echo Step 1 (saved immediately, because there is no transaction): record the loan
INSERT INTO loan (copy_id, member_id, issued_by_staff_id, checkout_branch_id, due_at)
VALUES (:copy_a, :member_id, 2, 1, now() + interval '14 days');
\echo Step 2: mark the copy as on_loan, but suppose the status value is wrong ("borrowed" is not an allowed status):
UPDATE copy SET status = 'borrowed' WHERE copy_id = :copy_a;
\echo Result: the loan exists, yet the copy still says "available". The data now disagrees with itself.
SELECT c.barcode, c.status AS copy_status,
       (SELECT count(*) FROM loan l WHERE l.copy_id = c.copy_id AND l.returned_at IS NULL) AS active_loans
FROM copy c WHERE c.copy_id = :copy_a;
\t on
SELECT p3_check('acid', 'A1', 'no transaction: failure leaves a half-finished borrow (loan exists, copy says available)',
       (SELECT status FROM copy WHERE copy_id = :copy_a) = 'available'
       AND EXISTS (SELECT 1 FROM loan WHERE copy_id = :copy_a AND returned_at IS NULL));
\t off
DELETE FROM loan WHERE copy_id = :copy_a;     -- clean up the damage before the next part

\echo
\echo ====================================================================
\echo  B. WITH a transaction: the same failure, but nothing is left behind
\echo ====================================================================
BEGIN;
INSERT INTO loan (copy_id, member_id, issued_by_staff_id, checkout_branch_id, due_at)
VALUES (:copy_a, :member_id, 2, 1, now() + interval '14 days');
UPDATE copy SET status = 'borrowed' WHERE copy_id = :copy_a;
ROLLBACK;
\echo After ROLLBACK the loan is gone too, so the data is consistent:
SELECT c.barcode, c.status AS copy_status,
       (SELECT count(*) FROM loan l WHERE l.copy_id = c.copy_id AND l.returned_at IS NULL) AS active_loans
FROM copy c WHERE c.copy_id = :copy_a;
\t on
SELECT p3_check('acid', 'B1', 'transaction: after the failure and ROLLBACK there is no loan and the copy is still available',
       (SELECT status FROM copy WHERE copy_id = :copy_a) = 'available'
       AND NOT EXISTS (SELECT 1 FROM loan WHERE copy_id = :copy_a));
\t off

\echo
\echo  Now the real borrow function, which does both writes in one transaction:
BEGIN;
SELECT checkout_copy(:copy_a, :member_id, 2) AS new_loan_id;
COMMIT;
SELECT c.barcode, c.status AS copy_status,
       (SELECT count(*) FROM loan l WHERE l.copy_id = c.copy_id AND l.returned_at IS NULL) AS active_loans
FROM copy c WHERE c.copy_id = :copy_a;
\t on
SELECT p3_check('acid', 'B2', 'checkout_copy(): after COMMIT the loan exists and the copy is on_loan',
       (SELECT status FROM copy WHERE copy_id = :copy_a) = 'on_loan'
       AND (SELECT count(*) FROM loan WHERE copy_id = :copy_a AND returned_at IS NULL) = 1);
\t off

\echo
\echo ====================================================================
\echo  C. SAVEPOINT: undo one step, keep the rest of the transaction
\echo ====================================================================
\echo A member borrows copy B, then changes their mind about a second copy within the same visit:
SELECT p3_copy('P3-ACID-3') AS copy_c \gset
BEGIN;
SELECT checkout_copy(:copy_b, :member_id, 2) AS loan_for_copy_b;
SAVEPOINT before_second_book;
SELECT checkout_copy(:copy_c, :member_id, 2) AS loan_for_copy_c;
ROLLBACK TO SAVEPOINT before_second_book;
COMMIT;
SELECT c.barcode, c.status AS copy_status FROM copy c WHERE c.copy_id IN (:copy_b, :copy_c) ORDER BY c.copy_id;
\t on
SELECT p3_check('acid', 'C1', 'savepoint: first borrow kept, second borrow undone',
       (SELECT status FROM copy WHERE copy_id = :copy_b) = 'on_loan'
       AND (SELECT status FROM copy WHERE copy_id = :copy_c) = 'available'
       AND NOT EXISTS (SELECT 1 FROM loan WHERE copy_id = :copy_c));
\t off

\echo
\echo ====================================================================
\echo  D. CONSISTENCY: the database itself refuses data that breaks a rule
\echo ====================================================================
\echo Try 1. Borrowing a copy that is already on loan (rule UPLN-021):
SELECT checkout_copy(:copy_a, :member_id, 2);
\echo Try 2. A loan that is due BEFORE it was issued (CHECK constraint from Portfolio 1):
INSERT INTO loan (copy_id, member_id, issued_by_staff_id, checkout_branch_id, loaned_at, due_at)
VALUES (:copy_c, :member_id, 2, 1, now(), now() - interval '1 day');
\echo Try 3. A second active loan on the same copy (partial unique index from Portfolio 1):
INSERT INTO loan (copy_id, member_id, issued_by_staff_id, checkout_branch_id, due_at)
VALUES (:copy_a, :member_id, 2, 1, now() + interval '14 days');
\t on
SELECT p3_check('acid', 'D1', 'consistency: no copy has two active loans, and no loan is due before it was issued',
       NOT EXISTS (SELECT 1 FROM loan WHERE returned_at IS NULL GROUP BY copy_id HAVING count(*) > 1)
       AND NOT EXISTS (SELECT 1 FROM loan WHERE due_at <= loaned_at));
\t off

\echo
\echo ====================================================================
\echo  E. DURABILITY: a COMMIT is written to the write-ahead log (WAL) first
\echo ====================================================================
SELECT name, setting FROM pg_settings WHERE name IN ('fsync', 'synchronous_commit', 'wal_level') ORDER BY name;
SELECT pg_current_wal_lsn() AS lsn_before \gset
SELECT 'WAL position before the commit: ' || :'lsn_before' AS info;
BEGIN;
SELECT return_copy(:copy_a) AS returned_loan_id;
COMMIT;
SELECT pg_current_wal_lsn() AS lsn_after \gset
SELECT 'WAL position after the commit : ' || :'lsn_after' || '   (' || pg_wal_lsn_diff(:'lsn_after', :'lsn_before') || ' bytes written)' AS info;
\t on
SELECT p3_check('acid', 'E1', 'durability: the commit wrote to the WAL and the change is visible to a new query',
       pg_wal_lsn_diff(:'lsn_after', :'lsn_before') > 0
       AND (SELECT status FROM copy WHERE copy_id = :copy_a) = 'available');
\t off

\echo
\echo ====================================================================
\echo  RESULT
\echo ====================================================================
SELECT scenario, count(*) FILTER (WHERE ok) AS pass, count(*) FILTER (WHERE NOT ok) AS fail
FROM p3_results WHERE scenario = 'acid' GROUP BY scenario;
SELECT p3_cleanup() \g /dev/null
