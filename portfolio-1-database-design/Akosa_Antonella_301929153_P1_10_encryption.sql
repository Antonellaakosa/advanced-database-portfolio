-- =====================================================================
-- Unity Public Library Network (UPLN)  |  MIT 8103  |  Portfolio 1 (security)
-- File    : 10_encryption.sql
-- Purpose : ENCRYPTION and HASHING with the pgcrypto extension.
--           1. A sensitive personal identifier (the National Identification
--              Number, NIN) is stored ENCRYPTED, so a stolen copy of the
--              database file or a backup does not reveal it.
--           2. Passwords for any future online member account would be
--              stored HASHED (salted bcrypt), never encrypted or plain.
--           3. A live check of whether the connection itself is encrypted.
-- Run     : bash portfolio-1-database-design/10b_run_encryption.sh
--           (it creates a random key for the demo; keys are NEVER committed)
-- Requires: 01 .. 06
-- =====================================================================
\if :{?nin_key}
\else
  \echo 'ERROR: run this through 10b_run_encryption.sh (it supplies the key)'
  \quit
\endif
SET client_min_messages = warning;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------
-- 1. A table for the identifier. It is a 16th table, one-to-one with member.
--    The raw NIN is never stored: only its ciphertext and the last 4 digits
--    (enough for a librarian to confirm identity at the desk).
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS member_identity CASCADE;
CREATE TABLE member_identity (
    member_id      INTEGER PRIMARY KEY REFERENCES member (member_id),
    nin_encrypted  BYTEA       NOT NULL,                        -- pgp_sym_encrypt(...) output
    nin_last4      CHAR(4)     NOT NULL CHECK (nin_last4 ~ '^[0-9]{4}$'),
    captured_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE member_identity IS
    'Encrypted National Identification Number. The key is held by the application, never by the database or the repository.';

REVOKE ALL ON member_identity FROM PUBLIC;
GRANT SELECT, INSERT, UPDATE ON member_identity TO upln_hq_admin;   -- ciphertext only; useless without the key
GRANT SELECT (member_id, nin_last4) ON member_identity TO upln_librarian;  -- desk staff see only the last 4 digits

-- The audit log records that the identifier changed, never its (even encrypted) value.
DROP TRIGGER IF EXISTS trg_audit ON member_identity;
CREATE TRIGGER trg_audit AFTER INSERT OR UPDATE OR DELETE ON member_identity
    FOR EACH ROW EXECUTE FUNCTION audit_row_change('member_id', 'nin_encrypted');

-- ---------------------------------------------------------------------
-- 2. Store synthetic NINs (made-up numbers) for two members, encrypted.
--    AES-256 via OpenPGP symmetric encryption; the key comes from the outside.
-- ---------------------------------------------------------------------
INSERT INTO member_identity (member_id, nin_encrypted, nin_last4) VALUES
    (1, pgp_sym_encrypt('12345678901', :'nin_key', 'cipher-algo=aes256'), '8901'),
    (2, pgp_sym_encrypt('10987654321', :'nin_key', 'cipher-algo=aes256'), '4321');

\pset format aligned
\pset border 2
\echo
\echo '=== A. What is really stored (the first bytes of the ciphertext) ==='
SELECT member_id, nin_last4,
       substr(encode(nin_encrypted, 'hex'), 1, 40) || '...' AS stored_bytes,
       length(nin_encrypted) AS stored_length
FROM member_identity ORDER BY member_id;

-- ---------------------------------------------------------------------
-- 3. Tests (nothing is kept from them; they only read, or are undone)
-- ---------------------------------------------------------------------
CREATE TEMP TABLE res (n SERIAL, test TEXT, expectation TEXT, result TEXT);

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

SELECT set_config('app.demo_key', :'nin_key', false) IS NOT NULL AS key_loaded_into_session \gset

DO $key$
DECLARE
    k TEXT := current_setting('app.demo_key');
    seen BOOLEAN;
    plain TEXT;
    c1 BYTEA; c2 BYTEA;
    code TEXT;
BEGIN
    -- E01 the plaintext cannot be found in the stored bytes
    SELECT EXISTS (SELECT 1 FROM member_identity WHERE position('12345678901'::bytea IN nin_encrypted) > 0
                                                    OR nin_encrypted::text LIKE '%12345678901%') INTO seen;
    INSERT INTO res (test, expectation, result) VALUES
      ('E01 Stored value does not contain the plain NIN', 'plain NIN not found in the stored bytes',
       CASE WHEN seen THEN 'FAIL (plain text found)' ELSE 'PASS (not found)' END);

    -- E02 the right key decrypts it
    SELECT pgp_sym_decrypt(nin_encrypted, k) INTO plain FROM member_identity WHERE member_id = 1;
    INSERT INTO res (test, expectation, result) VALUES
      ('E02 The correct key recovers the NIN', 'decrypts to the original number',
       CASE WHEN plain = '12345678901' THEN 'PASS (recovered ' || left(plain, 3) || '********)' ELSE 'FAIL' END);

    -- E03 a wrong key fails
    BEGIN
        PERFORM pgp_sym_decrypt(nin_encrypted, k || 'x') FROM member_identity WHERE member_id = 1;
        code := 'decrypted';
    EXCEPTION WHEN OTHERS THEN code := 'refused';
    END;
    INSERT INTO res (test, expectation, result) VALUES
      ('E03 A wrong key cannot decrypt', 'refused ("Wrong key or corrupt data")',
       CASE WHEN code = 'refused' THEN 'PASS (refused)' ELSE 'FAIL (it decrypted)' END);

    -- E04 the same NIN encrypted twice gives different bytes (random salt)
    c1 := pgp_sym_encrypt('12345678901', k);
    c2 := pgp_sym_encrypt('12345678901', k);
    INSERT INTO res (test, expectation, result) VALUES
      ('E04 Same NIN encrypted twice looks different', 'two different ciphertexts',
       CASE WHEN c1 <> c2 THEN 'PASS (different)' ELSE 'FAIL (identical)' END);

    -- E05 a librarian may see the last 4 digits but not the ciphertext
    code := pg_temp.try_as('upln_librarian', 'SELECT member_id, nin_last4 FROM member_identity');
    INSERT INTO res (test, expectation, result) VALUES
      ('E05 Librarian can read the last 4 digits', 'allowed', CASE WHEN code = 'ok' THEN 'PASS (allowed)' ELSE 'FAIL ' || code END);
    code := pg_temp.try_as('upln_librarian', 'SELECT nin_encrypted FROM member_identity');
    INSERT INTO res (test, expectation, result) VALUES
      ('E06 Librarian cannot read the ciphertext column', 'refused (42501)', CASE WHEN code = '42501' THEN 'PASS (refused)' ELSE 'FAIL ' || code END);
    code := pg_temp.try_as('upln_analyst', 'SELECT * FROM member_identity');
    INSERT INTO res (test, expectation, result) VALUES
      ('E07 Analyst cannot read the table at all', 'refused (42501)', CASE WHEN code = '42501' THEN 'PASS (refused)' ELSE 'FAIL ' || code END);

    -- E08 the audit log never shows the encrypted value
    SELECT EXISTS (SELECT 1 FROM audit_log WHERE table_name = 'member_identity' AND new_data ->> 'nin_encrypted' = '[REDACTED]') INTO seen;
    INSERT INTO res (test, expectation, result) VALUES
      ('E08 Audit log hides the encrypted value', 'nin_encrypted shown as [REDACTED]',
       CASE WHEN seen THEN 'PASS (redacted)' ELSE 'FAIL' END);

    -- E09/E10 password hashing: right password verifies, wrong one does not, salts differ
    INSERT INTO res (test, expectation, result)
    SELECT 'E09 Password hashing: right password verifies, wrong one fails',
           'true and false',
           CASE WHEN crypt('Correct-Horse-9', h) = h AND crypt('wrong-guess', h) <> h THEN 'PASS (true / false)' ELSE 'FAIL' END
    FROM (SELECT crypt('Correct-Horse-9', gen_salt('bf', 10)) AS h) s;
    INSERT INTO res (test, expectation, result)
    SELECT 'E10 Same password gets a different hash each time', 'two different hashes',
           CASE WHEN a <> b THEN 'PASS (different salts)' ELSE 'FAIL' END
    FROM (SELECT crypt('Correct-Horse-9', gen_salt('bf', 10)) AS a, crypt('Correct-Horse-9', gen_salt('bf', 10)) AS b) s;
END $key$;

\echo
\echo '=== B. Encryption and hashing tests ==='
SELECT n AS "#", test, expectation, result FROM res ORDER BY n;

\echo
\echo '=== C. What each role can see of member_identity ==='
\echo '--- Librarian (desk): last 4 digits only'
SET ROLE upln_librarian;
SELECT member_id, nin_last4 FROM member_identity ORDER BY member_id;
RESET ROLE;

\echo '--- Is the connection to the database itself encrypted (TLS)? ---'
SELECT current_setting('ssl') AS server_ssl_setting,
       COALESCE((SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()), FALSE) AS this_connection_encrypted;
\echo 'In this local lab the answer is off, because the container is reached over a private Docker network.'
\echo 'A production or cloud deployment must require TLS (see Portfolio 5: managed database with TLS and encrypted storage).'
