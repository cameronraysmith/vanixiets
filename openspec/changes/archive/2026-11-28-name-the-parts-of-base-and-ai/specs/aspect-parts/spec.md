## ADDED Requirements

### Requirement: The base settings and the agent tooling are each one parts list

The base settings of NixOS hosts, the base settings of darwin hosts and the agent tooling SHALL each consist of exactly the parts its parts list names, in that list's order, and the fleet description SHALL add nothing to them except through that list.

#### Scenario: A reader asks what the base settings of a darwin host are

- **WHEN** the operator reads the parts list of the darwin base settings
- **THEN** it names every part a darwin host receives as base settings, and no other statement in the fleet description adds to them

#### Scenario: A statement adds to the base settings outside the list

- **WHEN** the fleet description gains a statement that adds settings to the base settings or the agent tooling without naming a part in a parts list
- **THEN** a check fails naming the statement's location, before the change is accepted

#### Scenario: A part is named and never listed

- **WHEN** the fleet description names a new part of the base settings or the agent tooling and no parts list names it
- **THEN** a check fails naming the part, before the change is accepted

#### Scenario: A second statement adds to an existing part

- **WHEN** the fleet description gains a statement, away from where a listed part is stated, that adds settings to that part
- **THEN** a check fails naming the statement's location and the part, before the change is accepted, unless the part is one stated on purpose in several places and the check names each of them

### Requirement: A part can be taken alone

A host's configuration, a home configuration or a check SHALL be able to take one part of the base settings or of the agent tooling without the rest, and taking it SHALL give exactly the settings that part holds in the parts list.

#### Scenario: A check takes one part

- **WHEN** a check's configuration takes a single part of the NixOS base settings and nothing else of the base settings
- **THEN** it receives that part's settings and none of the other parts'

### Requirement: Restating the base settings or the agent tooling changes nothing delivered beyond declared order

When the base settings or the agent tooling are restated as parts lists, every host and home configuration SHALL deploy or activate the same members in every list it holds, with the same accounts and groups and the same uid and gid for each, and SHALL differ only in member order declared in advance. This relies on A344, A375, A376 and A377.

#### Scenario: A restatement step's declared differences are read

- **WHEN** the differences a restatement step declares in advance are read
- **THEN** each is the member order of a configuration's installed packages, of the agent tooling's three review bindings or of a kind of Homebrew entry a Mac installs, and each names the hosts and homes it reaches

#### Scenario: A restatement step is compared with its base commit

- **WHEN** a restatement step's host and home configurations and checks are set beside those of its base commit
- **THEN** every difference is one the step declared, every declared difference occurred, and each differing configuration differs only in the member order of its installed packages, of the three review bindings or of a kind of Homebrew entry

#### Scenario: A Mac is deployed after the restatement

- **WHEN** the operator deploys a darwin host after a restatement that reached it
- **THEN** the host's accounts and groups, and each one's uid and gid, are those it had before, and the deploy deletes none of them

#### Scenario: The installed packages are compared before the step is accepted

- **WHEN** the installed packages of every host and home a step reorders are built at the step's base commit and at its candidate commit, every package included
- **THEN** both provide the same files from the same packages, and the step is accepted only then

#### Scenario: Something other than declared member order differs

- **WHEN** the comparison of a restatement step finds a configuration whose lists differ in their members, whose accounts, groups or identifiers differ, or anything delivered that differs other than in the member order of its installed packages, of the three review bindings or of a kind of Homebrew entry, including a reordered activation step or configuration file
- **THEN** the step is not accepted, the difference is reported and recorded as an open question, and it is never declared as an accepted difference
