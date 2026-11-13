## ADDED Requirements

### Requirement: A signing key admits no login anywhere in the fleet

No host of the fleet SHALL hold a login authorization for the public key of any person's signing key, for any of its accounts, the administrator's account and the early-boot unlock shell included.
A person's signing key SHALL be a different key pair from every login key recorded in any person's profile.

**Discharged by**: `commit-signing-key-interface` requirements `A profile's signing key is none of the fleet's login keys`, `Every configured login source of a host is enumerated`, `A login source the enumeration cannot read fails closed` and `No login source on any host carries a signing key`.

#### Scenario: Cameron's signing key is offered for a login

- **WHEN** a login to the administrator's account on magnetite, or to Cameron's account on any host, is attempted with the private key of Cameron's signing key, after every host has deployed this change
- **THEN** the host refuses it, because no login authorization on that host names the signing key's public key

#### Scenario: A signing key is added to a person's login keys

- **WHEN** a person's signing key public key is added to the login keys recorded in any profile
- **THEN** the fleet's checks fail before the change that adds it can merge

### Requirement: No account only agents work under holds a key that admits a login

No account that only agents work under, an Omnigent worker's account or the hosted sandbox account of the ubuntu profile, SHALL be given a private key whose public key any host of the fleet holds a login authorization for.
An Omnigent worker SHALL be given, as its only signing credential, the private key of its owner's signing key.
An agent working under a person's own account holds whatever that account holds, and is not bounded by this requirement.

**Discharged by**: `commit-signing-key-interface` requirements `A worker's declared signing key is its owner's signing key` and `No login source on any host carries a signing key`, and the worker enrollment check observed after delivery.

#### Scenario: Cameron's worker on magnetite is inspected after the deploy

- **WHEN** magnetite has deployed this change and Cameron's Omnigent worker's signing key file is read under that worker's account
- **THEN** its public key is Cameron's signing key and not his login key, and the worker's enrollment check passes

#### Scenario: A worker is still given its owner's login key

- **WHEN** a worker's delivered private key is its owner's login key while its configuration declares the owner's signing key
- **THEN** the worker's enrollment check fails with a signing public key mismatch, and the worker does not become ready

### Requirement: Every commit is signed without interaction

Every commit in the local sense that a version-control tool records and signs under an account of the fleet, whether for the person working there or by an agent acting for that person, SHALL be signed with the private key of that person's signing key read from a file on that host, without any key agent being asked and without interaction.
The password vault's key agent SHALL serve logins only, and SHALL NOT be asked to sign any commit.

**Discharged by**: `commit-signing-key-interface` requirements `Every person's home signs with the signing key file`, `Every person's home signs through the agent-free program` and `The agent-free program never asks a key agent`, resting on world assumption `A93 — ssh-keygen signs through a key agent that holds the key, even when given a private key file`.

#### Scenario: Cameron commits on stibnite with the vault locked

- **WHEN** Cameron, or an agent working under his account on stibnite, records a commit with git and another with jj while the password vault is locked, after stibnite has deployed this change
- **THEN** both commits are signed with Cameron's signing key, and no unlock or authorization prompt appears

#### Scenario: An agent commits with no person present

- **WHEN** an Omnigent worker records a signed commit with jj on pyrite and no person is at pyrite
- **THEN** the commit is signed and recorded without waiting on any prompt

### Requirement: A person's commits are signed by their signing key under their author address

From the deploy of this change on a host, every signed commit recorded there for a person, by their account or by an Omnigent worker they own, SHALL be signed by that person's signing key, and the signer principal a verifier pairs with that key SHALL remain the person's author address.

**Discharged by**: `commit-signing-key-interface` requirements `Every person's home signs with the signing key file`, `The signers file lists the signing key and each retired key under the author address` and `A worker's declared signing key is its owner's signing key`, and the corpus requirement `The signer principal is the author address`.

#### Scenario: Janette's signed commit is verified on rosegold

- **WHEN** Janette's account on rosegold signs a commit after rosegold has deployed this change, and the same account then verifies it
- **THEN** the verifier accepts it for the signer principal `125711642+janetteasmith@users.noreply.github.com` and the public key of Janette's signing key

#### Scenario: A host has not yet deployed

- **WHEN** a host carrying a person's account has not deployed this change
- **THEN** commits recorded there are still signed by the retired key, which verifiers and the forge still accept until the cutover

### Requirement: A signing key opens no secret

The private key of a person's signing key SHALL NOT be the decryption identity of any secret the fleet keeps, so that an agent holding it can open no secret by holding it.

**Discharged by**: `commit-signing-key-interface` requirement `A signing key is no decryption identity`, resting on world assumption `A95 — ssh-to-age maps an ed25519 key pair to exactly one age identity`.

#### Scenario: A signing key is made a secret's recipient

- **WHEN** the age recipient derived from a person's signing key is added as a recipient of any secret the fleet keeps
- **THEN** the change that adds it fails its checks before it can merge

### Requirement: A forge marks every commit verified throughout the migration

From before the first host deploys a person's new signing key until after the last of their hosts and Omnigent workers has, every commit signed for a person with a forge account SHALL get the forge's verified mark when pushed, whichever key signed it.
A retired key's signing registration SHALL be removed only after all of them sign with the new key and every commit the retired key signed that is meant to be pushed has been pushed or re-signed.

**Discharged by**: no interface requirement; the operator registers each signing key before any host deploys it and removes each retired registration only after every host has, resting on world assumption `A94 — A forge's verified mark follows signing registrations and persists once given`; no check regulates a forge's registrations.

#### Scenario: A host deploys before the forge knows the new key

- **WHEN** a host deploys this change before the person's new signing key has a signing registration on their forge account
- **THEN** commits signed there and pushed lack the verified mark, and this requirement is violated

#### Scenario: A commit signed by the retired key is pushed after the cutover

- **WHEN** a commit signed by a retired signing key after the cutover is pushed once that key's signing registration has been removed
- **THEN** the forge gives it no verified mark

### Requirement: A commit signed before the cutover keeps verifying

A commit signed by a person's retired signing key whose claimed time precedes the cutover SHALL keep verifying with git under the person's author address, and SHALL keep the verified mark the forge gave it.
This requirement does not bound a holder of the retired key: a commit made after the cutover that claims an earlier time also verifies with git (assumption A91), and jj reports every signature of a retired key as of unknown principal once the cutover has passed (assumption A92).

**Discharged by**: `commit-signing-key-interface` requirement `The signers file lists the signing key and each retired key under the author address`, resting on world assumptions `A91 — git judges an SSH signature's validity at the time the commit claims`, `A92 — jj judges an SSH signature's validity at the time of verification` and `A94 — A forge's verified mark follows signing registrations and persists once given`.

#### Scenario: An old commit is verified with git after the cutover

- **WHEN** Cameron runs `git verify-commit` on a commit his login key signed before the cutover, on a host that has deployed phase B
- **THEN** git reports a good signature for `cameron.ray.smith@gmail.com`

#### Scenario: A retired key signs a new commit claiming the present time

- **WHEN** a commit signed by the retired login key after the cutover, claiming its true time, is verified with git on a host that has deployed phase B
- **THEN** git rejects the signature
