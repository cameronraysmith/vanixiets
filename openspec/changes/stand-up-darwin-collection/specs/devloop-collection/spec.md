## MODIFIED Requirements

### Requirement: Every dev-loop event is recorded once and kept for a year

Every attribute outcome the build service records, every build it finishes, every batch event the merge queue announces, and every deploy on a collected host SHALL be kept in the dev-loop history as one dev-loop record per event, for 365 days, however often the collector reads it.
When the build service restarts an attribute that had finished, the earlier outcome SHALL stay in the dev-loop history as its own dev-loop record beside the new one.

**Discharged by**: `devloop-collection-interface` requirements `The collector reads nixbot's builds and attributes through two cursor queries`, `gitea-mq's five batch messages are parsed from its journal`, `Each activation appends one deploy record`, `Each agent host's collector ships its own deploy records`, `The devloop tables are pre-created with keys, a time index and deduplication` and `Dev-loop sources are stamped and routed to their table`, resting on world assumptions `A43 — nixbot's migrations create the build and attribute columns the dev-loop copy reads, and finish times are transaction start times`, `A44 — gitea-mq announces each batch transition in one of five exact journal messages`, `A46 — GreptimeDB 1.2.1 keeps one row per key and time in a pre-created non-append table`, `A47 — The collector's sqlquery receiver resumes logs queries from the last row's tracking value` and `A65 — A store-built binary on stibnite reaches the ingress over ZeroTier`; the daily reconcile, the on-demand container tests' overlap and delivery cases, the darwin collector check's validation of stibnite's rendered collector configuration, and the operator's comparison at each collected host's first deploy or activation discharge it.

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

#### Scenario: stibnite becomes a collected host

- **WHEN** stibnite is first activated with its own collector
- **THEN** the dev-loop history holds one dev-loop record for each deploy record stibnite had written, including those written before it had a collector, and the operator records that the count of its deploy records equals the count of its dev-loop records
