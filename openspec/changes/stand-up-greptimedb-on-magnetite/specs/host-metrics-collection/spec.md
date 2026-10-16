## ADDED Requirements

### Requirement: magnetite contributes its own signals to the telemetry store

The collector on magnetite SHALL write magnetite's memory, compressed swap, per-process memory, unit, storage-pool and out-of-memory signals, and the signals the services on magnetite publish about themselves, to the `fleet` database, gathering each from a source on magnetite itself.
The collector SHALL write series only, and SHALL write no log records and no traces to the telemetry store.

**Discharged by**: `telemetry-store-interface` requirements `Ingest is OTLP over HTTP with a database header`, `Scrape targets are reached on loopback` and `The collector's configuration bounds what it gathers`; the evaluation-time regulator over magnetite's collector configuration, the container runtime test's ingest and unit-state cases, and the operator's confirmation at first activation discharge it.

#### Scenario: magnetite's collector configuration is evaluated

- **WHEN** magnetite's collector configuration is evaluated
- **THEN** the evaluation-time collector regulator finds configured magnetite's available memory, its compressed swap use, the memory of each process large enough to matter, the running state and restart count of each unit on the fleet's watched list, its storage pool's health and cache size, the kernel's count of processes killed for want of memory, and the signals the forge, the build service, the binary cache, the web front end, the overlay network and the telemetry store itself publish, each reached only from magnetite itself, and its mutants show it fails when one is broken

#### Scenario: The collector runs beside the telemetry store in the container runtime test

- **WHEN** the container runtime test runs the collector and the telemetry store together
- **THEN** a series the collector gathers is written to the `fleet` database the collector selects for it, and the collector reads each watched unit's state from the host's supervisor while running under an identity allocated at start

#### Scenario: magnetite is first activated with the collector

- **WHEN** magnetite is first activated with the collector and has run for one collection interval
- **THEN** the operator confirms that compressed swap use for magnetite's compressed swap device appears in the `fleet` database, and that the telemetry store holds no log records and no traces, and records both observations

### Requirement: Each stored series names its host

Every series the collector writes SHALL carry the name of the host it was gathered on, and a reader SHALL be able to select series by that name through both of the telemetry store's query languages.

**Discharged by**: `telemetry-store-interface` requirements `Ingest is OTLP over HTTP with a database header` and `Reads are PromQL and SQL over HTTP with a database header`; the container runtime test's read-back case and the operator's confirmation at first activation discharge it.

#### Scenario: A series is read back in the container runtime test

- **WHEN** the container runtime test reads back a series the collector wrote, selecting the `fleet` database
- **THEN** the series carries the host's name

#### Scenario: magnetite's series are queried after first activation

- **WHEN** the operator queries magnetite's series in the `fleet` database at first activation, once through each query language
- **THEN** both queries return series carrying `magnetite` as their host, and the operator records the result

### Requirement: Series cardinality stays bounded

The collector SHALL bound how many series each signal produces on magnetite, and no per-process signal SHALL carry an identifier that changes with each process started, such as its process number or command line.
Per-process memory is bounded by a memory floor rather than by a count: no stage of the pinned collector limits the number of distinct process names, so the bound of 30 names per host is declared at evaluation, observed at first activation, and regulated at runtime from slice S4.

**Discharged by**: `telemetry-store-interface` requirement `The collector's configuration bounds what it gathers`; the evaluation-time regulator over magnetite's collector configuration and its mutants, and the operator's count of distinct process names at first activation, discharge it.

#### Scenario: The bounds are evaluated

- **WHEN** the evaluation-time collector regulator reads magnetite's collector configuration
- **THEN** it finds per-process memory recorded only for processes using at least 64 MiB, the bound of 30 distinct process names declared beside the watched list, per-unit signals recorded only for units on the fleet's watched list of no more than 40 units, and only the named storage-pool and out-of-memory signals kept from the host's own probe

#### Scenario: Distinct process names are counted at first activation

- **WHEN** magnetite has run the collector for an hour after first activation
- **THEN** the operator counts the distinct process names stored for magnetite and records the count, and a count above 30 is a finding against the declared bound

#### Scenario: A per-process identifier is turned back on

- **WHEN** magnetite's collector configuration is changed so that any of the six disabled per-process identifiers is gathered again
- **THEN** the evaluation-time collector regulator fails before any activation

#### Scenario: The watched list and the collector's unit list diverge

- **WHEN** the units the collector watches differ from the fleet's watched list, or that list exceeds 40 units
- **THEN** the evaluation-time collector regulator fails before any activation

### Requirement: Collection survives a telemetry store restart without losing the queued interval

When the telemetry store is unavailable, the collector SHALL hold the queued interval on disk, for at least 24 hours of collection and in less than 512 MiB, and SHALL write it to the telemetry store once the telemetry store accepts series again, so that a restart of the telemetry store leaves no gap in the series.

**Discharged by**: `telemetry-store-interface` requirement `The collector's queue persists across a telemetry store restart`; the evaluation-time collector regulator's queue case with its mutant, the container runtime test's restart case, and the operator's measurement at first activation of the rate the queue fills, which the 24-hour bound otherwise assumes, discharge it.

#### Scenario: magnetite's collector configuration loses its persistent queue

- **WHEN** magnetite's collector configuration holds its queue only in memory, or bounds it below 24 hours or at or above 512 MiB
- **THEN** the evaluation-time collector regulator fails before any activation, which its mutant shows

#### Scenario: The telemetry store is stopped while the collector gathers

- **WHEN** the container runtime test stops the telemetry store, lets the collector gather, and starts the telemetry store again
- **THEN** the measurements gathered while the telemetry store was stopped are read back from the telemetry store

### Requirement: Stored unit names carry no owner's name

The collector SHALL store the name of each Omnigent worker unit, which carries the name of the person it runs for, under a fixed alias of that person instead, so that no series in the telemetry store carries a person's name and adding or removing a person never renames another person's series.

**Discharged by**: `telemetry-store-interface` requirement `Omnigent unit names are stored under aliases`; the evaluation-time collector regulator's alias case with its mutant, the container runtime test's alias read-back, and the operator's query at first activation discharge it.

#### Scenario: A worker unit has no alias

- **WHEN** magnetite's configuration runs an Omnigent worker unit for a person who has no alias
- **THEN** the evaluation-time collector regulator fails before any activation, which its mutant shows

#### Scenario: A worker unit's state is read back

- **WHEN** the container runtime test, or the operator at first activation, reads the unit names stored for magnetite
- **THEN** each Omnigent worker unit appears under its alias, and no stored unit name contains the person's name

### Requirement: A failed collection or store job notifies a person

A failure of the collector, of the telemetry store, of the unit that sets up its databases, of its hourly envelope regulator, or of any unit that applies or confirms a disk-share setting on magnetite SHALL produce, from magnetite, a failure notice on the fleet's notification service naming the failed unit and magnetite, without the notifier holding any credential for that service.

**Discharged by**: `telemetry-store-interface` requirement `Failure notices are posted to one topic`, resting on world assumption `A33 — The fleet's notification service on cinnabar is reachable over ZeroTier and accepts anonymous publishing`; the evaluation-time collector regulator's failure-wiring case with its mutant discharges that every named unit hands its failure to the notifier, and the operator's deliberately failed envelope regulator at first activation discharges delivery from magnetite.

#### Scenario: A watched unit fails at first activation

- **WHEN** at magnetite's first activation the hourly envelope regulator is made to fail
- **THEN** a failure notice naming that unit and magnetite appears on the fleet's notification service, and the operator records it

#### Scenario: A named unit loses its failure handler

- **WHEN** magnetite's configuration is changed so that the collector, or any other unit this requirement names, no longer hands its failure to the notifier
- **THEN** the evaluation-time collector regulator fails before any activation, which its mutant shows, so a broken collection is reported rather than noticed as an absence of series
