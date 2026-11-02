# devloop-collection Specification

## Purpose
This capability (stratum: `behavioral`) states what the fleet requires of its dev-loop history: that every attribute outcome, finished build, merge-queue batch event and deploy is recorded once in `devloop` and kept for a year; that a gap in that history reaches a person within a day; that no error text, message body or other free text enters it; that the past week of the dev loop can be asked about; that a deploy can be attributed to the commits that built it; and that the build service's records are read without being changed and without a stored credential.

## Requirements

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

When the dev-loop history lacks a record for an event of the previous UTC day that its source on magnetite still holds, or holds a record such a source cannot account for, a failure notice SHALL reach a person by 03:00 UTC of the following day.
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

### Requirement: No error text, message body or other free text enters the dev-loop history

The dev-loop history SHALL keep only the fields each kind of dev-loop record declares, none of them error text, a message body or other free text, whatever the build service, the merge queue or a host's deploy record carries.

**Discharged by**: `devloop-collection-interface` requirements `One devloop allow-list decides every stored column` and `The devloop tables are pre-created with keys, a time index and deduplication`, and `telemetry-store-interface` requirement `Ingest is OTLP over HTTP with a database header`; `checks.x86_64-linux.devloop-queries`' result-column comparison and its selected-error mutant, and the container test's table-shape case, discharge it.

#### Scenario: A query edit selects the error text

- **WHEN** the query that reads the build service's attribute outcomes is edited to select their error text
- **THEN** the build-time query check fails before the change can merge

#### Scenario: A merge-queue message carries an unexpected field

- **WHEN** the merge queue adds a field to one of its batch messages
- **THEN** the dev-loop history does not keep it, and the stored batch events keep exactly their declared fields, which the container test's table-shape case confirms

### Requirement: The past week of the dev loop can be asked about

A person SHALL be able to ask the dev-loop history, for the past week, each batch's formation-to-land, the queue wait of the builds run for pull requests, and whether each build passed when flaky and abandoned attributes are left out.
An attribute that failed only because something it depends on failed SHALL count against its build, because the dev-loop history does not record which dependency failed.

**Discharged by**: `devloop-collection-interface` requirements `The devloop tables are pre-created with keys, a time index and deduplication` and `The collector reads nixbot's builds and attributes through two cursor queries`, resting on world assumptions `A43 — nixbot's migrations create the build and attribute columns the dev-loop copy reads, and finish times are transaction start times` and `A44 — gitea-mq announces each batch transition in one of five exact journal messages`; the container test's query case and the operator's recorded answers for the week after deploy discharge it.

#### Scenario: A bisected batch lands in parts

- **WHEN** a batch is bisected and lands in three parts before the merge queue announces it done
- **THEN** its formation-to-land ends at the announcement that it is done, and the three landings stay in the dev-loop history

#### Scenario: One derivation passes and fails in the same week

- **WHEN** an attribute's derivation passed in one build and failed on its own in another within the week
- **THEN** that attribute is flaky for the week and neither build's outcome counts it

#### Scenario: The week after deploy is asked about

- **WHEN** a week has passed since collection started on magnetite
- **THEN** the operator asks the three questions of the dev-loop history and records the answers

### Requirement: A deploy can be attributed to the commits that built it

Each deploy on a collected host SHALL leave a dev-loop record naming the host, the closure it activated, the closure it replaced, if any, and the time, from which a person can find every commit for which the build service passed that host's closure, and a deploy whose closure the build service never passed SHALL be recognisable as such.

**Discharged by**: `devloop-collection-interface` requirements `Each activation appends one deploy record` and `The x86_64-linux NixOS machine checks carry the deploy-record snippet`, resting on world assumption `A49 — NixOS and nix-darwin run activation snippets before the current system is relinked`; the machine-check obligation with its negative control, the reconcile's current-system comparison and the container test's switch case discharge it.

#### Scenario: magnetite is deployed

- **WHEN** magnetite is deployed from a commit the build service passed
- **THEN** exactly one new dev-loop record names magnetite, the new closure and the replaced one, and joining its closure with the build service's passed outputs for magnetite's system yields that commit, which the operator records

#### Scenario: A machine's configuration loses the snippet

- **WHEN** the configuration of a machine whose build-time check the build service runs is evaluated without the deploy-record snippet
- **THEN** that machine's build-time check fails, which the obligation's negative control shows, which blocks a merge for the five x86_64-linux NixOS machines, while for the others the snippet's presence is shown once, when it is introduced

#### Scenario: magnetite boots

- **WHEN** magnetite boots
- **THEN** a dev-loop record names magnetite and its closure with no replaced closure, which marks it as a boot rather than a deploy

### Requirement: The build service's records are read without being changed and without a stored credential

Reading the build service's records for the dev-loop history SHALL change nothing the build service keeps, SHALL add nothing to its database, and SHALL use no stored credential, and each service reading them SHALL be allowed to read only the fields it uses.

**Discharged by**: `devloop-collection-interface` requirement `The nixbot readers authenticate by peer and hold column grants only`, resting on world assumption `A45 — PostgreSQL on magnetite admits a local role named after the connecting system user without a password`; `checks.x86_64-linux.devloop-queries`, which runs the queries under the rendered grants, and its grant mutant discharge it.

#### Scenario: A reader's grants lack a field its query uses

- **WHEN** the grants are rendered without a field the attribute query refers to
- **THEN** the build-time query check fails, which its grant mutant shows
