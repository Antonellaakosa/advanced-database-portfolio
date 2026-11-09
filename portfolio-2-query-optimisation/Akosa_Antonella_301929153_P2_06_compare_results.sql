-- =====================================================================
-- Unity Public Library Network (UPLN)  |  MIT 8103  |  Portfolio 2
-- File    : Akosa_Antonella_301929153_P2_06_compare_results.sql
-- Purpose : Side-by-side before / after comparison.
-- Run     : psql -U library_admin -d upln_perf -f Akosa_Antonella_301929153_P2_06_compare_results.sql
-- Requires: Akosa_Antonella_301929153_P2_04_run_benchmark.sql has been run twice (label=before, label=after).
-- =====================================================================
\pset format aligned

\echo '=== Before vs after: time, speed-up and data blocks touched ==='
SELECT b.query_id AS id,
       q.name,
       b.median_ms AS "before ms",
       a.median_ms AS "after ms",
       CASE WHEN a.median_ms > 0 THEN round(b.median_ms / a.median_ms, 1) END AS "x faster",
       b.blocks_read AS "blocks before",
       a.blocks_read AS "blocks after"
FROM bench_results b
JOIN bench_results a ON a.query_id = b.query_id AND a.label = 'after'
JOIN bench_queries q ON q.query_id = b.query_id
WHERE b.label = 'before'
ORDER BY b.query_id;

\echo
\echo '=== How the execution plan changed ==='
SELECT b.query_id AS id,
       b.plan_nodes AS "plan before",
       a.plan_nodes AS "plan after",
       a.indexes_used AS "indexes used after"
FROM bench_results b
JOIN bench_results a ON a.query_id = b.query_id AND a.label = 'after'
WHERE b.label = 'before'
ORDER BY b.query_id;
