# Portfolio 5: Distributed and Cloud Databases

**Course:** MIT 8103 Advanced Database Systems  
**Case study:** Unity Public Library Network (UPLN), a fictional library network with branches in Abuja, Lagos, Port Harcourt, Kano and Enugu. All data is synthetic.

## 1. Objectives and Scope

In the earlier relational portfolios, I worked with a single PostgreSQL server. In this portfolio, I extended the UPLN case study to a four-server PostgreSQL 16 cluster to examine replication, availability, sharding, backup and recovery. I implemented and tested four areas:

1. **Replication:** a standby server receiving and replaying changes from the primary.
2. **Failover:** promoting the replica after stopping the primary and measuring when it accepted writes.
3. **Sharding:** distributing loan history by branch, with Abuja and Kano on one shard and Lagos, Port Harcourt and Enugu on another.
4. **Backup and recovery:** restoring data deleted by mistake to a chosen point in time.

I also tested TLS connections, SCRAM-SHA-256 authentication, database permissions and the handling of passwords and certificates outside the repository.

```text
                         Application / reporting
                                  |
                             TLS + SCRAM
                                  |
                      +-----------v------------+
                      | Primary / coordinator  |
                      | Port 5541              |
                      +------+-----------+-----+
                             |           |
                WAL over TLS |           | postgres_fdw (TLS)
                             v           +--------------------+
                      +-------------+         |                |
                      | Replica     |         v                v
                      | Port 5542   |   +--------------+  +---------------+
                      | Read-only   |   | North shard  |  | South shard   |
                      +-------------+   | Port 5543    |  | Port 5544     |
                                        | ABJ, KAN     |  | LOS, PHC, ENU |
                                        +--------------+  +---------------+

                   Temporary PITR server: port 5545 (restore drill)
```

## 2. Implementation Files

| File | Purpose |
|---|---|
| `Akosa_Antonella_301929153_P5_docker-compose.p5.yml`, `conf/`, `docker/`, `sql/` | Define the four PostgreSQL 16 containers, `pg_hba` connection rules, shared settings and account creation |
| `Akosa_Antonella_301929153_P5_00_make_certs.sh` | Creates a private certificate authority, a server certificate and random passwords kept out of GitHub |
| `Akosa_Antonella_301929153_P5_01_start_cluster.sh` | Builds and starts the cluster; `--reset` starts from a clean state |
| `Akosa_Antonella_301929153_P5_02_load_primary.sh` | Loads the Portfolio 1 schema and data and assigns least-privilege permissions |
| `Akosa_Antonella_301929153_P5_03_replication_tests.sh` | Tests streaming replication, lag, read-only access and synchronous commit |
| `Akosa_Antonella_301929153_P5_04_sharding.sh` | Distributes loan history across two branch-based shards |
| `Akosa_Antonella_301929153_P5_05_security_checks.sh` | Tests connection security and permission restrictions |
| `Akosa_Antonella_301929153_P5_06_backup_pitr.sh` | Tests backup and point-in-time recovery (PITR) |
| `Akosa_Antonella_301929153_P5_07_failover.sh` | Stops the primary, promotes the replica and demonstrates split brain |
| `Akosa_Antonella_301929153_P5_08_run_all_tests.sh` | Runs the tests from a clean state and produces a summary |
| `Akosa_Antonella_301929153_P5_09_monitor.sh` | Reports cluster health on one screen |
| `evidence/` | Contains my screenshots |

## 3. Cluster Deployment and Test Execution

With Docker running, I used the following command from the repository root:

```bash
bash portfolio-5-distributed-cloud/Akosa_Antonella_301929153_P5_08_run_all_tests.sh
```

This script builds the cluster, runs the tests and prints a summary table. The full run takes about five minutes. I can also run the stages individually: `Akosa_Antonella_301929153_P5_01_start_cluster.sh --reset`, followed by scripts `02` to `07` in order, with `Akosa_Antonella_301929153_P5_09_monitor.sh` available for monitoring. I run `Akosa_Antonella_301929153_P5_07_failover.sh` last because it promotes the replica and changes the cluster state. I use `--reset` before repeating the complete exercise.

All four PostgreSQL servers run on the same machine using separate ports: primary **5541**, replica **5542**, north shard **5543** and south shard **5544**. Port **5545** is used temporarily during the recovery drill. The servers listen on `127.0.0.1`, rather than on an externally accessible interface.

**Deployment problem and resolution.** I initially placed the four servers on a private Docker network. In my Codespace, traffic between containers on that network was blocked: the replica could not reach the primary, and the shards could not reach each other, although each server was running. I tested connectivity between containers, then changed the configuration to use the host network and separate ports. I also found that `localhost` resolved to an IPv6 address that my `pg_hba` rules did not permit. I therefore used `127.0.0.1` explicitly in the scripts.

## 4. Architecture and Design Decisions

**Streaming replication.** I used PostgreSQL physical streaming replication. The standby receives the primary's write-ahead log (WAL) over TLS and replays it to maintain a physical copy of the database. I configured a named replication slot to retain WAL required by the standby. This arrangement lets the standby be promoted without converting the data to another database format, although asynchronous replication can lag behind the primary.

**Branch-based sharding.** I used a list of branches as the shard key. Abuja and Kano share the north shard; Lagos, Port Harcourt and Enugu share the south shard. I chose this arrangement because a branch-specific loan query can target one shard, which I checked in the query plan, whereas a network-wide report must read both shards. List-based placement also makes each branch's location clear. The limitation is that the workload may become uneven if one branch grows faster than the others.

**Primary as coordinator.** I kept the Portfolio 1 library data on the primary and used it as the coordinator for `branch_loan`. This presents one logical table made from two foreign-table partitions through `postgres_fdw`, one on each shard. I used this arrangement to keep the lab small. A larger deployment could use a separate routing or coordination service.

**Security configuration**

| Choice | Reason |
|---|---|
| TLS for connections, including replication and shard links | Encrypts data and passwords in transit; connections without TLS are refused |
| Private certificate authority; clients can use `verify-full` | Supports verification of the server identity |
| SCRAM-SHA-256 passwords | Avoids storing plaintext or MD5 password hashes |
| `replicator` can stream WAL but cannot open a normal SQL session | Restricts the replication account's access to database tables |
| `p5_app`: no DELETE and no access to `member` | Limits the application's permissions |
| `p5_report`: read-only | Prevents the reporting account from changing data |
| `fdw_user` on the shards: loan-table access only; cannot create objects | Limits the coordinator's access on each shard |
| `pg_hba` permits TLS and password connections from `127.0.0.1`; servers listen on `127.0.0.1` | Restricts connections to the permitted local interface and authentication method |
| Passwords and keys in `.env.p5` and `certs/`, in `.gitignore`, with mode 600 | Keeps generated secrets out of the Git repository and restricts file access |
| Data checksums enabled | Provides a means of detecting data-page corruption |

## 5. Test Methodology and Recorded Results

The scripts print `PASS` or `FAIL` results and save their output in `results/`. My run recorded **62 checks** across the five test scripts.

| Script | Checks | Recorded verification |
|---|---|---|
| `Akosa_Antonella_301929153_P5_03_replication_tests.sh` | 12 | I verified TLS streaming, replica visibility after a primary write, rejection of writes on the replica and reporting access. With synchronous commit enabled and the replica stopped, the primary's commit waited until I cancelled it |
| `Akosa_Antonella_301929153_P5_04_sharding.sh` | 12 | I verified that each branch is assigned to one of the two shards, that the coordinator returns **50,000 loans**, that branch queries reach one shard, that cross-shard reports match the shard totals and that inserts are routed correctly. With one shard down, the healthy branches remained accessible while a network-wide report failed rather than returning an incomplete total |
| `Akosa_Antonella_301929153_P5_05_security_checks.sh` | 20 | I tested refusal of non-TLS connections on all four nodes and incorrect passwords, SCRAM password storage, restrictions on the replication, application and reporting roles, loopback-only listening and exclusion of secrets from Git tracking |
| `Akosa_Antonella_301929153_P5_06_backup_pitr.sh` | 9 | I verified a base backup, performed a deliberate `DELETE` without `WHERE`, and restored to a selected time on a separate server. Rows committed after the backup but before the recovery point were restored; changes after that point were not included |
| `Akosa_Antonella_301929153_P5_07_failover.sh` | 9 | I stopped the primary, promoted the replica and measured when it accepted writes. No committed rows were lost in this run. I also restarted the old primary and confirmed that it accepted independent writes, demonstrating split brain |

### 5.1 Results from My Run

I recorded these results in a GitHub Codespace on **1 November 2026**. They describe this single-machine laboratory exercise and are not production performance targets.

| Measure | Result |
|---|---|
| Replica delay after a write | **376 ms** until visible on the replica (including the measurement check); **0 bytes** behind once idle |
| Commit with synchronous replication, replica up | **107 ms** |
| Commit with synchronous replication, replica down | Waited **3115 ms** until I cancelled it (consistency chosen over availability) |
| Cross-shard count | **50,000 loans** |
| Measured restore time (laboratory recovery drill, not a complete service RTO) | **3.3 s** (**3.3 to 5.0 s** across my runs) |
| Time until the promoted replica accepted writes after the primary stopped | **634 ms** (script-measured) |
| Rows lost in the failover | **0 of 200** (asynchronous replication does not guarantee this outcome) |
| Rows lost in the restore | **0** up to the chosen recovery point (the observed PITR result, not a general zero-loss guarantee) |

## 6. Distributed Database Discussion

**Replication and consistency.** I compared asynchronous and synchronous replication. With asynchronous replication, the primary can confirm a commit before the standby has replayed its WAL. This avoids waiting for the replica but risks losing recent acknowledged writes if the primary fails before they reach it. My failover test lost no committed rows, but asynchronous replication does not guarantee that result. With synchronous commit, the primary waits for the required standby acknowledgement. When I stopped the replica, the commit waited for **3115 ms** until I cancelled it. This demonstrates the trade-off between protecting acknowledged writes and keeping writes available when the standby is unreachable.

**CAP and shard availability.** CAP concerns consistency and availability *during a network partition*. My test stopped a shard; it did not simulate a separate network partition. In that test, a Lagos query depending on the unavailable shard failed rather than return an incomplete result, while an Abuja query served by the healthy shard continued. Network-wide reporting also failed rather than give a wrong total. The test therefore demonstrates partial availability during a shard outage, not a CAP partition experiment. For payments I would prioritise consistency; for the catalogue discussed in Portfolio 4, a slightly stale search result may be acceptable.

**Failover and split brain.** A standby must be promoted before it can accept writes. I initiated promotion through `Akosa_Antonella_301929153_P5_07_failover.sh` after stopping the primary; the promoted replica accepted writes after **634 ms**. This was script-controlled, not automatic failover. I then restarted the old primary and found that it accepted new writes independently. Those writes did not appear on the promoted server, so two writable copies could diverge: this is the **split-brain** condition demonstrated by my test. A production failover manager such as Patroni, or a managed cloud service, would need to prevent the former primary from taking writes until it is safely rebuilt or rejoined. I did not implement that protection here.

**Sharding trade-offs.** I used two branch-based shards to distribute loan storage and branch-specific queries. A branch query can reach one shard; a network-wide report must query both. Separating the data also means a shard failure affects only some branch operations, while reports requiring all shards cannot complete. **Cross-shard transactions are not atomic** in this implementation: each shard commits separately, so a cross-branch operation could be partly committed. Two-phase commit or a carefully designed recovery process would be needed to handle that risk; I did not implement distributed atomic commits. Moving a branch between shards would require further work, and one branch growing faster than others could unbalance the workload. A member borrowing across branches adds another complication.

**Backup and recovery.** Replication is not a substitute for backup: an accidental `DELETE` is replicated too. I tested recovery with a base backup and archived WAL, restoring onto a separate server to a chosen point before the deletion. The records were recovered without changing the running primary, and subsequent changes were excluded. RPO describes acceptable data loss; my result was **0 rows lost up to the selected recovery point**, provided the needed WAL was available, not a guarantee of zero loss after that point. RTO is the time required to restore service. My measured restore took **3.3 s** (**3.3 to 5.0 s** across runs), but this small lab measurement does not include failure detection, reconnection or application recovery and is not a complete production RTO. Actual recovery time depends on database size and deployment conditions.

## 7. Cloud Deployment Considerations

I used the laboratory components to describe how the same design could be deployed in a cloud environment. The table is a proposed mapping, not a cloud deployment that I tested.

| Laboratory component | Cloud equivalent or consideration |
|---|---|
| Servers bound to `127.0.0.1`, `pg_hba` rules | Private network (VPC), private subnets and security groups restricting application access |
| Primary and replica | Managed PostgreSQL with a standby in another availability zone, automatic failover and read replicas |
| WAL archive volume | Versioned object storage in a region separate from the database |
| Private CA and `.env.p5` | Managed certificates and a secrets manager with password rotation; no credentials committed to source code |
| Passwords assigned to database roles | Identity and access management for people and database roles for applications |
| Two branch-based shards | Sharded or partitioned managed service, or application-level routing |
| `Akosa_Antonella_301929153_P5_09_monitor.sh` | Dashboards and alarms for replica lag, archive failures, connections, disk space and failed logins |

**Encryption at rest.** I did not demonstrate disk or backup encryption in this lab. For a cloud deployment, I would require encryption of database volumes and backups using managed keys. Portfolio 1 separately demonstrated column-level protection using `pgcrypto`. Under a shared-responsibility model, the provider manages parts of the underlying platform, while the organisation remains responsible for access controls, data handling, backup verification and configuration. A real library processing Nigerian members' personal data would also need to consider the Nigeria Data Protection Act 2023 when designing access, encryption, retention and backup locations.

## 8. Implementation Limitations

- **Single-machine deployment.** All four servers ran on one laptop or Codespace, so I did not test separate hardware failures, availability zones or realistic network delay. The **376 ms** replica visibility measurement includes the check itself; production lag may differ.
- **Manual failover and split brain.** I promoted the replica with `Akosa_Antonella_301929153_P5_07_failover.sh`, without an automatic failover manager. I did not rebuild the old primary as a standby or test failback. Options include `pg_rewind` or replacing its data with a fresh base backup. Restarting the old primary showed why its ability to accept independent writes must be controlled.
- **Cross-shard transactions are not atomic.** Each shard commits separately. I did not implement two-phase commit or another mechanism to commit changes across shards as one transaction; cross-branch workflows could therefore be left partially complete.
- **Self-generated certificates.** I used a private CA and the same server certificate for all four nodes. This was suitable for the lab, but not the certificate-management arrangement I would choose for production.
- **MongoDB.** Portfolio 4 runs MongoDB as a single node. I did not test MongoDB replica sets or sharding.
- **Encryption at rest and recovery targets.** Disk and backup encryption were discussed, not demonstrated. The measured restore and failover timings are laboratory results, not validated production RTO or RPO objectives.

## 9. Supporting Evidence

I recorded ten screenshots with the clock visible in `evidence/`: `Akosa_Antonella_301929153_P5_01_cluster_up`, `Akosa_Antonella_301929153_P5_02_load_primary`, `Akosa_Antonella_301929153_P5_03_replication`, `Akosa_Antonella_301929153_P5_04_sharding`, `Akosa_Antonella_301929153_P5_05_security`, `Akosa_Antonella_301929153_P5_06_backup_pitr`, `Akosa_Antonella_301929153_P5_07_failover`, `Akosa_Antonella_301929153_P5_07_after_failover_monitor`, `Akosa_Antonella_301929153_P5_08_all_tests` and `Akosa_Antonella_301929153_P5_09_monitor`.

## 10. References

- PostgreSQL Global Development Group. *PostgreSQL 16 Documentation: High Availability, Load Balancing, and Replication*. https://www.postgresql.org/docs/16/high-availability.html
- PostgreSQL Global Development Group. *PostgreSQL 16 Documentation: Continuous Archiving and Point-in-Time Recovery (PITR)*. https://www.postgresql.org/docs/16/continuous-archiving.html
- PostgreSQL Global Development Group. *PostgreSQL 16 Documentation: postgres_fdw*. https://www.postgresql.org/docs/16/postgres-fdw.html
- PostgreSQL Global Development Group. *PostgreSQL 16 Documentation: Secure TCP/IP Connections with SSL*. https://www.postgresql.org/docs/16/ssl-tcp.html
- PostgreSQL Global Development Group. *PostgreSQL 16 Documentation: The pg_hba.conf File*. https://www.postgresql.org/docs/16/auth-pg-hba-conf.html
- PostgreSQL Global Development Group. *PostgreSQL 16 Documentation: Table Partitioning*. https://www.postgresql.org/docs/16/ddl-partitioning.html
- Brewer, E. (2012). CAP twelve years later: How the "rules" have changed. *IEEE Computer*, 45(2), 23-29.
- MIVA Open University (n.d.). *MIT 8103 Advanced Database Systems, Live Lesson I: Distributed databases and the CAP theorem* [Lecture slides].
