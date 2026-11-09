-- =====================================================================
-- Unity Public Library Network (UPLN)  |  MIT 8103  |  Portfolio 1 (security)
-- File    : Akosa_Antonella_301929153_P1_07_audit_tests.sql
-- Purpose : Proves that (a) changes are logged with the right facts,
--           (b) personal data is redacted in the log, (c) nobody can alter
--           or forge the log, and (d) only authorised roles can read it.
--           Everything runs in one transaction that is ROLLED BACK at the
--           end, so your data and your audit log are left untouched.
-- Run     : psql -U library_admin -d upln -f Akosa_Antonella_301929153_P1_07_audit_tests.sql
-- Requires: 01 .. 06 (and 08 if you want the payment guard active)
-- =====================================================================
\pset format aligned
\pset border 2
BEGIN;

CREATE TEMP TABLE res (n SERIAL, test TEXT, expectation TEXT, result TEXT);

-- Run a statement as a given role. Returns 'ok' or the error code (SQLSTATE).
CREATE FUNCTION pg_temp.try_as(as_role TEXT, sql_text TEXT) RETURNS TEXT LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE format('SET LOCAL ROLE %I', as_role);
        EXECUTE sql_text;
        RESET ROLE;
        RETURN 'ok';
    EXCEPTION WHEN OTHERS THEN
        RESET ROLE;
        RETURN SQLSTATE;
    END;
END $$;

CREATE FUNCTION pg_temp.rec(t TEXT, expectation TEXT, passed BOOLEAN, detail TEXT DEFAULT '') RETURNS VOID
LANGUAGE sql AS $$
    INSERT INTO res (test, expectation, result)
    VALUES (t, expectation, CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END || CASE WHEN detail = '' THEN '' ELSE ' (' || detail || ')' END);
$$;

DO $$
DECLARE
    base BIGINT := COALESCE((SELECT max(audit_id) FROM audit_log), 0);
    a    audit_log%ROWTYPE;
    n_before BIGINT;
    code TEXT;
BEGIN
    -- ===== Part 1: changes are logged ====================================
    PERFORM set_config('app.staff_id', '3', true);       -- the app says: staff member 3 is at the desk

    -- A01: librarian changes a member's phone number
    code := pg_temp.try_as('upln_librarian', $q$UPDATE member SET phone = '+2348099999999' WHERE member_id = 1$q$);
    SELECT * INTO a FROM audit_log WHERE audit_id > base AND table_name = 'member' AND operation = 'UPDATE' ORDER BY audit_id DESC LIMIT 1;
    PERFORM pg_temp.rec('A01 Phone change by a librarian is logged', 'one UPDATE row on member 1 by upln_librarian',
        code = 'ok' AND a.row_pk = '1' AND a.effective_role = 'upln_librarian' AND a.changed_columns = ARRAY['phone'],
        format('role=%s, changed=%s', a.effective_role, a.changed_columns));
    PERFORM pg_temp.rec('A02 The application''s staff id is recorded', 'app_staff_id = 3', a.app_staff_id = 3, 'app_staff_id=' || COALESCE(a.app_staff_id::text, 'null'));
    PERFORM pg_temp.rec('A03 Personal data is redacted in the log', 'phone shown as [REDACTED], not the number',
        a.new_data ->> 'phone' = '[REDACTED]' AND a.old_data ->> 'phone' = '[REDACTED]',
        'new phone in log = ' || (a.new_data ->> 'phone'));

    -- A04: manager waives a fine
    code := pg_temp.try_as('upln_branch_manager', $q$UPDATE fine SET waived = TRUE WHERE fine_id = 3$q$);
    SELECT * INTO a FROM audit_log WHERE audit_id > base AND table_name = 'fine' AND operation = 'UPDATE' ORDER BY audit_id DESC LIMIT 1;
    PERFORM pg_temp.rec('A04 Fine waiver is logged with before and after', 'waived false -> true, by upln_branch_manager',
        code = 'ok' AND a.effective_role = 'upln_branch_manager' AND a.changed_columns = ARRAY['waived']
        AND a.old_data ->> 'waived' = 'false' AND a.new_data ->> 'waived' = 'true',
        format('old=%s new=%s', a.old_data ->> 'waived', a.new_data ->> 'waived'));

    -- A05: librarian records a payment on fine 2
    code := pg_temp.try_as('upln_librarian',
        $q$INSERT INTO payment (fine_id, received_by_staff_id, amount, method) VALUES (2, 3, 100.00, 'cash')$q$);
    SELECT * INTO a FROM audit_log WHERE audit_id > base AND table_name = 'payment' AND operation = 'INSERT' ORDER BY audit_id DESC LIMIT 1;
    PERFORM pg_temp.rec('A05 A new payment is logged', 'INSERT row on payment with amount 100.00',
        code = 'ok' AND (a.new_data ->> 'amount')::numeric = 100.00, 'amount=' || COALESCE(a.new_data ->> 'amount', 'none'));

    -- A06: HQ admin deletes a payment
    code := pg_temp.try_as('upln_hq_admin', $q$DELETE FROM payment WHERE payment_id = 1$q$);
    SELECT * INTO a FROM audit_log WHERE audit_id > base AND table_name = 'payment' AND operation = 'DELETE' ORDER BY audit_id DESC LIMIT 1;
    PERFORM pg_temp.rec('A06 A deletion keeps a copy of the deleted row', 'DELETE row with old_data',
        code = 'ok' AND a.old_data IS NOT NULL AND a.new_data IS NULL AND a.row_pk = '1', 'old amount=' || COALESCE(a.old_data ->> 'amount', 'none'));

    -- A07: a new member is logged, phone redacted
    code := pg_temp.try_as('upln_librarian',
        $q$INSERT INTO member (first_name, last_name, email, phone, type_id, home_branch_id) VALUES ('Test', 'Person', 'test.person@example.com', '+2348000000000', 1, 1)$q$);
    SELECT * INTO a FROM audit_log WHERE audit_id > base AND table_name = 'member' AND operation = 'INSERT' ORDER BY audit_id DESC LIMIT 1;
    PERFORM pg_temp.rec('A07 A new member is logged without the phone number', 'INSERT row; phone [REDACTED]',
        code = 'ok' AND a.new_data ->> 'phone' = '[REDACTED]' AND a.new_data ->> 'email' = 'test.person@example.com', 'phone in log=' || COALESCE(a.new_data ->> 'phone', 'none'));

    -- A08: a failed change leaves no trace (the log is part of the same transaction)
    SELECT count(*) INTO n_before FROM audit_log;
    BEGIN
        UPDATE member SET status = 'suspended' WHERE member_id = 2;
        RAISE EXCEPTION 'simulated failure' USING ERRCODE = 'RB001';
    EXCEPTION WHEN SQLSTATE 'RB001' THEN NULL;
    END;
    PERFORM pg_temp.rec('A08 A rolled-back change leaves no log entry', 'log row count unchanged',
        (SELECT count(*) FROM audit_log) = n_before, 'rows before=' || n_before || ', after=' || (SELECT count(*) FROM audit_log));

    -- ===== Part 2: the log cannot be altered or forged ===================
    -- Even the administrator who owns the table is stopped by the triggers.
    BEGIN UPDATE audit_log SET table_name = 'x' WHERE audit_id > base; code := 'ok'; EXCEPTION WHEN OTHERS THEN code := SQLSTATE; END;
    PERFORM pg_temp.rec('A09 Administrator cannot UPDATE the log', 'refused (42501)', code = '42501', 'code=' || code);
    BEGIN DELETE FROM audit_log WHERE audit_id > base; code := 'ok'; EXCEPTION WHEN OTHERS THEN code := SQLSTATE; END;
    PERFORM pg_temp.rec('A10 Administrator cannot DELETE from the log', 'refused (42501)', code = '42501', 'code=' || code);
    BEGIN TRUNCATE audit_log; code := 'ok'; EXCEPTION WHEN OTHERS THEN code := SQLSTATE; END;
    PERFORM pg_temp.rec('A11 Administrator cannot TRUNCATE the log', 'refused (42501)', code = '42501', 'code=' || code);

    code := pg_temp.try_as('upln_hq_admin', $q$DELETE FROM audit_log$q$);
    PERFORM pg_temp.rec('A12 HQ administrator role cannot DELETE from the log', 'refused (42501)', code = '42501', 'code=' || code);
    code := pg_temp.try_as('upln_hq_admin',
        $q$INSERT INTO audit_log (table_name, operation, row_pk) VALUES ('member', 'DELETE', '1')$q$);
    PERFORM pg_temp.rec('A13 Nobody can forge an entry directly', 'refused (42501)', code = '42501', 'code=' || code);

    -- ===== Part 3: who may read the log ==================================
    code := pg_temp.try_as('upln_librarian',       $q$SELECT * FROM audit_log$q$);
    PERFORM pg_temp.rec('A14 Librarian cannot read the log', 'refused (42501)', code = '42501', 'code=' || code);
    code := pg_temp.try_as('upln_analyst',         $q$SELECT * FROM audit_log$q$);
    PERFORM pg_temp.rec('A15 Analyst cannot read the log', 'refused (42501)', code = '42501', 'code=' || code);
    code := pg_temp.try_as('upln_member_self',     $q$SELECT * FROM audit_log$q$);
    PERFORM pg_temp.rec('A16 Member app cannot read the log', 'refused (42501)', code = '42501', 'code=' || code);
    code := pg_temp.try_as('upln_auditor',         $q$SELECT * FROM v_audit_trail$q$);
    PERFORM pg_temp.rec('A17 Auditor can read the audit trail', 'allowed', code = 'ok', 'code=' || code);
    code := pg_temp.try_as('upln_hq_admin',        $q$SELECT * FROM audit_log$q$);
    PERFORM pg_temp.rec('A18 HQ administrator can read the log', 'allowed', code = 'ok', 'code=' || code);
END $$;

SELECT n AS "#", test, expectation, result FROM res ORDER BY n;

\echo
\echo '=== What an auditor sees (the entries created by this test run) ==='
SELECT audit_id AS id, to_char(changed_at, 'HH24:MI:SS') AS at, effective_role AS role, app_staff_id AS staff,
       table_name AS "table", operation AS op, row_pk AS pk, changed_columns AS changed
FROM audit_log ORDER BY audit_id;

ROLLBACK;
\echo
\echo 'Test transaction rolled back: your data and audit log are unchanged.'
