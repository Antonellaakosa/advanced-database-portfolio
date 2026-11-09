#!/usr/bin/env bash
# =====================================================================
# Unity Public Library Network (UPLN) | MIT 8103 | Portfolio 3
# File    : Akosa_Antonella_301929153_P3_00_setup.sh
# Purpose : Builds a separate test database `upln_tx` from the Portfolio 1
#           design (schema, sample data, payment guard) and installs the
#           Portfolio 3 transaction functions. Safe to run again: it starts
#           from scratch each time. The main `upln` database is never touched.
# Run     : bash portfolio-3-transactions-concurrency/Akosa_Antonella_301929153_P3_00_setup.sh     (from the repo root)
# =====================================================================
set -u
source "$(dirname "$0")/Akosa_Antonella_301929153_P3_lib.sh"
P1="$ROOT/portfolio-1-database-design"

echo "== Portfolio 3 setup: creating database $DB from the Portfolio 1 design =="
P3_CONN_DB=postgres psqlx -v ON_ERROR_STOP=1 <<SQL
SET client_min_messages = warning;
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB' AND pid <> pg_backend_pid();
DROP DATABASE IF EXISTS $DB;
CREATE DATABASE $DB;
SQL
[ $? -eq 0 ] || { echo "Could not create the database. Is Docker running? (docker compose -f Akosa_Antonella_301929153_docker-compose.yml up -d)"; exit 1; }

for f in Akosa_Antonella_301929153_P1_01_schema.sql Akosa_Antonella_301929153_P1_02_sample_data.sql Akosa_Antonella_301929153_P1_08_payment_guard.sql; do
  echo "   loading Portfolio 1: $f"
  psqlx -v ON_ERROR_STOP=1 < "$P1/$f" > /dev/null || { echo "FAILED while loading $f"; exit 1; }
done
echo "   loading Portfolio 3: Akosa_Antonella_301929153_P3_01_transaction_functions.sql"
psqlx -v ON_ERROR_STOP=1 < "$HERE/Akosa_Antonella_301929153_P3_01_transaction_functions.sql" > /dev/null || { echo "FAILED while loading the functions"; exit 1; }

echo
echo "== What is in $DB now =="
psqlx -v ON_ERROR_STOP=1 <<'SQL'
SELECT 'core tables from Portfolio 1: ' || count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name NOT LIKE 'p3_%' AND table_type='BASE TABLE';
SELECT 'members / copies / loans: ' || (SELECT count(*) FROM member) || ' / ' || (SELECT count(*) FROM copy) || ' / ' || (SELECT count(*) FROM loan);
SELECT 'one-active-loan rule    : ' || indexname || '  ' || regexp_replace(indexdef, '^.* ON ', 'ON ') FROM pg_indexes WHERE indexname='uq_one_active_loan_per_copy';
SELECT 'payment guard trigger   : ' || tgname FROM pg_trigger WHERE tgname='trg_guard_payment';
SELECT 'P3 functions installed  : ' || string_agg(proname, ', ' ORDER BY proname) FROM pg_proc WHERE proname IN ('checkout_copy','return_copy','checkout_unsafe','p3_cleanup','p3_check');
SQL
echo
echo "Setup finished."
