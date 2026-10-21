# shared-reference-tree Specification

## Purpose
This capability (stratum: `behavioral`) states what the fleet requires of reference repositories on a host that shares them: one reference tree per participating host, read by every participating account, changed only by the writer, extended on request without a person, readable by no other account, leaving every private home private, and introduced without losing anyone's existing copies, moving only an administrator's copies in place.

## Requirements

### Requirement: Every participating account reads one reference tree per host

On each host the operator declares as sharing its reference tree, every participating account SHALL read reference repositories from that host's one reference tree, so that a reference repository present for one participating account is present for all of them.
The discharge of this requirement depends on assumption A35.

#### Scenario: A reference repository is added for one account

- **WHEN** a reference repository is added to a host's reference tree as a result of one participating account's acquisition request
- **THEN** every other participating account on that host can read the same reference repository in the same reference tree without acquiring it again

#### Scenario: A host is not declared as sharing its reference tree

- **WHEN** a host is not among those the operator declares as sharing a reference tree
- **THEN** each account on that host keeps its reference repositories in its own private home exactly as before

### Requirement: Only the writer changes the reference tree

On each sharing host, the writer SHALL be the only account that can add, alter or remove anything within the reference tree, including any repository-local setting of any reference repository in it, so that no participating account can act as another participating account by way of the reference tree.
The writer SHALL be an account no person and no agent works under.
The discharge of this requirement depends on assumption A34.

#### Scenario: A participating account tries to change a reference repository

- **WHEN** a participating account attempts to add, alter or remove anything within the reference tree, including a repository-local setting of a reference repository there
- **THEN** the attempt is refused, and the reference tree is unchanged

#### Scenario: An agent's account and its owner's account share a host

- **WHEN** an agent works under a participating account and the person it acts for works under another participating account on the same host
- **THEN** nothing the agent can do to the reference tree lets it act as the person's account when that person later reads a reference repository

### Requirement: A missing reference repository can be requested without a person

A participating account SHALL be able to make an acquisition request for a reference repository the reference tree lacks, or to refresh or deepen one it holds, and the writer SHALL carry out a well-formed acquisition request without a person intervening.
An acquisition request SHALL NOT let the requesting account choose anything the writer does beyond which reference repository is acted on and whether it is added, refreshed or deepened.

#### Scenario: A participating account needs a reference repository the tree lacks

- **WHEN** a participating account makes an acquisition request for a reference repository absent from the reference tree
- **THEN** the reference repository appears in the reference tree, written by the writer, and is readable by every participating account on that host

#### Scenario: An acquisition request asks for more than adding, refreshing or deepening

- **WHEN** an acquisition request names anything beyond a reference repository and whether to add, refresh or deepen it
- **THEN** the writer refuses it and the reference tree is unchanged

### Requirement: Only participating accounts can read the reference tree

On each sharing host, an account that is neither a participating account nor the writer SHALL NOT be able to read the reference tree.

#### Scenario: An account outside the declared set looks for the reference tree

- **WHEN** an account on a sharing host that the operator has not declared as participating attempts to read a reference repository in the reference tree
- **THEN** the attempt is refused

### Requirement: Sharing the reference tree leaves every private home private

Introducing the shared reference tree SHALL NOT make any account's private home readable by any other account.

#### Scenario: A participating account reads the reference tree

- **WHEN** a participating account reads reference repositories from the shared reference tree
- **THEN** it gains no access to any other account's private home, and its own private home remains unreadable by the writer and by every other participating account

### Requirement: Moving per-account copies into the reference tree loses nothing and is reversible

Moving a host to the shared reference tree SHALL bring an administrator's per-account copies into the reference tree as they are, without acquiring them again, and SHALL lose no per-account copy: where two administrators hold the same reference repository, the one not kept SHALL be set aside in its account's private home, unaltered.
A per-account copy of any account that is not an administrator SHALL NOT be brought into the reference tree; it SHALL be set aside in that account's private home, unaltered and still its own, and each reference repository it held SHALL be acquirable again through an acquisition request.
Until the operator explicitly authorizes deleting what was set aside, the move SHALL be reversible for each account.
Before the move, the operator SHALL be shown every per-account copy holding history or a changed file that exists nowhere else, because after the move the account that made it can no longer change it.
The discharge of this requirement depends on assumption A36.

#### Scenario: A host moves to the shared reference tree

- **WHEN** a host is moved to the shared reference tree
- **THEN** every reference repository each administrator held is present in the reference tree or set aside in that account's private home, and none had to be acquired again

#### Scenario: An account that is not an administrator is moved

- **WHEN** a host is moved to the shared reference tree and an account that is not an administrator holds per-account copies
- **THEN** none of them is in the reference tree, all of them are set aside in that account's private home, unaltered, and the operator is shown how each is acquired again

#### Scenario: A per-account copy holds history or a changed file that exists nowhere else

- **WHEN** a per-account copy holds changes or history not present at its upstream
- **THEN** it is listed to the operator before the move, and it is moved or set aside as it is rather than lost

#### Scenario: The move is reversed for one account

- **WHEN** the operator reverses the move for one account before authorizing any deletion
- **THEN** that account again holds its per-account copies, as they were, in its private home

#### Scenario: The operator authorizes deletion

- **WHEN** the operator explicitly authorizes deleting what was set aside for one account on one host
- **THEN** only that account's set-aside copies on that host are deleted
