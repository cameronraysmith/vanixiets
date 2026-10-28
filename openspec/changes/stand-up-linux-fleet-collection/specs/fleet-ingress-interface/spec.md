## ADDED Requirements

### Requirement: One host table declares the agent hosts and what each reports

`flake.lib.observabilityHosts` SHALL map each agent host to its `collect`, `alwaysOn`, `notifiedUnits` and `smartDevices`, and the collector's `agent` role machines and whether each collects, each host's `services.observability-notify.units`, the evaluator's always-on hosts, expected hosts and `SystemdUnitFailed` exclusion, and the SMART exporter's devices SHALL be read from it.

**Discharged by**: the agent role's per-host assertions with their `extendModules` overrides; `checks.x86_64-linux.fleet-alert`'s exclusion and absence legs.

#### Scenario: The table is evaluated

- **WHEN** `flake.lib.observabilityHosts` is evaluated
- **THEN** it names magnetite, cinnabar, pyrite, electrum, galena and scheelite, every host with `collect = true` once its first watched deploy has happened, only magnetite and cinnabar with `alwaysOn = true`, only pyrite with `smartDevices = [ "/dev/nvme0" ]`, and every host with `opentelemetry-collector` and `otel-envelope` among its `notifiedUnits`, cinnabar also with `fleet-deadman` and magnetite also with its store, dev-loop, evaluator and dataset units

#### Scenario: A host does not collect yet

- **WHEN** a host's `collect` is false
- **THEN** its configuration carries none of the agent role's units, collector settings or `zerotierone` change, and no alert rule expects it or counts it as always-on

#### Scenario: A notified unit is not a unit of its host

- **WHEN** a host's `notifiedUnits` names a unit for which the host defines no service with an `ExecStart`, or omits `opentelemetry-collector` or `otel-envelope`
- **THEN** that host's evaluation fails on the agent role's assertion, as an override of cinnabar's configuration that notifies `zfs-set-root-typo-quota` shows

### Requirement: The collection CA issues each agent host one certificate

The clan vars generator `otel-ca` SHALL be shared, with `ca.key` never deployed and `ca.crt` public, and `otel-cert` SHALL issue each agent host a P-256 certificate signed by it, valid 3650 days, with CN the machine name and `extendedKeyUsage=clientAuth`, or on the ingress host `serverAuth,clientAuth` with `IP:<flake.lib.hosts.magnetite.zt>` and `DNS:magnetite.zt` as SANs.

**Discharged by**: the plan's `openssl` reading of each issued certificate and its hash check after every vars step; `vmTests.x86_64-linux.fleet-ingress`'s refusal and delivery cases.

#### Scenario: The ingress host's certificate is read

- **WHEN** `openssl x509 -ext subjectAltName,extendedKeyUsage` reads `vars/per-machine/magnetite/otel-cert/cert.pem/value`
- **THEN** it shows `IP Address:fddb:4344:343b:14b9:399:930f:39db:40d2`, `DNS:magnetite.zt`, `TLS Web Server Authentication` and `TLS Web Client Authentication`

#### Scenario: A vars step runs

- **WHEN** a certificate is generated for a host, or a host is added as a reader of a shared var
- **THEN** the sha256 of `otel-ca`'s `ca.crt` and of the `ntfy-alerter` token are unchanged afterwards, and the step stops otherwise

#### Scenario: A certificate's SANs or usage change

- **WHEN** the SAN string or the key usage rendered for a host's certificate differs from the one recorded in its `validation`
- **THEN** clan regenerates that host's `otel-cert`, and its new files restart the collector through `restartUnits`

### Requirement: The ingress receiver accepts only certificate holders on magnetite's ZeroTier address

The ingress role SHALL run `otlp/mesh`, an OTLP/HTTP receiver at `[${flake.lib.hosts.magnetite.zt}]:4318` with `tls` from `otel-cert`, `client_ca_file` the `otel-ca` certificate and `min_version: "1.3"`, feeding `metrics/ingress` and `logs/ingress`, and SHALL open TCP 4318 on `zt+` only; it SHALL be the only collector endpoint off loopback.

**Discharged by**: R3.1's endpoint clause with its mutants; `vmTests.x86_64-linux.fleet-ingress`'s refusal case; the operator's refused request from stibnite at deploy.

#### Scenario: The endpoint is evaluated

- **WHEN** the evaluation-time collector check (R3.1) builds against magnetite's configuration
- **THEN** every receiver, exporter and scrape target endpoint is loopback except `otlp/mesh`'s, whose address equals the address in `vars/shared/zerotier-ip-magnetite-zerotier/ip/value`

#### Scenario: The endpoint is widened or moved

- **WHEN** a mutant sets `otlp/mesh`'s endpoint to `[::]:4318`, adds a second receiver on magnetite's ZeroTier address, or gives the check a ZeroTier address file naming another address
- **THEN** the evaluation-time collector check (R3.1) fails

#### Scenario: A client without a valid certificate connects

- **WHEN** `fleet-ingress` connects to the receiver without a client certificate, with a certificate from another CA, or offering at most TLS 1.2
- **THEN** each connection is refused during the handshake and no request reaches a pipeline

#### Scenario: A mesh member without a certificate connects at deploy

- **WHEN** after magnetite's deploy the operator sends an OTLP request from stibnite to `https://[fddb:4344:343b:14b9:399:930f:39db:40d2]:4318` without a client certificate
- **THEN** the handshake is refused, and the operator records the client's error

### Requirement: Each agent exports by its role

On the ingress host the agent's pipelines SHALL end in `forward`, and on every other agent host in `otlp_http/ingress` for metrics and `otlp_http/ingress-logs` for logs, each to `https://[${flake.lib.hosts.magnetite.zt}]:4318` with its `otel-cert`, `ca_file` the `otel-ca` certificate, `min_version: "1.3"`, a `file_storage` queue of 400 MiB and 16 MiB with the `bytes` sizer, and retry without a time limit.

**Discharged by**: the agent role's queue assertion with its `extendModules` override; `vmTests.x86_64-linux.fleet-ingress`'s delivery and back-pressure cases; the measured queue rate at cinnabar's first deploy.

#### Scenario: An agent's queue is evaluated

- **WHEN** a host without the ingress role is evaluated
- **THEN** the agent role asserts that both exporters queue in `file_storage` with the `bytes` sizer and unlimited retry, that the metrics queue holds at least 24 hours at `flake.lib.otelCollectorSchema.fleetBytesPerMinute`, and that the queues sum to less than 512 MiB, and an override of cinnabar's metrics queue to 64 MiB fails the evaluation

#### Scenario: The ingress refuses data under back-pressure

- **WHEN** `fleet-ingress` fills the ingress's store queue, and later makes its limiter refuse, while the agent keeps collecting
- **THEN** the ingress answers HTTP 503, the agent's queue grows and then drains, and every point the agent scraped arrives in the store

#### Scenario: An agent queues before the ingress exists

- **WHEN** cinnabar is deployed before magnetite's receiver exists
- **THEN** cinnabar's metrics queue grows until magnetite's deploy and then drains to zero, and the operator records its growth per minute against the assumed rate

### Requirement: otel-envelope regulates each agent from its own collector

Every agent host SHALL run `otel-envelope.service` every 5 minutes, failing when its collector's telemetry at `127.0.0.1:8888` or a declared scrape target is unanswered on two consecutive runs, an exporter's queue reaches 90% of its capacity, or a loss counter increased, an absent loss counter reading as zero, as the scenarios state.

**Discharged by**: `checks.x86_64-linux.otel-envelope` with its mutants; `vmTests.x86_64-linux.fleet-ingress`'s loss, back-pressure, crash-loop and long-running cases; the operator's stopped-collector and stopped-exporter controls on cinnabar.

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

### Requirement: otel-envelope on the ingress host regulates the fleet budget

The ingress host's `otel-envelope` SHALL, once an hour, query the store as `regulator` and fail when `fleet` exceeds 8,000 active series, a label exceeds 200 values outside its per-host bound, a host exceeds 30 process names, 40 unit names other than notifier instances or 30 job labels, or stores a notifier instance outside its notified units, `devloop` exceeds 100,000 rows a day, or a database's retention differs.

**Discharged by**: `vmTests.x86_64-linux.fleet-ingress`'s budget fixtures on the real store; the operator's drop-in control at deploy.

#### Scenario: A budget is exceeded in the container test

- **WHEN** `fleet-ingress` writes one synthetic metric with 300 values of one label, 31 process names for one host, a notifier instance for a unit outside the host's list, or alters a database's `ttl`
- **THEN** the envelope's next hourly run fails on that clause

#### Scenario: A queried table is missing

- **WHEN** a mutant of the envelope queries a table that does not exist
- **THEN** the run fails, because an empty result or a missing table is a failure of its clause

#### Scenario: magnetite's unit names are counted at deploy

- **WHEN** at magnetite's deploy a runtime drop-in sets `OTEL_ENVELOPE_MAX_UNITS=27` and the envelope runs
- **THEN** it fails on magnetite's ordinary unit names, a `FAILED` naming it reaches `fleet-alerts`, and removing the drop-in posts its `RESOLVED`

### Requirement: pyrite's NVMe health is read by a loopback exporter

On each host whose `smartDevices` is non-empty, the agent role SHALL run `prometheus-smartctl-exporter` on `127.0.0.1:9633` over those devices with `MemoryMax=64M`, granting `smartctl-exporter-access` read and write on each device before every start, and the collector SHALL scrape it with SC's smartctl keep-list.

**Discharged by**: R3.1's loopback clause; `otel-envelope`'s target clause; the operator's stored SMART read on pyrite after its deploy, resting on world assumption `A51 — pyrite's NVMe controller answers the SMART health log at the pinned smartmontools`.

#### Scenario: pyrite is deployed

- **WHEN** pyrite has been switched to the agent role without a reboot and one scrape interval has passed
- **THEN** `smartctl_device_critical_warning{host_name="pyrite"}` and `smartctl_device_percentage_used{host_name="pyrite"}` are stored, and the operator records both

### Requirement: This capability states its own trust boundary

This capability SHALL state what its properties guarantee and what they do not, and SHALL NOT be described, by itself or in any downstream report, as an end-to-end guarantee that a host's series reach the store.

**Discharged by**: the requirement's own statement in the scenarios below; no regulator applies.

#### Scenario: The properties above are read as a set

- **WHEN** the properties of this capability are read as a set
- **THEN** what they establish is that each agent host holds a certificate from `otel-ca`, that the ingress accepts only such holders on magnetite's ZeroTier address at TLS 1.3, that each agent queues and retries toward it, and that `otel-envelope` regulates each collector and the fleet budget, each as far as its check, container test or recorded observation reaches

#### Scenario: A guarantee about a certificate holder is sought

- **WHEN** someone asks whether a host can write series only under its own name
- **THEN** the answer is no: any holder of an `otel-ca` certificate is trusted to write, and a certificate's CN is not bound to the `host.name` its agent stamps

#### Scenario: A guarantee about a lost key is sought

- **WHEN** someone asks whether a lost or stolen agent key stops being accepted
- **THEN** the answer is no: certificates have no revocation, and a lost key stays valid until `otel-ca` is rotated, which the CA key, kept only in the encrypted repository vars, makes possible

#### Scenario: A guarantee about the network is sought

- **WHEN** someone asks whether ZeroTier authenticates the writer
- **THEN** the answer is no: ZeroTier is trusted to carry packets between members and nothing more, so the two Android members and stibnite reach the handshake and only mTLS refuses them

#### Scenario: An end-to-end guarantee is sought

- **WHEN** someone asks whether these properties guarantee that a given series reaches the store
- **THEN** the answer is no: each stage's configuration, the gating checks, the container test and `otel-envelope` behave as stated, and nothing here observes a series' whole path
