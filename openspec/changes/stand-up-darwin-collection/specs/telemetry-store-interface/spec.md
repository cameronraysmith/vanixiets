## MODIFIED Requirements

### Requirement: Scrape targets are reached on loopback

The collector on every agent host SHALL reach every metrics source it scrapes on a loopback address, scraping a service's endpoint only where that service runs, and the machine SHALL expose nixbot's `/metrics` to it through a loopback nginx server on `127.0.0.1:9180` that proxies to nixbot's socket, because nixbot listens on no TCP port.
On a darwin agent host the collector SHALL scrape only node_exporter on `127.0.0.1:9100` and its own telemetry on `127.0.0.1:8888`.

**Discharged by**: the evaluation-time collector check (R3.1) with its mutants; the agent module's firewall assertion; `checks.x86_64-linux.otel-collector-darwin`'s loopback clause with its mutants `nodeListenEmpty` and `exporterAddressOther`; the darwin fragment's loopback assertion; `otel-envelope`'s target clause on every agent host.

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

#### Scenario: stibnite's scrape targets are checked

- **WHEN** `checks.x86_64-linux.otel-collector-darwin` renders the darwin agent's configuration from `flake.lib.otelCollectorDarwin`
- **THEN** it finds the jobs `node` on `127.0.0.1:9100`, with `schema.nix`'s darwin keep-list, and `otelcol` on `127.0.0.1:8888`, the `otlp` receiver on `127.0.0.1:4318`, node_exporter's `listenAddress` `127.0.0.1`, and no endpoint off loopback but the two exporters', and the mutants `nodeListenEmpty` and `exporterAddressOther` each fail it

#### Scenario: A darwin listener leaves loopback

- **WHEN** an `extendModules` override of stibnite's configuration, with its `collect` true, binds a receiver or node_exporter outside `127.0.0.0/8`
- **THEN** stibnite's evaluation fails on the darwin fragment's loopback assertion

### Requirement: The collector's configuration bounds what it gathers

The machine SHALL configure each agent host's collector so that per-process memory carries no per-process identifier and covers only processes holding at least the host platform's floor, 64 MiB on a NixOS host and 384 MiB on a darwin host, and node_exporter's series pass a keep-list.
On a NixOS host per-unit signals SHALL cover the `schema.nix` allow-list with at most 40 matching units besides `observability-notify@` instances, paging SHALL report usage only, and file systems SHALL cover the host's ZFS mountpoints.
On a darwin host the `disk` and `filesystem` scrapers SHALL include only `disk0` and `/System/Volumes/Data` by `strict` match, per-process memory SHALL be gathered only by the root `otelcol-process`, and the fleet's own executables named in `schema.nix`'s `process.darwinFleetExecutables` SHALL be kept below the floor, as the scenarios state.
The ingress host's `otel-envelope` SHALL regulate ADR-004's 30 process names per host.

**Discharged by**: the evaluation-time collector check (R3.1) with its mutants; the agent module's assertions with their overrides; `checks.x86_64-linux.otel-collector-darwin`'s clauses with their mutants `seventhIdentityAttribute`, `processEndpoint`, `diskIncludeAll` and `otlpFeedsLogs`, and its `fleetKeptBelowFloor` case with the mutant `keepListIgnored`; the darwin fragment's assertion that each long-running `org.nixos.*` daemon matches exactly one glob of `process.darwinFleetExecutables`; nixpkgs' build-time `otelcol-contrib validate` and the darwin check's `otelcol-contrib validate`; `fleet-ingress-interface` requirement `otel-envelope on the ingress host regulates the fleet budget`; resting, for the darwin floor, on world assumption `A77 — macOS resident size counts each process's mapped share of the shared cache, so ordinary processes read tens to hundreds of MiB`.

#### Scenario: The collector check runs with its mutants

- **WHEN** the evaluation-time collector check (R3.1) runs against magnetite's collector configuration and its mutants, and magnetite's configuration is evaluated and built
- **THEN** the agent module's assertion finds `process.pid`, `process.parent_pid`, `process.command`, `process.command_line`, `process.executable.path` and `process.owner` disabled at source, the check finds the 64 MiB floor stage in the process pipeline, nixpkgs' build-time `otelcol-contrib validate` passes, and the check fails on every mutant; the paging metrics, the node_exporter collectors and its keep-list are literals of the agent module with no copy in the check

#### Scenario: The unit cap is evaluated on each agent host

- **WHEN** any NixOS agent host's configuration is evaluated
- **THEN** the agent module's assertion finds no more than 40 of the host's services, `observability-notify@` excluded, matching the `systemd` receiver's `units`, which the agent builds from the `schema.nix` allow-list, and an override of pyrite with 41 matching services fails the evaluation

#### Scenario: The file systems are evaluated on each agent host

- **WHEN** any NixOS agent host's configuration is evaluated
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

#### Scenario: The darwin agent's configuration is checked

- **WHEN** `checks.x86_64-linux.otel-collector-darwin` renders the darwin agent's configuration from `flake.lib` data only and validates it with the root pin's `otelcol-contrib validate`, and reads the agent's pipelines from stibnite's evaluated darwin fragment
- **THEN** validation passes, the `disk` scraper includes only `disk0` and the `filesystem` scraper only `/System/Volumes/Data`, both by `strict` match, `system.disk.io_time` and `system.disk.pending_operations` are disabled, no `paging` scraper, `system.linux.memory.available` or `systemd` receiver is present, the `otlp` receiver feeds `metrics/host` and no logs pipeline, and the mutants `diskIncludeAll` and `otlpFeedsLogs` each fail the check

#### Scenario: The root process collector is checked

- **WHEN** the same check renders and validates `otelcol-process`'s configuration
- **THEN** it holds only the `process` scraper with the six identity attributes disabled and the 384 MiB floor, sets no `service.name`, has no receiver endpoint, no telemetry listener (`service.telemetry.metrics.level` is `none`) and no credential path, and exports only to `http://127.0.0.1:4318`, and the mutants `seventhIdentityAttribute` and `processEndpoint` each fail the check

#### Scenario: The darwin fleet executables are kept below the floor

- **WHEN** the same check runs the root pin's collector with `otelcol-process`'s filter over process points of a fleet executable below 384 MiB, another executable below it, and an executable above it
- **THEN** the collector writes the fleet executable's and the large executable's points and drops the other, and the mutant `keepListIgnored`, whose filter omits the keep-list, fails the case

### Requirement: The telemetry store and the collector run inside a declared envelope

The machine SHALL run `greptimedb.service` under the static user `greptimedb` with `MemoryHigh=3G`, `MemoryMax=4G`, `MemorySwapMax=0`, `OOMScoreAdjust=500` and a lower `CPUWeight`, magnetite's collector with `MemoryMax=512M` and `OOMScoreAdjust=300`, below the build service's evaluator at 900, and other NixOS agents' collectors with `MemoryMax=256M`.
On a darwin host, which launchd bounds in no memory, the agent SHALL run with a 150 MiB `memory_limiter` and 30 MiB spike and `otelcol-process` with 64 MiB and 16 MiB, and the darwin `otel-envelope` SHALL fail above 256 MiB and 128 MiB of physical footprint, the kernel's own accounting, which unlike the resident size excludes the mapped binary's clean file-backed pages.
The dataset `zroot/root/greptimedb` SHALL carry `quota=16G`, `reservation=12G` and `com.sun:auto-snapshot=false`, applied or asserted at boot.

**Discharged by**: the evaluation-time envelope check (R7.1) with its mutants, the agent role's limiter assertion on every NixOS host without the ingress role, `checks.x86_64-linux.otel-collector-darwin`'s clauses over stibnite's evaluated darwin fragment with the mutants `agentLimiterRaised`, `processSpikeRaised`, `c5LimitsSwapped` and `c5AgentLimitChanged`, `checks.x86_64-linux.otel-envelope`'s darwin memory cases with the mutants `c5WrongPid`, `c5ReadsRss` and `c5UnreadablePasses`, the hourly envelope regulator, the on-demand OOM-order test, and the operator's 24-hour memory measurement on stibnite, resting on world assumption `A70 — macOS top prints a process's physical footprint as unversioned text to an unprivileged account`.

#### Scenario: The evaluation-time envelope check runs with its mutants

- **WHEN** the evaluation-time envelope check (R7.1) runs against magnetite's configuration and against each of its mutants, which drop `MemoryMax`, swap the store's and the collector's `OOMScoreAdjust`, and remove the restart on rotation
- **THEN** it passes on magnetite's configuration, where it finds `MemoryHigh` below `MemoryMax`, `MemorySwapMax=0`, the evaluator's `oom_score_adj` above the store's and the store's above the collector's, and the collector's `memory_limiter` below the collector's `MemoryMax`, and it fails on every mutant; the listener, protocol, user-provider and usage-report properties are the store module's assertions, and the memory knobs ADR-007 names are literals of the store module whose effect R7.2 and the OOM-order test regulate

#### Scenario: Another agent's envelope is evaluated

- **WHEN** a NixOS host without the ingress role is evaluated
- **THEN** its collector runs with `MemoryMax=256M` and a `memory_limiter` of 150 MiB with a 30 MiB spike allowance, and the agent role's assertion fails the evaluation when the limiter is not below `MemoryMax`, as an override of pyrite's limiter to 300 MiB shows

#### Scenario: A darwin host's envelope is evaluated

- **WHEN** `checks.x86_64-linux.otel-collector-darwin` reads stibnite's evaluated darwin fragment
- **THEN** the agent's `memory_limiter` is 150 MiB with a 30 MiB spike and `otelcol-process`'s 64 MiB with a 16 MiB spike, each pipeline of both begins with `memory_limiter`, and the limits the fragment gives the darwin `otel-envelope` are 268,435,456 B for `org.nixos.otelcol` and 134,217,728 B for `org.nixos.otelcol-process`, whose failing and passing cases `fleet-ingress-interface` requirement `otel-envelope regulates each agent from its own collector` states; the mutants `agentLimiterRaised`, `processSpikeRaised`, `c5LimitsSwapped` and `c5AgentLimitChanged` each fail the check

#### Scenario: The darwin collectors' memory is measured

- **WHEN** the launchd alert rules are about to ship, and again once stibnite has collected for 24 hours
- **THEN** before the rules ship the operator confirms or changes the darwin `otel-envelope`'s two limits from a physical-footprint reading of each collector and the envelope's passing runs, and over the 24 hours the operator records both collectors' maximum physical footprint, and the maximum after a sleep when the window holds one

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

### Requirement: Credentials exist only as activation-resolved files owned by non-worker users

Every store credential, every `otel-cert` key and every darwin host's copy of the `alerter` token SHALL reach its consumer as a file resolved when its host's configuration is activated, readable only by its owner, owned by no omnigent worker account, and absent from the configuration that produced it.
Replacing the account file SHALL restart the telemetry store, replacing the `collector` password or a NixOS host's `otel-cert` SHALL restart that host's collector, replacing a darwin host's `otel-cert` SHALL reload `org.nixos.otelcol` through its plist, and replacing the `perses` password SHALL restart `perses.service`.
On a darwin host `otelcol-process` SHALL hold no credential.

**Discharged by**: the evaluation-time ownership check (R8.2) with its mutant, magnetite's credential-holder assertion (R8.2), which admits `fleet-alert`, `devloop-reconcile` and `otel-envelope` as `regulator-password` holders and `perses` as the `perses-password` holder, the evaluation-time envelope check (R7.1) with its restart-on-rotation mutant, the `otel-cert` generator's `restartUnits` on NixOS, the darwin agent's `OTEL_CERT_SHA256`, `perses-password`'s `restartUnits`, `checks.x86_64-linux.otel-collector-darwin`'s no-credential clause on `otelcol-process`, and the operator's reading of the darwin files' owner and mode after stibnite's routine activation.

#### Scenario: The credential files are evaluated

- **WHEN** the evaluation-time ownership check (R8.2) reads magnetite's configuration
- **THEN** the account file is owned by `greptimedb` with mode `0400` and reaches the telemetry store through `LoadCredential`, each password file and the `otel-cert` key have mode `0400` and are owned by no worker account, the `collector` password and the `otel-cert` key reach the collector through `LoadCredential`, the `perses` password reaches `perses.service` through `LoadCredential`, and the R2 generator's prompted values carry `deploy = false`

#### Scenario: A worker account owns a credential

- **WHEN** magnetite's configuration makes a worker account the owner of the `collector` password file
- **THEN** the evaluation-time ownership check (R8.2) fails, which its mutant shows

#### Scenario: A credential is loaded by a unit outside its holders

- **WHEN** magnetite's configuration is evaluated, which loads each password file into the units that name it
- **THEN** magnetite's credential-holder assertion (R8.2) finds `users` loaded only by `greptimedb`, `admin-password` only by `greptimedb-schema`, `collector-password` only by `opentelemetry-collector`, `regulator-password` only by `greptimedb-envelope`, `fleet-alert`, `devloop-reconcile` and `otel-envelope`, and `perses-password` only by `perses`, and an evaluation with a second unit loading `admin-password` or `perses-password` fails on it

#### Scenario: The restart on rotation is removed

- **WHEN** magnetite's configuration drops `greptimedb.service` from the account file's restart list
- **THEN** the evaluation-time envelope check (R7.1) fails, which is one of its mutants

#### Scenario: The perses password is replaced

- **WHEN** `greptimedb-users` is regenerated and magnetite is deployed
- **THEN** `perses.service` restarts with the new password, because `perses-password` lists it in `restartUnits`, and its next query through `greptimedb-promql` succeeds

#### Scenario: stibnite's credential files are read

- **WHEN** the operator lists stibnite's `otel-cert` key and `ntfy-alerter` token after its routine activation
- **THEN** both are owned by `_otelcol` with mode `-r--------`, the token reaches `observability-notify-run` only as `NTFY_TOKEN_FILE`, and the operator records the listing

#### Scenario: stibnite's certificate is reissued

- **WHEN** stibnite's `otel-cert` is regenerated and stibnite is activated
- **THEN** `org.nixos.otelcol`'s plist carries a new `OTEL_CERT_SHA256`, the sha256 of the new `cert.pem`, so nix-darwin reloads the agent with the new key

#### Scenario: The root process collector is given a credential

- **WHEN** `checks.x86_64-linux.otel-collector-darwin` reads `otelcol-process`'s rendered configuration
- **THEN** it finds no certificate, key, token or password path, and fails if one is present

### Requirement: Omnigent unit names are stored under aliases

The machine SHALL rewrite each `omnigent-host-<owner>.service` unit name to `omnigent-host-<alias>.service`, and each `org.nixos.omnigent-host-<owner>` launchd label to `org.nixos.omnigent-host-<alias>`, from `ownerAliases` in `schema.nix`, `{ cameron = "owner-1"; janettesmith = "owner-2"; }` in S1, before any exporter.

**Discharged by**: the agent module's alias assertion on every NixOS agent host with its override; the darwin fragment's assertion that every `omnigent-host-<owner>` launchd daemon has an alias in `flake.lib.otelCollectorSchema.ownerAliases`, with its `omnigent-host-nobody` override; the container test's alias read-back; `checks.x86_64-linux.otel-collector-darwin`'s probe fixture for `org.nixos.omnigent-host-cameron` with the mutant `aliasDropped`.

#### Scenario: An Omnigent owner has no alias

- **WHEN** an agent host's configuration runs an `omnigent-host-<owner>` unit whose owner `ownerAliases` lacks, or an alias contains an owner's name
- **THEN** that host's evaluation fails on the agent module's alias assertion, as an override of cinnabar's configuration with an `omnigent-host-nobody` service shows

#### Scenario: A darwin Omnigent owner has no alias

- **WHEN** an `extendModules` override of stibnite's configuration, with its `collect` true, adds an `omnigent-host-nobody` launchd daemon
- **THEN** stibnite's evaluation fails on the darwin fragment's alias assertion

#### Scenario: Stored unit names are read back in the container test

- **WHEN** the container test reads the stored `systemd_unit_name` values after the collector has reported an `omnigent-host-<owner>` unit
- **THEN** the unit appears under its alias, and no stored value contains the owner's name

#### Scenario: A launchd label is written by the probe

- **WHEN** `checks.x86_64-linux.otel-collector-darwin` runs the probe's parser over the `launchctl print` reply recorded on stibnite for `org.nixos.omnigent-host-cameron`
- **THEN** `launchd.prom` carries `launchd_label="org.nixos.omnigent-host-owner-1"`, no line contains `cameron`, and the mutant `aliasDropped` fails the check

### Requirement: Failure notices are posted to one topic

The machine SHALL define `observability-notify@.service` in `flake.modules.nixos.observability-notify` on every NixOS agent host, posting through the one `ntfy-send` package to `fleet-alerts` with the `alerter` token and logging each posted `FAILED` in `/var/lib/observability-notify/failed.log`, and SHALL set `OnFailure=observability-notify@%n.service` on the units the scenarios below name.
On every darwin agent host `org.nixos.otel-envelope` SHALL run under `observability-notify-run`, which posts `FAILED <label> on <host>` and `RESOLVED <label> on <host>` through the same posting code and `ntfy-send` to `fleet-alerts` with the `alerter` token, at most one `FAILED` per label per 900 s, appending each posted `FAILED` to `/var/lib/otel-envelope/notify.log`, the log path its caller names.

**Discharged by**: the failure-wiring clause and notifier rehearsal of the evaluation-time collector check (R3.1) with their mutants, the agent role's notified-unit assertion on every NixOS agent host, `checks.<system>.package-ntfy-send-test-token-transport` with its argv mutant, the resolve-hook assertion in `observability-notify.nix`, shown able to fail by an `extendModules` override, `checks.x86_64-linux.otel-collector-darwin`'s wrapper cases with the mutant `postEveryFailure`, and the operator's recorded deliveries.

#### Scenario: Each named unit has the failure handler

- **WHEN** magnetite's configuration is evaluated
- **THEN** `OnFailure=observability-notify@%n.service` is set on `greptimedb.service`, `greptimedb-schema.service`, `greptimedb-envelope.service`, `opentelemetry-collector.service`, `otel-envelope.service`, `devloop-reconcile.service`, `devloop-pg-grants.service`, `fleet-alert.service` and magnetite's nine ZFS property oneshots

#### Scenario: Every agent host notifies its collector and regulator

- **WHEN** any NixOS agent host's configuration is evaluated
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

- **WHEN** the NixOS agent hosts' configurations are evaluated
- **THEN** each defines `observability-notify@.service` from `flake.modules.nixos.observability-notify` through the collector's `agent` role, cinnabar's direct import merging with it, with the option `services.observability-notify.units` unchanged

#### Scenario: The sender is one package

- **WHEN** the notifier, the darwin wrapper and the home-manager `ntfy-send` command are evaluated
- **THEN** each resolves `ntfy-send` to `pkgs/by-name/ntfy-send`

#### Scenario: The notifier carries the alerter token

- **WHEN** the NixOS agent hosts' configurations are evaluated
- **THEN** `observability-notify.nix`'s assertion holds that, with `tokenFile` set, each notified unit's `ExecStartPost=` and `ExecStopPost=` hooks run under `env NTFY_TOKEN_FILE=<tokenFile>`, and an `extendModules` override that replaces one unit's hooks makes evaluation fail

#### Scenario: Each posted failure is logged

- **WHEN** the collector check's rehearsal runs the notifier's scripts against a temporary state directory and a recording `ntfy-send`, with one failure that posts and one that the 15-minute interval suppresses
- **THEN** `failed.log` gains exactly one line of the form `<epoch> <unit> <host>`, for the posted `FAILED`, and a mutant that drops the append makes the rehearsal fail

#### Scenario: The darwin wrapper posts once per episode

- **WHEN** `checks.x86_64-linux.otel-collector-darwin` runs `observability-notify-run` for `otel-envelope` on stibnite over a recording `ntfy-send` with runs that pass, fail, fail and pass, and separately with a first run that fails
- **THEN** the first sequence posts exactly one `FAILED otel-envelope on stibnite` and one `RESOLVED otel-envelope on stibnite`, the first failing run posts `FAILED`, the token reaches `ntfy-send` only as `NTFY_TOKEN_FILE`, each posted `FAILED` is appended to the log path the caller names, and the mutant `postEveryFailure` fails the check

#### Scenario: NixOS notices are unchanged by the shared posting code

- **WHEN** the NixOS template calls the posting code it shares with `observability-notify-run`, naming `/var/lib/observability-notify/failed.log` as its log path
- **THEN** `checks.x86_64-linux.otel-envelope` and the notice cases of `vmTests.x86_64-linux.fleet-ingress` pass unchanged, and each posted `FAILED` is still appended to `failed.log`, which the alert evaluator's budget reads on magnetite

#### Scenario: A failure is delivered at first activation

- **WHEN** `greptimedb-envelope` is made to fail at first activation
- **THEN** a message naming `greptimedb-envelope.service` and magnetite appears on `fleet-alerts`, and the operator records it

#### Scenario: A failure is delivered after the access entries are in force

- **WHEN** after cinnabar's ntfy refuses anonymous publishing to `fleet-*`, `greptimedb-envelope` is made to fail on magnetite
- **THEN** a message naming `greptimedb-envelope.service` and magnetite appears on `fleet-alerts`, a line for it appears in `failed.log`, and the operator records both

#### Scenario: Another agent host's regulator fails

- **WHEN** cinnabar's `otel-envelope` fails at acceptance
- **THEN** a message naming `otel-envelope.service` and cinnabar appears on `fleet-alerts`, and the operator records it

#### Scenario: stibnite's regulator fails at acceptance

- **WHEN** stibnite's `otel-envelope` fails because the operator stopped `org.nixos.otelcol` for two envelope periods
- **THEN** `FAILED otel-envelope on stibnite` appears on `fleet-alerts` and in `/var/lib/otel-envelope/notify.log`, and the operator records both

### Requirement: A failure episode ends at the unit's next successful start or exit

Each unit that sets `OnFailure=observability-notify@%n.service` SHALL carry an `ExecStartPost=` and an `ExecStopPost=` hook running one script that posts one `RESOLVED` and ends the failure episode at the unit's next successful start or exit.
On a darwin agent host `observability-notify-run` SHALL post one `RESOLVED` and end a label's failure episode at the label's next passing run.

**Discharged by**: the failure-wiring clause and notifier rehearsal of the evaluation-time collector check (R3.1) with their mutants; `checks.x86_64-linux.otel-collector-darwin`'s wrapper cases with the mutant `postEveryFailure`; the operator's stopped-collector control on stibnite.

#### Scenario: Failure notices continue across automatic restarts

- **WHEN** a notified unit fails, systemd restarts it automatically, it starts successfully, and it later fails again
- **THEN** the successful start posts one `RESOLVED` and ends the episode, so the later failure posts a new notice, and a oneshot posts no second `RESOLVED` on its stop because its start hook already removed the stamp

#### Scenario: A unit's start-time recovery hook is removed

- **WHEN** a mutant of magnetite's configuration drops the `RESOLVED` `ExecStartPost=` hook from one notified unit, or gives a oneshot's start hook a script other than its stop hook's
- **THEN** the evaluation-time collector check (R3.1) fails on its failure-wiring clause

#### Scenario: A crash loop is rate-limited

- **WHEN** the collector check's rehearsal runs the notifier's scripts against a temporary stamp directory and a recording `ntfy-send`, with a crash, a start, a crash and a start within 15 minutes, then a crash after 15 minutes
- **THEN** the first two crashes post exactly one `FAILED` and one `RESOLVED`, and the later crash posts a new `FAILED` and `RESOLVED`, so a persistent crash loop yields one pair, then at most one new pair per 15 minutes per unit

#### Scenario: A darwin episode ends at the next passing run

- **WHEN** the wrapper's cases run a failing run, a passing run, a second failure episode inside 900 s, and a third after 900 s
- **THEN** the passing run posts one `RESOLVED` and ends the episode, the second episode posts nothing, and the third posts a new `FAILED`

#### Scenario: stibnite's collector returns at acceptance

- **WHEN** the operator loads `org.nixos.otelcol` again after stopping it for two envelope periods
- **THEN** the next passing `otel-envelope` run posts one `RESOLVED otel-envelope on stibnite`, nothing else is posted, and the operator records it

### Requirement: This capability states its own trust boundary

This capability SHALL state what its properties guarantee and what they do not, and SHALL NOT be described, by itself or in any downstream report, as an end-to-end guarantee that a series reaches the telemetry store or that a failure reaches a person.

**Discharged by**: the requirement's own statement in the scenarios below; no regulator applies.

#### Scenario: The properties above are read as a set

- **WHEN** the properties of this capability are read as a set
- **THEN** what they establish is that the telemetry store and its scrape targets listen only on loopback, that four accounts with fixed modes gate every `/v1/` path, that ingest and reads use the stated paths and headers, that the databases carry their declared retention, that object data is configured under one prefix of one bucket, that credentials exist only as activation-resolved files owned by non-worker users, that the store and collector run inside the declared envelope, darwin's runtime memory clause included, that the queue is persistent and bounded, and that the named units and darwin's wrapped `otel-envelope` hand their failures to the notifier's posting code, which posts with the `alerter` token, each as far as its own check, assertion, test or recorded observation reaches

#### Scenario: A guarantee about R2 is sought from this capability

- **WHEN** someone asks whether these properties guarantee that object data is durable or that the R2 token is scoped to the store prefix
- **THEN** the answer is no: the token's scope and the bucket's durability are set and provided by Cloudflare, and this machine does not assert them

#### Scenario: A guarantee about who can reach the loopback listener is sought

- **WHEN** someone asks whether loopback binding limits access to the named consumers
- **THEN** the answer is no: any root process on magnetite can reach the loopback listener, and only the account credentials distinguish it from the named consumers

#### Scenario: A guarantee about notice delivery or publishing is sought

- **WHEN** someone asks whether these properties guarantee that a failure notice reaches a person, or that only the notifier and the alert evaluator publish to `fleet-alerts`
- **THEN** the answer is no: ntfy on cinnabar enforces that only the `alerter` token publishes to `fleet-*`, and this machine only configures it; any root process on a host holding a copy of that token can read it, magnetite, cinnabar and every other NixOS agent host, and stibnite, where the copy is owned by `_otelcol`; and cinnabar is a single delivery path that nothing here watches

#### Scenario: An end-to-end guarantee is sought

- **WHEN** someone asks whether these properties guarantee that a given series reaches the telemetry store
- **THEN** the answer is no: each stage's configuration is checked and the tested pipeline behaves as stated, and nothing here observes the whole path on magnetite end to end
