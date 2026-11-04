## MODIFIED Requirements

### Requirement: The telemetry store runs a stable vendor release that serves its dashboard

The telemetry store SHALL run a stable release, never a prerelease, and SHALL serve its vendor's embedded dashboard only to a reader on magnetite or tunnelled to its loopback listener, as the operator's fallback when the dashboard service is unavailable.
The fleet SHALL run the vendor's own published build of that release unless the channel's package also serves the embedded dashboard.
The embedded dashboard SHALL NOT be reachable through the dashboard service's hostname; people read the fleet's signals through the dashboard service, which `fleet-dashboard` requires.

**Discharged by**: `telemetry-store-interface` requirements `The telemetry store's release and usage reporting are fixed at evaluation` and `Listeners are bound to loopback only`, and `fleet-dashboard-interface` requirement `The dashboard service listens on loopback behind one vhost`, resting on world assumption `A30 — nixpkgs channels lag the telemetry store's vendor releases and omit its dashboard`; the evaluation-time release regulator with its mutants, the store module's listener assertion, the serving predicate's vhost clause and the container runtime test's dashboard case discharge it.

#### Scenario: A prerelease is configured

- **WHEN** magnetite's configuration selects a telemetry store release whose version carries a prerelease suffix
- **THEN** the evaluation-time release regulator fails before any activation

#### Scenario: A build without the dashboard is configured

- **WHEN** magnetite's configuration selects a build of the telemetry store that does not declare the embedded dashboard, such as the channel's package
- **THEN** the evaluation-time release regulator fails before any activation, which its mutant shows

#### Scenario: A reader opens the dashboard

- **WHEN** the operator on magnetite, or one tunnelled to its loopback listener, requests the embedded dashboard from the running telemetry store
- **THEN** the telemetry store serves it, which the container runtime test's dashboard case confirms

#### Scenario: The embedded dashboard is requested through the dashboard service's hostname

- **WHEN** a configuration of the dashboard service's vhost gains a location that proxies to the telemetry store's listener
- **THEN** magnetite's evaluation fails on the serving predicate's vhost clause, which admits only the proxy to the dashboard service and the refusal of `/metrics`
