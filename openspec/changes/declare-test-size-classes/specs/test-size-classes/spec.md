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

A runtime test whose run outlasts the limit of its size class SHALL fail, so that a runtime test that grows past its class is seen when it is next run rather than absorbed.

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

A check whose recent runs on the build service take longer than its size class allows, judged by the median of at least three runs within 30 days, or any one of whose runs takes longer than 60 minutes, SHALL reach the operator as a low-priority alert naming the check, its median and slowest run, and its class.

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

### Requirement: Every enormous test runs weekly with a visible result

Every enormous test SHALL be run as a scheduled run at least once a week against the default branch's latest commit, its outcome SHALL be recorded where the operator can read it, a failed run SHALL reach the operator as a failure notice, and an enormous test that has not passed for eight days SHALL reach the operator as an alert.

**Discharged by**: `test-size-classes-interface` requirements `enormous-tests builds every enormous runtime test from the default branch weekly` and `EnormousTestStale fires when an enormous test has not passed for eight days`, resting on world assumption `A224 — pyrite is the fleet's only kvm host, takes one build at a time, and is the operator's laptop`.

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
- **THEN** that run takes at most 5 minutes and needs no run notice

#### Scenario: The ingress's outage behaviour

- **WHEN** the ingress's behaviour across a store outage, a full queue or a crash loop is to be shown
- **THEN** a separate enormous test shows it, run weekly or after a run notice

### Requirement: A run expected to exceed five minutes is preceded by a run notice

A person or agent SHALL give a run notice before starting any run expected to take longer than 5 minutes, and an agent working for another agent SHALL return with the notice instead of starting the run.

**Discharged by**: the fleet-wide agent context's "Test sizes" section and the subagent dispatch contract, which state the rule to every agent; no regulator observes a notice, so this requirement is discharged by instruction alone, and a scheduled run's notice is the schedule's own declaration.

#### Scenario: An agent is about to start an enormous test

- **WHEN** an agent working for an orchestrator is about to start a run expected to take 30 minutes
- **THEN** it returns with the expected duration, what the run proves that a cheaper run cannot, and what waits on it, and does not start the run

#### Scenario: A scheduled run

- **WHEN** the weekly scheduled run starts an enormous test
- **THEN** no further notice is given, because the schedule is the declared notice
