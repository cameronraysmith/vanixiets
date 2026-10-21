## MODIFIED Requirements

### Requirement: Ingest is OTLP over HTTP with a database header

The collector SHALL write metrics to the telemetry store only through OTLP over HTTP at `http://127.0.0.1:4000/v1/otlp`, authenticating as `collector`, through one `otlp_http` exporter per database fed by a `routing` connector, each sending `x-greptime-db-name` and `x-greptime-otlp-metric-promote-resource-attrs`.
The collector SHALL write logs to the telemetry store only into `devloop`, through a `routing/logs` connector in the ingress role that routes on the resource attributes `vanixiets.database` and `vanixiets.table` to one `otlp_http/devloop_<table>` exporter per table of `flake.lib.otelCollectorSchema.devloop.tables`, each authenticating as `collector` and sending `x-greptime-db-name: devloop`, `x-greptime-log-table-name: <table>`, `x-greptime-pipeline-name: devloop_<table>` and `x-greptime-hints: auto_create_table=false`, and `resource/strip-database` SHALL delete both attributes before every exporter.
No logs pipeline SHALL carry a message body or a field outside that allow-list into the telemetry store, and the collector SHALL carry no traces pipeline into it.

**Discharged by**: the evaluation-time collector check (R3.1) with its mutants, nixpkgs' build-time `otelcol-contrib validate`, and the container tests `greptimedb-pipeline` and `devloop-ingest`.

#### Scenario: Dev-loop rows are ingested in the container test

- **WHEN** `vmTests.x86_64-linux.devloop-ingest` runs the collector with its S2 receivers against the store
- **THEN** each source's rows pass from its `logs/devloop-<table>` pipeline through `forward` and `routing/logs` into the `devloop` table its exporter names, with zero failed log records and no `body` column

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
- **THEN** validation passes without a placeholder credential, because `basicauth` reads the `collector` password through `client_auth.password_file`, which validation does not open; the one validation override removes the `authorization` of the zerotierone scrape job, whose credential file the prometheus receiver's validation stats, and the evaluation-time collector check (R3.1) fails when an override touches anything else

### Requirement: Databases and their retention are set at the telemetry store

The machine SHALL run a oneshot `greptimedb-schema.service` as `admin` that polls `GET /health` until the telemetry store answers, then for each of `fleet` (`30d`), `devloop` (`365d`) and `agent` (`90d`) issues `CREATE DATABASE IF NOT EXISTS` followed by `ALTER DATABASE ... SET 'ttl'`, because the create statement leaves an existing database's retention unchanged.
The machine SHALL then create, with `CREATE TABLE IF NOT EXISTS`, exactly the `devloop` tables `ci_attribute`, `ci_build`, `batch_event` and `deploy_record` from `services.greptimedb.tables`, each non-append with the flat SST format, its primary key, its time index and no `ttl` of its own, and upload each `devloop_<table>` ingest pipeline from `services.greptimedb.pipelines`, and SHALL create no other table.

#### Scenario: The schema oneshot runs against an empty store and against an existing database

- **WHEN** the container test runs the schema oneshot once against an empty telemetry store, and once after creating `fleet` with another `ttl`
- **THEN** each database carries its declared `ttl` after each run

#### Scenario: The devloop tables are created before the collector writes

- **WHEN** the container test `devloop-ingest` runs the schema oneshot and then the collector
- **THEN** the four `devloop` tables exist with `append_mode=false` and `sst_format=flat` in their create options and no `ttl` of their own, and the collector's first logs write to each succeeds

### Requirement: Credentials exist only as activation-resolved files owned by non-worker users

Every store credential SHALL reach its consumer as a file resolved when magnetite's configuration is activated, readable only by its owner, owned by no omnigent worker account, and absent from the configuration that produced it.
Replacing the account file SHALL restart the telemetry store, and replacing the `collector` password SHALL restart the collector.

**Discharged by**: the evaluation-time ownership check (R8.2) with its mutant, magnetite's credential-holder assertion (R8.2), which admits `fleet-alert` and `devloop-reconcile` as `regulator-password` holders, and the evaluation-time envelope check (R7.1) with its restart-on-rotation mutant.

#### Scenario: The credential files are evaluated

- **WHEN** the evaluation-time ownership check (R8.2) reads magnetite's configuration
- **THEN** the account file is owned by `greptimedb` with mode `0400` and reaches the telemetry store through `LoadCredential`, each password file has mode `0400`, the `collector` password reaches the collector through `LoadCredential`, and the R2 generator's prompted values carry `deploy = false`

#### Scenario: A worker account owns a credential

- **WHEN** magnetite's configuration makes a worker account the owner of the `collector` password file
- **THEN** the evaluation-time ownership check (R8.2) fails, which its mutant shows

#### Scenario: A credential is loaded by a unit outside its holders

- **WHEN** magnetite's configuration is evaluated, which loads each password file into the units that name it
- **THEN** magnetite's credential-holder assertion (R8.2) finds `users` loaded only by `greptimedb`, `admin-password` only by `greptimedb-schema`, `collector-password` only by `opentelemetry-collector`, `regulator-password` only by `greptimedb-envelope`, `fleet-alert` and `devloop-reconcile`, and `perses-password` by none, and an evaluation with a second unit loading `admin-password` fails on it

#### Scenario: The restart on rotation is removed

- **WHEN** magnetite's configuration drops `greptimedb.service` from the account file's restart list
- **THEN** the evaluation-time envelope check (R7.1) fails, which is one of its mutants

### Requirement: Failure notices are posted to one topic

The machine SHALL define `observability-notify@.service` in `flake.modules.nixos.observability-notify`, posting through the one `ntfy-send` package to `fleet-alerts` with the `alerter` token and logging each posted `FAILED` in `/var/lib/observability-notify/failed.log`, and SHALL set `OnFailure=observability-notify@%n.service` on `greptimedb.service`, `greptimedb-schema.service`, `greptimedb-envelope.service`, `opentelemetry-collector.service`, `devloop-reconcile.service`, `devloop-pg-grants.service` and magnetite's nine ZFS property oneshots.

**Discharged by**: the failure-wiring clause and notifier rehearsal of the evaluation-time collector check (R3.1) with their mutants, `checks.<system>.package-ntfy-send-test-token-transport` with its argv mutant, the resolve-hook assertion in `observability-notify.nix`, shown able to fail by an `extendModules` override, and the operator's recorded delivery of a forced failure after the access entries are in force.

#### Scenario: The failure wiring is evaluated

- **WHEN** the evaluation-time collector check (R3.1) reads magnetite's configuration
- **THEN** its failure-wiring clause finds every magnetite service named `greptimedb*`, `devloop-*`, `zfs-set-*`, `zfs-assert-*` or `opentelemetry-collector` listed in `services.observability-notify.units`, which today is `greptimedb.service`, `greptimedb-schema.service`, `greptimedb-envelope.service`, `opentelemetry-collector.service`, `devloop-reconcile.service`, `devloop-pg-grants.service`, `zfs-set-root-greptimedb-quota`, `zfs-set-root-greptimedb-reservation`, `zfs-assert-root-greptimedb-noautosnap`, `zfs-assert-root-nix-noautosnap`, `zfs-assert-root-docker-noautosnap`, `zfs-assert-root-podman-noautosnap`, `zfs-set-root-nix-quota`, `zfs-set-root-nixos-reservation` and `zfs-set-root-home-reservation`, finds each listed name to be a unit with an `ExecStart`, and finds `OnFailure=observability-notify@%n.service` on each

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

- **WHEN** magnetite's and cinnabar's configurations are evaluated
- **THEN** both define `observability-notify@.service` from `flake.modules.nixos.observability-notify`, magnetite through the collector's `agent` role and cinnabar by a direct import, with the option `services.observability-notify.units` unchanged

#### Scenario: The sender is one package

- **WHEN** the notifier and the home-manager `ntfy-send` command are evaluated
- **THEN** both resolve `ntfy-send` to `pkgs/by-name/ntfy-send`

#### Scenario: The notifier carries the alerter token

- **WHEN** magnetite's and cinnabar's configurations are evaluated
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

### Requirement: The collector's queue persists across a telemetry store restart

The machine SHALL back each exporter's sending queue in magnetite's collector with a `file_storage` extension using the `bytes` sizer, 400 MiB for `fleet`, 48 MiB for `agent`, and 48 MiB for `devloop` split as 4 MiB for its metrics exporter, 32 MiB for `otlp_http/devloop_ci_attribute` and 4 MiB each for `otlp_http/devloop_ci_build`, `otlp_http/devloop_batch_event` and `otlp_http/devloop_deploy_record`, in one directory, so that the queues sum to less than 512 MiB and the `fleet` queue holds at least 24 hours at an assumed 256,000 bytes per minute, a rate measured at first activation.

#### Scenario: The persistent queue is removed

- **WHEN** a mutant of magnetite's collector configuration drops the `file_storage` queue, sizes the `fleet` queue below 24 hours at the assumed rate, gives a `devloop` logs exporter no persistent queue, or brings the queues' sum to 512 MiB or more
- **THEN** the evaluation-time collector check (R3.1) fails on its queue clause

#### Scenario: The `fleet` queue rate is measured at first activation

- **WHEN** the operator stops `greptimedb.service` for ten minutes on magnetite and measures the bytes the `fleet` queue accumulates
- **THEN** the operator records the measured rate beside the assumed 256,000 bytes per minute, and a measured rate under which the 400 MiB queue holds less than 24 hours is a finding that resizes the queues

#### Scenario: The store restarts during collection

- **WHEN** the container test stops `greptimedb.service`, emits metrics, starts `greptimedb.service` again and queries the interval
- **THEN** the metrics emitted while the store was stopped are returned
