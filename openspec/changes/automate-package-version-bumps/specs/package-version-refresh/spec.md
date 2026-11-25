## Purpose

Keeping each package built from a pinned upstream release current without a person running a script: every new stable release is proposed in an update pull request of its own, with every digest the package needs already derived and checked, and a person still decides whether it merges.

## ADDED Requirements

### Requirement: Each new stable release of a package with a package pin is proposed in an update pull request of its own

For every package whose package pin the dependency updater reads, a release of that package's upstream that is newer than the release the package pin records SHALL be proposed in an update pull request that proposes no other package.
While that update pull request is open, a still newer release SHALL replace the proposal in the same update pull request rather than open a second one.

**Discharged by**: the `package-version-refresh-interface` requirements `One custom manager reads every package pin and names the package` and `The pin rule fixes the branch, the task and the update window`; resting on world assumptions `A226 — Renovate 44.247.1 ships the jsonata custom manager and custom datasources` and `A229 — Renovate proposes only releases newer than the current one, and no unstable release over a stable one`.

#### Scenario: An upstream publishes a new release

- **WHEN** the upstream of a package with a package pin publishes a stable release newer than the one the package pin records, and the dependency updater runs inside the update window
- **THEN** an update pull request for that package alone exists afterwards, proposing that release

#### Scenario: The upstream publishes again before the pull request merges

- **WHEN** a package's update pull request is open and its upstream publishes a newer stable release
- **THEN** the next run inside the update window moves that update pull request to the newer release, and no second update pull request exists for the package

### Requirement: Package updates never move a package to an older release, or from a stable release to an unstable release

The dependency updater SHALL NOT propose a release older than the one a package pin records, and SHALL NOT propose an unstable release for a package whose package pin records a stable release.

**Discharged by**: world assumption `A229 — Renovate proposes only releases newer than the current one, and no unstable release over a stable one`, together with the `package-version-refresh-interface` requirement `The pin rule fixes the branch, the task and the update window`, which sets no rule that admits unstable releases.

#### Scenario: The upstream publishes a release candidate

- **WHEN** the upstream of a package whose package pin records a stable release publishes an unstable release newer than it
- **THEN** no update pull request proposes the unstable release

#### Scenario: An upstream withdraws its newest release

- **WHEN** an upstream withdraws the release a package pin records, so that its newest remaining release is older
- **THEN** no update pull request proposes the older release, and the operator decides by hand whether to move the package back

### Requirement: Every pushed package update commit is a consistent commit

Every commit the dependency updater pushes for a package update SHALL be a consistent commit as pushed: the package pin SHALL record the proposed release, every artifact's digest SHALL be the digest of that release's artifact for its platform, and every companion file of the package SHALL agree with that release.
No package update SHALL need a follow-up commit or an instruction to a person to become consistent.

**Discharged by**: the `package-version-refresh-interface` requirements `The realizer realizes one version of one package, total over every source and artifact kind`, `The realizer writes only the package pin and the files its typed companions name` and `The pin rule fixes the branch, the task and the update window`; resting on world assumptions `A228 — Renovate compiles a post-upgrade command as a template, admits it only through allowedCommands, and passes the task no forge credential` and `A230 — An upstream's checksum file states the digests of the artifacts it publishes for that release`.

#### Scenario: A package with a companion file is updated

- **WHEN** the dependency updater pushes an update of a package that declares a companion file
- **THEN** the pushed commit carries the package pin, its digests and the companion file for the same release, and the repository's required checks that compare them pass without another commit

#### Scenario: A package publishes binaries for several platforms

- **WHEN** the dependency updater pushes an update of a package used on four platforms
- **THEN** the package pin in the pushed commit records, for each of the four platforms, the digest of that platform's artifact of the proposed release

### Requirement: An update that cannot be completed never lands with a stale digest

When the digests or companion files for a proposed release cannot be determined, the update pull request SHALL show that the update failed, and its required checks SHALL fail rather than pass with a digest from an earlier release.

**Discharged by**: the `package-version-refresh-interface` requirements `The realizer leaves every file as it was when it fails or runs out of time` and `Every package pin is validated when the flake is evaluated`; resting on world assumption `A228 — Renovate compiles a post-upgrade command as a template, admits it only through allowedCommands, and passes the task no forge credential`, and on the build service refusing an artifact whose digest does not match its package pin.

#### Scenario: The upstream's checksum file is missing

- **WHEN** a release's checksum file cannot be fetched while the dependency updater prepares an update
- **THEN** the update pull request carries a comment from the dependency updater saying the update failed, and the build service fails the required check that builds the package

### Requirement: A malformed package pin fails a required check before it can merge

A package pin that names no upstream, no release, an artifact kind or source kind the repository does not define, a platform without a digest, or a file outside the package's own directory that no companion entry names SHALL fail a required check of any pull request that contains it.

**Discharged by**: the `package-version-refresh-interface` requirements `Every package pin is validated when the flake is evaluated`, `A file outside the package's directory changes only through a typed companion entry` and `The pin contract and the realizer are each guarded by a small check with a declared size class`.

#### Scenario: A pin loses a platform's digest

- **WHEN** a pull request changes a package pin so that one platform the package is used on has no digest
- **THEN** a required check of that pull request fails naming the package and the missing platform

### Requirement: Each package has exactly one updater

A package whose package pin the dependency updater reads SHALL have no other updater: no script or recipe in the repository SHALL propose or rewrite that package's release, and the flake-input updater SHALL never change its package pin.

**Discharged by**: the `package-version-refresh-interface` requirement `A migrated package keeps no updater of its own`.

#### Scenario: A package migrates

- **WHEN** a package's package pin is first read by the dependency updater
- **THEN** the same commit removes the package's own update script and its entry in the repository's list of update commands

### Requirement: Package update pull requests open only inside the update window, and in bounded numbers

The dependency updater SHALL open or update a package's update pull request only inside the update window, Monday and Thursday from 14:00 to 17:59 UTC.
It SHALL open at most two such update pull requests in any clock hour and SHALL keep at most six open at once.
The update window SHALL share no hour with the flake-input updater's runs, Tuesday and Friday, or with the daily deletion of unused build outputs from magnetite's binary cache, at 04:00 New York time.

**Discharged by**: the `package-version-refresh-interface` requirement `The pin rule fixes the branch, the task and the update window`; resting on world assumption `A227 — Renovate 44.247.1 honours schedule and limits inside a package rule and counts them across the repository`, and on the `dependency-update-interface` requirement `The updater runs on a fixed schedule within a bounded envelope`.

#### Scenario: A release appears outside the window

- **WHEN** an upstream publishes a new release on a Tuesday
- **THEN** no update pull request for it opens and no open one is updated before the next Monday or Thursday at 14:00 UTC

#### Scenario: Many packages have new releases at once

- **WHEN** ten packages with package pins have new stable releases at the start of a window
- **THEN** at most two of their update pull requests are opened per clock hour, and no more than six are open at any time

### Requirement: Merge authorization for package updates stays with people

The dependency updater SHALL NOT give merge authorization for any package update pull request; each one SHALL wait for a person to give it before the merge queue lands it.

**Discharged by**: the `package-version-refresh-interface` requirement `The pin rule fixes the branch, the task and the update window`, which sets no automerge and no queue label, and the `dependency-update-interface` requirement `The updater neither labels for the queue nor enables auto-merge`.

#### Scenario: A package update pull request is opened

- **WHEN** the dependency updater opens or updates a package's update pull request
- **THEN** it carries no merge authorization unless a person gave it
