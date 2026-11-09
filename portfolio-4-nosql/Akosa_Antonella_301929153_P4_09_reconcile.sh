#!/usr/bin/env bash
# =====================================================================
# Unity Public Library Network (UPLN) | MIT 8103 | Portfolio 4
# File    : Akosa_Antonella_301929153_P4_09_reconcile.sh
# Purpose : Proves the migration was faithful. Compares PostgreSQL (the
#           source of truth) with the migrated documents in MongoDB:
#           titles, copies and free copies, per category.
# =====================================================================
set -u
source "$(dirname "$0")/Akosa_Antonella_301929153_P4_lib.sh"
PASS=0; FAIL=0
verdict() { if [ "$2" = "$3" ]; then echo "   PASS  $1   (PostgreSQL $2 = MongoDB $3)"; PASS=$((PASS+1)); else echo "   FAIL  $1   (PostgreSQL $2, MongoDB $3)"; FAIL=$((FAIL+1)); fi; }

echo "== Reconciliation: PostgreSQL (source of truth) vs migrated MongoDB documents =="

pg_titles=$(echo "SELECT count(*) FROM title;" | psql_upln)
mg_titles=$(mongoeval 'print(db.titles.countDocuments({migratedFrom:"postgresql:upln.title"}))' | tail -1)
verdict "R1 number of titles" "$pg_titles" "$mg_titles"

pg_copies=$(echo "SELECT count(*) FROM copy;" | psql_upln)
mg_copies=$(mongoeval 'print(db.titles.aggregate([{$match:{migratedFrom:"postgresql:upln.title"}},{$group:{_id:null,n:{$sum:"$availability.total"}}}]).toArray()[0].n)' | tail -1)
verdict "R2 total copies" "$pg_copies" "$mg_copies"

pg_free=$(echo "SELECT count(*) FROM copy WHERE status='available';" | psql_upln)
mg_free=$(mongoeval 'print(db.titles.aggregate([{$match:{migratedFrom:"postgresql:upln.title"}},{$group:{_id:null,n:{$sum:"$availability.available"}}}]).toArray()[0].n)' | tail -1)
verdict "R3 copies currently available" "$pg_free" "$mg_free"

pg_auth=$(echo "SELECT count(*) FROM title_author;" | psql_upln)
mg_auth=$(mongoeval 'print(db.titles.aggregate([{$match:{migratedFrom:"postgresql:upln.title"}},{$unwind:"$authors"},{$count:"n"}]).toArray()[0].n)' | tail -1)
verdict "R4 title-author links" "$pg_auth" "$mg_auth"

pg_cat=$(echo "SELECT string_agg(c.category_name||'='||x.n, ',' ORDER BY c.category_name) FROM (SELECT category_id, count(*) n FROM title GROUP BY 1) x JOIN category c USING (category_id);" | psql_upln)
mg_cat=$(mongoeval 'print(db.titles.aggregate([{$match:{migratedFrom:"postgresql:upln.title"}},{$group:{_id:"$category.name",n:{$sum:1}}},{$sort:{_id:1}}]).toArray().map(function(r){return r._id+"="+r.n}).join(","))' | tail -1)
verdict "R5 titles per category" "$pg_cat" "$mg_cat"

echo
echo "== Reconcile: $PASS PASS, $FAIL FAIL =="
[ "$FAIL" -eq 0 ]
