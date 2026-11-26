## ADDED Requirements

### Requirement: Each fact about a fleet host is recorded once

The host registry SHALL hold one record per fleet member, and each host fact SHALL be written in exactly one place: the member's record. A host fact that follows from other host facts, such as a host's kind from its system, its fully qualified name and overlay address from its name, or the address it is deployed at from its deploy account and name, SHALL be a derived fact and SHALL NOT be written anywhere.
A host's state version SHALL be one of its recorded facts.

#### Scenario: A host's system is changed

- **WHEN** the operator changes one host's system in its record and nothing else
- **THEN** the host's kind, the system its configuration is built for, and every per-host check that depends on its kind follow from that one edit, and no second place needs editing for the configuration to build

#### Scenario: Two places disagree about a host

- **WHEN** a search of the repository finds a host's system, kind or deploy address written by hand outside its record
- **THEN** the requirement is violated for that fact

### Requirement: A fleet member that runs no configuration is never treated as a host that builds one

A phone SHALL be a fleet member with no system, and SHALL be left out of every set of hosts whose configurations are built, checked or deployed. A phone SHALL remain a member of every set that concerns the overlay network.

#### Scenario: The set of hosts whose configurations are built

- **WHEN** the set of hosts with a system is read
- **THEN** it holds the six NixOS and four nix-darwin hosts and neither phone

#### Scenario: The overlay network's external members

- **WHEN** the externally joined members are read
- **THEN** both phones are among them

### Requirement: Lifecycle facts about a host are independent of each other

Whether a host is a checked host, whether it is an enrolled host, and whether its cloud server exists SHALL be three separate host facts, and changing one SHALL change neither of the others nor anything that depends only on the others.

#### Scenario: A cloud server is turned off

- **WHEN** the operator records that a host's cloud server no longer exists
- **THEN** the host remains a checked host and its per-host check still runs

#### Scenario: A host is deferred from checks

- **WHEN** the operator records that a host is not a checked host
- **THEN** its overlay network membership, its deployability and its cloud server are unchanged

#### Scenario: A reserved name has no machine

- **WHEN** a host has a record and a configuration but is not an enrolled host
- **THEN** it is left out of the overlay network peers that need its machine key, without its name being written in those sets

### Requirement: A cloud host's memory follows from its cloud machine type

The memory recorded for a host running on a cloud server SHALL be the memory of its cloud machine type, and SHALL NOT be written separately. A cloud machine type whose memory is not known SHALL stop evaluation with a message naming the type.

#### Scenario: A cloud server is resized

- **WHEN** the operator changes a host's cloud machine type to another type of known memory
- **THEN** the host's recorded memory, and the evaluator bound that follows from it, change with no other edit

#### Scenario: An unknown machine type

- **WHEN** a host is given a cloud machine type that has no memory entry
- **THEN** evaluation reading its memory fails and names the type

### Requirement: A host whose memory cannot be read is reported, never silently classified

A host that runs a configuration and whose memory cannot be read SHALL be named in the report of unclassified hosts. A host whose memory is recorded as unknown SHALL be accepted as unknown and SHALL get the evaluator chosen for unknown memory.

#### Scenario: A host's memory is invalid

- **WHEN** a host's memory is recorded as something that is neither a positive number of GiB nor unknown
- **THEN** the report of unclassified hosts names it, and no evaluator bound is chosen for it

#### Scenario: blackphos's memory is unknown

- **WHEN** the report is read
- **THEN** blackphos is accepted with unknown memory, as it is today

### Requirement: Membership in a service role is decided by one rule

Every reader that needs the hosts playing a service role SHALL use one rule, the one the fleet's service deployment applies: the hosts named in the role, together with every host carrying any of the role's inventory tags, where the tag `all` matches every host.

#### Scenario: A host joins a role by tag

- **WHEN** a host gains an inventory tag that a service role lists
- **THEN** every reader of that role's membership, including the role's checks, includes the host

#### Scenario: A role uses the tag all

- **WHEN** a service role lists the tag `all`
- **THEN** every reader of its membership includes every host

### Requirement: The overlay network controller admits exactly the externally joined members

The overlay network's controller SHALL authorise exactly the externally joined members, determined from each member's host kind, so that adding or removing a nix-darwin host or a phone changes the admitted set with no further edit.

#### Scenario: A laptop joins the fleet

- **WHEN** a nix-darwin host is added to the host registry with its overlay address
- **THEN** the controller's admitted set includes it after the controller's next deploy, with no edit to the controller's settings

#### Scenario: The admitted set today

- **WHEN** the controller's admitted set is read after this requirement is met
- **THEN** it holds the overlay addresses of argentum, blackphos, rosegold, stibnite, pixel7 and pixel11 and no other

### Requirement: A host dropped or reclassified everywhere at once is still caught

The fleet pin SHALL be kept as literal data, independent of the host registry. Every host's kind as the registry derives it SHALL be compared with the fleet pin, so that a host removed from the registry, or whose kind changes, is reported even though every table derived from the registry agrees with it.

#### Scenario: A host disappears from the registry

- **WHEN** a host's record is removed and nothing else is edited
- **THEN** the comparison with the fleet pin fails and names the host

#### Scenario: A host's kind flips

- **WHEN** a host's system is changed so that its derived kind differs
- **THEN** the comparison with the fleet pin fails and names the host
