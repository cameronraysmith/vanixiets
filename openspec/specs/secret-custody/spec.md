# secret-custody Specification

## Purpose
Who can read the fleet's secrets, and how the keys that grant that reading are kept true to the people and hosts they name. Operator credentials are readable by the operator alone, retired hosts read nothing, every host can read what it delivers, a darwin host is not activated without its machine key, keys are provisioned without leaving private material in the working tree, and the documentation describes only current procedures. Behavioral stratum; `secret-custody-interface` states the properties that discharge it.

## Requirements

### Requirement: Operator credentials are readable only by the operator

Every secret file holding operator credentials SHALL have as its readers only the operator identity and the recovery key.
No person other than the operator, and no host, SHALL be a reader of such a file.

#### Scenario: A person who is not the operator holds their personal key
- **WHEN** a person other than the operator tries to read a secret file holding operator credentials with their personal key
- **THEN** the secret is not recovered

#### Scenario: The operator reads operator credentials
- **WHEN** the operator reads a secret file holding operator credentials with the operator identity
- **THEN** every credential in it is recovered

### Requirement: The operator identity can read every secret file

The operator identity SHALL be a reader of every secret file in the repository, so that the operator can maintain any file's readers without the recovery key, and no key other than the operator identity, the recovery key, and the keys of the persons, hosts and automated runners that use a file SHALL be a reader of it.

#### Scenario: The operator re-applies readers to another person's secrets
- **WHEN** the operator re-applies the reader rules to a secret file holding another person's secrets
- **THEN** the file is recovered with the operator identity alone, and the person still recovers it with their personal key

### Requirement: No retired host is a reader of any secret file

No key belonging to a retired host, or to a host's earlier hardware, SHALL be a reader of any secret file in the repository.
When a host is retired or rehomed, its earlier keys SHALL be removed from every secret file's readers before the change that retires it is accepted.

#### Scenario: A host is rehomed to new hardware
- **WHEN** the earlier hardware's host key is still a reader of some secret file
- **THEN** the change that rehomes it is reported as failing when pushed, naming that key

### Requirement: Narrowing a secret file's readers keeps every reader still in use and renews its protection

When a secret file's readers are narrowed, every person, host or automated runner that still reads that file SHALL remain a reader, and the file SHALL be re-protected so that a removed reader cannot recover any secret written to it afterwards.
Narrowing readers SHALL NOT be taken as revoking a removed reader's access to the file's earlier contents, which history retains.

#### Scenario: A file's readers are narrowed
- **WHEN** a reader is removed from a secret file
- **THEN** each person, host or automated runner that still uses the file still recovers its secrets, and the removed reader cannot recover the file's current contents

#### Scenario: A removed reader holds an earlier commit
- **WHEN** a removed reader reads the file as it was in a commit from before the narrowing
- **THEN** those earlier contents are recovered, which is the residual exposure the operator accepted by not rotating the credentials

### Requirement: Every public key the repository names corresponds to the person or machine it names

Every public key the repository names as a reader for a person, a host's machine key, or a host's host key SHALL be the public half of the key that person or host holds as the repository itself records it elsewhere, and every reader named for secret files SHALL be accounted for as belonging to a person, a host, an automated runner, or the recovery key.
A disagreement SHALL be detected when the change that introduces it is pushed, without access to the key store.

#### Scenario: A person's login key changes without their reader being updated
- **WHEN** the repository records a new public key for a person and still names the old reader for them
- **THEN** the change is reported as failing when pushed, naming that person

#### Scenario: A reader is added that belongs to no one the repository knows
- **WHEN** a reader is named that is not accounted for as a person, host, automated runner or the recovery key
- **THEN** the change is reported as failing when pushed, naming that reader

### Requirement: Every host can read the personal keys it delivers to its users

A host that delivers a person's personal key to that person at activation SHALL be a reader of the secret file holding that personal key.

#### Scenario: A host is added that delivers a personal key it cannot read
- **WHEN** a host is configured to deliver a personal key from a secret file it is not a reader of
- **THEN** the change that configures it is reported as failing before any host is changed, naming the host and the file

### Requirement: A darwin host is not activated without its machine key

A darwin host for which the repository holds a machine key SHALL NOT be activated by the operator's activation command unless the host holds that machine key.
When it does not, activation SHALL stop before changing the host and SHALL tell the operator the command that installs the machine key.

#### Scenario: The host has never received its machine key
- **WHEN** the operator activates a darwin host whose machine key is absent from the host
- **THEN** activation stops before any change and names the command that installs the machine key on that host

#### Scenario: The host holds a different machine key
- **WHEN** the machine key on the host is not the one the repository records for it
- **THEN** activation stops before any change and names the same remedy

#### Scenario: The host has no machine key in the repository
- **WHEN** the operator activates a darwin host for which the repository holds no machine key
- **THEN** activation proceeds without this condition

### Requirement: Provisioning a key never leaves a private key in the repository's working tree

No maintenance tool SHALL write a private key, unprotected, to any path inside the repository's working tree, including transiently and including when the tool fails part-way.

#### Scenario: Protecting the key fails part-way
- **WHEN** a provisioning tool fails after reading a private key and before protecting it
- **THEN** no file in the working tree contains that private key

### Requirement: A workstation's personal key is derived from the person's SSH key in the key store

There SHALL be exactly one convention for a person's personal key on a workstation: it is derived from that person's SSH key pair held in the key store, so the same personal key results on every workstation the person uses.
No maintenance tool or documented procedure SHALL generate an unrelated personal key for a person.

#### Scenario: A person sets up a second workstation
- **WHEN** the person follows the documented procedure on a new workstation
- **THEN** the personal key on it equals the one on their first workstation, and its public half equals the reader the repository names for them

### Requirement: No maintenance tool rewrites readers or host identities from an external source

No maintenance tool SHALL rewrite the repository's reader rules, a workstation's personal-key file, or a host's host key from the key store or any other source outside the repository.
Changing readers or keys SHALL be a documented procedure the operator performs, after which the correspondence of every named public key is confirmed when the change is pushed.

#### Scenario: The operator rotates a person's reader
- **WHEN** the operator follows the documented rotation procedure
- **THEN** the only changes are to the repository files the procedure names, and the change is not reported as failing correspondence

### Requirement: The documentation describes only current procedures

The fleet's documentation of secrets SHALL describe only the arrangement and procedures that work against the repository as it is, and SHALL NOT instruct a person to run a tool that no longer exists or to use a file, field or key-store item that does not exist.
Historical decision records MAY describe earlier arrangements when they are marked as superseded where the arrangement has changed.

#### Scenario: A reader follows a documented secrets procedure
- **WHEN** a person performs any procedure the documentation gives for secrets
- **THEN** every command, path, field and item it names exists
