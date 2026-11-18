## ADDED Requirements

### Requirement: The documentation shows a fleet map of every host and the services it runs

The documentation SHALL publish a fleet map naming every host of the fleet, whether it is a darwin host or a NixOS host, every service each host runs, and the service role each service gives that host.
A service role that every host holds SHALL be shown once, as holding on every host, rather than repeated on each host.

#### Scenario: A person looks up where a service runs

- **WHEN** a person reads the fleet map to learn which host runs a service the fleet offers
- **THEN** the map names that host, its platform, and the service role the service gives it

#### Scenario: A service runs on every host

- **WHEN** a service gives the same service role to every host of the fleet
- **THEN** the fleet map shows it once as holding on every host and not inside each host

### Requirement: The fleet map shows each fleet network and the public edge

The fleet map SHALL show every fleet network, every network member of it, and the service role each network member holds in it, including devices that are not hosts.
The fleet map SHALL show each public hostname of the fleet together with the host that answers it and, where a declared fact records them, the ports at which it is reached.

#### Scenario: Two fleet networks run side by side

- **WHEN** the fleet runs two fleet networks at once, as it does while moving from ZeroTier to tincr
- **THEN** the fleet map shows both networks, each with its own network members and their service roles

#### Scenario: A phone joins a fleet network

- **WHEN** a device that is not a host becomes a network member of a fleet network
- **THEN** the fleet map shows the device as a member of that network

#### Scenario: A person looks up a public hostname

- **WHEN** a person reads the fleet map to learn which host answers a public hostname
- **THEN** the map names that host and the service behind the hostname

### Requirement: The fleet map is derived and says which of its facts are declared

The fleet map SHALL be produced from the fleet's own declared configuration together with the declared facts, and no person SHALL edit the fleet map itself.
The documentation SHALL say which parts of the fleet map come from declared facts, which are true only as the operator last recorded them.

#### Scenario: A person edits the map by hand

- **WHEN** a change edits the fleet map without changing what it is produced from
- **THEN** a check run on the change fails before it merges

#### Scenario: A person asks how far to trust the map

- **WHEN** a person reads the documentation page carrying the fleet map
- **THEN** the page states which facts are derived from the fleet's configuration and which are declared facts

### Requirement: A change to the fleet's placement carries its fleet map change

A change that alters which host runs a service, the service role a service gives a host, the membership of a fleet network, or a declared fact SHALL carry the corresponding change to the fleet map as readable text, and a change that alters any of them without it SHALL fail a check run before it merges.

#### Scenario: A service moves between hosts

- **WHEN** a change moves a service from one host to another and updates the fleet map
- **THEN** the person reviewing the change sees the move as a difference in the fleet map's text in the same change

#### Scenario: A placement change forgets the map

- **WHEN** a change moves a service, changes a fleet network's membership or edits a declared fact without updating the fleet map
- **THEN** a check run on the change fails before it merges, and the failure names the command that brings the map up to date
