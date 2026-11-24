<!--
Raw capture of the decision chain for this change.
No interactive brainstorming session ran: the operator approved opening this change on 2026-11-24 with the policy of pull request #4224 fixed (four classes and their limits, the five-minute notice, where each class runs) and the fleet-ingress split as its first step, and was not available to answer questions while it was written.
The forks below were settled from the repository, the locked nixpkgs source and the measurements cited; each fork the operator may want to overturn is repeated as an open question in design.md.
The evidence files named below (the inventory and the TestSizePolicy report) are session artifacts outside the repository; their figures are restated here so this file stands alone.
-->

# Brainstorm: declare and hold every test to its size class

## Background

The fleet adopted a test size policy on 2026-11-24 (pull request #4224).
A run's class is the wall-clock time of one run: small up to 1 minute, medium up to 5, large up to 15, enormous up to 60, the timeouts Bazel's test encyclopedia implies for its sizes.
Before any run expected to exceed 5 minutes, whoever starts it states its expected duration, what it proves that a cheaper run cannot, and what waits on it.
Small and medium checks belong on nixbot's pull-request gate, a large check only with its reason recorded beside its definition, and an enormous test never gates a pull request.
In this repository, runtime tests (`vmTests`, QEMU and systemd-nspawn) run on pyrite on demand, outside the gate.
The policy is text in three places (the fleet-wide fragment's `## Test sizes`, this repository's fragment, and the `preferences-nix-checks-architecture` skill's `references/test-sizes.md`); nothing in code declares a class and nothing fails for exceeding one.

The trigger was a 36–39 minute `fleet-ingress` run started on 2026-11-24 to verify a two-line filter change, with no notice.

### What the inventory measured (2026-11-24, nothing built for it)

Sources: nixbot's `build_attributes` table on magnetite (uncached successful runs; the median since 2026-10-24 sets the class, the slowest is reported beside it), and the driver's `test script finished in` lines in `logs/` for the runtime tests.

| class | checks (nixbot) | runtime tests | total |
|---|---|---|---|
| small | 206 | 6 | 212 |
| medium | 65 | 3 | 68 |
| large | 20 | 0 | 20 |
| enormous | 1 | 2 | 3 |
| no data | 46, plus the 102 `checks.aarch64-linux` attributes nixbot never evaluates | 7 | 155 |

- Enormous: `vmTests.x86_64-linux.fleet-ingress` (script 2,115–2,200 s on 2026-11-23, whole run 36–39 min), `vmTests.x86_64-linux.devloop-ingest` (script 1,690–1,701 s, three runs), `checks.x86_64-linux.package-omnigraph` (median 1,836 s, slowest 3,402 s, last uncached run 2026-10-23).
- Large: twenty package builds, seventeen of them on aarch64-darwin, most measured once or twice on 2026-11-11.
- No data among runtime tests: `caddy-root-from-vars`, `greptimedb-oom-order`, `tincr-mesh-partition`, `tuwunel-server-name-guard`, and the three `vmTests.aarch64-linux` tests (`omnigent-worker-isolation`, `zerotier-mss-clamp-runtime`, `zerotier-mss-clamp-runtime-nftables`), for which the fleet has no builder.

### fleet-ingress by case (2026-11-23 full runs, from the `=== case` markers)

| case | seconds | where the time goes |
|---|---|---|
| backPressure | 384–421 | GreptimeDB stopped, then 6×30 s and 4×30 s fixed sleeps until the agent queue fills and the ingress refuses, then ~44 s draining |
| lossControls | 279–340 | ~241 s for the 64 KiB agent queue to reach 90 % at ~16 KiB/min, then ~60 s for a refused scrape on the 60 s interval |
| crashLoop | 391–399 | three fixed 120 s sleeps between four SIGKILLs |
| longRun | 269 | 70 s for each receiver's first scrape, then ten runs 20 s apart |
| langfuse | 168–187 | ~177 s idle on the exporter's 20 s retry limit and 10 s flush timeout, plus 12 s sleeps |
| agentSpans / agentSession | 226–285 / 103–134 | no real-time waits; the no-leak scans issue one SQL query per string or JSON column (~1,550 columns × 4 scans ≈ 6,200 queries, each two driver commands), 283–316 s in all |
| absentClientCa | 66–70 | a 30 s fixed sleep and collector restarts |
| processName | 66 | one 60 s process scrape on each collector |
| refusal, delivery, schemaOrder, handoffCap, budget | 13–35 each | active work |

Each case also spends ~6 s in `fresh_start`.

### devloop-ingest by case (`logs/iets-alert-green-devloop-ingest-20261121T164852Z.log`, read for this change)

From the driver timestamps before each marker: everything before `reconcile` (firstStart, noAutoCreate, overlap, tableShape, switch, documentedQueries) took ~215 s; `reconcile` took ~1,468 s (215 s to 1,683 s); `burnRule` and `ietsHealthRule` took ~5 s each.
`reconcile` waits 190 s after each leg's rows for three 60 s overlap re-reads and 130 s after each mutated receiver, and, if fewer than 3,600 s remain before 00:00 UTC, first sleeps until the next UTC day plus 60 s, so its worst case already exceeds 60 minutes.

### package-omnigraph is no longer a source build

`pkgs/by-name/omnigraph/package.nix` has fetched upstream's release binaries since 924862ef6 (2026-11-13, `dontBuild = true`); the aarch64-darwin build measured a 38 s median on 2026-11-13.
The 1,836 s x86_64-linux median comes from source builds before that commit, and no uncached x86_64-linux run has been recorded since.

### What the locked nixpkgs test driver does (nixpkgs `bd5b7d01`, read 2026-11-24)

`globalTimeout` (`nixos/lib/testing/driver.nix:164`) is an int, default 3600, passed to the driver as `global_timeout`.
The driver starts a `threading.Timer` just before the test script; when it fires it releases every machine and container and sends SIGTERM to itself, so the build fails.
It covers the test script only, not the driver or node builds.
Every test value carries `passthru.extend { modules = [ … ]; }` (`nixos/lib/testing/call-test.nix:30`), which re-evaluates the test with extra modules.
Neither Nix nor nixbot has a per-derivation wall-clock limit: Nix has builder-wide `timeout` and `max-silent-time`, nixbot one global `build_timeout`.

## Decision chain

Q1. How is a class declared?
Beside the definition, as static data in a per-system option `testSizes`, one literal entry per attribute name: `testSizes.<kind>.<name> = { class; reason ? null; measured ? true; }` where `<kind>` is `checks` or `vmTests`.
The repository fragment already requires a large check's reason "recorded beside its definition", which a central table cannot honour.
A literal entry costs nothing to read and forces no derivation; a check module that builds its entry from `pkgs` or from a derivation's attributes would defeat that, which the evaluation-cost measurement in Q4 detects.
Generated names (`package-*`, `package-*-test-*`, `nixos-*`, `darwin-*`, `home-manager-*`) are declared in the module that generates them, keyed by the generated name.
Rejected: a central table (the TestSizePolicy proposal), because it separates the reason from the definition and becomes a merge hot spot; `passthru.size` or `meta` on each derivation, because reading it from a structural check forces every check's value, about the cost of evaluating the whole set; a class encoded in the attribute name, because a reclassification would rename the attribute and break nixbot's per-attribute history.

Q2. How are runtime tests held to their class?
The `vmTests` option applies `test.extend { modules = [ { globalTimeout = limit; } ]; }` to every test, with the limit taken from its declared class, in `modules/vm-tests/default.nix`, so no test file can forget it.
A test whose script outlasts its class fails.
The limit bounds the script only; a cold run's driver and node builds come on top, so a test's whole run can exceed its class by its build time without failing; the size rule (Q5) does not see runtime tests, so this gap is stated rather than closed.
Enormous tests keep the default 3600 s, so their derivations do not change.
Rejected: a `globalTimeout` line in each of the 14 test files (drifts, and nothing would check it without evaluating every test); wrapping the test script in `timeout` (the driver already owns the timer and releases the machines).

Q3. What happens to the 7 runtime tests with no measurement?
Each is declared `medium` with `measured = false`: their scripts have no fixed sleeps and wait at most 300 s for a condition, and `tincr-mesh`, the nearest measured sibling, ran 270 s.
Medium is the largest class that does not need a notice, so a wrong guess fails a test at 5 minutes rather than letting it grow unannounced.
The next run of each records its measurement and sets `measured = true`.
The three aarch64-linux tests cannot run in the fleet (no aarch64-linux builder) and stay `measured = false` with that stated.
Rejected: `enormous` until measured (no bound at all); leaving them unclassified (the structural check then fails on day one).

Q4. What does the structural check assert, and what may it cost?
`checks.<system>.test-size-classes`, on x86_64-linux and aarch64-darwin, the two systems nixbot builds, compares `attrNames checks.<system>` (and on x86_64-linux `attrNames vmTests.x86_64-linux` and `vmTests.aarch64-linux`) with the declared names: every attribute has exactly one entry and no entry names a missing attribute; no check is enormous; every large check carries a non-empty reason.
It reads key sets that nixbot already pays for, plus literal data.
Two `vmTests` modules guard their key on `pkgs.stdenv.hostPlatform.isLinux`; reading `vmTests.aarch64-linux`'s keys from an x86_64-linux worker would instantiate aarch64-linux nixpkgs, so both guards become `system`-based first.
Budget: the check's cold single-attribute evaluation stays within 25 MiB and 0.5 s of CPU of `checks.x86_64-linux`'s key-set figure, and the fleet-wide nix-eval-jobs run on magnetite (iets, 5 × 3072 MiB) shows no difference between arms in an A/B/A/B benchmark.
`checks.aarch64-linux` is out of scope: nothing builds it, so its classes would be unmeasurable.

Q5. How are pure builds judged after the fact?
A fleet-alert SQL rule, `CheckOutgrewItsClass`, at `info` severity (low priority, never a page), over `devloop.ci_attribute`, which already holds nixbot's `build_attributes` rows.
It fires for an attribute whose median uncached successful duration over 30 days exceeds its class limit with at least three runs, or which has any run over 3600 s.
The limits are rendered into the rule's SQL from the declared classes at evaluation, as the other rules are rendered from Nix.
Rejected: a weekly report document (nobody reads a report that arrives when nothing is wrong); a dashboard panel alone (pull-only); a nixbot patch that marks slow attributes (a new carried patch on an input).

Q6. Where and how do enormous tests run weekly?
A systemd timer on pyrite, `enormous-tests`, weekly at 03:00 local on Sunday, which builds each enormous test from the forge's `main` with `--builders ''`.
A test whose derivation is unchanged since its last success is already in pyrite's store, so it costs nothing; only changed tests run.
The unit's failure posts through the failure notifier pyrite already runs, and each test's last success and last run go to the textfile collector as metrics, read by an `EnormousTestStale` rule that fires when a declared enormous test has not succeeded for 8 days.
Rejected for now: a nixbot `onSchedule` effect, which would keep every schedule in nixbot and evaluate exactly the default branch's tip, but whose ability to build a uid-range or kvm derivation on pyrite from the effect sandbox is unverified, and which would need a notification secret added to the effect; it is the operator's question Q2.
Rejected: on demand only (that is today's state, which the policy names as a gap).

Q7. How is fleet-ingress split?
Two attributes from the one file, sharing the container and helpers: `fleet-ingress` keeps the cases that assert filtering, routing, refusal and no-leak (processName, refusal, delivery, agentSession, agentSpans, schemaOrder, handoffCap, budget), and `fleet-ingress-outage` takes the cases whose behaviour needs real time (backPressure, lossControls, crashLoop, longRun, absentClientCa, langfuse).
Keeping the name for the medium part keeps every corpus discharge clause that cites the routing cases true; the corpus requirements that cite a moved case are restated in the stage that moves it.
The no-leak scan becomes one command inside the container per scan, which reads the column list and runs the per-column queries there, instead of two driver commands per column; expected cost is tens of seconds instead of 283–316 s, unmeasured.
Expected: `fleet-ingress` about 225 s of script without the scans plus the batched scans, a medium run only if the whole cold run measures at most 300 s; `fleet-ingress-outage` about 1,650 s, enormous.
Shortening the outage case's sleeps and queue sizes might make it large; that is left for a later change, because it changes what the case proves.

Q8. How is devloop-ingest split?
The same way: `devloop-ingest` keeps every case but `reconcile` (~225 s, medium if measured so), and `devloop-ingest-reconcile` takes `reconcile` (~1,468 s, enormous).
`reconcile`'s midnight guard shrinks from 3,600 s to 1,800 s, the case's own duration plus margin, so the worst case (a 30-minute wait plus 25 minutes) stays inside 3,600 s.
The 60 s receiver interval stays: the case's purpose is the production overlap re-read.

Q9. Which stages land as their own pull requests?
1. the fleet-ingress split; 2. the devloop-ingest split; 3. the `testSizes` option, the `vmTests` timeout and the runtime-test classes; 4. every check's class and the structural check; 5. the size rule; 6. the weekly run.
Each stage leaves the repository consistent on its own: stages 1 and 2 need no declaration, stage 3 declares only `vmTests`, and the structural check arrives with the full check table in stage 4.

## Trade-offs weighed

- Co-located declarations against a central table: locality and the "reason beside the definition" rule, against one file to read; the structural check gives the one-place view a table would.
- Timeout on the script against the whole run: the driver's timer is the only per-test limit that exists; the build time it misses is bounded by the store cache and visible in the run log.
- Medium for unmeasured tests against a guess per test: a uniform rule needs no argument per test and never lets a test pass 5 minutes unannounced.
- A timer on pyrite against a nixbot schedule: verified machinery now, against one scheduler later.
- Keeping names against renaming: fewer corpus restatements, at the cost of `fleet-ingress` meaning less than it did.
