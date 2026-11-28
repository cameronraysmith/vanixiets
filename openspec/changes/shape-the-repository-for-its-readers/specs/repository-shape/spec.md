## ADDED Requirements

### Requirement: No host list is kept by convention alone

Every place in the fleet description outside a host's own directory where a host's name or fact is written SHALL either be derived from the host registry or be compared with it by a check that names a missing or extra host, except places another planned change removes, which the documentation SHALL name. The documentation SHALL list, in one place, the steps of adding a host that no statement can derive, each with the check that fails until it is done.

#### Scenario: The operator adds a server

- **WHEN** the operator adds a NixOS server and follows the documentation's one place for adding a host
- **THEN** every host list the server must join is either derived, named in that place, or enforced by a check that fails until the server is added

#### Scenario: A checked host list disagrees with the registry

- **WHEN** a hand-written host list names a host the registry does not hold, or omits one it does
- **THEN** a check fails naming the host and the list, before the change is accepted

#### Scenario: A generated step is skipped

- **WHEN** a new host that will be deployed lacks a generated step the documentation lists
- **THEN** the check that step names fails, naming the host

### Requirement: Each configuration's composition can be stated on request and its routes are known

The fleet description SHALL provide one documented command that states, for any host configuration or home configuration built apart from a host, its composition: each part, the route by which it arrives, and for a home the systems it is built for. A check SHALL fail when a part reaches a checked host's configuration by a route the documentation does not list.

#### Scenario: A reader lists what a host consists of

- **WHEN** a reader with a shell asks for everything that ends up in one host's configuration, grouped by how it arrives
- **THEN** the documented command answers it in full

#### Scenario: A part arrives by an unlisted route

- **WHEN** the fleet description makes a part reach a checked host's configuration by a route the documentation does not list
- **THEN** a check fails naming the host, the part and where it was brought in, before the change is accepted

### Requirement: One placement rule per kind of addition

The documentation SHALL state, in one entry-point document, one placement rule for each kind of addition: a host, a person, a fleet-wide setting, a feature for some hosts, a Mac application, a home tool, a hand-entered secret and a check. No other documentation SHALL state a different rule for the same kind.

#### Scenario: Three contributors add the same kind of thing

- **WHEN** three contributors, each reading only the repository, place the same new addition of one kind
- **THEN** each cites the rule in the entry-point document and all three place it in the same file or directory with the same mechanism

#### Scenario: Two documents disagree

- **WHEN** a document other than the entry point states a placement rule for a kind the entry point covers, and the two differ
- **THEN** the review of the change that introduced the difference rejects it, and the entry point's rule stands

### Requirement: Restructuring delivers nothing but declared priority and order

Each step of restructuring the fleet description SHALL be a refactor. Only the priority step and the order step SHALL name declared differences: the priority step only priority marks that keep each file's provider, the order step only the order of installed packages and of three review bindings; every other step SHALL name none beyond the checks it adds. This relies on A376, A377 and A384.

#### Scenario: A move or rename step is compared

- **WHEN** a step that moves or renames parts of the fleet description is compared with its base commit
- **THEN** no host configuration or home configuration differs, and every differing check is one the step declared

#### Scenario: The order step is compared

- **WHEN** the order step's candidate commit is compared with its base commit
- **THEN** every differing host or home configuration differs only in the order of its installed packages or of the three review bindings, every file its installed packages provide has the same content when built, and on a darwin host the accounts, groups and their identifiers are equal

#### Scenario: Something other than declared difference differs

- **WHEN** a step's comparison shows a difference that is not one it declared, or a declared difference beyond priority or order
- **THEN** the step is not accepted, and the difference is recorded as an open question rather than declared

### Requirement: Restructuring is accepted on what readers can do

The restructuring SHALL be accepted only when a re-run of the reader measure answers every lookup task rightly at no greater cost than the baseline, and every run of each placement, enumeration and impact task meets the target set for it; results SHALL be reported as counts of runs with the sample size.

#### Scenario: The lookup tasks are re-run

- **WHEN** the lookup tasks are re-run after the last step with the baseline's tools
- **THEN** every answer is right, and the files opened and searches made are no more, at the median and at the maximum, than at the baseline

#### Scenario: A target is missed

- **WHEN** a run of the re-measure misses a target
- **THEN** the miss is recorded with the task and run, and the next step taken is the one the design names for that miss
