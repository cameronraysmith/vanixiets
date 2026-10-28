## MODIFIED Requirements

### Requirement: Every dev-loop event is recorded once and kept for a year

Every attribute outcome the build service records, every build it finishes, every batch event the merge queue announces, and every deploy on a collected host SHALL be kept in the dev-loop history as one dev-loop record per event, for 365 days, however often the collector reads it.
When the build service restarts an attribute that had finished, the earlier outcome SHALL stay in the dev-loop history as its own dev-loop record beside the new one.

**Discharged by**: `devloop-collection-interface` requirements `The collector reads nixbot's builds and attributes through two cursor queries`, `gitea-mq's five batch messages are parsed from its journal`, `Each activation appends one deploy record`, `Each agent host's collector ships its own deploy records`, `The devloop tables are pre-created with keys, a time index and deduplication` and `Dev-loop sources are stamped and routed to their table`, resting on world assumptions `A43 — nixbot's migrations create the build and attribute columns the dev-loop copy reads, and finish times are transaction start times`, `A44 — gitea-mq announces each batch transition in one of five exact journal messages`, `A46 — GreptimeDB 1.2.1 keeps one row per key and time in a pre-created non-append table` and `A47 — The collector's sqlquery receiver resumes logs queries from the last row's tracking value`; the daily reconcile, the on-demand container tests' overlap and delivery cases, and the operator's comparison at each collected host's first deploy discharge it.

#### Scenario: The collector reads the same attribute outcome five times

- **WHEN** an attribute outcome is read on each of five consecutive reads while it is less than five minutes old
- **THEN** the dev-loop history holds one dev-loop record for it, which the container test's overlap case shows and the daily reconcile confirms on magnetite

#### Scenario: An attribute is restarted

- **WHEN** an attribute that finished yesterday is restarted today and finishes again
- **THEN** the dev-loop history holds both outcomes, and the reconcile accepts yesterday's record although the build service now keeps only the later one

#### Scenario: The build service prunes a build

- **WHEN** the build service deletes a build 90 days after it finished
- **THEN** its dev-loop records stay in the dev-loop history until they are 365 days old

#### Scenario: A host other than magnetite becomes a collected host

- **WHEN** cinnabar, and later pyrite, is first deployed with its own collector
- **THEN** the dev-loop history holds one dev-loop record for each deploy record that host had written, and the operator records that the count of its deploy records equals the count of its dev-loop records

### Requirement: A gap in the dev-loop history reaches a person within a day

When the dev-loop history lacks a record for an event of the previous UTC day that its source on magnetite still holds, or holds a record such a source cannot account for, a failure notice SHALL reach a person by the end of the following morning.
When the build service built a merge-queue batch on a day for which the dev-loop history holds no batch event announcing a build, a failure notice SHALL reach a person the same way.

**Discharged by**: `devloop-collection-interface` requirements `devloop-reconcile runs daily as its own reader`, `devloop-reconcile compares CI rows with nixbot every day`, `devloop-reconcile compares batch events with the journal every day` and `devloop-reconcile compares deploy records with the file and the current system`, and `telemetry-store-interface` requirement `Failure notices are posted to one topic`, resting on world assumptions `A33 — The fleet's notification service on cinnabar is reachable over ZeroTier and is the single delivery path`, `A43 — nixbot's migrations create the build and attribute columns the dev-loop copy reads, and finish times are transaction start times` and `A48 — magnetite's journal keeps gitea-mq's lines for longer than the reconcile's window`; the container test's reconcile mutants and the operator's forced reconcile failure at deploy discharge it.

#### Scenario: A collector change stops copying cached outcomes

- **WHEN** the collector stops copying outcomes of attributes the build service took from a cache
- **THEN** the next morning's reconcile fails and a failure notice naming it and magnetite reaches a person, which the container test's cached-row mutant shows

#### Scenario: The merge queue renames a batch message

- **WHEN** the merge queue keeps building batches but no longer announces them in a message the collector reads
- **THEN** the next morning's reconcile fails on its liveness comparison, which the container test's silent-merge-queue case shows

#### Scenario: Another host's deploy record is lost

- **WHEN** a deploy record that cinnabar or pyrite wrote never reaches the dev-loop history
- **THEN** no failure notice is posted, because the daily comparison samples magnetite's deploy records alone, and the gap is found only by comparing that host's deploy records with its dev-loop records
