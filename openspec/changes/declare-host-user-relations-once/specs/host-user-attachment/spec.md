## ADDED Requirements

### Requirement: Each account a person holds on a host is declared once

Each account a person holds on a host SHALL be declared once, together with whether that account belongs to the host's primary user, whether it is the host's admin account, whether the person's personal key reaches it, and what that account's home configuration adds on that host. Every other place that needs one of these facts SHALL take it from that declaration and SHALL NOT state it again.

#### Scenario: A person is given an account on a new host

- **WHEN** the operator declares that a person holds an account on a host, and makes no other edit
- **THEN** the account is created on the host, its home configuration is built there, and its personal key reaches it where that is declared, with no second place to edit

#### Scenario: A host-account fact is written twice

- **WHEN** a search of the repository finds which hosts an account is on, which account is a host's primary user or admin account, or whose personal key reaches a host, written by hand outside that declaration
- **THEN** the requirement is violated for that fact

### Requirement: A host provides exactly its declared accounts, home configurations and secret access

Each host SHALL provide exactly the accounts declared for it, each with that person's home configuration plus what the declaration adds for that host, and the personal key of a person SHALL reach an account on a host exactly where that is declared.

#### Scenario: The accounts and home configurations are unchanged by the declaration

- **WHEN** each host's accounts, home configurations and personal-key reach are compared before and after the declarations replace the hand-written statements
- **THEN** they are the same on every host

#### Scenario: A declared account that nothing creates

- **WHEN** an account is declared on a host where nothing creates that account
- **THEN** the host's configuration fails to evaluate, naming the host and the account, rather than building a home configuration for an account that does not exist

### Requirement: A darwin host's admin account is declared separately from its primary user

On a darwin host, the admin account SHALL be declared as its own fact, and SHALL NOT be inferred from which person is the host's primary user. One person's account MAY be both. A darwin host SHALL have exactly one admin account, and every host SHALL have at most one primary user.

#### Scenario: The primary user is not the administrator

- **WHEN** a darwin host's primary user is a person other than the one whose account administers it, as on blackphos and the two laptops
- **THEN** the host is administered through the declared admin account and the primary user's account is not given that role

#### Scenario: Two primary users are declared

- **WHEN** two accounts on one host are both declared as the primary user's
- **THEN** evaluation fails, naming the host

### Requirement: Which hosts run a person's Omnigent workers is declared once

For each person on whose behalf the fleet runs Omnigent workers, the hosts that run them SHALL be declared once. The hosts each worker runs on, the people whose workers may request deploys, and each such host's participating accounts in its reference tree SHALL follow from that declaration.

#### Scenario: A person's worker is added to a host

- **WHEN** the operator declares one more host for a person's Omnigent workers, and makes no other edit
- **THEN** the worker runs there and becomes a participating account of that host's reference tree, with no second place to edit

#### Scenario: The worker hosts are compared with an independent record

- **WHEN** the hosts that run workers, and the people whose workers run on each, are compared with the fleet's independently kept record of them
- **THEN** they agree, and a difference fails the fleet's checks

### Requirement: An Omnigent worker's home configuration cannot read any person's private settings or whole home configuration

An Omnigent worker's home configuration SHALL be built from a restricted fleet description that holds neither any person's private settings nor any person's whole home configuration, so that a worker home configuration that tries to read either fails to build.

#### Scenario: A worker home configuration reaches for a person's configuration

- **WHEN** a worker's home configuration is given a setting that reads a person's whole home configuration, or a person's private settings
- **THEN** evaluating that worker's home configuration fails, and the fleet's checks observe that failure

#### Scenario: The worker home configurations of the fleet

- **WHEN** the worker home configurations on the hosts that run workers are built
- **THEN** each is built from the restricted fleet description, and none fails

### Requirement: The person-account correspondence is stated once

The person-account correspondence SHALL be stated once, and both directions, from a person to the account name under which the fleet keeps that person's home configuration and keys, and from such an account name to its person, SHALL be read from that statement. No person or account name SHALL change as a result.

#### Scenario: The two directions are read

- **WHEN** the person for crs58 and the account for cameron are read
- **THEN** they are cameron and crs58, from the same statement, and every other known name maps to itself

#### Scenario: An unknown name is read

- **WHEN** the person is read for a name that is neither a person nor an account the fleet knows
- **THEN** the read fails with a message naming it, rather than returning the name

### Requirement: Every home configuration is checked without a hand-kept list

On each checked system, every person's home configuration SHALL be checked once, inside a host that provides it or else on its own, and the set checked on its own SHALL follow from the declared accounts rather than from a list kept by hand. Deciding which checks exist SHALL NOT require building any home configuration or host configuration.

#### Scenario: An account is moved between hosts

- **WHEN** a person's only account on the hosts of a checked system is removed
- **THEN** that person's home configuration is checked on its own on that checked system, with no list to edit

#### Scenario: The checked set today

- **WHEN** the home configurations checked on their own are listed before and after the change
- **THEN** the lists are equal on both checked systems

### Requirement: A person's home configuration does not depend on the order a host's settings are read

Every home configuration a host provides, and every home configuration built on its own, SHALL be built from one fleet description, given to it by whatever composes it, and SHALL NOT depend on the order in which a host's settings are read.

#### Scenario: Two writers of the fleet description

- **WHEN** a host's configuration gives every home configuration on it a fleet description in more than one place
- **THEN** evaluation fails, naming the host

#### Scenario: The fleet description is made single

- **WHEN** each home configuration's build is compared before and after the fleet description is made single
- **THEN** every home configuration and every host configuration is the same, or the difference is traced to its cause and declared
