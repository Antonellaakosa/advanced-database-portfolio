# Portfolio 4: NoSQL and Advanced Data Models (MongoDB)

**Course:** MIT 8103 Advanced Database Systems  **Case study:** Unity Public Library Network (UPLN), a fictional library network with branches in Abuja, Lagos, Port Harcourt, Kano and Enugu. All data is made up.

## 1. Objectives and Scope

In Portfolio 1, I modelled the library in PostgreSQL using 17 related tables. In this portfolio, I examined which data would suit a document model and the trade-offs involved in using MongoDB.

I selected the **book catalogue**, where a catalogue page brings together a title, its authors, publisher, category and copy counts by branch. PostgreSQL uses joins across five tables for this information; MongoDB can hold it in one document. I kept members, loans, fines and payments in PostgreSQL because they rely on the transaction and integrity controls tested in Portfolio 3.

Using PostgreSQL for transactional records and MongoDB for catalogue data illustrates *polyglot persistence*.

| Data | Where it lives | Why |
|---|---|---|
| Members, loans, fines, payments | PostgreSQL | Needs ACID transactions and strict rules |
| Catalogue (titles, authors, availability) | MongoDB | Read as a whole, flexible fields, easy to search |
| Reviews | MongoDB (own collection) | Grow without limit, so referenced rather than embedded |

## 2. Implementation Files

| File | What it does |
|---|---|
| `Akosa_Antonella_301929153_P4_docker-compose.mongo.yml`, `Akosa_Antonella_301929153_P4_00_start_mongo.sh` | Starts MongoDB 7 in Docker |
| `Akosa_Antonella_301929153_P4_01_export_from_postgres.sh` | Reads the catalogue from PostgreSQL and turns each title into one document (`data/Akosa_Antonella_301929153_P4_migrated_titles.js`) |
| `Akosa_Antonella_301929153_P4_02_schema_validation.js` | Creates the `titles` collection with validation rules and tests them |
| `Akosa_Antonella_301929153_P4_03_load_migrated.js` | Loads the 10 migrated titles |
| `Akosa_Antonella_301929153_P4_04_generate_data.js` | Adds 100,000 generated titles and 50,000 reviews (fixed seed, same every run) |
| `Akosa_Antonella_301929153_P4_05_queries.js` | Find, update, upsert, delete and bulk operations |
| `Akosa_Antonella_301929153_P4_06_aggregation.js` | Group, unwind, bucket, lookup, facet and merge |
| `Akosa_Antonella_301929153_P4_07_indexes_explain.js` | Indexes and explain plans, before and after |
| `Akosa_Antonella_301929153_P4_08_modelling_patterns.js` | Embedding vs referencing, computed and subset patterns |
| `Akosa_Antonella_301929153_P4_09_reconcile.sh` | Checks PostgreSQL and MongoDB agree after the migration |
| `Akosa_Antonella_301929153_P4_11_other_nosql_models.js` | Key-value sessions (with a basket field), wide-column (branch-day counters) and graph (linked titles) examples |
| `Akosa_Antonella_301929153_P4_12_secure_mongo.sh`, `Akosa_Antonella_301929153_P4_docker-compose.mongo-secure.yml` | A second, password-protected MongoDB, and tests that try to get past it |
| `Akosa_Antonella_301929153_P4_13_media_formats.js` | One title of each format (book, e-book, audiobook, DVD, magazine) with its own fields, queried and validated |
| `Akosa_Antonella_301929153_P4_10_run_all_tests.sh` | Runs everything and prints one summary table |
| `evidence/` | Screenshots from my own runs |

## 3. Execution Procedure

I used the following commands from the repository root, with Docker running and the Portfolio 1 PostgreSQL container started (`docker compose -f Akosa_Antonella_301929153_docker-compose.yml up -d`):

```bash
bash portfolio-4-nosql/Akosa_Antonella_301929153_P4_00_start_mongo.sh
bash portfolio-4-nosql/Akosa_Antonella_301929153_P4_01_export_from_postgres.sh
docker exec -w /p4 upln_mongo mongosh --quiet upln_nosql --file Akosa_Antonella_301929153_P4_02_schema_validation.js
# ...and the same line for 03 to 08 and 11, then:
bash portfolio-4-nosql/Akosa_Antonella_301929153_P4_09_reconcile.sh
```

I used `bash portfolio-4-nosql/Akosa_Antonella_301929153_P4_10_run_all_tests.sh` to run the scripted checks and obtain the summary. The hardened MongoDB test is separate and optional: `bash portfolio-4-nosql/Akosa_Antonella_301929153_P4_12_secure_mongo.sh`. Each script clears its earlier output before rerunning.

## 4. Document Modelling and Design Decisions

**Embedding and referencing.** I embedded related information that is read with a title and remains small, while referencing information that can grow independently.

- **Embedded:** Authors, publisher, category and copy counts by branch are kept with the title because they are read together and change infrequently.
- **Referenced:** Reviews are stored in a separate collection using `titleId`. A popular title can have thousands of reviews, while a MongoDB document has a 16 MB size limit.

**Computed pattern.** Each title stores `rating: { sum, count }`. I used one atomic `$inc` to update both values when adding a review, allowing the average to be calculated without scanning the reviews collection.

**Subset pattern.** I stored the three newest reviews in the title's `recentReviews` field for display, while retaining the full review history in `reviews`.

**Schema validation.** I added a `$jsonSchema` validator to `titles` to require core fields, restrict `mediaType` to an allowed list, require a numeric year and reject negative copy counts. Format-specific fields, such as an audiobook's `durationMinutes`, remain optional. This keeps the document model flexible without accepting invalid core data.

## 5. Implementation Tests and Results

I checked the scripts using their `PASS` and `FAIL` results, which are also recorded in `p4_results` for the summary.

- **02, validation (8 checks):** one good document is accepted, six bad ones are refused (missing title, unknown media type, year as text, negative copies, ISBN with letters, author without a name), and an audiobook with extra fields is accepted.
- **03, migration (3 checks):** all 10 documents pass validation and arrive with their authors and branch counts inside them.
- **04, data (3 checks):** 100,000 titles and 50,000 reviews load; every title passed validation.
- **05, queries (10 checks):** the MongoDB version of everyday SQL, including `$inc` for atomic updates, upsert and `bulkWrite`.
- **06, aggregation (8 checks):** reports such as titles per category, busiest authors, copies per branch, average stars, publication periods and a join to reviews with `$lookup`.
- **07, indexes (main performance evidence):** three queries compared before and after indexing using `COLLSCAN` and `IXSCAN` plans. The script also tests unique-sparse, partial, text and TTL indexes. X3 has a `LIMIT 50`, so its unindexed scan stops before examining the entire collection.
- **08, patterns (6 checks):** the embed, computed and subset patterns working on a real title.
- **11, other NoSQL families (10 checks):** a session stored and retrieved by key with a TTL index, including a `basket` array of title IDs `[4242, 1017]` that is emptied in check K3; one wide row per branch per day with hourly counters; and titles linked by shared readers, traversed using `$graphLookup`.
- **13, media formats (10 checks):** a printed book, an e-book, an audiobook, a DVD and a magazine live in the same collection, each with the fields only it has (pages, file format, narrator and duration, runtime and director, issue number and date). The validation rule is extended to cover those fields, then format-specific queries run and bad values are refused.
- **12, secure MongoDB (10 checks):** anonymous access, a wrong password, a read-only account that tries to write, and an application account that reaches for the admin database or tries to create an administrator, all refused.
- **09, reconcile (5 checks):** titles, copies, free copies, author links and titles per category match PostgreSQL exactly.

### 5.1 Indexing Results and Execution Plans

I recorded the following results from `Akosa_Antonella_301929153_P4_07_indexes_explain.js` in `evidence/Akosa_Antonella_301929153_P4_07_indexes.png`. The times are **averages of five runs**, as reported in the screenshot. They describe this lab run rather than fixed timings for other environments.

| Query | Before: docs examined | After: docs examined | Before ms | After ms |
|---|---|---|---|---|
| X1 find by ISBN | 100,010 | 1 | 43.80 | 1.20 |
| X2 category + newest year | 100,010 | 20 | 51.00 | 1.80 |
| X3 author inside array | 11,507 | 50 | 12.80 | 1.80 |

For X1 and X2, the unindexed `COLLSCAN` examined all 100,010 titles. X3 examined 11,507 before indexing because its `LIMIT 50` stopped the collection scan after 50 matches. After indexing, the plan used `IXSCAN` with `FETCH` and examined 50 documents. The screenshot records 14 `PASS` and 0 `FAIL` results for the index tests.

## 6. NoSQL Models and Suitability for UPLN

I used UPLN to compare four NoSQL data models. The document model is implemented in MongoDB; the key-value, wide-column and graph examples also run in MongoDB to demonstrate their data structures and operations.

| Family | UPLN need | Why it fits | Where it is implemented |
|---|---|---|---|
| **Document** | The catalogue: title, authors, publisher, category, copies per branch | A catalogue page reads all of that together. One document replaces a five-table join, and optional fields (audiobook length, e-book size) need no empty columns | Scripts 02 to 08 (the main part of this portfolio) |
| **Key-value** | Login sessions containing a `basket` field of title IDs | I read and write sessions by key, not by searching their contents. A TTL index is configured for expiry after 30 minutes. The basket is inside the session, not a separate reading-list collection | Script 11, `kv_session` with a TTL index |
| **Wide-column** | Loan counts per branch per hour, for busy-time charts | Millions of small counter updates, always read as "this branch, this day". One row per branch-day with a column per hour | Script 11, `branch_daily`. MongoDB only imitates this; the real systems for it are Cassandra and HBase |
| **Graph** | "People who borrowed this also borrowed..." recommendations | The question is about links between titles and how far you can walk along them, which is clumsy as repeated SQL joins | Script 11, `title_links` with `$graphLookup`. A dedicated graph database such as Neo4j would suit this better at scale |

**Media formats.** A DVD has a runtime and director, a magazine has an issue number but no ISBN or author, and an audiobook has a narrator and duration. In a fixed relational design, these differences may require nullable columns or separate tables. MongoDB lets me keep only the relevant attributes in each document (script 13). My Portfolio 1 PostgreSQL schema supports four types (book, DVD, audiobook and magazine). I added `ebook` in MongoDB to demonstrate a new media type without a table migration. None of the 10 titles migrated from PostgreSQL are e-books, so the migration reconciliation still matches.

**Relational data retained.** I kept loans, fines, payments and members in PostgreSQL because they require integrity rules, multi-table transactions and accurate monetary records. Portfolio 3 tests the relevant transaction controls. My proposed design uses PostgreSQL as the source of truth and MongoDB for catalogue reads, adding other models only where their access patterns justify them.

**Scope of the model examples.** I used MongoDB to illustrate the wide-column and graph structures. I did not deploy Cassandra or Neo4j, so these examples do not measure either system's performance or distribution.

## 7. Technical Trade-offs and Limitations

- **Denormalised data.** Storing a free-copy count inside each title duplicates availability information held in PostgreSQL. After a loan, the two values may differ until the catalogue is updated. I therefore treat the MongoDB count as display information and keep the loan record in PostgreSQL.
- **Index costs.** The tested indexes improved reads, but indexes also consume space and require maintenance during writes. I chose indexes for the queries demonstrated here.
- **Atomicity and consistency.** The computed rating uses an atomic update within one MongoDB document. Atomic changes spanning multiple documents require a transaction on a replica set or sharded deployment; I did not implement MongoDB multi-document transactions. Portfolio 5 instead uses PostgreSQL.
- **CAP and BASE considerations.** My proposed catalogue can tolerate some delay before displaying changed availability, whereas a payment needs an accurate balance. This informs the choice to keep transactional records in PostgreSQL.

## 8. Authentication and Security Controls

I ran scripts 02 to 11 against a lab MongoDB instance without password authentication, with its host port bound to `127.0.0.1`. I also created and tested a separate **hardened instance** using `Akosa_Antonella_301929153_P4_12_secure_mongo.sh`:

| Measure | What the test shows |
|---|---|
| Authentication switched on (`--auth`) | An anonymous connection and a wrong password are both refused |
| Separate accounts with least privilege | `catalogue_app` can read and write the catalogue; `catalogue_report` can only read |
| No reach beyond the job | The application account cannot read the admin database or create users |
| Port bound to `127.0.0.1` only | Not reachable from the network |
| Random passwords in `.env.mongo`, mode 600, in `.gitignore` | Test credentials are stored outside the tracked repository files |

**Security limitations.** I did not implement TLS for MongoDB or encryption at rest. Portfolio 5 demonstrates TLS and certificate validation for PostgreSQL, not MongoDB. A production MongoDB deployment would need its own TLS configuration (`--tlsMode requireTLS`), storage or field-level encryption, separate service accounts, password rotation and audit logging.

## 9. Supporting Evidence

I recorded screenshots with the clock visible in `evidence/`. The screenshot names below correspond to each implementation stage; `Akosa_Antonella_301929153_P4_07_indexes.png` is the index-plan screenshot reviewed for this README.

| Screenshot name in `evidence/` | Implementation evidence |
|---|---|
| `Akosa_Antonella_301929153_P4_00_mongo_started`, `Akosa_Antonella_301929153_P4_01_export` | MongoDB start-up and catalogue export |
| `Akosa_Antonella_301929153_P4_02_validation`, `Akosa_Antonella_301929153_P4_03_migration` | Schema validation and migrated catalogue documents |
| `Akosa_Antonella_301929153_P4_04_data`, `Akosa_Antonella_301929153_P4_05_queries` | Generated dataset and document operations |
| `Akosa_Antonella_301929153_P4_06_aggregation`, `Akosa_Antonella_301929153_P4_07_indexes` | Aggregation and index/explain results |
| `Akosa_Antonella_301929153_P4_08_patterns`, `Akosa_Antonella_301929153_P4_09_reconcile` | Modelling patterns and PostgreSQL/MongoDB reconciliation |
| `Akosa_Antonella_301929153_P4_10_all_tests`, `Akosa_Antonella_301929153_P4_11_other_models` | Overall test summary and other NoSQL model examples |
| `Akosa_Antonella_301929153_P4_12_secure_mongo`, `Akosa_Antonella_301929153_P4_13_media_formats` | Authentication checks and format-specific modelling |

## 10. References

- MIVA Open University (n.d.). *MIT 8103 Advanced Database Systems* course materials (NoSQL and advanced data models).
- MongoDB (n.d.). *Data Modelling*. https://www.mongodb.com/docs/v7.0/data-modeling/
- MongoDB (n.d.). *Schema Validation*. https://www.mongodb.com/docs/v7.0/core/schema-validation/
- MongoDB (n.d.). *Explain Results*. https://www.mongodb.com/docs/v7.0/reference/explain-results/
- MongoDB (n.d.). *TTL Indexes*. https://www.mongodb.com/docs/v7.0/core/index-ttl/
- MongoDB (n.d.). *Aggregation Pipeline*. https://www.mongodb.com/docs/v7.0/core/aggregation-pipeline/
- MongoDB (n.d.). *Transactions*. https://www.mongodb.com/docs/v7.0/core/transactions/
