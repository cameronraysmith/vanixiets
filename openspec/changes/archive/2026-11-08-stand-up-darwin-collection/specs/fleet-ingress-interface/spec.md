## RENAMED Requirements

- FROM: `### Requirement: pyrite's NVMe health is read by a loopback exporter`
- TO: `### Requirement: A laptop's disk health is read on the host and served on loopback`

## MODIFIED Requirements

### Requirement: One host table declares the agent hosts and what each reports

`flake.lib.observabilityHosts` SHALL map each agent host to its `platform`, `collect`, `alwaysOn`, `notifiedUnits` and `smartDevices`, and the collector's `agent` role machines and whether each collects, each host's notified units, the evaluator's always-on hosts, expected hosts by platform and `SystemdUnitFailed` exclusion, and the devices whose disk health is read SHALL be read from it.

**Discharged by**: the agent role's per-host assertions with their `extendModules` overrides; the `otel-collector` inventory instance's platform assertion with its scratch-edit control; `checks.x86_64-linux.fleet-alert`'s exclusion, absence and platform legs.

#### Scenario: Each row's platform follows the inventory

- **WHEN** `flake.lib.observabilityHosts` and `modules/clan/inventory/machines.nix` are evaluated
- **THEN** Each row's `platform`, `nixos` or `darwin`, SHALL equal the `machineClass` that `modules/clan/inventory/machines.nix` gives the same machine.

#### Scenario: The table is evaluated

- **WHEN** `flake.lib.observabilityHosts` is evaluated
- **THEN** it names magnetite, cinnabar, pyrite, electrum, galena, scheelite and stibnite, every host with `collect = true` once its first watched deploy has happened, only magnetite and cinnabar with `alwaysOn = true`, only stibnite with `platform = "darwin"` and every other host with `platform = "nixos"`, only pyrite with `smartDevices = [ "/dev/nvme0" ]` and stibnite with `smartDevices = [ "disk0" ]`, every NixOS host with `opentelemetry-collector` and `otel-envelope` among its `notifiedUnits`, cinnabar also with `fleet-deadman` and magnetite also with its store, dev-loop, evaluator and dataset units, and stibnite with `notifiedUnits = [ "otel-envelope" ]`, the one darwin job that posts its own notices

#### Scenario: A host does not collect yet

- **WHEN** a host's `collect` is false
- **THEN** its configuration carries none of the agent role's units, launchd jobs, collector settings or `zerotierone` change, and no alert rule expects it or counts it as always-on, while a darwin host's `otel-cert` key and `ntfy-alerter` token are already installed owned by `_otelcol`

#### Scenario: A notified unit is not a unit of its host

- **WHEN** a NixOS host's `notifiedUnits` names a unit for which the host defines no service with an `ExecStart`, or omits `opentelemetry-collector` or `otel-envelope`
- **THEN** that host's evaluation fails on the agent role's assertion, as an override of cinnabar's configuration that notifies `zfs-set-root-typo-quota` shows

#### Scenario: A row's platform disagrees with the inventory

- **WHEN** a row's `platform` differs from its machine's `machineClass` in `modules/clan/inventory/machines.nix`
- **THEN** evaluation fails on the `otel-collector` inventory instance's assertion naming that machine, as a scratch edit setting stibnite's `platform` to `"nixos"` shows

### Requirement: The collection CA issues each agent host one certificate

The clan vars generator `otel-ca` SHALL be shared, with `ca.key` never deployed and `ca.crt` public, and `otel-cert` SHALL issue each agent host a P-256 certificate signed by it, valid 3650 days, with CN the machine name and `extendedKeyUsage=clientAuth`, or on the ingress host `serverAuth,clientAuth` with `IP:<flake.lib.hosts.magnetite.zt>` and `DNS:magnetite.zt` as SANs.

**Discharged by**: the plan's `openssl` reading of each issued certificate and its hash check after every vars step; `vmTests.x86_64-linux.fleet-ingress`'s refusal and delivery cases; stibnite's evaluation of the agent role's `darwinModule`; the operator's reading of the darwin key's owner and mode after stibnite's routine activation.

#### Scenario: A darwin agent host's certificate is wired to its agent

- **WHEN** `otel-cert` is declared on a darwin agent host
- **THEN** On a darwin agent host the key SHALL be owned by `_otelcol` with mode `0400` and declared without `restartUnits`, and the agent's plist SHALL carry the certificate's sha256 as `OTEL_CERT_SHA256`, so a reissued certificate reloads the agent.

#### Scenario: The ingress host's certificate is read

- **WHEN** `openssl x509 -ext subjectAltName,extendedKeyUsage` reads `vars/per-machine/magnetite/otel-cert/cert.pem/value`
- **THEN** it shows `IP Address:fddb:4344:343b:14b9:399:930f:39db:40d2`, `DNS:magnetite.zt`, `TLS Web Server Authentication` and `TLS Web Client Authentication`

#### Scenario: A vars step runs

- **WHEN** a certificate is generated for a host, or a host is added as a reader of a shared var
- **THEN** the sha256 of `otel-ca`'s `ca.crt` and of the `ntfy-alerter` token are unchanged afterwards, and the step stops otherwise

#### Scenario: A certificate's SANs or usage change

- **WHEN** the SAN string or the key usage rendered for a host's certificate differs from the one recorded in its `validation`
- **THEN** clan regenerates that host's `otel-cert`, and its new files restart a NixOS host's collector through `restartUnits` and change a darwin host's `OTEL_CERT_SHA256`, so the host's next activation reloads `org.nixos.otelcol`

#### Scenario: stibnite's certificate is read

- **WHEN** `openssl x509 -subject -ext extendedKeyUsage` reads `vars/per-machine/stibnite/otel-cert/cert.pem/value` and `openssl verify -CAfile vars/shared/otel-ca/ca.crt/value` checks it
- **THEN** it shows `CN=stibnite` and `TLS Web Client Authentication`, and the verification succeeds

#### Scenario: A darwin key is installed

- **WHEN** stibnite has been activated with the agent role's `darwinModule`
- **THEN** its `otel-cert` declaration sets no `restartUnits`, which clan-core rejects on darwin, and the installed key is owned by `_otelcol` with mode `-r--------`, which the operator records

### Requirement: Each agent exports by its role

On the ingress host the agent's pipelines SHALL end in `forward`, and on every other agent host, darwin included, in `otlp_http/ingress` for metrics and `otlp_http/ingress-logs` for logs, each to `https://[${flake.lib.hosts.magnetite.zt}]:4318` with its `otel-cert`, `ca_file` the `otel-ca` certificate, `min_version: "1.3"`, a `file_storage` queue of 400 MiB and 16 MiB with the `bytes` sizer, and retry without a time limit.

**Discharged by**: the agent role's queue assertion with its `extendModules` override; the darwin fragment's queue assertions with their `extendModules` overrides; `checks.x86_64-linux.otel-collector-darwin`'s exporter-address clause with its mutant `exporterAddressOther`; `vmTests.x86_64-linux.fleet-ingress`'s delivery and back-pressure cases; the measured queue rate at cinnabar's first deploy; the exporter's sent points at stibnite's first activation, resting on world assumption `A65 — A store-built binary on stibnite reaches the ingress over ZeroTier`.

#### Scenario: A darwin agent's memory is bounded inside the process

- **WHEN** a darwin agent host's collector is configured
- **THEN** On a darwin agent host the 150 MiB `memory_limiter` with a 30 MiB spike allowance SHALL be the agent's only memory bound inside the process, because launchd bounds no memory.

#### Scenario: An agent's queue is evaluated

- **WHEN** a host without the ingress role is evaluated
- **THEN** the agent role asserts that both exporters queue in `file_storage` with the `bytes` sizer and unlimited retry, that the metrics queue holds at least 24 hours at `flake.lib.otelCollectorSchema.fleetBytesPerMinute`, and that the queues sum to less than 512 MiB, and an override of cinnabar's metrics queue to 64 MiB fails the evaluation

#### Scenario: A darwin agent's queue is evaluated

- **WHEN** stibnite's configuration is evaluated with its `collect` true
- **THEN** the darwin fragment asserts the same 24-hour relation and the sum below 512 MiB over the queues in `/var/lib/opentelemetry-collector/queue`, and an `extendModules` override of stibnite's metrics queue to 64 MiB fails the evaluation

#### Scenario: A darwin agent's exporter address is checked

- **WHEN** `checks.x86_64-linux.otel-collector-darwin` renders the darwin agent's configuration from `flake.lib.otelCollectorDarwin`
- **THEN** both exporters' endpoint address equals the content of `vars/shared/zerotier-ip-magnetite-zerotier/ip/value`, the limiter is 150 MiB with a 30 MiB spike, and the mutant `exporterAddressOther` fails the check

#### Scenario: The ingress refuses data under back-pressure

- **WHEN** `fleet-ingress` fills the ingress's store queue, and later makes its limiter refuse, while the agent keeps collecting
- **THEN** the ingress answers HTTP 503, the agent's queue grows and then drains, and every point the agent scraped arrives in the store

#### Scenario: An agent queues before the ingress exists

- **WHEN** cinnabar is deployed before magnetite's receiver exists
- **THEN** cinnabar's metrics queue grows until magnetite's deploy and then drains to zero, and the operator records its growth per minute against the assumed rate

#### Scenario: stibnite's agent first exports

- **WHEN** stibnite's agent has run for two minutes after its watched activation
- **THEN** `otlp_http/ingress`'s `otelcol_exporter_sent_metric_points` at `127.0.0.1:8888` grows across two reads 60 s apart, and the operator records both reads

### Requirement: otel-envelope regulates each agent from its own collector

Every agent host SHALL run `otel-envelope` every 5 minutes, failing when its collector's telemetry at `127.0.0.1:8888` or a declared scrape target is unanswered on two consecutive runs, an exporter's queue reaches 90% of its capacity, or a loss counter increased, an absent loss counter reading as zero, as the scenarios state.

**Discharged by**: `checks.x86_64-linux.otel-envelope` with its mutants, its darwin cases and its mutants `c5WrongPid`, `c5ReadsRss` and `c5UnreadablePasses`; `checks.x86_64-linux.otel-collector-darwin`'s wrapper cases; `vmTests.x86_64-linux.fleet-ingress`'s loss, back-pressure, crash-loop and long-running cases; the operator's stopped-collector and stopped-exporter controls on cinnabar and stopped-collector control on stibnite; resting on world assumption `A70 — macOS top prints a process's physical footprint as unversioned text to an unprivileged account`.

#### Scenario: The envelope runs as each platform's job

- **WHEN** `otel-envelope` is installed on an agent host
- **THEN** On a NixOS host it SHALL run as `otel-envelope.service`; on a darwin host as `org.nixos.otel-envelope`, a `StartInterval = 300` job run as `_otelcol` under `observability-notify-run`, which SHALL also fail when `org.nixos.otelcol`'s physical footprint exceeds 256 MiB or `org.nixos.otelcol-process`'s exceeds 128 MiB, or when either running job's footprint cannot be read within 10 seconds.

#### Scenario: The darwin envelope measures the physical footprint

- **WHEN** the darwin envelope reads a running job's memory
- **THEN** The footprint, the kernel's own accounting of a process's memory, is the measure, because the resident size also counts the file-backed pages of the mapped collector binary.

#### Scenario: The loss counters are read

- **WHEN** a run compares the telemetry with the previous run's values
- **THEN** an increase of `otelcol_exporter_send_failed_*` on any exporter, of `otelcol_receiver_refused_*` on any receiver but `otlp/mesh`, or, on a host without the ingress role, of `otelcol_exporter_enqueue_failed_*` fails the run, and a counter below its recorded value counts its current value as the increase

#### Scenario: The ingress is under back-pressure

- **WHEN** on the ingress host `otlp/mesh` refuses points or a store exporter counts enqueue failures while its queue is below 90%
- **THEN** the run passes, because the agents keep those points queued

#### Scenario: A loss counter has never incremented

- **WHEN** the telemetry carries no `otelcol_exporter_send_failed_*` or `otelcol_exporter_enqueue_failed_*` series
- **THEN** each reads as zero, while a run that obtains no telemetry at all fails

#### Scenario: The collector crash-loops

- **WHEN** `fleet-ingress` kills the agent collector four times within 10 minutes and no point is lost
- **THEN** the envelope passes each run in which the telemetry answered and fails each second consecutive run in which it did not, and the counter resets fail nothing

#### Scenario: The envelope runs for a long time

- **WHEN** the envelope runs three times over growing counters while a target answers only after 15 seconds
- **THEN** each run ends within its start timeout, the second and later runs fail on that target, and the state file holds one line per series

#### Scenario: A collector or exporter is stopped at acceptance

- **WHEN** the operator stops cinnabar's collector, and later cinnabar's `prometheus-node-exporter`
- **THEN** cinnabar's `otel-envelope` fails within 10 minutes each time and a `FAILED` naming `otel-envelope.service` and cinnabar reaches `fleet-alerts`, and the operator records both

#### Scenario: The darwin envelope's inputs are evaluated

- **WHEN** `checks.x86_64-linux.otel-envelope` runs its darwin case set over telemetry recorded in stibnite's shape
- **THEN** the envelope probes only the targets `node` at `127.0.0.1:9100` and `otelcol` at `127.0.0.1:8888`, reads only the exporters `otlp_http/ingress` and `otlp_http/ingress-logs`, takes its state directory from `STATE_DIRECTORY`, and each case passes or fails as the NixOS case of the same clause does

#### Scenario: A darwin collector holds too much memory

- **WHEN** the darwin cases give the envelope a stub `launchctl` that prints each job's `pid` and a stub `top` that prints recorded `top -l 1 -pid <pid> -stats pid,mem` text with a MEM of 255 MiB, then 257 MiB, then `1G+`, for `org.nixos.otelcol`, and 129 MiB, then `2144K`, for `org.nixos.otelcol-process`
- **THEN** the 255 MiB and `2144K` runs pass, the 257 MiB, `1G+` and 129 MiB runs fail on the memory clause naming the job and its MiB, and the mutant `c5WrongPid`, which reads another pid's footprint, fails the check

#### Scenario: A darwin collector's resident size exceeds its limit while its footprint does not

- **WHEN** the stub `top` prints stibnite's recorded footprint of 102 MiB for `org.nixos.otelcol-process` while its resident size, recorded at 179 MiB on 2026-11-06, exceeds 128 MiB
- **THEN** the memory clause passes, and the mutant `c5ReadsRss`, which reads the resident size, fails the check

#### Scenario: A darwin collector's footprint cannot be read

- **WHEN** the stub `top` prints a MEM field without a unit, prints no row for the pid, or does not answer within 10 seconds
- **THEN** the memory clause fails naming the job, and the mutant `c5UnreadablePasses`, which passes an unreadable field, fails the check

#### Scenario: stibnite's collector is stopped at acceptance

- **WHEN** the operator boots out `org.nixos.otelcol` on stibnite for two envelope periods and then loads it again
- **THEN** one `FAILED otel-envelope on stibnite` reaches `fleet-alerts` and its line is appended to `/var/lib/otel-envelope/notify.log`, one `RESOLVED otel-envelope on stibnite` follows the next passing run, nothing else is posted, and the operator records both posts and the log line

### Requirement: A laptop's disk health is read on the host and served on loopback

On each host whose `smartDevices` is non-empty, its disk health SHALL be read on that host and reach its collector on loopback under smartctl_exporter's metric names, filtered by SC's smartctl keep-list.

**Discharged by**: R3.1's loopback clause; `otel-envelope`'s target clause; `checks.x86_64-linux.otel-collector-darwin`'s smartctl fixture; the operator's stored SMART reads on pyrite and stibnite after their deploys, resting on world assumptions `A51 — pyrite's NVMe controller answers the SMART health log at the pinned smartmontools` and `A63 — stibnite's internal SSD answers the SMART health read without privilege at the pinned smartmontools`.

#### Scenario: Each platform serves the disk health its own way

- **WHEN** a host whose `smartDevices` is non-empty is configured
- **THEN** On a NixOS host `prometheus-smartctl-exporter` SHALL serve it on `127.0.0.1:9633` with `MemoryMax=64M`, granting `smartctl-exporter-access` read and write on each device before every start; on a darwin host the probe SHALL write `smartctl -j -H -A <device>` into `smartctl.prom`, typing as a counter each field the exporter declares a counter, for the loopback node_exporter to serve.

#### Scenario: pyrite is deployed

- **WHEN** pyrite has been switched to the agent role without a reboot and one scrape interval has passed
- **THEN** `smartctl_device_critical_warning_total{host_name="pyrite"}` and `smartctl_device_percentage_used_total{host_name="pyrite"}`, the names the store gives the exporter's counter-typed fields, are stored, and the operator records both

#### Scenario: stibnite's SMART reply is parsed

- **WHEN** `checks.x86_64-linux.otel-collector-darwin` runs the probe's SMART writer over the `smartctl -j -H -A disk0` reply recorded on stibnite
- **THEN** `smartctl.prom` equals its expected file: the eight names of the smartctl keep-list with `device="disk0"`, `temperature_type="current"` on the temperature, `# TYPE` counter on every field but `smart_status` and `temperature`, and no `serial_number`

#### Scenario: stibnite is activated

- **WHEN** stibnite's probe has run for one interval after its watched activation
- **THEN** `smartctl_device_critical_warning_total{host_name="stibnite"}` and `smartctl_device_percentage_used_total{host_name="stibnite"}` are stored, read by the probe as `_prometheus-node-exporter`, and the operator records both

### Requirement: This capability states its own trust boundary

This capability SHALL state what its properties guarantee and what they do not, and SHALL NOT be described, by itself or in any downstream report, as an end-to-end guarantee that a host's series reach the store.

**Discharged by**: the requirement's own statement in the scenarios below; no regulator applies.

#### Scenario: The properties above are read as a set

- **WHEN** the properties of this capability are read as a set
- **THEN** what they establish is that each agent host holds a certificate from `otel-ca`, that the ingress accepts only such holders on magnetite's ZeroTier address at TLS 1.3, that each agent, darwin included, queues and retries toward it, that the darwin probe writes launchd job state and disk health for the loopback node_exporter, and that `otel-envelope` regulates each collector and the fleet budget, each as far as its check, assertion, container test or recorded observation reaches

#### Scenario: A guarantee about a certificate holder is sought

- **WHEN** someone asks whether a host can write series only under its own name
- **THEN** the answer is no: any holder of an `otel-ca` certificate is trusted to write, and a certificate's CN is not bound to the `host.name` its agent stamps

#### Scenario: A guarantee about a lost key is sought

- **WHEN** someone asks whether a lost or stolen agent key stops being accepted
- **THEN** the answer is no: certificates have no revocation, and a lost key stays valid until `otel-ca` is rotated, which the CA key, kept only in the encrypted repository vars, makes possible; stibnite's key sits on a laptop that leaves the operator's premises

#### Scenario: A guarantee about the network is sought

- **WHEN** someone asks whether ZeroTier authenticates the writer
- **THEN** the answer is no: ZeroTier is trusted to carry packets between members and nothing more, so the two Android members and the darwin machines without a certificate reach the handshake and only mTLS refuses them

#### Scenario: A guarantee about launchd's report is sought

- **WHEN** someone asks whether the probe's launchd series are correct after a macOS update
- **THEN** the answer is no: the probe trusts `launchctl print`'s text, which launchctl's manual page says is not API, and the parser's fixtures hold only for the text recorded on stibnite, under world assumption `A62 — launchctl print reports a system job's state, runs and last exit code as unversioned text, and omits the exit code for some killed jobs`

#### Scenario: A guarantee about root on a darwin host is sought

- **WHEN** someone asks whether a darwin host's collection runs without root
- **THEN** the answer is no: `org.nixos.otelcol-process` runs as root to read other accounts' process memory, confined to the `process` scraper with no receiver endpoint, telemetry listener or credential, and any root process on that host can read the `_otelcol` key and inject points on loopback

#### Scenario: An end-to-end guarantee is sought

- **WHEN** someone asks whether these properties guarantee that a given series reaches the store
- **THEN** the answer is no: each stage's configuration, the gating checks, the container test and `otel-envelope` behave as stated, and nothing here observes a series' whole path

## ADDED Requirements

### Requirement: The darwin probe reports each allow-listed launchd job and the host's disk health in a textfile

On each darwin agent host, `org.nixos.otel-host-probe` SHALL run every 60 s as `_prometheus-node-exporter` and replace `launchd.prom`, read from `launchctl print` for each allow-listed launchd job the host defines, and `smartctl.prom` in `/var/lib/prometheus-node-exporter/textfile` by write-then-rename within 30 s, as the scenarios state.
node_exporter SHALL serve that directory on `127.0.0.1:9100` with only its `textfile` collector.

**Discharged by**: `checks.x86_64-linux.otel-collector-darwin`'s label clause, node_exporter clause and parser fixtures, with the mutants `nodeListenEmpty`, `labelDotUnescaped`, `aliasDropped`, `pidWritten`, `missingExitCodeAsZero` and `idleExitAsFailure`; the operator's signal-kill control on stibnite, resting on world assumption `A62 — launchctl print reports a system job's state, runs and last exit code as unversioned text, and omits the exit code for some killed jobs`.

#### Scenario: The probe's labels and listener are checked

- **WHEN** `checks.x86_64-linux.otel-collector-darwin` renders the probe and node_exporter for a fixture list of stibnite's daemons
- **THEN** the probe's labels equal the launchd allow-list in `schema.nix` intersected with that list, node_exporter listens on `127.0.0.1:9100` with `--collector.disable-defaults` and only `--collector.textfile`, and the mutants `nodeListenEmpty` and `labelDotUnescaped` each fail the check

#### Scenario: A job's state is parsed

- **WHEN** the parser reads a recorded reply with `state = running`, `runs = 3`, a `pid` and `last exit code = 0`, and another with `last exit code = 78`
- **THEN** `launchd.prom` holds `launchd_job_state` 1 for `launchd_state="running"` and 0 for `not_running`, `unloaded` and `other`, `launchd_job_runs_total` 3, `launchd_job_last_exit_code` 0 and 78 respectively, and no `pid`, and the mutant `pidWritten` fails the check

#### Scenario: A job has never exited

- **WHEN** a reply's `last exit code` reads `(never exited)`
- **THEN** `launchd_job_last_exit_code` for that label is 0

#### Scenario: A job's exit code is missing or not an integer

- **WHEN** a reply has no `last exit code` line and no `last exit reason` of a jetsam idle exit, as for a job killed by a signal, whose reply prints no `last exit reason`, only `last terminating signal = Killed: 9` (recorded for `org.nixos.otelcol-process` on 2026-11-07), or a value that is not an integer
- **THEN** `launchd_job_last_exit_code` for that label is -1, and the mutant `missingExitCodeAsZero` fails the check

#### Scenario: A job was reclaimed while idle

- **WHEN** a reply has no `last exit code` line and `last exit reason = JETSAM_REASON_MEMORY_IDLE_EXIT`, as recorded for 98 of stibnite's system jobs on 2026-11-05
- **THEN** `launchd_job_last_exit_code` for that label is 0, and the mutant `idleExitAsFailure` fails the check

#### Scenario: A label is not loaded

- **WHEN** `launchctl` answers `Could not find service` for an allow-listed label
- **THEN** `launchd.prom` holds `launchd_job_state{launchd_state="unloaded"}` 1 for it and no exit-code or runs series

#### Scenario: An owner's label is written

- **WHEN** the parser reads the recorded reply for `org.nixos.omnigent-host-cameron`
- **THEN** `launchd.prom` names it `org.nixos.omnigent-host-owner-1` from `ownerAliases`, no line contains `cameron`, and the mutant `aliasDropped` fails the check

#### Scenario: A collector is killed by a signal at acceptance

- **WHEN** the operator sends `SIGKILL` to `org.nixos.otelcol-process` on stibnite and launchd restarts it
- **THEN** the stored `launchd_job_last_exit_code{launchd_label="org.nixos.otelcol-process"}` reads -1, and after `launchctl kickstart -k` it reads the exit code the operator records

### Requirement: No darwin collection job runs on a calendar schedule

The darwin fragment SHALL run each of its launchd jobs either kept alive or from `StartInterval`, and SHALL assert that none of its daemons sets `StartCalendarInterval`, so no collection or regulation schedule on a darwin host depends on the wall clock.

**Discharged by**: the darwin fragment's calendar assertion with its `extendModules` override; the operator's suspend of stibnite at acceptance, resting on world assumption `A61 — launchd misses a StartInterval firing during sleep and coalesces missed StartCalendarInterval firings into one run at wake`.

#### Scenario: A calendar is added

- **WHEN** an `extendModules` override of stibnite's configuration gives `otel-envelope` a `StartCalendarInterval`
- **THEN** stibnite's evaluation fails on the fragment's assertion

#### Scenario: The schedules are evaluated

- **WHEN** stibnite's configuration is evaluated with its `collect` true
- **THEN** `org.nixos.otel-host-probe` carries `StartInterval = 60`, `org.nixos.otel-envelope` `StartInterval = 300`, `org.nixos.otelcol`, `org.nixos.otelcol-process` and `org.nixos.prometheus-node-exporter` `KeepAlive = true`, and none carries `StartCalendarInterval`

#### Scenario: stibnite sleeps through its intervals

- **WHEN** the operator closes stibnite's lid for at least 30 minutes and opens it
- **THEN** launchd fires none of the missed intervals, `otel-host-probe` and `otel-envelope` each show a new run in `launchctl print`'s `runs` within one interval of wake, and the operator records both
