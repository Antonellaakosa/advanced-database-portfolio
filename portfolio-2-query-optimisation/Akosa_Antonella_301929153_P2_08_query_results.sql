-- =====================================================================
-- Unity Public Library Network (UPLN)  |  MIT 8103  |  Portfolio 2
-- File    : Akosa_Antonella_301929153_P2_08_query_results.sql
-- Purpose : Shows WHAT each of the nine benchmark queries returns, not just how
--           fast it runs: the SQL, the first rows of the result, and the total
--           number of rows. Then it checks that the optimised version of every
--           query returns exactly the same rows as the original.
-- Run     : after Akosa_Antonella_301929153_P2_05_create_indexes.sql (the indexes must exist), with
--           psql -U library_admin -d upln_perf -f Akosa_Antonella_301929153_P2_08_query_results.sql
--           Tip: add  > results/Akosa_Antonella_301929153_P2_query_results.txt  to save the output.
-- Time    : well under a minute.
-- Changes nothing: it only reads data and sets planner options for one query at a time.
-- =====================================================================

\set QUIET on

-- Helper (lives only for this session). Returns how many rows a query gives and a
-- fingerprint (md5) of those rows, ignoring row order. With plain = true it tells the
-- planner not to use any index, so the query runs as a full scan: the "before" way.
CREATE OR REPLACE FUNCTION pg_temp.result_digest(q TEXT, plain BOOLEAN)
RETURNS TABLE (n BIGINT, fingerprint TEXT) LANGUAGE plpgsql AS $$
BEGIN
    IF q IS NULL THEN RETURN; END IF;
    IF plain THEN
        PERFORM set_config('enable_indexscan',     'off', true);
        PERFORM set_config('enable_indexonlyscan', 'off', true);
        PERFORM set_config('enable_bitmapscan',    'off', true);
    END IF;
    EXECUTE format('SELECT count(*), md5(coalesce(string_agg(x::text, ''|'' ORDER BY x::text), '''')) FROM (%s) x', q)
       INTO n, fingerprint;
    IF plain THEN
        PERFORM set_config('enable_indexscan',     'on', true);
        PERFORM set_config('enable_indexonlyscan', 'on', true);
        PERFORM set_config('enable_bitmapscan',    'on', true);
    END IF;
    RETURN NEXT;
END;
$$;

\echo
\echo '##########  PART 1: the SQL and the rows each query returns  ##########'

\pset tuples_only on
\pset format unaligned
SELECT E'\n=====================================================================\nQ' || query_id || '. ' || name || E'\n' || purpose || E'\n\nSQL (original form):\n' || sql_before
FROM bench_queries WHERE query_id = 1;
\pset tuples_only off
\pset format aligned
\echo
\echo 'First 5 rows returned:'
SELECT format('SELECT * FROM (%s) x LIMIT 5', sql_before) FROM bench_queries WHERE query_id = 1 \gexec
SELECT format('SELECT count(*) AS "total rows returned" FROM (%s) x', sql_before) FROM bench_queries WHERE query_id = 1 \gexec

\pset tuples_only on
\pset format unaligned
SELECT E'\n=====================================================================\nQ' || query_id || '. ' || name || E'\n' || purpose || E'\n\nSQL (original form):\n' || sql_before
FROM bench_queries WHERE query_id = 2;
\pset tuples_only off
\pset format aligned
\echo
\echo 'First 5 rows returned:'
SELECT format('SELECT * FROM (%s) x LIMIT 5', sql_before) FROM bench_queries WHERE query_id = 2 \gexec
SELECT format('SELECT count(*) AS "total rows returned" FROM (%s) x', sql_before) FROM bench_queries WHERE query_id = 2 \gexec

\pset tuples_only on
\pset format unaligned
SELECT E'\n=====================================================================\nQ' || query_id || '. ' || name || E'\n' || purpose || E'\n\nSQL (original form):\n' || sql_before
FROM bench_queries WHERE query_id = 3;
\pset tuples_only off
\pset format aligned
\echo
\echo 'First 5 rows returned:'
SELECT format('SELECT * FROM (%s) x LIMIT 5', sql_before) FROM bench_queries WHERE query_id = 3 \gexec
SELECT format('SELECT count(*) AS "total rows returned" FROM (%s) x', sql_before) FROM bench_queries WHERE query_id = 3 \gexec

\pset tuples_only on
\pset format unaligned
SELECT E'\n=====================================================================\nQ' || query_id || '. ' || name || E'\n' || purpose || E'\n\nSQL (original form):\n' || sql_before
FROM bench_queries WHERE query_id = 4;
\pset tuples_only off
\pset format aligned
\echo
\echo 'First 5 rows returned:'
SELECT format('SELECT * FROM (%s) x LIMIT 5', sql_before) FROM bench_queries WHERE query_id = 4 \gexec
SELECT format('SELECT count(*) AS "total rows returned" FROM (%s) x', sql_before) FROM bench_queries WHERE query_id = 4 \gexec

\pset tuples_only on
\pset format unaligned
SELECT E'\n=====================================================================\nQ' || query_id || '. ' || name || E'\n' || purpose || E'\n\nSQL (original form):\n' || sql_before
FROM bench_queries WHERE query_id = 5;
\pset tuples_only off
\pset format aligned
\echo
\echo 'First 5 rows returned:'
SELECT format('SELECT * FROM (%s) x LIMIT 5', sql_before) FROM bench_queries WHERE query_id = 5 \gexec
SELECT format('SELECT count(*) AS "total rows returned" FROM (%s) x', sql_before) FROM bench_queries WHERE query_id = 5 \gexec

\pset tuples_only on
\pset format unaligned
SELECT E'\n=====================================================================\nQ' || query_id || '. ' || name || E'\n' || purpose || E'\n\nSQL (original form):\n' || sql_before
FROM bench_queries WHERE query_id = 6;
SELECT E'\nSQL (optimised form, after the indexes and the materialised view):\n' || sql_after FROM bench_queries WHERE query_id = 6 AND sql_after IS NOT NULL;
\pset tuples_only off
\pset format aligned
\echo
\echo 'First 5 rows returned:'
SELECT format('SELECT * FROM (%s) x LIMIT 5', sql_before) FROM bench_queries WHERE query_id = 6 \gexec
SELECT format('SELECT count(*) AS "total rows returned" FROM (%s) x', sql_before) FROM bench_queries WHERE query_id = 6 \gexec
\echo
\echo 'First 5 rows from the optimised form (the materialised view):'
SELECT format('SELECT * FROM (%s) x LIMIT 5', sql_after) FROM bench_queries WHERE query_id = 6 AND sql_after IS NOT NULL \gexec
SELECT format('SELECT count(*) AS "total rows in the view" FROM (%s) x', sql_after) FROM bench_queries WHERE query_id = 6 AND sql_after IS NOT NULL \gexec

\pset tuples_only on
\pset format unaligned
SELECT E'\n=====================================================================\nQ' || query_id || '. ' || name || E'\n' || purpose || E'\n\nSQL (original form):\n' || sql_before
FROM bench_queries WHERE query_id = 7;
\pset tuples_only off
\pset format aligned
\echo
\echo 'First 5 rows returned:'
SELECT format('SELECT * FROM (%s) x LIMIT 5', sql_before) FROM bench_queries WHERE query_id = 7 \gexec
SELECT format('SELECT count(*) AS "total rows returned" FROM (%s) x', sql_before) FROM bench_queries WHERE query_id = 7 \gexec

\pset tuples_only on
\pset format unaligned
SELECT E'\n=====================================================================\nQ' || query_id || '. ' || name || E'\n' || purpose || E'\n\nSQL (original form):\n' || sql_before
FROM bench_queries WHERE query_id = 8;
\pset tuples_only off
\pset format aligned
\echo
\echo 'First 5 rows returned:'
SELECT format('SELECT * FROM (%s) x LIMIT 5', sql_before) FROM bench_queries WHERE query_id = 8 \gexec
SELECT format('SELECT count(*) AS "total rows returned" FROM (%s) x', sql_before) FROM bench_queries WHERE query_id = 8 \gexec

\pset tuples_only on
\pset format unaligned
SELECT E'\n=====================================================================\nQ' || query_id || '. ' || name || E'\n' || purpose || E'\n\nSQL (original form):\n' || sql_before
FROM bench_queries WHERE query_id = 9;
\pset tuples_only off
\pset format aligned
\echo
\echo 'First 5 rows returned:'
SELECT format('SELECT * FROM (%s) x LIMIT 5', sql_before) FROM bench_queries WHERE query_id = 9 \gexec
SELECT format('SELECT count(*) AS "total rows returned" FROM (%s) x', sql_before) FROM bench_queries WHERE query_id = 9 \gexec

\echo
\echo '##########  PART 2: does the optimised version return the SAME rows?  ##########'
\echo 'Each query is run (a) as it normally runs now, with the indexes, and (b) with the planner told to ignore every index,'
\echo 'which is the original full-scan way. A fingerprint of all rows (ignoring order) is compared. For Q6 the summary'
\echo 'view is also compared with the original aggregate query.'
\echo
SELECT q.query_id AS id,
       q.name,
       a.n AS "rows",
       CASE WHEN a.fingerprint = b.fingerprint AND a.n = b.n THEN 'identical' ELSE 'DIFFERENT' END AS "same rows with and without indexes?",
       CASE WHEN q.sql_after IS NULL THEN '-'
            WHEN a.fingerprint = c.fingerprint AND a.n = c.n THEN 'identical' ELSE 'DIFFERENT' END AS "same rows from the optimised query?"
FROM bench_queries q
CROSS JOIN LATERAL pg_temp.result_digest(q.sql_before, false) a
CROSS JOIN LATERAL pg_temp.result_digest(q.sql_before, true)  b
LEFT  JOIN LATERAL pg_temp.result_digest(q.sql_after,  false) c ON true
ORDER BY q.query_id;

\echo
\echo 'Note: Q3 shows the oldest overdue loans; if two loans are due at the exact same moment their order can differ,'
\echo 'which would show here as DIFFERENT even though both answers are correct.'
