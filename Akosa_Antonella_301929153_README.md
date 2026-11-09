# Advanced Database Systems: Individual Practical Database Portfolio

**Course:** MIT 8103 Advanced Database Systems, MIVA Open University (Master of Information Technology)  
**Name:** Antonella Akosa  
**Student ID:** 301929153  
**Case study:** Unity Public Library Network (UPLN), a fictional Nigerian public library network  
**Database systems:** PostgreSQL 16 and MongoDB 7

This repository contains my five practical portfolio activities for MIT 8103. I used the same UPLN case study to examine relational database design, query optimisation, transactions and concurrency, NoSQL data models, and distributed database operations. Each portfolio includes implementation scripts, tests, recorded results and supporting evidence, with a separate README explaining the activity in detail.

My aim was to apply advanced database concepts to problems that could arise in a multi-branch library system: maintaining accurate records, preventing conflicting transactions, retrieving information efficiently, choosing suitable data models and recovering from failures. I used synthetic data and laboratory environments throughout. The results demonstrate the behaviour observed in my tests; they do not represent a production deployment of UPLN.

## Contents

1. [Project Objectives and Scope](#1-project-objectives-and-scope)
2. [Case Study and Database Requirements](#2-case-study-and-database-requirements)
3. [Technical Environment and Implementation Architecture](#3-technical-environment-and-implementation-architecture)
4. [Repository Structure and Navigation](#4-repository-structure-and-navigation)
5. [Portfolio Implementation and Technical Analysis](#5-portfolio-implementation-and-technical-analysis)
6. [Integration of Advanced Database Concepts](#6-integration-of-advanced-database-concepts)
7. [Testing Methodology and Results Verification](#7-testing-methodology-and-results-verification)
8. [Supporting Evidence and Assessment Traceability](#8-supporting-evidence-and-assessment-traceability)
9. [Reproducing the Portfolio Activities](#9-reproducing-the-portfolio-activities)
10. [Implementation Limitations and Production Considerations](#10-implementation-limitations-and-production-considerations)
11. [Individual Technical Reflection](#11-individual-technical-reflection)
12. [Declaration of AI Use](#12-declaration-of-ai-use)
13. [References](#13-references)

## 1. Project Objectives and Scope

I organised the work around five related objectives:

1. **Relational design and integrity:** Model library operations in PostgreSQL, implement database-enforced business rules and test security and privacy controls.
2. **Query processing and optimisation:** Measure how execution plans, indexes, statistics and data organisation affect query performance without changing the intended query results.
3. **Transactions and concurrency:** Reproduce conflicting operations, examine isolation behaviour and test mechanisms that protect data integrity when sessions run concurrently.
4. **NoSQL modelling:** Evaluate document, key-value, wide-column and graph models against specific UPLN access patterns, using MongoDB for the practical demonstrations.
5. **Distributed and cloud database concepts:** Implement and test replication, branch-based sharding, failover, secure connections, backup and point-in-time recovery in a multi-instance PostgreSQL laboratory.

I assessed each objective through executable operations rather than relying only on descriptions of database concepts. Where a test had a limited scope, I have stated that limitation. The individual portfolio READMEs provide the full scripts, test procedures, results and screenshots referenced below.

## 2. Case Study and Database Requirements

**Unity Public Library Network (UPLN)** is a fictional public library system with its headquarters in Abuja and branches in Lagos, Port Harcourt, Kano and Enugu. The branches share a catalogue. Members can borrow and return physical copies at different branches; staff also manage reservations, transfers, fines and payments. All names, identifying details and transactions used in the portfolio are synthetic. Monetary values are expressed in Nigerian naira (NGN).

| Aspect | UPLN requirements |
|---|---|
| Users | Members, librarians, branch managers and headquarters administrators |
| Catalogue | Titles, authors, publishers, categories and physical copies held at different branches |
| Circulation | Membership, loans, returns, reservations and transfers between branches |
| Financial records | Fines, payment instalments and outstanding balances |
| Operational reporting | Catalogue searches, branch activity, borrowing patterns and fine balances |
| Data protection | Appropriate access restrictions, audit records and protection of sensitive member information |

These operations create database problems that cannot be addressed by table creation alone:

| Computing problem | Database requirement | Portfolio |
|---|---|---|
| One physical copy must not have two active loans | Relational constraints, uniqueness and concurrency controls | 1 and 3 |
| A member or title must remain identifiable across related records | Primary keys, foreign keys, normalisation and referential integrity | 1 |
| Staff need timely answers from larger operational datasets | Query plans, appropriate indexes and measured optimisation | 2 |
| Two cashiers may update the same fine balance | Transactions, locking and correct concurrent validation | 1 and 3 |
| Catalogue pages combine related information and different media formats | Data-model selection, embedding, referencing and schema validation | 4 |
| Individual database instances or shards may become unavailable | Replication, failover, fault handling, backup and recovery | 5 |

The scenario provides a consistent basis for comparing different techniques. For example, Portfolio 1 establishes the one-active-loan-per-copy rule, while Portfolio 3 tests its behaviour during simultaneous borrowing attempts. Portfolio 4 evaluates a different representation of selected catalogue data without claiming that the transactional records have been migrated to MongoDB in a production system.

## 3. Technical Environment and Implementation Architecture

I ran the activities in a **GitHub Codespace** using Docker-based database environments. PostgreSQL 16 supports the relational, performance, concurrency and distributed-database activities; MongoDB 7 supports the NoSQL activity. I executed the SQL, shell and JavaScript scripts, checked their recorded output and captured screenshots of my runs.

| Environment | Purpose | Scope |
|---|---|---|
| PostgreSQL database `upln` | Core schema, sample data, constraints and security tests | Portfolio 1 |
| PostgreSQL database `upln_perf` | Generated performance dataset and query benchmarks | Portfolio 2 |
| PostgreSQL database `upln_tx` | Transaction and concurrent-session tests | Portfolio 3 |
| MongoDB database `upln_nosql` | Catalogue documents and NoSQL modelling examples | Portfolio 4 |
| Four PostgreSQL server instances | Primary/coordinator, read-only replica and two branch-based shards | Portfolio 5 |
| Temporary PostgreSQL recovery instance | Separate point-in-time recovery test | Portfolio 5 |

The environments are connected by a common case study, not by an always-running application spanning every portfolio. Portfolios 2 and 3 use separate test databases so their experiments do not overwrite Portfolio 1's recorded evidence. Portfolio 4 exports catalogue data from the relational database for its migration and reconciliation exercises. Portfolio 5 uses its own PostgreSQL cluster to examine distributed behaviour.

```text
                          UPLN case study
                                 |
                   Portfolio 1: PostgreSQL upln
                    relational model and data
                     /          |          \
                    /           |           \
     Portfolio 2: upln_perf  Portfolio 3: upln_tx  Portfolio 4: MongoDB
     generated benchmark     transactional tests   catalogue export and
     data and query plans    and concurrency       NoSQL model examples

     Portfolio 5: separate four-instance PostgreSQL laboratory
     primary/coordinator + replica + two branch-based shards
     (plus a temporary instance for the recovery drill)
```

The diagram describes the relationship between the practical activities. It does not imply that the PostgreSQL and MongoDB environments formed one deployed production application.

## 4. Repository Structure and Navigation

```text
advanced-database-portfolio/
├── Akosa_Antonella_301929153_README.md           this overview
├── Akosa_Antonella_301929153_docker-compose.yml  PostgreSQL 16 for Portfolios 1-3
├── portfolio-1-database-design/                  schema, ER model, constraints and security
├── portfolio-2-query-optimisation/               generated data, benchmarks, plans and results
├── portfolio-3-transactions-concurrency/         transaction and concurrent-session tests
├── portfolio-4-nosql/                            MongoDB catalogue and NoSQL models
└── portfolio-5-distributed-cloud/                PostgreSQL replication, sharding and recovery
```

| Portfolio | Detailed documentation | Main implementation and evidence |
|---|---|---|
| 1. Database Design and Modelling | [Portfolio 1 README](portfolio-1-database-design/Akosa_Antonella_301929153_P1_README.md) | [`Akosa_Antonella_301929153_P1_01_schema.sql`](portfolio-1-database-design/Akosa_Antonella_301929153_P1_01_schema.sql), [ER diagram](portfolio-1-database-design/Akosa_Antonella_301929153_P1_er_diagram.png), [`evidence/`](portfolio-1-database-design/evidence/) |
| 2. Query Processing and Optimisation | [Portfolio 2 README](portfolio-2-query-optimisation/Akosa_Antonella_301929153_P2_README.md) | [`Akosa_Antonella_301929153_P2_02_benchmark_harness.sql`](portfolio-2-query-optimisation/Akosa_Antonella_301929153_P2_02_benchmark_harness.sql), [`Akosa_Antonella_301929153_P2_08_query_results.sql`](portfolio-2-query-optimisation/Akosa_Antonella_301929153_P2_08_query_results.sql), [`results/`](portfolio-2-query-optimisation/results/) |
| 3. Transactions and Concurrency | [Portfolio 3 README](portfolio-3-transactions-concurrency/Akosa_Antonella_301929153_P3_README.md) | [`Akosa_Antonella_301929153_P3_07_run_all_tests.sh`](portfolio-3-transactions-concurrency/Akosa_Antonella_301929153_P3_07_run_all_tests.sh), [`evidence/`](portfolio-3-transactions-concurrency/evidence/) |
| 4. NoSQL and Advanced Data Models | [Portfolio 4 README](portfolio-4-nosql/Akosa_Antonella_301929153_P4_README.md) | [`Akosa_Antonella_301929153_P4_11_other_nosql_models.js`](portfolio-4-nosql/Akosa_Antonella_301929153_P4_11_other_nosql_models.js), [`Akosa_Antonella_301929153_P4_10_run_all_tests.sh`](portfolio-4-nosql/Akosa_Antonella_301929153_P4_10_run_all_tests.sh), [`evidence/`](portfolio-4-nosql/evidence/) |
| 5. Distributed and Cloud Databases | [Portfolio 5 README](portfolio-5-distributed-cloud/Akosa_Antonella_301929153_P5_README.md) | [`Akosa_Antonella_301929153_P5_08_run_all_tests.sh`](portfolio-5-distributed-cloud/Akosa_Antonella_301929153_P5_08_run_all_tests.sh), [`Akosa_Antonella_301929153_P5_09_monitor.sh`](portfolio-5-distributed-cloud/Akosa_Antonella_301929153_P5_09_monitor.sh), [`evidence/`](portfolio-5-distributed-cloud/evidence/) |

The portfolio READMEs are the authoritative locations for complete execution sequences and detailed limitations. Each portfolio also contains screenshots of the tests I ran; the portfolios with saved raw outputs include a `results/` directory.

## 5. Portfolio Implementation and Technical Analysis

### 5.1 Portfolio 1 — Relational Database Design and Modelling

**Problem and design.** UPLN needs to represent titles separately from their physical copies, retain borrowing history and link loans, members, staff, branches, fines and payments without creating inconsistent records. I implemented the relational foundation in PostgreSQL 16 using **15 core tables** and two additional tables for audit logging and encrypted member identity, giving **17 tables** in total. The schema uses primary and foreign keys, unique and check constraints, and a junction table (`title_author`) for the many-to-many relationship between titles and authors.

**Application of relational concepts.** I examined normalisation through the anomalies that would arise if member, membership, catalogue and borrowing facts were kept together. Separating membership rules into `membership_type`, publisher attributes into `publisher`, and titles from physical copies reduces repetition and the risk of inconsistent updates. My README discusses 1NF, 2NF, 3NF and BCNF. I do not present the BCNF discussion as a formal proof that every table satisfies every possible functional dependency.

The partial unique index `uq_one_active_loan_per_copy`, defined for loans where `returned_at IS NULL`, permits historical loans while preventing more than one active loan for a particular copy. Another partial unique index enforces **at most one** headquarters branch; it does not require a headquarters row to exist. These are examples of putting business rules in the database rather than depending entirely on an application check.

**Security and operational controls.** I implemented role-based permissions, column-level restrictions, row-level security (RLS), privacy-preserving views, authentication tests, an audit trail and encryption of synthetic identity numbers. The fine-payment guard uses a row-level lock to validate payments against the outstanding fine balance. My SQL injection exercise compares unsafe query construction with parameterised execution and demonstrates the effect of least-privilege permissions. The RLS test uses a session member identifier to filter rows; it does not prove that an untrusted user cannot change that identifier in a production application.

**Tests and interpretation.** The recorded results include **18 integrity tests**, **14 permission tests**, **18 audit tests**, **6 fine-payment tests** and **10 encryption and hashing tests**, all passing in their respective test runs. The audit exercise also revealed that a `SECURITY DEFINER` function initially recorded the function owner's identity rather than the intended acting role; I corrected it and tested the audit attribution again. I also corrected the restricted-role SQL injection demonstration when its initial syntax error failed to test the intended permission restriction. These results demonstrate integrity and access-control behaviour for the specified cases, not comprehensive production assurance. The [Portfolio 1 README](portfolio-1-database-design/Akosa_Antonella_301929153_P1_README.md) contains the SQL and screenshot references.

### 5.2 Portfolio 2 — Query Processing and Optimisation

**Problem and method.** The small relational sample used for design testing is not suitable for meaningful performance comparisons. I created a separate PostgreSQL database, `upln_perf`, containing approximately **50,000 members**, **100,000 titles** and **1,000,010 loans**. I benchmarked **nine library queries** using `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`. Each query had one cache-warming execution followed by five measured executions; I used the **median** execution time to reduce the influence of individual runs.

I compared the baseline with results after adding performance indexes. The baseline still contained the primary-key, unique and partial unique indexes inherited from Portfolio 1, so it was not a database without indexes. I measured buffer-page activity as the sum of shared hit blocks and shared read blocks from the final timed run. Those are **8 kB buffer pages touched**, including pages served from memory, rather than a count of physical disk reads alone.

**Selected results and explanations.** Query Q2, which retrieves a member's ten most recent loans, changed from a parallel sequential scan to an index scan after I introduced the composite `(member_id, loaned_at DESC)` index. Its median execution time fell from **50.255 ms to 0.045 ms**. The index matches both the member filter and required ordering, avoiding a separate sort and allowing an early stop at ten rows.

Q5, which checks available copies of a title, changed from **7.001 ms to 0.005 ms**. After `VACUUM (ANALYZE)`, its index-only plan reported **`Heap Fetches: 0`** and touched **4 buffer pages**, compared with **1,649** before optimisation. Q3 was different: the Portfolio 1 partial index already served the overdue-loan query, so I added no index. I treated its small timing change as run-to-run variation, not a new indexing achievement.

For Q6, the measured report time fell from **956.283 ms** for the underlying aggregation to **0.019 ms** when reading a materialised 40-row summary. This compares an aggregation with a **pre-computed result**; it does not include the cost of refreshing the materialised view. The distinction matters when deciding whether the faster read justifies the work and possible staleness involved in maintaining the summary.

**Further analysis and correctness.** Seven additional experiments examined BRIN versus B-tree indexes, join algorithms, planner statistics, parallel queries, `CLUSTER`, query form and index maintenance costs. In the write-cost experiment, **200,000 inserts** took **361 ms** without additional indexes and **2,151 ms** with four additional indexes. This demonstrates that improving read performance can make writes more expensive. I also compared the results of all nine queries under normal planning and settings that discouraged index-based scans; the indexes remained in place. The output comparison found identical result sets, and Q6's summary matched its source aggregation. The benchmark results were recorded on **18 October 2026**, with the additional query-result verification on **2 November 2026**. See the [Portfolio 2 README](portfolio-2-query-optimisation/Akosa_Antonella_301929153_P2_README.md) and [`results/`](portfolio-2-query-optimisation/results/).

### 5.3 Portfolio 3 — Transactions and Concurrency Control

**Problem and implementation.** A loan or payment can be valid when considered alone but incorrect when two sessions act on the same records. I used the separate `upln_tx` database to examine transaction atomicity, rollback and savepoints, isolation levels, double borrowing, lost updates, write skew, deadlocks and simultaneous fine payments. The tests reported **43 checks** in total. The ACID demonstrations include single-session operations; the race and locking exercises use concurrent sessions.

**Transaction correctness.** In the atomicity tests, a failed second operation could leave a loan record inconsistent with the copy's status when the steps were not protected as one transaction. A `ROLLBACK` prevented the partial change from remaining, while savepoints allowed only part of a transaction to be undone. The durability demonstration observed advancement of PostgreSQL's write-ahead log after `COMMIT`. I did **not** crash or restart the server in Portfolio 3, so that observation is not a crash-recovery result.

**Concurrency and isolation.** The double-borrow test showed that, when the partial unique index was present, the database rejected a second active loan for the same copy. With that protection temporarily removed in the test database, both loans could be accepted. `checkout_copy()` instead locks the copy first; the second librarian waits and then receives a controlled copy-unavailable error. The isolation exercises demonstrated a non-repeatable read, a lost update and write skew. In the loan-limit scenario, READ COMMITTED and REPEATABLE READ permitted a write-skew outcome, whereas SERIALIZABLE cancelled a conflicting transaction; its retry was refused according to the loan-limit rule.

The deadlock test deliberately acquired copy locks in opposite orders. PostgreSQL detected the cycle and cancelled a transaction. Acquiring locks consistently by `copy_id` avoided that deadlock in the tested scenario.

**Payment-integrity result.** Two cashiers each attempted to accept **NGN 800** against **NGN 1,000** outstanding. Without the lock, both payments were accepted, causing **NGN 600** of overpayment. With the Portfolio 1 `guard_payment()` trigger locking the fine row, the second cashier waited and was refused because only **NGN 200** remained. The final amount paid was **NGN 1,300**, including the earlier NGN 500 payment. This test shows why reading a balance and then updating it without controlling concurrency can produce an incorrect financial result. Details and the [single double-borrow screenshot](portfolio-3-transactions-concurrency/evidence/Akosa_Antonella_301929153_P3_03_double_borrow_race.png) are in the [Portfolio 3 README](portfolio-3-transactions-concurrency/Akosa_Antonella_301929153_P3_README.md).

### 5.4 Portfolio 4 — NoSQL and Advanced Data Models

**Problem and model selection.** Catalogue pages need a title, its authors, publisher, category and branch copy counts together. I evaluated a MongoDB document model for that access pattern while retaining members, loans, fines and payments in PostgreSQL, where I had already tested relational constraints and transaction controls. This is a proposed **polyglot persistence** approach, not evidence of a complete live system connecting both databases.

**Document implementation.** I exported and migrated **10 catalogue titles** from PostgreSQL, embedded information commonly retrieved with the title and placed reviews in a separate referenced collection. I used MongoDB schema validation, CRUD operations, aggregation, computed rating fields and a subset of recent reviews. I also generated **100,000 titles** and **50,000 reviews** for additional tests. Reconciliation checks compared the migrated catalogue information with PostgreSQL. The media-format exercise stored printed books, e-books, audiobooks, DVDs and magazines with format-specific attributes. The `ebook` type was introduced for the MongoDB example; the original PostgreSQL schema had four media types, and the ten migrated titles did not contain e-books.

**Index evidence.** In the ISBN lookup (X1), the unindexed query examined **100,010 documents** and the indexed query examined **1**, with average execution times of **43.80 ms** and **1.20 ms** across five runs. X2 examined **100,010** documents before indexing and **20** afterwards. X3 examined **11,507** before indexing and **50** afterwards; its `LIMIT 50` caused the unindexed scan to stop after finding 50 matches rather than examining the entire collection. The [index screenshot](portfolio-4-nosql/evidence/Akosa_Antonella_301929153_P4_07_indexes.png) records these results.

**Other NoSQL models and suitability.** I implemented a **key-value session example** in `kv_session`, including a TTL index and a `basket` field containing title IDs; this is not a separate reading-list implementation. I modelled **wide-column-style** branch/day counters and **graph-style** title relationships using `$graphLookup`. Those examples ran inside MongoDB. I did not deploy or benchmark Cassandra, HBase or Neo4j, so the tests illustrate model structure and operations rather than the behaviour of those dedicated engines.

**Trade-offs.** Embedding information can reduce the joins needed to display a title, but a catalogue copy count can become stale when PostgreSQL changes. I treated PostgreSQL's circulation records as authoritative rather than claiming the two databases were automatically synchronised. MongoDB's single-document atomicity supports the computed rating update; I did not implement multi-document MongoDB transactions. A separate hardened MongoDB exercise tested authentication and least-privilege accounts. See the [Portfolio 4 README](portfolio-4-nosql/Akosa_Antonella_301929153_P4_README.md).

### 5.5 Portfolio 5 — Distributed and Cloud Databases

**Problem and environment.** A single database instance is a point of failure, while separating data across servers introduces new coordination problems. I built a **four-instance PostgreSQL 16 laboratory** on one Codespace machine: a primary that also acts as coordinator, a read-only physical standby and two branch-based shards. A temporary fifth instance was used for point-in-time recovery. The north shard holds Abuja and Kano loan data; the south shard holds Lagos, Port Harcourt and Enugu loan data. The coordinator uses `postgres_fdw` to present the distributed loan records for querying. The scripts reported **62 checks**.

**Replication and consistency.** I tested streaming replication over TLS, standby read-only behaviour and synchronous-commit effects. A write became visible on the replica after **376 ms**, including the measurement check. With synchronous replication and the replica available, a commit took **107 ms**; when I stopped the replica, a commit waited **3,115 ms** until I cancelled it. This illustrates that requiring standby acknowledgement can affect write availability. The default asynchronous arrangement does not guarantee that every recently acknowledged commit survives a primary failure, even though no rows were lost in my particular failover run.

**Sharding and availability.** The coordinator's cross-shard count returned **50,000 loans**. A branch-specific query could reach its assigned shard, while a network-wide report required both shards. When one shard was stopped, queries against healthy branches continued but the complete report failed instead of silently returning an incomplete total. This is a **shard-outage test**, not a simulated network partition or proof of the CAP theorem. **Cross-shard transactions are not atomic** in my setup: each shard commits separately, and I did not implement distributed commit coordination.

**Failover and recovery.** After stopping the primary, the promoted replica accepted writes after **634 ms** in the scripted test, with **0 of 200 rows lost** in that run. Restarting the old primary allowed independent writes on the former and promoted servers, demonstrating **split brain** and why a production deployment needs fencing or another safeguard against two writable primaries. The backup exercise used a base backup and archived WAL to restore records deleted by mistake to a selected recovery point. The measured restore took **3.3 seconds**, with **3.3–5.0 seconds** across runs. It is a laboratory restore measurement, not a full service recovery-time objective or a production recovery guarantee.

**Implementation boundaries.** I used TLS, SCRAM authentication, least-privilege roles and loopback-only connections. The Docker network initially prevented the PostgreSQL instances from communicating in my Codespace, so I changed the setup to use separate ports on the host network. The test does not cover independent hardware, availability zones, automated failover, production network delay or encryption at rest. Section 7 of the [Portfolio 5 README](portfolio-5-distributed-cloud/Akosa_Antonella_301929153_P5_README.md) maps the laboratory components to possible cloud equivalents, but I did not deploy this cluster to cloud infrastructure.

## 6. Integration of Advanced Database Concepts

The five activities address different aspects of one computing problem. Their value is not limited to the result of each script; several of the results affect how I would evaluate the others.

**Integrity and concurrency.** Portfolio 1 enforces business rules through constraints and triggers. Portfolio 3 then demonstrates why those rules need to remain effective when two sessions act at the same time. The double-borrow and fine-payment tests show that a sequential check of availability or balance is insufficient when another transaction can change the relevant record before the first operation completes.

**Read performance and maintenance cost.** Portfolio 2 shows that the appropriate index depends on the filter, ordering and data distribution. Q2 benefits from a composite index; Q3 already benefits from a partial index created for integrity; Q6 benefits from pre-computation rather than an ordinary index. The measured insert-cost experiment shows the other side of indexing: faster searches may require more work whenever rows are written. I therefore cannot evaluate an index solely by its best read-time result.

**Normalisation and document modelling.** Portfolio 1 separates relationships to control redundancy. Portfolio 4 intentionally embeds selected catalogue information because it is read together. These are not contradictory decisions: they serve different access patterns. The trade-off is that a duplicated catalogue availability count needs a way to remain aligned with PostgreSQL, while loans and payments continue to depend on strict integrity controls.

**Local consistency and distributed coordination.** Portfolio 3 examines atomic changes and concurrency inside one PostgreSQL database. Portfolio 5 shows that splitting work across shards adds another boundary: the individual shards can commit independently, and the demonstrated setup has no atomic cross-shard transaction. Replication also creates a distinction between a committed write on the primary and a change known to have reached a standby. The failover and split-brain tests make this distinction operational rather than merely theoretical.

**Replication and recovery.** A standby can support service continuity, but it also receives accidental changes made on the primary. The point-in-time recovery exercise addresses a different failure scenario from failover. I used both tests because restoring mistakenly deleted data is not the same operation as promoting a surviving replica.

These connections support a common architectural conclusion: database design choices must be evaluated against **correctness, access patterns, concurrency, failure behaviour and operational cost together**. None of the tests establishes that one engine or technique is the best choice for every part of UPLN.

## 7. Testing Methodology and Results Verification

I used different forms of testing because each database concept requires different evidence.

| Test approach | What I checked | Example |
|---|---|---|
| Positive and negative integrity tests | Valid operations are accepted and specified invalid operations are refused | Portfolio 1 constraint and payment-guard tests |
| Permission and authentication tests | Access is allowed or denied according to the tested role or login | Portfolio 1 RBAC, authentication and audit checks |
| Execution-plan measurement | Query strategy and measured resource use change as expected | Portfolio 2 `EXPLAIN (ANALYZE, BUFFERS)` comparisons |
| Result-equivalence checks | Faster queries still return the same rows in the tested cases | Portfolio 2 nine-query comparison and Q6 materialised-view check |
| Concurrent-session tests | Timing and isolation can produce or prevent anomalies | Portfolio 3 borrowing, deadlock and payment tests |
| Schema validation and reconciliation | MongoDB documents meet the intended rules and migrated data agrees with PostgreSQL | Portfolio 4 validation and migration checks |
| Failure and recovery tests | Standby promotion, shard-outage handling and PITR behave as recorded | Portfolio 5 replication, failover and recovery scripts |

A passing negative test is meaningful only when the operation is rejected for the intended reason. I checked the script outputs against their intended results and corrected tests that initially failed for the wrong reason, rather than treating every SQL error as a successful security or integrity control. The recorded failure examples explain what needed correction.

I also distinguish **correctness** from **performance**. A faster query must still return the intended data; an index-only scan requires plan evidence, not just a fast timing; and a materialised view has a refresh cost that a query-time comparison omits. Similarly, WAL advancement after a commit is not the same as restoring after a crash, and one successful asynchronous failover does not prove zero data loss under every failure condition.

## 8. Supporting Evidence and Assessment Traceability

The table below points to the principal implementation evidence. I captured the screenshots during my test runs and checked the results recorded in the scripts and outputs. Full test-by-test descriptions and additional screenshots remain in the corresponding portfolio README files.

| Assessment deliverable | Principal implementation evidence | Supporting outputs and screenshots |
|---|---|---|
| Relational schema, ER model, constraints and normalisation | [Portfolio 1 schema](portfolio-1-database-design/Akosa_Antonella_301929153_P1_01_schema.sql) and [README](portfolio-1-database-design/Akosa_Antonella_301929153_P1_README.md) | [ER diagram](portfolio-1-database-design/Akosa_Antonella_301929153_P1_er_diagram.png); [`evidence/`](portfolio-1-database-design/evidence/) |
| SQL queries, results, execution plans, indexing and analysis | [Portfolio 2 README](portfolio-2-query-optimisation/Akosa_Antonella_301929153_P2_README.md), [`Akosa_Antonella_301929153_P2_02_benchmark_harness.sql`](portfolio-2-query-optimisation/Akosa_Antonella_301929153_P2_02_benchmark_harness.sql), [`Akosa_Antonella_301929153_P2_08_query_results.sql`](portfolio-2-query-optimisation/Akosa_Antonella_301929153_P2_08_query_results.sql) | [`results/Akosa_Antonella_301929153_P2_plans_before.txt`](portfolio-2-query-optimisation/results/Akosa_Antonella_301929153_P2_plans_before.txt), [`results/Akosa_Antonella_301929153_P2_plans_after.txt`](portfolio-2-query-optimisation/results/Akosa_Antonella_301929153_P2_plans_after.txt), [`evidence/Akosa_Antonella_301929153_P2_09_query_results.png`](portfolio-2-query-optimisation/evidence/Akosa_Antonella_301929153_P2_09_query_results.png) |
| COMMIT, ROLLBACK, isolation, concurrency problems and controls | [Portfolio 3 README](portfolio-3-transactions-concurrency/Akosa_Antonella_301929153_P3_README.md) and [`Akosa_Antonella_301929153_P3_07_run_all_tests.sh`](portfolio-3-transactions-concurrency/Akosa_Antonella_301929153_P3_07_run_all_tests.sh) | [`evidence/Akosa_Antonella_301929153_P3_03_double_borrow_race.png`](portfolio-3-transactions-concurrency/evidence/Akosa_Antonella_301929153_P3_03_double_borrow_race.png), [`evidence/Akosa_Antonella_301929153_P3_07_all_tests_summary.png`](portfolio-3-transactions-concurrency/evidence/Akosa_Antonella_301929153_P3_07_all_tests_summary.png) |
| Document, key-value, wide-column and graph models and suitability | [Portfolio 4 README](portfolio-4-nosql/Akosa_Antonella_301929153_P4_README.md), [`Akosa_Antonella_301929153_P4_11_other_nosql_models.js`](portfolio-4-nosql/Akosa_Antonella_301929153_P4_11_other_nosql_models.js) | [`evidence/Akosa_Antonella_301929153_P4_07_indexes.png`](portfolio-4-nosql/evidence/Akosa_Antonella_301929153_P4_07_indexes.png), [additional evidence](portfolio-4-nosql/evidence/) |
| Replication, sharding, availability, consistency, backup and cloud discussion | [Portfolio 5 README](portfolio-5-distributed-cloud/Akosa_Antonella_301929153_P5_README.md), [`Akosa_Antonella_301929153_P5_08_run_all_tests.sh`](portfolio-5-distributed-cloud/Akosa_Antonella_301929153_P5_08_run_all_tests.sh) | [`evidence/`](portfolio-5-distributed-cloud/evidence/), including `Akosa_Antonella_301929153_P5_07_failover` and `Akosa_Antonella_301929153_P5_07_after_failover_monitor` |


For Portfolio 2, the performance benchmark and the later query-result verification were recorded on different dates. The query-result evidence supplements the original optimisation results rather than replacing them. Portfolio 5's evidence index retains all ten screenshots: `Akosa_Antonella_301929153_P5_01_cluster_up`, `Akosa_Antonella_301929153_P5_02_load_primary`, `Akosa_Antonella_301929153_P5_03_replication`, `Akosa_Antonella_301929153_P5_04_sharding`, `Akosa_Antonella_301929153_P5_05_security`, `Akosa_Antonella_301929153_P5_06_backup_pitr`, `Akosa_Antonella_301929153_P5_07_failover`, `Akosa_Antonella_301929153_P5_07_after_failover_monitor`, `Akosa_Antonella_301929153_P5_08_all_tests` and `Akosa_Antonella_301929153_P5_09_monitor`.

## 9. Reproducing the Portfolio Activities

I used **Docker with Docker Compose** in GitHub Codespaces. The detailed commands and execution order for every activity are in the relevant portfolio README.

From the repository root, start the PostgreSQL environment used by Portfolios 1–3:

```bash
docker compose -f Akosa_Antonella_301929153_docker-compose.yml up -d
```

Run the portfolio-specific setup and test procedures as documented in each folder. The main test entry points for Portfolios 3–5 are:

```bash
bash portfolio-3-transactions-concurrency/Akosa_Antonella_301929153_P3_07_run_all_tests.sh
bash portfolio-4-nosql/Akosa_Antonella_301929153_P4_10_run_all_tests.sh
bash portfolio-5-distributed-cloud/Akosa_Antonella_301929153_P5_08_run_all_tests.sh
```

These are **separate activities**, not three commands that must be run together as one integrated deployment. Portfolio 4 requires the Portfolio 1 catalogue data for its migration and reconciliation tests. Portfolio 2 creates a separate performance database and has its own data-generation and benchmark sequence.

**Reset and test-data precautions.** Rerunning Portfolio 1's `Akosa_Antonella_301929153_P1_01_schema.sql` drops and recreates its core tables; it must not be used against data that needs to be preserved. Portfolio 3 deliberately disables selected controls in the disposable `upln_tx` test environment and restores them during testing. Portfolio 5's reset rebuilds its own laboratory cluster, and its failover script changes which instance is writable. I use only synthetic records for these demonstrations.

**Credentials and connection boundaries.** The root `Akosa_Antonella_301929153_docker-compose.yml` contains a practice PostgreSQL password for the disposable lab. Portfolio 4's primary MongoDB demonstration is bound to `127.0.0.1`; the separate hardened exercise tests authenticated access. Portfolio 5 generates laboratory passwords and certificates and tests TLS connections. Generated `.env.mongo`, `.env.p5` and certificate material are excluded from Git tracking according to the portfolio configuration. These arrangements are not substitutes for production secret-management and network controls.

## 10. Implementation Limitations and Production Considerations

- **Synthetic data and controlled workloads.** The datasets make specific design and query behaviours measurable. They do not establish the workload distribution or operational requirements of a real library.
- **Limited assurance from passing tests.** The recorded pass counts support the test cases that were executed; they do not establish that all defects, security failures or concurrency anomalies have been eliminated.
- **Performance variability.** PostgreSQL timings and buffer activity depend on the environment, cache and query plan. MongoDB indexing timings are averages from the recorded runs. Neither set should be treated as a production service-level objective.
- **Identity and encryption boundaries.** Portfolio 1's RLS session variable demonstrates filtering, not a complete secure identity binding. TLS and storage encryption were not both implemented in every portfolio; Portfolio 5 demonstrated TLS for PostgreSQL, while encryption at rest remained a design consideration.
- **Catalogue consistency.** The MongoDB catalogue model can duplicate information held in PostgreSQL. The portfolio demonstrates modelling and reconciliation, not automatic real-time synchronisation for every circulation operation.
- **Distributed deployment scope.** Portfolio 5's PostgreSQL instances share one host. I did not demonstrate independent hardware failures, managed cloud services, automated failover or atomic cross-shard transactions. The split-brain test demonstrates the consequences of missing protection against multiple writable primaries.
- **Recovery measurements.** The reported restore and failover timings are limited to the scripted laboratory operations. They do not include every stage of detecting and recovering from an application-level outage.

These limits define what the recorded evidence supports and what would require further implementation or testing before a production deployment.

## 11. Individual Technical Reflection

Working across the five UPLN portfolios helped me examine database design as a series of connected decisions rather than five isolated topics. My earlier database experience was primarily with MySQL, and Portfolio 1 gave me practical experience with PostgreSQL features such as partial unique indexes, row-level security, `SECURITY DEFINER` functions and `pgcrypto`. More importantly, I had to test whether the controls actually enforced the business rules I had described. The one-active-loan-per-copy index is a useful example: it preserves historical borrowing records while preventing a second active loan for the same physical copy. I also had to distinguish a constraint that permits **at most one** headquarters from one that requires a headquarters to exist.

The link between the relational design and the concurrency experiments was particularly useful. In Portfolio 3, removing the active-loan protection in the disposable test database allowed the double-borrow race to produce two active loans for one copy. The fine-payment test exposed a similar problem: both cashiers could act on the same old balance unless the payment guard locked the fine row. These tests showed me why a correct-looking application check is not enough when another transaction can change the data before the first one finishes. They also made the differences between rollback, isolation and locking concrete. I was careful not to describe the WAL advancement observed in Portfolio 3 as proof of crash recovery, because no server crash was tested there.

Portfolio 2 changed the way I interpret performance results. I used execution plans and buffer measurements alongside timings, rather than assuming that a faster number proves an optimisation was effective. Q2 showed how a composite index could support both filtering and ordering, while Q3 demonstrated that an index already created for integrity could also serve a query without further changes. The materialised-view result for Q6 was substantial, but it measured retrieval of a pre-computed summary, not the cost of keeping that summary current. The insert experiment also showed the cost of maintaining additional indexes. Comparing returned rows as well as execution times mattered because an optimised query is only useful if it still gives the correct answer.

Portfolio 4 required a different way of thinking about the same library information. I used a document model for catalogue data that is commonly read together, while keeping borrowing and payments within the relational design. Embedding catalogue details reduces the need for joins, but copying availability information creates a consistency problem if PostgreSQL changes. The migration and reconciliation checks gave me a way to test the initial data agreement; they did not establish automatic synchronisation between the systems. I also kept the scope of the other NoSQL examples clear: the key-value session, wide-column-style counters and graph traversal were demonstrated in MongoDB, not in separate specialist database engines.

Portfolio 5 made the operational consequences of distributed databases more apparent. The synchronous-replication test showed a commit waiting while the replica was unavailable; the manual failover test showed that promoting a standby does not, by itself, prevent the old primary from accepting writes after a restart. The split-brain result is why I would not describe replication alone as a complete high-availability solution. The point-in-time recovery exercise addressed a different problem: recovering data after a mistaken deletion that replication would also copy. I also had to resolve a practical networking problem in Codespaces when the original Docker network prevented the PostgreSQL instances from communicating. I tested connectivity and changed the setup to use the host network and separate ports, with `127.0.0.1` used to match the connection rules.

Across the project, I found that **the reason a test passes matters as much as the pass result**. The audit-trigger identity error and the SQL injection demonstration that initially failed with a syntax error both required correction before they supported the intended conclusions. I therefore distinguish what I observed from what would require additional testing: the MongoDB models were not all separate database deployments, the distributed PostgreSQL servers shared one machine, failover was manual, and cross-shard transactions were not atomic. My overall conclusion is that applying advanced database concepts involves choosing suitable controls, checking their behaviour under realistic failure or concurrency conditions, and recognising the cost and limitations of those choices.

## 12. Declaration of AI Use

I used Claude to help design, write and explain SQL, shell and JavaScript scripts and to suggest test cases. I used ChatGPT to help edit the portfolio README files. I ran and tested the scripts in GitHub Codespaces, reviewed the recorded results and screenshots, and checked the documentation for accuracy. I remain responsible for the implementation, verification and conclusions presented in this portfolio.

## 13. References

The individual portfolio READMEs contain the sources specific to their experiments. The principal shared technical references are:

1. MIVA Open University (n.d.). *MIT 8103 Advanced Database Systems, Live Lessons I and II* [Lecture slides].
2. PostgreSQL Global Development Group. [PostgreSQL 16 Documentation: Partial Indexes](https://www.postgresql.org/docs/16/indexes-partial.html), [Row Security Policies](https://www.postgresql.org/docs/16/ddl-rowsecurity.html) and [pgcrypto](https://www.postgresql.org/docs/16/pgcrypto.html).
3. PostgreSQL Global Development Group. [PostgreSQL 16 Documentation: Using EXPLAIN](https://www.postgresql.org/docs/16/using-explain.html), [Index-Only Scans and Covering Indexes](https://www.postgresql.org/docs/16/indexes-index-only-scans.html) and [Materialized Views](https://www.postgresql.org/docs/16/rules-materializedviews.html).
4. PostgreSQL Global Development Group. [PostgreSQL 16 Documentation: Transaction Isolation](https://www.postgresql.org/docs/16/transaction-iso.html), [Explicit Locking](https://www.postgresql.org/docs/16/explicit-locking.html) and [Write-Ahead Logging (WAL)](https://www.postgresql.org/docs/16/wal-intro.html).
5. MongoDB. [MongoDB 7.0 Documentation: Data Modelling](https://www.mongodb.com/docs/v7.0/data-modeling/), [Schema Validation](https://www.mongodb.com/docs/v7.0/core/schema-validation/), [Explain Results](https://www.mongodb.com/docs/v7.0/reference/explain-results/) and [TTL Indexes](https://www.mongodb.com/docs/v7.0/core/index-ttl/).
6. PostgreSQL Global Development Group. [PostgreSQL 16 Documentation: High Availability, Load Balancing, and Replication](https://www.postgresql.org/docs/16/high-availability.html), [Continuous Archiving and Point-in-Time Recovery](https://www.postgresql.org/docs/16/continuous-archiving.html) and [postgres_fdw](https://www.postgresql.org/docs/16/postgres-fdw.html).
7. Brewer, E. (2012). CAP twelve years later: How the 'rules' have changed. *IEEE Computer*, 45(2), 23–29.
8. MIVA Open University (2026/2027). *MIT 8103 Advanced Database Systems: First Semester Continuous Assessment — Individual Practical Database Portfolio* (assessment instructions, 40 marks).

