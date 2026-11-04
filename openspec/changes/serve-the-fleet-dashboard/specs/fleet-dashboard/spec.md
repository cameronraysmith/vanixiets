## ADDED Requirements

### Requirement: An admitted person views the fleet's signals and the dev-loop history by host

An admitted person SHALL be able to open the dashboard service at its hostname from a browser, and SHALL find there one view of each collecting host's memory, compressed swap, per-process memory, out-of-memory kills, file systems, storage pools, units and disk health, selectable by the name of the host, and one view of the dev-loop history's queue wait, formation-to-land, build outcomes and deploys per host.

**Discharged by**: `fleet-dashboard-interface` requirements `The dashboard service runs the vendor's release with its pinned plugins`, `The dashboard service listens on loopback behind one vhost`, `The telemetry store is read only through two global datasources`, `Committed files are the only source of views and datasources` and `The view files lint clean at the shipped plugins`, resting on world assumption `A58 — Perses 0.55.0 removes its write routes in read-only mode, proxies with the stored credential and fixed headers, and refreshes a session without the identity provider`; the lint check, the container runtime test's query cases and the operator's recorded observation at first deployment discharge it.

#### Scenario: The operator opens both views after admission

- **WHEN** at first deployment the operator, admitted, opens each view
- **THEN** the host view shows series for magnetite, cinnabar and pyrite told apart by the name of the host, the dev-loop view shows rows from the dev-loop history, and the operator records both

#### Scenario: A view queries a series the telemetry store does not hold

- **WHEN** the container runtime test runs a view's query against a table the telemetry store does not hold
- **THEN** the telemetry store rejects it, and the test fails rather than showing an empty chart as success

#### Scenario: A host joins the fleet's collection

- **WHEN** a host begins sending its signals to the telemetry store under its own name
- **THEN** the host view offers that name without a change to any view, because the view selects hosts from the stored names

### Requirement: A person outside the dashboard group is refused

The identity provider SHALL refuse to admit to the dashboard service any person who is not a member of the dashboard group, and the dashboard service SHALL show nothing to a person it has not admitted.

**Discharged by**: `fleet-dashboard-interface` requirements `The identity provider admits only the dashboard group` and `The dashboard service listens on loopback behind one vhost`, resting on world assumptions `A56 — Kanidm refuses an authorization whose scopes no group of the person maps` and `A57 — Dashboard-group membership is kept in the running identity provider`; the serving predicate's client and authentication clauses, the container runtime test's unauthenticated case and the operator's recorded refusal at first deployment discharge it.

#### Scenario: The operator tries before joining the group

- **WHEN** at first deployment the operator, not yet a member of the dashboard group, tries to log in to the dashboard service
- **THEN** the identity provider refuses with Access Denied, and the operator records the refusal before joining

#### Scenario: A request carries no login

- **WHEN** the container runtime test asks the dashboard service for its projects without having logged in
- **THEN** the dashboard service refuses with HTTP 401

### Requirement: A person removed from the dashboard group loses access within an hour

A person removed from the dashboard group SHALL lose access to the dashboard service within one hour of the removal.

**Discharged by**: `fleet-dashboard-interface` requirement `The identity provider admits only the dashboard group`, resting on world assumptions `A57 — Dashboard-group membership is kept in the running identity provider` and `A58 — Perses 0.55.0 removes its write routes in read-only mode, proxies with the stored credential and fixed headers, and refreshes a session without the identity provider`; the serving predicate's session clause and its mutant discharge it.

#### Scenario: The session lifetime is lengthened

- **WHEN** the dashboard service's configuration lets a login be renewed for longer than one hour without asking the identity provider
- **THEN** magnetite's evaluation fails on the serving predicate, which its mutant shows

### Requirement: Nobody changes the views except by a committed change

The dashboard service SHALL offer an admitted person no way to create, change or delete a view or a datasource, and after each start of the dashboard service the views and datasources it holds SHALL be exactly those committed to the repository.

**Discharged by**: `fleet-dashboard-interface` requirements `Readers hold only read permission on a read-only server` and `Committed files are the only source of views and datasources`, resting on world assumption `A58 — Perses 0.55.0 removes its write routes in read-only mode, proxies with the stored credential and fixed headers, and refreshes a session without the identity provider`; the serving predicate, the container runtime test's write and planted-view cases and the operator's recorded refused write at first deployment discharge it.

#### Scenario: An admitted person tries to save a view

- **WHEN** an admitted person attempts to create, change or delete a view
- **THEN** the dashboard service refuses, which the container runtime test shows for each of the three and the operator records once at first deployment

#### Scenario: A view not in the repository is present at a start

- **WHEN** the container runtime test plants a view in the dashboard service's state and restarts it
- **THEN** the planted view is gone, and only the committed views remain

### Requirement: No store credential reaches a person, and the dashboard service only reads

No store credential SHALL reach a person's browser through the dashboard service, the dashboard service SHALL read the telemetry store only as the dashboard's store account, and nothing a person sends SHALL reach the telemetry store outside the query paths of its two query languages.

**Discharged by**: `fleet-dashboard-interface` requirements `The telemetry store is read only through two global datasources`, `The dashboard service listens on loopback behind one vhost` and `The dashboard service's secrets arrive only as credentials`, and `telemetry-store-interface` requirement `Credentials exist only as activation-resolved files owned by non-worker users`, resting on world assumptions `A58 — Perses 0.55.0 removes its write routes in read-only mode, proxies with the stored credential and fixed headers, and refreshes a session without the identity provider` and `A59 — GreptimeDB 1.2.1 reads x-greptime-auth before Authorization`; the serving predicate, the container runtime test's proxy, header and bypass cases, and the operator's recorded inspection of browser storage discharge it.

#### Scenario: A person sends a store credential of their own

- **WHEN** the container runtime test sends, through the vhost, a request carrying the administrative store account's credential in the header the telemetry store reads first
- **THEN** the telemetry store sees the dashboard's store account, and a write through that request is refused; the same request sent around the vhost reaches the telemetry store as the administrative account, which shows the vhost is what protects it

#### Scenario: A person asks for a store route outside the query paths

- **WHEN** the container runtime test asks the dashboard service to forward a deletion route or a path-traversal form of a query path
- **THEN** the dashboard service refuses with HTTP 403, and the telemetry store receives nothing

#### Scenario: The operator inspects the browser after logging in

- **WHEN** at first deployment the operator, admitted, inspects the browser's stored data for the dashboard service
- **THEN** it holds no store credential, and the operator records it

### Requirement: The dashboard service stays inside its memory envelope and its failures reach a person

The dashboard service SHALL use no more than 256 MiB of memory, SHALL be stopped by the kernel before the telemetry store when the host runs out of memory, and its failure SHALL produce a failure notice naming it and magnetite.

**Discharged by**: `fleet-dashboard-interface` requirement `The dashboard service runs inside a memory envelope and hands its failures to the notifier`, resting on world assumption `A31 — magnetite's memory is finite and shared with the build service's evaluation work`; the serving predicate's memory clause with its mutant, the notified-unit assertion and the operator's recorded kill at first deployment discharge it.

#### Scenario: The memory ceiling is raised

- **WHEN** magnetite's configuration lets the dashboard service use more than 256 MiB
- **THEN** magnetite's evaluation fails on the serving predicate, which its mutant shows

#### Scenario: The dashboard service is killed

- **WHEN** at first deployment the operator kills the dashboard service
- **THEN** a failure notice naming it and magnetite arrives, the dashboard service starts again, and the operator records both
