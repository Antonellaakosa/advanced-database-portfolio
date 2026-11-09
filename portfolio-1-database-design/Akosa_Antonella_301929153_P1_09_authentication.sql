-- =====================================================================
-- Unity Public Library Network (UPLN)  |  MIT 8103  |  Portfolio 1 (security)
-- File    : 09_authentication.sql
-- Purpose : AUTHENTICATION. Until now the five roles were "job titles" that
--           nobody could log in as. Here two real login accounts are
--           created and attached to those job roles:
--               staff_amina   -> upln_librarian   (front-desk staff)
--               auditor_ngozi -> upln_auditor     (reads the audit trail)
--           Passwords are supplied when the script runs. They are NEVER
--           written in the repository, and the database keeps only a salted
--           SCRAM-SHA-256 hash, never the password itself.
-- Run     : see 09b_login_tests.sh (it generates random passwords for you)
-- Requires: 01 .. 06 (audit log, so that real logins appear in it)
-- =====================================================================
\if :{?amina_pw}
\else
  \echo 'ERROR: run this through 09b_login_tests.sh (it supplies the passwords)'
  \quit
\endif
\if :{?ngozi_pw}
\else
  \echo 'ERROR: run this through 09b_login_tests.sh (it supplies the passwords)'
  \quit
\endif

SET client_min_messages = warning;
SET password_encryption = 'scram-sha-256';      -- store salted hashes, not passwords

-- 1. Create the login accounts (a "role" that may log in is a user).
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'staff_amina') THEN
        CREATE ROLE staff_amina LOGIN CONNECTION LIMIT 5;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'auditor_ngozi') THEN
        CREATE ROLE auditor_ngozi LOGIN CONNECTION LIMIT 5;
    END IF;
END $$;

-- 2. Set (or rotate) the passwords, with an expiry date so they cannot live forever.
ALTER ROLE staff_amina   PASSWORD :'amina_pw'  VALID UNTIL '2027-06-30';
ALTER ROLE auditor_ngozi PASSWORD :'ngozi_pw'  VALID UNTIL '2027-06-30';

-- 3. Authorisation: each person receives the rights of exactly one job role.
GRANT upln_librarian TO staff_amina;
GRANT upln_auditor   TO auditor_ngozi;
-- Safety: a user must never be able to hand out rights or create other users.
ALTER ROLE staff_amina   NOSUPERUSER NOCREATEDB NOCREATEROLE;
ALTER ROLE auditor_ngozi NOSUPERUSER NOCREATEDB NOCREATEROLE;

\pset format aligned
\pset border 2
\echo
\echo '=== A. The accounts: password stored as a salted hash, never as text ==='
SELECT r.rolname                         AS login_account,
       r.rolcanlogin                     AS can_log_in,
       left(a.rolpassword, 14) || '...'  AS stored_password,
       r.rolvaliduntil::date             AS password_expires,
       r.rolsuper                        AS is_superuser
FROM pg_roles r JOIN pg_authid a ON a.oid = r.oid
WHERE r.rolname IN ('staff_amina', 'auditor_ngozi') ORDER BY 1;

\echo
\echo '=== B. Which job role each account holds ==='
SELECT m.rolname AS login_account, g.rolname AS job_role
FROM pg_auth_members am
JOIN pg_roles m ON m.oid = am.member
JOIN pg_roles g ON g.oid = am.roleid
WHERE m.rolname IN ('staff_amina', 'auditor_ngozi') ORDER BY 1;

\echo
\echo '=== C. How the server checks identity (connection rules, from pg_hba.conf) ==='
\echo 'Look for the rule that applies to network connections: it must say scram-sha-256 (password proof).'
\echo 'Any "trust" lines are the lab container\'s own local connections only and would not exist in production.'
SELECT line_number AS line, type, database, user_name, address, auth_method
FROM pg_hba_file_rules WHERE error IS NULL ORDER BY line_number;
