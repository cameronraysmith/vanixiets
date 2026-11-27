## ADDED Requirements

### Requirement: Each host's deployed system is unchanged apart from declared differences

When the way a host's configuration is composed is restructured, the system each host deploys SHALL stay the same, apart from differences declared in advance, each with the hosts it reaches and what a deploy of it changes on them.

#### Scenario: A restructuring step is compared with its base commit

- **WHEN** the derivations of every host's configuration, home configuration, check and runtime test at a step's base commit are set beside those at its candidate commit
- **THEN** every difference is one the step declared, and every declared difference occurred

#### Scenario: A step changes a host it did not declare

- **WHEN** the comparison finds a host whose deployed system differs and the step declared no difference for it
- **THEN** the step is not accepted until the difference is traced to its cause and removed

### Requirement: A capability several hosts run is declared once

A capability that more than one host runs SHALL be declared once, and each host SHALL state only the capabilities it runs and what is particular to it.

#### Scenario: A second host takes up a capability

- **WHEN** the operator gives a second host a capability one host runs today
- **THEN** the second host names the capability and states only its own particulars, with no copy of the first host's statement

#### Scenario: A shared statement is copied into a host

- **WHEN** a search finds the same statement of a shared capability in two hosts' own declarations
- **THEN** the requirement is violated for that capability

### Requirement: A cloud server takes its provider's shape from one declaration

Each cloud server SHALL take the shape its cloud provider requires (its network uplink, how its disks are named, and the provider's hardware settings) from one declaration per provider, and SHALL take the declaration of the provider it runs on and no other.

#### Scenario: A host names the wrong provider's shape

- **WHEN** a cloud server is declared with the shape of a provider other than the one the fleet description records for it
- **THEN** its configuration fails to evaluate, naming the host and both providers

#### Scenario: A host that is not a cloud server

- **WHEN** a host the fleet description records with no cloud provider is composed
- **THEN** it takes no provider's shape

### Requirement: A Mac's state version is declared once

Each darwin host's state version SHALL be declared once, in the fleet description, as the version the host was first set up with, and every part of the host's configuration that depends on it SHALL take it from there.

#### Scenario: The state versions are read

- **WHEN** each darwin host's configured state version is read
- **THEN** it equals the version the fleet description records for that host, which for argentum, blackphos, rosegold and stibnite is 4

### Requirement: A darwin host's deploy record is the last thing its activation writes

On every darwin host, the deploy record SHALL be the last step of activation before the new system becomes the current one, so that a deploy record names a deploy whose every other step completed.

#### Scenario: A step is added after the record

- **WHEN** a darwin host's activation would run another step after its deploy record and before the new system becomes current
- **THEN** the fleet's checks of that host fail, naming the step

### Requirement: Each darwin host consults each binary cache once

Each darwin host SHALL be configured with each binary cache it trusts exactly once.

#### Scenario: The caches are read after the change is deployed

- **WHEN** the operator reads the binary caches a deployed darwin host is configured with
- **THEN** each appears once, and the set of caches is the one the host had before

### Requirement: magnetite's boot-enforced dataset properties are stated once

The storage properties magnetite enforces on its datasets at each boot SHALL be stated once, and SHALL be kept independent of the declaration the host was installed from, so that the two can be compared.

#### Scenario: The enforced properties differ from the install-time declaration

- **WHEN** a property magnetite enforces at boot on the telemetry store's dataset differs from the install-time declaration
- **THEN** the fleet's checks fail, naming the property
