## ADDED Requirements

### Requirement: Graph data lives on the disk of the host that serves it

When a host's storage location is its own disk, the graph store on that host SHALL keep all of its graph data on that host's disk, within a bound of 20 GiB that leaves the rest of the disk to the host's other services, and SHALL keep none of it in a bucket.
A new storage location on a disk SHALL start empty and be filled by seeding each example graph from its published seed, never by copying graph data from a bucket.

**Discharged by**: `graph-store-interface` requirements `The root store setting yields the root's location`, `The graph data has a dataset of its own`, `Every omnigraph unit runs as the static user omnigraph` and `The bootstrap creates and seeds the local root`; relies on A231 and A241.

#### Scenario: magnetite serves from its disk

- **WHEN** magnetite's storage location is its disk and the graph store is serving
- **THEN** every graph it serves is read from magnetite's disk, and its graph data occupies at most 20 GiB of that disk

#### Scenario: the first start on the disk

- **WHEN** the graph store first starts on magnetite after its storage location changes to the disk
- **THEN** each example graph is created and loaded once from its seed, and the graph store then serves all of them

### Requirement: The storage location is chosen per host, and switching back serves what the bucket held

Each host SHALL have exactly one storage location for its graph data, either its own disk or a bucket, chosen by one setting of that host, and both locations SHALL be reachable under the same graph data name.
Switching a host back to the bucket SHALL serve the graph data the bucket held when the host left it; changes made while serving from the disk SHALL NOT follow.

**Discharged by**: `graph-store-interface` requirements `The root store setting yields the root's location`, `R2 settings apply only to an R2 root`, `Every omnigraph unit runs as the static user omnigraph` and `The state directory survives the moves between stores and generations`; relies on A236 and A241.

#### Scenario: switching back to the bucket

- **WHEN** magnetite's setting is changed back to the bucket after a week of serving from its disk
- **THEN** the graph store serves the graph data as it stood in the bucket on the day magnetite left it, and none of that week's changes

#### Scenario: only one location is served

- **WHEN** magnetite's configuration is evaluated with either setting
- **THEN** the graph store is configured with exactly one storage location

### Requirement: The graph store recovers from its own crash without a person

When the graph store's previous run ended in a crash and left its stale writer claim behind, the graph store's next start SHALL clear that claim by itself and serve the same graph data, provided no direct writer is running against that graph data, the claim was made by the graph store itself, and the claim's writer is gone or the claim was made before the current boot.
Each such recovery SHALL be counted, and SHALL send a recovery notice to the operator.

**Discharged by**: `graph-store-interface` requirements `The server's start clears a stale serve lock`, `Recoveries are counted and announced` and `A rehearsal holds the recovery's verdicts`; relies on A232 and A233.

#### Scenario: a kill while serving

- **WHEN** the graph store is killed while serving on magnetite's disk and is started again
- **THEN** it serves every graph with the same entity counts and the same answers to stored queries as before the kill, the recovery count rises by one, and the operator receives one recovery notice

#### Scenario: a crash before a reboot

- **WHEN** magnetite reboots after the graph store crashed, and the claim names a writer that matches something running in the new boot
- **THEN** the graph store clears the claim made before the boot and serves

### Requirement: The graph store refuses to clear a writer claim it cannot prove stale

The graph store's start SHALL leave a writer claim in place and fail visibly, telling the operator why and the manual step that clears it, whenever it cannot show the claim is stale.

**Discharged by**: `graph-store-interface` requirements `The server's start clears a stale serve lock` and `A rehearsal holds the recovery's verdicts`; relies on A232.

#### Scenario: a direct writer is running

- **WHEN** the graph store starts while a direct writer is running against its graph data
- **THEN** the claim stays, the graph store does not serve, and the operator receives a failure notice naming the running writer

#### Scenario: the claim was made by a direct writer

- **WHEN** the graph store starts and finds a claim made by a direct writer that is no longer running
- **THEN** the claim stays, the graph store does not serve, and the reason names the direct writer's own recovery step

#### Scenario: the claim's writer is alive in this boot

- **WHEN** the graph store starts and finds its own claim made during the current boot whose writer is still running
- **THEN** the claim stays and the graph store does not serve

#### Scenario: the claim changed while it was read

- **WHEN** the claim found at start differs from the claim the graph store reports for its graph data
- **THEN** the claim stays and the graph store does not serve

#### Scenario: the claim cannot be read

- **WHEN** the claim found at start is not in the form the graph store writes
- **THEN** the claim stays and the graph store does not serve

### Requirement: Graph data is copied off its host every night from an instant image

Each night, a host whose storage location is its disk SHALL take a local snapshot of its graph data and store a graph backup made from that snapshot in a bucket off the host, keeping the last 7 nights, one per week for 4 weeks and one per month for 6 months, with a sample read back each night.
A graph backup SHALL be made only from a local snapshot, never by copying the graph data file by file while the graph store runs, and the graph store SHALL keep serving while it is made.

**Discharged by**: `graph-store-interface` requirements `The backup job copies a ZFS snapshot to its R2 repository` and `The backup job runs nightly and catches up a missed night`; relies on A234 and A235.

#### Scenario: a night on magnetite

- **WHEN** a night passes on magnetite while it serves from its disk
- **THEN** the bucket holds a new graph backup of that night's graph data, and the graph store answered requests throughout

#### Scenario: a copy taken file by file

- **WHEN** a configuration would back the graph data up by copying it file by file from the live location
- **THEN** it is refused before deploy

### Requirement: Graph data can be restored to identical answers

The operator SHALL be able to restore graph data from a graph backup, clear the writer claim the backup carries, and start the graph store on the restored graph data, which then answers with the entity counts and stored query results it had when the backup was taken.

**Discharged by**: `graph-store-interface` requirements `A runtime test proves recovery, refusal and restore` and `Every omnigraph unit runs as the static user omnigraph`; the runbook; relies on A232 and A235.

#### Scenario: a restore after the graph data is lost

- **WHEN** the graph data on magnetite's disk is lost and the operator restores the latest graph backup by the runbook
- **THEN** the graph store serves every graph with the entity counts and stored query results recorded at that backup

### Requirement: Local snapshots stay available

The graph data SHALL have local snapshots on the host's disk on the host's usual schedule, for returning to a recent state without the bucket.

**Discharged by**: `graph-store-interface` requirement `The graph data has a dataset of its own`; relies on A235.

#### Scenario: an hour after the switch

- **WHEN** magnetite has served from its disk for over an hour
- **THEN** at least one local snapshot of the graph data exists on magnetite

### Requirement: The operator learns when the graph store is not serving

The operator SHALL receive an alert when, for 5 minutes, the graph store is not serving or any of its graphs is blocked, and SHALL receive its resolution when serving returns.

**Discharged by**: `graph-store-interface` requirements `The probe publishes readiness each minute` and `OmnigraphNotServing reports a graph store that is not serving`.

#### Scenario: the graph store stops

- **WHEN** the graph store on magnetite stops answering and stays down for 6 minutes
- **THEN** the operator receives a warning alert naming magnetite, and a resolution once it serves again

#### Scenario: a restart

- **WHEN** the graph store restarts and serves again within 2 minutes
- **THEN** no alert is sent

### Requirement: The operator learns when graph backups are overdue

The operator SHALL receive an alert when no graph backup has succeeded on a host for 36 hours, including when none ever has.

**Discharged by**: `graph-store-interface` requirement `OmnigraphBackupStale reports an overdue backup`.

#### Scenario: two nights missed

- **WHEN** the last successful graph backup on magnetite is 37 hours old
- **THEN** the operator receives a warning alert naming magnetite and the runbook

### Requirement: The graph store's state is visible on a dashboard

A dashboard SHALL show, for the graph store, whether it is serving, how many graphs are in each state, how long its last start took to serve, each graph's entity count, version and storage format, whether those per-graph readings succeeded, the graph data's use of its disk bound, the number of local snapshots, the age of the last graph backup and the number of recoveries.

**Discharged by**: `graph-store-interface` requirements `The probe publishes readiness each minute`, `The probe publishes per-graph and storage series`, `The probe reports a failed per-graph read` and `The omnigraph view is provisioned and query-checked`.

#### Scenario: the operator opens the dashboard

- **WHEN** the operator opens the graph store's dashboard while magnetite serves from its disk
- **THEN** every quantity above is shown for magnetite
