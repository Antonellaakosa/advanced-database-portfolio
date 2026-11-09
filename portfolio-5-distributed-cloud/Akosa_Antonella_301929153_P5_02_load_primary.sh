#!/usr/bin/env bash
# =====================================================================
# UPLN | MIT 8103 | Portfolio 5
# File    : Akosa_Antonella_301929153_P5_02_load_primary.sh
# Purpose : Puts the Portfolio 1 library schema and sample data on the
#           primary, creates the small ledger table used by the backup
#           test, and gives the application and reporting accounts only
#           the rights they need. The replica receives all of it by
#           streaming replication.
# Run     : bash portfolio-5-distributed-cloud/Akosa_Antonella_301929153_P5_02_load_primary.sh
# =====================================================================
set -u
source "$(dirname "$0")/Akosa_Antonella_301929153_P5_lib.sh"
P1="$ROOT/portfolio-1-database-design"
echo "== Loading the UPLN case study onto the primary =="
if [ "$(asql primary "select count(*) from information_schema.tables where table_schema='public' and table_name='title'")" = "1" ]; then
  echo "   the schema is already there (kept)"
else
  admin primary < "$P1/Akosa_Antonella_301929153_P1_01_schema.sql"      > /dev/null || { echo "schema load failed"; exit 1; }
  admin primary < "$P1/Akosa_Antonella_301929153_P1_02_sample_data.sql" > /dev/null || { echo "sample data load failed"; exit 1; }
  echo "   Portfolio 1 schema and sample data loaded"
fi

admin primary > /dev/null <<'SQL'
CREATE TABLE IF NOT EXISTS p5_ledger (id serial PRIMARY KEY, note text NOT NULL, created_at timestamptz NOT NULL DEFAULT now());
-- least privilege: reporting may only read; the application may read the catalogue and write loans
GRANT USAGE ON SCHEMA public TO p5_app, p5_report;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO p5_report;
GRANT SELECT ON title, author, title_author, category, publisher, branch, copy TO p5_app;
GRANT SELECT, INSERT, UPDATE ON loan, copy TO p5_app;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO p5_app;
SQL
echo "   least-privilege rights granted to p5_app and p5_report"

echo
echo "== Row counts on the primary =="
for t in title copy loan member; do printf "   %-8s %s\n" "$t" "$(asql primary "select count(*) from $t")"; done
echo
echo "Load finished."
