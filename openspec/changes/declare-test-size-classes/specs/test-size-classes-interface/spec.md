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

**Query**: the rule reads `devloop.runtime_test_result`, the records the weekly run writes (below). Per test it takes the last 8 records within 180 days whose outcome is `passed` or `timed_out`, a timed-out record carrying its class limit as its script time, and judges them by the class limit of the test's newest record; it returns the test when, with at least 6 records, the median of the newest 3 exceeds the median of the older ones by more than a tenth of that limit (growth), or when, with at least 2 records, that limit minus its median is smaller than its maximum minus its minimum (spread); with no record it returns nothing. A `present` or `failed` record is not a run and is never counted. Its labels are the test and the newest record's class; its value is the text of the median, run count, spread, the two medians of the growth arm and the limit.

**Discharged by**: the acceptance cases below, computed on the measurements recorded on 2026-11-24; `vmTests.x86_64-linux.devloop-ingest`'s `runtimeRules` case, which ships fixture records through the record file and the collector into the table, runs the rendered query and requires exactly the expected tests, with the mutants `noSpreadArm` (the rule without its spread arm), `noGrowthArm`, `noTimeoutCount`, `noWindow`, `noLastEight` and `largestLimit` (the window's largest limit instead of the newest record's), each of which must change the answer.

#### Scenario: A stable test near its limit

- **WHEN** the rule is computed on `tincr-mesh`'s recorded scripts (267.74 and 269.94 seconds, medium) or `devloop-ingest`'s (229.54 and 233.38 seconds, medium)
- **THEN** it returns neither

#### Scenario: A test whose spread exceeds its margin

- **WHEN** the rule is computed on `fleet-ingress`'s recorded scripts before 2026-11-24's fix (252.56, 280.74 and 216.61 seconds, and one run that reached the 300-second timeout, medium)
- **THEN** it returns `fleet-ingress`

#### Scenario: A test whose median grows

- **WHEN** a medium test's five older runs took 100 seconds and its newest three 140 seconds
- **THEN** it returns that test, though its margin under 300 seconds exceeds its spread

#### Scenario: A test reclassified smaller

- **WHEN** a test ran 40 seconds while declared medium and then 55 seconds at a revision that declares it small
- **THEN** it returns that test, judged by the small limit of 60 seconds

#### Scenario: A test already built

- **WHEN** the weekly run found a test's output already in the store and recorded it `present`
- **THEN** that record is not a run, and the rule counts it neither in the window nor in the minimum of 2 or 6

### Requirement: enormous-tests builds every runtime test of the default branch weekly and records what each did

pyrite SHALL run `enormous-tests.timer` (`OnCalendar = "Sun 03:00 America/New_York"`, `Persistent = true`) and `enormous-tests.service`, one of pyrite's `notifiedUnits`, which builds every runtime test the default branch declares enormous, then every other `vmTests.x86_64-linux` test, records one result per test, and exits non-zero if any failed, timed out or did not evaluate.

**Run**: the service fetches its flake reference (`ENORMOUS_TESTS_FLAKE`, by default `github:cameronraysmith/vanixiets/main`) once into the store with `nix flake prefetch`, reads that revision's `lib.runtimeTestSizes`, evaluates its `vmTests.x86_64-linux` once with the host's lock-wrapped `nix-eval-jobs`, and builds each test's derivation one at a time with `--builders ''` through the daemon, holding the host evaluation lock only while it evaluates. A test whose output is already in pyrite's store is not built and is recorded `present`; a built test is recorded `passed` with the script time of the driver's `test script finished in` line in that build's own log, `present` when the build succeeded without that line, `timed_out` with its class limit as its script time when the log carries the driver's `timeout reached`, and otherwise `failed`; a test that did not evaluate is recorded `failed`. Each record is one JSON line in `/var/log/runtime-test-result.jsonl` with exactly the columns of `devloop.runtime_test_result`: `host`, `test`, `revision`, `drv_path`, `class`, `limit_s`, `outcome`, `script_ms`, `build_ms` and `finished_at`. The unit keeps one GC root per declared test on the output it last saw pass, and its own `TimeoutStartSec` of 6 hours.

**Discharged by**: `checks.x86_64-linux.enormous-tests`, which runs the service's script against a stub `nix` and a stub `nix-eval-jobs` and requires each outcome's record, the order, the columns, the roots and the exit status, with its mutants `presentAsPassed`, `timeoutAsFailure`, `exitZero` and `buildPresent`; one on-demand start after the deploys, given its notice, with one result record per test read from the store; the unit started once with a runtime drop-in pointing at a throwaway tree in which `greptimedb-pipeline` is declared enormous and fails, which fails the unit, posts one failure notice and records `failed`. Rests on world assumption `A224 — pyrite is the fleet's only kvm host, takes one build at a time, and is the operator's laptop`.

#### Scenario: A test fails

- **WHEN** one enormous test fails during the weekly run
- **THEN** the remaining tests still run, the unit exits non-zero, one failure notice for `enormous-tests` posts, and the failed test's record carries `outcome = "failed"`

#### Scenario: Nothing changed

- **WHEN** a test's derivation is unchanged since the weekly run last saw it pass
- **THEN** the run builds nothing for it and records it `present`, with no script time

### Requirement: Pyrite's collector ships the weekly run's records into devloop.runtime_test_result

`devloop.runtime_test_result` SHALL be an allow-listed, pre-created `devloop` table with primary key (`host`, `test`) and time index `finished_at`; the agent role's `vanixiets.otelCollector.devloopRecordFiles` SHALL ship each listed file through `file_log/<name>` as the deploy record is shipped, defaulting to the deploy record alone, and pyrite SHALL list `/var/log/runtime-test-result.jsonl` as `runtime-test-result`.

**Discharged by**: `vmTests.x86_64-linux.devloop-ingest`'s first-start case, which requires a sent record and a stored row for every allow-listed table and each table's `DESC TABLE` to equal its allow-list, with a seeded record line, and its `runtimeRules` case, which ships its fixture records through the file; the first on-demand run's records read from the store.

#### Scenario: Every other host is unchanged

- **WHEN** any agent host other than pyrite is evaluated
- **THEN** its collector carries `file_log/deploy-record` with the settings it had before, and no other file receiver

### Requirement: EnormousTestStale fires when an enormous test has not passed for eight days

`modules/nixos/fleet-alert/rules.nix` SHALL carry an SQL rule `EnormousTestStale` on database `devloop`, severity `warning`, `for = "2h"`, rendered with one name per entry of `lib.enormousTests` of magnetite's deployed revision, that returns each such test whose newest `passed` or `present` record in `devloop.runtime_test_result` finished more than 8 days ago, or that has no such record.

**Discharged by**: `vmTests.x86_64-linux.devloop-ingest`'s `runtimeRules` case, which renders the rule over fixture names and requires exactly the stale ones, with the mutants `enormousStaleAt80Days`, `noPresent`, `noAbsentArm` and `anyOutcome`, each of which must change the answer; `checks.x86_64-linux.fleet-alert`'s `staleRenderClause`, which requires one rendered name per `lib.enormousTests` entry, with its mutant `staleRenderDropped`.

#### Scenario: Pyrite was off for the week

- **WHEN** pyrite did not run the weekly service and an enormous test's last passing record is nine days old
- **THEN** `EnormousTestStale` fires for that test

#### Scenario: Nothing changed

- **WHEN** an enormous test last ran 20 days ago and the weekly run recorded it `present` yesterday
- **THEN** `EnormousTestStale` is silent for it

#### Scenario: Nothing arrives

- **WHEN** the table holds no passing or present record of an enormous test
- **THEN** `EnormousTestStale` fires for that test

### Requirement: Routing and ingest assertions run apart from elapsed-time cases

`vmTests.x86_64-linux.fleet-ingress` and `vmTests.x86_64-linux.devloop-ingest` SHALL run no case whose behaviour needs elapsed time; those cases SHALL run in `vmTests.x86_64-linux.fleet-ingress-outage` and `vmTests.x86_64-linux.devloop-ingest-reconcile`.

**Cases**: `fleet-ingress` runs exactly `processName`, `refusal`, `delivery`, `agentSession`, `agentSpans`, `schemaOrder`, `handoffCap` and `budget`, and `fleet-ingress-outage` exactly `backPressure`, `lossControls`, `crashLoop`, `longRun`, `absentClientCa` and `langfuse`, both from one container definition, and `fleet-ingress`'s no-leak scans SHALL run as one command inside the container per scan, reporting per column; `devloop-ingest` runs every case except `reconcile`, which `devloop-ingest-reconcile` runs, with its wait for the next UTC day applied only when fewer than 1,800 seconds remain before midnight.

**Discharged by**: measured runs of each medium test on pyrite with `--builders ''`, each test script (the driver's `test script finished in`) at most 300 seconds, and each run's per-case times recorded; one passing run of each enormous test; the scan mutants `scanFirstTable` and `scanStringOnly` failing `fleet-ingress`'s positive controls.

#### Scenario: A run of the routing test

- **WHEN** `vmTests.x86_64-linux.fleet-ingress` is built on pyrite after a collector change
- **THEN** the test script takes at most 300 seconds and the log shows the eight case markers and none of the six outage cases

### Requirement: Trust boundary of the size regulators

These properties SHALL be stated with their limits: the timeout bounds a runtime test's script, not its builds; `CheckOutgrewItsClass` sees only builds nixbot recorded; `RuntimeTestCostDrift` and `EnormousTestStale` see only the weekly run's records that reached the store; the weekly run sees only what pyrite could build and reach; the structural check sees names, not durations; nothing observes a run notice.

**Discharged by**: this statement, repeated in the repository fragment's test-size paragraph and in `references/test-sizes.md` "What is not enforced" when each regulator lands.

#### Scenario: A runtime test's cold build is slow

- **WHEN** a runtime test's script takes 250 seconds and its node builds 200 seconds more
- **THEN** the test passes as medium, since its class is its script's time; the build time is build cost, visible only in the whole-build timing a stage's log records

#### Scenario: A non-enormous test's record is lost

- **WHEN** a result record of a non-enormous test never reaches `devloop.runtime_test_result`
- **THEN** no regulator reports it: `RuntimeTestCostDrift` judges the records that arrived, and `EnormousTestStale` watches only enormous tests
