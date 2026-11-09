-- =====================================================================
-- Unity Public Library Network (UPLN)  |  MIT 8103  |  Portfolio 1 (security)
-- File    : 06b_audit_demo.sql
-- Purpose : A short, REAL working day. Staff make changes; the audit log
--           records them; an auditor reads the trail. Unlike 07_audit_tests,
--           these changes are kept (the net effect on your data is nil:
--           each change is reversed, which is itself recorded).
-- Run     : psql -U library_admin -d upln -f 06b_audit_demo.sql
-- Requires: 06_audit_log.sql
-- =====================================================================
\pset format aligned
\pset border 2

\echo '--- 09:00  Desk staff member 3 (a librarian) fixes a member''s phone number'
SET app.staff_id = '3';
SET ROLE upln_librarian;
UPDATE member SET phone = '+2348010000099' WHERE member_id = 1;
RESET ROLE;

\echo '--- 09:05  Staff member 3 realises it was a typing error and corrects it'
SET ROLE upln_librarian;
UPDATE member SET phone = '+2348010000001' WHERE member_id = 1;
RESET ROLE;

\echo '--- 11:30  Branch manager (staff member 5) waives a fine, then restores it'
SET app.staff_id = '5';
SET ROLE upln_branch_manager;
UPDATE fine SET waived = TRUE  WHERE fine_id = 3;
UPDATE fine SET waived = FALSE WHERE fine_id = 3;
RESET ROLE;

\echo '--- 16:00  Someone tries to cover their tracks by editing the log (must fail)'
SET ROLE upln_hq_admin;
DELETE FROM audit_log;
RESET ROLE;

\echo
\echo '=== The auditor opens the audit trail ==='
SET ROLE upln_auditor;
SELECT audit_id AS id,
       to_char(changed_at, 'YYYY-MM-DD HH24:MI:SS') AS "when",
       effective_role AS "acting as",
       app_staff_id AS staff,
       table_name AS "table",
       operation AS op,
       row_pk AS pk,
       changed_columns AS changed,
       COALESCE(old_data ->> 'waived', old_data ->> 'phone') AS "old value",
       COALESCE(new_data ->> 'waived', new_data ->> 'phone') AS "new value"
FROM v_audit_trail
ORDER BY audit_id;
RESET ROLE;
