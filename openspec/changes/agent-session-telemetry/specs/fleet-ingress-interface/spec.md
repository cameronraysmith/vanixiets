## MODIFIED Requirements

### Requirement: Each agent exports by its role

On the ingress host the agent's pipelines SHALL end in `forward`, and on every other agent host, darwin included, in `otlp_http/ingress` for metrics and `otlp_http/ingress-logs` for logs, each to `https://[${flake.lib.hosts.magnetite.zt}]:4318` with its `otel-cert`, `ca_file` the `otel-ca` certificate, `min_version: "1.3"`, a `file_storage` queue of at least 400 MiB and of 16 MiB with the `bytes` sizer, and retry without a time limit.

**Discharged by**: the agent role's queue assertion with its `extendModules` override; the darwin fragment's queue assertions with their `extendModules` overrides; `checks.x86_64-linux.otel-collector-darwin`'s exporter-address clause with its mutant `exporterAddressOther`; `vmTests.x86_64-linux.fleet-ingress`'s delivery and back-pressure cases; the measured queue rate at cinnabar's first deploy; the exporter's sent points at stibnite's first activation, resting on world assumption `A65 — A store-built binary on stibnite reaches the ingress over ZeroTier`.

#### Scenario: A darwin agent's memory is bounded inside the process

- **WHEN** a darwin agent host's collector is configured
- **THEN** On a darwin agent host the 150 MiB `memory_limiter` with a 30 MiB spike allowance SHALL be the agent's only memory bound inside the process, because launchd bounds no memory.

#### Scenario: An agent's queue is evaluated

- **WHEN** a host without the ingress role is evaluated
- **THEN** the agent role asserts that every exporter queues in `file_storage` with the `bytes` sizer and unlimited retry, that the metrics queue holds at least 24 hours at `flake.lib.otelCollectorSchema.fleetBytesPerMinute` plus, where `agentTelemetry` is set, `agentMetricsBytesPerMinute`, that `otlp_http/ingress-agent` holds at least 8 hours at `agentEventBytesPerMinute` where it exists, and that the queues sum to less than 512 MiB, and an override of cinnabar's metrics queue to 64 MiB, or of pyrite's metrics queue to 400 MiB, fails the evaluation

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

## ADDED Requirements

### Requirement: Agent-telemetry hosts export agent events through a third exporter

On a host other than the ingress whose host-table row sets `agentTelemetry`, `otlp_http/ingress` SHALL queue 408 MiB, and `logs/agent-session` SHALL end in `otlp_http/ingress-agent`, a logs-only exporter with `otlp_http/ingress`'s endpoint, TLS and unlimited retry and a 64 MiB `file_storage` queue sized in bytes.

**Discharged by**: the agent role's queue assertion with `extendModules` overrides of pyrite; `checks.x86_64-linux.otel-collector-config`'s clause that `otlp_http/ingress-agent` is in no metrics pipeline; `vmTests.x86_64-linux.fleet-ingress`'s agent-telemetry container.

#### Scenario: pyrite's exporters are evaluated

- **WHEN** pyrite's configuration is evaluated
- **THEN** `otlp_http/ingress` queues 408 MiB, `otlp_http/ingress-logs` 16 MiB and `otlp_http/ingress-agent` 64 MiB, 488 MiB in all, and `otlp_http/ingress-agent` appears in no metrics pipeline

#### Scenario: Agent events cross the ingress in the VM test

- **WHEN** the VM test's agent-telemetry container posts an admitted session event to its `otlp/local`
- **THEN** the event passes through `otlp_http/ingress-agent`, `otlp/mesh` and `routing/logs` into `agent.session_event`, and the exporter's failed-send count stays zero

