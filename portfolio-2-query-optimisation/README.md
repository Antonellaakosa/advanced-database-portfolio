# Portfolio 2 — Query Processing and Optimisation

**Course:** MIT 8103 Advanced Database Systems  |  **Case study:** Unity Public Library Network (UPLN)  |  **DBMS:** PostgreSQL 16

> STATUS: scripts complete. Results and analysis sections (marked **TODO**) are completed from my own run.

## 1. Aim
Show, with measurements, how PostgreSQL processes queries and how design choices (indexes, query form,
statistics, physical order, pre-computed summaries) change speed. Every claim below is backed by an
execution plan or a timing produced by the scripts in this folder.

## 2. Test database
A separate database `upln_perf` (so the Portfolio 1 evidence stays untouched) is filled by
`01_generate_data.sql` using the Portfolio 1 schema. Data is synthetic and reproducible (`setseed`).

| Table | Rows (approx.) |
|---|---|
| member | 50,000 |
| title / author / title_author | 100,000 / 20,010 / 110,000 |
| copy | 150,019 |
| **loan** | **1,000,010** |
| fine / payment | 130,962 / 91,886 |

Why this size: on a few dozen rows every plan looks the same, because scanning everything is cheapest.
Optimisation differences only appear at scale. No secondary indexes exist at the start on purpose.

## 3. Method
1. Nine realistic library queries are stored in `bench_queries` (`02_benchmark_harness.sql`).
2. `bench_run()` runs each query once to warm the cache, then 5 times under
   `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` and stores the **median** execution time, the pages touched,
   and the scan/join types used. The median avoids one-off noise.
3. Benchmark **before** indexes, create indexes (`05_create_indexes.sql`), benchmark **after**, compare.
4. Full plans are saved with `03_explain_plans.sql` as evidence.

## 4. How to run (Codespace)
```bash
# one-off: create the separate database and load the Portfolio 1 schema and sample rows
docker compose exec -T postgres psql -U library_admin -d postgres -c "CREATE DATABASE upln_perf"
P="docker compose exec -T postgres psql -U library_admin -d upln_perf -v ON_ERROR_STOP=1"
$P < portfolio-1-database-design/01_schema.sql
$P < portfolio-1-database-design/02_sample_data.sql
cd portfolio-2-query-optimisation
$P < 01_generate_data.sql            # about 1 to 3 minutes (add -v scale=0.1 for a 10% size test)
$P < 02_benchmark_harness.sql
$P -v label=before < 04_run_benchmark.sql
$P < 03_explain_plans.sql -v which=before   # optional: full plans
$P < 05_create_indexes.sql
$P -v label=after  < 04_run_benchmark.sql
$P < 03_explain_plans.sql -v which=after
$P < 06_compare_results.sql
$P < 07_extra_experiments.sql
```

## 5. Queries and indexes
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

## 6. Results (TODO: paste from my own run of `06_compare_results.sql`)
| Query | Before (ms) | After (ms) | Speed-up | Scan type before → after |
|---|---|---|---|---|
| Q1 | | | | |
| Q2 | | | | |
| Q3 | | | | |
| Q4 | | | | |
| Q5 | | | | |
| Q6 | | | | |
| Q7 | | | | |
| Q8 | | | | |
| Q9 | | | | |

Index sizes (from `05_create_indexes.sql`): TODO.

## 7. Analysis (TODO: completed after my run, in my own words)
Points to cover, each tied to a plan in `evidence/`:
- Sequential scan → index scan / bitmap scan / index-only scan, and why the planner switches.
- Q2: how a composite index removes the sort. Q4: why a B-tree fails on `%word%`. Q5: what "Heap Fetches: 0" means.
- Q3: the honest finding that a Portfolio 1 design decision already optimised the query.
- Q6: a materialised view trades freshness (must be refreshed) for speed.
- Cost of indexes: storage, plus slower writes (experiment 7).

## 8. Extra experiments (`07_extra_experiments.sql`)
1. BRIN vs B-tree size and speed. 2. Hash vs merge vs nested-loop join. 3. Estimated vs actual rows, before/after `ANALYZE`.
4. Parallel query. 5. Physical order (`pg_stats.correlation`) and `CLUSTER`. 6. `IN` subquery vs `JOIN` rewrite.
7. Write cost of extra indexes. Results and conclusions: TODO.

## 9. Evidence
Screenshots and saved outputs in `evidence/` and `results/` (TODO list after run).

## 10. Limitations
- Synthetic data; real distributions differ.
- Timings depend on the machine and cache state; the pattern, not the exact number, is the finding.
- Materialised view is a snapshot until refreshed.
- Partitioning was considered but rejected: it conflicts with the Portfolio 1 rule that one partial unique index
  enforces "one active loan per copy" (a unique index on a partitioned table must include the partition key).

## 11. Sources
PostgreSQL 16 documentation: EXPLAIN, Indexes (B-tree, GIN, BRIN), pg_trgm, Materialized Views, Planner statistics, CLUSTER. MIT 8103 lesson notes (query processing and optimisation). TODO: final reference list.
