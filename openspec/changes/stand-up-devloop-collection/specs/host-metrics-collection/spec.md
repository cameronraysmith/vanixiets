## MODIFIED Requirements

### Requirement: magnetite contributes its own signals to the telemetry store

The collector on magnetite SHALL write magnetite's memory, compressed swap, per-process memory, unit, storage-pool and out-of-memory signals, and the signals the services on magnetite publish about themselves, to the `fleet` database, gathering each from a source on magnetite itself.
The collector SHALL write series only to the `fleet` database, and SHALL write no log records and no traces there; the dev-loop records it writes to the dev-loop history are required by `devloop-collection`, not here.

**Discharged by**: `telemetry-store-interface` requirements `Ingest is OTLP over HTTP with a database header`, `Scrape targets are reached on loopback` and `The collector's configuration bounds what it gathers`; the evaluation-time regulator over magnetite's collector configuration, the container runtime test's ingest and unit-state cases, and the operator's confirmation at first activation discharge it.

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
