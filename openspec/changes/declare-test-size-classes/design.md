## Context

### Current state

The fleet's test size policy (pull request #4224, 2026-11-24) sets four classes by the wall-clock time of one run, small up to 60 s, medium up to 300 s, large up to 900 s and enormous up to 3,600 s, the timeouts Bazel's test encyclopedia implies for its sizes.
Before any run expected to exceed 300 s, whoever starts it states its expected duration, what it proves that a cheaper run cannot, and what waits on it.
Small and medium checks belong on nixbot's pull-request gate (`checks.x86_64-linux` on magnetite's store, `checks.aarch64-darwin` best-effort), a large check only with its reason recorded beside its definition, and an enormous test never gates a pull request.
Runtime tests (`vmTests.<system>.<name>`, QEMU tests needing `kvm` and systemd-nspawn container tests needing `uid-range`) stay outside the gate and run on pyrite on demand, a container test with `--builders ''`.
These four inputs are decided and are not reopened here.

Nothing in code declares a class, and nothing fails a build or a test for exceeding one.
The inventory of 2026-11-24 (brainstorm.md, "What the inventory measured") found 212 small, 68 medium, 20 large and 3 enormous attributes, and 155 with no measurement.
The three enormous ones are `vmTests.x86_64-linux.fleet-ingress` (2,115–2,200 s of script, 36–39 minutes per cold run), `vmTests.x86_64-linux.devloop-ingest` (1,690–1,701 s) and `checks.x86_64-linux.package-omnigraph` (median 1,836 s from source builds that ended on 2026-11-13).

### What bounds a run today

The NixOS test driver's `globalTimeout` (default 3,600 s) bounds a runtime test's script; nothing bounds a pure build except Nix's builder-wide `timeout` and `max-silent-time` and nixbot's one global `build_timeout` (world assumptions A221, A222).
nixbot records each attribute's build in `build_attributes` from builder-slot acquisition to completion, and the dev-loop collection copies those rows into `devloop.ci_attribute` in the telemetry store (A223).
fleet-alert already evaluates SQL rules over `devloop` (`PullRequestQueueWaitBurn`, `IetsEvaluationUnhealthy`), rendered from Nix with their thresholds.
pyrite is the fleet's only host with `/dev/kvm` and takes one build at a time (A224).

### Requirements and the world they rest on

| Req | Statement (behavioral, `test-size-classes`) | Rests on | Breaks if it fails | Discharged by |
|---|---|---|---|---|
| R1 | Every test the repository declares carries exactly one size class | A225 (the measured durations behind the initial classes) | a test grows with no class to exceed | `checks.<system>.test-size-classes` (G4) |
| R2 | A runtime test whose run outlasts its class fails | A221 | a runtime test grows past its class unannounced | the `vmTests` timeout application (G3) |
| R3 | No enormous test gates a pull request, and a large check gates one only with a recorded reason | — | a pull request waits an hour on a test, or on an unexplained 15 minutes | G4 |
| R4 | A check whose recent builds outgrow its class reaches the operator without paging | A222, A223 | a check outgrows its class and nobody learns of it | `CheckOutgrewItsClass` (G5) |
| R5 | Every enormous test runs at least weekly against the default branch, with a visible result, and a failure or a missed week reaches the operator | A224 | an enormous test breaks and stays broken until someone runs it by hand | the `enormous-tests` timer and `EnormousTestStale` (G6, G7) |
| R6 | A property that needs no real time to occur is shown by a test of medium class or smaller | A225 | an agent must start a 36-minute run to check a filter | the stage 1 and 2 splits, measured (G1, G2) |

R2 bounds the script, not the driver and node builds; R4 sees only pure builds nixbot ran; the five-minute notice itself has no regulator and stays a rule for people and agents.

### Stakeholders

The operator, who reads the notices and alerts and approves the large reasons; agents that run tests before publishing; nixbot's gate; pyrite, which runs every runtime test.

## Goals / Non-Goals

**Goals:**
- Each test's class is declared once, beside the definition that makes the test.
- Every regulator that holds a class is seen failing on a mutant before it is trusted.
- The routing and filtering assertions of `fleet-ingress` and the ingest assertions of `devloop-ingest` run in a medium test.
- Six stages, each landing alone as one pull request.

**Non-Goals:**
- Shortening `fleet-ingress-outage` or `devloop-ingest-reconcile` to large: shorter sleeps, smaller queues or a shorter receiver interval would change what those cases prove; a later change can propose it with the measurement.
- Moving runtime tests onto the pull-request gate (the policy keeps them on pyrite; Open Question 4 records the possibility for container tests).
- Classes for `checks.aarch64-linux`: nothing builds it, so no class could be measured.
- Enforcing the five-minute notice in code.
- Bounding a pure build's time inside the build: no per-derivation limit exists (A222).

## Decisions

### D1: a class is declared beside its definition, as literal data in a per-system `testSizes` option

- **Choice**: a perSystem option `testSizes`, declared once in `modules/checks/test-sizes.nix` and not transposed into a flake output, typed `{ checks = attrsOf entry; vmTests = attrsOf entry; }` with `entry = { class : enum [ "small" "medium" "large" "enormous" ]; reason : nullOr str = null; measured : bool = true; }`. The module that defines a check or runtime test defines its entry in the same `perSystem` block, keyed by the attribute name. A module that generates names (`modules/checks/packages.nix`, `package-tests.nix`, `home.nix`, `containers.nix`, the machine checks) declares a literal attribute set keyed by the generated names, beside the `mapAttrs'` that generates them, and selects the class by `system` where the two systems differ (for example `package-atomic`: large on x86_64-linux, medium on aarch64-darwin). The same module exports `flake.lib.testSizeLimits = { small = 60; medium = 300; large = 900; enormous = 3600; }`.
- **Rationale**: the repository fragment requires a large check's reason "recorded beside its definition", which only co-location honours. Literal data costs nothing to read and forces no derivation. Selecting by `system`, a perSystem argument that is a string, keeps entries static. Boundary: source-only; no vendored code and nothing delivered to a host changes.
- **Alternatives considered**: (a) one central table `lib/test-sizes.nix`, the TestSizePolicy proposal: cheap and static, but it separates the reason from the definition and every new check edits one shared file; (b) `passthru.size` or `meta` on each derivation: the structural check would force every check's value to read it, about the cost of evaluating the whole set; (c) the class in the attribute name (`large-…`): a reclassification would rename the attribute and break nixbot's per-attribute history in `build_attributes`.

### D2: what a declared class means

- **Choice**: `class` is the class of one cold run as `references/test-sizes.md` defines it (the median of recent uncached nixbot runs for a check; script plus driver and node builds for a runtime test). `measured = false` marks a class not yet backed by a run. `reason` is required for `large` checks and allowed elsewhere.
- **Rationale**: the skill already defines assignment and measurement; the option records the result and does not restate the procedure.
- **Alternatives considered**: storing the measurement itself (median, slowest, date) in the entry: it goes stale on the next build and duplicates nixbot's record, which G5 reads directly.

### D3: runtime tests take their timeout from their class, applied in one place

- **Choice**: the `vmTests` option in `modules/vm-tests/default.nix` gains an `apply` that maps each test `name: test` to `test.extend { modules = [ { globalTimeout = limit; } ]; }`, where `limit` is `testSizeLimits.${testSizes.vmTests.${name}.class}`. A test with no entry fails evaluation with a message naming it. Enormous tests keep 3,600 s, the driver default, so their derivations do not change.
- **Rationale**: `passthru.extend` is the test framework's documented override (`nixos/lib/testing/call-test.nix:30` at the locked nixpkgs, manual section "sec-override-nixos-test"), and `globalTimeout` is its documented option (`driver.nix:164`); applying it centrally means no test file can omit it, and the option's `apply` maps values lazily, so the key set stays static. Boundary: vendored-versus-first-party. The vendored test framework is used through its public extension point and is not patched; the first-party side is one `apply`.
- **What it does not bound**: the timer starts just before the test script, so the driver and node builds are outside it (A221). A test whose script fits its class but whose cold build does not still passes; the measurement in each stage times the whole `nix build` to see it.
- **Alternatives considered**: (a) a `globalTimeout` line in each of the 14 test files: drifts, and nothing could check it without evaluating every test; (b) wrapping the script in `timeout`: the driver already owns the timer and releases containers and machines when it fires, which an outer `timeout` would not.

### D4: the seven runtime tests with no measurement are declared medium until measured

- **Choice**: `caddy-root-from-vars`, `greptimedb-oom-order`, `tincr-mesh-partition`, `tuwunel-server-name-guard` (x86_64-linux) and `omnigent-worker-isolation`, `zerotier-mss-clamp-runtime`, `zerotier-mss-clamp-runtime-nftables` (aarch64-linux) are declared `{ class = "medium"; measured = false; }`. The next run of each x86_64-linux test records its whole-run time and sets the class it measured, with `measured = true`. The three aarch64-linux tests stay unmeasured, with the comment that the fleet has no aarch64-linux builder; their x86_64-linux twins measured 36–62 s.
- **Checks with no recorded run**: the same rule covers the 46 gated checks with no uncached successful nixbot run (many are structural checks whose outputs nixbot found already built). Each is declared `{ class = "medium"; measured = false; }`, and the size rule (D10) reports any of them whose builds exceed 300 s once nixbot builds it uncached; stage 4 sets `measured = true` for any that gained runs since 2026-11-24.
- **Rationale**: none of the four x86_64-linux scripts has a fixed sleep, the longest condition wait is 300 s, and `tincr-mesh`, the nearest measured sibling, ran 270 s. Medium is the largest class that needs no notice, so a wrong guess fails a test at 300 s rather than letting it grow unannounced, and such a failure is the measurement that reclassifies it.
- **Alternatives considered**: enormous until measured (no bound at all); one guess per test (an argument per test for no gain); running all four now (about 20 minutes of pyrite for numbers the next ordinary run produces anyway; stage 3 runs them only because its timeout changes their derivations, task 3.6).

### D5: the structural check, and its cold evaluation cost budget

- **Choice**: `checks.x86_64-linux.test-size-classes` and `checks.aarch64-darwin.test-size-classes`, each a `runCommand` that fails with a list of findings computed at evaluation, in the style of the `structure-*` checks. Each compares `attrNames config.checks` of its own system with `attrNames config.testSizes.checks`, and the x86_64-linux one also compares `attrNames self.vmTests.x86_64-linux` and `attrNames self.vmTests.aarch64-linux` with the `vmTests` entries of those systems. Findings: an attribute with no entry; an entry naming no attribute; an enormous check; a large check with a null or empty `reason`. It declares its own entry, small.
- **Static key sets first**: `omnigent-worker-isolation.nix` and `zerotier-mss-clamp-runtime.nix` guard their `vmTests` key on `pkgs.stdenv.hostPlatform.isLinux`, so reading `vmTests.aarch64-linux`'s names from an x86_64-linux worker would instantiate aarch64-linux nixpkgs, a second nixpkgs on that worker. Both guards become `lib.elem system [ "x86_64-linux" "aarch64-linux" ]` in the same stage, with every `vmTests` `drvPath` unchanged (drvPath-identity oracle).
- **Budget**, measured with the `evaluation-cost.md` protocol, stock Nix on magnetite, before stage 4 merges and recorded with evaluator, version, host, memory and concurrent load:
  - single attribute: `checks.x86_64-linux.test-size-classes.drvPath` costs at most the `attrNames checks.x86_64-linux` key-set figure (79–80 MiB in the 2026-11 audit) plus 25 MiB of allocation and 0.5 s of CPU;
  - fleet-wide: nixbot's evaluation of the two-system set on magnetite (iets, 5 workers × 3,072 MiB, nixbot's arguments through the host lock) shows no separation between arms in an A/B/A/B benchmark, every run reported;
  - the `testSizes` entries themselves: `nix eval --json '.#.checks.x86_64-linux' --apply builtins.attrNames` allocation unchanged within run-to-run variation, which shows no entry forces anything.
  - If a figure exceeds its budget, the stage stops and the offending definitions are found with the key-set bisection before merging.
- **Rationale**: the check reads key sets nixbot already pays for plus literal data, so its marginal cost should be near zero; the budget makes that a measured claim. Placement per gated system means each worker reads only its own system's names.
- **Alternatives considered**: (a) one x86_64-linux check reading every system's checks: forces the aarch64-darwin key set, and with it that system's nixpkgs, on an x86_64-linux worker; (b) an evaluation-time `assert` in the flake: would fail every evaluation, devshells included, instead of one check run; (c) a nix-unit test: not on the gate.

### D6: large checks on the gate carry a reason; package builds share one

- **Choice**: every large check declares `reason`. The twenty large attributes today are package builds (three on x86_64-linux, seventeen on aarch64-darwin, most measured once or twice on 2026-11-11). Their entries in `modules/checks/packages.nix` carry the shared reason "a package check is the package's own build: it cannot be split, it reruns only when the package's inputs change, and a host closure that includes the package needs the same build" (Open Question 3). Stage 4 re-reads nixbot's figures for all twenty and classes each by its median then.
- **Rationale**: a reason per package would restate the same fact twenty times; a package that fits that reason badly (one that runs a test suite, say) gets its own.
- **Alternatives considered**: moving large package builds off the gate: a broken package would then reach `main` and the hosts that include it.

### D7: stage 1 splits `fleet-ingress` into a medium routing test and an enormous outage test

- **Choice**: `modules/vm-tests/fleet-ingress.nix` builds two tests from one container definition and one helper file, differing only in their case list and name:
  - `fleet-ingress`: processName, refusal, delivery, agentSession, agentSpans, schemaOrder, handoffCap, budget. These show that the ingress filters, routes, stamps and refuses what it should, that no credential, token or forbidden attribute reaches any stored column (the no-leak scans), and that the hand-off batch and budget hold. Expected: about 225 s of script without the scans (measured from 2026-11-23 markers) plus the batched scans; medium if one cold run, timed as the whole `nix build` with the node and driver rebuilt by the change, measures at most 300 s.
  - `fleet-ingress-outage`: backPressure, lossControls, crashLoop, longRun, absentClientCa, langfuse. These show what happens over real time: refusal under a full queue and its drain, loss controls at a 64 KiB queue, recovery across four SIGKILLs, ten runs of the long-run path, recovery without a client CA, and the Langfuse exporter's retry and flush timers. Expected about 1,650 s; enormous.
- **Class and margin** (stage 3): `fleet-ingress` is declared medium, with the 300 s timeout. Its script measured 252.56, 280.74 and 216.61 s in three runs on pyrite (stage 1, `logs/tsc-1-fleet-ingress-pyrite-*.log`), so its margin under the timeout has been as small as 19 s. A timeout failure there is the regulator saying the test has outgrown medium; the response is the trimming options of this decision and of Risks first (letting `processName` read an earlier scrape, moving `budget` to the outage test), then the operator's answer to Open Question 1.
- **No-leak scans**: `nonce_hits` stops issuing two driver commands per column. It runs one command in the container per scan, `python3 /etc/fleet-ingress/nonce_scan.py <netrc> <nonce>…`, a script shipped in the container's `/etc` that reads the string and JSON column list from `information_schema.columns` as `regulator` and runs the same per-column `count(*)` queries on the container's loopback, four at a time, printing `{"hits": {"<db>.<table>.<column>": count}, "columns": n, "tables": m}` as JSON. The container already carries `python3`, so the script reuses the driver helper's query construction unchanged and needs no shell quoting of SQL (implemented 2026-11-24 in place of the `writeShellApplication` with `curl` and `jq` first planned). The per-column result, and so the existing assertions (`== {"agent.session_event.prompt": 1}` as the positive control, `== {}` for the forbidden values), are unchanged. Because the scan now runs out of the driver's sight, `nonce_hits` counts the same columns from the driver before and after it and asserts that the scan read a number between the two: the 2026-11-24 mutant `scanStringOnly` showed that the positive controls alone pass a scan that skips every JSON column, since every expected hit is in a string column. Measured on pyrite on 2026-11-24, one column at a time the four scans took 111 s (12.0, 8.7, 18.5 and 71.7 s) and the script 336.65 s; four at a time they took 71 s and the script 252.56 s.
- **Names**: `fleet-ingress` keeps its name, so the discharge clauses in the corpus that cite its refusal, delivery and agent-session cases stay true. Corpus text that cites a moved case is restated in stage 1 as MODIFIED deltas added to this change. Read on 2026-11-24, they are `fleet-ingress-interface` "Each agent exports by its role" (the back-pressure case and its scenario) and "otel-envelope regulates each agent from its own collector" (the loss, back-pressure, crash-loop and long-running cases and the crash-loop scenario), `telemetry-store-interface` "Failure notices are posted to one topic" (notice cases now in both tests), and world assumption A52's evidence (the back-pressure case as its monitor). "otel-envelope on the ingress host regulates the fleet budget" cites the budget fixtures, which stay in `fleet-ingress`, and `host-metrics-collection` cites "the container runtime tests' restart and back-pressure cases" without naming a test; neither changes.
- **Rationale**: the routing assertions are the ones every collector or filter change needs; with them medium, an agent runs them without a notice, and the outage cases run weekly (D11) and on demand with a notice. Boundary: source-only (a test definition); nothing delivered to a host changes.
- **Alternatives considered**: (a) a case filter passed at build time, one attribute: one class per attribute is what the structural check and the timeout key on, and two attributes cache and fail independently; (b) one query per table with the columns OR-ed: still about 980 driver round trips across four scans, and it loses the per-column report the assertions compare; (c) shorter sleeps and queues in the outage test now: changes what it proves (Non-Goals).

### D8: stage 2 splits `devloop-ingest` the same way

- **Choice**: `devloop-ingest` keeps firstStart, noAutoCreate, overlap, tableShape, switch, documentedQueries, burnRule and ietsHealthRule (about 225 s of script on 2026-11-21; medium if one cold run measures at most 300 s); `devloop-ingest-reconcile` takes `reconcile` (about 1,468 s; enormous). `reconcile`'s guard, which sleeps to the next UTC day when less than 3,600 s remain, drops to 1,800 s, about the case's own duration plus margin, so its worst case (30 minutes of waiting plus about 25 of the case) stays under the 3,600 s timeout.
- **Implemented 2026-11-24, with one deliberate deviation**: `devloop-ingest-reconcile` runs `firstStart` and then `reconcile`, not `reconcile` alone. `reconcile` has no start of its own: in the single test it followed `firstStart`, whose `start_all()` and wait for each exporter's first send are what bring up GreptimeDB, the schema job and nixbot's PostgreSQL before the case's first leg drops tables and queries nixbot. `firstStart` is the reconcile case's precondition, not a second subject of the test; it reuses the readiness gate already proven instead of adding a weaker one, and changes no assertion (the orchestrator's decision, 2026-11-24). Two imports in case bodies gained a `noqa: F811` for the driver's linter, which saw a first import unused once the cases around it changed (`ietsHealthRule`'s `datetime` after `burnRule`'s; `reconcile`'s `re` after the helpers'); no other text of a case changed except the guard and its comment.
- **Rationale**: the receiver's 60 s interval and the 190 s and 130 s waits are what the reconcile case proves (three overlap re-reads of each new row), so they stay. The corpus requirement "devloop-ingest shows the collection path and the reconcile able to fail" and the `devloop-reconcile` requirements whose discharge cites the reconcile legs are restated in stage 2 as MODIFIED deltas. Boundary: source-only.
- **Alternatives considered**: a 10 s receiver interval in the test: shorter, but it would test a configuration production does not run.

### D9: `package-omnigraph` is re-measured before it is classed

- **Choice**: stage 4 times `nix build --rebuild .#checks.x86_64-linux.package-omnigraph` on magnetite's store and classes it by that run; it is expected small, since the package fetches upstream's release binaries (`dontBuild = true`, 924862ef6, 2026-11-13) and the aarch64-darwin build of the same derivation measured a 38 s median on 2026-11-13. If it measures enormous, the structural check fails until it leaves the gate (Open Question 5).
- **Rationale**: the 1,836 s figure measured a source build that no longer exists.

### D10: pure builds are judged after the fact by a low-priority SQL rule

- **Choice**: a fleet-alert rule `CheckOutgrewItsClass` (`database = "devloop"`, `language = "sql"`, severity `info`, which posts at the notification service's lowest priority and never pages). Its query reads `ci_attribute` rows with `status = 'succeeded'`, `NOT cached` and `finished_at` within 30 days, groups them by `attr`, and returns one row per attribute that either has at least three runs and a median `finished_at - started_at` above its class limit, or has any run above 3,600 s. The class limit per attribute is rendered into the query from the declared classes at evaluation, as a `VALUES` list of `(attr, limit_s)` for every gated check, the same way the other rules render their thresholds. `for = "1d"`, so a single slow day does not post. The posted summary names the attribute, its median and slowest run, and its class.
- **Rationale**: the data is already in the store; a rule reaches the operator only when something is wrong, without paging, through the path every other fleet alert uses. A median over at least three runs follows the skill's assignment rule and ignores one run slowed by a busy builder; the 3,600 s arm catches a single enormous run that a median would hide. Boundary: source-versus-delivered. The rule is source in `modules/nixos/fleet-alert/rules.nix` and takes effect only when magnetite deploys.
- **Unverified**: that GreptimeDB 1.2.1's SQL accepts the median aggregate the query needs (`median` or `approx_percentile_cont`). Stage 5's first task runs the query against the store before anything else.
- **Alternatives considered**: (a) a weekly report document: arrives when nothing is wrong, so it trains people to skip it; (b) a dashboard panel alone: nobody is pulled to it; (c) a nixbot patch that flags slow attributes in the check run: a new carried patch on an input.

### D11: the weekly enormous run is a timer on pyrite

- **Choice**: a NixOS module on pyrite adds `enormous-tests.service` (oneshot, root) and `enormous-tests.timer` (`OnCalendar = "Sun 03:00"`, `Persistent = true`). The service resolves `github:cameronraysmith/vanixiets/main` to one revision, reads from that revision the names it declares enormous (`nix eval --json <ref>#lib.enormousTests`, a list rendered from the `vmTests` entries of `testSizes`), and builds each `vmTests.x86_64-linux.<name>` from the same revision, one at a time, with `--builders ''`, logging each to the journal. Reading the list at run time means a test declared enormous joins the weekly run when it merges, without a pyrite deploy. A test whose derivation is unchanged since its last success is already in pyrite's store, so it costs nothing; only changed tests run. After each test the service writes `vanixiets_enormous_test_last_run_timestamp_seconds{test,result}` and, on success, `vanixiets_enormous_test_last_success_timestamp_seconds{test}` to the node exporter's textfile directory, and exits non-zero if any test failed. The unit is one of pyrite's `notifiedUnits`, so a failure posts a failure notice naming the unit; the journal names the failing test and holds its log. A fleet-alert rule `EnormousTestStale` (`warning`) fires when a test that magnetite's deployed configuration declares enormous has no success newer than 8 days, or has no series while pyrite reports host metrics. On demand: `systemctl start enormous-tests.service`, after the notice.
- **When it fails**: the failure notice reaches the operator; the failing test's log is in pyrite's journal; the fix lands as an ordinary pull request, and the test's next weekly run, or an on-demand run, clears the alert. An enormous test's failure never blocks another pull request.
- **The schedule is the notice**: a weekly run is announced once, by this design, rather than each week.
- **Rationale**: every link is existing, observed machinery (pyrite's `kvm` and `uid-range`, systemd timers, the failure notifier, fleet-alert's PromQL rules); the run happens on the only host that can run the QEMU tests, at an hour the operator is not using it. Boundary: source-versus-delivered. The module and rule are source and take effect only when pyrite and magnetite deploy. The textfile directory on pyrite is unverified: magnetite has one (`node-exporter-textfile`); stage 6's first task reads pyrite's node exporter flags and adds the directory if absent.
- **Alternatives considered**: (a) a nixbot `onSchedule` effect, `nbo schedule run` for on-demand runs: one scheduler for the fleet and exactly the default branch's tip, but nobody has verified that an effect's sandbox can run `nix build` through magnetite's daemon and have it dispatch `kvm` or `uid-range` work to pyrite, and the effect would need the ntfy credential added to its secrets to report a failure (Open Question 2); (b) on demand only: today's state, which the policy names as a gap.

### D12: documentation follows each regulator

- **Choice**: the stage that lands a regulator updates the repository fragment's test-size paragraph and the skill's `references/test-sizes.md` "What is not enforced" section to say what is now enforced and by what; the weekly-schedule sentence changes from "does not exist yet" to the timer in stage 6. The generated `AGENTS.md` and `CLAUDE.md` are never edited; they recompose from the fragments.
- **Rationale**: the fragments and the skill are source; the delivered context and skill corpus update on the next build and activation. Boundary: source-versus-delivered.

### Regulators, each with the mutant it must fail on

| # | Regulator (placement) | What it asserts | Mutant that must fail it |
|---|---|---|---|
| G1 | `fleet-ingress`'s no-leak assertions, after the scan moves into the container (stage 1), plus `nonce_hits`' column cross-check | the batched scan still reports per column, still finds every planted nonce the per-column driver loop found (the positive controls in `agentSession` and `agentSpans`), and reads every string and JSON column the driver counts around it | a scan program that stops after the first table it reads (`scanFirstTable`) fails `agentSession`'s positive control; a scan program that omits JSON columns (`scanStringOnly`) passes the positive controls, every expected hit being in a string column, and fails the column cross-check |
| G2 | the measured whole run of `fleet-ingress` and of `devloop-ingest` (stages 1, 2) | each cold run at most 300 s | not a standing regulator; G3 holds it afterwards |
| G3 | the `vmTests` `apply` (stage 3) | each test's driver `globalTimeout` equals its class limit; a test with no entry fails evaluation | a throwaway override declaring `greptimedb-pipeline` (13–16 s of script) with a 5 s limit fails on the driver's timeout; removing one test's entry fails evaluation naming it |
| G4 | `checks.<system>.test-size-classes` (stage 4) | every attribute has one entry, no entry is orphaned, no check is enormous, every large check has a reason | four mutants, each alone: a check with no entry; an entry for a missing name; a check declared enormous; a large check with `reason = null` |
| G5 | `CheckOutgrewItsClass` (stage 5) | the query returns exactly the attributes over their limit | a new `devloop-ingest` case `sizeRule` loads `ci_attribute` fixture rows (one attribute three runs over its limit, one two runs over, one a single run over 3,600 s, one within) and requires exactly the first and third; mutant `sizeRuleLimitOff` renders medium as 3,000 s and must fail; `fleet-alert`'s rendering clause pins the rendered `VALUES` list |
| G6 | `enormous-tests.service` (stage 6) | a failing enormous test fails the unit, posts one failure notice and records `result="failure"` | the unit started once on pyrite with a runtime drop-in (`systemctl edit --runtime`) that points its flake reference, an `Environment=` variable, at a throwaway tree in which `greptimedb-pipeline` (13–16 s) is declared enormous and given a failing assertion: the unit fails, one notice posts, the metric records the failure; the drop-in is removed afterwards |
| G7 | `EnormousTestStale` (stage 6) | fires on a success older than 8 days or an absent series | `fleet-alert` fixture legs `enormousStale` (a 9-day-old success; fires) and `enormousFresh` (a 1-day-old success; silent); mutant `enormousStaleAt80Days`, the rule rendered with an 80-day threshold, must fail `enormousStale` |

## Risks / Trade-offs

- [Risk] `fleet-ingress` without the outage cases still measures over 300 s cold, since the node rebuild adds to about 225 s of script → Mitigation: stage 1 does not class it medium unless measured so; the remaining levers are, in order, letting `processName` read a scrape that already happened during earlier cases instead of waiting for a fresh one, and moving `budget` to the outage test. If neither suffices, it is declared large with its measurement and reason (Open Question 1).
- [Risk] The batched scan misses a column the per-column driver loop found → Mitigation: the per-column report is unchanged, and G1's mutant plants a nonce in a JSON column.
- [Risk] A runtime test's cold build pushes its whole run past its class while its script fits → Mitigation: stage measurements time the whole `nix build`; the gap is stated in the interface trust boundary.
- [Risk] A provisional medium class is wrong and a test that used to pass fails at 300 s → Mitigation: that failure is the test's first measurement; reclassify it by a one-line change with the measurement, or split it.
- [Risk] A `testSizes` definition reads `pkgs` or a derivation and costs evaluation on every worker → Mitigation: the stage 4 key-set measurement; review keeps entries literal.
- [Risk] Concurrent changes add checks without entries and fail the gate once stage 4 lands → Mitigation: the failure names the attribute; the fix is one line; the policy text tells authors to declare a class.
- [Trade-off] A medium default for unmeasured tests over a per-test guess → accepted because it is uniform and never lets a test pass 300 s unannounced.
- [Trade-off] The weekly run on pyrite over a nixbot schedule → accepted because every link is verified now; revisited if Open Question 2 is answered the other way.
- [Trade-off] The size rule sees only nixbot's builds, not agents' local builds or runtime tests → accepted; runtime tests are bounded by G3 instead.

## Migration Plan

Six pull requests, in order; each lands alone, and none changes what a host runs until stages 5 and 6.

1. Stage 1: `fleet-ingress` split and batched scans. No deploy.
2. Stage 2: `devloop-ingest` split and the shorter guard. No deploy.
3. Stage 3: `testSizes` option, runtime-test entries and the `vmTests` timeout. No deploy. Every non-enormous runtime test's derivation changes once (its driver's timeout), so each reruns at its next use.
4. Stage 4: every check's entry, the structural check, the static `vmTests` guards. No deploy. From this merge, a new check without an entry fails the gate.
5. Stage 5: `CheckOutgrewItsClass`. Deploy magnetite (`clan machines update magnetite`); watch fleet-alert's posts for 24 hours and explain each.
6. Stage 6: `enormous-tests` on pyrite and `EnormousTestStale` on magnetite. Deploy pyrite, then magnetite; run the service once on demand (with the notice) and see its metrics and the rule's state.

Rollback: each stage reverts as one pull request. Reverting stage 5 or 6 needs the same host's redeploy. Reverting stage 3 restores every runtime test's previous derivation.

## Open Questions

1. If `fleet-ingress` measures between 300 s and 900 s after both levers in Risks, is it acceptable as a large on-demand test with its reason, or must stage 1 cut further? Recommendation: accept large with the measurement and reason; runtime tests are not on the gate, so the cost is the notice, and further cuts would change what the routing cases prove.
2. Should the weekly run be a nixbot `onSchedule` effect instead of a timer on pyrite? Recommendation: the timer now (D11); open a separate spike that builds `greptimedb-pipeline` from a scheduled effect, and move the schedule to nixbot only if that spike shows the build dispatched to pyrite and a failure reported.
3. Is the one shared reason for large package builds (D6) acceptable as the "reason recorded beside the definition"? Recommendation: yes; give a package its own reason only when its build does something other than build the package, such as running a test suite.
4. Should medium and small container tests (which need only `uid-range`, which magnetite has) later join the pull-request gate? Recommendation: not in this change; it would add their evaluation (a NixOS evaluation per test) and their GreptimeDB and collector containers to magnetite's gate load, which needs its own measurement.
5. If `package-omnigraph` measures enormous again, should it leave the gate or be declared large with a reason? Recommendation: neither is expected, since it is now a binary repackage; if it happens, blacklist it in `packages.nix` (a host closure still builds it) and report why it grew.
6. The weekly hour: Sunday 03:00 pyrite local time. Recommendation: keep it unless the operator uses pyrite then.

**Answered by the operator on 2026-11-24, each as recommended** (relayed by the orchestrator):
1. Yes: a `fleet-ingress` that measures 300–900 s after both levers becomes large and on demand, with its measurement and reason recorded.
2. The timer on pyrite now; the scheduled-effect build of `greptimedb-pipeline` is a separate trial.
3. Yes: large package builds share the one reason.
4. Not in this change.
5. Yes: if `package-omnigraph` measures enormous, it leaves the gate through `packages.nix`'s exclusion list, with the reason it grew reported.
6. Keep Sunday 03:00 pyrite local time.
