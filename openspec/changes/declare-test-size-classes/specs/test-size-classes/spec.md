## ADDED Requirements

### Requirement: Every test carries one declared size class

Every check the build service builds and every runtime test SHALL carry exactly one size class, declared where the test is defined, and a pull request that adds a check without one SHALL fail the pull-request gate.
A class not yet backed by a run SHALL be marked as such until a run measures it.

**Discharged by**: `test-size-classes-interface` requirements `Each test's size class is declared beside its definition` and `The structural check fails on an unclassed, orphaned, enormous or unexplained large check`, resting on world assumption `A225 — The measured durations behind the initial size classes` for the classes first declared.

#### Scenario: A check is added without a class

- **WHEN** a pull request adds a check and declares no size class for it
- **THEN** the pull-request gate fails, naming the check

#### Scenario: A runtime test has never run

- **WHEN** a runtime test has no measured run
- **THEN** it carries the medium class, marked as unmeasured, until its first run measures it

### Requirement: A runtime test that outlasts its class fails

A runtime test whose test script outlasts the limit of its size class SHALL fail, so that a runtime test that grows past its class is seen when it is next run rather than absorbed. A runtime test's class is judged on its test script's time alone; the builds of its driver and nodes are build cost, which depends on what the store holds, and are not part of its class.

**Discharged by**: `test-size-classes-interface` requirement `Each runtime test's global timeout is its class limit`, resting on world assumption `A221 — The NixOS test driver ends a test whose script outlasts its global timeout, timing the script only`.

#### Scenario: A medium runtime test runs for six minutes

- **WHEN** a runtime test declared medium is still running its assertions 300 seconds after they began
- **THEN** the run fails

#### Scenario: An enormous runtime test

- **WHEN** a runtime test declared enormous runs
- **THEN** it fails only if its assertions run longer than 60 minutes

### Requirement: The pull-request gate holds no enormous test and no large check without a recorded reason

No enormous test SHALL be part of the pull-request gate, and a large check SHALL be part of it only with the reason it belongs there recorded where it is defined.

**Discharged by**: `test-size-classes-interface` requirement `The structural check fails on an unclassed, orphaned, enormous or unexplained large check`.

#### Scenario: A check is declared enormous

- **WHEN** a pull request declares a check enormous
- **THEN** the pull-request gate fails, naming the check

#### Scenario: A large check without a reason

- **WHEN** a pull request declares a check large and records no reason
- **THEN** the pull-request gate fails, naming the check

### Requirement: A check that outgrows its class reaches the operator without paging

A check whose recent runs on the build service take longer than its size class allows, judged by the median of at least three runs within 30 days, or any one of whose runs takes longer than 60 minutes, SHALL reach the operator as a low-priority alert naming the check, its median and slowest run, and its class. A run is a successful build of the check's own output, by this repository's project, that took at least one second.

**Discharged by**: `test-size-classes-interface` requirement `CheckOutgrewItsClass reports a check over its class limit`, resting on world assumptions `A222 — Neither Nix nor nixbot bounds the build time of one derivation` and `A223 — nixbot times an attribute's build from its builder slot to its completion, and an output already present gets no duration`.

#### Scenario: A medium check's builds take seven minutes

- **WHEN** a check declared medium has three runs in the last 30 days, each taking about 420 seconds
- **THEN** a low-priority alert names the check, its median, its slowest run and its class

#### Scenario: One slow run

- **WHEN** a check declared small has ten runs in the last 30 days, one of which took 200 seconds on a busy day
- **THEN** no alert is posted

#### Scenario: A check runs for more than an hour once

- **WHEN** any run of a check takes longer than 60 minutes
- **THEN** a low-priority alert names the check, whatever its median

### Requirement: A check declared without a measurement is reported once its runs measure it

A check declared without a measured run SHALL reach the operator as a low-priority alert once it has three runs within 30 days, naming its median and slowest run, its declared class and the class its runs give, so that its declaration is corrected.

**Discharged by**: `test-size-classes-interface` requirement `CheckOutgrewItsClass reports a check over its class limit`, resting on world assumption `A223 — nixbot times an attribute's build from its builder slot to its completion, and an output already present gets no duration`.

#### Scenario: A check declared without a measurement gains three runs

- **WHEN** a check declared medium and unmeasured has three runs in the last 30 days, each taking about 30 seconds
- **THEN** a low-priority alert names the check, its median, its slowest run, its declared class and the class its runs give, small

### Requirement: Every enormous test runs weekly with a visible result

Every enormous test SHALL be run as a scheduled run at least once a week against the default branch's latest commit, its outcome SHALL be recorded where the operator can read it, a failed run SHALL reach the operator as a failure notice, and an enormous test that has not passed for eight days SHALL reach the operator as an alert.

**Discharged by**: `test-size-classes-interface` requirements `enormous-tests builds every enormous runtime test from the default branch weekly, and records every runtime test's script time` and `EnormousTestStale fires when an enormous test has not passed for eight days`, resting on world assumption `A224 — pyrite is the fleet's only kvm host, takes one build at a time, and is the operator's laptop`.

#### Scenario: An enormous test fails on the default branch

- **WHEN** the weekly scheduled run of an enormous test fails
- **THEN** a failure notice reaches the operator, and the run's record names the failing test

#### Scenario: The weekly run does not happen

- **WHEN** an enormous test has had no passing run for eight days, because its runs failed or because none started
- **THEN** an alert names the test

#### Scenario: Nothing changed

- **WHEN** nothing an enormous test depends on changed since its last passing run
- **THEN** its scheduled run passes without running it again

### Requirement: Behaviour that needs no elapsed time is shown by a test no larger than medium

A property of the fleet that does not depend on elapsed-time behaviour, such as filtering, routing, refusal, the absence of a forbidden value from storage, or the shape of stored records, SHALL be shown by a test of medium class or smaller, and only elapsed-time behaviour SHALL justify a large or enormous test.

**Discharged by**: `test-size-classes-interface` requirement `Routing and ingest assertions run apart from elapsed-time cases`, resting on world assumption `A225 — The measured durations behind the initial size classes` for the measurements that placed them.

#### Scenario: An agent checks a filter change to the fleet ingress

- **WHEN** an agent changes what the fleet ingress filters or routes and runs the test that shows it
- **THEN** its test script takes at most 5 minutes and the run needs no run notice

#### Scenario: The ingress's outage behaviour

- **WHEN** the ingress's behaviour across a store outage, a full queue or a crash loop is to be shown
- **THEN** a separate enormous test shows it, run weekly or after a run notice

### Requirement: A size class constrains what a test may wait on, its time per run and its cost over time, each by its own regulator

A declared size class SHALL constrain three properties of a test, each held by its own regulator: what it may wait on, so that a small test waits on no passage of time while a medium or large test may wait within its limit, and behaviour whose point is the passage of time runs only in the tests named for it; the time of one run, held by a timeout on the test script as tight as it can be without flakiness; and its cost over time, held on its recorded runs, never on one run.

**Discharged by**: `test-size-classes-interface` requirements `Routing and ingest assertions run apart from elapsed-time cases` (kind), `Each runtime test's global timeout is its class limit` (ceiling), `CheckOutgrewItsClass reports a check over its class limit` and `RuntimeTestCostDrift reports a runtime test whose script time grows or whose margin is smaller than its spread` (cost over time), resting on world assumptions `A221 — The NixOS test driver ends a test whose script outlasts its global timeout, timing the script only` and `A223 — nixbot times an attribute's build from its builder slot to its completion, and an output already present gets no duration`.

#### Scenario: A medium test gains a case whose point is an outage window

- **WHEN** a case that shows behaviour across a store outage, a queue filling at its real rate or a crash loop is added to a medium runtime test
- **THEN** it is moved to the enormous test the interface names for such cases, whatever the medium test's measured time

#### Scenario: A small test sleeps

- **WHEN** a case of a small test waits on a sleep or on an interval
- **THEN** it is rewritten to wait for the event it needs, or the test is declared medium with its measurement

#### Scenario: A runtime test's script time spreads towards its limit

- **WHEN** a medium runtime test's recorded script times range from 216 to 281 seconds, a spread wider than its margin under 300 seconds
- **THEN** a low-priority alert names the test, its recorded times and its class, before an unlucky run fails at the limit

#### Scenario: A stable test close to its limit

- **WHEN** a medium runtime test's recorded script times stay within two seconds of 269 seconds
- **THEN** no alert is posted

### Requirement: A short bounded timeout that shows something does not happen is not a wait on time

A short, bounded timeout that shows that something does not happen, such as a resolver that does not answer or a connection that is refused, SHALL NOT count as waiting on the passage of time, because no event exists to wait for and the bound is the proof; such a timeout SHALL be the tool's own, of a few seconds, and the case's time SHALL be recorded with each run.

**Discharged by**: the per-case times each measured run records from the test's case markers; `tincr-mesh-partition`'s resolver case, two `dig +tries=1 +time=2` queries against stopped resolvers, about 4 seconds of its 38.40 to 38.60 seconds (`declare-test-size-classes` stages 3 and 4).

#### Scenario: A small test shows that a stopped resolver does not answer

- **WHEN** a case of a small test queries each stopped resolver once with the client's own 2-second timeout and requires no answer
- **THEN** the test stays small, and the case's time is recorded with the run's per-case times

### Requirement: Variation that comes from inside a test is removed in the test

A test whose script time varies between runs for a reason internal to the test, such as its phase against a scrape, export or flush interval, SHALL be treated as defective, and the variation SHALL be removed in the test, so that it waits for the event it needs rather than the next tick of an interval; a timeout SHALL NOT be loosened, and a class SHALL NOT be raised, to absorb such variation.

**Discharged by**: the per-case times each measured run records from the test's case markers, compared across runs; `fleet-ingress`'s `processName`, which took 10 or 66 seconds by its phase against the collectors' 60-second process scrape and, with that wait removed, took 5 seconds (`declare-test-size-classes` stage 3).

#### Scenario: A case's time depends on a scrape's phase

- **WHEN** a case's time differs between runs by about one scrape interval
- **THEN** the case is changed to wait for the scrape it needs, its assertions unchanged, and the test's timeout and class stay as they were

### Requirement: A run expected to exceed five minutes is preceded by a run notice

A person or agent SHALL give a run notice before starting any run expected to take longer than 5 minutes, and an agent working for another agent SHALL return with the notice instead of starting the run.

**Discharged by**: the fleet-wide agent context's "Test sizes" section and the subagent dispatch contract, which state the rule to every agent; no regulator observes a notice, so this requirement is discharged by instruction alone, and a scheduled run's notice is the schedule's own declaration.

#### Scenario: An agent is about to start an enormous test

- **WHEN** an agent working for an orchestrator is about to start a run expected to take 30 minutes
- **THEN** it returns with the expected duration, what the run proves that a cheaper run cannot, and what waits on it, and does not start the run

#### Scenario: A scheduled run

- **WHEN** the weekly scheduled run starts an enormous test
- **THEN** no further notice is given, because the schedule is the declared notice
