#!/usr/bin/env bash
# =====================================================================
# Unity Public Library Network (UPLN) | MIT 8103 | Portfolio 1 (security)
# File    : Akosa_Antonella_301929153_P1_09b_login_tests.sh
# Purpose : Creates the two login accounts with RANDOM passwords, then proves
#           authentication really works by logging in as them over the network.
# Run     : bash portfolio-1-database-design/Akosa_Antonella_301929153_P1_09b_login_tests.sh   (from the repo root)
# Note    : The random passwords live only in this shell session's memory.
#           They are never written to a file or committed.
# =====================================================================
set -u
AMINA_PW="$(openssl rand -base64 18)"
NGOZI_PW="$(openssl rand -base64 18)"
HERE="$(cd "$(dirname "$0")" && pwd)"

# Run SQL as a given login user, over a real network connection with a password.
#   login_sql <user> <password> <sql>
login_sql() {
  if [ -n "${UPLN_PSQL_LOCAL:-}" ]; then      # test hook: a server outside Docker
    PGPASSWORD="$2" psql -X -h 127.0.0.1 -p "$UPLN_PSQL_LOCAL" -U "$1" -d upln -c "$3" 2>&1
  else
    docker compose -f "$HERE/../Akosa_Antonella_301929153_docker-compose.yml" exec -T -e PGPASSWORD="$2" postgres psql -X -h postgres -U "$1" -d upln -c "$3" 2>&1
  fi
}
admin_file() {                                  # run a file as the administrator
  if [ -n "${UPLN_PSQL_LOCAL:-}" ]; then
    psql -X -h /tmp -p "$UPLN_PSQL_LOCAL" -U postgres -d upln -v ON_ERROR_STOP=1 -q \
         -v amina_pw="$AMINA_PW" -v ngozi_pw="$NGOZI_PW" -f "$1"
  else
    docker compose -f "$HERE/../Akosa_Antonella_301929153_docker-compose.yml" exec -T postgres psql -X -U library_admin -d upln -v ON_ERROR_STOP=1 -q \
         -v amina_pw="$AMINA_PW" -v ngozi_pw="$NGOZI_PW" < "$1"
  fi
}

echo "##### Step 1: create the login accounts (passwords are random and not shown) #####"
admin_file "$HERE/Akosa_Antonella_301929153_P1_09_authentication.sql" || { echo "setup failed"; exit 1; }

echo
echo "##### L1: wrong password must be REFUSED #####"
login_sql staff_amina "not-the-password" "SELECT 1"

echo
echo "##### L2: correct password is accepted. Who am I? #####"
login_sql staff_amina "$AMINA_PW" \
  "SELECT session_user AS logged_in_as, pg_has_role(session_user, 'upln_librarian', 'member') AS has_librarian_rights, pg_has_role(session_user, 'upln_hq_admin', 'member') AS has_admin_rights"

echo
echo "##### L3: a librarian login cannot delete loans (least privilege) #####"
login_sql staff_amina "$AMINA_PW" "DELETE FROM loan WHERE loan_id = 1"

echo
echo "##### L4: a librarian login cannot read the audit log #####"
login_sql staff_amina "$AMINA_PW" "SELECT * FROM audit_log LIMIT 1"

echo
echo "##### L5: a librarian login CAN do her job (a permitted update on a loan; it changes nothing but is logged) #####"
login_sql staff_amina "$AMINA_PW" \
  "SET app.staff_id = '3'; UPDATE loan SET renewals = renewals WHERE loan_id = 2"

echo
echo "##### L6: the auditor logs in and sees the REAL login name in the trail #####"
login_sql auditor_ngozi "$NGOZI_PW" \
  "SELECT audit_id AS id, db_user AS logged_in_as, effective_role AS acting_as, app_staff_id AS staff, table_name AS \"table\", operation AS op, row_pk AS pk FROM v_audit_trail ORDER BY audit_id DESC LIMIT 3"

echo
echo "##### L7: the auditor cannot change anything #####"
login_sql auditor_ngozi "$NGOZI_PW" "UPDATE member SET status = 'active' WHERE member_id = 1"
