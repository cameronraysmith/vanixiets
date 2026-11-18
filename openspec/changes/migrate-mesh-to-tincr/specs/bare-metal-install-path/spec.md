## REMOVED Requirements

### Requirement: ZeroTier admission requires redeploying the controller

**Reason**: The fleet's overlay network no longer has a controller or an `allowedIps` list; a machine is admitted by being declared an overlay member, and every other member learns it at its next deploy.

**Migration**: Follow `Overlay admission requires redeploying every member`: declare the machine in the member registry, deploy every other host, then rely on the new machine.

## ADDED Requirements

### Requirement: Overlay admission requires redeploying every member

pyrite SHALL be admitted to the overlay network by being declared an overlay member, and SHALL be treated as a member only after every other host has been deployed with that declaration.
pyrite's overlay address SHALL follow from its name alone, so it is known before pyrite is ever installed.

#### Scenario: a declared member needs no hand admission

- **WHEN** pyrite is declared an overlay member
- **THEN** no person admits it by hand on any other host, because each host learns pyrite's key and overlay address from the declaration at its next deploy

#### Scenario: the address is knowable before the machine exists

- **WHEN** pyrite's declaration is evaluated before installation
- **THEN** its overlay address and canonical name are known, and the post-install records can be prepared in advance

#### Scenario: redeploying every member is an explicit step

- **WHEN** pyrite's declaration is committed and pyrite is installed
- **THEN** every other host is deployed before pyrite is relied on, because a host not yet deployed refuses pyrite's overlay address
