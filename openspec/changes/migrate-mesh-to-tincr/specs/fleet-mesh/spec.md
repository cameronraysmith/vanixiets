## ADDED Requirements

### Requirement: Every overlay member reaches every fleet service by its canonical name

Every overlay member, whether a NixOS host, a darwin host or a phone, SHALL reach every service the fleet offers to overlay members, and every other overlay member, by its canonical name over the overlay network, with that name answered by the overlay network's name service.
This rests on world assumptions A128 and, for phones and darwin hosts, A133 and A134.

#### Scenario: A NixOS host reaches a service by name

- **WHEN** a person on pyrite opens `https://ntfy.vanixiets.internal`
- **THEN** the name resolves to cinnabar's overlay address, the connection travels over the overlay network, and the notification service answers

#### Scenario: A darwin host reaches a member by name

- **WHEN** the operator on stibnite connects to `magnetite.vanixiets.internal`
- **THEN** the name resolves to magnetite's overlay address and the connection travels over the overlay network

#### Scenario: A phone reaches a service by name

- **WHEN** a person on an enrolled phone opens `https://ntfy.vanixiets.internal` while connected to the overlay network
- **THEN** the name resolves through the overlay network's name service and the notification service answers

#### Scenario: One name service is down

- **WHEN** either cinnabar's or magnetite's name service stops answering
- **THEN** every overlay member still resolves every canonical name through the other

### Requirement: Members behind address-translating routers reach each other without a coordinating host

Two overlay members that are both online SHALL reach each other while any one host of the fleet is absent, including when both members sit behind address-translating routers; they SHALL reach each other directly when their routers allow it, and through another overlay member when they do not.
This rests on world assumption A130.

#### Scenario: Two laptops behind different routers

- **WHEN** pyrite and a darwin host are each behind an address-translating router on different networks and both are online
- **THEN** each reaches the other's canonical name, and the operator records whether the path is direct or through another member

#### Scenario: cinnabar is down

- **WHEN** cinnabar is powered off and magnetite is online
- **THEN** two other online members keep reaching each other and magnetite's name service keeps answering

### Requirement: Only members the operator declares are admitted, each only at its own overlay address

The overlay network SHALL admit only overlay members the operator has declared, and a member SHALL be reachable at and send from only the overlay address the operator's declaration gives it, so that no member can take over another member's overlay address.
This rests on world assumption A131.

#### Scenario: An undeclared device tries to join

- **WHEN** a device whose key the operator has not declared connects to a member
- **THEN** no member carries traffic to or from it

#### Scenario: A member claims another member's address

- **WHEN** an admitted member advertises another member's overlay address
- **THEN** no other member routes that address to it

### Requirement: The fleet declares each overlay member once

Adding, renaming or removing an overlay member SHALL be one declaration by the operator, from which the member's canonical name, its overlay address and every way the fleet reaches or deploys to it follow, and every host SHALL apply it at its next deploy without any other record of the member being edited.

#### Scenario: A host is added

- **WHEN** the operator declares a new host as an overlay member and deploys every host
- **THEN** the new host has a canonical name, an overlay address and a recovery path class, every other member reaches it by name, and the operator edited no other record of it

#### Scenario: A record is edited by hand

- **WHEN** a host's canonical name or overlay address appears in the fleet's configuration other than as derived from its declaration
- **THEN** that is a defect, found by the review of the change that introduced it

### Requirement: The chat service is identified by its canonical name

The fleet's chat service SHALL identify every person, bot and room it holds under `matrix.vanixiets.internal`, and every service that talks to it SHALL name its rooms and people under that name.
This rests on world assumption A129.

#### Scenario: A bot posts to its home room

- **WHEN** hermes posts a scheduled result to its home room
- **THEN** the room's identifier ends in `:matrix.vanixiets.internal` and the post arrives

### Requirement: Each remotely administered host has a recovery path

Every host the operator administers remotely SHALL have a recovery path, and the fleet SHALL state for each host which one it is: for a host with a public address, a connection to that address and its provider's console; for pyrite, which runs unattended work, a path that reaches it behind an address-translating router; for any other laptop, the person at the machine.

#### Scenario: The overlay network fails on a cloud server

- **WHEN** a deploy leaves magnetite unreachable over the overlay network
- **THEN** the operator redeploys magnetite through its public address and its overlay membership returns

#### Scenario: The overlay network fails on another person's laptop

- **WHEN** a deploy leaves blackphos unreachable over the overlay network
- **THEN** its primary user, following the fleet's written steps, starts the laptop's previous configuration and the operator reaches it again

#### Scenario: The overlay network fails on pyrite while no person is with it

- **WHEN** pyrite, behind an address-translating router, is unreachable over the overlay network
- **THEN** the operator reaches pyrite over its recovery path and repairs it, as shown once before the previous overlay network is retired

### Requirement: The overlay network is the fleet's only private network

Once the operator approves the cutover, every overlay member SHALL use only the overlay network for the fleet's private traffic, every deploy SHALL travel over it or a recovery path, and no host and no phone in use SHALL keep the previous overlay network's software, names or addresses.

#### Scenario: The previous network is retired

- **WHEN** retirement has been deployed to every host and pixel11
- **THEN** no host, and not pixel11, runs the previous overlay network's software or holds its names or addresses, and every service is still reached by its canonical name; pixel7, a phone kept out of use, loses the previous overlay network when its controller is retired whether or not its software is removed
