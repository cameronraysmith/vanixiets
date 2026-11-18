## ADDED Requirements

### Requirement: Each laptop that builds for the fleet reports its store disk

Once its collection is turned on with a watched deploy, the collector on rosegold and on argentum SHALL write that laptop's file-system signals for the disk holding its software store, and the state of its launchd jobs, to the `fleet` database.

**Discharged by**: the existing requirements of this capability for a darwin host, and `store-garbage-collection-interface` requirement `An overrun rule reports a cleanup still running after an hour`.

#### Scenario: rosegold reports after its watched deploy

- **WHEN** rosegold has run the collector for one collection interval after the deploy that turns its collection on
- **THEN** the operator finds file-system and launchd job series for rosegold, told apart from every other host's by its name, and records the result

#### Scenario: argentum reports after its watched deploy

- **WHEN** argentum has run the collector for one collection interval after the deploy that turns its collection on
- **THEN** the operator finds file-system and launchd job series for argentum, told apart from every other host's by its name, and records the result with argentum's available memory before and after the deploy

### Requirement: blackphos is declared an agent host with its collection off until a machine takes its name

blackphos SHALL be declared among the agent hosts with its collection off, and SHALL report only after a machine takes its name and its collection is turned on with a watched deploy.

#### Scenario: blackphos has no machine

- **WHEN** the agent hosts are read while no machine has taken the name blackphos
- **THEN** blackphos is declared with its collection off, writes nothing, and nothing reports its absence
