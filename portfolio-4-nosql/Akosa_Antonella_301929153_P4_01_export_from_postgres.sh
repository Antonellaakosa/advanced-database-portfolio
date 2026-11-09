#!/usr/bin/env bash
# =====================================================================
# Unity Public Library Network (UPLN) | MIT 8103 | Portfolio 4
# File    : 01_export_from_postgres.sh
# Purpose : The "migration" step. Reads the catalogue from PostgreSQL
#           (database `upln`, Portfolio 1) and turns each TITLE into ONE
#           document, with its authors, publisher, category and the number
#           of copies per branch folded inside it. The result is written to
#           data/migrated_titles.js. PostgreSQL is only READ, never changed.
# Run     : bash portfolio-4-nosql/01_export_from_postgres.sh      (from the repo root)
# =====================================================================
set -u
source "$(dirname "$0")/lib.sh"
OUT="$HERE/data/migrated_titles.js"
mkdir -p "$HERE/data"

echo "== Exporting the catalogue from PostgreSQL (database upln) =="
psql_upln > "$OUT" <<'SQL'
SELECT 'var migratedTitles = ' || jsonb_pretty(COALESCE(jsonb_agg(doc ORDER BY (doc->>'_id')::int), '[]'::jsonb)) || ';'
FROM (
  SELECT jsonb_strip_nulls(jsonb_build_object(
    '_id',             t.title_id,
    'title',           t.title_name,
    'mediaType',       t.media_type,
    'isbn',            NULLIF(trim(t.isbn), ''),
    'publicationYear', t.publication_year,
    'language',        t.language,
    'category',        jsonb_build_object('name', c.category_name),
    'publisher',       CASE WHEN p.publisher_id IS NULL THEN NULL
                            ELSE jsonb_build_object('name', p.publisher_name, 'country', p.country) END,
    'authors',         COALESCE((SELECT jsonb_agg(jsonb_build_object('name', a.full_name, 'order', ta.author_order)
                                                  ORDER BY ta.author_order)
                                 FROM title_author ta JOIN author a USING (author_id)
                                 WHERE ta.title_id = t.title_id), '[]'::jsonb),
    'subjects',        jsonb_build_array(lower(c.category_name)),
    'availability',    jsonb_build_object(
                         'total',     (SELECT count(*) FROM copy x WHERE x.title_id = t.title_id),
                         'available', (SELECT count(*) FROM copy x WHERE x.title_id = t.title_id AND x.status = 'available'),
                         'byBranch',  COALESCE((SELECT jsonb_agg(jsonb_build_object('branch', g.branch_name, 'copies', g.copies, 'available', g.available)
                                                                 ORDER BY g.branch_name)
                                                FROM (SELECT b.branch_name, count(*) AS copies,
                                                             count(*) FILTER (WHERE x.status = 'available') AS available
                                                      FROM copy x JOIN branch b USING (branch_id)
                                                      WHERE x.title_id = t.title_id GROUP BY b.branch_name) g), '[]'::jsonb)),
    'rating',          jsonb_build_object('sum', 0, 'count', 0),
    'migratedFrom',    'postgresql:upln.title'
  )) AS doc
  FROM title t
  JOIN category c ON c.category_id = t.category_id
  LEFT JOIN publisher p ON p.publisher_id = t.publisher_id
) d;
SQL
[ $? -eq 0 ] || { echo "Export failed. Is PostgreSQL running? (docker compose up -d)"; exit 1; }

N="$(grep -c '"_id":' "$OUT")"
echo "   documents written : $N"
echo "   file              : portfolio-4-nosql/data/migrated_titles.js  ($(wc -c < "$OUT") bytes)"
echo
echo "== The first document (one relational title = one document) =="
awk 'BEGIN{n=0} /^    \{/ {n++} n==1 {print} /^    \}/ && n==1 {exit}' "$OUT" | sed 's/^/   /'
echo
echo "Export finished."
