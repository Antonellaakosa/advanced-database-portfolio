-- =====================================================================
-- File    : Akosa_Antonella_301929153_P1_08b_payment_guard_tests.sql
-- Purpose : Proves the payment guard works. Nothing is kept (ROLLBACK).
-- Run     : psql -U library_admin -d upln -f Akosa_Antonella_301929153_P1_08b_payment_guard_tests.sql
-- =====================================================================
\pset format aligned
\pset border 2
\echo '--- State of fines before the tests (fine, assessed, paid, outstanding, waived)'
SELECT fine_id, amount_assessed, amount_paid, amount_outstanding, waived FROM v_fine_balance ORDER BY fine_id;

CREATE FUNCTION pg_temp.payment_test(test_name TEXT, sql_text TEXT, expected_state TEXT)
RETURNS TABLE (test TEXT, expectation TEXT, result TEXT) LANGUAGE plpgsql AS $$
BEGIN
    test := test_name;
    expectation := CASE WHEN expected_state = 'OK' THEN 'must be accepted' ELSE 'must be refused (' || expected_state || ')' END;
    BEGIN
        EXECUTE sql_text;
        RAISE EXCEPTION 'undo' USING ERRCODE = 'RB001';
    EXCEPTION
        WHEN SQLSTATE 'RB001' THEN result := CASE WHEN expected_state = 'OK' THEN 'PASS (accepted)' ELSE 'FAIL (it was accepted)' END;
        WHEN OTHERS THEN
            result := CASE WHEN SQLSTATE = expected_state THEN 'PASS (refused: ' || SQLERRM || ')' ELSE 'FAIL (' || SQLSTATE || ': ' || SQLERRM || ')' END;
    END;
    RETURN NEXT;
END $$;

-- Sample data: fine 2 owes NGN 1,000.00 and fine 3 owes NGN 400.00 (see the table above).
SELECT test, expectation, result FROM (
    SELECT 1 AS n, * FROM pg_temp.payment_test('P01 Pay more than the balance',
        $$INSERT INTO payment (fine_id, received_by_staff_id, amount, method)
          SELECT fine_id, 1, amount_outstanding + 0.01, 'cash' FROM v_fine_balance
          WHERE amount_outstanding > 0 ORDER BY fine_id LIMIT 1$$, '23514')
    UNION ALL SELECT 2, * FROM pg_temp.payment_test('P02 Pay exactly the balance',
        $$INSERT INTO payment (fine_id, received_by_staff_id, amount, method)
          SELECT fine_id, 1, amount_outstanding, 'cash' FROM v_fine_balance
          WHERE amount_outstanding > 0 ORDER BY fine_id LIMIT 1$$, 'OK')
    UNION ALL SELECT 3, * FROM pg_temp.payment_test('P03 Pay part of the balance',
        $$INSERT INTO payment (fine_id, received_by_staff_id, amount, method)
          SELECT fine_id, 1, 1.00, 'card' FROM v_fine_balance
          WHERE amount_outstanding > 1 ORDER BY fine_id LIMIT 1$$, 'OK')
    UNION ALL SELECT 4, * FROM pg_temp.payment_test('P04 Pay a waived fine',
        $$UPDATE fine SET waived = TRUE WHERE fine_id = 3;
          INSERT INTO payment (fine_id, received_by_staff_id, amount, method) VALUES (3, 1, 1.00, 'cash')$$, '23514')
    UNION ALL SELECT 5, * FROM pg_temp.payment_test('P05 Pay a fine that does not exist',
        $$INSERT INTO payment (fine_id, received_by_staff_id, amount, method) VALUES (999999, 1, 10, 'cash')$$, '23503')
    UNION ALL SELECT 6, * FROM pg_temp.payment_test('P06 Two payments that together exceed the balance',
        $$INSERT INTO payment (fine_id, received_by_staff_id, amount, method) VALUES (3, 1, 400.00, 'cash');
          INSERT INTO payment (fine_id, received_by_staff_id, amount, method) VALUES (3, 1, 0.01, 'cash')$$, '23514')
) t ORDER BY n;
