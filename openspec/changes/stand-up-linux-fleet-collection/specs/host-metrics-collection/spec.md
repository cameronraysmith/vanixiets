## RENAMED Requirements

- FROM: `### Requirement: magnetite contributes its own signals to the telemetry store`
- TO: `### Requirement: Each agent host contributes its own signals to the telemetry store`

## MODIFIED Requirements

### Requirement: Each agent host contributes its own signals to the telemetry store

The collector on each provisioned agent host SHALL write that host's memory, compressed swap, per-process memory, unit, storage-pool, out-of-memory and file-system signals, a laptop's disk health, and on magnetite the signals its services publish about themselves, to the `fleet` database, gathering each from a source on that host.
The collector SHALL write only series to the `fleet` database, no log records and no traces; the dev-loop records it writes are required by `devloop-collection`.

**Discharged by**: `telemetry-store-interface` requirements `Ingest is OTLP over HTTP with a database header`, `Scrape targets are reached on loopback` and `The collector's configuration bounds what it gathers`, and `fleet-ingress-interface` requirements `The ingress receiver accepts only certificate holders on magnetite's ZeroTier address`, `Each agent exports by its role` and `pyrite's NVMe health is read by a loopback exporter`, resting on world assumptions `A50 — electrum, galena and scheelite exist only while provisioned on demand` and `A51 — pyrite's NVMe controller answers the SMART health log at the pinned smartmontools`; the evaluation-time regulator over magnetite's collector configuration, the agent role's assertions, the container runtime tests and the operator's confirmation at each host's first deploy discharge it.

#### Scenario: magnetite's collector configuration is evaluated

- **WHEN** magnetite's collector configuration is evaluated
- **THEN** the evaluation-time collector regulator finds every source the collector reaches for these signals, node_exporter's storage-pool and out-of-memory signals and the endpoints the forge, the build service, the binary cache, the web front end, the overlay network and the telemetry store itself publish, on loopback, so each is reached only from magnetite itself, and its mutants show it fails when one leaves loopback; which signals are gathered is set by the collector's module, with no copy in the regulator, and the container test and the first activation observe the series that arrive

#### Scenario: The collector runs beside the telemetry store in the container runtime test

- **WHEN** the container runtime test runs the collector and the telemetry store together
- **THEN** a series the collector gathers is written to the `fleet` database the collector selects for it, and the collector reads each watched unit's state from the host's supervisor while running under an identity allocated at start

#### Scenario: magnetite is first activated with the collector

- **WHEN** magnetite is first activated with the collector and has run for one collection interval
- **THEN** the operator confirms that compressed swap use for magnetite's compressed swap device appears in the `fleet` database, and that the `fleet` database holds no log records and no traces, and records both observations

#### Scenario: The collector starts after the databases exist

- **WHEN** magnetite starts the collector while the telemetry store holds no databases yet, as at first activation or after the telemetry store is rebuilt
- **THEN** the collector begins writing only after the unit that sets up the telemetry store's databases has run, and the evaluation-time collector regulator fails before any activation if the collector is no longer ordered after that unit, which its mutant shows

#### Scenario: Every provisioned agent host reports

- **WHEN** magnetite, cinnabar and pyrite have each run the collector for one collection interval after their first deploy with the ingress
- **THEN** the operator finds memory, unit, storage-pool and file-system series for each of the three, told apart by the name of its host, and records the result

#### Scenario: Another agent host's collector is the container test's agent

- **WHEN** the ingress container test runs a collector of a host other than magnetite against the ingress and the telemetry store
- **THEN** that host's series arrive in the `fleet` database under its own name, after crossing the ingress

#### Scenario: pyrite's disk health is read

- **WHEN** pyrite has run the collector for one collection interval after its deploy, without a reboot
- **THEN** the operator finds pyrite's disk health in the `fleet` database and records it

#### Scenario: A host that is not provisioned

- **WHEN** an agent host of the fleet is configured but not provisioned
- **THEN** it writes nothing and nothing reports its absence, and it reports from its first provisioning on

#### Scenario: A host runs none of magnetite's services

- **WHEN** a host other than magnetite is evaluated
- **THEN** its collector reaches no endpoint for the forge, the build service, the binary cache or the telemetry store, because each is gathered only where that service runs

### Requirement: Series cardinality stays bounded

The collector SHALL bound how many series each signal produces on each agent host, and no per-process signal SHALL carry an identifier that changes with each process started, such as its process number or command line.
The collector's signals about itself SHALL carry no identifier that changes with each start of the collector.

**Discharged by**: `telemetry-store-interface` requirement `The collector's configuration bounds what it gathers` and `fleet-ingress-interface` requirement `otel-envelope on the ingress host regulates the fleet budget`; the evaluation-time regulator over magnetite's collector configuration and its mutants, the agent role's assertions, the collector module's assertion that the per-process identifiers are disabled, and the hourly budget regulator with its container-test fixtures discharge it.

#### Scenario: The bounds are evaluated

- **WHEN** the evaluation-time collector regulator reads magnetite's collector configuration, and each agent host's configuration is evaluated
- **THEN** the regulator finds the 64 MiB per-process memory floor in magnetite's process pipeline, and each host's evaluation finds no more than 40 of that host's units on the collector's watched-unit list, the notifier's per-unit instances not counted, and its mutants and overrides show each fails when the floor leaves the pipeline or the list grows past 40 units; the storage-pool and out-of-memory keep-list is a literal of the collector's module with no copy in the regulator

#### Scenario: Per-process memory is bounded by its floor rather than by a count of names

- **WHEN** a host runs processes under many distinct program names, each holding at least the memory floor
- **THEN** the collector records a series for each of them, because it bounds per-process memory by that floor only and does not itself limit how many distinct process names it stores, and the hourly budget regulator fails once a host stores more than 30 names

#### Scenario: Distinct process names are counted at first activation

- **WHEN** magnetite has run the collector for an hour after first activation
- **THEN** the operator counts the distinct process names stored for magnetite and records the count, and a count above 30 is a finding against the declared bound

#### Scenario: A per-process identifier is turned back on

- **WHEN** a host's collector configuration is changed so that any of the six disabled per-process identifiers is gathered again
- **THEN** that host's evaluation fails before any activation on the collector module's assertion, as an evaluation with `process.command_line` enabled shows

#### Scenario: The watched-unit list grows past its bound

- **WHEN** more than 40 of a host's units, the notifier's instances not counted, match the units the collector watches
- **THEN** that host's evaluation fails before any activation, which a mutant of pyrite's configuration shows

#### Scenario: The notifier's instances are counted

- **WHEN** the hourly budget regulator counts a host's stored unit names
- **THEN** it counts the notifier's instances apart from the cap of 40, and fails when one names a unit the host does not list for notification

#### Scenario: The collector restarts in a loop

- **WHEN** a host's collector restarts repeatedly
- **THEN** its stored signals about itself keep one series per signal, because the identifier of each start is dropped before storage

### Requirement: Collection survives a telemetry store restart without losing the queued interval

When the telemetry store or the ingress is unavailable, the collector on each agent host SHALL hold the queued interval on disk, for at least 24 hours of collection and in less than 512 MiB, and SHALL write it once the telemetry store or the ingress accepts series again, so that a restart of either leaves no gap in the series.

**Discharged by**: `telemetry-store-interface` requirement `The collector's queue persists across a telemetry store restart` and `fleet-ingress-interface` requirement `Each agent exports by its role`, resting on world assumption `A52 — The collector answers back-pressure with a retryable refusal and keeps its persistent queue across an outage and a restart`; the evaluation-time collector regulator's queue case with its mutant, the agent role's queue assertion, the container runtime tests' restart and back-pressure cases, and the operator's measurements of the rate each queue fills discharge it.

#### Scenario: magnetite's collector configuration loses its persistent queue

- **WHEN** magnetite's collector configuration holds its queue only in memory, or bounds it below 24 hours or at or above 512 MiB
- **THEN** the evaluation-time collector regulator fails before any activation, which its mutant shows

#### Scenario: Another agent host's queue is shrunk

- **WHEN** the configuration of a host other than magnetite bounds its queue below 24 hours, at or above 512 MiB, or in memory only
- **THEN** that host's evaluation fails before any activation, which a mutant of cinnabar's configuration shows

#### Scenario: The telemetry store is stopped while the collector gathers

- **WHEN** the container runtime test stops the telemetry store, lets the collector gather, and starts the telemetry store again
- **THEN** the measurements gathered while the telemetry store was stopped are read back from the telemetry store

#### Scenario: The ingress refuses series for a while

- **WHEN** the ingress container test fills the ingress's queue toward the telemetry store, and later makes it refuse series for memory, while another host's collector keeps gathering
- **THEN** every measurement that host gathered is read back from the telemetry store once the ingress accepts series again

### Requirement: Stored unit names carry no owner's name

The collector SHALL store the name of each Omnigent worker unit, which carries the name of the person it runs for, under a fixed alias of that person instead, so that no series in the telemetry store carries a person's name and adding or removing a person never renames another person's series.

**Discharged by**: `telemetry-store-interface` requirement `Omnigent unit names are stored under aliases`; the agent role's alias assertion on every agent host with its override, the container runtime test's alias read-back, and the operator's query at first activation discharge it.

#### Scenario: A worker unit has no alias

- **WHEN** any agent host's configuration runs an Omnigent worker unit for a person who has no alias
- **THEN** that host's evaluation fails before any activation, which a mutant of cinnabar's configuration shows

#### Scenario: A worker unit's state is read back

- **WHEN** the container runtime test, or the operator at first activation, reads the unit names stored for magnetite
- **THEN** each Omnigent worker unit appears under its alias, and no stored unit name contains the person's name

### Requirement: A failed collection or store job notifies a person

A failure of the collector or of its periodic regulator on any agent host, or on magnetite of the telemetry store, the unit that sets up its databases, its hourly envelope regulator, or any unit that applies or confirms a disk-share setting, SHALL produce, from that host, a failure notice on the fleet's notification service naming the failed unit and the host.

**Discharged by**: `telemetry-store-interface` requirement `Failure notices are posted to one topic`, which posts with the notification service's credential, and `fleet-ingress-interface` requirement `One host table declares the agent hosts and what each reports`, resting on world assumptions `A33 — The fleet's notification service on cinnabar is reachable over ZeroTier and is the single delivery path` and `A37 — ntfy provisions users, access entries and tokens from its declaration, and refuses to start on an undeclared user`; the evaluation-time collector regulator's failure-wiring case with its mutants, the agent role's notified-unit assertion on every agent host, `checks.<system>.package-ntfy-send-test-token-transport` and the resolve-hook assertion in `observability-notify.nix`, shown able to fail by an `extendModules` override, discharge that every unit of the kinds named here hands its failure to the notifier with the credential; the operator's recorded deliveries discharge the rest.

#### Scenario: A watched unit fails at first activation

- **WHEN** at magnetite's first activation the hourly envelope regulator is made to fail
- **THEN** a failure notice naming that unit and magnetite appears on the fleet's notification service, and the operator records it

#### Scenario: A named unit loses its failure handler

- **WHEN** magnetite's configuration is changed so that the collector, or any other unit this requirement names, no longer hands its failure to the notifier
- **THEN** the evaluation-time collector regulator fails before any activation, which its mutant shows, so a broken collection is reported rather than noticed as an absence of series

#### Scenario: A new disk-share unit is added

- **WHEN** magnetite's configuration gains a unit that applies or confirms a disk-share setting and does not list it for notification
- **THEN** the evaluation-time collector regulator fails before any activation, which its mutant shows

#### Scenario: A unit fails after publishing to the fleet topics requires the credential

- **WHEN** once the notification service refuses anonymous publishing to the fleet topics, a unit this requirement names fails on magnetite
- **THEN** a failure notice naming that unit and magnetite appears on the fleet's notification service, posted with the credential, and the operator records it

#### Scenario: Another agent host's collector or regulator stops being notified

- **WHEN** an agent host's configuration no longer lists its collector or its periodic regulator for notification
- **THEN** that host's evaluation fails before any activation, which a mutant of cinnabar's configuration shows

#### Scenario: cinnabar's periodic regulator fails at acceptance

- **WHEN** the operator stops cinnabar's collector for 10 minutes while the notification service runs
- **THEN** a failure notice naming cinnabar's periodic regulator and cinnabar appears on the fleet's notification service, and the operator records it
