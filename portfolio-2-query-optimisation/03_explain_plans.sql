-- =====================================================================
-- Unity Public Library Network (UPLN)  |  MIT 8103  |  Portfolio 2
-- File    : 03_explain_plans.sql
-- Purpose : Prints the FULL execution plan (EXPLAIN ANALYZE with buffer
--           counts) of all 9 benchmark queries, for use as evidence.
-- Run     : psql -U library_admin -d upln_perf -v which=before -f 03_explain_plans.sql
--           psql -U library_admin -d upln_perf -v which=after  -f 03_explain_plans.sql
--           Tip: add  > results/plans_before.txt  to save the output.
-- =====================================================================
\if :{?which}
\else
  \echo 'ERROR: please pass -v which=before or -v which=after'
  \quit
\endif

\pset tuples_only on
\pset format unaligned

SELECT stmt FROM (
    SELECT query_id, 1 AS part,
           format('SELECT %L', E'\n==== Q' || query_id || ': ' || name || '  [' || :'which' || '] ====' || E'\n' || purpose) AS stmt
    FROM bench_queries
    UNION ALL
    SELECT query_id, 2,
           'EXPLAIN (ANALYZE, BUFFERS) ' ||
           CASE WHEN :'which' = 'after' THEN COALESCE(sql_after, sql_before) ELSE sql_before END
    FROM bench_queries
) x ORDER BY query_id, part
\gexec
