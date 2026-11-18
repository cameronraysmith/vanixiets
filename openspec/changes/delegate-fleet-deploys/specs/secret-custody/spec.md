## MODIFIED Requirements

### Requirement: The operator identity can read every secret file

The operator identity SHALL be a reader of every secret file in the repository, so that the operator can maintain any file's readers without the recovery key, and no key other than the operator identity, the recovery key, the deployer's key for the machine keys of deployable hosts, and the keys of the persons, hosts and automated runners that use a file SHALL be a reader of it.

#### Scenario: The operator re-applies readers to another person's secrets
- **WHEN** the operator re-applies the reader rules to a secret file holding another person's secrets
- **THEN** the file is recovered with the operator identity alone, and the person still recovers it with their personal key

#### Scenario: The operator re-applies readers to a deployable host's machine key
- **WHEN** the operator re-applies the readers of a deployable host's machine key
- **THEN** the file is recovered with the operator identity alone, and the deployer still recovers it with its own key

## ADDED Requirements

### Requirement: The deployer reads only the machine keys of the hosts it deploys

The deployer's key SHALL be a reader of the machine key, and of the secrets a host needs before its configuration takes effect, of every deployable host, and of no other secret file. No person's personal key other than the operator identity, and no request credential, SHALL be a reader of any machine key.

**Discharged by**: `secret-custody-interface` requirement `The correspondence check compares the deployer's reach with the deploy targets`, resting on world assumption `A155 — A host's machine key opens every secret meant for that host`.

#### Scenario: the deployer's key is tried on stibnite's machine key
- **WHEN** the deployer's key is used to read stibnite's or blackphos's machine key, an operator credential, or a secret shared among hosts
- **THEN** the secret is not recovered

#### Scenario: the deployer's key is tried on argentum's machine key
- **WHEN** the deployer's key is used to read argentum's machine key
- **THEN** the machine key is recovered
