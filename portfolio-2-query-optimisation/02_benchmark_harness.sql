-- =====================================================================
-- Unity Public Library Network (UPLN)  |  MIT 8103  |  Portfolio 2
-- File    : 02_benchmark_harness.sql
-- Purpose : Defines the 9 workload queries and a function that measures them.
--           The SAME harness is used before and after optimisation, so the
--           comparison is fair.
-- Run     : psql -U library_admin -d upln_perf -v ON_ERROR_STOP=1 -f 02_benchmark_harness.sql
-- Method  : For every query, bench_run() does one warm-up run (to fill the
--           cache), then 5 timed runs with EXPLAIN (ANALYZE, BUFFERS), and
--           stores the MEDIAN execution time, the plan's scan and join types,
--           the index names used, and the number of 8 kB data blocks touched.
-- =====================================================================

SET client_min_messages = warning;
DROP TABLE IF EXISTS bench_results;
DROP TABLE IF EXISTS bench_queries;

CREATE TABLE bench_queries (
    query_id    INTEGER PRIMARY KEY,
    name        TEXT NOT NULL,
    purpose     TEXT NOT NULL,
    sql_before  TEXT NOT NULL,          -- the query as written
    sql_after   TEXT                    -- optional: rewritten form used after optimisation
);

CREATE TABLE bench_results (
    label        TEXT    NOT NULL,      -- 'before' or 'after'
    query_id     INTEGER NOT NULL REFERENCES bench_queries (query_id),
    median_ms    NUMERIC NOT NULL,
    plan_nodes   TEXT,                  -- scan and join types used
    indexes_used TEXT,
    blocks_read  BIGINT,                -- 8 kB blocks touched (cache hits + disk reads)
    rows_returned BIGINT,
    PRIMARY KEY (label, query_id)
);

INSERT INTO bench_queries (query_id, name, purpose, sql_before, sql_after) VALUES
(1, 'Members by surname',
    'Front desk looks up a member by last name',
    $q$SELECT member_id, first_name, last_name, email FROM member WHERE last_name = 'Okafor'$q$,
    NULL),
(2, 'A member''s recent loan history',
    'The 10 most recent loans of member 1500 (joins loan, copy, title)',
    $q$SELECT l.loan_id, t.title_name, l.loaned_at, l.returned_at
       FROM loan l JOIN copy c ON c.copy_id = l.copy_id JOIN title t ON t.title_id = c.title_id
       WHERE l.member_id = 1500 ORDER BY l.loaned_at DESC LIMIT 10$q$,
    NULL),
(3, 'Overdue loans report',
    'The 100 oldest overdue loans still out',
    $q$SELECT loan_id, member_id, due_at FROM loan
       WHERE returned_at IS NULL AND due_at < now() ORDER BY due_at LIMIT 100$q$,
    NULL),
(4, 'Catalogue keyword search',
    'Find titles containing the word "database" anywhere in the name',
    $q$SELECT title_id, title_name FROM title WHERE title_name ILIKE '%database%'$q$,
    NULL),
(5, 'Available copies of a title',
    'Which copies of title 4242 can be borrowed right now, and where',
    $q$SELECT copy_id, barcode, branch_id FROM copy WHERE title_id = 4242 AND status = 'available'$q$,
    NULL),
(6, 'Loans per city per year',
    'Management report over all 1,000,000 loans',
    $q$SELECT b.city, date_trunc('year', l.loaned_at) AS year, count(*) AS loans
       FROM loan l JOIN branch b ON b.branch_id = l.checkout_branch_id
       GROUP BY b.city, date_trunc('year', l.loaned_at) ORDER BY b.city, year$q$,
    $q$SELECT city, year, loans FROM mv_loans_by_city_year ORDER BY city, year$q$),
(7, 'Loans in one month',
    'Count loans issued in January 2025 (date range)',
    $q$SELECT count(*) FROM loan
       WHERE loaned_at >= timestamptz '2025-01-01' AND loaned_at < timestamptz '2025-02-01'$q$,
    NULL),
(8, 'Titles by an author',
    'List the titles written by "Author 777" (joins author, title_author, title)',
    $q$SELECT t.title_id, t.title_name
       FROM author a JOIN title_author ta ON ta.author_id = a.author_id
                     JOIN title t ON t.title_id = ta.title_id
       WHERE a.full_name = 'Author 777'$q$,
    NULL),
(9, 'Outstanding fines for a member',
    'What member 1500 still owes (joins loan, fine, payment)',
    $q$SELECT f.fine_id, f.amount, COALESCE(SUM(p.amount), 0) AS paid,
              f.amount - COALESCE(SUM(p.amount), 0) AS outstanding
       FROM loan l JOIN fine f ON f.loan_id = l.loan_id
                   LEFT JOIN payment p ON p.fine_id = f.fine_id
       WHERE l.member_id = 1500 AND NOT f.waived
       GROUP BY f.fine_id, f.amount
       HAVING f.amount - COALESCE(SUM(p.amount), 0) > 0$q$,
    NULL);

-- ---------------------------------------------------------------------
-- bench_run('before') or bench_run('after'): measure every query.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION bench_run(p_label TEXT, p_runs INTEGER DEFAULT 5)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    q        RECORD;
    stmt     TEXT;
    plan     JSON;
    pj       JSONB;
    times    NUMERIC[];
    i        INTEGER;
BEGIN
    DELETE FROM bench_results WHERE label = p_label;

    FOR q IN SELECT * FROM bench_queries ORDER BY query_id LOOP
        stmt := CASE WHEN p_label = 'after' AND q.sql_after IS NOT NULL
                     THEN q.sql_after ELSE q.sql_before END;
        times := ARRAY[]::NUMERIC[];

        -- run 0 is a warm-up and is discarded; runs 1..p_runs are measured
        FOR i IN 0..p_runs LOOP
            EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' || stmt INTO plan;
            pj := plan::jsonb;
            IF i > 0 THEN
                times := times || ((pj -> 0 ->> 'Execution Time')::NUMERIC);
            END IF;
        END LOOP;

        INSERT INTO bench_results (label, query_id, median_ms, plan_nodes, indexes_used,
                                   blocks_read, rows_returned)
        VALUES (
            p_label, q.query_id,
            (SELECT percentile_disc(0.5) WITHIN GROUP (ORDER BY t) FROM unnest(times) t),
            (SELECT string_agg(DISTINCT n, ', ' ORDER BY n)
               FROM jsonb_array_elements_text(jsonb_path_query_array(pj, 'strict $.**."Node Type"')) n
              WHERE n ~ '(Scan|Join|Nested Loop)'),
            (SELECT string_agg(DISTINCT n, ', ' ORDER BY n)
               FROM jsonb_array_elements_text(jsonb_path_query_array(pj, 'strict $.**."Index Name"')) n),
            COALESCE((pj -> 0 -> 'Plan' ->> 'Shared Hit Blocks')::BIGINT, 0)
              + COALESCE((pj -> 0 -> 'Plan' ->> 'Shared Read Blocks')::BIGINT, 0),
            (pj -> 0 -> 'Plan' ->> 'Actual Rows')::BIGINT
        );
    END LOOP;
END;
$$;

\echo 'Harness ready: 9 queries defined. Next: SELECT bench_run(''before'');'
SELECT query_id, name, purpose FROM bench_queries ORDER BY query_id;
