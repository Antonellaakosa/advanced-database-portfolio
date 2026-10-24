# Portfolio 3: Transactions and Concurrency

**Course:** MIT 8103 Advanced Database Systems | **Case study:** Unity Public Library Network (UPLN) | **DBMS:** PostgreSQL 16

## 1. What this portfolio is about

A library database is used by many people at once. Several librarians lend books at the same time, and two cashiers
may take a payment on the same fine. If the database is careless, two people can walk out with the same book, or a
fine can be paid twice over.

In this portfolio I make these problems happen on purpose, watch them happen, and then show how PostgreSQL and the
Portfolio 1 design stop them. Every test runs two or three database sessions **at the same moment** and prints a
timeline, so you can see who waited for whom.

## 2. What is in this folder

| File | What it does |
|---|---|
| `00_setup.sh` | Builds a separate test database `upln_tx` from the Portfolio 1 design (schema, sample data, payment guard). Safe to run again |
| `01_transaction_functions.sql` | The borrow and return operations (`checkout_copy`, `return_copy`), a deliberately unsafe version for demonstrations (`checkout_unsafe`), and the PASS/FAIL helper |
| `lib.sh` | Small helper that runs several sessions at once and merges their output into one timeline |
| `02_acid_basics.sql` | Atomicity, consistency and durability, one at a time |
| `03_double_borrow_race.sh` | Two librarians lend the same copy at the same moment |
| `04_isolation_levels.sh` | What each isolation level lets you see, a lost update, and a broken loan limit |
| `05_deadlock.sh` | Two staff block each other, and the fix |
| `06_two_cashiers.sh` | Two cashiers pay the same fine at once (the test promised in the Portfolio 1 README) |
| `07_run_all_tests.sh` | Runs everything and prints one summary table |
| `evidence/` | My screenshots of each run |

I used a separate database (`upln_tx`) so the Portfolio 1 database `upln`, with its security and audit evidence, is
never touched. Some tests temporarily switch off a protection to show what it was protecting. That is only ever done
in `upln_tx`, and the script puts the protection back and checks that it is back.

## 3. How to run it (from the repo root, in the Codespace)

```bash
docker compose up -d                                   # make sure the database is running
bash portfolio-3-transactions-concurrency/00_setup.sh
docker compose exec -T postgres psql -U library_admin -d upln_tx < portfolio-3-transactions-concurrency/02_acid_basics.sql
bash portfolio-3-transactions-concurrency/03_double_borrow_race.sh
bash portfolio-3-transactions-concurrency/04_isolation_levels.sh
bash portfolio-3-transactions-concurrency/05_deadlock.sh
bash portfolio-3-transactions-concurrency/06_two_cashiers.sh
bash portfolio-3-transactions-concurrency/07_run_all_tests.sh     # all of the above, one summary
```

## 4. The key ideas in plain words

**A transaction** is a group of steps that must succeed together or not at all. Lending a book is two steps: record
the loan, and mark the copy as on loan. If only one of them happens, the data contradicts itself.

**ACID** is the checklist for a reliable transaction:

| Letter | Meaning | Where I show it |
|---|---|---|
| Atomicity | All steps happen, or none do | `02_acid_basics.sql`, parts A to C |
| Consistency | The rules of the database always hold afterwards | `02_acid_basics.sql`, part D, and every race test |
| Isolation | Transactions running together do not disturb each other | `03` and `04` |
| Durability | Once committed, it survives a crash (the change is written to the write-ahead log first) | `02_acid_basics.sql`, part E |

**Locks and MVCC.** PostgreSQL lets readers and writers work together by keeping several versions of a row (MVCC,
multi-version concurrency control), so a reader normally never has to wait for a writer. When two sessions want to
*change* the same row, one has to wait. `SELECT ... FOR UPDATE` takes that lock on purpose, before deciding anything.

**Isolation levels in PostgreSQL** (what I tested is in bold):

| Level | Dirty read | Non-repeatable read | Phantom read | Write skew |
|---|---|---|---|---|
| READ COMMITTED (default) | No | **Possible** | Possible | **Possible** |
| REPEATABLE READ | No | **No** | No (PostgreSQL) | **Possible** |
| SERIALIZABLE | No | No | No | **No (a transaction is cancelled and must retry)** |

READ UNCOMMITTED exists in PostgreSQL but behaves like READ COMMITTED, so dirty reads never happen. I tested that too.

## 5. What each test shows and what I found

Everything below is checked by a PASS/FAIL line in the scripts: 43 checks in total.

### 5.1 ACID basics (`02_acid_basics.sql`, 6 checks)
- **Without a transaction**, a failed second step left a loan recorded while the copy still said "available". With a
  transaction and a `ROLLBACK`, nothing was left behind.
- A **savepoint** let me undo the second borrow of a visit and keep the first.
- The database itself refused a copy that was already on loan, a loan due before it was issued, and a second active
  loan on the same copy.
- A `COMMIT` moved the write-ahead log position forward, which is how PostgreSQL makes a commit durable.

### 5.2 The double-borrow race (`03_double_borrow_race.sh`, 9 checks)
Two librarians check that a copy is available, then both try to lend it.
1. **With the Portfolio 1 rule** (`uq_one_active_loan_per_copy`): the second loan was refused by the database when
   the first one committed. Only one loan existed.
2. **With the rule removed**: both loans were accepted. One copy, two borrowers. Putting the rule back failed until
   I repaired the data, which shows how hard it is to fix this after the fact.
3. **With `checkout_copy()`**, which locks the copy first: the second librarian simply waited, then received a clear
   message (`UPLN-021`, copy not available), not a raw index error.

### 5.3 Isolation levels (`04_isolation_levels.sh`, 15 checks)
- **READ COMMITTED**: the same query gave two different answers inside one transaction (a non-repeatable read).
- **REPEATABLE READ**: both reads agreed, because the transaction works from a frozen snapshot.
- **READ UNCOMMITTED**: the reader never saw an uncommitted change (no dirty reads in PostgreSQL).
- **Lost update**: two front desks renewed the same loan. Reading the count, deciding in the program, then writing back
  approved both renewals although only one was left. A single `UPDATE ... WHERE renewals < 2` approved one and refused the other.
- **Write skew** (the loan limit of 5): a member with 4 loans borrowed two copies at once. Under READ COMMITTED
  **and** REPEATABLE READ both succeeded and the member ended with 6 loans. Under SERIALIZABLE, PostgreSQL cancelled one
  transaction (`could not serialize access`), and the retry was refused correctly. `checkout_copy()` is safe even at the
  default level because it locks the member's row.

### 5.4 Deadlock (`05_deadlock.sh`, 6 checks)
Staff A locks copy 1 then wants copy 2. Staff B locks copy 2 then wants copy 1. Neither can continue. PostgreSQL detected
the cycle and cancelled one of them (`deadlock detected`), and the other finished. The fix is to always take locks in
the same order (by `copy_id`): then there is no deadlock and the second session just waits its turn. An "observer"
session shows who is blocked by whom using `pg_blocking_pids`.

### 5.5 Two cashiers (`06_two_cashiers.sh`, 7 checks)
A fine of NGN 1,500 had NGN 500 paid, so NGN 1,000 was owed. Two cashiers each took NGN 800 at the same moment.
- **Without a lock** (a temporary test version of the check): both payments were accepted and the fine was overpaid by NGN 600.
- **With the Portfolio 1 guard** (`guard_payment()`, which locks the fine row): the second cashier waited, then was refused
  with `UPLN-016` because only NGN 200 was left. The fine ended at NGN 1,300 paid. This closes the promise made in the
  Portfolio 1 README.

## 6. How this connects to Portfolio 1

- `uq_one_active_loan_per_copy` (a partial unique index) is the last line of defence against a double-borrow.
- `copy.status` is stored separately from the loans (a deliberate choice explained in Portfolio 1). That is only safe
  if both are updated in one transaction, which is exactly what `checkout_copy()` does.
- `guard_payment()` uses `FOR UPDATE` on the fine row, and Test 5.5 proves why that line matters.

## 7. Limitations

- The "two people at once" timing is created with short pauses (`pg_sleep`), standing in for the time a real person or
  network takes. The results are reliable, but on a very slow machine a timing-based check could, in rare cases, need a re-run.
- This is one PostgreSQL server. Transactions across several servers (distributed transactions) belong to Portfolio 5.
- I did not test optimistic locking (version columns) or advisory locks. Row locks and SERIALIZABLE cover the cases in this case study.

## 8. Evidence

| File | Shows |
|---|---|
| `evidence/01_setup_done.png` | The test database built from the Portfolio 1 design |
| `evidence/02_acid_basics_a.png`, `02_acid_basics_b.png` | ACID tests |
| `evidence/03_double_borrow_race_a.png`, `03_double_borrow_race_b.png` | The race, with and without the rule, and the safe version |
| `evidence/04_isolation_levels_a.png`, `b`, `c` | Isolation levels, lost update, write skew |
| `evidence/05_deadlock.png` | The deadlock and the fix |
| `evidence/06_two_cashiers.png` | Overpayment without a lock, refusal with the guard |
| `evidence/07_all_tests_summary.png` | All checks in one table |

## 9. Sources

PostgreSQL 16 documentation: Transaction Isolation, Explicit Locking, MVCC, Serializable Snapshot Isolation, WAL
(Reliability and the Write-Ahead Log). MIT 8103 lesson notes on ACID and concurrency.
