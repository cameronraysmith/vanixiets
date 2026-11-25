## MODIFIED Requirements

### Requirement: The past week of the dev loop can be asked about

A person SHALL be able to ask the dev-loop history, for the past week, each batch's formation-to-land, the queue wait of the builds run for pull requests, and whether each build passed when flaky and unproven attributes are left out.
An attribute that failed only because something it depends on failed SHALL count against its build, because the dev-loop history does not record which dependency failed.
A Mac attribute that failed with a verdict SHALL count against its build like any other failure.

**Discharged by**: `devloop-collection-interface` requirements `The devloop tables are pre-created with keys, a time index and deduplication`, `The collector reads nixbot's builds and attributes through two cursor queries` and `The attribute query derives abandoned from the unproven status`, resting on world assumptions `A43 — nixbot's migrations create the build and attribute columns the dev-loop copy reads, and finish times are transaction start times` and `A44 — gitea-mq announces each batch transition in one of five exact journal messages`; the container test's query case and the operator's recorded answers for the week after deploy discharge it.

#### Scenario: A bisected batch lands in parts

- **WHEN** a batch is bisected and lands in three parts before the merge queue announces it done
- **THEN** its formation-to-land ends at the announcement that it is done, and the three landings stay in the dev-loop history

#### Scenario: One derivation passes and fails in the same week

- **WHEN** an attribute's derivation passed in one build and failed on its own in another within the week
- **THEN** that attribute is flaky for the week and neither build's outcome counts it

#### Scenario: A build whose Mac attributes were unproven

- **WHEN** a build's Linux attributes passed and its Mac attributes were unproven
- **THEN** the build counts as passed

#### Scenario: A build whose Mac attribute failed with a verdict

- **WHEN** a build's Mac attribute failed because its builder exited non-zero
- **THEN** the build counts as failed

#### Scenario: The week after deploy is asked about

- **WHEN** a week has passed since collection started on magnetite
- **THEN** the operator asks the three questions of the dev-loop history and records the answers
