## ADDED Requirements

### Requirement: Every evaluation of the build service is measured whichever evaluator runs

Each evaluation the build service runs on magnetite SHALL leave one dev-loop record of its evaluator and version, its workers and their share of memory, its duration and processor time, its memory peak against its memory ceiling, its kernel and evaluator kills, and its outcome, produced the same way whichever evaluator runs.

**Discharged by**: `build-service-evaluator-interface` requirements `nixbot logs one record per evaluation` and `nixbot's unit names its evaluator`, and `devloop-collection-interface` requirements `nixbot's evaluation records are parsed from its journal` and `devloop-reconcile compares evaluation records with the journal every day`, resting on world assumptions `A145 — Neither evaluator reports routine worker recycling, and nix-eval-jobs reports its kills in two fixed messages` and `A146 — nixbot evaluates in a sandbox that sees neither the journal nor the cgroup tree, in a cgroup it removes after the run`; the patch's check, the collection path's container test and the operator's recorded first week discharge it.

#### Scenario: An evaluation finishes under the current evaluator

- **WHEN** the build service finishes an evaluation of a push to `cameronraysmith/vanixiets` with nix-eval-jobs
- **THEN** one dev-loop record names nix-eval-jobs and its version, 6 workers of 3072 MiB, the duration, user and system time, the memory peak and the memory ceiling of 21504 MiB, zero or more kernel kills and evaluator kills, and the outcome

#### Scenario: An evaluation fails

- **WHEN** an evaluation exits non-zero, whether from an error in the repository or from the kernel killing a worker
- **THEN** its dev-loop record still exists, records the failure, and records the kernel kills its processes suffered

#### Scenario: A worker is replaced for outgrowing its share

- **WHEN** a worker exceeds its share of memory, leaves after its attribute and is replaced
- **THEN** the dev-loop record does not count it, because neither evaluator reports it, and the record's memory peak still bounds what the evaluation held

### Requirement: The build service changes evaluator only after a week of measured evaluations under the evaluator it replaces

The build service SHALL NOT change its evaluator until the dev-loop history holds the records of at least seven consecutive days of evaluations under the evaluator it replaces, at the memory settings the new evaluator will start with, and the operator has recorded that week's memory peaks, durations and kill counts as the baseline.

**Discharged by**: the ordering of the change's deployment, with the operator's recorded baseline as its evidence; `build-service-evaluator-interface` requirement `nixbot's evaluator is the lock-wrapped nix-eval-jobs option` keeps the stock evaluator in place until the switch.

#### Scenario: The switch is proposed before a week has passed

- **WHEN** fewer than seven days of evaluation records exist under nix-eval-jobs at 6 × 3072 MiB
- **THEN** the switch is not deployed

### Requirement: A change of evaluator keeps every attribute's derivation and cache status

Before the build service changes its evaluator, the new evaluator SHALL run inside the build service's own isolation on magnetite, under the name the build service invokes, and SHALL give every attribute of the canary commits the same derivation, outputs, system and cache status as the evaluator it replaces, failing where that evaluator fails.
The canary commits SHALL cover outputs already on magnetite, outputs only a binary cache holds, outputs nowhere held, and an evaluation that fails.

**Discharged by**: `build-service-evaluator-interface` requirement `The canary compares the evaluators inside nixbot's sandbox`, resting on world assumptions `A143 — iets evaluates without building, never reads a flake's nixConfig, and asks the daemon for cache status` and `A147 — iets computes the same derivations as nix-eval-jobs for this repository's checks`; the canary's recorded comparison discharges it.

#### Scenario: One attribute's derivation differs

- **WHEN** the canary finds one attribute whose derivation under iets differs from nix-eval-jobs'
- **THEN** the switch is not deployed until the difference is explained and recorded

#### Scenario: An output only a binary cache holds

- **WHEN** the canary evaluates a commit whose outputs are in one of the fleet's binary caches but not on magnetite
- **THEN** both evaluators report those attributes as cached rather than as not built

### Requirement: Whole-evaluation failure on a killed worker is accepted only with measured headroom

While the build service runs an evaluator that fails a whole evaluation when one of its workers is killed, every evaluation in the canary and in the first seven days after the switch SHALL peak at or below 90 % of its memory ceiling and below the build service's 20 GiB throttle level, with no kernel kill.
When one does not, or the operator judges the headroom not comfortable, the build service SHALL return to the evaluator it replaced, with the operator's recorded reason.

**Discharged by**: `build-service-evaluator-interface` requirement `nixbot logs one record per evaluation`, resting on world assumption `A144 — iets fails a whole evaluation when a worker is killed, while nix-eval-jobs retries the killed worker's attribute alone`; the operator's recorded gate over the canary's and the first week's dev-loop records discharges it.

#### Scenario: An evaluation peaks above 90 % of its ceiling

- **WHEN** an evaluation under iets in its first week records a memory peak of 19.5 GiB against a 21 GiB ceiling
- **THEN** the build service returns to nix-eval-jobs and the operator's record cites that evaluation

#### Scenario: The kernel kills a worker under iets

- **WHEN** an evaluation under iets records one kernel kill and fails
- **THEN** the build service returns to nix-eval-jobs, unless the operator records why the kill does not recur

### Requirement: The evaluation still runs one at a time and without building

Whichever evaluator the build service runs, its evaluation SHALL wait for every other evaluation on magnetite to finish before it starts, SHALL be the first of the build service's work the kernel kills for memory, and SHALL build nothing while it evaluates.

**Discharged by**: `build-service-evaluator-interface` requirement `nixbot's evaluator is the lock-wrapped nix-eval-jobs option`, resting on world assumption `A143 — iets evaluates without building, never reads a flake's nixConfig, and asks the daemon for cache status`; the lock's rehearsal check and magnetite's evaluation-time assertions discharge it.

#### Scenario: The switch drops the lock

- **WHEN** magnetite's configuration sets nixbot's evaluator to an iets package that the lock does not wrap
- **THEN** magnetite's evaluation fails on the lock's assertion

### Requirement: A change of evaluator is reverted with one change

Returning the build service to the evaluator it replaced SHALL take one change to one line of magnetite's configuration and one deploy of magnetite, and SHALL leave the evaluation records and their chart in place.

**Discharged by**: `build-service-evaluator-interface` requirement `nixbot's evaluator is the lock-wrapped nix-eval-jobs option`; the reversal rehearsed in a scratch copy discharges it.

#### Scenario: The switch is reverted

- **WHEN** the line selecting the iets package is reverted
- **THEN** magnetite's configuration evaluates with nixbot's stock evaluator behind the lock, and the evaluation records keep arriving with the evaluator named nix-eval-jobs

### Requirement: A change to the evaluation's memory settings rests on recorded measurements

The number of workers and each worker's share of memory SHALL change only by a decision the operator records beside the earlier measurements, citing the evaluations' memory peaks, durations and kill counts from the dev-loop history for at least the seven days before the decision.

**Discharged by**: the comment table beside `evalWorkerCount` and `evalMaxMemorySize` in `modules/nixos/nixbot.nix`, with the operator's recorded decision as its evidence.

#### Scenario: A tuning change without measurements

- **WHEN** a change alters the number of workers or a worker's share of memory without citing seven days of evaluation records
- **THEN** the change is not merged
