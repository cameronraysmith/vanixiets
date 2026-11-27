## ADDED Requirements

### Requirement: Building one host's configuration does not require another host's configuration

The configuration of each host in the fleet SHALL be built without any other host's configuration.

**Discharged by**: the `host-configuration-independence-interface` requirements `No host configuration reads another host's evaluated configuration` and `The evaluation saving is measured, not inferred`.

#### Scenario: A darwin host is built

- **WHEN** stibnite's configuration is built
- **THEN** no other host's configuration is computed for it

#### Scenario: A NixOS host is built

- **WHEN** cinnabar's configuration is built
- **THEN** no other host's configuration is computed for it

### Requirement: Each host takes other hosts' host keys from the keys the fleet pins

Every host that trusts another fleet host's host key SHALL take that key from the host keys the fleet pins, and the key it trusts SHALL be identical to the one it trusted before this requirement, byte for byte.

**Discharged by**: the `host-configuration-independence-interface` requirement `flake.lib.hostKeys holds every pinned host key and known_hosts reads only it`. Rests on world assumptions `A320 — clan reads a public var's value as the committed file, untrimmed, at a path fixed by machine, generator and file` and `A321 — The sshd service's host key generator is per machine and its public half is public`.

#### Scenario: A host connects to a NixOS host

- **WHEN** pyrite connects to magnetite over SSH
- **THEN** pyrite checks magnetite's host key against the key the fleet pins for magnetite, which is the same key pyrite trusted before this change

### Requirement: A host whose configuration presents a host key other than its pinned one fails before deploy

A host whose own configuration would present a host key other than the one the fleet pins for it SHALL fail to build, so that it cannot be deployed with a key the rest of the fleet does not trust.

**Discharged by**: the `host-configuration-independence-interface` requirement `Each NixOS host asserts that its generated host key equals its pinned key`. Darwin hosts are outside this discharge: macOS manages their host keys, and the fleet pins them by hand. Rests on world assumption `A321 — The sshd service's host key generator is per machine and its public half is public`.

#### Scenario: A host's key is regenerated but not committed

- **WHEN** a NixOS host's host key is regenerated and the key the fleet pins for it is left unchanged
- **THEN** that host's configuration fails to build, naming the host and the mismatch, and no deploy of it starts
