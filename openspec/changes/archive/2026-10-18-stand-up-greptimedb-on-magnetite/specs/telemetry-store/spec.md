## ADDED Requirements

### Requirement: A database keeps its series for its retention and no longer

The fleet SHALL keep one telemetry store on magnetite with three databases, `fleet` with a retention of 30 days, `devloop` with a retention of 365 days and `agent` with a retention of 90 days, and the telemetry store SHALL return each database's series to a reader for that database's retention and SHALL NOT keep them past it.
A changed retention SHALL take effect on a database that already exists.

**Discharged by**: `telemetry-store-interface` requirements `Databases and their retention are set at the telemetry store` and `Object data lives under one prefix of one bucket`, resting on world assumption `A29 — Cloudflare R2 behaves as S3-compatible object storage for the telemetry store's client`; the container runtime test's retention case discharges it.

#### Scenario: The telemetry store starts with no databases

- **WHEN** the telemetry store starts for the first time
- **THEN** the databases `fleet`, `devloop` and `agent` exist with retentions of 30, 365 and 90 days, which the container runtime test confirms by reading each database's retention back

#### Scenario: A database already exists with a different retention

- **WHEN** the telemetry store starts while one of the three databases already exists with a retention other than its declared one
- **THEN** that database's retention is changed to the declared value rather than left as it was, which the container runtime test confirms by creating the database with another retention first

### Requirement: Part of a database keeps the database's retention unless another is declared

No part of a database SHALL keep its series on a retention other than the database's own unless the fleet's configuration declares a retention for that part, and a part with a declared retention SHALL keep its series on exactly that retention.

**Discharged by**: `telemetry-store-interface` requirement `Tables allowed a retention of their own are declared`; the hourly envelope regulator's table-retention clause, the envelope check's recorded-answer rehearsal and the container runtime test's undeclared-retention control against the real telemetry store discharge it.

#### Scenario: Part of a database carries an undeclared retention of its own

- **WHEN** a part of one of the three databases carries a retention of its own that the fleet's configuration does not declare, which would override the database's
- **THEN** the hourly envelope regulator fails, and a failure notice reaches a person

#### Scenario: Part of a database carries a declared retention

- **WHEN** a part of one of the three databases carries a retention of its own and the fleet's configuration declares that part with the same retention
- **THEN** the hourly envelope regulator passes on that part, and a declared part that does not exist yet is not judged

#### Scenario: Part of a database departs from its declared retention

- **WHEN** the fleet's configuration declares a retention for a part of one of the three databases and that part carries a different retention, or none of its own
- **THEN** the hourly envelope regulator fails, and a failure notice reaches a person

### Requirement: Only the collector writes and only named readers read

Only the collector SHALL write series to the telemetry store, and only the unit that sets up the databases SHALL hold the operator's administrative store account, the one account that may both read and write.
The telemetry store SHALL refuse the collector any read, SHALL answer queries only from the administrative, the dashboard's and the regulators' store accounts, and SHALL refuse writes from the dashboard's and the regulators' store accounts.

**Discharged by**: `telemetry-store-interface` requirements `Store accounts carry fixed permission modes`, `Listeners are bound to loopback only` and `Credentials exist only as activation-resolved files owned by non-worker users`; magnetite's credential-holder assertion, the container runtime test's authorization matrix, the evaluation-time regulator that the account list holds exactly four valid entries, and the evaluation-time ownership regulator discharge it.

#### Scenario: A second unit takes the administrative store account

- **WHEN** magnetite's configuration gives a unit other than the one that sets up the databases the administrative store account's credential
- **THEN** magnetite's evaluation fails before any activation on its credential-holder assertion, as an evaluation with that change shows

#### Scenario: The collector attempts a read

- **WHEN** the collector presents its own store credential to query any database
- **THEN** the telemetry store refuses the query, which the container runtime test's authorization matrix confirms

#### Scenario: A request arrives with no store credential or a wrong one

- **WHEN** a request to add or query series carries no store credential, or one the telemetry store does not hold
- **THEN** the telemetry store refuses it, including when the request originates on magnetite itself, which the container runtime test's authorization matrix confirms

#### Scenario: A read-only reader attempts a write

- **WHEN** the dashboard's or the regulators' store account presents its store credential to add series
- **THEN** the telemetry store refuses the write, which the container runtime test's authorization matrix confirms

### Requirement: A replaced store credential takes effect on the running telemetry store

A replaced store credential SHALL take effect on the running telemetry store rather than leaving the superseded value valid.

**Discharged by**: `telemetry-store-interface` requirements `Credentials exist only as activation-resolved files owned by non-worker users` and `The account file the telemetry store loaded is recorded`; the evaluation-time envelope regulator's restart-on-rotation mutant and the hourly envelope regulator's credential-freshness case discharge it.

#### Scenario: A store credential is replaced

- **WHEN** the operator replaces the store credentials and magnetite is activated
- **THEN** the telemetry store is running on the new values, and the hourly envelope regulator fails if the account file the running telemetry store loaded is not the one now deployed

#### Scenario: The restart on replacement is dropped from magnetite's configuration

- **WHEN** magnetite's configuration no longer restarts the telemetry store when its store credentials are replaced
- **THEN** the evaluation-time envelope regulator fails before any activation, which one of its mutants shows

### Requirement: The telemetry store stays inside a memory envelope that leaves build capacity to the build service

The telemetry store SHALL draw at most 4 GiB of magnetite's memory, SHALL be throttled before that ceiling, SHALL stay out of compressed swap, and SHALL run at a reduced processor share with fixed parallelism, so that the build service's evaluation keeps its build capacity.
Under memory pressure on magnetite the kernel SHALL kill the build service's evaluation first, the telemetry store second and the collector, which draws at most 512 MiB, third.

**Discharged by**: `telemetry-store-interface` requirement `The telemetry store and the collector run inside a declared envelope`, resting on world assumptions `A31 — magnetite's memory is finite and shared with the build service's evaluation work` and `A32 — magnetite has no /dev/kvm, and the kernel's kill order does not depend on the host it runs on`; the evaluation-time envelope regulator's ceiling and kill-order cases with their mutants, the hourly envelope regulator's memory case, and the on-demand virtual-machine runtime test of the kill order on pyrite discharge it.

#### Scenario: magnetite's configuration drops a memory ceiling

- **WHEN** magnetite's configuration is changed so that the telemetry store loses its memory ceiling, its throttle no longer sits below the ceiling, it may use compressed swap, or its kill preference no longer sits between the evaluation's and the collector's
- **THEN** the evaluation-time envelope regulator fails before any activation, which its mutants dropping the ceiling and swapping the store's and the collector's kill preferences show

#### Scenario: The telemetry store reaches its throttle in operation

- **WHEN** the telemetry store is throttled at its memory level, its own memory, excluding cached file data, reaches that level, or the kernel kills it for exceeding its ceiling
- **THEN** the hourly envelope regulator fails and a failure notice reaches a person, and at magnetite's first activation a deliberately lowered threshold is shown to make that regulator fail

#### Scenario: Memory runs out with all three services drawing

- **WHEN** memory runs out on a host running the build service's evaluation, the telemetry store and the collector with magnetite's kill preferences
- **THEN** the evaluation is killed before the telemetry store and the telemetry store before the collector, which the on-demand virtual-machine runtime test on pyrite confirms

### Requirement: The telemetry store stays inside a disk envelope of its own

The telemetry store SHALL keep its local state in a share of magnetite's disk capped at 16 GiB, of which 12 GiB is held for it, excluded from automatic snapshots, and SHALL raise a failure notice when it has used 80% of that share or when its object data exceeds 50 GiB.

**Discharged by**: `telemetry-store-interface` requirement `The telemetry store and the collector run inside a declared envelope`; the boot-time disk units, the hourly envelope regulator's disk and object-size cases, and the operator's confirmation at first activation of the cap and the holding discharge it.

#### Scenario: magnetite boots

- **WHEN** magnetite boots
- **THEN** the telemetry store's disk share carries its 16 GiB cap and its 12 GiB holding and is excluded from automatic snapshots, and a disk unit that cannot apply or confirm one of those settings fails and raises a failure notice

#### Scenario: The telemetry store fills its share

- **WHEN** the telemetry store's local state reaches 80% of its disk share, or its object data exceeds 50 GiB
- **THEN** the hourly envelope regulator fails and a failure notice reaches a person

#### Scenario: magnetite is first activated with the telemetry store

- **WHEN** magnetite is first activated with the telemetry store
- **THEN** the operator confirms on magnetite that the cap and the holding are in force and records the observation, because no runtime test reaches magnetite's own disk

### Requirement: The telemetry store sends no usage report to its vendor

The telemetry store SHALL NOT send a usage report to its vendor.

**Discharged by**: `telemetry-store-interface` requirement `The telemetry store's release and usage reporting are fixed at evaluation`; the telemetry store module's usage-report assertion discharges it.

#### Scenario: magnetite's configuration omits the usage-report setting

- **WHEN** magnetite's configuration no longer turns the telemetry store's usage report off
- **THEN** magnetite's evaluation fails before any activation on the telemetry store module's usage-report assertion, as an evaluation with the usage report turned on shows

### Requirement: The telemetry store runs a stable vendor release that serves its dashboard

The telemetry store SHALL run a stable release, never a prerelease, and SHALL serve its vendor's embedded dashboard to a reader on magnetite.
The fleet SHALL run the vendor's own published build of that release unless the channel's package also serves the embedded dashboard.

**Discharged by**: `telemetry-store-interface` requirement `The telemetry store's release and usage reporting are fixed at evaluation`, resting on world assumption `A30 — nixpkgs channels lag the telemetry store's vendor releases and omit its dashboard`; the evaluation-time release regulator with its mutants and the container runtime test's dashboard case discharge it.

#### Scenario: A prerelease is configured

- **WHEN** magnetite's configuration selects a telemetry store release whose version carries a prerelease suffix
- **THEN** the evaluation-time release regulator fails before any activation

#### Scenario: A build without the dashboard is configured

- **WHEN** magnetite's configuration selects a build of the telemetry store that does not declare the embedded dashboard, such as the channel's package
- **THEN** the evaluation-time release regulator fails before any activation, which its mutant shows

#### Scenario: A reader opens the dashboard

- **WHEN** a reader on magnetite, or one tunnelled to its loopback listener, requests the dashboard from the running telemetry store
- **THEN** the telemetry store serves it, which the container runtime test's dashboard case confirms

### Requirement: The telemetry store's own failures reach a person

A failure of the telemetry store, of the unit that sets up its databases, of its hourly envelope regulator, or of any unit that applies or confirms a disk-share setting on magnetite SHALL produce a failure notice naming the failed unit and magnetite on the fleet's notification service.

**Discharged by**: `telemetry-store-interface` requirement `Failure notices are posted to one topic`, resting on world assumption `A33 — The fleet's notification service on cinnabar is reachable over ZeroTier and accepts anonymous publishing`; the evaluation-time collector regulator's failure-wiring case with its mutants discharges that each of these units, and any unit of these kinds added later, hands its failure to the notifier, and the operator's deliberately failed envelope regulator at first activation discharges delivery.

#### Scenario: The hourly envelope regulator is made to fail at first activation

- **WHEN** at magnetite's first activation the hourly envelope regulator's memory threshold is set below the telemetry store's observed memory and the regulator runs
- **THEN** the regulator fails, a failure notice naming it and magnetite appears on the fleet's notification service, and the operator records that notice

#### Scenario: The notification service is unreachable

- **WHEN** one of these units fails while the fleet's notification service is down or unreachable from magnetite
- **THEN** no failure notice reaches a person, which this requirement does not cover and world assumption `A33` records
