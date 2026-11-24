# Test sizes: assigning, measuring, and outgrowing a class

This reference is the procedure behind "Test sizes" in the parent skill.
The four classes and the five-minute notice are fleet-wide rules carried by the agent context; this file says how a check or test gets its class, how one run is measured, and what to do when a check outgrows its class.
The figures quoted are measurements from this repository, not targets.

## The classes

| class | one run takes at most | where it runs |
|---|---|---|
| small | 1 minute | the pull-request gate |
| medium | 5 minutes | the pull-request gate |
| large | 15 minutes | the pull-request gate only with a recorded reason, otherwise on demand |
| enormous | 60 minutes | never the pull-request gate; a schedule, or on demand |

The limits are the timeouts Bazel implies for its test sizes: short 60 s, moderate 300 s, long 900 s and eternal 3600 s ([test encyclopedia](https://bazel.build/reference/test-encyclopedia)).
Bazel's size also sets a test's assumed memory and CPU; these classes measure wall-clock time only.
Before any run expected to exceed 5 minutes, that is any large or enormous run, the person or agent starting it states its expected duration, what it proves that a cheaper run cannot, and what waits on its result.

## Assigning a class

A class is a measured property of one cold run on the runner that executes it, not an estimate from the test's design.
A cold run is one in which the check's own output is in no store or cache the runner consults; dependencies built only for this check count toward it, because a pull request that changes them pays for them as well.
A check built by CI takes the class of the median of its recent uncached runs there, with the slowest run reported beside it, because concurrent builds on a shared builder lengthen individual runs.
A NixOS VM or container test takes the class of its whole run: the test script plus the driver and node builds.
A test that has never run has no class yet, and its first run is announced if it may exceed 5 minutes.

The class a test needs follows from what it asserts.
An assertion about configuration, filtering, routing, or a pure function is small or medium.
Only behaviour that takes real time to occur, such as an outage window, retries with backoff, a scrape or export interval, or a crash loop, justifies a large or enormous case.

## Measuring one run

For a check built by nixbot, query its PostgreSQL database for the attribute's uncached successful runs:

```sql
SELECT system, count(*) AS runs,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM finished_at - started_at)) AS median_s,
       max(extract(epoch FROM finished_at - started_at)) AS slowest_s,
       max(finished_at) AS latest
FROM build_attributes
WHERE attr = 'checks.x86_64-linux.<name>' AND status = 'succeeded' AND NOT cached
  AND finished_at > now() - interval '30 days'
GROUP BY system;
```

nixbot sets `started_at` after the attribute acquires a builder slot, so the duration excludes queue wait and includes the dependencies built for the attribute and the upload that follows.
An attribute whose output was already in nixbot's store has status `skipped_local` and no duration.

For a check built locally, `nix build --rebuild .#checks.<system>.<name>` rebuilds only the top-level derivation once its output exists, so timing it measures the check's own run without its dependencies.
Capture the run with `tee` into `logs/` as for any long-running command.

For a NixOS VM or container test, the driver prints `test script finished in <seconds>`, and every driver line carries `[<seconds>s]` counted from the driver's start.
A test script that prints a marker at the start of each case, such as `print("=== case <name>", flush=True)`, can be split by case from its log: a case's duration is the timestamp before the next case's marker minus the timestamp before its own.
Time the whole `nix build` as well, since the class covers the driver and node builds.

## When a check outgrows its class

A check whose measured run exceeds its class, or exceeds what its purpose needs, is a defect to report with the measurement (median, slowest, source, and date) and a proposal.
The proposal takes one of three forms.
Split the check into cases that each fit the class their purpose needs, as separate attributes so that each builds, caches, and fails on its own.
Move the slow part, the cases that wait out real time, into a case of the larger class that runs on that class's cadence.
Remove time the purpose does not need: replace a fixed sleep with polling for the condition, shorten an interval in the test's own configuration, or batch many driver round trips into one command.
Raising the class instead is a decision recorded beside the check's definition with its reason, the same record a large check on the pull-request gate needs.

`vmTests.x86_64-linux.fleet-ingress` is the measured instance.
Its test script ran 2,115 to 2,200 s on 2026-11-23 across 14 cases.
Four cases that exercise outage and recovery (`backPressure`, `lossControls`, `crashLoop`, `longRun`) took 1,360 to 1,390 s, most of it fixed sleeps and waits on the collectors' intervals.
The no-leak scans in `agentSession` and `agentSpans` issue one SQL query per string or JSON column of every table, about 1,550 columns per scan and four scans per run, so about 6,200 queries, each two driver commands, took 280 to 320 s.
Without those scans, the seven cases that assert filtering, routing, and refusal took 185 to 195 s, a medium run; the outage cases alone are an enormous one, and `langfuse`, whose waits follow its exporter's retry and flush timers, belongs with them.
The test was split on 2026-11-24 (`declare-test-size-classes` stage 1) into two attributes built from one container definition.
`fleet-ingress` keeps the eight cases that assert filtering, routing, refusal, the absence of forbidden values, the hand-off cap and the budget.
Each of its scans now runs as one command inside the container, four queries at a time, and the driver checks the scan's column count against its own.
Its script measured 252.56 to 280.74 s on pyrite, a medium run.
`fleet-ingress-outage` takes `langfuse`, `backPressure`, `lossControls`, `crashLoop`, `longRun` and `absentClientCa`, an enormous run.

## What is not enforced

Nothing fails a build or a test for exceeding its class.
Classes are declared and announced by the people and agents who run checks, and a check's measured duration is visible only in nixbot's records and the driver's log.
