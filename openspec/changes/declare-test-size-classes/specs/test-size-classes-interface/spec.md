## ADDED Requirements

### Requirement: Each test's size class is declared beside its definition

Each attribute of `checks.x86_64-linux`, `checks.aarch64-darwin`, `vmTests.x86_64-linux` and `vmTests.aarch64-linux` SHALL have exactly one entry in the perSystem option `testSizes`, defined beside the attribute or beside the code that generates it.

**Entry**: `testSizes.checks.<name>` or `testSizes.vmTests.<name>`, of the form `{ class; reason ? null; measured ? true; }` with `class` one of `small`, `medium`, `large`, `enormous`; every entry SHALL be literal data or depend only on the perSystem `system` string, never on `pkgs` or on any derivation; `flake.lib.testSizeLimits` SHALL be `{ small = 60; medium = 300; large = 900; enormous = 3600; }`, in seconds, and `flake.lib.enormousTests` SHALL list the `vmTests.x86_64-linux` names whose entry is `enormous`.

**Discharged by**: `checks.<system>.test-size-classes` (the structural check below) for presence and uniqueness; the evaluation-cost measurement under `The structural check stays within its evaluation budget` for the literal-data clause; `nix eval .#lib.testSizeLimits` and `.#lib.enormousTests` for the two values.

#### Scenario: A large package build

- **WHEN** `checks.aarch64-darwin.package-buzz-git-sign-nostr` is declared
- **THEN** its entry sits in `modules/checks/packages.nix` beside the `mapAttrs'` that generates it, with `class = "large"` and a non-empty `reason`

#### Scenario: A runtime test never measured

- **WHEN** `vmTests.x86_64-linux.tuwunel-server-name-guard` is declared before its first measured run
- **THEN** its entry is `{ class = "medium"; measured = false; }`

### Requirement: Each runtime test's global timeout is its class limit

The `vmTests` option SHALL apply to every test `test.extend { modules = [ { globalTimeout = limit; } ]; }`, with `limit` the `testSizeLimits` value of the test's declared class, and a test without an entry SHALL fail evaluation with a message naming it.

**Discharged by**: by evaluation, every `vmTests.x86_64-linux.<name>.driver`'s rendered `global_timeout` equal to its class limit; the mutant that declares `greptimedb-pipeline` with a 5-second limit and fails on the driver's timeout; the mutant that removes one entry and fails evaluation naming the test. Rests on world assumption `A221 — The NixOS test driver ends a test whose script outlasts its global timeout, timing the script only`.

#### Scenario: A small test given too little time

- **WHEN** `vmTests.x86_64-linux.greptimedb-pipeline`, whose script takes 13–16 seconds, is built with a limit of 5 seconds
- **THEN** the driver's timer ends the test and the build fails

#### Scenario: An enormous test's derivation

- **WHEN** a test declared enormous is evaluated before and after the timeout is applied
- **THEN** its `drvPath` is unchanged, since 3600 is the driver's default

### Requirement: The structural check fails on an unclassed, orphaned, enormous or unexplained large check

`checks.x86_64-linux.test-size-classes` and `checks.aarch64-darwin.test-size-classes` SHALL each fail, listing every finding, when an attribute of its system's `checks` has no entry, an entry names no attribute, a check is `enormous`, or a `large` check has no `reason`.

**Runtime tests**: the x86_64-linux check SHALL apply the first two findings also to `vmTests.x86_64-linux` and `vmTests.aarch64-linux` against those systems' `testSizes.vmTests` entries, and every `vmTests` module SHALL decide its attribute names from the `system` string alone.

**Discharged by**: the check passing on the stage's head, and four mutants, each alone, failing it: a check with no entry; an entry for a missing name; a check declared `enormous`; a `large` check with `reason = null`.

#### Scenario: A new check without an entry

- **WHEN** a module adds `checks.x86_64-linux.example` and no `testSizes.checks.example`
- **THEN** `checks.x86_64-linux.test-size-classes` fails, naming `example`

#### Scenario: Reading another system's runtime-test names

- **WHEN** the x86_64-linux check reads the names of `vmTests.aarch64-linux`
- **THEN** no aarch64-linux nixpkgs is instantiated, because every `vmTests` module keys on `system`

### Requirement: The structural check stays within its evaluation budget

`checks.x86_64-linux.test-size-classes` SHALL cost, cold, at most the key-set figure of `checks.x86_64-linux` plus 25 MiB of allocation and 0.5 s of CPU, and the `testSizes` entries SHALL leave both that key-set figure and nixbot's evaluation time unchanged.

**Measurement**: each figure is measured with stock Nix on magnetite by the protocol of the `preferences-nix-checks-architecture` skill's evaluation-cost reference; nixbot's evaluation of the two gated systems (iets, 5 workers × 3,072 MiB) is compared in an interleaved A/B/A/B benchmark, and "unchanged" means no separation between arms.

**Discharged by**: the recorded measurements, with evaluator, version, host, memory, worker count and concurrent load, in the stage's log before it merges.

#### Scenario: An entry forces a derivation

- **WHEN** a `testSizes` entry reads an attribute of a derivation
- **THEN** the key-set figure or the single-attribute figure exceeds its budget and the stage does not merge until the entry is literal

### Requirement: CheckOutgrewItsClass reports a check over its class limit

`modules/nixos/fleet-alert/rules.nix` SHALL carry an SQL rule `CheckOutgrewItsClass` on database `devloop`, severity `info`, `for = "24h"`, that returns each check whose uncached successful builds in the last 30 days exceed its class limit, and each check declared `measured = false` that has three such builds.

**Query**: the rule reads `ci_attribute` rows with `project = 'cameronraysmith/vanixiets'`, `status = 'succeeded'`, `cached` false, `finished_at - started_at` at least 1 second and `finished_at` within 30 days, and returns one row per `attr` that has at least three such rows and either a median `finished_at - started_at` above its limit or an entry with `measured = false`, or any such row above 3,600 seconds; the median SHALL be GreptimeDB's exact `median`. The per-check class, limit and `measured` SHALL be rendered into the query as a `VALUES` list from `flake.lib.checkSizes` (the `testSizes.checks` entries of `checks.x86_64-linux` and `checks.aarch64-darwin`, keyed `checks.<system>.<name>`) and `testSizeLimits`. Each row SHALL carry the labels `attr`, `class`, `measured` and `runs_class` (the class its median gives) and a `value` naming its median, slowest run, run count and limit.

**Discharged by**: `vmTests.x86_64-linux.devloop-ingest`'s `sizeRule` case, which runs the rendered query on GreptimeDB against fixture rows and requires exactly the expected checks, with its mutant `sizeRuleLimitOff` and one mutant per filter and arm; `checks.x86_64-linux.fleet-alert`'s `sizeRuleClause`, which pins the rendered limits, with its mutants `sizeRenderLimitOff` and `sizeRenderDropped`. Rests on world assumptions `A222 — Neither Nix nor nixbot bounds the build time of one derivation` and `A223 — nixbot times an attribute's build from its builder slot to its completion, and an output already present gets no duration`.

#### Scenario: The fixture rows

- **WHEN** `sizeRule` loads one medium check with three runs of 420 seconds, one with two such runs, one small check with a single run of 3,700 seconds among nine of 10 seconds, one within its limit beside another project's, cached and failed rows of 400 seconds, one medium check whose three runs of 420 seconds finished 31 days ago, one unmeasured check with three runs of 30 seconds, and one unmeasured check with two runs of 30 seconds and two rows under 1 second
- **THEN** the query returns exactly the first, the third and the unmeasured check with three runs, the last with `runs_class` small

### Requirement: RuntimeTestCostDrift reports a runtime test whose script time grows or whose margin is smaller than its spread

`modules/nixos/fleet-alert/rules.nix` SHALL carry an SQL rule `RuntimeTestCostDrift` on database `devloop`, severity `info`, that returns each `vmTests.x86_64-linux` test whose recorded test-script times show either growth of its median relative to its own recorded baseline, or a margin under its class limit smaller than its own observed spread.

**Query**: the rule reads the runtime-test run records the weekly run writes (below), counting a run that ended on its timeout as at least its class limit; the per-test limits SHALL be rendered from `testSizes.vmTests` and `testSizeLimits`. Per test it reads the last 8 records within 180 days whose outcome is a pass or a timeout, and returns the test when, with at least 6 records, the median of the newest 3 exceeds the median of the older ones by more than a tenth of its class limit (growth), or when, with at least 2 records, its class limit minus its median is smaller than its maximum minus its minimum (spread); with no record it returns nothing.

**Discharged by**: the acceptance cases below, computed on the measurements recorded on 2026-11-24; `vmTests.x86_64-linux.devloop-ingest`'s `sizeRule` case, extended with runtime-test fixture records, which runs the rendered query and requires exactly the expected tests, with a mutant that renders the rule without its spread arm and must fail.

#### Scenario: A stable test near its limit

- **WHEN** the rule is computed on `tincr-mesh`'s recorded scripts (267.74 and 269.94 seconds, medium) or `devloop-ingest`'s (229.54 and 233.38 seconds, medium)
- **THEN** it returns neither

#### Scenario: A test whose spread exceeds its margin

- **WHEN** the rule is computed on `fleet-ingress`'s recorded scripts before 2026-11-24's fix (252.56, 280.74 and 216.61 seconds, and one run that reached the 300-second timeout, medium)
- **THEN** it returns `fleet-ingress`

### Requirement: enormous-tests builds every enormous runtime test from the default branch weekly, and records every runtime test's script time

pyrite SHALL run `enormous-tests.timer` (`OnCalendar = "Sun 03:00"`, `Persistent = true`) and `enormous-tests.service`, one of pyrite's `notifiedUnits`, which builds every runtime test the default branch declares enormous, then every other `vmTests.x86_64-linux` test, and exits non-zero if any fails.

**Run**: the service resolves its flake reference (by default `github:cameronraysmith/vanixiets/main`) to one revision, reads that revision's `lib.enormousTests`, and builds each `vmTests.x86_64-linux.<name>` of that revision one at a time with `--builders ''`; after each enormous build it writes `vanixiets_enormous_test_last_run_timestamp_seconds{test,result}` and, on success, `vanixiets_enormous_test_last_success_timestamp_seconds{test}` to the node exporter's textfile directory. For every test it actually ran, enormous or not, it appends one record (test, revision, class, the script time from the driver's `test script finished in`, outcome) to a file the dev-loop collection ships into a `devloop` table; a test whose output is already in the store adds no record.

**Discharged by**: one on-demand start after the deploy, given its notice, with both metrics and one run record per test it ran read from the store; the unit started once with a runtime drop-in pointing at a throwaway tree in which `greptimedb-pipeline` is declared enormous and fails, which fails the unit, posts one failure notice and records `result="failure"`. Rests on world assumption `A224 — pyrite is the fleet's only kvm host, takes one build at a time, and is the operator's laptop`.

#### Scenario: A test fails

- **WHEN** one enormous test fails during the weekly run
- **THEN** the remaining tests still run, the unit exits non-zero, one failure notice for `enormous-tests` posts, and the failed test's metric carries `result="failure"`

### Requirement: EnormousTestStale fires when an enormous test has not passed for eight days

`modules/nixos/fleet-alert/rules.nix` SHALL carry a PromQL rule `EnormousTestStale`, severity `warning`, rendered with one selector per name in `lib.enormousTests` of magnetite's deployed revision, that fires when `time() - vanixiets_enormous_test_last_success_timestamp_seconds{test="<name>"}` exceeds 691,200 seconds or the series is absent while pyrite reports host metrics.

**Discharged by**: `checks.x86_64-linux.fleet-alert`'s legs `enormousStale` (a 9-day-old success; fires) and `enormousFresh` (a 1-day-old success; silent), with the mutant `enormousStaleAt80Days` failing `enormousStale`.

#### Scenario: Pyrite was off for the week

- **WHEN** pyrite did not run the weekly service and an enormous test's last success is nine days old
- **THEN** `EnormousTestStale` fires for that test

### Requirement: Routing and ingest assertions run apart from elapsed-time cases

`vmTests.x86_64-linux.fleet-ingress` and `vmTests.x86_64-linux.devloop-ingest` SHALL run no case whose behaviour needs elapsed time; those cases SHALL run in `vmTests.x86_64-linux.fleet-ingress-outage` and `vmTests.x86_64-linux.devloop-ingest-reconcile`.

**Cases**: `fleet-ingress` runs exactly `processName`, `refusal`, `delivery`, `agentSession`, `agentSpans`, `schemaOrder`, `handoffCap` and `budget`, and `fleet-ingress-outage` exactly `backPressure`, `lossControls`, `crashLoop`, `longRun`, `absentClientCa` and `langfuse`, both from one container definition, and `fleet-ingress`'s no-leak scans SHALL run as one command inside the container per scan, reporting per column; `devloop-ingest` runs every case except `reconcile`, which `devloop-ingest-reconcile` runs, with its wait for the next UTC day applied only when fewer than 1,800 seconds remain before midnight.

**Discharged by**: measured runs of each medium test on pyrite with `--builders ''`, each test script (the driver's `test script finished in`) at most 300 seconds, and each run's per-case times recorded; one passing run of each enormous test; the scan mutants `scanFirstTable` and `scanStringOnly` failing `fleet-ingress`'s positive controls.

#### Scenario: A run of the routing test

- **WHEN** `vmTests.x86_64-linux.fleet-ingress` is built on pyrite after a collector change
- **THEN** the test script takes at most 300 seconds and the log shows the eight case markers and none of the six outage cases

### Requirement: Trust boundary of the size regulators

These properties SHALL be stated with their limits: the timeout bounds a runtime test's script, not its driver or node builds, which are build cost judged by no size regulator; `CheckOutgrewItsClass` sees only builds nixbot recorded, so no local build and no runtime test; `RuntimeTestCostDrift` sees only runs the weekly run made; the weekly run sees only what pyrite could build and reach; the structural check sees names, not durations; nothing observes a run notice.

**Discharged by**: this statement, repeated in the repository fragment's test-size paragraph and in `references/test-sizes.md` "What is not enforced" when each regulator lands.

#### Scenario: A runtime test's cold build is slow

- **WHEN** a runtime test's script takes 250 seconds and its node builds 200 seconds more
- **THEN** the test passes as medium, since its class is its script's time; the build time is build cost, visible only in the whole-build timing a stage's log records
