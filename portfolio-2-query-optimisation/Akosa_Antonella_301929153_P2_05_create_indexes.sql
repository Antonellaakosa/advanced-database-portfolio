-- =====================================================================
-- Unity Public Library Network (UPLN)  |  MIT 8103  |  Portfolio 2
-- File    : Akosa_Antonella_301929153_P2_05_create_indexes.sql
-- Purpose : The optimisations. Each one targets a specific slow query.
-- Run     : psql -U library_admin -d upln_perf -v ON_ERROR_STOP=1 -f Akosa_Antonella_301929153_P2_05_create_indexes.sql
-- Safe to re-run (it drops and recreates the objects it adds).
-- =====================================================================
SET client_min_messages = warning;
\timing on

CREATE EXTENSION IF NOT EXISTS pg_trgm;     -- trigram matching, used for keyword search

DROP INDEX IF EXISTS idx_member_last_name, idx_loan_member_loaned_at, idx_title_name_trgm,
                     idx_copy_title_status, idx_loan_loaned_at_brin, idx_author_full_name,
                     idx_title_author_author, idx_payment_fine;
DROP MATERIALIZED VIEW IF EXISTS mv_loans_by_city_year;

-- Q1  Members by surname: a plain B-tree index on the searched column.
CREATE INDEX idx_member_last_name ON member (last_name);

-- Q2 and Q9  Loans of one member. A COMPOSITE index: it finds the member's rows
--            AND returns them already sorted by date, so "latest 10" needs no sort.
CREATE INDEX idx_loan_member_loaned_at ON loan (member_id, loaned_at DESC);

-- Q4  Keyword search with ILIKE '%word%'. A B-tree cannot help with a leading
--     wildcard, so we use a trigram GIN index (it indexes every 3-letter chunk).
CREATE INDEX idx_title_name_trgm ON title USING gin (title_name gin_trgm_ops);

-- Q5  Available copies of a title. A COVERING index: the columns the query returns
--     are stored inside the index (INCLUDE), so the table itself is not touched.
CREATE INDEX idx_copy_title_status ON copy (title_id, status) INCLUDE (copy_id, barcode, branch_id);

-- Q7  Date range over a table that is stored in date order. A BRIN index keeps only
--     the min/max date per block of rows, so it is tiny (compare with a B-tree in
--     Akosa_Antonella_301929153_P2_07_extra_experiments.sql).
CREATE INDEX idx_loan_loaned_at_brin ON loan USING brin (loaned_at);

-- Q8  Titles by author: the primary key of title_author starts with title_id, so
--     lookups by author_id could not use it. Two small indexes fix the join.
CREATE INDEX idx_author_full_name     ON author (full_name);
CREATE INDEX idx_title_author_author  ON title_author (author_id);

-- Q9  Payments of a fine (foreign key columns are not indexed automatically).
CREATE INDEX idx_payment_fine ON payment (fine_id);

-- Q6  A report over ALL loans cannot be made fast by any index, because it must
--     read every row. Instead we precompute it once: a MATERIALISED VIEW.
--     Trade-off: it must be refreshed to show new loans.
CREATE MATERIALIZED VIEW mv_loans_by_city_year AS
SELECT b.city, date_trunc('year', l.loaned_at) AS year, count(*) AS loans
FROM loan l JOIN branch b ON b.branch_id = l.checkout_branch_id
GROUP BY b.city, date_trunc('year', l.loaned_at);
CREATE UNIQUE INDEX uq_mv_loans_city_year ON mv_loans_by_city_year (city, year);

-- Q3  (Overdue loans) deliberately gets NO new index. The partial index created in
--     Portfolio 1 (uq_one_active_loan_per_copy) already covers only unreturned loans,
--     so the query was fast to begin with. Adding another index would only slow writes.

-- Refresh statistics so the planner knows about the new indexes.
VACUUM (ANALYZE);
\timing off

\echo
\echo '=== New indexes and their sizes ==='
SELECT c.relname AS index_name, t.relname AS on_table,
       pg_size_pretty(pg_relation_size(c.oid)) AS size
FROM pg_class c
JOIN pg_index i ON i.indexrelid = c.oid
JOIN pg_class t ON t.oid = i.indrelid
WHERE c.relname IN ('idx_member_last_name','idx_loan_member_loaned_at','idx_title_name_trgm',
                    'idx_copy_title_status','idx_loan_loaned_at_brin','idx_author_full_name',
                    'idx_title_author_author','idx_payment_fine','uq_mv_loans_city_year')
ORDER BY pg_relation_size(c.oid) DESC;
