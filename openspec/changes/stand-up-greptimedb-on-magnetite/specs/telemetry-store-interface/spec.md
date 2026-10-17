## ADDED Requirements

### Requirement: Listeners are bound to loopback only

The machine SHALL bind the telemetry store's HTTP listener to `127.0.0.1:4000` and its gRPC listener to `127.0.0.1:4001`, SHALL disable its MySQL, PostgreSQL, InfluxDB, OpenTSDB and Jaeger listeners, and SHALL open no firewall port for the telemetry store.
gRPC is bound to loopback rather than disabled, because the telemetry store's v1.2.1 configuration offers no setting that disables it.

#### Scenario: The HTTP listener is configured on a non-loopback address

- **WHEN** magnetite's configuration binds the telemetry store's HTTP listener to `0.0.0.0`
- **THEN** the evaluation-time envelope check (R7.1) fails, which is one of its seven mutants, and the evaluation-time ownership and bind check (R8.2) fails as well

#### Scenario: A disabled protocol is re-enabled

- **WHEN** magnetite's configuration re-enables the MySQL listener
- **THEN** the evaluation-time envelope check (R7.1) fails, which is another of its mutants

#### Scenario: The gRPC listener leaves loopback

- **WHEN** magnetite's configuration sets the gRPC `bind_addr` outside `127.0.0.0/8`
- **THEN** the evaluation-time envelope check (R7.1) fails

### Requirement: Prometheus remote storage stays enabled for the PromQL query API

The machine SHALL keep the telemetry store's Prometheus remote read and write at `/v1/prometheus/{read,write}` enabled, because its v1.2.1 registers the PromQL query API only together with them (`src/frontend/src/server.rs:130-158`).
They are served on the loopback HTTP listener, require credentials, and accept writes only from `collector` (`wo`) and `admin` (`rw`).

#### Scenario: Prometheus remote storage is disabled

- **WHEN** magnetite's configuration sets `prom_store.enable = false`
- **THEN** the evaluation-time envelope check fails, because the PromQL query API would then be absent

### Requirement: Scrape targets are reached on loopback

The collector on magnetite SHALL reach every metrics source it scrapes on a loopback address, and the machine SHALL expose nixbot's `/metrics` to it through a loopback nginx server on `127.0.0.1:9180` that proxies to nixbot's socket, because nixbot listens on no TCP port.

#### Scenario: The scrape targets are evaluated

- **WHEN** the evaluation-time collector check (R3.1) reads magnetite's collector configuration
- **THEN** it finds node_exporter on `127.0.0.1:9100`, gitea on `127.0.0.1:3002`, niks3 on `127.0.0.1:5752`, nixbot on `127.0.0.1:9180`, nginx's `stub_status`, zerotierone's metrics with `enableMetrics = true` in zerotierone's `local.conf`, and the telemetry store's own `/metrics` on `127.0.0.1:4000`, each on loopback

#### Scenario: A scrape target is configured off loopback

- **WHEN** a mutant of magnetite's collector configuration names a scrape target outside `127.0.0.0/8`
- **THEN** the evaluation-time collector check (R3.1) fails

### Requirement: Store accounts carry fixed permission modes

The machine SHALL configure the telemetry store with a static user provider read from a file holding exactly four accounts, `admin` with mode `rw`, `collector` with mode `wo`, `perses` with mode `ro` and `regulator` with mode `ro`, each line in the `name:mode=password` form with a hexadecimal password.
The machine SHALL require one of these accounts on every `/v1/` path, loopback included.

#### Scenario: The account file is evaluated

- **WHEN** magnetite's configuration is evaluated
- **THEN** the evaluation-time account-file check finds exactly four lines that the telemetry store's file format accepts, each with exactly one `=`, because the telemetry store skips a malformed line without an error

#### Scenario: The authorization matrix runs

- **WHEN** the container test presents each account to the write and read paths
- **THEN** a request with no credential and one with a wrong password are answered HTTP 401, `collector` writes with 200 and is refused a read with HTTP 403, `perses` reads with 200 and is refused a write with HTTP 403, `regulator` reads with 200, and `admin` reads and writes with 200

#### Scenario: The user provider is removed

- **WHEN** magnetite's configuration drops the `user_provider` setting
- **THEN** the evaluation-time envelope check (R7.1) fails, which is one of its mutants

### Requirement: Ingest is OTLP over HTTP with a database header

The collector SHALL write metrics to the telemetry store only through OTLP over HTTP at `http://127.0.0.1:4000/v1/otlp`, authenticating as `collector`, through one `otlp_http` exporter per database fed by a `routing` connector, each sending `x-greptime-db-name` and `x-greptime-otlp-metric-promote-resource-attrs`.
The collector SHALL carry no logs or traces pipeline into the telemetry store.

#### Scenario: A metric is ingested in the container test

- **WHEN** the container test emits a metric to the collector's local receiver
- **THEN** the metric passes from the agent pipeline to the ingress pipeline through an in-process `forward` connector, arrives in the database the routing connector selects, and carries `host_name` as a promoted label

#### Scenario: The promoted attributes are evaluated

- **WHEN** the evaluation-time collector check (R3.1) reads each exporter's headers
- **THEN** `x-greptime-otlp-metric-promote-resource-attrs` equals the resource allow-list in `schema.nix`, which includes `host.name`, and `x-greptime-db-name` names the exporter's database

#### Scenario: The histogram conversion is removed while the store is below 1.3.0

- **WHEN** magnetite's collector configuration drops the conversion of exponential histograms to explicit-bucket histograms while the telemetry store's version is below 1.3.0
- **THEN** the evaluation-time conversion check (R1.2) fails, which its mutant shows

#### Scenario: The collector configuration is validated at build time

- **WHEN** the collector's configuration is validated during the build, before `/run/credentials` exists
- **THEN** validation passes without a placeholder credential, because `basicauth` reads the `collector` password through `client_auth.password_file`, which validation does not open; the one validation override removes the `authorization` of the zerotierone scrape job, whose credential file the prometheus receiver's validation stats, and the evaluation-time collector check (R3.1) fails when an override touches anything else

### Requirement: Reads are PromQL and SQL over HTTP with a database header

The machine SHALL serve reads on the telemetry store's HTTP listener through the PromQL API at `/v1/prometheus/api/v1`, selecting the database with the `x-greptime-db-name` header, and through SQL at `/v1/sql`.

#### Scenario: A series is read back with PromQL in the container test

- **WHEN** the container test queries the PromQL API with `x-greptime-db-name: fleet` for a metric it emitted
- **THEN** the query returns that series with its `host_name` label

#### Scenario: magnetite's series are read at first activation

- **WHEN** the operator queries magnetite's series at first activation through SQL and through PromQL
- **THEN** both return series labelled with `host_name` equal to `magnetite`, and the operator records the queries and their results

### Requirement: Databases and their retention are set at the telemetry store

The machine SHALL run a oneshot `greptimedb-schema.service` as `admin` that polls `GET /health` until the telemetry store answers, then for each of `fleet` (`30d`), `devloop` (`365d`) and `agent` (`90d`) issues `CREATE DATABASE IF NOT EXISTS` followed by `ALTER DATABASE ... SET 'ttl'`, because the create statement leaves an existing database's retention unchanged.
The machine SHALL create no logs table.

#### Scenario: The schema oneshot runs against an empty store and against an existing database

- **WHEN** the container test runs the schema oneshot once against an empty telemetry store, and once after creating `fleet` with another `ttl`
- **THEN** each database carries its declared `ttl` after each run

### Requirement: Tables allowed a retention of their own are declared

The machine SHALL read the tables allowed a `ttl` of their own from `services.greptimedb.tableTtls`, a map from `<database>.<table>` to that table's TTL, which is empty in S1.

#### Scenario: A table carries an undeclared ttl

- **WHEN** any table in the three databases carries a `ttl` of its own and `services.greptimedb.tableTtls` does not declare it
- **THEN** the hourly envelope regulator `greptimedb-envelope` fails, which the envelope check's recorded-answer rehearsal confirms

#### Scenario: A table carries a declared ttl

- **WHEN** a table carries a `ttl` of its own that equals, as a duration, the TTL `services.greptimedb.tableTtls` declares for it
- **THEN** `greptimedb-envelope` passes on that table, and a declared table that does not exist yet is not judged

#### Scenario: A declared table departs from its declared ttl

- **WHEN** `services.greptimedb.tableTtls` declares a table whose own `ttl` differs from the declared TTL, or which carries no `ttl` of its own
- **THEN** `greptimedb-envelope` fails

### Requirement: The store and the collector name the same databases

The machine SHALL take magnetite's databases and their TTLs from `flake.lib.otelCollectorSchema.databases`, the map the ingress routes on.

#### Scenario: The store and the collector name different databases

- **WHEN** magnetite's `services.greptimedb.databases` names a database that `flake.lib.otelCollectorSchema.databases` does not, or omits one it names
- **THEN** magnetite's evaluation fails on the ingress module's assertion, naming both lists

### Requirement: Object data lives under one prefix of one bucket

The machine SHALL configure the telemetry store's storage as type `S3` with bucket `sciexp` and root `projects/vanixiets/observability/store/`, at the R2 account endpoint the `omnigraph-r2` generator already uses, with `storage.data_home` on the dataset `zroot/root/greptimedb`, and every table SHALL use the flat SST format.
The R2 access key and secret SHALL reach the telemetry store only through an environment file rendered by the `greptimedb-r2` generator.

#### Scenario: The storage stanza is evaluated

- **WHEN** the evaluation-time storage check (R6.4's storage clause) reads magnetite's configuration
- **THEN** it finds region `auto`, `enable_virtual_host_style = false`, `disable_ec2_metadata = true`, bucket `sciexp` and the stated root, and the environment file carries only `GREPTIMEDB_STANDALONE__STORAGE__ACCESS_KEY_ID` and `GREPTIMEDB_STANDALONE__STORAGE__SECRET_ACCESS_KEY`

#### Scenario: The storage stanza is weakened

- **WHEN** magnetite's configuration drops `disable_ec2_metadata` or sets the storage root to the empty string
- **THEN** the evaluation-time storage check fails, which its two mutants show

#### Scenario: The telemetry store starts against R2

- **WHEN** the hourly envelope regulator runs after the telemetry store starts
- **THEN** it fails unless the telemetry store answers ready (R6.4's readiness case), and the operator confirms at first activation that objects appear under the store prefix in `sciexp`

#### Scenario: A table uses the legacy format

- **WHEN** any table's create options name a legacy `sst_format`
- **THEN** the hourly envelope regulator fails (R6.3)

### Requirement: Credentials exist only as activation-resolved files owned by non-worker users

Every store credential SHALL reach its consumer as a file resolved when magnetite's configuration is activated, readable only by its owner, owned by no omnigent worker account, and absent from the configuration that produced it.
Replacing the account file SHALL restart the telemetry store, and replacing the `collector` password SHALL restart the collector.

#### Scenario: The credential files are evaluated

- **WHEN** the evaluation-time ownership check (R8.2) reads magnetite's configuration
- **THEN** the account file is owned by `greptimedb` with mode `0400` and reaches the telemetry store through `LoadCredential`, each password file has mode `0400`, the `collector` password reaches the collector through `LoadCredential`, and the R2 generator's prompted values carry `deploy = false`

#### Scenario: A worker account owns a credential

- **WHEN** magnetite's configuration makes a worker account the owner of the `collector` password file
- **THEN** the evaluation-time ownership check (R8.2) fails, which its mutant shows

#### Scenario: A credential is loaded by a unit outside its holders

- **WHEN** the evaluation-time ownership check (R8.2) reads which of magnetite's evaluated units load each password file
- **THEN** its credential-holder clause finds `admin-password` loaded only by `greptimedb-schema`, `collector-password` only by `opentelemetry-collector` and `regulator-password` only by the regulator units, and a mutant in which a second unit loads `admin-password` makes it fail

#### Scenario: The restart on rotation is removed

- **WHEN** magnetite's configuration drops `greptimedb.service` from the account file's restart list
- **THEN** the evaluation-time envelope check (R7.1) fails, which is one of its mutants

### Requirement: The account file the telemetry store loaded is recorded

The machine SHALL publish the sha256 of the account file as the non-secret generator file `users-sha256`, and `greptimedb.service` SHALL record, before it starts, the sha256 of the account file it loaded in `/run/greptimedb/loaded-users.sha256`.

#### Scenario: The telemetry store runs on a superseded account file

- **WHEN** the sha256 in `/run/greptimedb/loaded-users.sha256` differs from the generator's `users-sha256`, or either file is missing
- **THEN** the hourly envelope regulator fails (R7.4)

#### Scenario: An activation rewrites the account file unchanged

- **WHEN** an activation rewrites the account file with a new modification time and the same content, and the telemetry store is not restarted
- **THEN** the hourly envelope regulator does not fail on credential freshness (R7.4), because it compares hashes rather than times

### Requirement: The telemetry store and the collector run inside a declared envelope

The machine SHALL run `greptimedb.service` under the static user `greptimedb` with `MemoryHigh=3G`, `MemoryMax=4G`, `MemorySwapMax=0`, `OOMScoreAdjust=500` and a `CPUWeight` below the default, and the collector with `MemoryMax=512M` and `OOMScoreAdjust=300`, against the build service's evaluator at `OOMScoreAdjust=900`.
The dataset `zroot/root/greptimedb` SHALL carry `quota=16G`, `reservation=12G` and `com.sun:auto-snapshot=false`, applied or asserted at boot.

#### Scenario: The evaluation-time envelope check runs with its mutants

- **WHEN** the evaluation-time envelope check (R7.1) runs against magnetite's configuration and against each of its seven mutants, which drop `MemoryMax`, drop `page_cache_size`, bind HTTP to `0.0.0.0`, re-enable MySQL, remove `user_provider`, omit `enable_telemetry` and remove the restart on rotation
- **THEN** it passes on magnetite's configuration, where it also finds `[runtime] global_rt_size = 4`, `compact_rt_size = 2`, the memory knobs ADR-007 names, `logging.dir = ""` and a collector `memory_limiter` of 384 MiB, and it fails on every mutant

#### Scenario: The hourly envelope regulator finds the store over its envelope

- **WHEN** `greptimedb-envelope` runs as `regulator` and the store's cgroup `memory.stat` `anon` has reached `GREPTIMEDB_ENVELOPE_ANON_MAX_BYTES`, which is set from `MemoryHigh`, its `memory.events` `high`, `oom_kill` or `max` counters have increased within one store invocation, or, across invocations, the journal for `greptimedb.service` records a kernel OOM kill (`MESSAGE_ID=fe6faa94e7774663a0da52717891d8ef`) or `NRestarts` has increased (R7.2), the dataset's used space has reached 80% of its quota or the quota or reservation differs from its declared value (R7.3), or the summed SST size in `information_schema.region_statistics` has reached 50 GiB (R6.2)
- **THEN** the unit fails

#### Scenario: The memory regulator is shown able to fail

- **WHEN** at first activation the anonymous-memory threshold is set below the observed value and `greptimedb-envelope` runs
- **THEN** the unit fails, and the operator records the failed run

#### Scenario: Page cache alone does not fail the memory regulator

- **WHEN** the envelope's build-time rehearsal runs the R7.2 regulator over `memory.events` and `memory.stat` recorded on magnetite, with a threshold above `anon` but below `memory.peak`, and then with `memory.events` `high` raised within the same invocation
- **THEN** the first run passes and the second fails naming `high`, its baseline and its new value

#### Scenario: The OOM kill order is exercised

- **WHEN** the on-demand QEMU VM test on pyrite exhausts memory with processes at `OOMScoreAdjust` 900, 500 and 300
- **THEN** the kernel kills them in that order in host-wide OOM kills whose victim lines carry `,global_oom,`, each of the three units logs systemd's OOM-kill message, and `greptimedb.service` ends with result `oom-kill`

#### Scenario: The dataset properties are applied at boot and confirmed on magnetite

- **WHEN** magnetite boots, and when the operator reads the dataset's properties at first activation
- **THEN** `zfs-set-root-greptimedb-quota`, `zfs-set-root-greptimedb-reservation` and `zfs-assert-root-greptimedb-noautosnap`, built from magnetite's `greptimedbDataset` binding, whose values the envelope check finds in `disko.nix` as well, succeed or fail visibly, and the operator records `quota`, `reservation` and `com.sun:auto-snapshot` on `zroot/root/greptimedb`

### Requirement: Runtime regulators treat absent evidence as failure

Every query `greptimedb-envelope` issues SHALL treat an empty result, or a missing table, as a failure of the property it regulates, never as a pass.

#### Scenario: The queried table is renamed

- **WHEN** a mutant of `greptimedb-envelope` queries a table name that does not exist
- **THEN** the regulator fails

### Requirement: The telemetry store's release and usage reporting are fixed at evaluation

The machine SHALL set `enable_telemetry = false` in the telemetry store's configuration (R1.4).
The machine SHALL run a telemetry store package whose version matches `^[0-9]+\.[0-9]+\.[0-9]+$` and that sets `passthru.embedsDashboard = true`, as `greptimedb-bin` does, and SHALL serve the embedded dashboard at `GET /dashboard/` on `127.0.0.1:4000` (R1.1, amended).

#### Scenario: The usage-report setting is omitted

- **WHEN** magnetite's configuration omits `enable_telemetry`
- **THEN** the evaluation-time telemetry check (R1.4) fails, which its mutant shows

#### Scenario: A prerelease version is configured

- **WHEN** the telemetry store's package is overridden to version `1.3.0-beta.2`
- **THEN** the evaluation-time release check (R1.1) fails

#### Scenario: A package without the embedded dashboard is configured

- **WHEN** magnetite's telemetry store package is set to the pinned `pkgs.greptimedb`, which lacks `passthru.embedsDashboard`
- **THEN** the evaluation-time release check (R1.1) fails, which its mutant shows

#### Scenario: The delivered binary serves the dashboard

- **WHEN** the container runtime test sends `GET http://127.0.0.1:4000/dashboard/` to the running telemetry store
- **THEN** the telemetry store answers 200

### Requirement: The collector's configuration bounds what it gathers

The machine SHALL configure magnetite's collector so that per-process memory carries no per-process identifier and covers only executables holding at least 64 MiB, per-unit signals cover exactly the `schema.nix` allow-list of at most 40 units, paging reports usage only, and node_exporter's series pass a keep-list.
`schema.nix` declares the 30-name per-host bound as `process.maxNames`, which no collector stage enforces; it is observed at first activation and regulated from slice S4.

#### Scenario: The collector check runs with its mutants

- **WHEN** the evaluation-time collector check (R3.1) runs against magnetite's collector configuration and its mutants
- **THEN** it passes `otelcol-contrib validate`, finds `process.pid`, `process.parent_pid`, `process.command`, `process.command_line`, `process.executable.path` and `process.owner` disabled at source, finds the 64 MiB filter and `process.maxNames = 30`, finds the paging scraper limited to `system.paging.usage` and `system.linux.memory.available` enabled, finds the `systemd` receiver's `units` equal to the `schema.nix` allow-list, finds node_exporter limited to its `zfs` collector and its `vmstat` collector filtered to `oom_kill`, and fails on every mutant

#### Scenario: The systemd receiver reaches D-Bus

- **WHEN** the container test runs the collector under `DynamicUser`
- **THEN** the `systemd` receiver reports the state of an allow-listed unit

#### Scenario: Paging series appear on magnetite

- **WHEN** magnetite has run the collector for one collection interval after first activation
- **THEN** the operator finds `system_paging_usage_bytes` for `/dev/zram0` in `fleet` and records it

### Requirement: Omnigent unit names are stored under aliases

The machine SHALL rewrite each `omnigent-host-<owner>.service` unit name to `omnigent-host-<alias>.service` from `ownerAliases` in `schema.nix`, `{ cameron = "owner-1"; janettesmith = "owner-2"; }` in S1, before any exporter.

#### Scenario: An Omnigent owner has no alias

- **WHEN** a mutant removes an owner whose `omnigent-host-<owner>` unit magnetite evaluates from `ownerAliases`
- **THEN** the evaluation-time collector check (R3.1) fails on its alias clause

#### Scenario: Stored unit names are read back in the container test

- **WHEN** the container test reads the stored `systemd_unit_name` values after the collector has reported an `omnigent-host-<owner>` unit
- **THEN** the unit appears under its alias, and no stored value contains the owner's name

### Requirement: The collector's queue persists across a telemetry store restart

The machine SHALL back each exporter's sending queue in magnetite's collector with a `file_storage` extension using the `bytes` sizer, 400 MiB for `fleet` and 48 MiB each for `devloop` and `agent` in one directory, so that the queues sum to less than 512 MiB and the `fleet` queue holds at least 24 hours at an assumed 256,000 bytes per minute, a rate measured at first activation.

#### Scenario: The persistent queue is removed

- **WHEN** a mutant of magnetite's collector configuration drops the `file_storage` queue, sizes the `fleet` queue below 24 hours at the assumed rate, or brings the queues' sum to 512 MiB or more
- **THEN** the evaluation-time collector check (R3.1) fails on its queue clause

#### Scenario: The `fleet` queue rate is measured at first activation

- **WHEN** the operator stops `greptimedb.service` for ten minutes on magnetite and measures the bytes the `fleet` queue accumulates
- **THEN** the operator records the measured rate beside the assumed 256,000 bytes per minute, and a measured rate under which the 400 MiB queue holds less than 24 hours is a finding that resizes the queues

#### Scenario: The store restarts during collection

- **WHEN** the container test stops `greptimedb.service`, emits metrics, starts `greptimedb.service` again and queries the interval
- **THEN** the metrics emitted while the store was stopped are returned

### Requirement: Failure notices are posted to one topic

The machine SHALL provide the template `observability-notify@.service` in the collector's `agent` role, posting through the single `ntfy-send` package to the topic `fleet-alerts` at `https://ntfy.zt` without a credential, and SHALL set `OnFailure=observability-notify@%n.service` on `greptimedb.service`, `greptimedb-schema.service`, `greptimedb-envelope.service`, `opentelemetry-collector.service` and all nine of magnetite's ZFS property oneshots.

#### Scenario: The failure wiring is evaluated

- **WHEN** the evaluation-time collector check (R3.1) reads magnetite's configuration
- **THEN** its failure-wiring clause finds `OnFailure=observability-notify@%n.service` on `greptimedb.service`, `greptimedb-schema.service`, `greptimedb-envelope.service`, `opentelemetry-collector.service`, `zfs-set-root-greptimedb-quota`, `zfs-set-root-greptimedb-reservation`, `zfs-assert-root-greptimedb-noautosnap`, `zfs-assert-root-nix-noautosnap`, `zfs-assert-root-docker-noautosnap`, `zfs-assert-root-podman-noautosnap`, `zfs-set-root-nix-quota`, `zfs-set-root-nixos-reservation` and `zfs-set-root-home-reservation`

#### Scenario: A unit's failure handler is removed

- **WHEN** a mutant of magnetite's configuration drops `OnFailure` from one of the named units
- **THEN** the evaluation-time collector check (R3.1) fails on its failure-wiring clause

#### Scenario: The sender is one package

- **WHEN** the notifier and the home-manager `ntfy-send` command are evaluated
- **THEN** both resolve `ntfy-send` to `pkgs/by-name/ntfy-send`

#### Scenario: A failure is delivered at first activation

- **WHEN** `greptimedb-envelope` is made to fail at first activation
- **THEN** a message naming `greptimedb-envelope.service` and magnetite appears on `fleet-alerts`, and the operator records it

### Requirement: A failure episode ends at the unit's next successful start or exit

Each unit that sets `OnFailure=observability-notify@%n.service` SHALL carry an `ExecStartPost=` and an `ExecStopPost=` hook running one script that posts one `RESOLVED` and ends the failure episode at the unit's next successful start or exit.

#### Scenario: Failure notices continue across automatic restarts

- **WHEN** a notified unit fails, systemd restarts it automatically, it starts successfully, and it later fails again
- **THEN** the successful start posts one `RESOLVED` and ends the episode, so the later failure posts a new notice, and a oneshot posts no second `RESOLVED` on its stop because its start hook already removed the stamp

#### Scenario: A unit's start-time recovery hook is removed

- **WHEN** a mutant of magnetite's configuration drops the `RESOLVED` `ExecStartPost=` hook from one notified unit, or gives a oneshot's start hook a script other than its stop hook's
- **THEN** the evaluation-time collector check (R3.1) fails on its failure-wiring clause

#### Scenario: A crash loop is rate-limited

- **WHEN** the collector check's rehearsal runs the notifier's scripts against a temporary stamp directory and a recording `ntfy-send`, with a crash, a start, a crash and a start within 15 minutes, then a crash after 15 minutes
- **THEN** the first two crashes post exactly one `FAILED` and one `RESOLVED`, and the later crash posts a new `FAILED` and `RESOLVED`, so a persistent crash loop yields one pair, then at most one new pair per 15 minutes per unit

### Requirement: This capability states its own trust boundary

This capability SHALL state what its properties guarantee and what they do not, and SHALL NOT be described, by itself or in any downstream report, as an end-to-end guarantee that a series reaches the telemetry store or that a failure reaches a person.

#### Scenario: The properties above are read as a set

- **WHEN** the properties of this capability are read as a set
- **THEN** what they establish is that the telemetry store and its scrape targets listen only on loopback, that four accounts with fixed modes gate every `/v1/` path, that ingest and reads use the stated paths and headers, that the databases carry their declared retention, that object data is configured under one prefix of one bucket, that credentials exist only as activation-resolved files owned by non-worker users, that the store and collector run inside the declared envelope, that the queue is persistent and bounded, and that the named units hand their failures to the notifier, each as far as its own check, test or recorded first-activation observation reaches

#### Scenario: A guarantee about R2 is sought from this capability

- **WHEN** someone asks whether these properties guarantee that object data is durable or that the R2 token is scoped to the store prefix
- **THEN** the answer is no: the token's scope and the bucket's durability are set and provided by Cloudflare, and this machine does not assert them

#### Scenario: A guarantee about who can reach the loopback listener is sought

- **WHEN** someone asks whether loopback binding limits access to the named consumers
- **THEN** the answer is no: any root process on magnetite can reach the loopback listener, and only the account credentials distinguish it from the named consumers

#### Scenario: A guarantee about notice delivery or publishing is sought

- **WHEN** someone asks whether these properties guarantee that a failure notice reaches a person, or that only the notifier publishes to `fleet-alerts`
- **THEN** the answer is no: access to the notification service is ZeroTier membership, and cinnabar is a single delivery path that nothing here watches

#### Scenario: An end-to-end guarantee is sought

- **WHEN** someone asks whether these properties guarantee that a given series reaches the telemetry store
- **THEN** the answer is no: each stage's configuration is checked and the tested pipeline behaves as stated, and nothing here observes the whole path on magnetite end to end
