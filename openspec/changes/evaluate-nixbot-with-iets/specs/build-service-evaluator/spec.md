## ADDED Requirements

### Requirement: Every evaluation of the build service is measured whichever evaluator runs

Each evaluation the build service runs on magnetite SHALL leave one dev-loop record of its evaluator and version, its workers and their share of memory, its duration and processor time, its memory peak against its memory ceiling, its kernel and evaluator kills, and its outcome, produced the same way whichever evaluator runs.

**Discharged by**: `build-service-evaluator-interface` requirements `nixbot logs one record per evaluation` and `nixbot's unit names its evaluator`, and `devloop-collection-interface` requirements `nixbot's evaluation records are parsed from its journal` and `devloop-reconcile compares evaluation records with the journal every day`, resting on world assumptions `A145 — Neither evaluator reports routine worker recycling, and nix-eval-jobs reports its kills in two fixed messages` and `A146 — nixbot evaluates in a sandbox that sees neither the journal nor the cgroup tree, in a cgroup it removes after the run`; the patch's check, the collection path's container test and the operator's recorded first week discharge it.

#### Scenario: An evaluation finishes under the current evaluator

- **WHEN** the build service finishes an evaluation of a push to `cameronraysmith/vanixiets` with nix-eval-jobs
- **THEN** one dev-loop record names nix-eval-jobs and its version, 6 workers of 3072 MiB, the duration, user and system time, the memory peak and the memory ceiling it ran under, at least 21504 MiB, zero or more kernel kills and evaluator kills, and the outcome

#### Scenario: An evaluation fails

- **WHEN** an evaluation exits non-zero, whether from an error in the repository or from the kernel killing a worker
- **THEN** its dev-loop record still exists, records the failure, and records the kernel kills its processes suffered

#### Scenario: A worker is replaced for outgrowing its share

- **WHEN** a worker exceeds its share of memory, leaves after its attribute and is replaced
- **THEN** the dev-loop record does not count it, because neither evaluator reports it, and the record's memory peak still bounds what the evaluation held

### Requirement: The build service changes evaluator only after a paired replay

The build service SHALL NOT change its evaluator until about twenty commits it has already evaluated, including broad lock-file updates and an evaluation that fails, have run under both evaluators back to back in its own isolation, and the operator has recorded the replay.
A replay criterion that is not met SHALL open the operator's discussion of mitigations rather than reject the evaluator.

**Discharged by**: the ordering of the change's deployment, with the operator's recorded replay as its evidence; `build-service-evaluator-interface` requirement `The canary compares the evaluators inside nixbot's sandbox` runs the replay, and `nixbot's evaluator is the lock-wrapped nix-eval-jobs option` keeps the stock evaluator in place until the switch.

#### Scenario: The switch is proposed before the replay

- **WHEN** the replay has not run, or a commit's attribute derivations differ between the evaluators without an explanation recorded
- **THEN** the switch is not deployed

#### Scenario: The replay is read

- **WHEN** the operator reads the replay before the switch
- **THEN** each commit kept its attribute set and each attribute's derivation, each iets peak stayed at most 90 % of its memory ceiling and at most 20 GiB with no kernel or worker kill, cache states behaved alike, and no commit was more than 10 % slower, or the criterion that was not met is under discussion

#### Scenario: The replay finds an iets peak above 90 % of its ceiling

- **WHEN** one replayed commit peaks under iets above 90 % of the memory ceiling it ran under
- **THEN** the operator opens a discussion of mitigations, starting with tuning the evaluator, and iets is not rejected for it

#### Scenario: The replay finds a commit slower under iets

- **WHEN** one replayed commit takes more than 10 % longer under iets than under nix-eval-jobs
- **THEN** the slowdown is diagnosed before the switch, and the replay's overall speed-up is reported

### Requirement: A change of evaluator keeps every attribute's derivation and cache status

Before the build service changes its evaluator, the new evaluator SHALL run inside the build service's own isolation on magnetite, under the name the build service invokes, and SHALL give every attribute of the replayed commits the same derivation, outputs, system and cache status as the evaluator it replaces, failing where that evaluator fails.
The replayed commits SHALL cover outputs already on magnetite, outputs only a binary cache holds, outputs nowhere held, and an evaluation that fails.

**Discharged by**: `build-service-evaluator-interface` requirement `The canary compares the evaluators inside nixbot's sandbox`, resting on world assumptions `A143 — iets evaluates without building, never reads a flake's nixConfig, and asks the daemon for cache status` and `A147 — iets computes the same derivations as nix-eval-jobs for this repository's checks`; the canary's recorded comparison discharges it.

#### Scenario: One attribute's derivation differs

- **WHEN** the canary finds one attribute whose derivation under iets differs from nix-eval-jobs'
- **THEN** the switch is not deployed until the difference is explained and recorded

#### Scenario: An output only a binary cache holds

- **WHEN** the canary evaluates a commit whose outputs are in one of the fleet's binary caches but not on magnetite
- **THEN** both evaluators report those attributes as cached rather than as not built

### Requirement: Insufficient evaluation headroom opens a capacity decision

While the build service runs an evaluator that fails a whole evaluation when one of its workers is killed, an evaluation peaking above 90 % of its memory ceiling or at the build service's 20 GiB throttle level, or suffering a kernel kill, SHALL open a capacity decision by the operator, recorded with the evaluation records and magnetite's memory budget.
The decision SHALL take, in order of cost: tuning the evaluator, reclaiming memory, moving other services, resizing magnetite.

**Discharged by**: `build-service-evaluator-interface` requirements `nixbot logs one record per evaluation` and `magnetite reports each competing unit's memory and its compressed swap`, resting on world assumption `A144 — iets fails a whole evaluation when a worker is killed, while nix-eval-jobs retries the killed worker's attribute alone`; the operator's recorded decisions over the canary's and each week's dev-loop records discharge it.

#### Scenario: An evaluation peaks above 90 % of its ceiling

- **WHEN** an evaluation under iets in its first week records a memory peak of 19.5 GiB against the 21 GiB ceiling it ran under
- **THEN** the build service keeps iets, and the operator records a capacity decision citing that evaluation and magnetite's memory budget at the time, starting with whether tuning the evaluator restores headroom

#### Scenario: Tuning cannot restore headroom without losing the speed

- **WHEN** fewer workers or a smaller share of memory per worker would bring the peak under the trigger only by giving back most of iets' measured speed
- **THEN** the operator's decision moves to reclaiming memory on magnetite, such as capping the file-system cache, and only then to moving other services or resizing magnetite, which the operator decides outside this capability

#### Scenario: The kernel kills a worker under iets

- **WHEN** an evaluation under iets records one kernel kill and fails
- **THEN** the build is rebuilt; if the same commit fails again, the operator records a capacity decision, starting with tuning the evaluator, and the kill alone does not return the build service to nix-eval-jobs

### Requirement: magnetite's memory budget is measured beside every evaluation

For as long as the build service evaluates on magnetite, the memory each competing unit holds and has held at most, the file-system cache's size and its limit, and the memory compressed swap holds and the data it stands for SHALL be recorded each minute, and SHALL be viewable beside the evaluation records.

**Discharged by**: `build-service-evaluator-interface` requirement `magnetite reports each competing unit's memory and its compressed swap`, the existing node_exporter keep-list's ARC series, and `fleet-dashboard` requirement `An admitted person views the fleet's signals and the dev-loop history by host`, resting on world assumption `A153 — The collector's systemd receiver reports no unit memory, and the kernel reports each service's memory and zram's footprint`; the operator's recorded baseline discharges it.

#### Scenario: The baseline is summarised

- **WHEN** the operator records the baseline
- **THEN** the record names each competing unit's largest memory, the file-system cache's largest size and its limit, and compressed swap's largest footprint, beside the evaluations' memory peaks

#### Scenario: A competing unit grows

- **WHEN** a unit on magnetite other than the build service doubles its memory over a week
- **THEN** the dev-loop view shows it beside the evaluation peaks, and a capacity decision can cite it

### Requirement: The evaluation still runs one at a time and without building

Whichever evaluator the build service runs, its evaluation SHALL wait for every other evaluation on magnetite to finish before it starts, SHALL be the first of the build service's work the kernel kills for memory, and SHALL build nothing while it evaluates.

**Discharged by**: `build-service-evaluator-interface` requirement `nixbot's evaluator is the lock-wrapped nix-eval-jobs option`, resting on world assumption `A143 — iets evaluates without building, never reads a flake's nixConfig, and asks the daemon for cache status`; the lock's rehearsal check and magnetite's evaluation-time assertions discharge it.

#### Scenario: The switch drops the lock

- **WHEN** magnetite's configuration sets nixbot's evaluator to an iets package that the lock does not wrap
- **THEN** magnetite's evaluation fails on the lock's assertion

### Requirement: A change of evaluator is reverted with one change

Returning the build service to the evaluator it replaced SHALL take one change to one line of magnetite's configuration and one deploy of magnetite, SHALL leave the evaluation records, magnetite's memory budget and their charts in place, and SHALL be taken only when a failing evaluation blocks merges and no fix or pin of the new evaluator is quick, as a decision the operator records (Q88, 2026-11-21).

**Discharged by**: `build-service-evaluator-interface` requirement `nixbot's evaluator is the lock-wrapped nix-eval-jobs option`; the reversal rehearsed in a scratch copy discharges it.

#### Scenario: The switch is reverted

- **WHEN** the line selecting the iets package is reverted
- **THEN** magnetite's configuration evaluates with nixbot's stock evaluator behind the lock, and the evaluation records keep arriving with the evaluator named nix-eval-jobs

#### Scenario: An evaluator failure repeats on a commit

- **WHEN** an evaluation under iets crashes, rebuilt it crashes again on the same commit, and nix-eval-jobs evaluates that commit cleanly
- **THEN** the failure is fixed forward, first by pinning iets to its last good revision, and the switch is reverted only if merges stay blocked and no fix or pin is quick

### Requirement: A change to the evaluation's memory settings rests on recorded measurements

The number of workers and each worker's share of memory SHALL change only by a decision the operator records beside the earlier measurements, citing the evaluations' memory peaks, durations and kill counts from the dev-loop history and magnetite's memory budget for at least the seven days before the decision; such tuning is the first response of a capacity decision.

**Discharged by**: the comment table beside `evalWorkerCount` and `evalMaxMemorySize` in `modules/nixos/nixbot.nix`, with the operator's recorded decision as its evidence.

#### Scenario: A tuning change without measurements

- **WHEN** a change alters the number of workers or a worker's share of memory without citing seven days of evaluation records
- **THEN** the change is not merged
