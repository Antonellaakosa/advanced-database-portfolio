# Portfolio 4: NoSQL and Advanced Data Models (MongoDB)

**Course:** MIT 8103 Advanced Database Systems  **Case study:** Unity Public Library Network (UPLN), a fictional library network with branches in Abuja, Lagos, Port Harcourt, Kano and Enugu. All data is made up.

## 1. What this portfolio does

In Portfolio 1 the library lived in PostgreSQL, spread across 17 related tables. This portfolio asks a different question: *which part of that data would be better off in a document database, and what do we gain and lose by moving it?*

My answer is the **book catalogue**. A catalogue page needs the title, its authors, publisher, category and how many copies each branch has, all at once. In PostgreSQL that is a join across five tables. In MongoDB it is one document. Loans, fines and payments stay in PostgreSQL, because they need strict transactions (Portfolio 3 showed why).

So the system I end up with uses both databases, each for what it is good at. This is called *polyglot persistence*.

| Data | Where it lives | Why |
|---|---|---|
| Members, loans, fines, payments | PostgreSQL | Needs ACID transactions and strict rules |
| Catalogue (titles, authors, availability) | MongoDB | Read as a whole, flexible fields, easy to search |
| Reviews | MongoDB (own collection) | Grow without limit, so referenced rather than embedded |

## 2. What is in this folder

| File | What it does |
|---|---|
| `docker-compose.mongo.yml`, `00_start_mongo.sh` | Starts MongoDB 7 in Docker |
| `01_export_from_postgres.sh` | Reads the catalogue from PostgreSQL and turns each title into one document (`data/migrated_titles.js`) |
| `02_schema_validation.js` | Creates the `titles` collection with validation rules and tests them |
| `03_load_migrated.js` | Loads the 10 migrated titles |
| `04_generate_data.js` | Adds 100,000 generated titles and 50,000 reviews (fixed seed, same every run) |
| `05_queries.js` | Find, update, upsert, delete and bulk operations |
| `06_aggregation.js` | Group, unwind, bucket, lookup, facet and merge |
| `07_indexes_explain.js` | Indexes and explain plans, before and after |
| `08_modelling_patterns.js` | Embedding vs referencing, computed and subset patterns |
| `09_reconcile.sh` | Checks PostgreSQL and MongoDB agree after the migration |
| `11_other_nosql_models.js` | Key-value (sessions), wide-column (branch-day counters) and graph (linked titles) examples |
| `12_secure_mongo.sh`, `docker-compose.mongo-secure.yml` | A second, password-protected MongoDB, and tests that try to get past it |
| `13_media_formats.js` | One title of each format (book, e-book, audiobook, DVD, magazine) with its own fields, queried and validated |
| `10_run_all_tests.sh` | Runs everything and prints one summary table |
| `evidence/` | Screenshots from my own runs |

## 3. How to run it

From the repository root, with Docker running and the PostgreSQL container from Portfolio 1 up (`docker compose up -d`):

```bash
bash portfolio-4-nosql/00_start_mongo.sh
bash portfolio-4-nosql/01_export_from_postgres.sh
docker exec -w /p4 upln_mongo mongosh --quiet upln_nosql --file 02_schema_validation.js
# ...and the same line for 03 to 08 and 11, then:
bash portfolio-4-nosql/09_reconcile.sh
```

Or run everything in one go with `bash portfolio-4-nosql/10_run_all_tests.sh`. The hardened MongoDB is separate and optional: `bash portfolio-4-nosql/12_secure_mongo.sh`. Each script clears its own earlier output first, so repeating it is safe.

## 4. Design decisions

**Embed or reference?** The rule I followed: embed what is read together and stays small, reference what grows.

- *Embedded:* authors, publisher, category, and the copies per branch. They are always shown with the title and rarely change.
- *Referenced:* reviews. A popular title could collect thousands, and a single MongoDB document cannot pass 16 MB. Reviews sit in their own collection and point back with `titleId`.

**Computed pattern.** Each title carries `rating: { sum, count }`. When a review arrives, one atomic `$inc` updates both numbers, so showing an average never means scanning reviews.

**Subset pattern.** The title page shows only the newest three reviews, so those are copied into the title (`recentReviews`). The full list stays in `reviews`.

**Validation.** MongoDB lets you store anything, which sounds nice until a typo becomes data. The `titles` collection has a `$jsonSchema` rule that requires the core fields, limits `mediaType` to a fixed list, checks that the year is a number and that copies are never negative. Optional fields (for example `durationMinutes` for an audiobook) are still allowed, so the model stays flexible where it should be.

## 5. What each test shows

Every script prints `PASS` or `FAIL` lines and also saves them in a `p4_results` collection, which the summary reads.

- **02, validation (8 checks):** one good document is accepted, six bad ones are refused (missing title, unknown media type, year as text, negative copies, ISBN with letters, author without a name), and an audiobook with extra fields is accepted.
- **03, migration (3 checks):** all 10 documents pass validation and arrive with their authors and branch counts inside them.
- **04, data (3 checks):** 100,000 titles and 50,000 reviews load; every title passed validation.
- **05, queries (10 checks):** the MongoDB version of everyday SQL, including `$inc` for atomic updates, upsert and `bulkWrite`.
- **06, aggregation (8 checks):** reports such as titles per category, busiest authors, copies per branch, average stars, publication periods and a join to reviews with `$lookup`.
- **07, indexes (the main performance evidence):** three queries explained before and after an index. Without an index MongoDB reads every document (`COLLSCAN`); with one it jumps straight to the match (`IXSCAN`). Also covers unique-sparse, partial, text and TTL indexes.
- **08, patterns (6 checks):** the embed, computed and subset patterns working on a real title.
- **11, other NoSQL families (10 checks):** a session stored and read by key with a TTL index; one wide row per branch per day with hourly counters; titles linked by shared readers and followed with `$graphLookup`.
- **13, media formats (10 checks):** a printed book, an e-book, an audiobook, a DVD and a magazine live in the same collection, each with the fields only it has (pages, file format, narrator and duration, runtime and director, issue number and date). The validation rule is extended to cover those fields, then format-specific queries run and bad values are refused.
- **12, secure MongoDB (10 checks):** anonymous access, a wrong password, a read-only account that tries to write, and an application account that reaches for the admin database or tries to create an administrator, all refused.
- **09, reconcile (5 checks):** titles, copies, free copies, author links and titles per category match PostgreSQL exactly.

### Index results

*(Copy these numbers from `evidence/07_indexes.png` after your run.)*

| Query | Before: docs examined | After: docs examined | Before ms | After ms |
|---|---|---|---|---|
| X1 find by ISBN | | | | |
| X2 category + newest year | | | | |
| X3 author inside array | | | | |

## 6. Which NoSQL family fits which part of UPLN

NoSQL is not one thing. There are four families, and each fits a different kind of question. I applied all four to the library, and implemented each so it can be checked.

| Family | UPLN need | Why it fits | Where it is implemented |
|---|---|---|---|
| **Document** | The catalogue: title, authors, publisher, category, copies per branch | A catalogue page reads all of that together. One document replaces a five-table join, and optional fields (audiobook length, e-book size) need no empty columns | Scripts 02 to 08 (the main part of this portfolio) |
| **Key-value** | Login sessions and a shopping-basket-style "reading list" | Always read and written by one key, never searched by content, and should vanish after 30 minutes. Simple and very fast | Script 11, `kv_session` with a TTL index |
| **Wide-column** | Loan counts per branch per hour, for busy-time charts | Millions of small counter updates, always read as "this branch, this day". One row per branch-day with a column per hour | Script 11, `branch_daily`. MongoDB only imitates this; the real systems for it are Cassandra and HBase |
| **Graph** | "People who borrowed this also borrowed..." recommendations | The question is about links between titles and how far you can walk along them, which is clumsy as repeated SQL joins | Script 11, `title_links` with `$graphLookup`. A dedicated graph database such as Neo4j would suit this better at scale |

**Formats.** A library lends more than printed books, and each format has its own details: a DVD has a runtime and a director, a magazine has an issue number and no ISBN or author, an audiobook has a narrator and a length. In PostgreSQL that means many mostly-empty columns or a table per format. In MongoDB each document carries only the fields it needs (script 13). Note that my PostgreSQL design from Portfolio 1 allows four media types (book, DVD, audiobook, magazine). I added `ebook` on the MongoDB side as a deliberate example of how a new format can be introduced without a table migration; the ten titles migrated from PostgreSQL contain no e-books, so the two databases still reconcile exactly.

**What stays relational.** Loans, fines, payments and members stay in PostgreSQL. They need strict rules, transactions across several tables, and exact money. Portfolio 3 showed how much work it takes to keep those correct, and none of the NoSQL families give that for free. So the system I recommend is PostgreSQL as the source of truth, with MongoDB serving the catalogue, and the other patterns added only where a real need appears.

**Honest limits of my examples.** The wide-column and graph examples run inside MongoDB to keep the lab to one technology. They show the *data model*, not the performance or distribution of Cassandra or Neo4j.

## 7. Trade-offs I noticed

- **Joins are the price of denormalising.** The catalogue is fast to read, but the free-copy count inside a title duplicates what PostgreSQL knows. If a copy is borrowed, two places must change. That is why loans stay in PostgreSQL and the MongoDB number is treated as a display copy, not the truth.
- **Indexes speed up reads and slow down writes.** Every index must be updated when a document changes, and it takes space. I only index fields that queries actually use.
- **Consistency.** A single MongoDB document is updated atomically, which is why the computed pattern is safe. Changing two documents together needs a transaction, which needs a replica set. That belongs to Portfolio 5.
- **CAP and BASE.** A catalogue can tolerate being a few seconds stale (eventual consistency). A payment cannot. That is the practical reason for splitting the system this way.

## 8. Security

The lab instance used for scripts 02 to 11 has no password, and it only listens on `127.0.0.1`, so nothing outside the machine can reach it. That keeps it easy for an assessor to run. A database like that must never be exposed, so I also built the **hardened version** and tested it (`12_secure_mongo.sh`):

| Measure | What the test shows |
|---|---|
| Authentication switched on (`--auth`) | An anonymous connection and a wrong password are both refused |
| Separate accounts with least privilege | `catalogue_app` can read and write the catalogue; `catalogue_report` can only read |
| No reach beyond the job | The application account cannot read the admin database or create users |
| Port bound to `127.0.0.1` only | Not reachable from the network |
| Random passwords in `.env.mongo`, mode 600, in `.gitignore` | Secrets never go to GitHub |

**Not done here, and I say so:** TLS for MongoDB connections and encryption at rest. Portfolio 5 shows TLS and certificate checking for PostgreSQL, and the same ideas apply (`--tlsMode requireTLS`, and disk or field-level encryption). A real deployment would also give each service its own account, rotate passwords, and keep audit logs.

## 9. Evidence

Screenshots with the clock visible are in `evidence/`: `00_mongo_started`, `01_export`, `02_validation`, `03_migration`, `04_data`, `05_queries`, `06_aggregation`, `07_indexes`, `08_patterns`, `09_reconcile`, `10_all_tests`, `11_other_models`, `12_secure_mongo`, `13_media_formats`.

## 10. AI-use note

I used Claude to help write and explain the scripts. I ran every script myself on my own machine and the numbers above come from my own screenshots. The full declaration is in the main README.
