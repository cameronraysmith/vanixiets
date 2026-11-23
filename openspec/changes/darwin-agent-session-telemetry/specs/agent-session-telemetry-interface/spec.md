## MODIFIED Requirements

### Requirement: The emitters exist only where the collector listens for them

`flake.lib.observabilityHosts` SHALL carry `agentTelemetry`, `true` only for magnetite, pyrite and stibnite; the collector SHALL add `otlp/local` only there. The agent-telemetry home module SHALL act only when its `agentTelemetry.enable` is true, which defaults to the host's flag through `osConfig` and which the darwin worker builder sets from the host's row, never through a worker unit's environment.

**Discharged by**: evaluation of every NixOS and darwin machine check; `checks.x86_64-linux.agent-telemetry-emitters` over every flagged and unflagged home, stibnite's omnigent worker home included; the omnigent fleet obligation that `worker.environment == { }`; an `extendModules` override of cinnabar with the home module and no flag.

#### Scenario: A host without the flag is evaluated

- **WHEN** cinnabar, rosegold, argentum or claude-sandbox's home is evaluated
- **THEN** no `otlp/local` receiver exists and no home carries the module's settings

#### Scenario: stibnite's worker home is evaluated

- **WHEN** the standalone home of `omnigent-cameron` on stibnite, whose `osConfig` is null, is evaluated
- **THEN** it carries the module's settings with `user.name=cameron`, and its launchd daemon's environment holds no `OTEL_*` variable

#### Scenario: The worker units are evaluated

- **WHEN** magnetite's omnigent worker units are evaluated
- **THEN** their environment is empty and no unit holds a store credential or an `OTEL_*` variable

### Requirement: Agent queues are sized to their holds

Each agent-session collector SHALL queue `otlp_http/ingress-metrics` 52 MiB (24 h), `otlp_http/ingress-agent` 64 MiB (8 h) and `otlp_http/ingress-traces` its row's `agentSpanQueueMiB`, 44 by default and 256 on stibnite (at least 3 h), below 512 MiB in sum. magnetite's `otlp_http/agent`, `otlp_http/agent_session_event` and `otlp_http/agent_span` SHALL hold 2 h, 2 h and 15 min (refusing when full) of every agent-telemetry host's rates, all its queues below 512 MiB.

**Discharged by**: the agent role's assertion over the NixOS unit and the darwin fragment's over the daemon, each with an `extendModules` override seen failing; `checks.x86_64-linux.otel-collector-config`'s queue clauses with mutants `agentSpanQueueShort`, `agentSpanQueueBlocks` and `agentQueueShortThreeHosts`; resting on world assumptions `A203 — The collector's OTTL and queues behave as read at 0.155.0` for the refusal and `A212 — Each agent-telemetry host's agent output stays within the assumed rates`.

#### Scenario: pyrite's event queue is shrunk

- **WHEN** an override sizes pyrite's agent-session `otlp_http/ingress-agent` at 32 MiB
- **THEN** pyrite's evaluation fails on the agent role's assertion over the unit

#### Scenario: stibnite is flagged before the ingress grows

- **WHEN** the check evaluates three agent-telemetry hosts with magnetite's `otlp_http/agent_session_event` at 32 MiB or its `otlp_http/agent_span` at 8 MiB
- **THEN** the queue clause fails, since three hosts need 47,880,000 B of events and 10,800,000 B of spans

#### Scenario: stibnite's span queue is read

- **WHEN** stibnite's agent-session settings are evaluated
- **THEN** `otlp_http/ingress-traces` queues 268,435,456 B and the daemon's four queues sum to 404 MiB

### Requirement: Langfuse's keys are a shared clan var loaded as credentials

The Langfuse project's keys SHALL be the shared clan var `langfuse`, entered at hidden persisted prompts and deployed only to hosts whose row sets `langfuse`, each a recipient. On NixOS `otel-agent-session.service` SHALL load them as credentials; on darwin they SHALL be `0400` files of `_otelagent`, which no other collector's account can read. No key SHALL appear in configuration, a command line or the repository in clear.

**Discharged by**: the agent role's generator and `LoadCredential` on NixOS and the darwin module's file owners and modes, asserted by the fragment; `flake.lib.sharedVarsObligations` on the machine checks; `checks.x86_64-linux.otel-collector-config`'s Langfuse exporter clause with mutant `langfuseKeyInline`; `checks.x86_64-linux.gitleaks`; `stat` of both files on stibnite after its switch.

#### Scenario: A host without the flag is evaluated

- **WHEN** cinnabar, electrum, rosegold or argentum is evaluated
- **THEN** it declares no `langfuse` generator and reads no Langfuse key

#### Scenario: stibnite is flagged without being a recipient

- **WHEN** stibnite's row sets `langfuse` and `vars/shared/langfuse/*/machines/stibnite` is absent
- **THEN** stibnite's evaluation fails on `sharedVarsObligations`

#### Scenario: The fleet collector's account reads the key on stibnite

- **WHEN** an override makes the Langfuse files on stibnite readable by `_otelcol`
- **THEN** stibnite's evaluation fails on the fragment's assertion

### Requirement: This capability states its own trust boundary

This capability SHALL state what its properties guarantee and what they do not, and SHALL NOT be described as an end-to-end guarantee about who reads session content, what a session sends, or how much memory a Mac gives the collector.

**Discharged by**: the requirement's own statement in the scenarios below; no regulator applies.

#### Scenario: The properties above are read as a set

- **WHEN** the properties of this capability are read as a set
- **THEN** they establish that the emitters are configured as stated where the flag is on, that the collector admits only the allow-list on the loopback path and stamps the host, that stibnite's pipelines equal pyrite's apart from host facts, that the store closes and indexes the table as stated, and that queues and regulators are bounded, each as far as its own check, assertion or test reaches

#### Scenario: A guarantee about who sent a session event is sought

- **WHEN** someone asks whether a stored user name proves which person's session sent an event
- **THEN** the answer is no: any local process can post to the loopback receiver under any user name (world assumption `A194 — Any local process can send to a loopback receiver and name any person`)

#### Scenario: A guarantee about what is inside an admitted field is sought

- **WHEN** someone asks whether a stored prompt, response, tool detail or tool output is free of secrets
- **THEN** the answer is no: the allow-list chooses fields, not their contents, and a person or an agent can paste a secret into a prompt or a command; the masking replaces only token-shaped credentials of the listed issuers

#### Scenario: A guarantee about readers is sought

- **WHEN** someone asks whether these properties limit who reads session content
- **THEN** the answer is no: every holder of a read store account reads it (world assumption `A188 — The telemetry store authorizes reads by a global mode, not by database`), and nothing here governs what a reader does with it

#### Scenario: A guarantee that the emitter settings hold is sought

- **WHEN** someone asks whether omp's content level, traces endpoint or buffer bound are enforced
- **THEN** the answer is no: a project `.env` in a session's working directory overrides `~/.omp/agent/.env` (world assumption `A197 — A project's environment file overrides omp's own`); the collector's allow-lists still bound what leaves the host

#### Scenario: A memory bound on a Mac is sought

- **WHEN** someone asks whether the agent-session collector on stibnite is held to 512 MiB
- **THEN** the answer is no: launchd enforces no memory ceiling on it (world assumption `A209 — launchd enforces no memory ceiling on the fleet's daemons`); `GOMEMLIMIT` and the limiter are soft, and the footprint clause only reports growth every five minutes while the Mac is awake

#### Scenario: A guarantee about which Mac harnesses export is sought

- **WHEN** someone asks which programs on stibnite export sessions
- **THEN** the answer is: those that read the user settings or omp's environment file, which the live check after the deploy lists; the desktop and IDE harnesses run builds this repository does not pin, and only the collector's allow-lists bound what they send

## ADDED Requirements

### Requirement: The agent-session settings are one function of host facts

The agent-session collector's settings SHALL be the value of `flake.lib.agentSessionCollector` for the host's name, ingress role, CA, certificate and key paths, queue directory, span queue size and Langfuse key paths. stibnite's settings SHALL equal pyrite's once host names, those paths and queue sizes are normalised.

**Discharged by**: the extraction's identity record (sha256 of magnetite's and pyrite's evaluated collector settings, agent-session settings and both units' `serviceConfig`, equal before and after); `checks.x86_64-linux.otel-collector-darwin`'s clause `agentSessionEqualsPyrite` with mutant `stibniteProcessorDropped`; Linux `otelcol-contrib validate` over stibnite's rendered file.

#### Scenario: The extraction is evaluated

- **WHEN** the extraction commit is evaluated beside its parent
- **THEN** the six hashes are equal and no host's toplevel `drvPath` differs

#### Scenario: stibnite's copy drifts

- **WHEN** a mutant removes one processor from stibnite's agent-session settings
- **THEN** `agentSessionEqualsPyrite` fails

### Requirement: On a darwin host the agent-session collector runs as a launchd daemon of its own

Where a darwin row sets `agentTelemetry`, `org.nixos.otel-agent-session` SHALL run the settings as `_otelagent`, kept alive, with `GOMEMLIMIT` 409 MiB above the 384 MiB limiter, `otlp/local` on `127.0.0.1:4318`, telemetry on `127.0.0.1:8890` and its own queue directory; the fleet collector's receiver and `otelcol-process`'s exporter SHALL use `127.0.0.1:4319`. `org.nixos.otel-agent-session-envelope` SHALL judge it every 300 s, C5 included.

**Discharged by**: the darwin fragment's assertions, forced on Linux by evaluating `darwinConfigurations.stibnite.config.assertions`, each seen failing under an `extendModules` mutant; `checks.x86_64-linux.otel-collector-darwin`'s port clauses; `checks.x86_64-linux.otel-envelope`'s darwin agent variant with C5 cases at the limit ±1 MiB; `launchctl print` and `lsof` on stibnite after its switch; resting on world assumptions `A209 — launchd enforces no memory ceiling on the fleet's daemons` and `A61 — launchd misses a StartInterval firing during sleep and coalesces missed StartCalendarInterval firings into one run at wake`.

#### Scenario: The fleet collector keeps 4318

- **WHEN** a mutant leaves the fleet collector's `otlp` receiver on `127.0.0.1:4318`
- **THEN** `checks.x86_64-linux.otel-collector-darwin` fails

#### Scenario: The daemon runs as the fleet collector's account

- **WHEN** an override sets the daemon's `UserName` to `_otelcol`
- **THEN** stibnite's evaluation fails on the fragment's assertion

#### Scenario: The daemon grows past its footprint limit

- **WHEN** the envelope's stubbed `top` reports the daemon's footprint 1 MiB above its limit
- **THEN** C5 fails and the wrapper posts `FAILED otel-agent-session-envelope on stibnite`; 1 MiB below, it passes

### Requirement: Langfuse's branch drops omp's startup requests

`agentSession.spans.keys` SHALL keep `omp.gen_ai.oneshot.kind`, the schema job SHALL add its `agent_span` column, `filter/langfuse` SHALL drop a span whose kind is on `agentSession.langfuse.droppedOneshotKinds`, which is `[ "skill_description" "mcp_namespace_hint" ]`, and `transform/langfuse` SHALL delete the key from every span it sends.

**Discharged by**: `checks.x86_64-linux.otel-collector-config`'s span-key and Langfuse clauses; `vmTests.x86_64-linux.fleet-ingress`'s `agentSpans` and `langfuse` cases with uncommitted mutants `langfuseOneshotKept` and `oneshotKeySent`; resting on world assumptions `A211 — omp marks each oneshot request's span with its kind, and a startup request is a leaf root`, `A198 — The telemetry store writes traces into pre-created v1 tables and refuses unknown columns` and `A204 — The telemetry store alters a table idempotently as read at 1.2.1`.

#### Scenario: The VM test posts the startup requests

- **WHEN** `agentSpans` posts omp root `chat` spans with kinds `skill_description`, `mcp_namespace_hint` and `compaction_summary`
- **THEN** the store holds all three with their kinds, the Langfuse sink receives only the third, and no span the sink receives carries the key

#### Scenario: The filter is removed

- **WHEN** the uncommitted mutant `langfuseOneshotKept` removes the kind condition
- **THEN** the `langfuse` case fails because the sink received the startup spans

### Requirement: The host collector keeps Langfuse's send counters

On hosts whose row sets `langfuse`, the host collector SHALL scrape the agent-session collector at `127.0.0.1:8890` as job `otelcol-agent-session`, keeping only `otelcol_exporter_sent_spans` and `otelcol_exporter_send_failed_spans` with `exporter="otlp_http/langfuse"` and dropping `service_instance_id`; no other host's scrape SHALL change.

**Discharged by**: `checks.x86_64-linux.otel-collector-config`'s scrape clause and `checks.x86_64-linux.otel-collector-darwin`'s equivalent with a mutant that widens the keep-list; the identity record, which names this job as the only change to pyrite's host collector after the extraction; `obs-query` reading both series from each Langfuse host after its deploy.

#### Scenario: A non-Langfuse host is evaluated

- **WHEN** cinnabar or rosegold is evaluated
- **THEN** its host collector has no `otelcol-agent-session` job

#### Scenario: The keep-list is widened

- **WHEN** a mutant keeps every `otelcol_exporter_*` series from 8890
- **THEN** the scrape clause fails

### Requirement: An emitter stamps the person's fleet user name

`agentTelemetry.person` SHALL default to the key of `flake.userAliases` whose value is the home's user name, else to that user name, and a darwin worker home SHALL receive its worker's owner; so stibnite's `crs58` home and `omnigent-cameron` both stamp `user.name=cameron`, and every NixOS home stamps what it stamps today.

**Discharged by**: `checks.x86_64-linux.agent-telemetry-emitters`, which writes each evaluated home's expected `user.name` out itself, with a mutant dropping the alias lookup that fails naming `crs58`; the activated `~/.claude/settings.json` and `~/.omp/agent/.env` of both stibnite homes read after the switch; resting on world assumptions `A190 — Claude Code emits its telemetry as documented for its packaged version` and `A191 — omp reads its own environment file and puts content only on spans`, under which each harness sends the resource attribute it is given.

#### Scenario: stibnite's homes are evaluated

- **WHEN** stibnite's `crs58` home and the standalone `omnigent-cameron` home are evaluated
- **THEN** both carry `OTEL_RESOURCE_ATTRIBUTES=user.name=cameron` in the Claude Code settings and in omp's file

#### Scenario: A NixOS home is evaluated

- **WHEN** cameron's and `omnigent-janettesmith`'s homes on pyrite and magnetite are evaluated
- **THEN** they stamp `cameron` and `janettesmith`, as before
