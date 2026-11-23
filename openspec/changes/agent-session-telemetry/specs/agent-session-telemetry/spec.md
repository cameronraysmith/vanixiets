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

### Requirement: Session content is readable by every store reader and, where flagged, by the Langfuse project

The fleet SHALL keep session content where every reader of the telemetry store may read it, and SHALL send it nowhere else except, from hosts whose row sets `langfuse`, the same spans to the Langfuse Cloud project whose keys the fleet holds; no Omnigent worker SHALL hold a store or Langfuse credential.

**Discharged by**: `telemetry-store` requirement `Only the collector writes and only named readers read`; `agent-session-telemetry-interface` requirements `The emitters exist only where the collector listens for them` (workers receive an endpoint, never a credential), `Langfuse gets the store's spans after every stage, under its own names` and `Langfuse's keys are a shared clan var loaded as credentials`; resting on world assumptions `A188 — The telemetry store authorizes reads by a global mode, not by database`, `A189 — The group has consented to its agent sessions being recorded and read by the group` and `A206 — The group consents to its agent sessions going to Langfuse Cloud`.

#### Scenario: A dashboard reader queries session events

- **WHEN** an admitted person or a regulator queries the `agent` database with its store account
- **THEN** the session content is returned, as it is for every database, because the telemetry store authorizes reads by mode alone

#### Scenario: A worker looks for a store credential

- **WHEN** an Omnigent worker's home configuration is evaluated on an agent-telemetry host
- **THEN** it holds the loopback endpoint and no store credential

#### Scenario: A Langfuse project member opens a session

- **WHEN** a member of the Langfuse project opens a trace sent from magnetite or pyrite
- **THEN** they see the same prompts, outputs and tool output the store holds, masked and cut alike, grouped by session and person; hosts without the flag send nothing there

### Requirement: Only allow-listed session content leaves a host

No part of an agent session SHALL leave its host unless it is on the fleet's allow-list: listed harnesses, listed session events and their listed fields. Prompts, responses, tool details and tool output are listed, each value at most 64 KiB; raw API bodies and a harness's whole conversation history are not. Anything unlisted SHALL be dropped on the host.

**Discharged by**: `agent-session-telemetry-interface` requirements `The agent-session stages admit only allow-listed events and keys`, `Every kept span and event value is at most 64 KiB`, `The span path keeps only the last user message and listed span keys`, `Only a top-level run's first request gets a last user message`, `One allow-list decides what the collector keeps and the store stores` and `The VM test proves the allow-list with a canary`; resting on world assumptions `A190 — Claude Code emits its telemetry as documented for its packaged version`, `A191 — omp reads its own environment file and puts content only on spans`, `A193 — The telemetry store's pipelines filter, close and index as documented`, `A198 — The telemetry store writes traces into pre-created v1 tables and refuses unknown columns`, `A201 — omp marks the spans whose newest user message can be other than a person's` and `A202 — Claude Code's traces carry its tool output in an event and read the span buffer bound from the environment`.

#### Scenario: A harness is reconfigured to send raw API bodies

- **WHEN** a person edits their Claude Code settings to send raw API bodies, or a session sends an unlisted event or an unlisted field
- **THEN** none of it reaches the telemetry store, which the VM test's canary shows for each kind

#### Scenario: A harness release adds a field

- **WHEN** a harness release adds a field to an event on the allow-list
- **THEN** the field is dropped on the host until the allow-list names it

#### Scenario: An omp session sends its whole history

- **WHEN** an omp session sends, with each model call, the whole conversation so far, earlier tool output included
- **THEN** only the newest user message of each run's first request, the response, the tool details and each tool's own output reach the telemetry store; the earlier conversation is dropped on the host

### Requirement: Token-shaped secrets in stored content are masked

Secrets of a listed token shape (private-key blocks and the tokens of the issuers the collector lists) in a session's prompts, responses, tool details, tool output or error text SHALL be replaced before they leave the host. This SHALL NOT be relied on for any other secret, and SHALL NOT replace the allow-list.

**Discharged by**: `agent-session-telemetry-interface` requirement `Credential shapes are masked in what the agent-session collector keeps`.

#### Scenario: A tool prints a token

- **WHEN** a session's command prints a GitHub token, or a file it reads holds a private key
- **THEN** the stored tool output holds `****` in its place and the rest of the output as printed

### Requirement: No account identifier leaves a host

No account identifier SHALL leave a host in an agent session's data.
Outside the content columns, which hold prompts, responses, tool details, tool output, error text and span status messages, the only person identifier stored SHALL be the session's user name.
Text a person types or a tool prints is session content and SHALL be stored as written, within the 64 KiB cut and the credential masking, so it may name a person or hold an address.

**Discharged by**: `agent-session-telemetry-interface` requirements `The agent-session stages admit only allow-listed events and keys`, `Every kept span and event value is at most 64 KiB`, `Credential shapes are masked in what the agent-session collector keeps` and `The VM test proves the allow-list with a canary`; resting on world assumption `A190 — Claude Code emits its telemetry as documented for its packaged version`; the operator's day-later scan (task 8.1).

#### Scenario: A session sends its account's email address

- **WHEN** Claude Code sends the account's email address, account ids and organisation id with every session event and series, as it does when signed in
- **THEN** none of them is in any column of any table of `agent`, content columns included, and the session event carries the user name only

#### Scenario: A person pastes an address, or a tool prints one

- **WHEN** a person pastes a jj log holding their commit email address into a prompt, or a `git log` a session runs prints it
- **THEN** the address is stored as written in a content column (`last_user_message` or `prompt`, or `gen_ai.tool.call.result`), and from a host whose row sets `langfuse` reaches Langfuse on the same span, in `langfuse.observation.input` or `.output` or the span attribute that holds it; no account identifier is in any column, and outside the content columns no column holds a person identifier other than `user_name`

#### Scenario: The content columns are listed

- **WHEN** the operator lists the columns of `agent` that hold session content
- **THEN** they are `session_event`'s `prompt`, `response`, `tool_parameters`, `tool_input` and `error`, and `agent_span`'s `span_status_message` and span attributes `last_user_message`, `user_prompt`, `gen_ai.output.messages`, `gen_ai.tool.call.arguments`, `gen_ai.tool.call.result`, `omp.gen_ai.tool.status`, `full_command`, `file_path` and `error`

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

**Discharged by**: `agent-session-telemetry-interface` requirement `Agent queues are sized to their holds`; `fleet-ingress-interface` requirements `Each agent exports by its role` and `The agent-session collector exports each signal through its own exporter`; `telemetry-store-interface` requirement `The collector's queue persists across a telemetry store restart`; the measured rates after deploy.

#### Scenario: A queue is shrunk below its hold

- **WHEN** a configuration sizes an agent-telemetry host's event queue below 8 hours, its agent series queue below 24 hours, or its own series queue below 24 hours
- **THEN** that host's evaluation fails

#### Scenario: The assumed rate is exceeded

- **WHEN** the rates measured after deploy give a hold below its target
- **THEN** the measurement is recorded as a finding and the queues are resized by a change

### Requirement: Agent sessions cannot cost a host's own series

However many agent sessions run on an agent-telemetry host and however large their content, the collector SHALL keep recording every series of that host's own signals; an overload SHALL cost only agent series, session events and omp's session content, and a lost one SHALL reach a person through a failure notice.

**Discharged by**: `agent-session-telemetry-interface` requirements `The agent-session pipelines run in a collector unit of their own`, `The loopback receiver feeds only the agent-session pipelines` and `Regulators cover the agent-session path`; the split load harness on pyrite's and magnetite's evaluated collectors (design D14); resting on world assumptions `A199 — omp's chat spans carry the whole conversation at the measured sizes` and `A200 — The collector holds ten to fourteen times a span request while decoding it`.

#### Scenario: Eight sessions post their largest contexts at once

- **WHEN** eight agent sessions on pyrite or magnetite each send a 13.8 MiB conversation every 5 seconds, or 64 spans at once
- **THEN** no series of the host's own signals is lost and the host's collector does not restart

#### Scenario: The agent sessions' part of the collector is killed

- **WHEN** the agent-session part of an agent-telemetry host's collector is killed for lack of memory
- **THEN** it restarts within seconds, the host's own series continue without a gap, and a failure notice names it

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

- **WHEN** the VM test sends raw API bodies, an unlisted field, an unlisted event, account identifiers, a message body, a foreign harness, an unlisted metric, a whole conversation history and planted token-shaped secrets, each marked with a unique word, beside admitted prompts and tool output
- **THEN** no marked word or forbidden field appears anywhere in the telemetry store, the secrets appear only as `****`, and the admitted prompt and tool output are found by their word
