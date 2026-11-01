# Portfolio 5: Distributed and Cloud Databases

**Course:** MIT 8103 Advanced Database Systems  **Case study:** Unity Public Library Network (UPLN), a fictional library network with branches in Abuja, Lagos, Port Harcourt, Kano and Enugu. All data is made up.

## 1. What this portfolio does

So far UPLN has lived on one database server. That is fine until the server breaks, the Lagos branch outgrows it, or someone steals a backup. This portfolio asks what changes when the library runs on **several servers**, and proves each answer by running it.

I built a small four-server cluster and tested four things:

1. **Replication.** A second copy of the database that follows the first one.
2. **Failover.** What happens when the main server dies, and how long the library is without a writer.
3. **Sharding.** Splitting the loan history by branch, so Abuja and Kano live on one server and Lagos, Port Harcourt and Enugu on another.
4. **Backup and recovery.** Getting back data that someone deleted by mistake, to an exact point in time.

Security runs through all of it: every connection uses TLS, every account has only the rights it needs, and no password or key ever goes to GitHub.

```
                  +--------------------+      TLS + SCRAM password
  application --> |  primary (writer)  | ------------------------------+
  reporting   --> |  = coordinator     |                               |
                  +---------+----------+                               |
                            | streams WAL (TLS)                        |
                  +---------v----------+      +------------------+  +--v---------------+
                  | replica (read-only)|      |  shard_north     |  |  shard_south     |
                  +--------------------+      |  ABJ, KAN loans  |  |  LOS, PHC, ENU   |
                                              +------------------+  +------------------+
```

## 2. What is in this folder

| File | What it does |
|---|---|
| `docker-compose.p5.yml`, `conf/`, `docker/`, `sql/` | The cluster itself: four PostgreSQL 16 containers, the connection rules (`pg_hba`), shared settings and account creation |
| `00_make_certs.sh` | Creates a private certificate authority, a server certificate and random passwords (kept out of GitHub) |
| `01_start_cluster.sh` | Builds and starts the cluster (`--reset` starts from nothing) |
| `02_load_primary.sh` | Loads the Portfolio 1 schema and data and sets least-privilege rights |
| `03_replication_tests.sh` | Replication, lag, read-only replica, synchronous commit |
| `04_sharding.sh` | Loan history split by branch across two shards |
| `05_security_checks.sh` | Tries to break the cluster and records what is refused |
| `06_backup_pitr.sh` | Backup and point-in-time recovery drill |
| `07_failover.sh` | Kills the primary, promotes the replica, shows split brain |
| `08_run_all_tests.sh` | Runs everything from scratch and prints one summary |
| `09_monitor.sh` | One-screen health report |
| `evidence/` | My screenshots |

## 3. How to run it

From the repository root, with Docker running:

```bash
bash portfolio-5-distributed-cloud/08_run_all_tests.sh
```

This builds the cluster, runs every test and prints one summary table. It takes about five minutes. To run the steps one at a time, use `01_start_cluster.sh --reset`, then `02` to `07` in order, and `09_monitor.sh` at any time. `07_failover.sh` changes the cluster (the replica becomes the primary), so run it last and use `--reset` before starting again.

The four servers run on the machine's own network, one port each: primary 5541, replica 5542, north shard 5543, south shard 5544 (5545 is used briefly for the recovery drill). Each listens on `127.0.0.1` only, so nothing is reachable from outside the machine.

**What went wrong on the way.** My first version put the four servers on a private Docker network. In my Codespace, Docker blocked traffic between containers on that network: the replica could not reach the primary and the shards could not reach each other, even though each server was healthy on its own. I confirmed this by testing connections between containers, then changed the setup so the servers use the host network with separate ports. A related slip earlier: connecting to `localhost` used the IPv6 address, which my `pg_hba` rules did not allow, so every script now connects to `127.0.0.1` explicitly.

## 4. Design decisions

**Why PostgreSQL streaming replication?** The replica receives the primary's change log (WAL) over a TLS connection and replays it. It is a byte-for-byte copy, so it can take over without conversion. A named replication slot stops the primary deleting log the replica still needs.

**Why shard by branch?** Staff in Lagos mostly ask about Lagos. If the shard key is the branch, a branch query goes to one server and the rest are not touched (I check this in the query plan). A network-wide report has to ask both. I chose a list of branches rather than a hash because the library already thinks in branches, and it makes it easy to see which server holds what. The drawback is uneven load if one branch grows much faster than the others.

**Why the primary is also the coordinator.** The primary holds the Portfolio 1 library data and a table called `branch_loan` that looks like one table but is made of two *foreign table* partitions (`postgres_fdw`), one per shard. That keeps the demonstration small. A bigger system would use a dedicated router.

**Security choices**

| Choice | Reason |
|---|---|
| TLS for every connection, including replication and shard links | Passwords and data cross the network encrypted, and a connection without TLS is refused |
| Own certificate authority; clients can use `verify-full` | They can tell they are talking to the real server |
| SCRAM-SHA-256 passwords | No plain or MD5 passwords stored |
| `replicator` can stream WAL but cannot open a normal SQL session | A stolen replication password does not give access to the tables |
| `p5_app`: no DELETE, no access to the `member` table | The application only has what it needs |
| `p5_report`: read-only | Reports cannot change data |
| `fdw_user` on the shards: only the loan table, cannot create objects | The coordinator link cannot be abused to change the shard |
| `pg_hba` allows only TLS + password connections from `127.0.0.1`, and the servers listen on `127.0.0.1` only | Everything else is rejected or cannot even reach the server |
| Passwords and keys in `.env.p5` and `certs/`, both in `.gitignore`, mode 600 | Secrets never go to GitHub |
| Data checksums on | Silent disk corruption is detected |

## 5. What each test shows

Each script prints `PASS` or `FAIL` and saves them in `results/`. Together there are **62 checks**.

| Script | Checks | What it proves |
|---|---|---|
| `03_replication_tests.sh` | 12 | The replica streams over TLS, shows data written on the primary within well under a second, refuses writes, and can serve reports. With synchronous commit on and the replica switched off, a commit on the primary **hangs** until cancelled |
| `04_sharding.sh` | 12 | Each branch is on its own shard, the coordinator sees all 50,000 loans, a branch query touches one shard only, a cross-shard report matches the shard totals, an insert is routed to the right shard. With one shard down, the other branches still work and a network-wide report **fails** instead of giving a wrong total |
| `05_security_checks.sh` | 20 | No-TLS refused on all four nodes, wrong password refused, no plain passwords, replication account cannot log in normally, application and report accounts limited, servers bound to 127.0.0.1, secrets not tracked by git |
| `06_backup_pitr.sh` | 9 | A base backup is verified; after a deliberate `DELETE` with no `WHERE`, a separate server restored to a chosen second brings back all rows, including those written after the backup, and none from after the chosen time |
| `07_failover.sh` | 9 | After killing the primary, the replica is writable again within a second or so (the number is in my screenshot). No committed row was lost in this run. The old primary, restarted, accepts writes of its own: that is **split brain** |

### Results from my run

These come from my own runs in a GitHub Codespace on 1 November 2026 (screenshots in `evidence/`). All figures are for a small lab database on one machine, so real systems would be slower.

| Measure | Result |
|---|---|
| Replica delay after a write | 376 ms until visible on the replica (this includes the cost of the check itself); 0 bytes behind once idle |
| Commit with synchronous replication, replica up | 107 ms |
| Commit with synchronous replication, replica down | Waited 3115 ms until I cancelled it (consistency chosen over availability) |
| Cross-shard count | 50,000 loans |
| Time for a restore (RTO) | 3.3 s (3.3 to 5.0 s across my runs) |
| Time until the new primary accepted writes after the crash | 634 ms (script-measured) |
| Rows lost in the failover | 0 of 200 (asynchronous replication does not guarantee this) |
| Rows lost in the restore (RPO) | 0 up to the chosen recovery point |

## 6. Distributed database discussion

**Replication and consistency.** By default the replica is *asynchronous*: the primary tells the user "committed" before the replica has the change. That is fast, but if the primary dies at the wrong moment the last few commits can be lost. In this lab nothing was lost, but the system does not promise that. With *synchronous* commit the primary waits for the replica to confirm. I turned it on and then stopped the replica: the commit just waited. That is the trade-off in one experiment. Synchronous replication protects the data (consistency) and costs availability, because writes stop when the replica is unreachable.

**CAP.** When the network splits, a system can keep answering (availability) or stay correct (consistency), not both. The same system behaves both ways in my tests: with a shard down, a Lagos query fails rather than guess (consistency), while an Abuja query keeps working (availability for the healthy part). For payments I would choose consistency. For a catalogue search (Portfolio 4) a slightly stale answer is acceptable.

**Availability.** A replica only helps if something promotes it. I did it by hand in a script. In production a tool such as Patroni, or a managed cloud service, detects the failure and does it, and prevents split brain by making sure the old primary cannot take writes. My test shows why that matters: the restarted old primary accepted its own writes, which the new primary never saw.

**Sharding trade-offs.** Gains: more storage and load capacity, and a failure affects only part of the data. Costs: network-wide reports must ask every shard; a transaction across two shards is not atomic here (each shard commits separately), so cross-branch transfers would need two-phase commit or careful design; and moving a branch to another shard is real work. Loans are a good fit because a loan belongs to one branch. A member who borrows in two branches is where it gets awkward.

**Backup and recovery.** A base backup plus the archived WAL lets me restore to a chosen second, not only to the moment of the backup. This is what protects against the accident that replication cannot: a replica faithfully copies a mistaken `DELETE` within a fraction of a second, so a replica is not a backup. My drill restored into a separate server and proved the rows were back before touching anything live. Recovery objectives: RPO is how much recent work you can afford to lose (here, nothing before the chosen second, as long as the WAL archive is intact), RTO is how long it takes to be back (measured in the table above, for a very small database; it grows with database size).

## 7. How this maps to a cloud deployment

| Lab piece | In a cloud |
|---|---|
| Servers bound to `127.0.0.1`, `pg_hba` rules | A private network (VPC) with private subnets; firewall rules (security groups) allowing only the application |
| Primary + replica | Managed PostgreSQL with a standby in another availability zone (automatic failover) and read replicas |
| WAL archive volume | Object storage with versioning, kept in a different region from the database |
| Own CA and `.env.p5` | Certificates from a managed CA; passwords in a secrets manager, rotated; no secrets in code |
| Passwords per role | Identity and access management for people; database roles for applications |
| Two shards | Sharded or partitioned managed service, or application-level routing |
| `09_monitor.sh` | Dashboards and alarms on replication lag, archive failures, connections, disk space and failed logins |

**Encryption at rest.** I could not prove this in the lab, so I do not claim it. In a cloud it would be switched on for the disks and backups with managed keys, and Portfolio 1 already protects the most sensitive columns inside the database with `pgcrypto`. **Shared responsibility:** the provider secures the hardware and the platform; UPLN is still responsible for who has access, what is exposed, backups that actually restore, and the data itself. Because UPLN handles personal data of Nigerian members, the Nigeria Data Protection Act 2023 applies, which is a further reason for encryption, access control and knowing where backups are stored.

## 8. Limitations

- **One machine.** All four servers share one laptop or Codespace, so there is no real network delay or real hardware failure. Replica delay in production would be larger.
- **Manual failover.** There is no automatic failover manager, and I did not script rebuilding the old primary as a replica (failback). The usual route is `pg_rewind`, or deleting its data and taking a fresh base backup from the new primary.
- **Cross-shard transactions are not atomic**, as explained above.
- **Self-made certificates.** Fine for a lab; a real deployment would use a proper CA. The same server certificate is used by all four nodes for simplicity.
- **MongoDB** (Portfolio 4) runs as a single node. Replica sets and sharding exist there too and follow the same ideas, but I did not run them.
- **Encryption at rest** is discussed, not demonstrated.

## 9. Evidence

Screenshots with the clock visible are in `evidence/`: `01_cluster_up`, `02_load_primary`, `03_replication`, `04_sharding`, `05_security`, `06_backup_pitr`, `07_failover`, `07_after_failover_monitor`, `08_all_tests` and `09_monitor`.

## 10. AI-use note

I used Claude to help design and write the scripts and to explain the concepts. I ran everything myself on my own machine, and the numbers in this README come from my own screenshots. The full declaration is in the main README.

## 11. References

- PostgreSQL 16 documentation: [High Availability, Load Balancing and Replication](https://www.postgresql.org/docs/16/high-availability.html), [Continuous Archiving and PITR](https://www.postgresql.org/docs/16/continuous-archiving.html), [postgres_fdw](https://www.postgresql.org/docs/16/postgres-fdw.html), [SSL Support](https://www.postgresql.org/docs/16/ssl-tcp.html), [The pg_hba.conf File](https://www.postgresql.org/docs/16/auth-pg-hba-conf.html), [Table Partitioning](https://www.postgresql.org/docs/16/ddl-partitioning.html)
- Brewer, E. (2012). CAP twelve years later: How the "rules" have changed. *IEEE Computer*, 45(2), 23-29.
