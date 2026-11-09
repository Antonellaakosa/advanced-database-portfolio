-- =====================================================================
-- Unity Public Library Network (UPLN)  |  MIT 8103  |  Portfolio 1
-- File    : Akosa_Antonella_301929153_P1_03_constraint_tests.sql
-- Purpose : Proves that keys and constraints really protect the data.
--           Each test deliberately tries to break one rule. A test PASSES
--           when PostgreSQL REJECTS the bad statement with the expected
--           error type. Nothing is changed in the database.
-- Run     : psql -U library_admin -d upln -f Akosa_Antonella_301929153_P1_03_constraint_tests.sql
-- Requires: Akosa_Antonella_301929153_P1_01_schema.sql and Akosa_Antonella_301929153_P1_02_sample_data.sql have been run.
-- =====================================================================

-- A small temporary helper (it disappears when the session ends).
-- It runs one statement and checks that it fails with the expected SQLSTATE:
--   23505 = unique_violation      23503 = foreign_key_violation
--   23514 = check_violation       23502 = not_null_violation
CREATE FUNCTION pg_temp.expect_error(test_name TEXT, bad_sql TEXT, expected_state TEXT)
RETURNS TABLE (test TEXT, expected TEXT, result TEXT, database_message TEXT)
LANGUAGE plpgsql AS $$
BEGIN
    test := test_name;
    expected := expected_state;
    BEGIN
        EXECUTE bad_sql;
        result := 'FAIL (statement was accepted)';
        database_message := '-';
    EXCEPTION WHEN OTHERS THEN
        IF SQLSTATE = expected_state THEN
            result := 'PASS (rejected)';
        ELSE
            result := 'FAIL (wrong error ' || SQLSTATE || ')';
        END IF;
        -- keep the database's message short and readable
        database_message := left(split_part(SQLERRM, E'\n', 1), 75);
    END;
    RETURN NEXT;
END;
$$;

\pset format aligned
\pset border 2

SELECT test, expected, result, database_message FROM (
  -- ---- Keys and uniqueness -------------------------------------------
  SELECT 1 AS n, * FROM pg_temp.expect_error(
    'T01 Second headquarters is refused',
    $$INSERT INTO branch (branch_name, city, state, address, is_headquarters)
      VALUES ('Fake HQ', 'Jos', 'Plateau', '1 Test Road', TRUE)$$, '23505')
  UNION ALL SELECT 2, * FROM pg_temp.expect_error(
    'T02 Duplicate member email is refused',
    $$INSERT INTO member (first_name, last_name, email, type_id, home_branch_id)
      VALUES ('Dup', 'Licate', 'adaeze.okafor@example.com', 1, 1)$$, '23505')
  UNION ALL SELECT 3, * FROM pg_temp.expect_error(
    'T03 Duplicate barcode is refused',
    $$INSERT INTO copy (title_id, branch_id, barcode) VALUES (1, 1, 'UPLN-000001')$$, '23505')
  UNION ALL SELECT 4, * FROM pg_temp.expect_error(
    'T04 Duplicate ISBN is refused',
    $$INSERT INTO title (isbn, title_name, category_id)
      VALUES ('9789990000011', 'Copycat', 1)$$, '23505')
  UNION ALL SELECT 5, * FROM pg_temp.expect_error(
    'T05 Same author twice on one title is refused (composite PK)',
    $$INSERT INTO title_author (title_id, author_id) VALUES (1, 1)$$, '23505')
  -- ---- Business rules -------------------------------------------------
  UNION ALL SELECT 6, * FROM pg_temp.expect_error(
    'T06 Double-borrowing an already-loaned copy is refused',
    $$INSERT INTO loan (copy_id, member_id, issued_by_staff_id, checkout_branch_id, due_at)
      VALUES (2, 3, 4, 2, now() + interval '14 days')$$, '23505')
  UNION ALL SELECT 7, * FROM pg_temp.expect_error(
    'T07 Second open reservation, same member and title, is refused',
    $$INSERT INTO reservation (title_id, member_id, pickup_branch_id)
      VALUES (2, 6, 1)$$, '23505')
  UNION ALL SELECT 8, * FROM pg_temp.expect_error(
    'T08 Copy transfer to the same branch is refused',
    $$INSERT INTO copy_transfer (copy_id, from_branch_id, to_branch_id, requested_by_staff_id)
      VALUES (5, 2, 2, 3)$$, '23514')
  -- ---- CHECK constraints ----------------------------------------------
  UNION ALL SELECT 9, * FROM pg_temp.expect_error(
    'T09 Loan due before it was issued is refused',
    $$INSERT INTO loan (copy_id, member_id, issued_by_staff_id, checkout_branch_id, loaned_at, due_at)
      VALUES (7, 3, 2, 1, now(), now() - interval '1 day')$$, '23514')
  UNION ALL SELECT 10, * FROM pg_temp.expect_error(
    'T10 Returned loan without a return branch is refused',
    $$INSERT INTO loan (copy_id, member_id, issued_by_staff_id, checkout_branch_id,
                        loaned_at, due_at, returned_at)
      VALUES (7, 3, 2, 1, now() - interval '5 days', now() + interval '9 days', now())$$, '23514')
  UNION ALL SELECT 11, * FROM pg_temp.expect_error(
    'T11 Negative fine amount is refused',
    $$INSERT INTO fine (loan_id, amount, reason) VALUES (9, -100, 'overdue')$$, '23514')
  UNION ALL SELECT 12, * FROM pg_temp.expect_error(
    'T12 Invalid copy status value is refused',
    $$UPDATE copy SET status = 'borrowed-ish' WHERE copy_id = 1$$, '23514')
  UNION ALL SELECT 13, * FROM pg_temp.expect_error(
    'T13 Malformed ISBN is refused',
    $$INSERT INTO title (isbn, title_name, category_id)
      VALUES ('12345', 'Bad ISBN', 1)$$, '23514')
  UNION ALL SELECT 14, * FROM pg_temp.expect_error(
    'T14 Malformed email address is refused',
    $$INSERT INTO member (first_name, last_name, email, type_id, home_branch_id)
      VALUES ('No', 'At', 'not-an-email', 1, 1)$$, '23514')
  UNION ALL SELECT 15, * FROM pg_temp.expect_error(
    'T15 Fourth renewal is refused (max 2)',
    $$UPDATE loan SET renewals = 3 WHERE loan_id = 1$$, '23514')
  -- ---- Foreign keys and NOT NULL ----------------------------------------
  UNION ALL SELECT 16, * FROM pg_temp.expect_error(
    'T16 Loan for a member that does not exist is refused',
    $$INSERT INTO loan (copy_id, member_id, issued_by_staff_id, checkout_branch_id, due_at)
      VALUES (7, 9999, 2, 1, now() + interval '14 days')$$, '23503')
  UNION ALL SELECT 17, * FROM pg_temp.expect_error(
    'T17 Deleting a branch that still holds copies is refused',
    $$DELETE FROM branch WHERE branch_id = 2$$, '23503')
  UNION ALL SELECT 18, * FROM pg_temp.expect_error(
    'T18 Member without a last name is refused',
    $$INSERT INTO member (first_name, last_name, email, type_id, home_branch_id)
      VALUES ('Only', NULL, 'only.first@example.com', 1, 1)$$, '23502')
) AS all_tests
ORDER BY n;

-- ---------------------------------------------------------------------
-- Positive control: a VALID loan must be accepted (then we undo it).
-- This shows the constraints block only bad data, not good data.
-- Copy 7 is available at HQ; member 6 (Standard) borrows it for 14 days.
-- ---------------------------------------------------------------------
BEGIN;
INSERT INTO loan (copy_id, member_id, issued_by_staff_id, checkout_branch_id, due_at)
VALUES (7, 6, 2, 1, now() + interval '14 days')
RETURNING loan_id, copy_id, member_id, due_at > loaned_at AS due_after_loan;
ROLLBACK;   -- undo, so the sample data stays unchanged
