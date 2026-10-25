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
| `10_run_all_tests.sh` | Runs everything and prints one summary table |
| `evidence/` | Screenshots from my own runs |

## 3. How to run it

From the repository root, with Docker running and the PostgreSQL container from Portfolio 1 up (`docker compose up -d`):

```bash
bash portfolio-4-nosql/00_start_mongo.sh
bash portfolio-4-nosql/01_export_from_postgres.sh
docker exec -w /p4 upln_mongo mongosh --quiet upln_nosql --file 02_schema_validation.js
# ...and the same line for 03 to 08, then:
bash portfolio-4-nosql/09_reconcile.sh
```

Or run everything in one go with `bash portfolio-4-nosql/10_run_all_tests.sh`. Each script clears its own earlier output first, so repeating it is safe.

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
- **09, reconcile (5 checks):** titles, copies, free copies, author links and titles per category match PostgreSQL exactly.

### Index results

*(Copy these numbers from `evidence/07_indexes.png` after your run.)*

| Query | Before: docs examined | After: docs examined | Before ms | After ms |
|---|---|---|---|---|
| X1 find by ISBN | | | | |
| X2 category + newest year | | | | |
| X3 author inside array | | | | |

## 6. Trade-offs I noticed

- **Joins are the price of denormalising.** The catalogue is fast to read, but the free-copy count inside a title duplicates what PostgreSQL knows. If a copy is borrowed, two places must change. That is why loans stay in PostgreSQL and the MongoDB number is treated as a display copy, not the truth.
- **Indexes speed up reads and slow down writes.** Every index must be updated when a document changes, and it takes space. I only index fields that queries actually use.
- **Consistency.** A single MongoDB document is updated atomically, which is why the computed pattern is safe. Changing two documents together needs a transaction, which needs a replica set. That belongs to Portfolio 5.
- **CAP and BASE.** A catalogue can tolerate being a few seconds stale (eventual consistency). A payment cannot. That is the practical reason for splitting the system this way.

## 7. Hardening notes

The Docker setup binds MongoDB to `127.0.0.1` only, so it is not reachable from outside the machine. For a real deployment I would add authentication with a least-privilege user per service, TLS, and a backup job. I did not enable authentication here to keep the portfolio runnable by an assessor in one command, and I am saying so openly.

## 8. Evidence

Screenshots with the clock visible are in `evidence/`: `00_mongo_started`, `01_export`, `02_validation`, `03_migration`, `04_data`, `05_queries`, `06_aggregation`, `07_indexes`, `08_patterns`, `09_reconcile`, `10_all_tests`.

## 9. AI-use note

I used Claude to help write and explain the scripts. I ran every script myself on my own machine and the numbers above come from my own screenshots. The full declaration is in the main README.
