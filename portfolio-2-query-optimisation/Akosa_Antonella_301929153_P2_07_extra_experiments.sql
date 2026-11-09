-- =====================================================================
-- Unity Public Library Network (UPLN)  |  MIT 8103  |  Portfolio 2
-- File    : 07_extra_experiments.sql
-- Purpose : Seven small experiments that show HOW and WHY the optimiser
--           behaves as it does (the "advanced concepts" of this portfolio).
-- Run     : psql -U library_admin -d upln_perf -f 07_extra_experiments.sql
-- Requires: 01_generate_data.sql and 05_create_indexes.sql already run.
-- Safe    : Experiments use scratch copies (exp_*). Everything is dropped at
--           the end. Re-runnable. Takes about 1 to 2 minutes.
-- =====================================================================
SET client_min_messages = warning;
\pset border 2
\pset format aligned
\pset tuples_only off

-- ---- helper functions (live only for this session) -------------------
-- Run a query under EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON), return a number.
CREATE FUNCTION pg_temp.plan_json(sql_text TEXT) RETURNS JSON LANGUAGE plpgsql AS $$
DECLARE j JSON;
BEGIN
    EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' || sql_text INTO j;
    RETURN j;
END $$;

-- Median execution time in ms over 5 runs (after one warm-up run).
CREATE FUNCTION pg_temp.ms(sql_text TEXT) RETURNS NUMERIC LANGUAGE plpgsql AS $$
DECLARE t NUMERIC[] := '{}'; i INT;
BEGIN
    PERFORM pg_temp.plan_json(sql_text);
    FOR i IN 1..5 LOOP
        t := t || ((pg_temp.plan_json(sql_text) -> 0 ->> 'Execution Time')::NUMERIC);
    END LOOP;
    RETURN round((SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY x) FROM unnest(t) x)::NUMERIC, 3);
END $$;

-- Pages (8 kB blocks) touched by the first run of a query.
CREATE FUNCTION pg_temp.blocks(sql_text TEXT) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE p JSON;
BEGIN
    p := pg_temp.plan_json(sql_text) -> 0 -> 'Plan';
    RETURN COALESCE((p ->> 'Shared Hit Blocks')::BIGINT, 0) + COALESCE((p ->> 'Shared Read Blocks')::BIGINT, 0);
END $$;

-- =====================================================================
\echo
\echo '#####  EXPERIMENT 1: BRIN versus B-tree on a time column  #####'
\echo 'loan.loaned_at grows in the same order rows are stored, so a tiny BRIN index can work.'
-- =====================================================================
DROP INDEX IF EXISTS exp_loan_loaned_at_btree;
CREATE INDEX exp_loan_loaned_at_btree ON loan (loaned_at);
SELECT 'B-tree' AS index_type, pg_size_pretty(pg_relation_size('exp_loan_loaned_at_btree')) AS size,
       pg_temp.ms($$SELECT count(*) FROM loan WHERE loaned_at >= '2025-01-01' AND loaned_at < '2025-02-01'$$) AS ms_jan_2025
UNION ALL
SELECT 'BRIN', pg_size_pretty(pg_relation_size('idx_loan_loaned_at_brin')), NULL;
-- Now remove the B-tree so the planner can only use BRIN, and measure again.
BEGIN;
DROP INDEX exp_loan_loaned_at_btree;      -- remove the B-tree so the planner can only choose BRIN
SELECT 'BRIN only' AS case, pg_temp.ms($$SELECT count(*) FROM loan WHERE loaned_at >= '2025-01-01' AND loaned_at < '2025-02-01'$$) AS ms_jan_2025;
COMMIT;
\echo 'Reading: BRIN is thousands of times smaller than a B-tree; its time is close, a fair trade for append-only history.'

-- =====================================================================
\echo
\echo '#####  EXPERIMENT 2: the three join algorithms  #####'
\echo 'Same query, forcing the optimiser to use one join method at a time.'
-- =====================================================================
CREATE TEMP TABLE exp_join_q AS SELECT $$SELECT count(*) FROM loan l JOIN copy c ON c.copy_id = l.copy_id
    WHERE l.loaned_at >= '2025-01-01' AND l.loaned_at < '2025-03-01'$$ AS q;

SET enable_hashjoin = on;  SET enable_mergejoin = on;  SET enable_nestloop = on;
SELECT 'optimiser free choice' AS setting, pg_temp.ms(q) AS ms,
       (SELECT string_agg(DISTINCT n, ', ') FROM regexp_matches(pg_temp.plan_json(q)::TEXT, '"Node Type": "([A-Za-z ]*Join|Nested Loop)"', 'g') AS m(a), unnest(a) n) AS join_used
FROM exp_join_q;
SET enable_hashjoin = off; SET enable_mergejoin = on;  SET enable_nestloop = off;
SELECT 'merge join forced' AS setting, pg_temp.ms(q) AS ms,
       (SELECT string_agg(DISTINCT n, ', ') FROM regexp_matches(pg_temp.plan_json(q)::TEXT, '"Node Type": "([A-Za-z ]*Join|Nested Loop)"', 'g') AS m(a), unnest(a) n) AS join_used
FROM exp_join_q;
SET enable_hashjoin = on;  SET enable_mergejoin = off; SET enable_nestloop = off;
SELECT 'hash join forced' AS setting, pg_temp.ms(q) AS ms,
       (SELECT string_agg(DISTINCT n, ', ') FROM regexp_matches(pg_temp.plan_json(q)::TEXT, '"Node Type": "([A-Za-z ]*Join|Nested Loop)"', 'g') AS m(a), unnest(a) n) AS join_used
FROM exp_join_q;
SET enable_hashjoin = off; SET enable_mergejoin = off; SET enable_nestloop = on;
SELECT 'nested loop forced' AS setting, pg_temp.ms(q) AS ms,
       (SELECT string_agg(DISTINCT n, ', ') FROM regexp_matches(pg_temp.plan_json(q)::TEXT, '"Node Type": "([A-Za-z ]*Join|Nested Loop)"', 'g') AS m(a), unnest(a) n) AS join_used
FROM exp_join_q;
RESET enable_hashjoin; RESET enable_mergejoin; RESET enable_nestloop;
\echo 'Reading: the free choice is normally the fastest; forcing a worse algorithm shows why cost-based choice matters.'

-- =====================================================================
\echo
\echo '#####  EXPERIMENT 3: estimated versus actual rows, and what ANALYZE changes  #####'
-- =====================================================================
DROP TABLE IF EXISTS exp_loan;
CREATE TABLE exp_loan (LIKE loan);
ALTER TABLE exp_loan SET (autovacuum_enabled = off);     -- so no automatic statistics appear
INSERT INTO exp_loan SELECT * FROM loan;                  -- 1,000,010 rows, no statistics yet

CREATE FUNCTION pg_temp.est_vs_actual(sql_text TEXT) RETURNS TABLE (estimated_rows NUMERIC, actual_rows NUMERIC)
LANGUAGE plpgsql AS $$
DECLARE p JSON;
BEGIN
    p := pg_temp.plan_json(sql_text) -> 0 -> 'Plan';
    RETURN QUERY SELECT (p ->> 'Plan Rows')::NUMERIC, (p ->> 'Actual Rows')::NUMERIC;
END $$;

\echo '--- Without statistics (table never analysed): member_id = 1500'
SELECT * FROM pg_temp.est_vs_actual($$SELECT * FROM exp_loan WHERE member_id = 1500$$);
\echo '--- Without statistics: a range on loaned_at (2025)'
SELECT * FROM pg_temp.est_vs_actual($$SELECT * FROM exp_loan WHERE loaned_at >= '2025-01-01' AND loaned_at < '2026-01-01'$$);
ANALYZE exp_loan;
\echo '--- After ANALYZE: member_id = 1500'
SELECT * FROM pg_temp.est_vs_actual($$SELECT * FROM exp_loan WHERE member_id = 1500$$);
\echo '--- After ANALYZE: a range on loaned_at (2025)'
SELECT * FROM pg_temp.est_vs_actual($$SELECT * FROM exp_loan WHERE loaned_at >= '2025-01-01' AND loaned_at < '2026-01-01'$$);
\echo 'Reading: statistics are the optimiser''s eyes. Closer estimates mean better plan choices.'

-- =====================================================================
\echo
\echo '#####  EXPERIMENT 4: parallel query on the analytic report (Q6)  #####'
-- =====================================================================
SET max_parallel_workers_per_gather = 0;
SELECT 'no parallel workers' AS setting, pg_temp.ms($$SELECT b.city, extract(year FROM l.loaned_at) AS yr, count(*)
    FROM loan l JOIN branch b ON b.branch_id = l.checkout_branch_id GROUP BY 1, 2$$) AS ms;
SET max_parallel_workers_per_gather = 2;
SELECT '2 parallel workers' AS setting, pg_temp.ms($$SELECT b.city, extract(year FROM l.loaned_at) AS yr, count(*)
    FROM loan l JOIN branch b ON b.branch_id = l.checkout_branch_id GROUP BY 1, 2$$) AS ms;
RESET max_parallel_workers_per_gather;
\echo 'Reading: parallel workers are not automatically faster. Starting them and merging their results has a cost,'
\echo 'so the gain depends on the machine (CPU cores) and the size of the scan. Always measure, never assume.'

-- =====================================================================
\echo
\echo '#####  EXPERIMENT 5: physical order (correlation) and CLUSTER  #####'
-- =====================================================================
\echo 'Correlation near 1 or -1 = rows stored in that order; near 0 = scattered.'
SELECT attname AS column_name, round(correlation::NUMERIC, 3) AS correlation
FROM pg_stats WHERE tablename = 'loan' AND attname IN ('loaned_at', 'member_id', 'copy_id') ORDER BY attname;

DROP TABLE IF EXISTS exp_loan_c;
CREATE TABLE exp_loan_c AS SELECT * FROM loan;
CREATE INDEX exp_loan_c_member ON exp_loan_c (member_id);
ANALYZE exp_loan_c;
SELECT 'before CLUSTER' AS state, pg_temp.blocks($$SELECT * FROM exp_loan_c WHERE member_id BETWEEN 1000 AND 1100$$) AS pages_touched,
       pg_temp.ms($$SELECT * FROM exp_loan_c WHERE member_id BETWEEN 1000 AND 1100$$) AS ms;
CLUSTER exp_loan_c USING exp_loan_c_member;
ANALYZE exp_loan_c;
SELECT 'after CLUSTER' AS state, pg_temp.blocks($$SELECT * FROM exp_loan_c WHERE member_id BETWEEN 1000 AND 1100$$) AS pages_touched,
       pg_temp.ms($$SELECT * FROM exp_loan_c WHERE member_id BETWEEN 1000 AND 1100$$) AS ms;
\echo 'Reading: when matching rows sit together on disk, far fewer pages are read. CLUSTER is a one-off; new rows are not kept in order.'

-- =====================================================================
\echo
\echo '#####  EXPERIMENT 6: query rewriting (IN subquery versus JOIN)  #####'
-- =====================================================================
\echo 'Two ways to ask: titles written by "Author 777".'
SELECT 'IN (subquery)' AS form, pg_temp.ms($$SELECT title_name FROM title WHERE title_id IN
    (SELECT ta.title_id FROM title_author ta JOIN author a ON a.author_id = ta.author_id WHERE a.full_name = 'Author 777')$$) AS ms;
SELECT 'JOIN' AS form, pg_temp.ms($$SELECT t.title_name FROM title t JOIN title_author ta ON ta.title_id = t.title_id
    JOIN author a ON a.author_id = ta.author_id WHERE a.full_name = 'Author 777'$$) AS ms;
\echo 'Reading: the optimiser flattens the subquery, so both forms get an equivalent plan. Write the clearest form.'

-- =====================================================================
\echo
\echo '#####  EXPERIMENT 7: the price of an index (write cost)  #####'
-- =====================================================================
DROP TABLE IF EXISTS exp_ins_plain, exp_ins_indexed;
CREATE TABLE exp_ins_plain   (LIKE loan INCLUDING DEFAULTS);
CREATE TABLE exp_ins_indexed (LIKE loan INCLUDING DEFAULTS);
CREATE INDEX ON exp_ins_indexed (member_id, loaned_at DESC);
CREATE INDEX ON exp_ins_indexed (copy_id);
CREATE INDEX ON exp_ins_indexed (loaned_at);
CREATE INDEX ON exp_ins_indexed (due_at);

DO $$
DECLARE t0 TIMESTAMPTZ; plain_ms NUMERIC; idx_ms NUMERIC;
BEGIN
    t0 := clock_timestamp();
    INSERT INTO exp_ins_plain SELECT * FROM loan WHERE loan_id <= 200000;
    plain_ms := extract(epoch FROM clock_timestamp() - t0) * 1000;
    t0 := clock_timestamp();
    INSERT INTO exp_ins_indexed SELECT * FROM loan WHERE loan_id <= 200000;
    idx_ms := extract(epoch FROM clock_timestamp() - t0) * 1000;
    RAISE WARNING 'Insert 200,000 rows: no extra indexes = % ms, 4 extra indexes = % ms (%x slower)',
        round(plain_ms), round(idx_ms), round(idx_ms / plain_ms, 1);
END $$;
\echo 'Reading: every index must be updated on each insert. Add only the indexes that queries really use.'

-- ---- clean up ---------------------------------------------------------
DROP INDEX IF EXISTS exp_loan_loaned_at_btree;
DROP TABLE IF EXISTS exp_loan, exp_loan_c, exp_ins_plain, exp_ins_indexed;
\echo
\echo 'All experiments finished; scratch tables removed.'
