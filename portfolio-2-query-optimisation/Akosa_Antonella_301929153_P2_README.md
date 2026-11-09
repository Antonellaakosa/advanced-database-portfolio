# Portfolio 2 — Query Processing and Optimisation

**Course:** MIT 8103 Advanced Database Systems  |  **Case study:** Unity Public Library Network (UPLN)  |  **DBMS:** PostgreSQL 16

> **Status:** Complete. I recorded the benchmark and performance experiment results in my GitHub Codespace on 18 October 2026. I ran the additional query-result verification on 2 November 2026. I kept screenshots in `evidence/` and raw output in `results/`.

## 1. Aim and Scope

I tested how PostgreSQL processes common library queries and measured how indexes, query structure, statistics, physical row order and pre-computed summaries affect performance. I used execution plans and query timings to explain the changes I measured.

## 2. Test Database and Dataset

I used a separate `upln_perf` database to keep the Portfolio 1 evidence unchanged. `Akosa_Antonella_301929153_P2_01_generate_data.sql` populated it using the Portfolio 1 schema, with synthetic data and `setseed` for reproducibility.

| Table | Rows (approx.) |
|---|---|
| member | 50,000 |
| title / author / title_author | 100,000 / 20,010 / 110,000 |
| copy | 150,019 |
| **loan** | **1,000,010** |
| fine / payment | 130,962 / 91,886 |

Small tables can be faster to scan than to access through an index, so I used larger tables to make optimisation differences measurable. I retained the primary-key, unique and partial unique indexes from Portfolio 1, but added no new performance indexes before the baseline.

## 3. Benchmark Method

1. I used nine library queries stored in `bench_queries` (`Akosa_Antonella_301929153_P2_02_benchmark_harness.sql`).
2. `bench_run()` ran each query once to warm the cache, then **5 times** using `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`. I recorded the **median** execution time to limit one-off variation, along with the scan/join types and buffer pages touched in the last timed run.
3. I benchmarked **before** adding the performance indexes, created them with `Akosa_Antonella_301929153_P2_05_create_indexes.sql`, then benchmarked **after**.
4. I saved full execution plans with `Akosa_Antonella_301929153_P2_03_explain_plans.sql` for both stages.

## 4. Implementation and Test Execution

I ran the following commands from the repository root in my Codespace:

```bash
# one-off: create the separate database and load the Portfolio 1 schema and sample rows
docker compose -f Akosa_Antonella_301929153_docker-compose.yml exec -T postgres psql -U library_admin -d postgres -c "CREATE DATABASE upln_perf"
P="docker compose -f Akosa_Antonella_301929153_docker-compose.yml exec -T postgres psql -U library_admin -d upln_perf -v ON_ERROR_STOP=1"
$P < portfolio-1-database-design/Akosa_Antonella_301929153_P1_01_schema.sql
$P < portfolio-1-database-design/Akosa_Antonella_301929153_P1_02_sample_data.sql
cd portfolio-2-query-optimisation
$P < Akosa_Antonella_301929153_P2_01_generate_data.sql            # about 1 to 3 minutes (add -v scale=0.1 for a 10% size test)
$P < Akosa_Antonella_301929153_P2_02_benchmark_harness.sql
$P -v label=before < Akosa_Antonella_301929153_P2_04_run_benchmark.sql
$P -v which=before < Akosa_Antonella_301929153_P2_03_explain_plans.sql | tee results/Akosa_Antonella_301929153_P2_plans_before.txt
$P < Akosa_Antonella_301929153_P2_05_create_indexes.sql
$P -v label=after  < Akosa_Antonella_301929153_P2_04_run_benchmark.sql
$P -v which=after  < Akosa_Antonella_301929153_P2_03_explain_plans.sql | tee results/Akosa_Antonella_301929153_P2_plans_after.txt
$P < Akosa_Antonella_301929153_P2_06_compare_results.sql
$P < Akosa_Antonella_301929153_P2_07_extra_experiments.sql | tee results/Akosa_Antonella_301929153_P2_extra_experiments.txt
$P < Akosa_Antonella_301929153_P2_08_query_results.sql | tee results/Akosa_Antonella_301929153_P2_query_results.txt
```

The `before` and `after` labels identify the benchmark runs. I compared them with `Akosa_Antonella_301929153_P2_06_compare_results.sql`, then ran `Akosa_Antonella_301929153_P2_07_extra_experiments.sql`. Finally, `Akosa_Antonella_301929153_P2_08_query_results.sql` prints each query's SQL and the rows it returns, and checks that the optimised versions return the same rows.

## 5. Queries and Optimisation Techniques

I tested nine queries covering searches, loans, availability, reports and fines. The table records the index or technique used for each.

| # | Query | Index / technique used | Why |
|---|---|---|---|
| Q1 | Members by surname | B-tree `idx_member_last_name` | Equality lookup on a selective column |
| Q2 | A member's 10 latest loans | Composite `(member_id, loaned_at DESC)` | Index order matches filter + sort, so no sort step and early stop at LIMIT 10 |
| Q3 | 100 oldest overdue loans | *No new index (deliberate)* | The Portfolio 1 partial index `uq_one_active_loan_per_copy` (`WHERE returned_at IS NULL`) already serves it |
| Q4 | Keyword search `ILIKE '%database%'` | Trigram GIN `gin_trgm_ops` | A B-tree cannot help a leading wildcard |
| Q5 | Available copies of a title | Covering index `(title_id, status) INCLUDE (...)` | Index-only scan: the table is never read |
| Q6 | Loans per city per year | Materialised view `mv_loans_by_city_year` | Pre-computes a heavy aggregate |
| Q7 | Loans in one month | BRIN on `loaned_at` | Time column is stored in order; index is only kilobytes |
| Q8 | Titles by an author | B-tree on `author.full_name` and `title_author.author_id` | Join keys on the many side |
| Q9 | Outstanding fines of a member | B-tree `payment.fine_id` (plus Q2 index) | Speeds the join chain |

### What the queries return

The benchmark measures speed, so I also checked what each query returns. [`Akosa_Antonella_301929153_P2_08_query_results.sql`](Akosa_Antonella_301929153_P2_08_query_results.sql) prints the SQL, the first rows and the total row count for all nine queries. Three of the statements are shown here; the other six are in [`Akosa_Antonella_301929153_P2_02_benchmark_harness.sql`](Akosa_Antonella_301929153_P2_02_benchmark_harness.sql).

```sql
-- Q2: a member's 10 most recent loans
SELECT l.loan_id, t.title_name, l.loaned_at, l.returned_at
FROM loan l JOIN copy c ON c.copy_id = l.copy_id JOIN title t ON t.title_id = c.title_id
WHERE l.member_id = 1500 ORDER BY l.loaned_at DESC LIMIT 10;

-- Q5: copies of title 4242 that can be borrowed now
SELECT copy_id, barcode, branch_id FROM copy WHERE title_id = 4242 AND status = 'available';

-- Q9: what member 1500 still owes
SELECT f.fine_id, f.amount, COALESCE(SUM(p.amount), 0) AS paid,
       f.amount - COALESCE(SUM(p.amount), 0) AS outstanding
FROM loan l JOIN fine f ON f.loan_id = l.loan_id
            LEFT JOIN payment p ON p.fine_id = f.fine_id
WHERE l.member_id = 1500 AND NOT f.waived
GROUP BY f.fine_id, f.amount
HAVING f.amount - COALESCE(SUM(p.amount), 0) > 0;
```

For example, Q9 returned two rows in my run:

| fine_id | amount | paid | outstanding |
|---|---|---|---|
| 114476 | 75.00 | 0 | 75.00 |
| 124775 | 25.00 | 0 | 25.00 |

I used `Akosa_Antonella_301929153_P2_08_query_results.sql` to check that the optimised queries returned the same results under two planner configurations. I ran each query with normal planning and again with index-based scan methods discouraged through planner settings. The indexes remained in the database for both runs, so this was a comparison of query results rather than a repeat of the original pre-index benchmark. I compared fingerprints of the complete result sets without considering row order. For Q6, I also compared the materialised view with the original aggregate query. All nine comparisons returned identical rows.

| Query | Rows returned | Same rows under both planner configurations |
|---|---|---|
| Q1 Members by surname | 777 | identical |
| Q2 Member's recent loans | 10 | identical |
| Q3 Overdue loans | 100 | identical |
| Q4 Keyword search | 1,273 | identical |
| Q5 Available copies | 3 | identical |
| Q6 Loans per city per year | 40 | identical (the summary view also matches the original query) |
| Q7 Loans in one month | 1 | identical |
| Q8 Titles by an author | 6 | identical |
| Q9 Member's outstanding fines | 2 | identical |

This shows that the faster plans return the same data for these nine queries. It is a check on my own queries, not a general proof. Evidence: `evidence/Akosa_Antonella_301929153_P2_09_query_results.png` and the full output in `results/Akosa_Antonella_301929153_P2_query_results.txt`.

## 6. Benchmark Results

These are my **median execution times from 5 runs**, using **1,000,010 loans**. The **Buffer pages touched** column is the total number of 8 kB shared buffer pages touched in the last timed run, calculated as `Shared Hit Blocks + Shared Read Blocks` from `EXPLAIN (ANALYZE, BUFFERS)`. It includes pages already in memory, not just physical disk reads.

| Query | Before (ms) | After (ms) | Speed-up | Buffer pages touched before → after | Plan before → after |
|---|---|---|---|---|---|
| Q1 Members by surname | 2.783 | 0.363 | 7.7x | 788 → 507 | Seq Scan → Bitmap Index Scan |
| Q2 Member's recent loans | 50.255 | 0.045 | 1,116.8x | 10,596 → 83 | Parallel Seq Scan on `loan` → Index Scan |
| Q3 Overdue loans | 0.892 | 0.508 | 1.8x (noise) | 30 → 30 | Same plan: P1 partial index |
| Q4 Keyword search | 79.334 | 1.513 | 52.4x | 1,378 → 860 | Seq Scan → Bitmap Index Scan (trigram) |
| Q5 Available copies | 7.001 | 0.005 | 1,400.2x | 1,649 → 4 | Seq Scan → Index Only Scan |
| Q6 Loans per city per year | 956.283 | 0.019 | 50,330.7x | 10,311 → 1 | Hash Join over `loan` → Seq Scan of a 40-row view |
| Q7 Loans in one month | 73.275 | 3.336 | 22.0x | 10,310 → 386 | Seq Scan → Bitmap Scan (BRIN) |
| Q8 Titles by an author | 13.326 | 0.028 | 475.9x | 731 → 29 | Seq Scans → Index Scans |
| Q9 Member's outstanding fines | 84.624 | 0.126 | 671.6x | 11,245 → 173 | Seq Scans → Index and Bitmap Scans |

Evidence: `evidence/Akosa_Antonella_301929153_P2_02_baseline_benchmark.png`, `Akosa_Antonella_301929153_P2_04_after_benchmark.png`, `Akosa_Antonella_301929153_P2_05_comparison.png`.

Index sizes (`evidence/Akosa_Antonella_301929153_P2_03_indexes_created.png`):

| Index | Table | Size |
|---|---|---|
| `idx_loan_member_loaned_at` | loan | 30 MB |
| `idx_copy_title_status` | copy | 8,640 kB |
| `idx_title_name_trgm` | title | 7,352 kB |
| `idx_payment_fine` | payment | 2,032 kB |
| `idx_title_author_author` | title_author | 1,240 kB |
| `idx_author_full_name` | author | 632 kB |
| `idx_member_last_name` | member | 376 kB |
| `idx_loan_loaned_at_brin` | loan | 24 kB |
| `uq_mv_loans_city_year` (on the materialised view) | mv_loans_by_city_year | 16 kB |

## 7. Execution Plan and Performance Analysis

**Changes in execution plans.** Before I added performance indexes, many queries used sequential scans (`Seq Scan`). For Q2, the plan recorded `Parallel Seq Scan on loan ... Filter: (member_id = 1500) ... Rows Removed by Filter: 333324`—about a million rows examined to return 10 (`evidence/Akosa_Antonella_301929153_P2_06_plans_before.png`). After indexing, PostgreSQL used an index scan and the number of 8 kB pages touched fell from 10,596 to 83.

**Q2 — Composite index.** `(member_id, loaned_at DESC)` matches the filter and sort order, so PostgreSQL returned the latest 10 loans without a separate sort.

**Q4 — Trigram index.** A B-tree cannot help a leading-wildcard search such as `ILIKE '%database%'`, where the match may start anywhere. A trigram GIN index supported the search, reducing the time from 79.3 ms to 1.5 ms.

**Q5 — Covering index.** `INCLUDE (copy_id, barcode, branch_id)` stores the columns needed by the query in the index. I prepared the data with `VACUUM (ANALYZE)` before using the index. The plan changed to an `Index Only Scan` with `Heap Fetches: 0`, confirming that it did not fetch rows from the table heap in that run. It touched 4 buffer pages in total rather than 1,649.

**Q3 — Existing partial index.** I added no index for this query because the Portfolio 1 partial index `uq_one_active_loan_per_copy` (`WHERE returned_at IS NULL`) already served it. The plan was unchanged. I treat the difference from 0.892 ms to 0.508 ms as run-to-run variation, not an indexing gain.

**Q6 — Materialised view.** The annual report scanned and joined all 1,000,010 loans. The materialised view stores the 40-row result, reducing the query to one page. The 956.283 ms to 0.019 ms comparison measures reading a pre-computed summary; it excludes the cost of refreshing it. The view is a snapshot until refreshed with `REFRESH MATERIALIZED VIEW CONCURRENTLY`, supported by its unique index.

**Q1 — Member surname lookup.** The 7.7x gain was smaller because `member` is a relatively small table (about 11 MB). The larger `loan` table showed greater improvements.

**Q7 — BRIN index.** BRIN stores one summary per block range, so the index is only 24 kB. The query still touched 386 pages but ran 22x faster than the full scan. Experiment 1 compares its size and speed with a B-tree.

## 8. Additional Performance Experiments

I used `Akosa_Antonella_301929153_P2_07_extra_experiments.sql` to test index size, join algorithms, statistics, parallelism, physical order and write costs.

| # | Experiment | Result | Conclusion |
|---|---|---|---|
| 1 | BRIN vs B-tree on `loaned_at` | B-tree 21 MB, 1.663 ms; BRIN 24 kB, 3.569 ms | BRIN is about 900x smaller and slower by about 2x here. It suits append-only, time-ordered data |
| 2 | Join algorithm (same query) | Optimiser's choice (Hash Join) 34.9 ms; Merge Join forced 68.2 ms; Nested Loop forced 57.8 ms; Hash Join forced 45.0 ms | Forcing a worse algorithm costs 1.7x to 2x. The 45.0 vs 34.9 ms gap is for the same algorithm, so it shows run-to-run noise of about 29% |
| 3 | Estimated vs actual rows | No statistics: estimated 5,361, actual 38 (member 1500); range on 2025: estimated 5,361, actual 134,196. After `ANALYZE`: estimated 23 (actual 38); range estimated 136,277 (actual 134,196) | The planner decides from statistics. Without them its guesses are off by up to 140x |
| 4 | Parallel query on the Q6 report | 0 workers 645.887 ms; 2 workers 641.462 ms | No meaningful gain on this machine. Parallelism has start-up and merge costs, so always measure |
| 5 | Physical order and `CLUSTER` | Correlation: `loaned_at` 1.000, `member_id` -0.014, `copy_id` -0.001. Before `CLUSTER`: 3,889 pages, 3.135 ms. After: 59 pages, 0.987 ms | Rows stored together are read in far fewer pages. `CLUSTER` is a one-off; new rows are not kept in order. High correlation on `loaned_at` is why BRIN works |
| 6 | `IN` subquery vs `JOIN` | 0.036 ms vs 0.030 ms | Equivalent plans: the optimiser flattens the subquery, so write the clearest form |
| 7 | Write cost of indexes | 200,000 inserts: 361 ms with no extra index; 2,151 ms with 4 extra indexes (6.0x slower) | Every index must be updated on every insert. Add only the indexes that queries use |

## 9. Supporting Evidence

| File | Shows |
|---|---|
| `evidence/Akosa_Antonella_301929153_P2_01_data_generated.png` | Row counts and table sizes after data generation |
| `evidence/Akosa_Antonella_301929153_P2_02_baseline_benchmark.png` | Benchmark before indexes |
| `evidence/Akosa_Antonella_301929153_P2_03_indexes_created.png` | Indexes and materialised view, with sizes |
| `evidence/Akosa_Antonella_301929153_P2_04_after_benchmark.png` | Benchmark after indexes |
| `evidence/Akosa_Antonella_301929153_P2_05_comparison.png` | Before/after table and plan changes |
| `evidence/Akosa_Antonella_301929153_P2_06_plans_before.png`, `Akosa_Antonella_301929153_P2_07_plans_after.png` | Execution plans (full text in `results/Akosa_Antonella_301929153_P2_plans_before.txt`, `Akosa_Antonella_301929153_P2_plans_after.txt`) |
| `evidence/Akosa_Antonella_301929153_P2_08_extra_experiments_a.png` to `evidence/Akosa_Antonella_301929153_P2_08_extra_experiments_e.png` | The seven experiments (full text in `results/Akosa_Antonella_301929153_P2_extra_experiments.txt`) |
| `evidence/Akosa_Antonella_301929153_P2_09_query_results.png` | Query results and the result-equivalence check recorded on 2 November 2026 (full text in `results/Akosa_Antonella_301929153_P2_query_results.txt`) |

Commit history on GitHub shows the work in stages: project setup, the data generator with the baseline results, the after-index results with the extra experiments, the README, and the query-result check.

## 10. Limitations

- **Synthetic data.** Real distributions may differ from the generated data.
- **Machine and cache effects.** Timings vary with machine and cache state. Q6 measured 956 ms in the benchmark but about 642 to 646 ms in Experiment 4. I focus on the pattern and plan changes rather than a single timing.
- **Parallel query result.** Experiment 4 showed no meaningful improvement on this machine; hardware with more cores may behave differently.
- **Materialised view freshness.** The summary is a snapshot until refreshed; the query timing excludes refresh costs.
- **Partitioning.** I considered but rejected it because unique indexes on partitioned tables must include the partition key, conflicting with Portfolio 1's one-active-loan-per-copy partial index.

## 11. References

- MIVA Open University (2025). *MIT 8103 Advanced Database Systems*, Live Lesson II: Query optimization and file organization; Caching strategies and materialized views. Lecture slides.
- PostgreSQL Global Development Group (n.d.). *PostgreSQL 16 Documentation: Using EXPLAIN*. https://www.postgresql.org/docs/16/using-explain.html
- PostgreSQL Global Development Group (n.d.). *PostgreSQL 16 Documentation: EXPLAIN*. https://www.postgresql.org/docs/16/sql-explain.html
- PostgreSQL Global Development Group (n.d.). *PostgreSQL 16 Documentation: Index Types* (B-tree, GIN and BRIN). https://www.postgresql.org/docs/16/indexes-types.html
- PostgreSQL Global Development Group (n.d.). *PostgreSQL 16 Documentation: Partial Indexes*. https://www.postgresql.org/docs/16/indexes-partial.html
- PostgreSQL Global Development Group (n.d.). *PostgreSQL 16 Documentation: Index-Only Scans and Covering Indexes*. https://www.postgresql.org/docs/16/indexes-index-only-scans.html
- PostgreSQL Global Development Group (n.d.). *PostgreSQL 16 Documentation: pg_trgm — Support for Similarity of Text Using Trigram Matching*. https://www.postgresql.org/docs/16/pgtrgm.html
- PostgreSQL Global Development Group (n.d.). *PostgreSQL 16 Documentation: Materialized Views*. https://www.postgresql.org/docs/16/rules-materializedviews.html
- PostgreSQL Global Development Group (n.d.). *PostgreSQL 16 Documentation: Query Planning*. https://www.postgresql.org/docs/16/runtime-config-query.html
- PostgreSQL Global Development Group (n.d.). *PostgreSQL 16 Documentation: Statistics Used by the Planner*. https://www.postgresql.org/docs/16/planner-stats.html
- PostgreSQL Global Development Group (n.d.). *PostgreSQL 16 Documentation: CLUSTER*. https://www.postgresql.org/docs/16/sql-cluster.html
- PostgreSQL Global Development Group (n.d.). *PostgreSQL 16 Documentation: VACUUM*. https://www.postgresql.org/docs/16/sql-vacuum.html
