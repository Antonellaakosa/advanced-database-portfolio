# Portfolio 3: Transactions and Concurrency

**Course:** MIT 8103 Advanced Database Systems | **Case study:** Unity Public Library Network (UPLN) | **DBMS:** PostgreSQL 16

## 1. Objectives and Scope

In this portfolio, I tested how PostgreSQL transactions protect the consistency of library lending, loan renewals and fine payments when several staff members work at the same time. I reproduced double borrowing, lost updates, write skew, deadlocks and concurrent payments, then tested the controls used to address each problem.

The concurrency scripts use two or three database sessions and combine their output into a timeline showing which session waited or continued. I tested basic transaction operations separately in `Akosa_Antonella_301929153_P3_02_acid_basics.sql`; these do not all require concurrent sessions.

## 2. Implementation Files and Test Environment

| File | Purpose |
|---|---|
| `Akosa_Antonella_301929153_P3_00_setup.sh` | Builds the separate `upln_tx` test database using the Portfolio 1 schema, sample data and payment guard; it can be rerun |
| `Akosa_Antonella_301929153_P3_01_transaction_functions.sql` | Defines `checkout_copy`, `return_copy`, the deliberately unsafe `checkout_unsafe` demonstration, and the PASS/FAIL helper |
| `Akosa_Antonella_301929153_P3_lib.sh` | Runs multiple sessions and combines their output into a timeline |
| `Akosa_Antonella_301929153_P3_02_acid_basics.sql` | Tests atomicity, consistency and the WAL observation used to discuss durability |
| `Akosa_Antonella_301929153_P3_03_double_borrow_race.sh` | Tests two librarians attempting to lend the same copy concurrently |
| `Akosa_Antonella_301929153_P3_04_isolation_levels.sh` | Tests isolation levels, a lost update and a loan-limit violation |
| `Akosa_Antonella_301929153_P3_05_deadlock.sh` | Demonstrates a deadlock and consistent lock ordering |
| `Akosa_Antonella_301929153_P3_06_two_cashiers.sh` | Tests concurrent payments against one fine, following the payment-guard implementation in Portfolio 1 |
| `Akosa_Antonella_301929153_P3_07_run_all_tests.sh` | Runs the tests and prints one summary table |
| `evidence/` | Contains my screenshots of the test runs |

I used `upln_tx` rather than the Portfolio 1 database `upln` so that its security and audit evidence remained untouched. For selected demonstrations, I temporarily disabled a protection, ran the test, restored the protection and checked that it was restored. These changes were confined to `upln_tx`.

## 3. Implementation and Test Execution

I ran the following commands from the repository root in my GitHub Codespace:

```bash
docker compose -f Akosa_Antonella_301929153_docker-compose.yml up -d                                   # make sure the database is running
bash portfolio-3-transactions-concurrency/Akosa_Antonella_301929153_P3_00_setup.sh
docker compose -f Akosa_Antonella_301929153_docker-compose.yml exec -T postgres psql -U library_admin -d upln_tx < portfolio-3-transactions-concurrency/Akosa_Antonella_301929153_P3_02_acid_basics.sql
bash portfolio-3-transactions-concurrency/Akosa_Antonella_301929153_P3_03_double_borrow_race.sh
bash portfolio-3-transactions-concurrency/Akosa_Antonella_301929153_P3_04_isolation_levels.sh
bash portfolio-3-transactions-concurrency/Akosa_Antonella_301929153_P3_05_deadlock.sh
bash portfolio-3-transactions-concurrency/Akosa_Antonella_301929153_P3_06_two_cashiers.sh
bash portfolio-3-transactions-concurrency/Akosa_Antonella_301929153_P3_07_run_all_tests.sh     # all of the above, one summary
```

## 4. Transaction Principles and Control Mechanisms

A transaction groups related database operations so that they commit together or are rolled back together. For a library checkout, recording the loan without also updating the copy's availability would leave the records inconsistent. I used the ACID properties to organise my tests.

| Property | Meaning | Test evidence |
|---|---|---|
| Atomicity | Either the related changes complete together or they are rolled back | `Akosa_Antonella_301929153_P3_02_acid_basics.sql`, parts A to C |
| Consistency | Committed changes must satisfy the database's defined integrity rules | `Akosa_Antonella_301929153_P3_02_acid_basics.sql`, part D, and the race-condition tests |
| Isolation | Concurrent transactions control the visibility of changes and conflicting operations | `03` and `04` |
| Durability | PostgreSQL uses the write-ahead log (WAL) to support recovery of committed changes; my test observed WAL advancement but did not simulate a crash | `Akosa_Antonella_301929153_P3_02_acid_basics.sql`, part E |

**Locks and multi-version concurrency control (MVCC).** PostgreSQL maintains row versions so readers generally do not block writers. When concurrent sessions attempt conflicting changes, row locking controls the order in which they proceed. I used `SELECT ... FOR UPDATE` to lock a row before checking whether an operation could proceed.

**Isolation levels in PostgreSQL** (bold entries identify behaviours covered by my tests):

| Level | Dirty read | Non-repeatable read | Phantom read | Write skew |
|---|---|---|---|---|
| READ COMMITTED (default) | No | **Possible** | Possible | **Possible** |
| REPEATABLE READ | No | **No** | No (PostgreSQL) | **Possible** |
| SERIALIZABLE | No | No | No | **No (a transaction is cancelled and must retry)** |

PostgreSQL accepts READ UNCOMMITTED but treats it as READ COMMITTED. I tested this and confirmed that the reader did not see an uncommitted change.

## 5. Transaction and Concurrency Tests: Methods and Results

I recorded **43 PASS/FAIL checks** across the scripts. The sections below describe the operations I tested, the results and the relevant controls.

### 5.1 ACID Operations, Rollback and Savepoints (`Akosa_Antonella_301929153_P3_02_acid_basics.sql`, 6 checks)

- **Atomicity:** Without a transaction, failure in the second step left a loan recorded while the copy was still marked `available`. When I used a transaction and `ROLLBACK`, neither change remained.
- **Savepoints:** I rolled back the second borrow in a visit while retaining the first.
- **Consistency:** PostgreSQL rejected a loan for a copy already on loan, a due date before the loan date and a second active loan for the same copy.
- **WAL and durability:** After `COMMIT`, I observed the WAL position advance. This demonstrates WAL activity associated with the commit, not recovery after a server crash. I did not crash the PostgreSQL server in this portfolio. Portfolio 5 contains separate failover and point-in-time recovery exercises.

### 5.2 Double-Borrow Race (`Akosa_Antonella_301929153_P3_03_double_borrow_race.sh`, 9 checks)

I tested two librarians checking the same copy's availability before attempting to lend it:

1. **With the Portfolio 1 partial unique index** `uq_one_active_loan_per_copy`, PostgreSQL rejected the second loan after the first committed. Only one active loan remained.
2. **With the index removed for the test**, both loans were accepted for the same copy. Recreating the index failed until I repaired the conflicting data.
3. **With `checkout_copy()`**, which locks the copy before proceeding, the second librarian waited and received `UPLN-021` (copy not available), rather than a raw unique-index error.

### 5.3 Isolation Levels and Concurrency Anomalies (`Akosa_Antonella_301929153_P3_04_isolation_levels.sh`, 15 checks)

- **READ COMMITTED:** I obtained different results from the same query within one transaction, demonstrating a non-repeatable read.
- **REPEATABLE READ:** The two reads returned the same result because they used the transaction's snapshot.
- **READ UNCOMMITTED:** The reader did not see uncommitted data, consistent with PostgreSQL treating this level as READ COMMITTED.
- **Lost update:** Two front desks read the renewal count, made decisions in the program and wrote a value back. Both renewals were approved even though only one remained. With a single `UPDATE ... WHERE renewals < 2`, one renewal succeeded and the other was refused.
- **Write skew:** A member with 4 active loans borrowed two more copies concurrently against a limit of 5. Under READ COMMITTED and REPEATABLE READ, both transactions succeeded and the member ended with 6 loans. Under SERIALIZABLE, PostgreSQL cancelled one transaction with `could not serialize access`; the retry was then refused. I also tested `checkout_copy()`, which locks the member's row and prevents this outcome at the default isolation level.

### 5.4 Deadlock Detection and Lock Ordering (`Akosa_Antonella_301929153_P3_05_deadlock.sh`, 6 checks)

I made Staff A lock copy 1 before requesting copy 2, while Staff B locked copy 2 before requesting copy 1. PostgreSQL detected the resulting deadlock, cancelled one transaction with `deadlock detected` and allowed the other to complete. An observer session used `pg_blocking_pids` to show which session blocked another.

I then tested acquiring the locks in the same `copy_id` order. In that run, the second session waited instead of entering a deadlock.

### 5.5 Concurrent Fine Payments (`Akosa_Antonella_301929153_P3_06_two_cashiers.sh`, 7 checks)

I started with a fine of **NGN 1,500**, of which **NGN 500** had been paid, leaving **NGN 1,000** outstanding. Two cashiers each attempted to accept **NGN 800**.

- **Without row locking**, using a temporary test version of the payment check, both payments were accepted. The fine was overpaid by **NGN 600**.
- **With the Portfolio 1 `guard_payment()` trigger**, which locks the fine row, the second cashier waited and then received `UPLN-016`. The first payment left only **NGN 200** outstanding, so the second payment was refused. The fine ended with **NGN 1,300 paid**.

This test extends the payment-integrity demonstration from Portfolio 1 to simultaneous cashier sessions.

## 6. Relationship to Portfolio 1 Controls

- The partial unique index `uq_one_active_loan_per_copy` prevented a second active loan in the tested double-borrow race, including when the application-level availability check was insufficient.
- Portfolio 1 stores `copy.status` separately from loan records. In `checkout_copy()`, I updated both within the same transaction to avoid leaving their states inconsistent.
- `guard_payment()` uses `FOR UPDATE` on the fine row, and the two-cashiers test in section 5.5 shows why that line matters.

## 7. Limitations

- I used short `pg_sleep` pauses to reproduce the delays that could occur between database sessions. A timing-dependent check might need to be rerun on a slower machine.
- I tested transactions on one PostgreSQL server. I did not implement or test atomic transactions across separate servers. Portfolio 5 addresses distributed database components in a separate lab, not cross-shard transaction atomicity.
- I did not test optimistic locking with version columns or advisory locks. The practical tests used row locks, conditional updates and SERIALIZABLE isolation.
- My WAL check did not include a server crash or restart; it should not be treated as proof of crash recovery.

## 8. Supporting Evidence

| File | Demonstrated result |
|---|---|
| `evidence/Akosa_Antonella_301929153_P3_01_setup_done.png` | Test database created from the Portfolio 1 design |
| `evidence/Akosa_Antonella_301929153_P3_02_acid_basics_a.png`, `Akosa_Antonella_301929153_P3_02_acid_basics_b.png` | ACID operation tests |
| `evidence/Akosa_Antonella_301929153_P3_03_double_borrow_race.png` | Double-borrow race with and without the constraint, and the locking-based solution |
| `evidence/Akosa_Antonella_301929153_P3_04_isolation_levels_a.png`, `b`, `c` | Isolation-level tests, lost update and write skew |
| `evidence/Akosa_Antonella_301929153_P3_05_deadlock.png` | Deadlock detection and the lock-ordering test |
| `evidence/Akosa_Antonella_301929153_P3_06_two_cashiers.png` | Overpayment without locking and rejection with the payment guard |
| `evidence/Akosa_Antonella_301929153_P3_07_all_tests_summary.png` | Summary of all 43 checks |

## 9. References

- PostgreSQL Global Development Group. *PostgreSQL 16 Documentation: Transaction Isolation*. https://www.postgresql.org/docs/16/transaction-iso.html
- PostgreSQL Global Development Group. *PostgreSQL 16 Documentation: Explicit Locking*. https://www.postgresql.org/docs/16/explicit-locking.html
- PostgreSQL Global Development Group. *PostgreSQL 16 Documentation: Concurrency Control*. https://www.postgresql.org/docs/16/mvcc.html
- PostgreSQL Global Development Group. *PostgreSQL 16 Documentation: Write-Ahead Logging (WAL)*. https://www.postgresql.org/docs/16/wal-intro.html
- MIVA Open University (n.d.). *MIT 8103 Advanced Database Systems, Live Lesson I: ACID properties in databases* [Lecture slides].
