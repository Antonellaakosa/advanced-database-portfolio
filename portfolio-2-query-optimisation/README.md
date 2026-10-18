# Portfolio 2 — Query Processing and Optimisation

**Course:** MIT 8103 Advanced Database Systems  |  **Case study:** Unity Public Library Network (UPLN)  |  **DBMS:** PostgreSQL 16

> STATUS: complete. All results below come from my own run in a GitHub Codespace on 18 Oct 2026 (screenshots in `evidence/`, raw output in `results/`).

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
$P -v which=before < 03_explain_plans.sql | tee results/plans_before.txt
$P < 05_create_indexes.sql
$P -v label=after  < 04_run_benchmark.sql
$P -v which=after  < 03_explain_plans.sql | tee results/plans_after.txt
$P < 06_compare_results.sql
$P < 07_extra_experiments.sql | tee results/extra_experiments.txt
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

## 6. Results (my run; median of 5 runs, 1,000,010 loans)
| Query | Before (ms) | After (ms) | Speed-up | Pages read before → after | Plan before → after |
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

Evidence: `evidence/02_baseline_benchmark.png`, `04_after_benchmark.png`, `05_comparison.png`.

Index sizes (`evidence/03_indexes_created.png`):

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

## 7. Analysis
**Why the plans changed.** Before any index existed, the planner had one way to answer most questions: read the
whole table (`Seq Scan`) and discard what did not match. For Q2 the plan shows this directly: `Parallel Seq Scan on loan
... Filter: (member_id = 1500) ... Rows Removed by Filter: 333324`, i.e. about a million rows read to return 10
(`evidence/06_plans_before.png`). Once an index offers a cheaper route, the cost-based planner switches to it. The
number of 8 kB pages read is the clearest measure: Q2 dropped from 10,596 pages to 83.

**Q2, composite index.** `(member_id, loaned_at DESC)` matches both the filter and the sort, so rows come out
already in order and the query stops after 10. No sort step is needed.

**Q4, trigram index.** A normal B-tree is ordered from the first letter, so it cannot help `ILIKE '%database%'`,
where the match can start anywhere. A trigram GIN index splits text into three-letter pieces, which makes the
leading wildcard searchable (79.3 ms to 1.5 ms).

**Q5, covering index.** `INCLUDE (copy_id, barcode, branch_id)` stores every column the query needs inside the
index, so the plan is an `Index Only Scan` and only 4 pages are touched (down from 1,649).

**Q3, an honest finding.** Q3 was already fast (0.892 ms) and I added no index for it, because the Portfolio 1
partial index `uq_one_active_loan_per_copy` (`WHERE returned_at IS NULL`) already serves it. The plan is identical
before and after. The small difference (0.892 vs 0.508 ms) is run-to-run variation, not an improvement, so I do not
claim a speed-up. A design decision in Portfolio 1 had already optimised this query.

**Q6, materialised view.** The yearly report scanned and joined all 1,000,010 loans. The view stores the 40-row
answer, so the query reads one page. The trade-off is freshness: a materialised view is a snapshot and must be
refreshed (`REFRESH MATERIALIZED VIEW CONCURRENTLY`, which is why it has a unique index) when the loans change.

**Q1, smaller gain.** Only 7.7x, because `member` is a small table (about 11 MB). The gain from an index grows with
table size, which is why the 1,000,010-row `loan` table shows the biggest effects.

**Q7, BRIN.** BRIN stores one summary per block range, so the index is only 24 kB. It still reads 386 pages
(a B-tree would read fewer) but is 22x faster than the full scan.

## 8. Extra experiments (`07_extra_experiments.sql`; evidence `08_extra_experiments_a` to `e`)
| # | Experiment | Result | Conclusion |
|---|---|---|---|
| 1 | BRIN vs B-tree on `loaned_at` | B-tree 21 MB, 1.663 ms; BRIN 24 kB, 3.569 ms | BRIN is about 900x smaller and slower by about 2x here. It suits append-only, time-ordered data |
| 2 | Join algorithm (same query) | Optimiser's choice (Hash Join) 34.9 ms; Merge Join forced 68.2 ms; Nested Loop forced 57.8 ms; Hash Join forced 45.0 ms | Forcing a worse algorithm costs 1.7x to 2x. The 45.0 vs 34.9 ms gap is for the same algorithm, so it shows run-to-run noise of about 25% |
| 3 | Estimated vs actual rows | No statistics: estimated 5,361, actual 38 (member 1500); range on 2025: estimated 5,361, actual 134,196. After `ANALYZE`: estimated 23 (actual 38); range estimated 136,277 (actual 134,196) | The planner decides from statistics. Without them its guesses are off by up to 140x |
| 4 | Parallel query on the Q6 report | 0 workers 645.887 ms; 2 workers 641.462 ms | No meaningful gain on this machine. Parallelism has start-up and merge costs, so always measure |
| 5 | Physical order and `CLUSTER` | Correlation: `loaned_at` 1.000, `member_id` -0.014, `copy_id` -0.001. Before `CLUSTER`: 3,889 pages, 3.135 ms. After: 59 pages, 0.987 ms | Rows stored together are read in far fewer pages. `CLUSTER` is a one-off; new rows are not kept in order. High correlation on `loaned_at` is why BRIN works |
| 6 | `IN` subquery vs `JOIN` | 0.036 ms vs 0.030 ms | Equivalent plans: the optimiser flattens the subquery, so write the clearest form |
| 7 | Write cost of indexes | 200,000 inserts: 361 ms with no extra index; 2,151 ms with 4 extra indexes (6.0x slower) | Every index must be updated on every insert. Add only the indexes that queries use |

## 9. Evidence
| File | Shows |
|---|---|
| `evidence/01_data_generated.png` | Row counts and table sizes after data generation |
| `evidence/02_baseline_benchmark.png` | Benchmark before indexes |
| `evidence/03_indexes_created.png` | Indexes and materialised view, with sizes |
| `evidence/04_after_benchmark.png` | Benchmark after indexes |
| `evidence/05_comparison.png` | Before/after table and plan changes |
| `evidence/06_plans_before.png`, `07_plans_after.png` | Execution plans (full text in `results/plans_before.txt`, `plans_after.txt`) |
| `evidence/08_extra_experiments_a.png` to `e.png` | The seven experiments (full text in `results/extra_experiments.txt`) |

Commit history on GitHub shows the work in order: schema, data generator, baseline, indexes and after-results.

## 10. Limitations
- Synthetic data; real distributions differ.
- Timings depend on the machine and cache state; the pattern, not the exact number, is the finding. For example the same
  Q6 query measured 956 ms in the benchmark but about 642 to 646 ms in Experiment 4 (a shared Codespace varies from run
  to run). The speed-ups are large enough that the conclusions are unaffected.
- Experiment 4 (parallel query) gave no gain on this machine. The result may differ on hardware with more cores.
- Materialised view is a snapshot until refreshed.
- Partitioning was considered but rejected: it conflicts with the Portfolio 1 rule that one partial unique index
  enforces "one active loan per copy" (a unique index on a partitioned table must include the partition key).

## 11. Sources
PostgreSQL 16 documentation: EXPLAIN, Indexes (B-tree, GIN, BRIN), pg_trgm, Materialized Views, Planner statistics, CLUSTER. MIT 8103 lesson notes (query processing and optimisation). Full reference list is in the final documentation.
