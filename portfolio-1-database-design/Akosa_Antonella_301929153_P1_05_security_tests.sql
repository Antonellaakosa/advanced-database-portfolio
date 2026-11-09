-- =====================================================================
-- Unity Public Library Network (UPLN)  |  MIT 8103  |  Portfolio 1 (extension)
-- File    : 05_security_tests.sql
-- Purpose : Proves the access rules in 04_security_privacy.sql really work.
--           Each test switches to a role (SET ROLE) and then tries something.
--           Nothing is permanently changed: allowed changes are undone.
-- Run     : psql -U library_admin -d upln -f 05_security_tests.sql
-- Requires: 01_schema.sql, 02_sample_data.sql, 04_security_privacy.sql
-- =====================================================================

-- Helper 1: the statement must be REFUSED because of missing permission.
--   SQLSTATE 42501 = insufficient_privilege
-- Helper 2: the statement must be ACCEPTED (we undo it straight afterwards).
CREATE FUNCTION pg_temp.check_security(test_name TEXT, as_role TEXT, sql_text TEXT, must_be_denied BOOLEAN)
RETURNS TABLE (test TEXT, role_used TEXT, expectation TEXT, result TEXT)
LANGUAGE plpgsql AS $$
BEGIN
    test := test_name;
    role_used := as_role;
    expectation := CASE WHEN must_be_denied THEN 'must be refused' ELSE 'must be allowed' END;
    BEGIN
        EXECUTE format('SET LOCAL ROLE %I', as_role);
        EXECUTE sql_text;
        RESET ROLE;
        -- reaching here means the statement was accepted: undo it
        RAISE EXCEPTION 'undo' USING ERRCODE = 'RB001';
    EXCEPTION
        WHEN SQLSTATE 'RB001' THEN
            result := CASE WHEN must_be_denied THEN 'FAIL (it was allowed)' ELSE 'PASS (allowed)' END;
        WHEN insufficient_privilege THEN
            result := CASE WHEN must_be_denied THEN 'PASS (refused)' ELSE 'FAIL (refused)' END;
        WHEN OTHERS THEN
            result := 'FAIL (other error: ' || SQLSTATE || ')';
    END;
    RESET ROLE;
    RETURN NEXT;
END;
$$;

\pset format aligned
\pset border 2

SELECT test, role_used, expectation, result FROM (
    SELECT 1 AS n, * FROM pg_temp.check_security(
        'S01 Librarian can read members',
        'upln_librarian', $$SELECT * FROM member$$, FALSE)
    UNION ALL SELECT 2, * FROM pg_temp.check_security(
        'S02 Librarian cannot delete a loan record',
        'upln_librarian', $$DELETE FROM loan WHERE loan_id = 9$$, TRUE)
    UNION ALL SELECT 3, * FROM pg_temp.check_security(
        'S03 Librarian cannot change a member''s email',
        'upln_librarian', $$UPDATE member SET email = 'x@example.com' WHERE member_id = 1$$, TRUE)
    UNION ALL SELECT 4, * FROM pg_temp.check_security(
        'S04 Librarian can update a member''s phone',
        'upln_librarian', $$UPDATE member SET phone = '+2348019999999' WHERE member_id = 1$$, FALSE)
    UNION ALL SELECT 5, * FROM pg_temp.check_security(
        'S05 Librarian cannot waive a fine',
        'upln_librarian', $$UPDATE fine SET waived = TRUE WHERE fine_id = 3$$, TRUE)
    UNION ALL SELECT 6, * FROM pg_temp.check_security(
        'S06 Branch manager can waive a fine',
        'upln_branch_manager', $$UPDATE fine SET waived = TRUE WHERE fine_id = 3$$, FALSE)
    UNION ALL SELECT 7, * FROM pg_temp.check_security(
        'S07 Analyst cannot read the raw member table',
        'upln_analyst', $$SELECT * FROM member$$, TRUE)
    UNION ALL SELECT 8, * FROM pg_temp.check_security(
        'S08 Analyst cannot read the loan table',
        'upln_analyst', $$SELECT * FROM loan$$, TRUE)
    UNION ALL SELECT 9, * FROM pg_temp.check_security(
        'S09 Analyst can read the masked member view',
        'upln_analyst', $$SELECT * FROM v_member_directory_masked$$, FALSE)
    UNION ALL SELECT 10, * FROM pg_temp.check_security(
        'S10 Analyst can read branch activity totals',
        'upln_analyst', $$SELECT * FROM v_branch_activity$$, FALSE)
    UNION ALL SELECT 11, * FROM pg_temp.check_security(
        'S11 Member app cannot edit loans',
        'upln_member_self', $$UPDATE loan SET returned_at = now() WHERE loan_id = 1$$, TRUE)
    UNION ALL SELECT 12, * FROM pg_temp.check_security(
        'S12 Member app cannot read staff details',
        'upln_member_self', $$SELECT * FROM staff$$, TRUE)
    UNION ALL SELECT 13, * FROM pg_temp.check_security(
        'S13 Member app cannot read fines or payments',
        'upln_member_self', $$SELECT * FROM payment$$, TRUE)
    UNION ALL SELECT 14, * FROM pg_temp.check_security(
        'S14 HQ administrator can insert a publisher',
        'upln_hq_admin', $$INSERT INTO publisher (publisher_name) VALUES ('Test Press')$$, FALSE)
) AS all_tests
ORDER BY n;

-- ---------------------------------------------------------------------
-- Demonstration A: what an analyst sees (personal data is masked).
-- ---------------------------------------------------------------------
\echo
\echo '=== A. Analyst view: masked member directory (no phone, no address) ==='
BEGIN;
SET LOCAL ROLE upln_analyst;
SELECT member_id, first_name, last_initial, email_masked, membership_type, home_city, status
FROM v_member_directory_masked ORDER BY member_id;
COMMIT;

-- ---------------------------------------------------------------------
-- Demonstration B: row-level security. The same query, three different users.
-- ---------------------------------------------------------------------
\echo
\echo '=== B1. Member app, logged in as member 1 (Adaeze): loans visible ==='
BEGIN;
SET LOCAL ROLE upln_member_self;
SET LOCAL app.current_member_id = '1';
SELECT loan_id, member_id, copy_id FROM loan ORDER BY loan_id;
COMMIT;

\echo
\echo '=== B2. Member app, logged in as member 7 (Funke): loans visible ==='
BEGIN;
SET LOCAL ROLE upln_member_self;
SET LOCAL app.current_member_id = '7';
SELECT loan_id, member_id, copy_id FROM loan ORDER BY loan_id;
COMMIT;

\echo
\echo '=== B3. Member app, nobody logged in: rows visible in loan and member (expect 0 and 0) ==='
BEGIN;
SET LOCAL ROLE upln_member_self;
SELECT (SELECT count(*) FROM loan)   AS loans_visible,
       (SELECT count(*) FROM member) AS members_visible;
COMMIT;

\echo
\echo '=== B4. Librarian (staff policy): rows visible in loan (expect all 10) ==='
BEGIN;
SET LOCAL ROLE upln_librarian;
SELECT count(*) AS loans_visible FROM loan;
COMMIT;
