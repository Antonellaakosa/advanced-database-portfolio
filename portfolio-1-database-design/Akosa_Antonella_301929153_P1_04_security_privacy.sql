-- =====================================================================
-- Unity Public Library Network (UPLN)  |  MIT 8103  |  Portfolio 1 (extension)
-- File    : Akosa_Antonella_301929153_P1_04_security_privacy.sql
-- Purpose : Access control and privacy protections:
--             1. Roles with least privilege (who may do what)
--             2. Column-level permissions (who may change which fields)
--             3. Privacy-safe views (masking personal data)
--             4. Row-level security (members see only their own records)
-- Run     : psql -U library_admin -d upln -f Akosa_Antonella_301929153_P1_04_security_privacy.sql
-- Requires: Akosa_Antonella_301929153_P1_01_schema.sql and Akosa_Antonella_301929153_P1_02_sample_data.sql have been run.
-- Note    : Safe to re-run. Roles are created only if they do not exist, and
--           permissions are re-applied each time.
-- Note    : These are GROUP roles (NOLOGIN). No passwords appear in this file
--           on purpose. In a real deployment, individual login users would be
--           created with strong secrets kept OUTSIDE the repository (for example
--           in an environment variable or a secrets manager) and added to the
--           group that matches their job.
-- =====================================================================

SET client_min_messages = warning;

-- ---------------------------------------------------------------------
-- 1. Roles (one per kind of user)
-- ---------------------------------------------------------------------
DO $$
DECLARE r TEXT;
BEGIN
    FOREACH r IN ARRAY ARRAY['upln_librarian', 'upln_branch_manager', 'upln_hq_admin',
                             'upln_analyst', 'upln_member_self']
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('CREATE ROLE %I NOLOGIN', r);
        END IF;
    END LOOP;
END $$;

-- A branch manager can do everything a librarian can, plus more.
GRANT upln_librarian TO upln_branch_manager;

-- ---------------------------------------------------------------------
-- 2. Start from "no access" (principle of least privilege)
-- ---------------------------------------------------------------------
REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;

REVOKE ALL ON ALL TABLES IN SCHEMA public
    FROM upln_librarian, upln_branch_manager, upln_hq_admin, upln_analyst, upln_member_self;

-- ---------------------------------------------------------------------
-- 3. Privacy-safe views
-- ---------------------------------------------------------------------

-- Hides contact details: phone and address are left out, the last name is
-- reduced to an initial, and the email is partly masked (ad***@example.com).
CREATE OR REPLACE VIEW v_member_directory_masked AS
SELECT m.member_id,
       m.first_name,
       left(m.last_name, 1) || '.'                          AS last_initial,
       left(m.email, 2) || '***@' || split_part(m.email, '@', 2) AS email_masked,
       mt.type_name                                         AS membership_type,
       b.city                                               AS home_city,
       m.joined_date,
       m.status
FROM member m
JOIN membership_type mt ON mt.type_id = m.type_id
JOIN branch b           ON b.branch_id = m.home_branch_id;

-- Aggregated figures only: no individual member appears in this view.
CREATE OR REPLACE VIEW v_branch_activity AS
SELECT b.branch_name,
       b.city,
       COUNT(l.loan_id)                                          AS total_loans,
       COUNT(l.loan_id) FILTER (WHERE l.returned_at IS NULL)     AS active_loans,
       COUNT(l.loan_id) FILTER (WHERE l.returned_at IS NULL
                                  AND l.due_at < now())          AS overdue_loans
FROM branch b
LEFT JOIN loan l ON l.checkout_branch_id = b.branch_id
GROUP BY b.branch_id, b.branch_name, b.city;

-- ---------------------------------------------------------------------
-- 4. Table and column permissions
-- ---------------------------------------------------------------------

-- Librarians: read everything needed for the front desk, and make only the
-- changes their job requires. They can NEVER delete rows.
GRANT USAGE ON SCHEMA public TO upln_librarian, upln_branch_manager, upln_hq_admin,
                                upln_analyst, upln_member_self;
GRANT SELECT ON branch, membership_type, member, staff, publisher, author, category,
                title, title_author, copy, loan, reservation, copy_transfer,
                fine, payment, v_fine_balance
      TO upln_librarian;
GRANT INSERT ON member, loan, reservation, payment TO upln_librarian;
GRANT UPDATE (phone, address, status)                        ON member      TO upln_librarian;  -- not email or name
GRANT UPDATE (status, branch_id)                             ON copy        TO upln_librarian;
GRANT UPDATE (return_branch_id, returned_at, due_at, renewals) ON loan      TO upln_librarian;
GRANT UPDATE (status, expires_at)                            ON reservation TO upln_librarian;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO upln_librarian;

-- Branch managers (in addition to librarian rights): manage the collection,
-- transfers and fines. Only managers may waive a fine.
GRANT INSERT, UPDATE ON copy, copy_transfer, title, title_author, author,
                        publisher, category TO upln_branch_manager;
GRANT INSERT         ON fine                TO upln_branch_manager;
GRANT UPDATE (waived) ON fine               TO upln_branch_manager;

-- HQ administrators: full data access (including deletes), but they are still
-- not database superusers, so they cannot bypass row-level security rules
-- or change the structure of the database.
GRANT ALL ON ALL TABLES    IN SCHEMA public TO upln_hq_admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO upln_hq_admin;

-- Analysts (reporting): see ONLY the privacy-safe views, never the raw tables.
GRANT SELECT ON v_member_directory_masked, v_branch_activity TO upln_analyst;

-- Members (self-service app): read the public catalogue, plus their own records
-- (the "own records" restriction is enforced by row-level security below).
GRANT SELECT ON branch, publisher, author, category, title, title_author, copy,
                member, loan, reservation
      TO upln_member_self;

-- ---------------------------------------------------------------------
-- 5. Row-level security: a member sees only HER OWN rows
-- ---------------------------------------------------------------------
-- The application tells the database who is logged in by setting
--   SET app.current_member_id = '<member_id>';
-- When it is not set (or empty), a member sees no personal rows at all.

ALTER TABLE member      ENABLE ROW LEVEL SECURITY;
ALTER TABLE loan        ENABLE ROW LEVEL SECURITY;
ALTER TABLE reservation ENABLE ROW LEVEL SECURITY;

-- Once row-level security is on, a role with no matching policy sees ZERO rows.
-- So staff roles are given an explicit "see all rows" policy.
DO $$
DECLARE t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['member', 'loan', 'reservation']
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS staff_all_rows ON %I', t);
        EXECUTE format('CREATE POLICY staff_all_rows ON %I
                        TO upln_librarian, upln_branch_manager, upln_hq_admin
                        USING (true) WITH CHECK (true)', t);
    END LOOP;
END $$;

DROP POLICY IF EXISTS member_own_row ON member;
CREATE POLICY member_own_row ON member
    FOR SELECT TO upln_member_self
    USING (member_id = NULLIF(current_setting('app.current_member_id', true), '')::INTEGER);

DROP POLICY IF EXISTS member_own_loans ON loan;
CREATE POLICY member_own_loans ON loan
    FOR SELECT TO upln_member_self
    USING (member_id = NULLIF(current_setting('app.current_member_id', true), '')::INTEGER);

DROP POLICY IF EXISTS member_own_reservations ON reservation;
CREATE POLICY member_own_reservations ON reservation
    FOR SELECT TO upln_member_self
    USING (member_id = NULLIF(current_setting('app.current_member_id', true), '')::INTEGER);
