# Test sizes: assigning, measuring, and outgrowing a class

This reference is the procedure behind "Test sizes" in the parent skill.
The four classes and the five-minute notice are fleet-wide rules carried by the agent context; this file says how a check or test gets its class, how one run is measured, and what to do when a check outgrows its class.
The figures quoted are measurements from this repository, not targets.

## The classes

A class says two things about a test: what it may touch or wait on, and how long one run may take.
Google's test sizes are defined the same way, by a table of features (network, database, file system, threads, sleep statements, system properties, external systems) of which the time limit is one row of eight, so that a size is a name for measurable criteria a test can be policed on ([Test Sizes](https://testing.googleblog.com/2010/12/test-sizes.html), 2010).
Adapted to a Nix repository, where every check builds in the sandbox and every runtime test runs in its own VMs or containers:

| | small | medium | large | enormous |
|---|---|---|---|---|
| one run takes at most | 1 minute | 5 minutes | 15 minutes | 60 minutes |
| may wait on the passage of time (a sleep, a scrape, export, flush or retry interval) | no | yes, within its limit | yes, within its limit | yes, within its limit |
| reaches anything outside its sandbox or its own VMs and containers | no | no | no | no |
| where it runs | the pull-request gate | the pull-request gate | the gate only with a recorded reason, otherwise on demand | never the gate; a schedule, or on demand |

The limits are the timeouts Bazel implies for its test sizes: short 60 s, moderate 300 s, long 900 s and eternal 3600 s ([test encyclopedia](https://bazel.build/reference/test-encyclopedia)).
Bazel keeps a test's size and its timeout as separate attributes and advises setting the timeout as tight as it can be without incurring flakiness; a test whose time varies with its own timers is fixed in the test, not given a looser timeout or a larger class.
Before any run expected to exceed 5 minutes, that is any large or enormous run, the person or agent starting it states its expected duration, what it proves that a cheaper run cannot, and what waits on its result.

A class constrains three properties, and each has its own regulator.
What a test may wait on is deterministic and is held structurally: a small test waits on no passage of time, and behaviour whose point is the passage of time (an outage window, a queue filling at its real rate, a crash loop) lives in the tests kept for it, by which cases each test contains.
The time of one run is held by a timeout on that run.
Growth over many runs, and a spread wider than the margin under the limit, are statistical and are held on recorded runs, never on one run.

## Assigning a class

A class is a measured property of one cold run on the runner that executes it, not an estimate from the test's design.
A cold run is one in which the check's own output is in no store or cache the runner consults; dependencies built only for this check count toward it, because a pull request that changes them pays for them as well.
A check built by CI takes the class of the median of its recent uncached runs there, with the slowest run reported beside it, because concurrent builds on a shared builder lengthen individual runs.
A run is a build that happened: a record that took under a second built nothing, whatever its status says, and is not counted.
The median is over the last 30 days when there are at least three runs, otherwise over every recorded run when there are at least three, noted with their number and dates; with fewer, the check has no measured class yet.
One run is not a class: it may fall on a day when the builder is busy, or on the day a large dependency was rebuilt.
Checks that share a dependency rebuild it together in one build, each waiting on it, so each one's duration holds the whole shared build, which is what a cold build of either alone would take; judge each on its own runs, and treat a pair that crosses a limit together as one cost to cut in the shared dependency.
Where runs straddle the limit whose higher class would take a check off the pull-request gate, the lower class is declared and marked as a boundary until fresh runs decide it, because removing a regulator is the costlier error.
A NixOS VM or container test takes the class of its test script, the driver's `test script finished in`, which is what its timeout enforces; its driver and node builds are build cost, which depends on what the store holds, and are not part of its class.
A test that has never run has no class yet, and its first run is announced if it may exceed 5 minutes.

The class a test needs follows from what it asserts.
An assertion about configuration, filtering, routing, or a pure function is small or medium.
Only behaviour whose point is the passage of time, such as an outage window, retries with backoff or a crash loop, justifies a large or enormous case; a medium test may still wait on a scrape or export interval as a means, within its limit.
A small test waits on no passage of time; a tool's own timeout of a few seconds that shows something does not happen, such as a resolver that does not answer or a connection that is refused, is not such a wait, because no event exists to wait for and the bound is the proof, and the case's time is recorded with each run.

## Measuring one run

For a check built by nixbot, query its PostgreSQL database for the attribute's uncached successful runs:

```sql
SELECT ba.system, count(*) AS runs,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM ba.finished_at - ba.started_at)) AS median_s,
       max(extract(epoch FROM ba.finished_at - ba.started_at)) AS slowest_s,
       max(ba.finished_at) AS latest
FROM build_attributes ba
JOIN builds b ON b.id = ba.build_id
JOIN projects p ON p.id = b.project_id
WHERE p.owner = '<owner>' AND p.name = '<repository>'
  AND ba.attr = 'checks.x86_64-linux.<name>' AND ba.status = 'succeeded' AND NOT ba.cached
  AND ba.finished_at - ba.started_at >= interval '1 second'
  AND ba.finished_at > now() - interval '30 days'
GROUP BY ba.system;
```

nixbot sets `started_at` after the attribute acquires a builder slot, so the duration excludes queue wait and includes the dependencies built for the attribute and the upload that follows.
An attribute whose output was already in nixbot's store has status `skipped_local` and no duration.
Filter by project: nixbot builds other repositories whose checks can share a name (`treefmt`, `gitleaks`), and without the filter their runs count into this one's.
The telemetry store's `devloop.ci_attribute` copy holds the same rows with a `project` column, and GreptimeDB's `median` gives the same exact median.

For a check built locally, `nix build --rebuild .#checks.<system>.<name>` rebuilds only the top-level derivation once its output exists, so timing it measures the check's own run without its dependencies.
Capture the run with `tee` into `logs/` as for any long-running command.

For a NixOS VM or container test, the driver prints `test script finished in <seconds>`, and every driver line carries `[<seconds>s]` counted from the driver's start.
A test script that prints a marker at the start of each case, such as `print("=== case <name>", flush=True)`, can be split by case from its log: a case's duration is the timestamp before the next case's marker minus the timestamp before its own.
Record each case's time beside earlier runs: a case whose time differs between runs by about one interval of a scrape, export or flush is waiting on its phase against that interval, which is a defect in the test (see below).
Time the whole `nix build` as well, so that a slow cold build is visible, although build cost is not part of a runtime test's class.
In vanixiets, run a runtime test on Pyrite itself, `ssh pyrite.vanixiets.internal nix build --builders '' '<source>#vmTests.x86_64-linux.<name>'` against a source already on Pyrite (a checkout there, or the store path `nix flake archive --to ssh-ng://pyrite.vanixiets.internal` prints), so that the measurement is Pyrite's.
`nix build --store ssh-ng://pyrite… --builders ''` from another host does not keep the build on Pyrite: the flag does not reach Pyrite's daemon, which on 2026-11-24 handed such a `fleet-ingress` build to Magnetite, where a case failed (`logs/tsc-1-fleet-ingress-20261124-111732.log`).

## When a check outgrows its class

A check whose measured run exceeds its class, or exceeds what its purpose needs, is a defect to report with the measurement (median, slowest, source, and date) and a proposal.
The proposal takes one of three forms.
Split the check into cases that each fit the class their purpose needs, as separate attributes so that each builds, caches, and fails on its own.
Move the slow part, the cases that wait out real time, into a case of the larger class that runs on that class's cadence.
Remove time the purpose does not need: replace a fixed sleep with polling for the condition, shorten an interval in the test's own configuration, start the thing a case observes before the event that samples it rather than waiting for the next sample, or batch many driver round trips into one command.
A case whose time varies with its phase against its own timers is fixed this way before anything else; the timeout is not loosened and the class not raised to absorb the variation.
Raising the class instead is a decision recorded beside the check's definition with its reason, the same record a large check on the pull-request gate needs.

`vmTests.x86_64-linux.fleet-ingress` is the measured instance.
Its test script ran 2,115 to 2,200 s on 2026-11-23 across 14 cases.
Four cases that exercise outage and recovery (`backPressure`, `lossControls`, `crashLoop`, `longRun`) took 1,360 to 1,390 s, most of it fixed sleeps and waits on the collectors' intervals.
The no-leak scans in `agentSession` and `agentSpans` issue one SQL query per string or JSON column of every table, about 1,550 columns per scan and four scans per run, so about 6,200 queries, each two driver commands, took 280 to 320 s.
Without those scans, the seven cases that assert filtering, routing, and refusal took 185 to 195 s, a medium run; the outage cases alone are an enormous one, and `langfuse`, whose waits follow its exporter's retry and flush timers, belongs with them.
The test was split on 2026-11-24 (`declare-test-size-classes` stage 1) into two attributes built from one container definition.
`fleet-ingress` keeps the eight cases that assert filtering, routing, refusal, the absence of forbidden values, the hand-off cap and the budget.
Each of its scans now runs as one command inside the container, four queries at a time, and the driver checks the scan's column count against its own.
Its script measured 216.61 to 280.74 s on pyrite in three runs, then reached its 300 s timeout in the first run under it.
Its per-case times showed why: `processName` took 10 s or 66 s, by where its process landed against the collectors' 60 s process scrape.
The case now starts its process before restarting the collectors, so their first scrape after the restart sees it; it took 5 s, and the script 189.37 s.
`fleet-ingress-outage` takes `langfuse`, `backPressure`, `lossControls`, `crashLoop`, `longRun` and `absentClientCa`, an enormous run.

`vmTests.x86_64-linux.devloop-ingest` was split the same way (stage 2), moving the slow part whole.
Its `reconcile` case took about 1,468 s of its 1,690 to 1,701 s, waiting out the receiver's 60 s polls, which is what it proves.
`devloop-ingest` keeps the other eight cases and measured 229.54 s of script, 246 s for the whole build, on pyrite on 2026-11-24, a medium run.
`devloop-ingest-reconcile` runs `firstStart`, the reconcile case's readiness precondition, then `reconcile`, and measured 1,490.54 s of script, 1,506 s for the whole build, an enormous run.

## What is enforced

In vanixiets, each runtime test declares its class beside its definition, `testSizes.vmTests.<name> = { class; reason ? null; measured ? true; }` in the module that defines the test, and `modules/vm-tests/default.nix` sets every test's driver `globalTimeout` to its class limit through the test framework's `extend` (`declare-test-size-classes` stage 3).
A test with no entry fails evaluation, naming it.
The driver starts that timer just before the test script; when it fires, the driver logs `timeout reached; test terminating...`, releases every VM and container and kills itself, so the build fails.
A test that no run has measured is declared medium with `measured = false`: a wrong guess fails at 5 minutes, and that run is its measurement.

In vanixiets, every check on the gated systems declares its class the same way in `testSizes.checks`, generated names in a literal set beside the code that generates them, and `checks.<system>.test-size-classes` fails the pull-request gate on a check with no entry, an entry naming no attribute, an enormous check, or a large check with no reason (stage 4); on x86_64-linux it also fails on a runtime test of x86_64-linux or aarch64-linux with no entry or an entry naming none.
It reads key sets and the literal entries only, so it forces no check's derivation.
In vanixiets, each x86_64-linux runtime test also has an evaluation check on that gate, `checks.x86_64-linux.vm-test-evaluates-<name>`, whose entry `modules/checks/vm-test-evaluates.nix` lists literally, so a new runtime test needs both entries.

In vanixiets, a check's cost over time is judged after the fact by fleet-alert's `CheckOutgrewItsClass` (stage 5), an SQL rule at severity `info`, which posts at low priority and never pages.
It reads the telemetry store's copy of nixbot's records, this repository's uncached successful runs of at least 1 s in the last 30 days, and posts a check that has at least three of them and a median above its class limit, a check declared `measured = false` that has three of them, with the class they give so its entry can be corrected, or a check with any run above an hour.
Its per-check limits are rendered from the `testSizes` entries at evaluation, and `checks.x86_64-linux.fleet-alert` pins the rendered list.

In vanixiets, every runtime test runs weekly on pyrite (stage 6): `enormous-tests.service`, started by its timer on Sundays at 03:00 America/New_York, fetches `main` once, evaluates every `vmTests.x86_64-linux` test under the host evaluation lock, and builds each with `--builders ''`, the enormous ones first, writing one record per test to the telemetry store's `devloop.runtime_test_result`.
A record is `passed` with the driver's `test script finished in` from that build's own log, `timed_out` with the class limit, `failed`, or `present` when the test's output was already in the store or the build succeeded without running the script, which is not a run.
A failed, timed-out or unevaluated test fails the unit, which posts a failure notice.
fleet-alert's `RuntimeTestCostDrift` (severity `info`) judges each test's newest 8 runs within 180 days by the class and limit of its newest record: it posts a test whose newest 3 runs' median exceeds the older runs' by more than a tenth of the limit, or whose margin under the limit is smaller than its range.
`EnormousTestStale` (`warning`) posts an enormous test with no `passed` or `present` record in 8 days, or with none at all.

## What is not enforced

The timer does not cover the driver and node builds, so a test whose script fits its class can still take longer as a whole cold run; that time is build cost, not part of the class, and no regulator judges it.
`RuntimeTestCostDrift` sees only the weekly run's runs, not on-demand ones, and a result record of a non-enormous test lost on its way to the store is not detected; a week in which pyrite is off or off the mesh shows only as `EnormousTestStale` for the enormous tests.
Nothing observes whether a person or agent gave a run notice.

How long one build of a check takes is not bounded while it runs: `CheckOutgrewItsClass` sees only builds nixbot recorded for this repository, after they finish, so no local build and no runtime test, and it never judges one run.
