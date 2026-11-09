-- =====================================================================
-- Unity Public Library Network (UPLN)  |  MIT 8103  |  Portfolio 2
-- File    : 04_run_benchmark.sql
-- Purpose : Measures all 9 queries and prints the results.
-- Run     : psql -U library_admin -d upln_perf -v label=before -f 04_run_benchmark.sql
--           psql -U library_admin -d upln_perf -v label=after  -f 04_run_benchmark.sql
--           (use label=before BEFORE creating the indexes, label=after AFTER)
-- Time    : roughly 10 to 60 seconds.
-- =====================================================================
\if :{?label}
\else
  \echo 'ERROR: please pass -v label=before or -v label=after'
  \quit
\endif

SELECT bench_run(:'label');

\echo
\echo '=== Results for the run labelled:' :label '==='
SELECT r.query_id AS id,
       q.name,
       r.median_ms AS "median ms",
       r.rows_returned AS rows,
       r.blocks_read AS "blocks touched",
       r.plan_nodes AS "scan / join types",
       r.indexes_used AS "indexes used"
FROM bench_results r JOIN bench_queries q USING (query_id)
WHERE r.label = :'label'
ORDER BY r.query_id;
