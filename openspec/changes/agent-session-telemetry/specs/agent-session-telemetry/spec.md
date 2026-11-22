## ADDED Requirements

### Requirement: Agent sessions on agent-telemetry hosts are recorded

Every agent session a person runs on an agent-telemetry host, and every agent session an Omnigent worker runs there for its owner, in either harness, SHALL reach the telemetry store's `agent` database as session events and series, each naming its host and its user name, only for people whose consent is recorded.

**Discharged by**: `agent-session-telemetry-interface` requirements `Claude Code's settings carry the emitter gates`, `omp's environment file carries the emitter gates`, `The emitters exist only where the collector listens for them`, `The loopback receiver feeds only the agent-session pipelines` and `Agent events are routed to their table`; resting on world assumptions `A189 — The group has consented to its agent sessions being recorded and read by the group`, `A190 — Claude Code emits its telemetry as documented for its packaged version`, `A191 — omp reads its own environment file and puts content only on spans` and `A195 — omnigent runs a worker's harness with the worker's home`; the VM test's admitted cases and the operator's reads after each deploy discharge it.

#### Scenario: A person's session on pyrite is read back

- **WHEN** a person runs a Claude Code session on pyrite after pyrite's deploy and submits a prompt
- **THEN** a session event for that prompt, naming `pyrite` and the person's user name, is returned by the telemetry store within five minutes

#### Scenario: An Omnigent worker's session is read back

- **WHEN** Janette's Omnigent worker on magnetite runs a session after magnetite's deploy
- **THEN** its session events name `magnetite` and `janettesmith`, not the worker's account name

#### Scenario: A person's consent is withdrawn

- **WHEN** a person's consent is withdrawn
- **THEN** that person's sessions are no longer discharged by this requirement until a change removes them from collection

### Requirement: Session content is readable by every store reader and only by them

The fleet SHALL keep session content where every reader of the telemetry store may read it and no one else may, and no Omnigent worker SHALL hold a store credential.

**Discharged by**: `telemetry-store` requirement `Only the collector writes and only named readers read`; `agent-session-telemetry-interface` requirement `The emitters exist only where the collector listens for them` (workers receive an endpoint, never a credential); resting on world assumptions `A188 — The telemetry store authorizes reads by a global mode, not by database` and `A189 — The group has consented to its agent sessions being recorded and read by the group`.

#### Scenario: A dashboard reader queries session events

- **WHEN** an admitted person or a regulator queries the `agent` database with its store account
- **THEN** the session content is returned, as it is for every database, because the telemetry store authorizes reads by mode alone

#### Scenario: A worker looks for a store credential

- **WHEN** an Omnigent worker's home configuration is evaluated on an agent-telemetry host
- **THEN** it holds the loopback endpoint and no store credential

### Requirement: Only allow-listed session content leaves a host

No part of an agent session SHALL leave its host unless it is on the fleet's allow-list: listed harnesses, listed session events and their listed fields; prompts, responses and tool details are listed, tool output and raw API bodies are not, and anything unlisted SHALL be dropped on the host.

**Discharged by**: `agent-session-telemetry-interface` requirements `The agent-session stages admit only allow-listed events and keys`, `The span path keeps only the newest prompt and listed span keys`, `One allow-list decides what the collector keeps and the store stores` and `The VM test proves the allow-list with a canary`; resting on world assumptions `A190 — Claude Code emits its telemetry as documented for its packaged version`, `A191 — omp reads its own environment file and puts content only on spans`, `A193 — The telemetry store's pipelines filter, close and index as documented` and `A198 — The telemetry store writes traces into pre-created v1 tables and refuses unknown columns`.

#### Scenario: A harness is reconfigured to send tool output

- **WHEN** a person edits their Claude Code settings to send tool output, or a session sends raw API bodies, an unlisted event or an unlisted field
- **THEN** none of it reaches the telemetry store, which the VM test's canary shows for each kind

#### Scenario: A harness release adds a field

- **WHEN** a harness release adds a field to an event on the allow-list
- **THEN** the field is dropped on the host until the allow-list names it

#### Scenario: An omp session sends its whole history

- **WHEN** an omp session sends, with each model call, the whole conversation so far, earlier tool output included
- **THEN** only the newest prompt of each turn, the response and the tool details reach the telemetry store; the earlier conversation and the tool output are dropped on the host

### Requirement: No account identifier leaves a host

No account identifier SHALL leave a host in an agent session's data, and the only person identifier stored SHALL be the session's user name.

**Discharged by**: `agent-session-telemetry-interface` requirements `The agent-session stages admit only allow-listed events and keys` and `The VM test proves the allow-list with a canary`; resting on world assumption `A190 — Claude Code emits its telemetry as documented for its packaged version`.

#### Scenario: A session sends its account's email address

- **WHEN** Claude Code sends the account's email address, account ids and organisation id with every session event and series, as it does when signed in
- **THEN** none of them is stored, and the session event carries the user name only

### Requirement: Session events are kept for 30 days

The telemetry store SHALL return an agent session's events and series for 30 days and SHALL NOT keep them past that.

**Discharged by**: `telemetry-store` requirement `A database keeps its series for its retention and no longer`; `agent-session-telemetry-interface` requirement `The session-event table is created by the schema job with its pipeline`; the hourly envelope regulator's table-retention clause.

#### Scenario: The retention is read back

- **WHEN** the VM test, and later the operator after magnetite's deploy, read the `agent` database's retention and the session-event table's own options
- **THEN** the database's retention is 30 days and the table has no retention of its own

### Requirement: Session content can be searched by word

A reader SHALL be able to find session events by a word their prompt or response contains, without reading every event.

**Discharged by**: `agent-session-telemetry-interface` requirement `The session-event table is created by the schema job with its pipeline`; resting on world assumption `A193 — The telemetry store's pipelines filter, close and index as documented`; the VM test's full-text case.

#### Scenario: A prompt is found by a word it contains

- **WHEN** the VM test stores a prompt containing a unique word and searches for that word
- **THEN** the search returns that session event, and the table's definition shows a full-text index on the prompt and the response

### Requirement: Only in-scope harnesses and hosts emit

Only Claude Code and omp sessions on agent-telemetry hosts SHALL send agent session data; cloud sessions, the sandbox profile, the alternative-backend Claude Code wrappers and hosts that are not agent-telemetry hosts SHALL send none, and no harness SHALL send traces.

**Discharged by**: `agent-session-telemetry-interface` requirements `The emitters exist only where the collector listens for them`, `Claude Code's settings carry the emitter gates` and `The loopback receiver feeds only the agent-session pipelines`.

#### Scenario: A host outside the scope is evaluated

- **WHEN** stibnite's, cinnabar's or the sandbox profile's configuration is evaluated
- **THEN** no harness there carries the telemetry settings

#### Scenario: A wrapper session starts on pyrite

- **WHEN** a person starts `claude-glm` or `claude-cerebras` on pyrite
- **THEN** its settings carry none of the telemetry settings

### Requirement: An outage is held for a stated time

Each agent-telemetry host SHALL keep at least 24 hours of its agent series, 8 hours of its session events and 3 hours of omp's session content through an outage of the ingress, and the ingress SHALL keep at least 2 hours of every agent-telemetry host's series and session events and 40 minutes of its omp content through an outage of the telemetry store, at the assumed rates, without shortening the fleet's own 24 hours.

**Discharged by**: `agent-session-telemetry-interface` requirement `Agent queues are sized to their holds`; `fleet-ingress-interface` requirement `Each agent exports by its role`; `telemetry-store-interface` requirement `The collector's queue persists across a telemetry store restart`; the measured rates after deploy.

#### Scenario: A queue is shrunk below its hold

- **WHEN** a configuration sizes an agent-telemetry host's event queue below 8 hours, or its metrics queue below 24 hours of fleet and agent series together
- **THEN** that host's evaluation fails

#### Scenario: The assumed rate is exceeded

- **WHEN** the rates measured after deploy give a hold below its target
- **THEN** the measurement is recorded as a finding and the queues are resized by a change

### Requirement: Agent series stay under their cap

The `agent` database SHALL hold at most 2,000 active series, and a breach SHALL reach a person through a failure notice within two hours.

**Discharged by**: `agent-session-telemetry-interface` requirement `Regulators cover the agent-session path`; `Metrics count across sessions without one series per session`.

#### Scenario: The cap is breached

- **WHEN** the `agent` database holds more than 2,000 active series
- **THEN** the ingress host's hourly envelope regulator fails and a failure notice reaches a person

### Requirement: Metrics count across sessions without one series per session

Agent series SHALL carry no session or prompt identifier, so that a session adds no series of its own, and their totals SHALL be read by summing the per-minute counts across sessions; two sessions' counts that coincide in the same millisecond may be counted once, an accepted undercount.

**Discharged by**: `agent-session-telemetry-interface` requirement `The agent-session stages admit only allow-listed events and keys`; resting on world assumptions `A190 — Claude Code emits its telemetry as documented for its packaged version` and `A192 — The telemetry store keeps one metric point per series and millisecond`.

#### Scenario: Two sessions run at once

- **WHEN** two sessions on one host with the same model report token counts in the same minute
- **THEN** both counts are stored in one series without a session label, unless their timestamps coincide to the millisecond

### Requirement: A canary proves the allow-list before a host deploys

No change to what agent sessions send, or to the collection path that carries it, SHALL reach a host before a test against the deployed telemetry store's release shows a canary of each forbidden kind dropped and an admitted prompt stored and found.

**Discharged by**: `agent-session-telemetry-interface` requirement `The VM test proves the allow-list with a canary`.

#### Scenario: The canary is run

- **WHEN** the VM test sends raw API bodies, an unlisted field, an unlisted event, account identifiers, a message body, a foreign harness and an unlisted metric, each marked with a unique word
- **THEN** no marked word or forbidden field appears anywhere in the telemetry store, and the admitted prompt is found by its word
