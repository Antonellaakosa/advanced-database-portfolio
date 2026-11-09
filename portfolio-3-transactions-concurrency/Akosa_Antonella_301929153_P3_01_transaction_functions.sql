-- =====================================================================
-- Unity Public Library Network (UPLN)  |  MIT 8103  |  Portfolio 3
-- File    : Akosa_Antonella_301929153_P3_01_transaction_functions.sql
-- Purpose : The "business transactions" used by every test in this folder,
--           plus small helpers for fixtures and for printing PASS/FAIL.
--
--   checkout_copy()   SAFE borrow: locks the copy and the member, checks the
--                     rules, then writes the loan and the copy status together.
--   return_copy()     SAFE return.
--   checkout_unsafe() DEMO ONLY. Same rules, but with NO locks and an optional
--                     pause, so that the race problems can be shown on purpose.
--   p3_cleanup()      Removes the rows the tests create (barcode 'P3-%',
--                     member email 'p3.%'). Never touches the Portfolio 1 sample data.
--   p3_check()        Records and prints one PASS/FAIL line.
-- Run     : (done for you by Akosa_Antonella_301929153_P3_00_setup.sh)
-- =====================================================================
SET client_min_messages = warning;

-- ---------------------------------------------------------------------
-- Results table: one row per check, so the run-all script can summarise.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS p3_results (
    scenario  TEXT        NOT NULL,
    code      TEXT        NOT NULL,
    label     TEXT        NOT NULL,
    ok        BOOLEAN     NOT NULL,
    at        TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

CREATE OR REPLACE FUNCTION p3_check(p_scenario TEXT, p_code TEXT, p_label TEXT, p_ok BOOLEAN)
RETURNS TEXT LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO p3_results (scenario, code, label, ok) VALUES (p_scenario, p_code, p_label, COALESCE(p_ok, FALSE));
    RETURN CASE WHEN COALESCE(p_ok, FALSE) THEN 'PASS  ' ELSE 'FAIL  ' END || p_code || '  ' || p_label;
END $$;

-- ---------------------------------------------------------------------
-- SAFE borrow. Lock order is always: copy first, then member. Using one
-- fixed order is also what keeps two borrows from deadlocking each other.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION checkout_copy(p_copy INTEGER, p_member INTEGER, p_staff INTEGER)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
    c_status  TEXT;
    c_branch  INTEGER;
    m_status  TEXT;
    m_max     INTEGER;
    m_days    INTEGER;
    m_active  INTEGER;
    new_loan  INTEGER;
BEGIN
    SELECT status, branch_id INTO c_status, c_branch
    FROM copy WHERE copy_id = p_copy FOR UPDATE;               -- lock the copy
    IF NOT FOUND THEN
        RAISE EXCEPTION 'UPLN-020 copy % does not exist', p_copy;
    END IF;
    IF c_status <> 'available' THEN
        RAISE EXCEPTION 'UPLN-021 copy % is not available (status: %)', p_copy, c_status
              USING ERRCODE = 'check_violation';
    END IF;

    SELECT m.status, t.max_loans, t.loan_days INTO m_status, m_max, m_days
    FROM member m JOIN membership_type t ON t.type_id = m.type_id
    WHERE m.member_id = p_member FOR UPDATE OF m;              -- lock the member
    IF NOT FOUND OR m_status <> 'active' THEN
        RAISE EXCEPTION 'UPLN-022 member % is not an active member', p_member
              USING ERRCODE = 'check_violation';
    END IF;

    SELECT count(*) INTO m_active FROM loan WHERE member_id = p_member AND returned_at IS NULL;
    IF m_active >= m_max THEN
        RAISE EXCEPTION 'UPLN-023 member % already has % of % allowed loans', p_member, m_active, m_max
              USING ERRCODE = 'check_violation';
    END IF;

    INSERT INTO loan (copy_id, member_id, issued_by_staff_id, checkout_branch_id, due_at)
    VALUES (p_copy, p_member, p_staff, c_branch, now() + make_interval(days => m_days))
    RETURNING loan_id INTO new_loan;
    UPDATE copy SET status = 'on_loan' WHERE copy_id = p_copy;  -- same transaction: all or nothing
    RETURN new_loan;
END $$;

-- ---------------------------------------------------------------------
-- SAFE return.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION return_copy(p_copy INTEGER)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
    c_branch INTEGER;
    l_id     INTEGER;
BEGIN
    SELECT branch_id INTO c_branch FROM copy WHERE copy_id = p_copy FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'UPLN-020 copy % does not exist', p_copy;
    END IF;
    UPDATE loan SET returned_at = now(), return_branch_id = c_branch
    WHERE copy_id = p_copy AND returned_at IS NULL
    RETURNING loan_id INTO l_id;
    IF l_id IS NULL THEN
        RAISE EXCEPTION 'UPLN-024 copy % is not on loan', p_copy USING ERRCODE = 'check_violation';
    END IF;
    UPDATE copy SET status = 'available' WHERE copy_id = p_copy;
    RETURN l_id;
END $$;

-- ---------------------------------------------------------------------
-- DEMO ONLY: same rules, NO locks. p_pause stretches the gap between
-- "check" and "write" so the race is easy to see. Never use this in real code.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION checkout_unsafe(p_copy INTEGER, p_member INTEGER, p_staff INTEGER, p_pause NUMERIC DEFAULT 0)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
    c_status TEXT; c_branch INTEGER; m_max INTEGER; m_days INTEGER; m_active INTEGER; new_loan INTEGER;
BEGIN
    SELECT status, branch_id INTO c_status, c_branch FROM copy WHERE copy_id = p_copy;        -- plain read, no lock
    IF c_status <> 'available' THEN
        RAISE EXCEPTION 'UPLN-021 copy % is not available (status: %)', p_copy, c_status USING ERRCODE = 'check_violation';
    END IF;
    SELECT t.max_loans, t.loan_days INTO m_max, m_days
    FROM member m JOIN membership_type t ON t.type_id = m.type_id WHERE m.member_id = p_member;
    SELECT count(*) INTO m_active FROM loan WHERE member_id = p_member AND returned_at IS NULL;
    IF m_active >= m_max THEN
        RAISE EXCEPTION 'UPLN-023 member % already has % of % allowed loans', p_member, m_active, m_max USING ERRCODE = 'check_violation';
    END IF;
    PERFORM pg_sleep(p_pause);                                                                 -- the gap where the race happens
    INSERT INTO loan (copy_id, member_id, issued_by_staff_id, checkout_branch_id, due_at)
    VALUES (p_copy, p_member, p_staff, c_branch, now() + make_interval(days => m_days))
    RETURNING loan_id INTO new_loan;
    UPDATE copy SET status = 'on_loan' WHERE copy_id = p_copy;
    RETURN new_loan;
END $$;

-- ---------------------------------------------------------------------
-- Fixture helper: removes only rows created by these tests.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION p3_cleanup() RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM payment WHERE fine_id IN (SELECT f.fine_id FROM fine f JOIN loan l USING (loan_id)
                                          WHERE l.member_id IN (SELECT member_id FROM member WHERE email LIKE 'p3.%'));
    DELETE FROM fine    WHERE loan_id IN (SELECT loan_id FROM loan
                                          WHERE member_id IN (SELECT member_id FROM member WHERE email LIKE 'p3.%')
                                             OR copy_id IN (SELECT copy_id FROM copy WHERE barcode LIKE 'P3-%'));
    DELETE FROM loan    WHERE member_id IN (SELECT member_id FROM member WHERE email LIKE 'p3.%')
                           OR copy_id IN (SELECT copy_id FROM copy WHERE barcode LIKE 'P3-%');
    DELETE FROM copy    WHERE barcode LIKE 'P3-%';
    DELETE FROM member  WHERE email LIKE 'p3.%';
END $$;

-- Convenience: create a test member (type 1 = Standard, max 5 loans) and a test copy.
CREATE OR REPLACE FUNCTION p3_member(p_tag TEXT) RETURNS INTEGER LANGUAGE sql AS $$
    INSERT INTO member (first_name, last_name, email, type_id, home_branch_id)
    VALUES ('P3', initcap(p_tag), 'p3.' || p_tag || '@example.com', 1, 1) RETURNING member_id;
$$;

CREATE OR REPLACE FUNCTION p3_copy(p_barcode TEXT, p_status TEXT DEFAULT 'available') RETURNS INTEGER LANGUAGE sql AS $$
    INSERT INTO copy (title_id, branch_id, barcode, status) VALUES (1, 1, p_barcode, p_status) RETURNING copy_id;
$$;

CREATE OR REPLACE FUNCTION p3_copy_id(p_barcode TEXT) RETURNS INTEGER LANGUAGE sql STABLE AS $$
    SELECT copy_id FROM copy WHERE barcode = p_barcode;
$$;
CREATE OR REPLACE FUNCTION p3_member_id(p_tag TEXT) RETURNS INTEGER LANGUAGE sql STABLE AS $$
    SELECT member_id FROM member WHERE email = 'p3.' || p_tag || '@example.com';
$$;
