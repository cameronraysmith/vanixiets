## ADDED Requirements

### Requirement: The dependency updater proposes updates on a fixed schedule

The fleet SHALL run a dependency updater on magnetite that, every two hours, looks for newer releases of the dependencies the forge-hosted repository `cameronraysmith/vanixiets` declares and proposes each update it is configured to make as an update pull request, and SHALL propose no update to any other repository.
A run SHALL end before its forge credential expires, and SHALL push at most four commits, so that the build service's evaluation load from one run stays bounded.

**Discharged by**: `dependency-update-interface` requirement `The updater runs on a fixed schedule within a bounded envelope`, resting on world assumption `A107 — A GitHub App installation token expires an hour after issue and reaches only the installation's repositories`.

#### Scenario: An upstream release appears

- **WHEN** a dependency the repository declares gains a newer release the repository's rules permit
- **THEN** within one scheduled run, about two hours and ten minutes at most, an update pull request for it exists or it is listed on the dependency dashboard as pending, held, or deferred by the per-run limit

#### Scenario: A run approaches the hour

- **WHEN** a run is still working fifty-five minutes after it started
- **THEN** it is stopped, and the next scheduled run starts with a new forge credential and resumes from the repository's state

### Requirement: The updater acts under its own forge identity with expiring credentials

The dependency updater SHALL act on the forge only through its own forge application, distinct from the build service's and the merge queue's and installed on this repository alone, with a forge credential minted for each run that expires within an hour.
No update task SHALL be able to read the application key, and every commit the updater adds SHALL be shown by the forge as verified and attributed to its forge application.

**Discharged by**: `dependency-update-interface` requirements `The application key is read only by a privileged pre-start step` and `The forge application holds a fixed permission set over this repository alone`, resting on world assumptions `A107 — A GitHub App installation token expires an hour after issue and reaches only the installation's repositories` and `A108 — Renovate commits through the forge's API under an App identity, and the forge signs those commits`.

#### Scenario: An update commit is inspected on the forge

- **WHEN** a person opens a commit on an update pull request
- **THEN** the forge shows it as verified and authored by the updater's forge application, not by a person, the hosted updater, or a workflow bot

#### Scenario: An update task tries to read the application key

- **WHEN** an update task, which runs repository-controlled code, attempts to read the application key during a run
- **THEN** the key is not reachable from the task, and the most the task can obtain is the current run's forge credential, which reaches only this repository and expires within the hour

### Requirement: Every pushed update commit is a consistent commit

Every commit the dependency updater pushes SHALL be a consistent commit, so that the build service's check runs on an update pull request's first push are not failed by inconsistency and no follow-up commit is needed.
A change to a flake input's declaration SHALL carry the re-locked flake lock file, and a change to the bun lock file SHALL carry its regenerated nix projection, in the same commit.

**Discharged by**: `dependency-update-interface` requirements `Update tasks are attached per dependency kind in the repository's configuration`, `Update task commands are admitted by the allowlist, and a check ties the repository's commands to it`, and `The tools on the updater's path match the repository's declarations`, resting on world assumptions `A109 — Renovate runs post-upgrade tasks between its own artifact updates and the commit, runs only allowlisted commands, and still commits when a task fails`, `A110 — Renovate replaces rather than merges a rule's post-upgrade tasks, and applies global rules before the repository's`, `A111 — Renovate runs a task command without a shell and passes it only PATH and HOME`, and `A114 — magnetite's nix daemon serves every local account and trusts only root and wheel`.

#### Scenario: A flake input's version reference is bumped

- **WHEN** the updater proposes moving a version-pinned flake input to a newer release
- **THEN** the update pull request's single commit changes that input's declaration and the flake lock file together, and the build service's evaluation of that first push resolves the new release

#### Scenario: A bun dependency is updated

- **WHEN** the updater proposes an update of a dependency declared for the bun workspace
- **THEN** the update pull request's single commit changes the declaration, the bun lock file, and the bun lock file's nix projection together

#### Scenario: An update task fails during a run

- **WHEN** an update task is refused by the allowlist or exits with an error
- **THEN** the updater still pushes the branch, under A109, with a comment on the update pull request naming the lock file problem; this requirement is unmet for that commit, and the failure is visible on the pull request rather than repaired by another identity's follow-up commit

### Requirement: The npm Playwright pin is derived from the Playwright flake input

The dependency updater SHALL NOT propose an update of the npm Playwright pin on its own.
Whenever it proposes an update of the Playwright flake input, the same commit SHALL set the npm Playwright pin to the driver version that input provides at the new release, reconcile the bun lock file, and regenerate its nix projection.

**Discharged by**: `dependency-update-interface` requirement `Update tasks are attached per dependency kind in the repository's configuration`, resting on world assumptions `A109 — Renovate runs post-upgrade tasks between its own artifact updates and the commit, runs only allowlisted commands, and still commits when a task fails` and `A110 — Renovate replaces rather than merges a rule's post-upgrade tasks, and applies global rules before the repository's`.

#### Scenario: The Playwright flake input gains a release

- **WHEN** the updater proposes moving the Playwright flake input to a newer release
- **THEN** the update pull request's single commit changes the input's declaration, the flake lock file, the npm Playwright pin, the bun lock file and its nix projection, and the npm Playwright pin at that commit equals the input's driver version at that commit

#### Scenario: npm publishes a Playwright release first

- **WHEN** the npm Playwright packages gain a release before the Playwright flake input does
- **THEN** no update pull request moves the npm Playwright pin, and the pin moves only with the flake input

### Requirement: Merge authorization stays with people

The dependency updater SHALL NOT give merge authorization for its own update pull requests, and SHALL hold no bypass of the repository's required checks or branch rules.
An update pull request SHALL land only after a person gives merge authorization and the merge queue's required checks pass.

**Discharged by**: `dependency-update-interface` requirements `The forge application holds a fixed permission set over this repository alone` and `The updater neither labels for the queue nor enables auto-merge`.

#### Scenario: An update pull request passes its checks

- **WHEN** an update pull request's required check runs all pass
- **THEN** it stays open and unqueued until a person gives merge authorization

### Requirement: Each dependency has exactly one updater, and one Renovate instance writes to the repository

Each dependency of the repository SHALL be proposed for update by exactly one dependency updater, and at any time at most one Renovate instance SHALL write branches, pull requests, comments or a dependency dashboard to the repository.
Before the fleet's dependency updater first writes to the repository, the hosted updater SHALL have stopped writing to it, and the hosted updater's open update pull requests, their branches and its dependency dashboard SHALL have been closed.

**Discharged by**: operator procedure at cutover, not by a machine property, for the single Renovate instance; the `dependency-update-interface` requirement `Update tasks are attached per dependency kind in the repository's configuration` together with the nix manager's lock file maintenance staying off, for the split of flake inputs between updaters; resting on world assumption `A112 — Renovate leaves a branch another author wrote, and recognizes only dashboard issues it created`.

**Reworded, 2026-11-17**: this requirement first read "Exactly one dependency updater writes to the repository". By operator decision of 2026-11-17, refreshes of branch-tracking flake inputs stay with a second dependency updater, the GitHub Actions flake updater, which a separate change replaces with nixbot's `flakeUpdate` effect. Renovate and that updater write disjoint sets of dependencies: Renovate takes the flake inputs pinned by revision or tag, the other updater the branch-tracking ones. The invariant that matters is therefore one updater per dependency, plus one Renovate instance.

#### Scenario: The fleet's updater begins writing

- **WHEN** the fleet's dependency updater's first non-dry run writes to the repository
- **THEN** no branch, pull request, comment or dependency dashboard written by the hosted updater after that moment exists, and a new dependency dashboard authored by the fleet's updater replaces the old one

#### Scenario: The hosted updater is left running

- **WHEN** the hosted updater is still writing to the repository when the fleet's updater starts writing
- **THEN** this requirement is violated: under A112 each updater skips the other's branches and the two dashboards diverge, so the cutover is incomplete until the hosted updater is stopped and its state closed

#### Scenario: Two updaters propose the same flake input

- **WHEN** a Renovate pull request changes the locked revision of a branch-tracking flake input, or the flake-input updater changes a flake input pinned by revision or tag
- **THEN** this requirement is violated, because one dependency then has two updaters whose pull requests conflict

### Requirement: The fleet's updater is observed in a dry run before it first writes

The fleet's dependency updater SHALL be run as a dry run against the repository, with its update tasks running and each would-be commit's files recorded, and that record SHALL be read by the operator before the updater's first run that writes to the forge.

**Discharged by**: `dependency-update-interface` requirement `A full dry run writes nothing to the forge and records each would-be commit`, resting on world assumption `A113 — A full dry run performs artifact updates and tasks and writes nothing to the forge`, together with operator procedure.

#### Scenario: The dry run shows an incomplete commit

- **WHEN** the dry run's record shows a would-be commit for a flake input bump without the flake lock file, or for a bun update without the bun lock file's nix projection, or an update task refused by the allowlist
- **THEN** the updater is not allowed to write to the forge until the cause is corrected and a new dry run shows complete commits
