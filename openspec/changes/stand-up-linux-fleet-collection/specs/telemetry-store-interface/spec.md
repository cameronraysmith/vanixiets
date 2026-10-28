## MODIFIED Requirements

### Requirement: Listeners are bound to loopback only

The machine SHALL bind the telemetry store's HTTP listener to `127.0.0.1:4000` and its gRPC listener to `127.0.0.1:4001`, SHALL disable its MySQL, PostgreSQL, InfluxDB, OpenTSDB and Jaeger listeners, and SHALL open no firewall port for the telemetry store.
gRPC is bound to loopback rather than disabled, because the telemetry store's v1.2.1 configuration offers no setting that disables it.
The only telemetry listener off loopback SHALL be the collector's `otlp/mesh` receiver.

**Discharged by**: the store module's assertions (R7.1) with their overrides; R3.1's endpoint clause and `fleet-ingress-interface` requirement `The ingress receiver accepts only certificate holders on magnetite's ZeroTier address`.

#### Scenario: The HTTP listener is configured on a non-loopback address

- **WHEN** magnetite's configuration binds the telemetry store's HTTP listener to `0.0.0.0`
- **THEN** magnetite's evaluation fails on the store module's listener assertion (R7.1, which R8.2's bind clause also names), as an evaluation with that override shows

#### Scenario: A disabled protocol is re-enabled

- **WHEN** magnetite's configuration re-enables the MySQL listener
- **THEN** magnetite's evaluation fails on the store module's protocol assertion (R7.1), as an evaluation with that override shows

#### Scenario: The gRPC listener leaves loopback

- **WHEN** magnetite's configuration sets the gRPC `bind_addr` outside `127.0.0.0/8`
- **THEN** magnetite's evaluation fails on the store module's gRPC assertion (R7.1)

#### Scenario: The listeners are read on magnetite after the ingress is deployed

- **WHEN** the operator runs `ss -tlnH` on magnetite after the deploy that adds the ingress receiver
- **THEN** every listener of the telemetry store and of the collector is on loopback except `[fddb:4344:343b:14b9:399:930f:39db:40d2]:4318`, and the operator records the output

### Requirement: Scrape targets are reached on loopback

The collector on every agent host SHALL reach every metrics source it scrapes on a loopback address, scraping a service's endpoint only where that service runs, and the machine SHALL expose nixbot's `/metrics` to it through a loopback nginx server on `127.0.0.1:9180` that proxies to nixbot's socket, because nixbot listens on no TCP port.

**Discharged by**: the evaluation-time collector check (R3.1) with its mutants; the agent module's firewall assertion; `otel-envelope`'s target clause on every agent host.

#### Scenario: The scrape targets are evaluated

- **WHEN** the evaluation-time collector check (R3.1) reads magnetite's collector configuration
- **THEN** it finds every scrape target, including node_exporter's, gitea's, niks3's, nixbot's, nginx's `stub_status`, zerotierone's, the collector's own telemetry and the telemetry store's own `/metrics`, and node_exporter's listener on loopback, and the agent module's assertion holds node_exporter's and the SMART exporter's firewall closed

#### Scenario: A scrape target is configured off loopback

- **WHEN** a mutant of magnetite's collector configuration names a scrape target outside `127.0.0.0/8`
- **THEN** the evaluation-time collector check (R3.1) fails

#### Scenario: A host runs none of magnetite's services

- **WHEN** cinnabar's configuration is evaluated
- **THEN** its collector carries no gitea, niks3, nixbot or greptimedb scrape job, because each is configured only where `services.<name>.enable` holds, and magnetite's rendered jobs are unchanged

#### Scenario: The collector's own telemetry is scraped

- **WHEN** any agent host's collector configuration is evaluated
- **THEN** a job `otelcol` scrapes `127.0.0.1:8888`, keeps only the queue, send-failure, enqueue-failure and refusal counters that `schema.nix` lists, and drops the label `service_instance_id`

#### Scenario: pyrite's SMART exporter is scraped

- **WHEN** pyrite's configuration is evaluated
- **THEN** `prometheus-smartctl-exporter` listens on `127.0.0.1:9633` over `/dev/nvme0` with `openFirewall = false`, and a job `smartctl` scrapes it with the smartctl keep-list of `schema.nix`

### Requirement: Ingest is OTLP over HTTP with a database header

The ingress SHALL write metrics to the telemetry store only through OTLP over HTTP at `http://127.0.0.1:4000/v1/otlp` as `collector`, one `otlp_http` exporter per database behind a `routing` connector, taking them from magnetite's agent through `forward` and from other agent hosts through `otlp/mesh`.
Logs SHALL enter the store only in `devloop`, as a scenario below states, with no message body or field outside `flake.lib.otelCollectorSchema.devloop.tables`, and traces SHALL NOT enter it.

**Discharged by**: the evaluation-time collector check (R3.1) with its mutants, nixpkgs' build-time `otelcol-contrib validate`, and the container tests `greptimedb-pipeline`, `devloop-ingest` and `fleet-ingress`.

#### Scenario: Each database exporter carries its headers

- **WHEN** magnetite's collector configuration is evaluated
- **THEN** each `otlp_http/<db>` exporter sends `x-greptime-db-name: <db>` and `x-greptime-otlp-metric-promote-resource-attrs` built from the resource allow-list in `schema.nix`

#### Scenario: Logs are routed to their devloop table

- **WHEN** magnetite's collector configuration is evaluated
- **THEN** logs reach the telemetry store only through a `routing/logs` connector in the ingress role that routes on the resource attributes `vanixiets.database` and `vanixiets.table` to one `otlp_http/devloop_<table>` exporter per table of `flake.lib.otelCollectorSchema.devloop.tables`, each authenticating as `collector` and sending `x-greptime-db-name: devloop`, `x-greptime-log-table-name: <table>`, `x-greptime-pipeline-name: devloop_<table>` and `x-greptime-hints: auto_create_table=false`, and `resource/strip-database` deletes both attributes before every exporter

#### Scenario: Dev-loop rows are ingested in the container test

- **WHEN** `vmTests.x86_64-linux.devloop-ingest` runs the collector with its S2 receivers against the store
- **THEN** each source's rows pass from its `logs/devloop-<table>` pipeline through `forward` and `routing/logs` into the `devloop` table its exporter names, with zero failed log records and no `body` column

#### Scenario: Another host's series and deploy records cross the ingress

- **WHEN** `vmTests.x86_64-linux.fleet-ingress` runs an agent without the ingress role against the ingress and the store
- **THEN** its metrics pass through `otlp/mesh` and `metrics/ingress` into `fleet` with the agent's `host_name`, its deploy records pass through `otlp/mesh` and `logs/ingress` into `devloop.deploy_record`, and every exporter's failed-send count is zero after first start

#### Scenario: A metric is ingested in the container test

- **WHEN** the container test emits a metric to the collector's local receiver
- **THEN** the metric passes from the agent pipeline to the ingress pipeline through an in-process `forward` connector, arrives in the database the routing connector selects, and carries `host_name` as a promoted label

#### Scenario: The promoted attributes are read back

- **WHEN** the container test reads back the metric it emitted
- **THEN** the metric carries `host_name`, promoted through the `x-greptime-otlp-metric-promote-resource-attrs` header the ingress builds from the resource allow-list in `schema.nix`, and appears only in the database whose name the exporter's `x-greptime-db-name` header carries

#### Scenario: The histogram conversion is removed while the store is below 1.3.0

- **WHEN** magnetite's collector configuration drops the conversion of exponential histograms to explicit-bucket histograms while the telemetry store's version is below 1.3.0
- **THEN** the evaluation-time conversion check (R1.2) fails, which its mutant shows

#### Scenario: The collector configuration is validated at build time

- **WHEN** the collector's configuration is validated during the build, before `/run/credentials` exists
- **THEN** validation passes without a placeholder credential, because `basicauth` reads the `collector` password through `client_auth.password_file` and validation opens no TLS file; the one validation override removes the `authorization` of the zerotierone scrape job, whose credential file the prometheus receiver's validation stats, and the evaluation-time collector check (R3.1) fails when an override touches anything else

#### Scenario: A logs pipeline takes an OTLP receiver other than the ingress receiver

- **WHEN** a mutant of magnetite's collector configuration adds a local OTLP receiver to a `logs/*` pipeline
- **THEN** the evaluation-time collector check (R3.1) fails, because only `otlp/mesh` may feed a logs pipeline

### Requirement: Credentials exist only as activation-resolved files owned by non-worker users

Every store credential and every `otel-cert` key SHALL reach its consumer as a file resolved when its host's configuration is activated, readable only by its owner, owned by no omnigent worker account, and absent from the configuration that produced it.
Replacing the account file SHALL restart the telemetry store, and replacing the `collector` password or a host's `otel-cert` SHALL restart that host's collector.

**Discharged by**: the evaluation-time ownership check (R8.2) with its mutant, magnetite's credential-holder assertion (R8.2), which admits `fleet-alert`, `devloop-reconcile` and `otel-envelope` as `regulator-password` holders, the evaluation-time envelope check (R7.1) with its restart-on-rotation mutant, and the `otel-cert` generator's `restartUnits`.

#### Scenario: The credential files are evaluated

- **WHEN** the evaluation-time ownership check (R8.2) reads magnetite's configuration
- **THEN** the account file is owned by `greptimedb` with mode `0400` and reaches the telemetry store through `LoadCredential`, each password file and the `otel-cert` key have mode `0400` and are owned by no worker account, the `collector` password and the `otel-cert` key reach the collector through `LoadCredential`, and the R2 generator's prompted values carry `deploy = false`

#### Scenario: A worker account owns a credential

- **WHEN** magnetite's configuration makes a worker account the owner of the `collector` password file
- **THEN** the evaluation-time ownership check (R8.2) fails, which its mutant shows

#### Scenario: A credential is loaded by a unit outside its holders

- **WHEN** magnetite's configuration is evaluated, which loads each password file into the units that name it
- **THEN** magnetite's credential-holder assertion (R8.2) finds `users` loaded only by `greptimedb`, `admin-password` only by `greptimedb-schema`, `collector-password` only by `opentelemetry-collector`, `regulator-password` only by `greptimedb-envelope`, `fleet-alert`, `devloop-reconcile` and `otel-envelope`, and `perses-password` by none, and an evaluation with a second unit loading `admin-password` fails on it

#### Scenario: The restart on rotation is removed

- **WHEN** magnetite's configuration drops `greptimedb.service` from the account file's restart list
- **THEN** the evaluation-time envelope check (R7.1) fails, which is one of its mutants

### Requirement: The telemetry store and the collector run inside a declared envelope

The machine SHALL run `greptimedb.service` under the static user `greptimedb` with `MemoryHigh=3G`, `MemoryMax=4G`, `MemorySwapMax=0`, `OOMScoreAdjust=500` and a lower `CPUWeight`, magnetite's collector with `MemoryMax=512M` and `OOMScoreAdjust=300`, below the build service's evaluator at 900, and other agents' collectors with `MemoryMax=256M`.
The dataset `zroot/root/greptimedb` SHALL carry `quota=16G`, `reservation=12G` and `com.sun:auto-snapshot=false`, applied or asserted at boot.

**Discharged by**: the evaluation-time envelope check (R7.1) with its mutants, the agent role's limiter assertion on every host without the ingress role, the hourly envelope regulator, and the on-demand OOM-order test.

#### Scenario: The evaluation-time envelope check runs with its mutants

- **WHEN** the evaluation-time envelope check (R7.1) runs against magnetite's configuration and against each of its mutants, which drop `MemoryMax`, swap the store's and the collector's `OOMScoreAdjust`, and remove the restart on rotation
- **THEN** it passes on magnetite's configuration, where it finds `MemoryHigh` below `MemoryMax`, `MemorySwapMax=0`, the evaluator's `oom_score_adj` above the store's and the store's above the collector's, and the collector's `memory_limiter` below the collector's `MemoryMax`, and it fails on every mutant; the listener, protocol, user-provider and usage-report properties are the store module's assertions, and the memory knobs ADR-007 names are literals of the store module whose effect R7.2 and the OOM-order test regulate

#### Scenario: Another agent's envelope is evaluated

- **WHEN** a host without the ingress role is evaluated
- **THEN** its collector runs with `MemoryMax=256M` and a `memory_limiter` of 150 MiB with a 30 MiB spike allowance, and the agent role's assertion fails the evaluation when the limiter is not below `MemoryMax`, as an override of pyrite's limiter to 300 MiB shows

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

### Requirement: The collector's configuration bounds what it gathers

The machine SHALL configure each agent host's collector so that per-process memory carries no per-process identifier and covers only executables holding at least 64 MiB, per-unit signals cover the `schema.nix` allow-list with at most 40 matching units besides `observability-notify@` instances, paging reports usage only, file systems cover the host's ZFS mountpoints, and node_exporter's series pass a keep-list.
The ingress host's `otel-envelope` SHALL regulate ADR-004's 30 process names per host.

**Discharged by**: the evaluation-time collector check (R3.1) with its mutants; the agent module's assertions with their overrides; nixpkgs' build-time `otelcol-contrib validate`; `fleet-ingress-interface` requirement `otel-envelope on the ingress host regulates the fleet budget`.

#### Scenario: The collector check runs with its mutants

- **WHEN** the evaluation-time collector check (R3.1) runs against magnetite's collector configuration and its mutants, and magnetite's configuration is evaluated and built
- **THEN** the agent module's assertion finds `process.pid`, `process.parent_pid`, `process.command`, `process.command_line`, `process.executable.path` and `process.owner` disabled at source, the check finds the 64 MiB floor stage in the process pipeline, nixpkgs' build-time `otelcol-contrib validate` passes, and the check fails on every mutant; the paging metrics, the node_exporter collectors and its keep-list are literals of the agent module with no copy in the check

#### Scenario: The unit cap is evaluated on each agent host

- **WHEN** any agent host's configuration is evaluated
- **THEN** the agent module's assertion finds no more than 40 of the host's services, `observability-notify@` excluded, matching the `systemd` receiver's `units`, which the agent builds from the `schema.nix` allow-list, and an override of pyrite with 41 matching services fails the evaluation

#### Scenario: The file systems are evaluated on each agent host

- **WHEN** any agent host's configuration is evaluated
- **THEN** the `filesystem` scraper's strict mountpoint list, read from the host's `fileSystems` whose `fsType` is `zfs`, is recorded for each host, and only `system.filesystem.usage` is enabled

#### Scenario: The systemd receiver reaches D-Bus

- **WHEN** the container test runs the collector under `DynamicUser`
- **THEN** the `systemd` receiver reports the state of an allow-listed unit

#### Scenario: Paging series appear on magnetite

- **WHEN** magnetite has run the collector for one collection interval after first activation
- **THEN** the operator finds `system_paging_usage_bytes` for `/dev/zram0` in `fleet` and records it

#### Scenario: A host stores too many process names

- **WHEN** `fleet-ingress` writes 31 distinct `process_executable_name` values for one host
- **THEN** the ingress host's `otel-envelope` fails on its next hourly run

### Requirement: Omnigent unit names are stored under aliases

The machine SHALL rewrite each `omnigent-host-<owner>.service` unit name to `omnigent-host-<alias>.service` from `ownerAliases` in `schema.nix`, `{ cameron = "owner-1"; janettesmith = "owner-2"; }` in S1, before any exporter.

**Discharged by**: the agent module's alias assertion on every agent host with its override; the container test's alias read-back.

#### Scenario: An Omnigent owner has no alias

- **WHEN** an agent host's configuration runs an `omnigent-host-<owner>` unit whose owner `ownerAliases` lacks, or an alias contains an owner's name
- **THEN** that host's evaluation fails on the agent module's alias assertion, as an override of cinnabar's configuration with an `omnigent-host-nobody` service shows

#### Scenario: Stored unit names are read back in the container test

- **WHEN** the container test reads the stored `systemd_unit_name` values after the collector has reported an `omnigent-host-<owner>` unit
- **THEN** the unit appears under its alias, and no stored value contains the owner's name

### Requirement: Failure notices are posted to one topic

The machine SHALL define `observability-notify@.service` in `flake.modules.nixos.observability-notify` on every agent host, posting through the one `ntfy-send` package to `fleet-alerts` with the `alerter` token and logging each posted `FAILED` in `/var/lib/observability-notify/failed.log`, and SHALL set `OnFailure=observability-notify@%n.service` on the units the scenarios below name.

**Discharged by**: the failure-wiring clause and notifier rehearsal of the evaluation-time collector check (R3.1) with their mutants, the agent role's notified-unit assertion on every agent host, `checks.<system>.package-ntfy-send-test-token-transport` with its argv mutant, the resolve-hook assertion in `observability-notify.nix`, shown able to fail by an `extendModules` override, and the operator's recorded deliveries.

#### Scenario: Each named unit has the failure handler

- **WHEN** magnetite's configuration is evaluated
- **THEN** `OnFailure=observability-notify@%n.service` is set on `greptimedb.service`, `greptimedb-schema.service`, `greptimedb-envelope.service`, `opentelemetry-collector.service`, `otel-envelope.service`, `devloop-reconcile.service`, `devloop-pg-grants.service`, `fleet-alert.service` and magnetite's nine ZFS property oneshots

#### Scenario: Every agent host notifies its collector and regulator

- **WHEN** any agent host's configuration is evaluated
- **THEN** `services.observability-notify.units` equals that host's `notifiedUnits` in `flake.lib.observabilityHosts` and includes `opentelemetry-collector` and `otel-envelope`, and the notifier carries the `alerter` token from the `ntfy-alerter` generator

#### Scenario: The failure wiring is evaluated

- **WHEN** the evaluation-time collector check (R3.1) reads magnetite's configuration
- **THEN** its failure-wiring clause finds every magnetite service named `greptimedb*`, `devloop-*`, `zfs-set-*`, `zfs-assert-*`, `opentelemetry-collector` or `otel-envelope` listed in `services.observability-notify.units`, finds each listed name to be a unit with an `ExecStart`, and finds `OnFailure=observability-notify@%n.service` on each

#### Scenario: A new disk-share unit is not listed

- **WHEN** a mutant of magnetite's configuration adds a `zfs-set-root-foo-quota` service that `services.observability-notify.units` does not list
- **THEN** the evaluation-time collector check (R3.1) fails on its failure-wiring clause

#### Scenario: The reconcile is not listed

- **WHEN** a mutant of magnetite's configuration drops `devloop-reconcile` from `services.observability-notify.units`
- **THEN** the evaluation-time collector check (R3.1) fails on its failure-wiring clause

#### Scenario: A listed name is not a unit

- **WHEN** a mutant lists a name in `services.observability-notify.units` for which magnetite defines no service of its own, so the wiring creates a unit with no `ExecStart`
- **THEN** the evaluation-time collector check (R3.1) fails on its failure-wiring clause

#### Scenario: A unit's failure handler is removed

- **WHEN** a mutant of magnetite's configuration drops `OnFailure` from one of the named units
- **THEN** the evaluation-time collector check (R3.1) fails on its failure-wiring clause

#### Scenario: The template is one module imported where it is needed

- **WHEN** the agent hosts' configurations are evaluated
- **THEN** each defines `observability-notify@.service` from `flake.modules.nixos.observability-notify` through the collector's `agent` role, cinnabar's direct import merging with it, with the option `services.observability-notify.units` unchanged

#### Scenario: The sender is one package

- **WHEN** the notifier and the home-manager `ntfy-send` command are evaluated
- **THEN** both resolve `ntfy-send` to `pkgs/by-name/ntfy-send`

#### Scenario: The notifier carries the alerter token

- **WHEN** the agent hosts' configurations are evaluated
- **THEN** `observability-notify.nix`'s assertion holds that, with `tokenFile` set, each notified unit's `ExecStartPost=` and `ExecStopPost=` hooks run under `env NTFY_TOKEN_FILE=<tokenFile>`, and an `extendModules` override that replaces one unit's hooks makes evaluation fail

#### Scenario: Each posted failure is logged

- **WHEN** the collector check's rehearsal runs the notifier's scripts against a temporary state directory and a recording `ntfy-send`, with one failure that posts and one that the 15-minute interval suppresses
- **THEN** `failed.log` gains exactly one line of the form `<epoch> <unit> <host>`, for the posted `FAILED`, and a mutant that drops the append makes the rehearsal fail

#### Scenario: A failure is delivered at first activation

- **WHEN** `greptimedb-envelope` is made to fail at first activation
- **THEN** a message naming `greptimedb-envelope.service` and magnetite appears on `fleet-alerts`, and the operator records it

#### Scenario: A failure is delivered after the access entries are in force

- **WHEN** after cinnabar's ntfy refuses anonymous publishing to `fleet-*`, `greptimedb-envelope` is made to fail on magnetite
- **THEN** a message naming `greptimedb-envelope.service` and magnetite appears on `fleet-alerts`, a line for it appears in `failed.log`, and the operator records both

#### Scenario: Another agent host's regulator fails

- **WHEN** cinnabar's `otel-envelope` fails at acceptance
- **THEN** a message naming `otel-envelope.service` and cinnabar appears on `fleet-alerts`, and the operator records it
