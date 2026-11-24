## MODIFIED Requirements

### Requirement: Only in-scope harnesses and hosts emit

Only Claude Code and omp sessions on agent-telemetry hosts SHALL send agent session data; cloud sessions, the sandbox profile, the alternative-backend Claude Code wrappers and hosts that are not agent-telemetry hosts SHALL send none. A session on stibnite SHALL be recorded under the user name the fleet gives its person, whatever that person's account on stibnite is called.

**Discharged by**: `agent-session-telemetry-interface` requirements `The emitters exist only where the collector listens for them`, `An emitter stamps the person's fleet user name`, `Claude Code's settings carry the emitter gates` and `The loopback receiver feeds only the agent-session pipelines`; resting on world assumptions `A189 — The group has consented to its agent sessions being recorded and read by the group` and `A190 — Claude Code emits its telemetry as documented for its packaged version`.

#### Scenario: A host outside the scope is evaluated

- **WHEN** cinnabar's, rosegold's, argentum's or the sandbox profile's configuration is evaluated
- **THEN** no harness there carries the telemetry settings

#### Scenario: A wrapper session starts on pyrite

- **WHEN** a person starts `claude-glm` or `claude-cerebras` on pyrite
- **THEN** its settings carry none of the telemetry settings

#### Scenario: The operator's session on stibnite is read back

- **WHEN** after stibnite's deploy the operator, logged in as `crs58`, runs a Claude Code session and an omp session there, each with a unique word in its prompt
- **THEN** the telemetry store returns each within five minutes, naming `stibnite` and the user name `cameron`

### Requirement: An outage is held for a stated time

Each agent-telemetry host SHALL keep at least 24 hours of its agent series, 8 hours of its session events and 3 hours of its session spans through an outage of the ingress, and stibnite about a week of its average spans; the ingress SHALL keep at least 2 hours of every agent-telemetry host's series and events and 15 minutes of its spans through an outage of the telemetry store, at the assumed rates, without shortening the fleet's own 24 hours.

**Discharged by**: `agent-session-telemetry-interface` requirement `Agent queues are sized to their holds`; `fleet-ingress-interface` requirements `Each agent exports by its role` and `The agent-session collector exports each signal through its own exporter`; `telemetry-store-interface` requirement `The collector's queue persists across a telemetry store restart`; resting on world assumptions `A210 — stibnite runs agent sessions at the measured concurrency and volume` and `A212 — Each agent-telemetry host's agent output stays within the assumed rates`.

#### Scenario: A queue is shrunk below its hold

- **WHEN** a configuration sizes an agent-telemetry host's event queue below 8 hours, its agent series queue below 24 hours, or its own series queue below 24 hours
- **THEN** that host's evaluation fails

#### Scenario: A third agent-telemetry host joins

- **WHEN** stibnite's row is flagged while the ingress's queues still hold only 2 hours of two hosts' events and 15 minutes of two hosts' spans
- **THEN** the collection check fails until the ingress's queues hold them for three hosts

#### Scenario: The assumed rate is exceeded

- **WHEN** the rates read from the store after a week give a hold below its target
- **THEN** the reading is recorded as a finding and the queues are resized by a change

### Requirement: Agent sessions cannot cost a host's own series

However many agent sessions run on an agent-telemetry host and however large their content, the collector SHALL keep recording every series of that host's own signals. An overload SHALL cost only agent series, session events and session spans and, on a host whose service manager enforces no memory ceiling, that host's memory headroom; either loss SHALL reach a person through a failure notice.

**Discharged by**: `agent-session-telemetry-interface` requirements `The agent-session pipelines run in a collector unit of their own`, `On a darwin host the agent-session collector runs as a launchd daemon of its own`, `The loopback receiver feeds only the agent-session pipelines` and `Regulators cover the agent-session path`; the split load harness at 8, 12 and 16 senders; resting on world assumptions `A199 — omp's chat spans carry the whole conversation at the measured sizes`, `A200 — The collector holds ten to fourteen times a span request while decoding it`, `A209 — launchd enforces no memory ceiling on the fleet's daemons` and `A210 — stibnite runs agent sessions at the measured concurrency and volume`.

#### Scenario: Eight sessions post their largest contexts at once

- **WHEN** eight agent sessions on pyrite or magnetite each send a 13.8 MiB conversation every 5 seconds, or 64 spans at once
- **THEN** no series of the host's own signals is lost and the host's collector does not restart

#### Scenario: Sixteen sessions post at once with no ceiling

- **WHEN** the load harness posts from 12 and then 16 senders to pyrite's evaluated agent-session collector with its memory ceiling removed
- **THEN** no series of the host's own signals is lost, the host's collector does not restart, and the agent collector's largest resident size is recorded and sets stibnite's footprint limit

#### Scenario: The agent sessions' part of the collector is killed on a NixOS host

- **WHEN** the agent-session part of magnetite's or pyrite's collector is killed for lack of memory
- **THEN** it restarts within seconds, the host's own series continue without a gap, and a failure notice names it

#### Scenario: The agent sessions' part of the collector grows on stibnite

- **WHEN** the agent-session collector on stibnite grows past its footprint limit
- **THEN** a failure notice names it on its next five-minute run, and stibnite's own series continue without a gap

## ADDED Requirements

### Requirement: Langfuse is not sent omp's helper requests

omp's helper requests, its two startup requests (kinds `skill_description` and `mcp_namespace_hint`) and its background jobs' caption and widget requests (kinds `job_caption` and `job_widget`), SHALL reach the telemetry store with their kind recorded, and SHALL NOT be sent to the Langfuse project from any host; every other span, other oneshot kinds such as compaction and handoff included, SHALL be sent as before.

**Discharged by**: `agent-session-telemetry-interface` requirement `Langfuse's branch drops omp's helper requests`; resting on world assumptions `A211 — omp marks each oneshot request's span with its kind, and a startup request is a leaf root` and `A204 — The telemetry store alters a table idempotently as read at 1.2.1`.

#### Scenario: A session starts and omp makes its startup requests

- **WHEN** an omp session starts on pyrite after its deploy and omp makes its skill-summary and MCP namespace-hint requests
- **THEN** the telemetry store holds both spans with kinds `skill_description` and `mcp_namespace_hint`, and the Langfuse project receives no trace for either

#### Scenario: omp captions a background job

- **WHEN** an omp session starts a background job and omp asks a small model for the job's caption or widget spec
- **THEN** the telemetry store holds that span with kind `job_caption` or `job_widget`, and the Langfuse project receives no observation for it

#### Scenario: omp summarises a long conversation

- **WHEN** an omp session compacts its conversation, a request of another kind
- **THEN** that request's span reaches both the telemetry store and the Langfuse project

### Requirement: A Langfuse block reaches a person without paging

When the Langfuse project refuses more of a host's spans than it accepts over a day, as it does when its quota blocks ingestion, a person SHALL receive a low-priority alert naming the host, and no page.

**Discharged by**: `fleet-alerting-interface` requirement `Langfuse's send failures are alerted at low priority`; `agent-session-telemetry-interface` requirement `The host collector keeps Langfuse's send counters`; resting on world assumption `A205 — Langfuse Cloud ingests OTLP traces as read on 2026-11-22`.

#### Scenario: Langfuse's quota blocks ingestion

- **WHEN** the Langfuse project answers every span request with a refusal for a day
- **THEN** one alert at low priority names each sending host, and no envelope run fails

#### Scenario: A sleeping Mac sends nothing

- **WHEN** stibnite sleeps through a day
- **THEN** no Langfuse alert names stibnite

### Requirement: Recording a darwin host's agent sessions leaves its own series unchanged

On a darwin host whose agent sessions are recorded, every series of that host's own signals, its processes' memory included, SHALL keep reaching the telemetry store as before, and nothing a harness sends to its configured endpoint SHALL enter the fleet's own database.

**Discharged by**: `agent-session-telemetry-interface` requirement `On a darwin host the agent-session collector runs as a launchd daemon of its own`; `fleet-ingress-interface` requirement `Each agent exports by its role`; resting on world assumptions `A190 — Claude Code emits its telemetry as documented for its packaged version` and `A191 — omp reads its own environment file and puts content only on spans`, which send each harness's data to its configured endpoint.

#### Scenario: stibnite's process series after the deploy

- **WHEN** stibnite has switched and runs agent sessions
- **THEN** its process memory series reach the telemetry store at the same count per minute as in the hour before the switch

#### Scenario: A harness exports on stibnite

- **WHEN** a Claude Code or omp session on stibnite exports its metrics
- **THEN** they are stored only in the `agent` database, and the fleet's own database gains no series from them
