## ADDED Requirements

### Requirement: Every Mac attribute may end unproven, with its stall limit

Every attribute of `checks.aarch64-darwin` SHALL carry `allowUnproven`, the seconds of `flake.lib.testSizeLimits` for its aarch64-darwin `testSizes.checks` class (small 60, medium 300, large 900; 900 without an entry), SHALL NOT carry `ignoreFailure`, and SHALL keep its `drvPath`; no `checks.x86_64-linux` attribute SHALL carry `allowUnproven`.

**Discharged by**: `checks.x86_64-linux.nixbot-wiring`'s representative clause (a medium Mac check carries `allowUnproven = 300`, no `ignoreFailure`, and the same `drvPath` as its unmarked form; a Linux check carries no `allowUnproven`).

#### Scenario: The representative Mac check is evaluated

- **WHEN** `checks.x86_64-linux.nixbot-wiring` evaluates `self.checks.aarch64-darwin.darwin-stibnite`
- **THEN** it carries `allowUnproven = 300` and no `ignoreFailure`, and its `drvPath` equals the unmarked check's

#### Scenario: The marking regresses to ignoreFailure

- **WHEN** the module marks Mac checks with `ignoreFailure = true` instead
- **THEN** `nixbot-wiring` fails

#### Scenario: A Linux check

- **WHEN** `nixbot-wiring` evaluates a Linux representative
- **THEN** it carries no `allowUnproven`

### Requirement: nixbot delivers allowUnproven to its scheduler

nixbot's apply function SHALL deliver `allowUnproven` in each job's `extraValue`, and the job model SHALL expose it as `allow_unproven`, absent when the attribute does not carry it.

**Discharged by**: the apply case of `checks.x86_64-linux.nixbot-unproven-attributes`.

#### Scenario: A marked and an unmarked attribute are evaluated

- **WHEN** the apply function runs over one attribute with `allowUnproven = 300` and one without
- **THEN** the first job's `allow_unproven` is 300 and the second's is absent

### Requirement: A failed run is unproven only on positive evidence that no builder answered

For a job with `allow_unproven`, nixbot SHALL return `BuildOutcome.unproven` from a failed `nix build` only when its log carries no verdict line and carries the scheduler's stop, a `TRANSIENT_ERROR_MARKERS` entry after nixbot's one retry, or an entry of the built worktree's `unproven_markers`; with a verdict line it SHALL return `BuildOutcome.failure`, and with neither `BuildOutcome.unrecognised`.

**Discharged by**: the classification cases of `checks.x86_64-linux.nixbot-unproven-attributes` over log fixtures captured from magnetite's deployed Nix (a failing Mac check, a builder stopped before dispatch, a builder stopped mid-build), with a fail-open mutant (unproven unless a verdict line is found) that the cases must reject; nixbot's own executor tests in the patch, resting on world assumptions `A231 — Nix names the builder in its answer to a failed remote build, and gives the same exit status for a lost builder` and `A233 — An unreachable Mac builder is refused within its connection timeout and the derivation then fails locally for its platform`.

#### Scenario: A failure with no recognised marker

- **WHEN** an `allowUnproven` job fails and its log holds neither a verdict line nor any infrastructure marker
- **THEN** the outcome is `BuildOutcome.unrecognised`

#### Scenario: The fail-open mutant

- **WHEN** the check runs the cases against a classifier that returns unproven unless it finds a verdict line
- **THEN** the case with no recognised marker rejects the mutant

#### Scenario: The fail-closed baseline

- **WHEN** the check classifies, with an empty `unproven_markers`, each fixture whose only infrastructure evidence is one of the repository's markers
- **THEN** it is `unrecognised`, never `unproven` and never passed

#### Scenario: A Linux attribute's transport failure

- **WHEN** a job without `allow_unproven` fails with `Connection refused`
- **THEN** it is classified exactly as before this change

#### Scenario: The reason is kept

- **WHEN** a job is classified unproven
- **THEN** its reason is the last line of its log and its recorded error

### Requirement: A verdict line decides a failure

A verdict line SHALL be the build hook's `build of '<drv>' on '<builder>' failed:` whose reason is the builder's own failure, a timeout or a hash mismatch, and a failed run whose log carries one SHALL return `BuildOutcome.failure` whatever infrastructure markers the log also carries.

**Discharged by**: the classification cases of `checks.x86_64-linux.nixbot-unproven-attributes`, including build 2456's captured log.

#### Scenario: A log with a verdict line and a transport marker

- **WHEN** an `allowUnproven` job's log holds a verdict line for one derivation and `unexpected end-of-file` for another
- **THEN** the outcome is `BuildOutcome.failure`

### Requirement: Unrecognised is a failure recorded under its own status

`AttributeStatus.unrecognised` SHALL be in `TERMINAL_ATTRIBUTE_STATUSES`, `FAILED_ATTRIBUTE_STATUSES`, `TERMINAL_FAILURES` and `FAILED_STATUS_STATES`, with the failure's last error line as its error; `_finish_job` SHALL NOT cache it; and no repository setting, modifier or label SHALL make a build with an unrecognised attribute succeed.

**Discharged by**: the status cases of `checks.x86_64-linux.nixbot-unproven-attributes`, with a mutant that records unrecognised endings as `failed` and one that caches them, both of which the cases must reject.

#### Scenario: A build with one unrecognised Mac attribute

- **WHEN** nixbot aggregates a build whose only non-passing attribute is unrecognised
- **THEN** the build is `failed`, the attribute's status is `unrecognised`, and its per-attribute failure context's headline starts `unrecognised Mac ending:`

#### Scenario: Settings cannot waive it

- **WHEN** the same build is run with every `nixbot.toml` setting this change adds at its most permissive value that names no marker for the line
- **THEN** the build is still `failed`

### Requirement: The repository's markers classify infrastructure endings from the built worktree

nixbot SHALL read `unproven_markers` from the built worktree's `nixbot.toml`, and this repository's `nixbot.toml` SHALL list the deployed Nix's and nix-grpc-store's messages for an unreachable or lost builder, each covered by a case of `checks.x86_64-linux.nixbot-unproven-attributes` over a log captured from magnetite, classified with the file as committed.

**Discharged by**: the marker cases of `checks.x86_64-linux.nixbot-unproven-attributes`, which load this repository's `nixbot.toml`, with a mutant that reads the markers from the default branch instead of the worktree and one that ignores them.

#### Scenario: A marker is added in a pull request

- **WHEN** a pull request adds a marker and the fixture of the ending it names
- **THEN** the check fails at the parent commit's `nixbot.toml` and passes at the pull request's, and the pull request's own build classifies that ending as unproven

#### Scenario: A marker is mistyped

- **WHEN** a marker in `nixbot.toml` no longer matches its fixture, or the file no longer parses
- **THEN** the check fails

### Requirement: Unproven is a terminal outcome that is not a failure

`AttributeStatus.unproven` SHALL be in `TERMINAL_ATTRIBUTE_STATUSES` and in none of `TERMINAL_FAILURES`, `FAILED_ATTRIBUTE_STATUSES` or `FAILED_STATUS_STATES`, so that `aggregate_build` and `ScheduleResult.success` ignore it and no per-attribute failure context is posted for it.

**Discharged by**: the status cases of `checks.x86_64-linux.nixbot-unproven-attributes`; nixbot's scheduler and orchestrator tests in the patch.

#### Scenario: A build with one unproven Mac attribute and passing Linux attributes

- **WHEN** nixbot aggregates the build
- **THEN** the build is `succeeded`, and `nixbot/nix-build` is success

#### Scenario: A Linux job is classified unproven

- **WHEN** `outcome_status` receives an unproven outcome for a job without `allow_unproven`
- **THEN** it returns `failed`

#### Scenario: A job that must fail ends unproven

- **WHEN** a job with both `require_failure` and `allow_unproven` ends unproven
- **THEN** its status is `unproven`, never `succeeded`

### Requirement: nixbot never remembers an unproven outcome as a failure

`_finish_job` SHALL NOT add an unproven outcome to the failed-build cache, so that the next build containing the derivation runs it.

**Discharged by**: the cache case of `checks.x86_64-linux.nixbot-unproven-attributes`, with a mutant that caches unproven outcomes.

#### Scenario: The cache is enabled

- **WHEN** an `allowUnproven` job ends unproven with `cacheFailedBuilds` enabled
- **THEN** the failed-build cache holds no entry for its derivation and the next build runs it

### Requirement: A dependent inherits its dependency's kind of outcome

A job that cannot run because a dependency did not pass SHALL be recorded `dependency_failed` if any blocking dependency failed with a verdict; otherwise `unproven` if one is unproven and the job has `allow_unproven`, `dependency_failed` if one is unproven and it lacks it, and `cancelled` if all were cancelled; in whichever order the two arrive.

**Discharged by**: the dependency cases of `checks.x86_64-linux.nixbot-unproven-attributes` (settle-first and late-arrival forms of each row); nixbot's scheduler tests in the patch.

#### Scenario: A late-arriving dependent of an unproven attribute

- **WHEN** an `allowUnproven` job arrives in an evaluation batch after its dependency ended unproven
- **THEN** it is recorded `unproven` without being built

#### Scenario: A required dependent of an unproven attribute

- **WHEN** a job without `allowUnproven` depends on an attribute that ended unproven
- **THEN** it is recorded `dependency_failed` and the build fails

### Requirement: The build service stops a Mac attribute only for a stall or the deadline

nixbot SHALL stop no `allow_unproven` job while evaluation runs or any other job is unsettled; from then on it SHALL stop a running job once its time since its last progress, or since its start if it has made none, reaches its `allow_unproven` seconds, and every remaining one `unproven_deadline` seconds later, read from the built worktree's `nixbot.toml`.

**Discharged by**: the scheduler cases of `checks.x86_64-linux.nixbot-unproven-attributes` with timed fake executors (a progressing job outlives its stall limit; a silent job is stopped at its stall limit; a job silent for longer than its limit while a required job ran is stopped as soon as the required job settles; a progressing job is stopped at the deadline; nothing is stopped while a required job runs), with mutants that ignore progress and that ignore the deadline; nixbot's own scheduler tests in the patch; resting on world assumptions `A235 — Mac attributes under contention take several times their uncontended run`, `A236 — The merge queue gives up on a batch whose required checks have not reported within one hour` and `A237 — A Mac attribute queued for a busy builder makes no progress`.

#### Scenario: No deadline is configured

- **WHEN** the worktree's `nixbot.toml` sets no `unproven_deadline`
- **THEN** the stall rule alone applies

#### Scenario: The repository's setting

- **WHEN** this repository's `nixbot.toml` is read
- **THEN** it sets `unproven_deadline = 1200`, a non-empty `unproven_markers`, and no `optional_build_grace`

#### Scenario: A progressing medium Mac attribute

- **WHEN** only a medium `allowUnproven` job remains, it writes a log line every 30 s, and 600 s pass
- **THEN** it is still running

#### Scenario: A silent small Mac attribute

- **WHEN** only a small `allowUnproven` job remains and it has made no progress for 60 s
- **THEN** it is stopped and recorded `unproven` with `no progress for 60 s`

#### Scenario: The deadline

- **WHEN** `allowUnproven` jobs are still progressing `unproven_deadline` seconds after only they remained
- **THEN** each is stopped and recorded `unproven` with `not finished by the deadline`, and the build finishes

### Requirement: Progress is a builder's work on the attribute

Progress SHALL be a build activity starting or stopping, a build log line, or a phase change in the job's `nix build` output, and Nix's waiting-for-a-machine activity SHALL NOT be progress.

**Discharged by**: the progress cases of `checks.x86_64-linux.nixbot-unproven-attributes` over the captured fixtures, resting on world assumptions `A232 — Nix's structured build log names the builder that accepted each derivation` and `A237 — A Mac attribute queued for a busy builder makes no progress`.

#### Scenario: The queued fixture

- **WHEN** the executor reads the fixture captured with every stibnite slot held
- **THEN** the job's last-progress time does not advance

### Requirement: A stopped Mac attribute ends unproven with its reason

A job stopped by the stall rule SHALL end `unproven` with `no progress for <N> s`, one stopped by the deadline with `not finished by the deadline`, and one never started by the deadline with `not started by the deadline`, while a build-level cancel SHALL stay `cancelled`.

**Discharged by**: the scheduler cases of `checks.x86_64-linux.nixbot-unproven-attributes`; nixbot's orchestrator tests in the patch.

#### Scenario: A superseded build

- **WHEN** a build is cancelled because a newer push supersedes it while an `allowUnproven` job runs
- **THEN** the job is `cancelled`, not `unproven`

### Requirement: The build summary names unproven and unrecognised attributes

The `nixbot/nix-build` summary SHALL read `<N> attributes built, <M> unproven: <names>` when any attribute is unproven, and SHALL begin with `unrecognised Mac ending: <name>: <line>` for each unrecognised attribute, naming attributes without the `checks.<system>.` prefix and truncating after the summary's length budget with `and <K> more`; with neither it SHALL read as before.
The build table SHALL show both outcomes with their own labels and positions.

**Discharged by**: the summary cases of `checks.x86_64-linux.nixbot-unproven-attributes`; nixbot's status tests in the patch.

#### Scenario: Two unproven attributes

- **WHEN** a build succeeds with 330 attributes built and `darwin-stibnite` and `home-manager-crs58` unproven
- **THEN** the summary reads `330 attributes built, 2 unproven: darwin-stibnite, home-manager-crs58`

#### Scenario: One unrecognised attribute

- **WHEN** a build fails because `darwin-stibnite` ended unrecognised with the error line `error: some new transport wording`
- **THEN** the summary begins `unrecognised Mac ending: darwin-stibnite: error: some new transport wording`

### Requirement: The readiness report names unproven and unrecognised attributes

`gh-queue-open-prs` SHALL read the `nixbot/nix-build` check run's summary for each pull request it reports and append to that pull request's verdict line `unproven: <names>` and each `unrecognised Mac ending: <name>: <line>` the summary carries, without changing the verdict or the authorization decision.

**Discharged by**: a new `checks.x86_64-linux.gh-queue-open-prs` that runs the script in `--dry-run` with a stub `gh` serving recorded answers (a green pull request with unproven attributes, one without, a failing one with an unrecognised ending, one whose check run has no summary) and compares its output with the expected lines, including a mutant script that drops the suffixes, which the comparison must reject.

#### Scenario: A green pull request with unproven attributes

- **WHEN** `gh-queue-open-prs -n` reports a pull request whose required checks passed and whose summary names `darwin-stibnite` as unproven
- **THEN** its line reads `green` and ends with `unproven: darwin-stibnite`

#### Scenario: A failing pull request with an unrecognised ending

- **WHEN** `gh-queue-open-prs -n` reports a pull request whose build failed because `darwin-stibnite` ended unrecognised with `error: some new transport wording`
- **THEN** its line reads `failing` and ends with `unrecognised Mac ending: darwin-stibnite: error: some new transport wording`

### Requirement: The modifier costs no measurable evaluation

Marking every Mac attribute with `allowUnproven` SHALL leave `NIX_SHOW_STATS` allocation of `nix eval .#checks.aarch64-darwin --apply builtins.attrNames` and nixbot's evaluation time of one commit within their run-to-run variation, measured three times before and after.

**Discharged by**: the recorded measurement in `logs/` before the cutover pull request merges.

#### Scenario: The measurement is read

- **WHEN** the three runs before and after are compared
- **THEN** the difference in each is within the spread of the runs before

### Requirement: The classification markers are pinned by live probes against the deployed Nix

After deployment, and after any change of Nix or nix-grpc-store on magnetite or stibnite, three probes SHALL be run on throwaway pull requests and recorded: a deliberately failing Mac check with stibnite awake, which must fail `nixbot/nix-build`; stibnite's builder service stopped before the build, which must leave the Mac attributes `unproven` and `nixbot/nix-build` success; and the builder service stopped mid-build, which must do the same within minutes.

**Discharged by**: the recorded probe logs; resting on world assumption `A231 — Nix names the builder in its answer to a failed remote build, and gives the same exit status for a lost builder`, whose violation condition these probes observe.

#### Scenario: A Nix bump rewords the hook's answer

- **WHEN** after a Nix bump the deliberately failing Mac check leaves `nixbot/nix-build` green, or a stopped builder turns it red
- **THEN** the classification markers are updated from the new logs before the next merge that relies on them
