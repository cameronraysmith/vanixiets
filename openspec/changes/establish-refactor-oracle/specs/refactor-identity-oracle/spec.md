## ADDED Requirements

### Requirement: A refactor changes no derivation it did not declare

A refactor SHALL leave the derivation of every host's configuration, every home configuration, every check and every runtime test of the fleet the same at its candidate commit as at its base commit, except for the declared differences it names before it is accepted.

#### Scenario: A neutral refactor

- **WHEN** a refactor that names no declared difference is compared at its base and candidate commits
- **THEN** every host's configuration, home configuration, check and runtime test has the same derivation at both commits, and the refactor may be accepted on that ground

#### Scenario: An undeclared difference

- **WHEN** the comparison finds a host's configuration, home configuration, check or runtime test whose derivation differs and which the refactor did not name as a declared difference
- **THEN** the refactor is not accepted until the difference is removed or named, with its reason, as a declared difference

#### Scenario: A host, home configuration, check or runtime test appears or disappears

- **WHEN** one exists at only one of the two commits and the refactor did not name its addition or removal as a declared difference
- **THEN** the refactor is not accepted, as for any undeclared difference

#### Scenario: A check built from every file of the repository

- **WHEN** a check's derivation takes the whole repository as an input, so that its derivation differs between any two commits
- **THEN** it is a declared difference named once, as uncertain, for every refactor, and no refactor names it again

### Requirement: A declared difference happens

A refactor SHALL NOT be accepted while a declared difference it names as certain did not occur between its base and candidate commits; a declared difference named as uncertain SHALL be reported whether or not it occurred.

#### Scenario: A declared difference is absent

- **WHEN** a refactor names a check's derivation as one it changes and the comparison finds that derivation unchanged
- **THEN** the refactor is not accepted until it either makes the change or withdraws the declared difference

### Requirement: A failure to evaluate is a difference only when it is new

The comparison SHALL treat a host's configuration, home configuration, check or runtime test whose derivation cannot be computed at both commits as unchanged and list it, and SHALL treat one that can be computed at only one commit as a difference.

#### Scenario: Broken at both commits

- **WHEN** a check's derivation cannot be computed at either commit
- **THEN** the check is listed as failing at both and does not by itself prevent acceptance

#### Scenario: Broken by the refactor

- **WHEN** a check's derivation is computed at the base commit and cannot be computed at the candidate commit
- **THEN** the check is a difference, and the refactor is not accepted unless it names that check as a declared difference

### Requirement: An evaluation-cost claim rests on alternating cost measurements against a recorded baseline

A claim that a refactor changes the evaluation cost of a host's configuration, a home configuration, a check, a runtime test or the set of check names SHALL be accepted only when that cost was taken as cost measurements at the base and the candidate commits in alternation, at least two at each commit, on one host with one evaluator, with every cost measurement and its conditions recorded, and when the cost measurements at each commit agree with each other and those of the two commits separate.

#### Scenario: One cost measurement at each commit

- **WHEN** a cost claim rests on one cost measurement at each commit
- **THEN** the claim is not accepted until the alternating cost measurements are made

#### Scenario: Measured under different conditions

- **WHEN** a cost claim compares a figure with a baseline measured by another evaluator or on another host
- **THEN** the claim is not accepted; a change of evaluator or host starts a new baseline

### Requirement: Baselines are recorded where later changes can read them

The fleet SHALL keep, in the repository, the evaluation-cost baseline of each host's configuration, check or set of check names that a planned refactor claims to make cheaper, each with the commit, host, evaluator and conditions it was measured under.

#### Scenario: A later change cites a cost point

- **WHEN** a refactor claims to reduce the evaluation cost of a host's configuration
- **THEN** the baseline it compares against is found in the repository with its conditions, not only in a log on one person's machine
