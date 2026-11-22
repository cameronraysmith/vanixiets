## MODIFIED Requirements

### Requirement: One closure defines the environment

Each environment snapshot SHALL hold one closure of this repository and record its commit.
Unless the operator pins one closure, it SHALL be the closure of the newest of the main branch's 5 newest commits that the binary cache already holds.
The setup step SHALL only fetch and activate a closure, never build one, and its text SHALL NOT change with new commits.
While pinned, the setup step SHALL be renewed at least every 30 days.

#### Scenario: Two sessions on one closure

- **WHEN** two cloud sessions start from environment snapshots that hold the same closure
- **THEN** they receive the same user context, skill corpus and required tools

#### Scenario: Updating the environment

- **WHEN** a commit on the main branch changes what cloud sessions receive and the binary cache holds its closure
- **THEN** the next environment snapshot of a cloud environment that is not pinned holds that closure, with no change to the setup step

#### Scenario: A month without changes

- **WHEN** 30 days pass since a pinned setup step was last renewed
- **THEN** the setup step has been regenerated and swapped, so its closure is still in the fleet's binary cache; a cloud environment that is not pinned needs no renewal

#### Scenario: The newest commit is not yet published

- **WHEN** an environment snapshot is made after a commit reaches the main branch and before the binary cache holds its closure
- **THEN** the snapshot holds the closure of the newest earlier commit, among the 5 newest, that the binary cache holds, and its bootstrap report names the commit used, its distance from the newest and why each newer commit was skipped

#### Scenario: None of the 5 newest commits is published

- **WHEN** the binary cache holds the closure of none of the main branch's 5 newest commits
- **THEN** the cloud session still starts, without the profile, and its bootstrap report says so; this risk is accepted

## ADDED Requirements

### Requirement: Sessions report how far behind the main branch they are

At each start, a cloud session SHALL record in its bootstrap report its closure's commit, how far that commit was behind the main branch's newest commit when the environment snapshot was made, and whether the main branch has moved on since.
Recording it SHALL change nothing else: the session SHALL keep the closure of its environment snapshot.

#### Scenario: A session behind the main branch

- **WHEN** a cloud session starts from an environment snapshot made two commits behind the main branch's newest commit, and the main branch has moved on since
- **THEN** its bootstrap report records the distance two and that the main branch has moved on, and the session runs that snapshot's closure

### Requirement: Every input source stays in the binary cache

Every change to this repository's flake inputs SHALL leave the input source of every flake input in the fleet's binary cache, so that a cloud session can follow the main branch without fetching any input source through the GitHub gate.

#### Scenario: A lock change lands

- **WHEN** a commit that changes the flake inputs reaches the main branch and the build service has published its outputs
- **THEN** the binary cache holds every input source of that commit's flake inputs
