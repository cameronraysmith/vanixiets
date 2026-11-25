## ADDED Requirements

### Requirement: A Mac attribute's failing verdict blocks the merge

When a Mac builder runs a Mac attribute's work and answers that it failed, the build service SHALL record the attribute as failed and the build as failed, so that the pull request or batch carrying it does not pass its required checks, exactly as for an attribute built on Linux.
An attribute that fails because a Mac attribute it depends on received a failing verdict SHALL fail the same way.

**Discharged by**: `mac-check-outcomes-interface` requirements `A failed run is unproven only on positive evidence that no builder answered`, `A verdict line decides a failure`, `Unproven is a terminal outcome that is not a failure` and `A dependent inherits its dependency's kind of outcome`, resting on world assumptions `A231 — Nix names the builder in its answer to a failed remote build, and gives the same exit status for a lost builder` and `A232 — Nix's structured build log names the builder that accepted each derivation`; the deliberately broken Mac check of the live probe discharges it.

#### Scenario: A Mac check is broken on purpose

- **WHEN** a pull request adds a Mac attribute whose builder exits non-zero, and a Mac builder is awake
- **THEN** the build fails, the attribute's check run reports the failure with the builder's log, and the merge queue does not land the pull request

#### Scenario: A Mac regression such as build 2456's

- **WHEN** a Mac builder builds a dependency of several Mac attributes and its builder exits 1
- **THEN** the dependency's attribute fails, the attributes that depend on it fail through it, and the build fails

#### Scenario: The failure comes from the Mac's own environment

- **WHEN** the Mac builder answers with a failure that its own disk or cache directory caused
- **THEN** the attribute still fails, because nothing in the answer separates it from a failure the change caused, and a rebuild after the Mac is repaired clears it

### Requirement: A Mac attribute without a verdict is unproven and never blocks a merge

When a Mac attribute ends without a verdict, because no Mac builder was reachable, none took the work, the builder was lost while building it, or the build service stopped waiting for it, the build service SHALL record its outcome as unproven together with the reason, SHALL NOT count it as failed or as passed, and SHALL NOT let it change whether the build, its required checks or the merge pass.

**Discharged by**: `mac-check-outcomes-interface` requirements `Every Mac attribute may end unproven, with its stall limit`, `nixbot delivers allowUnproven to its scheduler`, `A failed run is unproven only on positive evidence that no builder answered` and `Unproven is a terminal outcome that is not a failure`, resting on world assumptions `A233 — An unreachable Mac builder is refused within its connection timeout and the derivation then fails locally for its platform` and `A234 — A Mac builder that sleeps mid-build is noticed by the connection's keepalive within minutes`; the stopped-builder probes discharge it.

#### Scenario: stibnite is asleep when the build starts

- **WHEN** a pull request is built while no Mac builder answers
- **THEN** each Mac attribute ends unproven with the reason that no builder was reachable, the build's required checks pass if the Linux attributes pass, and the build finishes as soon as the Linux attributes settle

#### Scenario: stibnite sleeps in the middle of a build

- **WHEN** the Mac builder stops answering after it has accepted a Mac attribute's work
- **THEN** the attribute ends unproven with the reason that the builder was lost, within minutes rather than at the build service's three-hour limit

#### Scenario: A Mac attribute expected to fail ends without a verdict

- **WHEN** a Mac attribute declared to pass only by failing ends without a verdict
- **THEN** it is unproven, never passed

### Requirement: The build service waits for a Mac attribute while a Mac builder makes progress on it

Once every attribute other than the Mac attributes has settled, the build service SHALL keep waiting for a Mac attribute while a Mac builder makes progress on it, and SHALL stop waiting and record it unproven when it has made no progress for as long as its size class allows one run, or when the build's deadline after that moment has passed.
The build service SHALL NOT stop a Mac attribute while any other attribute is unsettled.

**Discharged by**: `mac-check-outcomes-interface` requirements `Every Mac attribute may end unproven, with its stall limit`, `The build service stops a Mac attribute only for a stall or the deadline`, `Progress is a builder's work on the attribute` and `A stopped Mac attribute ends unproven with its reason`, resting on world assumptions `A235 — Mac attributes under contention take several times their uncontended run`, `A236 — The merge queue gives up on a batch whose required checks have not reported within one hour` and `A237 — A Mac attribute queued for a busy builder makes no progress`; the scheduler cases of the repository check discharge it.

#### Scenario: A burst like 2026-11-24's

- **WHEN** the Linux attributes of a pull request settle while stibnite is still building that pull request's machine checks and printing their progress
- **THEN** the build keeps waiting for them and records their verdicts, up to the deadline

#### Scenario: A Mac attribute queued behind a full builder

- **WHEN** the Linux attributes have settled and a small Mac attribute has made no progress for 60 s because every slot on stibnite is taken
- **THEN** it ends unproven with the reason that it made no progress, and the build finishes

#### Scenario: The deadline passes with Mac attributes still working

- **WHEN** Mac attributes are still making progress when the build's deadline after the Linux attributes settled passes
- **THEN** they end unproven with the reason that they were not finished by the deadline, and the build finishes within the merge queue's time for a batch

### Requirement: An unproven Mac attribute is named wherever a person reads readiness

An unproven Mac attribute SHALL be named, with the count of unproven attributes, on the pull request's build check run, on the commit of the main branch that carries the build, and in the readiness report a person reads before merge authorization, without changing whether that report calls the pull request ready.

**Discharged by**: `mac-check-outcomes-interface` requirements `The build summary names unproven and unrecognised attributes` and `The readiness report names unproven and unrecognised attributes`; the fixture of the readiness report and the summary test discharge it.

#### Scenario: The operator reads the readiness report after the burst

- **WHEN** a pull request's build passed with two Mac attributes unproven
- **THEN** the readiness report calls it ready and names the two attributes as unproven

#### Scenario: The pull request lands

- **WHEN** a pull request whose build had unproven Mac attributes lands on the main branch through a fast-forward that reuses its build
- **THEN** the main branch's commit carries the same summary naming them

### Requirement: An unproven Mac attribute is built again by the next build that contains it

The build service SHALL NOT remember an unproven attribute's derivation as failed, so that the next build containing the same derivation, of any pull request, batch or the main branch, builds it again and records a verdict when a Mac builder answers.
No alert SHALL be raised because a Mac attribute is unproven.

**Discharged by**: `mac-check-outcomes-interface` requirements `Unproven is a terminal outcome that is not a failure` and `nixbot never remembers an unproven outcome as a failure`; the cache case of the repository check discharges it.

#### Scenario: The next build after stibnite wakes

- **WHEN** a derivation that was unproven in one build appears in a later build while stibnite is awake
- **THEN** it is built, and a failing verdict then fails that later build as any failure would

#### Scenario: stibnite is away for a week

- **WHEN** every build for a week has unproven Mac attributes
- **THEN** no alert is raised, and each build's summary and the readiness report name them

### Requirement: A dependent inherits its dependency's kind of outcome

An attribute that cannot be built because an attribute it depends on did not pass SHALL take that dependency's kind of outcome: failed when the dependency received a failing verdict, unproven when the dependency is unproven and the dependent may be unproven, and failed when the dependency is unproven and the dependent may not.

**Discharged by**: `mac-check-outcomes-interface` requirement `A dependent inherits its dependency's kind of outcome`; its scheduler cases discharge it.

#### Scenario: A Mac attribute depends on one whose builder was lost

- **WHEN** a Mac attribute depends on another whose builder was lost
- **THEN** both are unproven, and the build is not failed by either

#### Scenario: One dependency failed and another is unproven

- **WHEN** a Mac attribute depends on two attributes, one with a failing verdict and one unproven
- **THEN** it fails, because a verdict among its dependencies decides it

### Requirement: Telling the outcomes apart adds no evaluation

Distinguishing a verdict from an unproven outcome SHALL NOT add evaluation to a build beyond reading one declared value per Mac attribute, and the build service's evaluation of a commit SHALL stay within its run-to-run variation.

**Discharged by**: `mac-check-outcomes-interface` requirement `The modifier costs no measurable evaluation`; the recorded measurement discharges it.

#### Scenario: The evaluation is measured before and after

- **WHEN** the Mac attributes' names and modifiers are evaluated before and after the change, and the build service evaluates the same commit under each
- **THEN** the allocation and the evaluation time differ by no more than their run-to-run variation

### Requirement: A Mac failure of unrecognised cause blocks and is recorded apart

When a Mac attribute fails and its log holds neither a builder's answer nor a message known to mean that no builder answered, the build service SHALL record an unrecognised ending, with the failure's last error text, under an outcome distinct from a failing verdict, and SHALL fail the build as for a failing verdict, so that such endings can be found and counted.

**Discharged by**: `mac-check-outcomes-interface` requirements `A failed run is unproven only on positive evidence that no builder answered` and `Unrecognised is a failure recorded under its own status`, and `devloop-collection-interface` requirement `The attribute query derives abandoned from the unproven status`; the status cases of the repository check and the dev-loop fixture discharge it.

#### Scenario: Nix rewords the message for an unreachable builder

- **WHEN** after a Nix change, a build runs while stibnite is asleep and the new message matches no known marker
- **THEN** each Mac attribute ends unrecognised with the new message as its error text, the build fails, and the dev-loop history counts the endings by their outcome

#### Scenario: A plausible wrong implementation records it as failed

- **WHEN** an implementation records an unrecognised ending as an ordinary failure
- **THEN** the status case expecting the unrecognised outcome fails

### Requirement: An unrecognised ending is named with its log line wherever a person reads readiness

A build that failed because of an unrecognised ending SHALL say so, naming the attribute and the failure's last error text, on the pull request's build check run and in the readiness report, so that whoever waits on the merge sees that the block is unrecognised and why without opening the log; no alert SHALL be raised for it.

**Discharged by**: `mac-check-outcomes-interface` requirements `The build summary names unproven and unrecognised attributes`, `The readiness report names unproven and unrecognised attributes` and `Unrecognised is a failure recorded under its own status`; the summary case and the readiness-report fixture discharge it.

#### Scenario: The operator runs the readiness report during such a block

- **WHEN** a pull request's build failed because `darwin-stibnite` ended unrecognised with the line `error: some new transport wording`
- **THEN** the readiness report calls the pull request failing and shows `unrecognised Mac ending: darwin-stibnite: error: some new transport wording`

#### Scenario: The report drops the label

- **WHEN** the readiness report's script is replaced by one that omits the unrecognised suffix
- **THEN** the report's fixture comparison fails

### Requirement: An unrecognised ending can be classified by one change to the repository, without a deploy

A message found to mean that no builder answered SHALL be classifiable by a change to this repository alone, which records the message as known and adds the captured log as a case, is verified by one check build, and takes effect for the build of the change itself and for every later build containing it, without changing or redeploying the build service; a message so recorded SHALL never turn a builder's answer into an unproven outcome.

**Discharged by**: `mac-check-outcomes-interface` requirements `The repository's markers classify infrastructure endings from the built worktree` and `A verdict line decides a failure`; the marker cases of the repository check discharge it.

#### Scenario: A new message is classified

- **WHEN** the message of an unrecognised ending is added to the repository's known messages together with its captured log and case
- **THEN** the repository check fails without the message and passes with it, and the pull request carrying it is built with the ending classified as unproven

#### Scenario: The marker matches a builder's answer

- **WHEN** a known message also occurs in a log that holds a builder's failing answer
- **THEN** the attribute still fails with a verdict

### Requirement: Unrelated work lands during an unrecognised block only through a true record

While an unrecognised ending blocks pull requests, no override SHALL exist that lets a build pass with that ending recorded; unrelated work SHALL be able to land only by a new attempt that ends otherwise, or by taking the Mac builder out of service so that its attributes end unproven because no builder is reachable.

**Discharged by**: `mac-check-outcomes-interface` requirement `Unrecognised is a failure recorded under its own status`, whose case runs an unrecognised ending under every setting this change adds and still fails the build; and the stopped-builder probe, which shows that a Mac taken out of service yields unproven outcomes.

#### Scenario: The ending was transient

- **WHEN** the blocked attribute is rerun and the new attempt receives a passing verdict
- **THEN** the build passes and the record shows the verdict

#### Scenario: The ending recurs

- **WHEN** the ending recurs and the operator stops stibnite's builder service
- **THEN** the next builds' Mac attributes end unproven because no builder is reachable, and unrelated pull requests land with them named as unproven
