## ADDED Requirements

### Requirement: A commit names the person it is recorded for

Every commit in the local sense recorded under an account on a host of the fleet, whether by the person who works under that account or by an agent acting for that person, SHALL name that person as its author, with the author name and author address recorded in that person's profile in the person sense, whichever version-control tool records it.
An Omnigent worker acts for its owner, so a commit an Omnigent worker records SHALL name its owner.
This requirement holds only while no author setting held for the repository or in the environment displaces the account's own, and its discharge depends on assumption A85.

**Discharged by**: `commit-author-identity-interface` requirements `One rule derives an author from a profile`, `Every home sets git and jj author from one non-empty pair`, `A worker's author is its owner's profile, set by the host` and `Every Linux worker's author is regulated against its owner's profile`, resting on world assumption `A85 — Repository and environment author settings take precedence over account settings`.

#### Scenario: Cameron records commits under both of his accounts

- **WHEN** Cameron records one commit with git and one with jj under the account `crs58` on stibnite, and one of each under the account `cameron` on magnetite, after both hosts have deployed this change
- **THEN** all four commits carry the author name `Cameron Smith` and the author address `cameron.ray.smith@gmail.com`

#### Scenario: A person whose jj author was empty records a commit

- **WHEN** Raquel, Tara, Christopher or the ubuntu account's person records a commit with jj under their own account on a host that has deployed this change
- **THEN** the commit carries the same non-empty author name and author address their git commits carry, not an empty name or an empty address

#### Scenario: Omnigent workers for two people record commits on one host

- **WHEN** the Omnigent worker whose owner is Cameron and the Omnigent worker whose owner is Janette each record a commit with jj on magnetite
- **THEN** Cameron's worker's commit carries `Cameron Smith` and `cameron.ray.smith@gmail.com`, Janette's worker's commit carries `Janette Smith` and `125711642+janetteasmith@users.noreply.github.com`, and neither carries the other person's author

#### Scenario: An author setting held for the repository differs

- **WHEN** a repository on a host holds its own author setting that differs from the account's
- **THEN** commits recorded in that repository carry the repository's author, and this requirement is not met there

### Requirement: No commit is recorded with an empty author name

No commit in the local sense recorded under an account on a host of the fleet, by a person or by an Omnigent worker, SHALL carry an empty author name, so that every such commit can be pushed to a forge-hosted repository.
A person whose profile records an empty personal name SHALL have no configuration for any of their accounts or Omnigent workers that can be deployed.
The discharge of this requirement depends on assumption A84.

**Discharged by**: `commit-author-identity-interface` requirements `Every home sets git and jj author from one non-empty pair` and `Every Linux worker's author is regulated against its owner's profile`, resting on world assumption `A84 — jj refuses to push a commit recorded while user.name was empty, until the commit is re-authored`.

#### Scenario: Cameron's worker pushes a commit

- **WHEN** the Omnigent worker whose owner is Cameron records a commit with jj on magnetite after magnetite has deployed this change, and pushes it to a forge-hosted repository
- **THEN** the push is not refused for an absent author

#### Scenario: A profile's personal name is emptied

- **WHEN** a profile's personal name is changed to the empty string
- **THEN** the configuration of every host carrying an account or an Omnigent worker of that person is refused before any deploy, and no commit is recorded with that empty name

#### Scenario: A commit was recorded before the host deployed

- **WHEN** a commit was recorded while the account's author setting held an empty author name, before its host deployed this change
- **THEN** that commit remains unpushable until it is re-authored, even after its host has deployed and the author setting holds a name

### Requirement: A person's commits carry their author address, not their sign-in address

A person's commits SHALL carry the author address recorded in their profile even where that person's sign-in address differs from it, and the person's Omnigent workers SHALL still be expected to sign in to Omnigent under the sign-in address.

**Discharged by**: `commit-author-identity-interface` requirements `One rule derives an author from a profile` and `The sign-in address is unchanged`.

#### Scenario: Janette's author address differs from her sign-in address

- **WHEN** Janette, whose sign-in address is `janette.a.smith@gmail.com` and whose author address is `125711642+janetteasmith@users.noreply.github.com`, records a commit under her own account on rosegold, or her Omnigent worker records one on pyrite
- **THEN** the commit carries `125711642+janetteasmith@users.noreply.github.com`, and her worker's expected sign-in identity remains `janette.a.smith@gmail.com`

#### Scenario: Author address and sign-in address coincide

- **WHEN** a person's profile records no separate author address
- **THEN** their commits carry their sign-in address as the author address

### Requirement: A person's signed commits verify against their author address

Where a person's account or Omnigent worker signs commits, the signer principal recorded beside that person's public key SHALL be the author address their commits carry, so that a verifier on that account accepts the signature of a commit it records.

**Discharged by**: `commit-author-identity-interface` requirement `The signer principal is the author address`.

#### Scenario: Janette's signed commit is verified

- **WHEN** Janette's account on rosegold signs a commit and then verifies its signature
- **THEN** the verifier accepts it for the signer principal `125711642+janetteasmith@users.noreply.github.com`

#### Scenario: The signer principal is the sign-in address

- **WHEN** the signer principal recorded for Janette is `janette.a.smith@gmail.com` while her commits carry her author address
- **THEN** the verifier finds no principal matching the commit's author, and this requirement is violated

### Requirement: An Omnigent worker runs only for a person with a profile

The fleet SHALL NOT run an Omnigent worker whose owner is not a person with a profile in the person sense, and every Omnigent worker's identity SHALL come from its owner's profile and from nothing else.

**Discharged by**: `commit-author-identity-interface` requirements `A worker's owner is a profile key` and `A worker's author is its owner's profile, set by the host`.

#### Scenario: A worker is declared for someone without a profile

- **WHEN** a host declares an Omnigent worker whose owner is a name with no profile
- **THEN** that host's configuration is refused before any deploy

#### Scenario: A worker's owner is named by the newer account name

- **WHEN** an Omnigent worker's owner is `cameron`, the account name newer hosts use for the person whose older account name is `crs58`
- **THEN** the worker takes Cameron's profile, and its commits carry the same author as Cameron's own commits under either account

### Requirement: A change to a profile reaches every account of that person at its host's next deploy

A change to the personal name or author address in a person's profile SHALL change the author of every commit recorded afterwards for that person, by each of their accounts and Omnigent workers, from the next deploy of the host that account or worker is on, with no other edit.

**Discharged by**: `commit-author-identity-interface` requirements `One rule derives an author from a profile`, `Every home sets git and jj author from one non-empty pair` and `A worker's author is its owner's profile, set by the host`.

#### Scenario: Janette's author address changes

- **WHEN** only the author address in Janette's profile changes, and rosegold, magnetite and pyrite then deploy
- **THEN** commits recorded afterwards by her account on rosegold and by her Omnigent workers on magnetite and pyrite carry the new address, and her signer principal on each is the new address

#### Scenario: A host has not yet deployed

- **WHEN** a person's profile changes and one host carrying their account has not deployed since
- **THEN** commits recorded on that host still carry the previous author until it deploys
