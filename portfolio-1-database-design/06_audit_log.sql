-- =====================================================================
-- Unity Public Library Network (UPLN)  |  MIT 8103  |  Portfolio 1 (security)
-- File    : 06_audit_log.sql
-- Purpose : AUDITING. Records WHO changed WHAT and WHEN on the sensitive
--           tables, and makes the record tamper-resistant.
--           (Course notes: "audit logs record who accessed the database,
--           what actions were performed, and when".)
-- Run     : psql -U library_admin -d upln -v ON_ERROR_STOP=1 -f 06_audit_log.sql
-- Requires: 01_schema.sql, 02_sample_data.sql, 04_security_privacy.sql
-- Note    : Re-runnable. Re-running RESETS the log (fine for coursework;
--           a production system would never drop its audit history).
-- =====================================================================
SET client_min_messages = warning;

-- ---------------------------------------------------------------------
-- 1. The audit table
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS audit_log CASCADE;
CREATE TABLE audit_log (
    audit_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    changed_at      TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    table_name      TEXT        NOT NULL,
    operation       TEXT        NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    row_pk          TEXT        NOT NULL,              -- primary key of the changed row
    db_user         TEXT        NOT NULL,              -- who logged in (session_user)
    effective_role  TEXT        NOT NULL,              -- the role they were acting as
    app_staff_id    INTEGER,                           -- staff member named by the application
    transaction_id  BIGINT      NOT NULL DEFAULT txid_current(),
    changed_columns TEXT[],                            -- UPDATE only: which columns changed
    old_data        JSONB,                             -- row before (UPDATE, DELETE)
    new_data        JSONB                              -- row after  (INSERT, UPDATE)
);
CREATE INDEX idx_audit_table_row ON audit_log (table_name, row_pk);
CREATE INDEX idx_audit_changed_at ON audit_log (changed_at);

COMMENT ON TABLE audit_log IS
    'Append-only history of changes to sensitive tables. Filled by triggers only. Personal fields are redacted.';

-- ---------------------------------------------------------------------
-- 2. The trigger function that writes the log
--    SECURITY DEFINER: it runs with its owner's rights, so ordinary users
--    (who have NO access to audit_log) still cause entries to be written,
--    and cannot avoid it. search_path is pinned for safety.
--    Arguments: TG_ARGV[0] = primary-key column, TG_ARGV[1] = list of
--    personal columns to REDACT (the log shows that they changed, not
--    their value: privacy by design, NDPA 2023 data minimisation).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION audit_row_change() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
    pk_col   TEXT   := TG_ARGV[0];
    redact   TEXT[] := string_to_array(COALESCE(TG_ARGV[1], ''), ',');
    old_j    JSONB;
    new_j    JSONB;
    col      TEXT;
    changed  TEXT[];
    staff_id INTEGER := NULLIF(current_setting('app.staff_id', true), '')::INTEGER;
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN old_j := to_jsonb(OLD); END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN new_j := to_jsonb(NEW); END IF;

    IF TG_OP = 'UPDATE' THEN
        SELECT array_agg(k ORDER BY k) INTO changed
        FROM jsonb_object_keys(new_j) AS k
        WHERE new_j -> k IS DISTINCT FROM old_j -> k;
    END IF;

    FOREACH col IN ARRAY redact LOOP
        IF col <> '' THEN
            IF old_j ? col AND old_j ->> col IS NOT NULL THEN old_j := jsonb_set(old_j, ARRAY[col], '"[REDACTED]"'); END IF;
            IF new_j ? col AND new_j ->> col IS NOT NULL THEN new_j := jsonb_set(new_j, ARRAY[col], '"[REDACTED]"'); END IF;
        END IF;
    END LOOP;

    -- Inside a SECURITY DEFINER function current_user is the function owner, so the
    -- role the person is really acting as is read from the 'role' setting instead
    -- ('none' means no SET ROLE was used, so the login name is the role).
    INSERT INTO audit_log (table_name, operation, row_pk, db_user, effective_role, app_staff_id,
                           changed_columns, old_data, new_data)
    VALUES (TG_TABLE_NAME, TG_OP,
            COALESCE(new_j, old_j) ->> pk_col,
            session_user,
            CASE WHEN current_setting('role') = 'none' THEN session_user::TEXT ELSE current_setting('role') END,
            staff_id, changed, old_j, new_j);
    RETURN NULL;          -- AFTER trigger: return value is ignored
END $$;

-- ---------------------------------------------------------------------
-- 3. Attach it to the sensitive tables
--    (the table owner/administrator is the only one allowed to do this)
-- ---------------------------------------------------------------------
DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT * FROM (VALUES
        ('member',      'member_id',      'phone,address'),   -- personal data: redacted
        ('staff',       'staff_id',       ''),
        ('loan',        'loan_id',        ''),
        ('fine',        'fine_id',        ''),
        ('payment',     'payment_id',     ''),
        ('copy',        'copy_id',        ''),
        ('reservation', 'reservation_id', '')
    ) AS t(tbl, pk, redact_cols)
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_audit ON %I', r.tbl);
        EXECUTE format('CREATE TRIGGER trg_audit AFTER INSERT OR UPDATE OR DELETE ON %I
                        FOR EACH ROW EXECUTE FUNCTION audit_row_change(%L, %L)',
                       r.tbl, r.pk, r.redact_cols);
    END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 4. Make the log append-only (tamper-resistant)
--    Layer 1: nobody gets write rights. Layer 2: triggers refuse
--    UPDATE, DELETE and TRUNCATE even for the table owner.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION audit_log_immutable() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'audit_log is append-only: % is not allowed', TG_OP
        USING ERRCODE = 'insufficient_privilege';
END $$;

DROP TRIGGER IF EXISTS trg_audit_no_change   ON audit_log;
DROP TRIGGER IF EXISTS trg_audit_no_truncate ON audit_log;
CREATE TRIGGER trg_audit_no_change   BEFORE UPDATE OR DELETE ON audit_log
    FOR EACH ROW EXECUTE FUNCTION audit_log_immutable();
CREATE TRIGGER trg_audit_no_truncate BEFORE TRUNCATE ON audit_log
    FOR EACH STATEMENT EXECUTE FUNCTION audit_log_immutable();

-- ---------------------------------------------------------------------
-- 5. Who may READ the log: an auditor role and HQ administrators only.
--    The log contains who-did-what, which is itself sensitive.
-- ---------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'upln_auditor') THEN
        CREATE ROLE upln_auditor NOLOGIN;
    END IF;
END $$;

REVOKE ALL ON audit_log FROM PUBLIC, upln_librarian, upln_branch_manager, upln_hq_admin,
                             upln_analyst, upln_member_self, upln_auditor;
GRANT USAGE ON SCHEMA public TO upln_auditor;
GRANT SELECT ON audit_log TO upln_auditor, upln_hq_admin;

-- ---------------------------------------------------------------------
-- 6. A friendly report for auditors
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_audit_trail AS
SELECT audit_id, changed_at, db_user, effective_role, app_staff_id,
       table_name, operation, row_pk, changed_columns,
       old_data, new_data
FROM audit_log
ORDER BY audit_id;
REVOKE ALL ON v_audit_trail FROM PUBLIC;
GRANT SELECT ON v_audit_trail TO upln_auditor, upln_hq_admin;
