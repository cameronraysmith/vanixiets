## ADDED Requirements

### Requirement: The flake-input updater runs twice a week and on demand

The flake-input updater SHALL start a run every Tuesday and every Friday at 22:00 UTC, and the operator SHALL be able to start a run by hand.

**Discharged by**: the `flake-input-refresh-interface` requirement `The scheduled update is declared from the repository with a fixed schedule`; resting on world assumptions `A122 — nixbot registers a schedule only after a successful default-branch build, and runs each occurrence from that branch's tip` and `A123 — nixbot runs a scheduled occurrence only within five minutes of its time, and never catches one up`.

#### Scenario: A scheduled time arrives

- **WHEN** Tuesday or Friday 22:00 UTC arrives while the service that runs the flake-input updater is up
- **THEN** a run starts within five minutes

#### Scenario: The operator starts a run by hand

- **WHEN** the operator starts a run outside the schedule
- **THEN** the run proposes the same update pull requests a scheduled run at that moment would

#### Scenario: The build service is down at the scheduled time

- **WHEN** the scheduled time passes while the service that runs the flake-input updater is down for longer than five minutes
- **THEN** no run takes place for that occurrence, and the inputs are proposed by the next scheduled run or by a run the operator starts by hand

### Requirement: Each moved branch-tracking flake input gets an update pull request of its own

In each run, every branch-tracking flake input whose tracked branch has moved since the repository's lock file recorded it SHALL be proposed in an update pull request of its own, whose commit changes only that input's entry in the lock file.
A failure to refresh one input SHALL NOT prevent the others from being proposed in the same run, and the run SHALL report that it failed and which inputs failed.

**Discharged by**: the `flake-input-refresh-interface` requirement `The update script runs one input at a time with fixed arguments`; resting on world assumption `A125 — nixbot's flakeUpdate with perInput rebuilds each input's branch from the base and continues past a failed input`.

#### Scenario: A run finds several inputs moved

- **WHEN** a run starts while three branch-tracking flake inputs have moved
- **THEN** three update pull requests exist afterwards, one per input, and each one's commit changes only that input's entry in the lock file

#### Scenario: One input cannot be refreshed

- **WHEN** refreshing one branch-tracking flake input fails during a run in which other inputs have moved
- **THEN** the other inputs' update pull requests are still opened or updated, and the run is reported as failed naming the input that failed

### Requirement: The flake-input updater leaves the Playwright flake input and pinned flake inputs alone

The flake-input updater SHALL NOT propose an update of the Playwright flake input, and SHALL NOT propose an update of a flake input whose declaration pins a revision or a tag, so that each flake input has exactly one updater.

**Discharged by**: the `flake-input-refresh-interface` requirement `The update script runs one input at a time with fixed arguments` for the Playwright flake input; world assumption `A127 — nix flake update leaves an input pinned by revision or tag at the revision it locks` for pinned inputs.

#### Scenario: The Playwright flake input's branch moves

- **WHEN** a run takes place while the Playwright flake input could be re-locked to a newer revision
- **THEN** no update pull request from the flake-input updater changes the Playwright flake input's entry in the lock file

#### Scenario: A pinned flake input is in the lock file

- **WHEN** a run takes place and a flake input's declaration pins a revision or a tag that has not been moved upstream
- **THEN** no update pull request from the flake-input updater exists for that input

### Requirement: Each branch-tracking flake input has at most one open update pull request, and a stale one is withdrawn

At any time the repository SHALL have at most one open update pull request from the flake-input updater per branch-tracking flake input.
A run in which an input has not moved since its open update pull request was last pushed SHALL push nothing to that pull request's branch, and a run in which the repository has already caught up with an input SHALL remove that input's update branch.

**Discharged by**: the `flake-input-refresh-interface` requirement `The update script runs one input at a time with fixed arguments`; resting on world assumption `A125 — nixbot's flakeUpdate with perInput rebuilds each input's branch from the base and continues past a failed input`.

#### Scenario: Two runs see the same revision

- **WHEN** two consecutive runs find the same new revision for an input
- **THEN** the second run pushes nothing to that input's branch, and the input still has exactly one open update pull request

#### Scenario: An input moves again before its pull request merges

- **WHEN** an input with an open update pull request moves again before the next run
- **THEN** the next run replaces that pull request's commit with one locking the newer revision, and no second pull request is opened for the input

#### Scenario: The repository already has the update

- **WHEN** a run finds that the repository's lock file already records the newest revision of an input that still has an update branch
- **THEN** that branch is removed, which closes its pull request

### Requirement: The flake-input updater acts under its own forge application with expiring credentials

Every branch, commit and pull request the flake-input updater writes SHALL be attributed to its own forge application, and each run SHALL push with a forge credential minted for that run that expires within one hour.
The build service's own forge credential SHALL NOT be able to write the repository's contents.

**Discharged by**: the `flake-input-refresh-interface` requirements `A run mints its own installation token from the application key` and `Commits carry the forge application's bot identity`; resting on world assumptions `A124 — nixbot delivers a scheduled effect exactly the secrets its map names, and any default-branch effect may name any repository secret` and `A126 — GitHub reports an App's installation to the App's own token, and pull requests an App opens reach other Apps' webhooks`.

#### Scenario: A run opens a pull request

- **WHEN** a run opens an update pull request
- **THEN** the forge shows the pull request opened by the flake-input updater's forge application, and its commit authored and committed by that application's bot user

#### Scenario: A credential from a run is replayed later

- **WHEN** a forge credential used by a run is presented to the forge more than one hour after the run minted it
- **THEN** the forge refuses it

#### Scenario: The build service's credential is used to push

- **WHEN** the build service's own forge credential is used to push a branch to the repository
- **THEN** the forge refuses the push

### Requirement: Merge authorization for flake-input updates stays with people

The flake-input updater SHALL NOT give merge authorization for any update pull request it opens; each one SHALL wait for a person to give it before the merge queue lands it.

**Discharged by**: the `flake-input-refresh-interface` requirement `The update script runs one input at a time with fixed arguments`.

#### Scenario: A run opens update pull requests

- **WHEN** a run opens or updates update pull requests
- **THEN** none of them carries merge authorization unless a person gave it

### Requirement: Flake-input refreshes use no hosted runner

No run of the flake-input updater SHALL consume a hosted runner.

**Discharged by**: the `flake-input-refresh-interface` requirement `No hosted workflow refreshes flake inputs`.

#### Scenario: The schedule fires

- **WHEN** a scheduled time arrives
- **THEN** the forge records no hosted-runner job for the repository that refreshes flake inputs
