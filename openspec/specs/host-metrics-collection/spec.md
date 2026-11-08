# host-metrics-collection Specification

## Purpose

This capability (stratum: `behavioral`) states what the fleet requires of collecting a host's metrics: which signals magnetite contributes, that each stored series names its host, that series cardinality stays bounded, that collection survives a store restart without losing the queued interval, and that a failed collection or store job notifies a human.

## Requirements

### Requirement: Each agent host contributes its own signals to the telemetry store

The collector on each provisioned agent host SHALL write that host's memory, per-process memory and file-system signals, a laptop's disk health, on each agent host other than a darwin host its compressed swap, unit, storage-pool and out-of-memory signals, on a darwin host the state of its launchd jobs, and on magnetite the signals its services publish about themselves, to the `fleet` database, gathering each from a source on that host.

**Discharged by**: `telemetry-store-interface` requirements `Ingest is OTLP over HTTP with a database header`, `Scrape targets are reached on loopback` and `The collector's configuration bounds what it gathers`, and `fleet-ingress-interface` requirements `The ingress receiver accepts only certificate holders on magnetite's ZeroTier address`, `Each agent exports by its role`, `A laptop's disk health is read on the host and served on loopback` and `The darwin probe reports each allow-listed launchd job and the host's disk health in a textfile`, resting on world assumptions `A50 — electrum, galena and scheelite exist only while provisioned on demand`, `A51 — pyrite's NVMe controller answers the SMART health log at the pinned smartmontools`, `A62 — launchctl print reports a system job's state, runs and last exit code as unversioned text, and omits the exit code for some killed jobs`, `A63 — stibnite's internal SSD answers the SMART health read without privilege at the pinned smartmontools` and `A65 — A store-built binary on stibnite reaches the ingress over ZeroTier`; the evaluation-time regulator over magnetite's collector configuration, the darwin collector check over stibnite's rendered collector configurations, the agent role's assertions, the darwin agent's assertions, the container runtime tests and the operator's confirmation at each host's first deploy or activation discharge it.

#### Scenario: The collector writes only series to the fleet database

- **WHEN** the collector writes to the `fleet` database
- **THEN** The collector SHALL write only series to the `fleet` database, no log records and no traces; the dev-loop records it writes are required by `devloop-collection`.

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

#### Scenario: stibnite reports after its first activation

- **WHEN** stibnite has run the collector for one collection interval after its first activation with the ingress
- **THEN** the operator finds memory, per-process memory, disk, file-system, launchd job and disk health series for stibnite, told apart from every other host's by its name, with its disk health read by the probe without administrator rights, and records the result

#### Scenario: A darwin host gathers only what its operating system provides

- **WHEN** the darwin collector check renders stibnite's collector configurations
- **THEN** it finds memory gathered without available memory, disk signals for `disk0` alone and file-system signals for `/System/Volumes/Data` alone, each by strict match, per-process memory gathered with an administrator's rights by a part of the collector that opens no listener, and no compressed swap, unit, storage-pool or out-of-memory source, because a darwin host provides none of them to the collector; its mutants show it fails when the disk list matches every disk or that part of the collector gains a listener

#### Scenario: stibnite sleeps

- **WHEN** stibnite sleeps
- **THEN** its collector gathers nothing while it sleeps, nothing reports its silence, and it reports again from its first collection interval after it wakes, which the operator records after one watched sleep of at least 30 minutes

#### Scenario: A host that is not provisioned

- **WHEN** an agent host of the fleet is configured but not provisioned
- **THEN** it writes nothing and nothing reports its absence, and it reports from its first provisioning on

#### Scenario: A host runs none of magnetite's services

- **WHEN** a host other than magnetite is evaluated
- **THEN** its collector reaches no endpoint for the forge, the build service, the binary cache or the telemetry store, because each is gathered only where that service runs

### Requirement: Each stored series names its host

Every series the collector writes SHALL carry the name of the host it was gathered on, and a reader SHALL be able to select series by that name through both of the telemetry store's query languages.

**Discharged by**: `telemetry-store-interface` requirements `Ingest is OTLP over HTTP with a database header`, `Reads are PromQL and SQL over HTTP with a database header` and `Prometheus remote storage stays enabled for the PromQL query API`; the container runtime test's read-back case and the operator's confirmation at magnetite's first activation and at stibnite's discharge it.

#### Scenario: A series is read back in the container runtime test

- **WHEN** the container runtime test reads back a series the collector wrote, selecting the `fleet` database
- **THEN** the series carries the host's name

#### Scenario: magnetite's series are queried after first activation

- **WHEN** the operator queries magnetite's series in the `fleet` database at first activation, once through each query language
- **THEN** both queries return series carrying `magnetite` as their host, and the operator records the result

#### Scenario: stibnite's series are selected after its first activation

- **WHEN** the operator counts the hosts reporting memory in the `fleet` database after stibnite's first activation, and selects series by `stibnite`
- **THEN** `stibnite` is among the hosts counted, every series selected carries `stibnite` as its host, and the operator records the result

### Requirement: Series cardinality stays bounded

The collector SHALL bound how many series each signal produces on each agent host, and no per-process signal SHALL carry an identifier that changes with each process started, such as its process number or command line.
The collector's signals about itself SHALL carry no identifier that changes with each start of the collector.

**Discharged by**: `telemetry-store-interface` requirement `The collector's configuration bounds what it gathers` and `fleet-ingress-interface` requirements `otel-envelope on the ingress host regulates the fleet budget` and `The darwin probe reports each allow-listed launchd job and the host's disk health in a textfile`; the evaluation-time regulator over magnetite's collector configuration and its mutants, the agent role's assertions, the collector module's assertion that the per-process identifiers are disabled, the darwin collector check's per-process and probe cases with their mutants, the darwin process floor of 384 MiB with the fleet executables kept below it, resting on world assumption `A77 — macOS resident size counts each process's mapped share of the shared cache, so ordinary processes read tens to hundreds of MiB`, the hourly budget regulator with its container-test fixtures, and the operator's count of stibnite's stored names over its first day discharge it.

#### Scenario: A darwin host's launchd jobs are bounded

- **WHEN** the collector on a darwin host reports its launchd jobs
- **THEN** On a darwin host the collector SHALL report the state of at most 30 launchd jobs, each named on the fleet's list of watched launchd jobs, and no launchd job's signal SHALL carry its process number.

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

#### Scenario: A darwin host's per-process identifier is turned back on

- **WHEN** the per-process part of a darwin host's rendered collector configuration gathers any of the six disabled per-process identifiers
- **THEN** the darwin collector check fails, which its mutant enabling a seventh identity attribute shows

#### Scenario: The watched-unit list grows past its bound

- **WHEN** more than 40 of a host's units, the notifier's instances not counted, match the units the collector watches
- **THEN** that host's evaluation fails before any activation, which a mutant of pyrite's configuration shows

#### Scenario: The notifier's instances are counted

- **WHEN** the hourly budget regulator counts a host's stored unit names
- **THEN** it counts the notifier's instances apart from the cap of 40, and fails when one names a unit the host does not list for notification

#### Scenario: A darwin host stores too many launchd job names

- **WHEN** the hourly budget regulator counts the launchd job names a host stored in the last hour
- **THEN** it fails once a host stores more than 30

#### Scenario: A launchd job's process number is read

- **WHEN** the probe reads a running launchd job whose reported state includes its process number
- **THEN** it writes no process number, and the darwin collector check's mutant that writes one fails

#### Scenario: stibnite's names are counted over its first day

- **WHEN** stibnite has run the collector for 24 hours after its first activation
- **THEN** the operator counts the distinct launchd job names and process names stored for stibnite and records both counts, and a count above 30 of either is a finding against the declared bound

#### Scenario: The collector restarts in a loop

- **WHEN** a host's collector restarts repeatedly
- **THEN** its stored signals about itself keep one series per signal, because the identifier of each start is dropped before storage

### Requirement: Collection survives a telemetry store restart without losing the queued interval

When the telemetry store or the ingress is unavailable, the collector on each agent host SHALL hold the queued interval in its local state, for at least 24 hours of collection and in less than 512 MiB, and SHALL write it once the telemetry store or the ingress accepts series again, so that a restart of either leaves no gap in the series.

**Discharged by**: `telemetry-store-interface` requirement `The collector's queue persists across a telemetry store restart` and `fleet-ingress-interface` requirement `Each agent exports by its role`, resting on world assumption `A52 — The collector answers back-pressure with a retryable refusal and keeps its persistent queue across an outage and a restart`; the evaluation-time collector regulator's queue case with its mutant, the agent role's queue assertion, the darwin agent's queue assertions with their overrides, the container runtime tests' restart and back-pressure cases, the operator's measurements of the rate each queue fills, and the operator's reading of stibnite's queues after a watched sleep discharge it.

#### Scenario: magnetite's collector configuration loses its persistent queue

- **WHEN** magnetite's collector configuration holds its queue only in memory, or bounds it below 24 hours or at or above 512 MiB
- **THEN** the evaluation-time collector regulator fails before any activation, which its mutant shows

#### Scenario: Another agent host's queue is shrunk

- **WHEN** the configuration of a host other than magnetite bounds its queue below 24 hours, at or above 512 MiB, or in memory only
- **THEN** that host's evaluation fails before any activation, which a mutant of cinnabar's configuration shows

#### Scenario: stibnite's queue is shrunk

- **WHEN** stibnite's configuration bounds its queues below 24 hours, or their sum at or above 512 MiB
- **THEN** stibnite's evaluation fails before any activation, which an override of stibnite's configuration shows for each bound

#### Scenario: The telemetry store is stopped while the collector gathers

- **WHEN** the container runtime test stops the telemetry store, lets the collector gather, and starts the telemetry store again
- **THEN** the measurements gathered while the telemetry store was stopped are read back from the telemetry store

#### Scenario: The ingress refuses series for a while

- **WHEN** the ingress container test fills the ingress's queue toward the telemetry store, and later makes it refuse series for memory, while another host's collector keeps gathering
- **THEN** every measurement that host gathered is read back from the telemetry store once the ingress accepts series again

#### Scenario: stibnite wakes with its queue held

- **WHEN** stibnite wakes from a sleep of at least 30 minutes taken after at least an hour of collection
- **THEN** each queue its collector holds drains to empty after it wakes, and the operator records the reading

### Requirement: Stored unit names carry no owner's name

The collector SHALL store the name of each Omnigent worker's unit or launchd job, which carries the name of the person it runs for, under a fixed alias of that person instead, so that no series in the telemetry store carries a person's name and adding or removing a person never renames another person's series.

**Discharged by**: `telemetry-store-interface` requirement `Omnigent unit names are stored under aliases` and `fleet-ingress-interface` requirement `The darwin probe reports each allow-listed launchd job and the host's disk health in a textfile`; the agent role's alias assertion on every agent host with its override, the darwin collector check's parser case over a recorded Omnigent worker's launchd job with its alias mutant, the container runtime test's alias read-back, and the operator's query at first activation discharge it.

#### Scenario: A worker unit has no alias

- **WHEN** any agent host's configuration runs an Omnigent worker unit for a person who has no alias
- **THEN** that host's evaluation fails before any activation, which a mutant of cinnabar's configuration shows

#### Scenario: A worker unit's state is read back

- **WHEN** the container runtime test, or the operator at first activation, reads the unit names stored for magnetite
- **THEN** each Omnigent worker unit appears under its alias, and no stored unit name contains the person's name

#### Scenario: A darwin worker job's state is read

- **WHEN** the darwin collector check runs the probe's reader over the recorded state of an Omnigent worker's launchd job on stibnite
- **THEN** the job is written under its person's alias and no written launchd job name contains the person's name, and the mutant that drops the alias fails

### Requirement: A failed collection or store job notifies a person

A failure of the collector or of its periodic regulator on any agent host, or on magnetite of the telemetry store, the unit that sets up its databases, its hourly envelope regulator, or any unit that applies or confirms a disk-share setting, SHALL produce, from that host, a failure notice on the fleet's notification service naming the failed unit and the host.

**Discharged by**: `telemetry-store-interface` requirements `Failure notices are posted to one topic`, which posts with the notification service's credential, and `A failure episode ends at the unit's next successful start or exit`, `fleet-ingress-interface` requirements `One host table declares the agent hosts and what each reports` and `otel-envelope regulates each agent from its own collector`, and `fleet-alerting` requirement `Each known failure class on a host reaches a person as an alert`, resting on world assumptions `A33 — The fleet's notification service on cinnabar is reachable over ZeroTier and is the single delivery path`, `A37 — ntfy provisions users, access entries and tokens from its declaration, and refuses to start on an undeclared user` and `A66 — ntfy refuses an anonymous post to a fleet topic from stibnite`; the evaluation-time collector regulator's failure-wiring case with its mutants, the agent role's notified-unit assertion on every agent host, `checks.<system>.package-ntfy-send-test-token-transport`, the resolve-hook assertion in `observability-notify.nix`, shown able to fail by an `extendModules` override, and the darwin collector check's notifier cases with their mutant, discharge that every unit of the kinds named here hands its failure to the notifier with the credential; the operator's recorded deliveries discharge the rest.

#### Scenario: A darwin host's collector fails

- **WHEN** the collector, or a launchd job of the collector, fails or stops on a darwin host
- **THEN** On a darwin host, whose launchd hands no failure to the notifier, a failure of the collector SHALL produce, from that host, a failure notice naming the periodic regulator that finds it and the host, and a stopped or failed launchd job of the collector SHALL reach a person as an alert.

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

#### Scenario: stibnite's collector stops at acceptance

- **WHEN** the operator stops stibnite's collector for two runs of its periodic regulator and then starts it again
- **THEN** one failure notice naming stibnite's periodic regulator and stibnite appears on the fleet's notification service, one notice of that failure's end follows the collector's start, nothing else is posted, and the operator records both

#### Scenario: The darwin notifier posts on every failing run

- **WHEN** the darwin notifier is changed so that it posts a failure notice on every failing run rather than once per failure
- **THEN** the darwin collector check fails, which its mutant shows

#### Scenario: A darwin notice is posted without the credential

- **WHEN** a post to a fleet topic leaves stibnite without the notification service's credential
- **THEN** the notification service refuses it, so stibnite's notices are posted with the credential, and the operator records the refusal at acceptance

#### Scenario: Part of stibnite's collector is killed

- **WHEN** the operator kills the per-process part of stibnite's collector
- **THEN** one alert naming a failed launchd job and stibnite reaches a person after 5 minutes, and its recovery once launchd's report of that job reads a clean exit, and the operator records both
