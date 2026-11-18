## MODIFIED Requirements

### Requirement: An admitted person views the fleet's signals and the dev-loop history by host

An admitted person SHALL be able to open the dashboard service at its hostname from a browser, and SHALL find there one view of each collecting host's memory, compressed swap, per-process memory, out-of-memory kills, file systems, storage pools, units and disk health, selectable by the name of the host, and one view of the dev-loop history's queue wait, formation-to-land, build outcomes and deploys per host, and of each evaluation's memory peak against its memory ceiling and its duration, told apart by evaluator.

**Discharged by**: `fleet-dashboard-interface` requirements `The dashboard service runs the vendor's release with its pinned plugins`, `The dashboard service listens on loopback behind one vhost`, `The telemetry store is read only through two global datasources`, `Committed files are the only source of views and datasources` and `The view files lint clean at the shipped plugins`, resting on world assumption `A58 — Perses 0.55.1 removes its write routes in read-only mode, proxies with the stored credential and fixed headers, and refreshes a session without depending on the identity provider's answer`; the lint check, the container runtime test's query and views cases and the operator's recorded observation at first deployment discharge it.

#### Scenario: The operator opens both views after admission

- **WHEN** at first deployment the operator, admitted, opens each view
- **THEN** the host view shows series for magnetite, cinnabar and pyrite told apart by the name of the host, the dev-loop view shows rows from the dev-loop history, and the operator records both

#### Scenario: A view's query fails or returns nothing

- **WHEN** the container runtime test runs every committed view's query through its datasource against the telemetry store
- **THEN** each query succeeds and each host-view query returns series, and the same case over a view whose query names a series the telemetry store does not hold fails rather than showing an empty chart as success

#### Scenario: A host joins the fleet's collection

- **WHEN** a host begins sending its signals to the telemetry store under its own name
- **THEN** the host view offers that name without a change to any view, because the view selects hosts from the stored names

#### Scenario: The evaluator changes

- **WHEN** the build service's evaluator changes and evaluations under both have been recorded
- **THEN** the dev-loop view shows both evaluators' memory peaks against the memory ceiling and both durations as separate series, so the change is visible at its date
