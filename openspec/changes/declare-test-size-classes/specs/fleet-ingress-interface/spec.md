## MODIFIED Requirements

### Requirement: Each agent exports by its role

On the ingress host the agent's pipelines SHALL end in `forward`, and on every other agent host, darwin included, in `otlp_http/ingress` for metrics and `otlp_http/ingress-logs` for logs, each to `https://[${flake.lib.hosts.magnetite.zt}]:4318` with its `otel-cert`, `ca_file` the `otel-ca` certificate, `min_version: "1.3"`, a `file_storage` queue of 400 MiB and 16 MiB with the `bytes` sizer, and retry without a time limit.

**Discharged by**: the agent role's queue assertion with its `extendModules` override; the darwin fragment's queue assertions with their `extendModules` overrides; `checks.x86_64-linux.otel-collector-darwin`'s exporter-address clause with its mutant `exporterAddressOther`; `vmTests.x86_64-linux.fleet-ingress`'s delivery case and `vmTests.x86_64-linux.fleet-ingress-outage`'s back-pressure case; the measured queue rate at cinnabar's first deploy; the exporter's sent points at stibnite's first activation, resting on world assumption `A65 — A store-built binary on stibnite reaches the ingress over ZeroTier`.

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

- **WHEN** `fleet-ingress-outage` fills the ingress's store queue, and later makes its limiter refuse, while the agent keeps collecting
- **THEN** the ingress answers HTTP 503, the agent's queue grows and then drains, and every point the agent scraped arrives in the store

#### Scenario: An agent queues before the ingress exists

- **WHEN** cinnabar is deployed before magnetite's receiver exists
- **THEN** cinnabar's metrics queue grows until magnetite's deploy and then drains to zero, and the operator records its growth per minute against the assumed rate

#### Scenario: stibnite's agent first exports

- **WHEN** stibnite's agent has run for two minutes after its watched activation
- **THEN** `otlp_http/ingress`'s `otelcol_exporter_sent_metric_points` at `127.0.0.1:8888` grows across two reads 60 s apart, and the operator records both reads

### Requirement: otel-envelope regulates each agent from its own collector

Every agent host SHALL run `otel-envelope` every 5 minutes, failing when its collector's telemetry at `127.0.0.1:8888` or a declared scrape target is unanswered on two consecutive runs, an exporter's queue reaches 90% of its capacity, or a loss counter increased, an absent loss counter reading as zero, as the scenarios state.

**Discharged by**: `checks.x86_64-linux.otel-envelope` with its mutants, its darwin cases and its mutants `c5WrongPid`, `c5ReadsRss` and `c5UnreadablePasses`; `checks.x86_64-linux.otel-collector-darwin`'s wrapper cases; `vmTests.x86_64-linux.fleet-ingress-outage`'s loss, back-pressure, crash-loop and long-running cases; the operator's stopped-collector and stopped-exporter controls on cinnabar and stopped-collector control on stibnite; resting on world assumption `A70 — macOS top prints a process's physical footprint as unversioned text to an unprivileged account`.

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

- **WHEN** `fleet-ingress-outage` kills the agent collector four times within 10 minutes and no point is lost
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

