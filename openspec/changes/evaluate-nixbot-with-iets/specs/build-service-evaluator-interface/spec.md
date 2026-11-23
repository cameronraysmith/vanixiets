## ADDED Requirements

### Requirement: nixbot's evaluator is the lock-wrapped nix-eval-jobs option

magnetite's configuration SHALL set `services.nixbot.packages.nix-eval-jobs` to `config.services.nixEvalLock.wrap` applied to exactly one package: `options.services.nixbot.packages.nix-eval-jobs.default` until the switch, and the package of `The iets package exposes nix-eval-jobs with nixbot's nix grafted on` after it, chosen on one line of `modules/nixos/nixbot.nix`; the unit's `NIX_CONFIG` SHALL keep `allow-import-from-derivation = false`.

**Discharged by**: `flake.modules.nixos.nix-eval-lock`'s assertions that no service PATH carries an unwrapped `nix-eval-jobs` and that a wrapper's `nix` equals its evaluator's (`modules/nixos/nix-eval-lock.nix`), `checks.x86_64-linux.nix-eval-lock-rehearsal`, magnetite's machine check through `flake.lib.nixEvalJobsObligations` (the selection), `checks.x86_64-linux.nix-eval-jobs-iets` (the lock's judgement reporting an unwrapped iets on nixbot's service PATH, and the obligations' `nixbotUnwrapped` mutant), and magnetite's kill-order assertion, resting on world assumption `A143 — iets evaluates without building, never reads a flake's nixConfig, and asks the daemon for cache status`; an evaluation of magnetite's `systemd.services.nixbot.path` and a read of the deployed unit's PATH discharge it.

#### Scenario: The unit PATH is read after the switch

- **WHEN** `nix eval` reads magnetite's `systemd.services.nixbot.path` after the switch
- **THEN** it holds one `nix-eval-jobs` wrapper whose `unwrapped.evaluator` is `iets` and whose `nix` has the same drvPath as the stock package's `nix`

#### Scenario: An unwrapped iets package reaches the unit PATH

- **WHEN** a mutant of magnetite's configuration sets `services.nixbot.packages.nix-eval-jobs` to the iets package without the wrapper
- **THEN** magnetite's evaluation fails on the lock's assertion

### Requirement: The iets package exposes nix-eval-jobs with nixbot's nix grafted on

The flake SHALL provide, for x86_64-linux, a package whose only executable is `bin/nix-eval-jobs`, a symlink to the `iets` input's default package's `bin/iets`, with `pname = "nix-eval-jobs"`, `evaluator = "iets"`, `version` equal to the input package's version, and `nix` equal to `options.services.nixbot.packages.nix-eval-jobs.default.nix` of the configuration that uses it; it SHALL include neither iets' `classic` package nor any other command name.

**Discharged by**: `nix build` of the package and a listing of its `bin/`; the canary, which runs it under that name inside nixbot's sandbox.

#### Scenario: The package is built

- **WHEN** the package is built
- **THEN** `bin/` holds exactly `nix-eval-jobs`, resolving to a store path of `iets-<version>/bin/iets`, and its closure holds no second Nix

### Requirement: The iets input is pinned without follows

`flake.nix` SHALL declare an `iets` input on `github:numtide/iets` with no `follows`, locked in `flake.lock`, and the iets build SHALL be substituted from `https://cache.numtide.com`, already among `lib/caches.nix`'s substituters.

**Discharged by**: `nix flake metadata` showing the input's own `nixpkgs`; the build log of the package showing a substitution rather than a build.

#### Scenario: The input follows the fleet's nixpkgs

- **WHEN** a change adds `inputs.iets.inputs.nixpkgs.follows`
- **THEN** the change is refused in review, because the repository does not redirect an upstream input's nixpkgs

### Requirement: nixbot logs one record per evaluation

A patch carried in `services.nixbot.packages.nixbot` SHALL make nixbot write, after its evaluator exits and before it removes the evaluation's cgroup, on success, failure and timeout alike, one log line through its own logger with `msg` `evaluation finished` and every `eval_run` field but `ts`, taking the cgroup fields from that cgroup, omitting them when the evaluation had no cgroup, and carrying no text from the evaluator's output.

**Discharged by**: a check that runs the patched runner against a stub evaluator in a cgroup it can read, for a success, a failure, a stub printing each kill message, and a timeout, asserting one line per run with the fields above; resting on world assumptions `A145 — Neither evaluator reports routine worker recycling, and nix-eval-jobs reports its kills in two fixed messages` and `A146 — nixbot evaluates in a sandbox that sees neither the journal nor the cgroup tree, in a cgroup it removes after the run`.

#### Scenario: The stub prints a budget kill line

- **WHEN** the check's stub evaluator prints `memory budget of 18432 MiB exceeded (19000 MiB in use), killing worker 42 ('checks.x', 4000 MiB)` and exits zero
- **THEN** the record has `budget_kills` 1, `worker_kills` 0 and `exit_status` 0, and no field contains `checks.x`

#### Scenario: The record's sources are read in the patch

- **WHEN** the patch is read against the record's fields
- **THEN** `memory_max_bytes`, `memory_peak_bytes`, `oom_kill`, `user_ms` and `system_ms` come from the evaluation cgroup's `memory.max`, `memory.peak`, `memory.events` `oom_kill` and `cpu.stat` `user_usec` and `system_usec`; `budget_kills` counts standard-error lines beginning `memory budget of` and `worker_kills` lines containing `was killed (system out of memory?)`; `evaluator` and `evaluator_version` come from `NIXBOT_EVALUATOR`; `workers`, `max_memory_mib` and `wall_ms` from nixbot's settings and its own timing; `exit_status` from the evaluator's exit

#### Scenario: The patch drops the record on failure

- **WHEN** a mutant of the patch writes the line only when the evaluator succeeds
- **THEN** the check's failure case fails

### Requirement: nixbot's unit names its evaluator

magnetite's configuration SHALL set `systemd.services.nixbot.environment.NIXBOT_EVALUATOR` to `<evaluator> <version>`, taken from the configured `services.nixbot.packages.nix-eval-jobs`' `unwrapped.evaluator`, or `nix-eval-jobs` when absent, and its `version`.

**Discharged by**: an evaluation of magnetite's `systemd.services.nixbot.environment.NIXBOT_EVALUATOR` before and after the switch.

#### Scenario: The value is read before and after the switch

- **WHEN** magnetite's configuration is evaluated before and after the switch
- **THEN** the value is `nix-eval-jobs 2.35.4` before and `iets 0.2.0` after, for the pinned revisions

### Requirement: The canary compares the evaluators inside nixbot's sandbox

Before the switch, the iets package SHALL run on magnetite as `nix-eval-jobs`, through nixbot's own sandbox command and argv and behind the host lock, back to back with the stock evaluator on a worktree of each replayed commit, alternating which runs first, while no nixbot evaluation runs; outputs SHALL be compared per attribute, and each run's peak, ceiling, kills and wall time recorded and kept out of the baseline.

**Discharged by**: the canary's logs and comparison under `logs/`, recorded in the change's verification, resting on world assumptions `A143 — iets evaluates without building, never reads a flake's nixConfig, and asks the daemon for cache status` and `A147 — iets computes the same derivations as nix-eval-jobs for this repository's checks`.

#### Scenario: The canary's comparison is read

- **WHEN** the comparison of the replayed commits is read
- **THEN** every attribute matches on the compared fields, each of `local`, `cached` and `notBuilt` occurs at least once, the failing commit fails under both evaluators on the same attributes, and each run's peak against its ceiling, kills and wall time stand beside it

#### Scenario: The canary's commits and fields are chosen

- **WHEN** the canary is prepared
- **THEN** its about twenty commits, all already evaluated by nixbot, include the five heaviest by stock memory peak, the five slowest by wall time, the latest flake update, one whose outputs are all on magnetite, one with outputs only a fleet binary cache holds, one with outputs no cache holds, and one whose evaluation fails, the rest drawn at random from recent days; the comparison covers `drvPath`, `outputs`, `system`, `cacheStatus` and the presence of `error`

### Requirement: magnetite reports each competing unit's memory and its compressed swap

The host nixbot runs on SHALL run `magnetite-memory-budget.service` every 60 s, replacing `magnetite-memory-budget.prom` in `vanixiets.nodeExporter.textfileDirectory` by write-then-rename with the `MemoryCurrent` and `MemoryPeak` of each active unit matching `memoryBudgetUnits` and of both slices, zram0's `mm_stat` sizes, and `user.slice`'s `memory.events` `high` count.
node_exporter SHALL read it through its `textfile` collector, and the six series names SHALL join `nodeExporterKeep`.

**Discharged by**: `checks.x86_64-linux.magnetite-memory-budget`, which formats systemctl output recorded on magnetite and a recorded `memory.events` with its mutants; the evaluation-time assertion of `flake.modules.nixos.magnetite-memory-budget` that node_exporter runs its textfile collector on the probe's directory and that `nodeExporterKeep` holds the six names; a read of the stored series after deploy; resting on world assumption `A153 — The collector's systemd receiver reports no unit memory, and the kernel reports each service's memory and zram's footprint`.

#### Scenario: The probe's output is read on magnetite

- **WHEN** `memory-budget.prom` is read on magnetite after deploy
- **THEN** it holds `vanixiets_unit_memory_current_bytes` and `vanixiets_unit_memory_peak_bytes` for each running unit of the list and for `system.slice` and `user.slice`, `vanixiets_zram_orig_data_bytes`, `vanixiets_zram_compr_data_bytes` and `vanixiets_zram_mem_used_bytes`, and `vanixiets_unit_memory_high_events{unit="user.slice"}`, with `omnigent-host-<owner>.service` written under its owner alias, and no series for a unit that is not running

#### Scenario: The keep-list loses a budget series

- **WHEN** a mutant of `nodeExporterKeep` drops `vanixiets_unit_memory_current_bytes`
- **THEN** magnetite's evaluation fails on the assertion

### Requirement: magnetite's user sessions carry a soft memory guard

magnetite's `user.slice` SHALL carry `MemoryHigh` 10G and no `MemoryMax`, so user sessions are throttled and reclaimed first above it and nothing is killed; `nix-daemon.service`, `nixbot.service` and `system.slice` SHALL carry no memory limit from this guard.

**Discharged by**: `flake.modules.nixos.magnetite-user-slice-guard`'s evaluation-time assertion, which the `nixos-magnetite` check evaluates, and `checks.x86_64-linux.user-slice-guard-obligations`, which runs its judge over fixtures; the `high` count of the budget probe shows how often it throttles.

#### Scenario: The guard loses its MemoryHigh

- **WHEN** a mutant of magnetite's configuration forces `user.slice`'s `MemoryHigh` to null
- **THEN** magnetite's evaluation fails on the guard's assertion

#### Scenario: The guard gains a MemoryMax

- **WHEN** a mutant of magnetite's configuration gives `user.slice` a `MemoryMax`
- **THEN** magnetite's evaluation fails on the guard's assertion, because the guard kills nothing

### Requirement: This capability states its own trust boundary

This capability SHALL guarantee only that magnetite selects one lock-wrapped evaluator, that the iets package and the record patch are built and checked as stated, and that the canary's comparison is recorded.
nixbot, the kernel's cgroup and zram counters and the evaluators produce what is recorded, trusted at the pinned revisions; nothing here guarantees that iets evaluates any expression as Nix does beyond the compared commits, or that a record reaches the telemetry store.

**Discharged by**: the statements of this capability's other requirements and of world assumptions `A143` to `A147` and `A153`.

#### Scenario: A reader asks whether iets is proven equivalent to Nix

- **WHEN** a reader looks here for a guarantee that iets evaluates every expression as Nix 2.35.6 does
- **THEN** this capability states it guarantees only the compared commits and the recorded measurements
