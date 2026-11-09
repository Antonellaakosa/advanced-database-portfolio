-- =====================================================================
-- Unity Public Library Network (UPLN)  |  MIT 8103  |  Portfolio 1 (integrity)
-- File    : Akosa_Antonella_301929153_P1_08_payment_guard.sql
-- Purpose : Protects MONEY. A payment can never be larger than what is
--           still owed on the fine, and a waived fine cannot be paid.
--           Two cashiers paying the same fine at once cannot both succeed
--           (the fine row is locked while the check runs).
-- Run     : psql -U library_admin -d upln -v ON_ERROR_STOP=1 -f Akosa_Antonella_301929153_P1_08_payment_guard.sql
-- Requires: Akosa_Antonella_301929153_P1_01_schema.sql .. Akosa_Antonella_301929153_P1_06_audit_log.sql
-- =====================================================================
SET client_min_messages = warning;

CREATE OR REPLACE FUNCTION guard_payment() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
    f_amount NUMERIC(10,2);
    f_waived BOOLEAN;
    paid     NUMERIC(10,2);
    owed     NUMERIC(10,2);
BEGIN
    -- Lock the fine row so two simultaneous payments are checked one after the other.
    SELECT amount, waived INTO f_amount, f_waived
    FROM fine WHERE fine_id = NEW.fine_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'UPLN-015 fine % does not exist', NEW.fine_id USING ERRCODE = 'foreign_key_violation';
    END IF;
    IF f_waived THEN
        RAISE EXCEPTION 'UPLN-017 fine % was waived: no payment is accepted', NEW.fine_id USING ERRCODE = 'check_violation';
    END IF;

    SELECT COALESCE(SUM(amount), 0) INTO paid FROM payment WHERE fine_id = NEW.fine_id;
    owed := f_amount - paid;

    IF NEW.amount > owed THEN
        RAISE EXCEPTION 'UPLN-016 payment of NGN % exceeds the outstanding balance of NGN % on fine %',
              NEW.amount, owed, NEW.fine_id USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_guard_payment ON payment;
CREATE TRIGGER trg_guard_payment BEFORE INSERT ON payment
    FOR EACH ROW EXECUTE FUNCTION guard_payment();
