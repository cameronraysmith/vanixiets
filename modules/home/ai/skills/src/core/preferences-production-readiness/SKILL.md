---
name: preferences-production-readiness
description: >
  Production readiness and observability-driven development practices for
  deploying, operating, and learning from production systems. Covers
  production readiness checklists, observability-driven development (ODD),
  progressive delivery, CI/CD pipeline observability, incident learning
  closure, and the feedback topology from alerting through SLO revision.
  Load when deploying to production, defining health checks, designing
  progressive delivery, conducting post-incident review, instrumenting
  CI/CD pipelines, or defining production readiness criteria.
---

# Production readiness

## Production readiness as an engineering discipline

Production readiness is not a checklist bolted onto the end of development.
It is a design constraint that shapes implementation from the start, just as type safety and test adequacy do.
A system is production-ready when operators can answer "what is happening and why?" for any observed behavior using only the system's own telemetry, without shipping new code.

This definition mirrors the observability criterion from `preferences-observability-engineering`: production readiness is the state where the system's observability is sufficient for its operational context.
The distinction between the two skills is one of emphasis.
`preferences-observability-engineering` addresses the conceptual model and instrumentation principles — what to measure, how to structure telemetry, and why certain approaches to metrics and tracing outperform others.
This skill addresses the operational envelope — how to verify that instrumentation is adequate before serving traffic, how to deploy safely, and how to learn from production incidents so the system improves over time.

Neither skill is complete without the other.
Instrumentation without operational discipline produces telemetry nobody watches.
Operational discipline without principled instrumentation produces dashboards that cannot answer novel questions.
The goal is a continuous feedback loop where production experience informs instrumentation choices, and instrumentation choices improve production experience.

Production readiness also connects to the testing discipline described in `preferences-validation-assurance`.
Pre-production testing and production observability form a complementary pair: testing provides confidence that the system behaves correctly under controlled conditions, while observability provides confidence that the system behaves correctly under real conditions.
The testing pyramid and the observability stack are not alternatives — they are two views of the same confidence-building enterprise, operating at different points in the system's lifecycle.
The CI/CD/CV trichotomy captures this relationship: continuous integration validates correctness against a specification, continuous delivery validates deployment mechanics, and continuous validation ensures the system remains correct under production conditions indefinitely.

## The production readiness checklist

The items below are not a gate review to be checked once and forgotten.
They are ongoing properties that a production system must maintain throughout its lifecycle.
Each item exists because its absence has caused real outages, and each should be verifiable by automated means rather than human inspection alone.

A useful framing: the production readiness checklist is the set of preconditions under which an operator can diagnose any problem without deploying new code.
If a problem requires adding a new metric, a new log field, or a new trace span before it can be understood, the system was not production-ready for that class of problem.
The checklist aims to minimize the surface area of problems that require code changes to diagnose.
It cannot eliminate that surface area entirely — novel failure modes will always exist — but it can ensure that the most common classes of operational questions are answerable from existing telemetry.

### Health endpoints

Three distinct health signals serve different consumers at different timescales.
Conflating them into a single `/health` endpoint forces operators to choose between restarting a process that is merely warming up and routing traffic to a process that cannot serve it.

The liveness probe confirms the process is running and not deadlocked.
It returns a success status if the server can accept and process requests at all.
Orchestrators use this signal to decide when to restart a stuck process.
The liveness probe should be the simplest possible check — if it depends on external resources, a database outage will cause cascading restarts across the fleet.

The readiness probe confirms the service can serve traffic correctly.
It checks connectivity to dependencies the service requires: database connections, cache availability, event bus subscriptions.
Load balancers use this signal to route traffic away from instances that are running but cannot fulfill requests.
When a dependency becomes unreachable, the readiness probe should fail, removing the instance from the load balancer pool without killing the process.
This distinction between "alive but not ready" and "dead" prevents unnecessary restarts during transient dependency failures.

The startup probe confirms that initial setup is complete.
Migrations have run, caches have warmed, configuration has been validated.
This probe prevents premature traffic routing during slow startups and provides a distinct signal from readiness — a service that has never been ready is different from a service that was ready and stopped being ready.
Without a startup probe, orchestrators must guess at timeout values for initial readiness, leading to either premature restarts of slow-starting services or delayed detection of genuinely broken deployments.

### Metrics emission

Two complementary metric frameworks provide the minimum viable telemetry for any service.

RED metrics — rate, errors, duration — apply at every service boundary.
Rate measures throughput: how many requests per unit time.
Errors measures failure rate: what fraction of requests fail, broken down by error category.
Duration measures latency: how long requests take, captured as histograms or percentile summaries rather than averages.
Averages hide the tail latency that degrades user experience, so percentiles (p50, p95, p99) are the standard representation.
Every API endpoint, every RPC call, every message consumer should emit RED metrics.
If a service boundary exists without RED metrics, operators cannot reason about its behavior.

USE metrics — utilization, saturation, errors — apply to every significant resource the service manages.
CPU, memory, disk, network interfaces, connection pools, thread pools, and queue depths all warrant USE instrumentation.
Utilization measures what fraction of a resource's capacity is in use.
Saturation measures the degree to which excess work is queued or rejected.
Errors measures resource-specific failure modes like disk write failures or connection pool exhaustion.
USE metrics enable capacity planning and help distinguish between application-level problems (visible in RED metrics) and infrastructure-level problems (visible in USE metrics).

Business metrics complement RED and USE when business outcomes need tracking.
Revenue per transaction, signup completion rate, search result relevance — these can be attached as span attributes within the tracing system or emitted as dedicated metric instruments.
The decision depends on cardinality: low-cardinality business dimensions fit well as metric labels, while high-cardinality dimensions like user ID belong in trace spans where they can be queried without the storage cost of metric explosion.

### Structured logging

Logs serve a different purpose from metrics and traces.
Metrics answer "how much?" over time.
Traces answer "what happened during this request?"
Logs answer "what did the code actually do at this point?"
All three are necessary, but logs are the most frequently misused, generating noise that obscures signal.

The guiding principle is one structured event per request per service, not multiple narrative log lines scattered through the code path.
A single wide event containing all relevant fields for a request — user ID, endpoint, status, duration, error details, feature flags — is more useful than twenty narrow log lines emitted at different points.
Wide events are queryable across any combination of fields without predicting in advance which combinations will matter.

Every log entry must include correlation identifiers — trace ID and span ID — so that logs can be joined to their corresponding traces.
Without correlation, debugging requires manual timeline reconstruction across services, which is slow and error-prone.

Field naming must be consistent across services.
Established conventions like the OpenTelemetry semantic conventions provide a shared vocabulary that makes cross-service queries possible.
When service A calls `http.status_code` and service B calls `response.status`, correlating their behavior requires a translation layer that should not exist.
Agree on naming conventions early and enforce them through shared libraries or linters.

Log levels deserve careful calibration.
The distinction between error, warning, info, and debug is not a matter of taste — it determines which logs are retained, which trigger alerts, and which are sampled or dropped under load.
An error log should indicate something that requires human attention.
A warning indicates a condition that may become a problem if it persists.
Info records normal operational events.
Debug provides implementation details useful during development but typically too voluminous for production retention.
Services that emit errors for expected conditions (like a cache miss or a retried request) train operators to ignore error-level logs, which is the logging equivalent of alert fatigue.

### Alerting

Alerts are the mechanism by which the system tells operators that user experience may be degrading.
Poorly designed alerts cause two failure modes: alert fatigue (too many non-actionable alerts cause operators to ignore them) and silent failures (insufficient alerts allow degradation to persist unnoticed).

SLO-based burn rate alerting, as described in `preferences-observability-engineering`, avoids both failure modes by alerting on the rate at which the error budget is being consumed rather than on instantaneous threshold violations.
A brief latency spike that self-resolves does not consume enough error budget to trigger an alert.
A sustained degradation that threatens the SLO target does.
This approach aligns alert severity with actual user impact.

Every alert must have two properties.
First, it must be a reliable indicator of user experience degradation — alerts that fire without user impact are noise.
Second, it must provide an actionable debugging path — an alert that says "something is wrong" without pointing toward investigation steps wastes the time of whoever is paged.

Runbooks accompany each alert, explaining the expected investigation steps and mitigation options.
A runbook is not a script to follow mechanically — it is a starting point that helps the responder orient quickly.
Runbooks should be updated after each incident where the existing runbook proved insufficient, creating a gradual improvement cycle.

### On-call

On-call is the organizational structure that ensures someone is responsible for responding to alerts.
Three properties distinguish sustainable on-call from the kind that burns people out.

Clear escalation paths mean that every responder knows who to contact when they cannot resolve an issue alone.
Escalation is not a sign of failure — it is a normal part of incident response for problems that span multiple domains.

Rotation prevents hero culture.
No single person should be the ultimate escalation point for any system.
If one person holds irreplaceable knowledge, that knowledge must be documented and distributed, not relied upon as a human single point of failure.

Sustainable page volume means that if on-call consistently wakes people at night, the problem is in the alerting configuration, not in the people.
Every page that wakes someone should be reviewed: was it actionable? Did it indicate real user impact?
Non-actionable pages should be eliminated or downgraded to non-paging severity.
The goal is a page volume where on-call is a reasonable professional responsibility, not a source of dread.

On-call quality is a leading indicator of system maturity.
A system with frequent, actionable pages has real problems that need architectural attention.
A system with frequent, non-actionable pages has alerting problems that need tuning.
A system with infrequent, actionable pages has reached a level of operational maturity where on-call is boring — and boring on-call is the goal.

## Observability-driven development

Observability-driven development is the production complement to test-driven development.
Where TDD ensures software adheres to an isolated specification, ODD ensures software works under real production conditions.
TDD and ODD are not alternatives — they operate at different scales and provide different kinds of evidence, both necessary.

The asymmetry between pre-production and production environments is fundamental.
Pre-production tests run against synthetic data, controlled traffic patterns, and isolated dependencies.
Production runs against real data with real distributions, real traffic patterns with real concurrency, and real dependencies with real failure modes.
No amount of pre-production testing can replicate the combinatorial complexity of production.
This is not a failure of testing — it is a structural property of complex systems.
ODD accepts this asymmetry and builds the practices needed to close the gap between pre-production confidence and production reality.

The prescriptive rule is straightforward: pull requests should never be submitted or accepted without first asking, "How will I know if this change is working as intended?"
This question must have a concrete answer rooted in the system's telemetry.
Instrumentation is reviewed in code review with the same rigor as business logic.
A change that alters behavior without adding or updating the instrumentation that makes that behavior observable is incomplete, just as a change without tests is incomplete.

Four questions every engineer must answer after deployment.
Is the code doing what you expected it to do?
How does it compare to the previous version?
Are users actively using the code?
Are any abnormal conditions emerging?
If the instrumentation in a pull request cannot answer these four questions, the pull request is not ready to merge.
These questions cannot be answered by pre-production testing alone because they concern real user behavior under real load with real data distributions.

The ship-then-watch cycle makes these questions operational rather than aspirational.
Engineers watch their code as it deploys, and spend time daily exploring their code in production.
The person who merged the code is automatically paged for thirty to sixty minutes post-deploy — not as punishment, but as the essential feedback loop between authoring and consequences.
You cannot develop the instincts needed to ship quality code if you are insulated from the feedback of your errors.
Over time, this practice builds an engineering culture where production awareness is the norm rather than the exception.

Speed and quality reinforce each other in this model.
The DORA Accelerate research demonstrates that for elite-performing teams, deployment frequency and stability metrics improve in tandem.
When deployment frequency increases, failures become smaller, happen less often, and are easier to recover from.
Teams that deploy slowly accumulate larger changesets, making each deployment riskier, making failures harder to diagnose, and making recovery slower.
ODD breaks this cycle by making each deployment's impact immediately visible, which in turn makes frequent small deployments the obviously safer strategy.

The common objection is that instrumentation slows development — that adding telemetry to every change is overhead.
The opposite is true in practice.
Teams that instrument well spend less total time on debugging because the telemetry answers questions that would otherwise require hours of log spelunking or reproduction attempts.
The investment in instrumentation during development is repaid many times over during operations.
Moreover, instrumentation written by the author of the code is higher quality than instrumentation added retroactively by someone unfamiliar with the design intent.
The author knows which invariants matter, which edge cases are likely, and which dimensions are worth capturing.
Instrumentation is a form of documentation that happens to be machine-readable and queryable.

## Progressive delivery

Progressive delivery decouples deployments from releases.
A deployment puts new code on servers.
A release exposes new functionality to users.
These are fundamentally different operations with different risk profiles, different rollback mechanisms, and different observability requirements.
Feature flags are the mechanism that separates these two events.
This separation is powerful because it allows code to be deployed and validated in production before any user sees it, and it allows releases to be rolled back instantly without a new deployment.
A deployment rollback requires redeploying the previous version, which takes minutes and carries its own risks.
A release rollback requires flipping a flag, which takes seconds and affects only the feature in question.

Feature flags introduce novel combinations of flag states that cannot be exhaustively tested before production.
The number of possible combinations grows exponentially with the number of flags, making pre-production coverage of all paths impractical.
Observability is required to understand the individual and collective impact of each flag, segmented by user cohort.
Monitoring behavior component-by-component no longer holds when a single endpoint can execute multiple code paths depending on user identity and flag assignments.
The observability system must support high-cardinality queries that filter by flag state, user segment, and endpoint simultaneously.

Progressive delivery patterns — canary, blue-green, rolling — all require observability to function correctly.
A canary deployment routes a small percentage of traffic to the new version while the rest continues on the old version.
Without observability, you cannot compare the behavior of the canary population against the baseline population to determine whether the new version is safe to promote.
Blue-green deployment maintains two full environments and switches traffic between them, requiring observability to confirm that the new environment behaves correctly before cutting over.
Rolling deployments update instances incrementally, requiring observability to detect degradation early enough to halt the rollout before all instances are affected.

In all these patterns, the observability data is the decision function for promotion or rollback.
Without it, promotion decisions are based on time ("it's been running for an hour with no complaints") or luck ("nobody has reported a problem yet").
Neither is a reliable indicator that the new version is correct.

The concrete sequence is: deploy behind a feature flag, expose to a subset of users, observe behavior with instrumentation, confirm the four post-deployment questions, progressively widen exposure, and complete the full release.
This creates seconds-to-minutes feedback loops instead of the hours-to-days cycles of traditional release processes.
Each widening step is a decision point where the telemetry either supports continued promotion or signals a halt.

Feature flags themselves require lifecycle management.
A flag that exists permanently becomes technical debt — a conditional branch in the code that nobody dares remove because nobody remembers whether it is still needed.
Flags should have an expiration policy: after a feature is fully released, the flag and its associated conditional logic must be removed.
Short-lived release flags and long-lived operational flags (kill switches, graceful degradation toggles) serve different purposes and deserve different lifecycle policies.
The observability system should track which flags are active, which users are in which cohorts, and how flag states correlate with error rates and latency distributions.
This telemetry is essential both for progressive delivery decisions and for understanding the system's behavior when multiple flags interact.

### Graceful degradation

Production-ready systems degrade gracefully rather than failing catastrophically.
When a dependency becomes unavailable, the system should continue serving requests at reduced functionality rather than returning errors to all users.
Circuit breakers prevent cascading failures by short-circuiting calls to failing dependencies after a threshold of failures is reached.
Fallback responses — cached data, default values, reduced feature sets — maintain partial service while the dependency recovers.

Graceful degradation requires the same observability as progressive delivery.
The system must know which degradation modes are active, how many users are affected, and whether the degraded experience is acceptable.
Without this telemetry, a circuit breaker that fires may go unnoticed until users report that a feature is missing, by which point the dependency may have recovered and the circuit breaker may have closed, making the problem impossible to reproduce.
Degradation events should be emitted as structured telemetry with the same dimensions as normal requests, enabling comparison between full-functionality and degraded-functionality cohorts.

## CI/CD pipeline observability

CI/CD pipelines are distributed systems.
They involve multiple machines, network calls, shared resources, race conditions, and intermittent failures — the same characteristics that make production services hard to debug.
For teams that build and maintain CI/CD infrastructure, the pipelines themselves are their production workload, and they need observability for the same reasons application teams do.

The cardinality of CI/CD telemetry may be lower than application telemetry — there are fewer concurrent builds than concurrent user requests — but the criticality of any single event is higher.
A broken build blocks an entire team.
A flaky test that fails intermittently erodes trust in the entire testing suite.
A slow pipeline step that adds ten minutes to every build costs the organization cumulative hours of engineering time daily.
These problems are invisible without structured telemetry and are fiendishly difficult to debug with traditional log-based approaches.

The instrumentation strategy mirrors application instrumentation: emit structured events with shared dimensions — commit hash, worker label, hostname, test suite name, build step, error messages, latency — and stitch events into traces across pipeline stages using trace context propagation.
A single build should be queryable as a trace from commit push through test execution through artifact publication through deployment.
When a build fails, the trace should reveal which step failed, on which worker, with which configuration, and how that step's timing compares to its historical distribution.

Practical outcomes from applying this approach are well-documented.
Teams that have added tracing to end-to-end tests have identified configuration dimensions correlated with flaky tests within days, dropping suite flake rates from double-digit percentages to well under one percent.
Anomalous runtimes caused by stale auto-scaling hosts have been discovered within minutes of having trace data on CI infrastructure.
Multi-day incidents involving interactions between CI runners and test environments have been resolved in under two hours by examining cross-service traces.

Build caching deserves particular attention because cache misses are among the most common causes of pipeline slowdowns, yet they are invisible without telemetry.
A cache hit rate metric, broken down by cache layer (source, dependency, artifact) and by worker, reveals whether the caching strategy is effective and whether specific workers or configurations are underperforming.
Cache invalidation events should be traced to their cause — was the cache busted by a dependency update, a configuration change, or a worker rotation?
Without this data, teams experience intermittent slow builds and have no way to distinguish systemic caching problems from one-off events.

The software supply chain encompasses everything that goes into or affects software from development through CI/CD until production.
A failure at any point in this chain represents a slowdown in developer velocity.
CI/CD observability is therefore a direct investment in engineering productivity — the same engineering productivity that the DORA research identifies as a key predictor of organizational performance.

One practical consideration: CI/CD telemetry often reveals problems that have been accepted as normal.
"Builds are slow" is a common complaint that teams live with because they lack the data to identify the specific bottleneck.
Tracing a build end-to-end frequently reveals that the majority of wall-clock time is spent in a small number of steps — dependency resolution, a particular test suite, artifact upload — that can be individually optimized once identified.
Similarly, flaky tests are often accepted as background noise until telemetry reveals their true cost: the hours of engineering time spent re-running pipelines, investigating false failures, and losing confidence in the test suite.
Making these costs visible through telemetry converts vague frustration into specific, actionable improvement targets.

## Incident learning closure

Incidents are learning events, not failures to be blamed.
The goal of incident review is not to find who did something wrong but to understand how the system's design, tooling, and processes allowed the incident to happen and how they can be improved.
Blame-oriented incident review suppresses the information flow that organizations need to improve, because people stop reporting near-misses and contributing honestly to reviews when they fear consequences.

The learning closure principle requires that every incident produce at least one concrete improvement to the system's observability or operational posture.
A new telemetry signal that would have detected the problem sooner.
A dashboard enhancement that makes the relevant data more accessible.
An alert refinement that would have paged earlier or with better context.
An architectural change that eliminates the failure mode entirely.
The specific improvement matters less than the discipline of always producing one — this is the mechanism by which the system's observability improves over time rather than remaining static.

Learning closure connects directly to the severity criterion from `preferences-validation-assurance`.
An incident reveals that some aspect of the system's behavior was not adequately covered by either pre-production testing or production observability.
The post-incident improvement should target whichever gap contributed more to the incident's impact.
If the failure mode could have been caught by a high-severity test but no such test existed, write the test.
If the failure mode was inherently unpredictable in pre-production but could have been detected faster with better instrumentation, add the instrumentation.
Often both are appropriate — the test prevents regression and the instrumentation provides early detection if a similar-but-different problem emerges.

One anti-pattern deserves particular attention: the reactive runbook spiral.
After each outage, the team writes a runbook for that specific failure, creates custom dashboards for the specific metrics involved, and adds new alerts for the specific thresholds that were violated.
In modern distributed systems where truly novel problems constitute the bulk of all problems, the team will rarely see the same problem again.
The runbooks accumulate, the dashboards proliferate, and the alerts multiply — all preparing for the last war while the next incident arrives from an unexpected direction.
The effort is better invested in improving general observability — wider events, better instrumentation coverage, more powerful query capabilities — than in preparing for the specific failure that just happened.
General observability addresses the next novel problem; specific dashboards address only the last one.

A second anti-pattern is hero culture.
The senior engineer who never takes a real vacation because they are the ultimate escalation point.
This is detrimental at every level: for the organization (single point of failure in human form), for the hero (sustained stress and burnout), and for junior engineers (no opportunity to develop debugging skills because they are never given hard problems to solve).
Observability democratizes debugging by making the system's behavior legible to anyone with access to the tooling, not only to those who have accumulated years of scar tissue from previous incidents.
When debugging requires first-principles analysis of telemetry rather than recalled knowledge of historical incidents, any competent engineer can investigate effectively.

Incident severity classification should be based on user impact, not on internal system symptoms.
A database failover that triggers alerts but causes no user-visible degradation is a low-severity incident.
A subtle data corruption that affects a small number of users but goes undetected for days is a high-severity incident despite generating no alerts.
Impact-based classification ensures that incident review effort is allocated proportionally to the actual consequences, not to the volume of internal noise generated.

## Feedback topology

Production operates through six nested feedback loops at different timescales.
These loops are not sequential stages — they operate concurrently, each informing the others.
Together they form the continuous validation regime within which individual CI/CD episodes are embedded.

Alerting operates on the timescale of seconds to minutes.
SLO burn rate detection triggers investigation when the error budget consumption rate indicates a trajectory toward SLO violation.
This is the fastest feedback loop, designed to catch active degradation before it becomes an outage.
The quality of this loop depends entirely on the quality of the SLO definitions and the instrumentation that measures them.
False positives erode trust and lead to alert fatigue; false negatives allow degradation to persist.
Tuning this loop is a continuous process informed by the incident learning loop below.

Deployment observation operates on the timescale of minutes to hours.
The ship-then-watch cycle and progressive delivery promotion and rollback decisions happen here.
Engineers observe their code in production, compare behavior to the previous version, and decide whether to promote or halt.
This loop catches problems that pre-production testing could not surface because they depend on real traffic patterns, real data distributions, or real infrastructure conditions.

Incident learning operates on the timescale of days to weeks.
Post-incident review examines what happened, why it happened, and what improvement to make.
The learning closure principle ensures this loop produces concrete observability improvements rather than only narrative accounts.
Each incident makes the system more observable, which makes the faster loops (alerting and deployment observation) more effective.

Capacity planning operates on the timescale of weeks to months.
Trend analysis of resource utilization over time informs scaling decisions.
Historical telemetry reveals growth patterns, seasonal variations, and the relationship between traffic volume and resource consumption.
Without this loop, scaling is reactive — responding to capacity exhaustion rather than anticipating it.

Chaos engineering operates on the timescale of weeks to months.
Active fault injection tests resilience hypotheses: "if this database fails, does the circuit breaker engage correctly?"
Chaos engineering also validates that the observability system itself detects injected faults — if you inject a failure and the alerting system does not notice, the alerting system needs improvement.
This loop is the only one that actively probes the system's failure modes rather than waiting for them to occur naturally.
The value of chaos engineering is proportional to the maturity of the observability system — injecting faults without the ability to observe their effects produces noise rather than insight.

SLO revision operates on the timescale of quarters to years.
SLO targets are adjusted based on accumulated operational experience, changes in business requirements, and evolution of user expectations.
An SLO that was appropriate at launch may be too loose after the service becomes business-critical, or too tight after architectural improvements make the service more reliable than it needs to be.
This is the slowest loop, but it governs the behavior of all the faster loops because SLO targets are the reference signal against which burn rate alerting, deployment decisions, and error budget policies are calibrated.

The nested structure of these loops means that improvements at slower timescales have cascading effects on faster timescales.
A better SLO definition improves alerting quality.
Better alerting improves deployment observation.
Better deployment observation feeds richer data into incident reviews.
Incident reviews produce observability improvements that make the next round of alerting, deployment observation, and capacity planning more effective.
The feedback topology is not a hierarchy but a cycle, and the system's operational maturity is a function of how well these loops reinforce each other.

The system is never "done."
Continuous validation is the ambient regime within which CI/CD episodes are embedded.
This framing is elaborated in `docs/notes/research/continuous-validation-observability-engineering-guide.md`, which develops the relationship between the CI/CD/CV trichotomy and the observability-driven practices described here.

## Cross-references

The following skills address adjacent concerns that interact with production readiness.

`preferences-observability-engineering` provides the foundational observability model, SLO framework, and instrumentation principles that production readiness operationalizes.
Without the conceptual foundations from that skill, the practices here lack grounding; without the operational practices here, the concepts there lack teeth.

`preferences-validation-assurance` addresses the testing discipline that provides pre-production confidence.
It covers the severity criterion, refinement as freedom preservation, and test adequacy — the CI side of the CI/CD/CV trichotomy that this skill extends into CD and CV.

`preferences-change-management` covers the change control practices that govern how changes move through the pipeline.
Production readiness intersects with change management at the deployment boundary, where change control policies determine the conditions under which a deployment is authorized.

`preferences-web-application-deployment` addresses deployment platform patterns — the mechanical concerns of how code reaches production infrastructure.
This skill addresses the observability and operational concerns that surround those mechanics.

`preferences-architectural-patterns` defines where observability instrumentation fits in the system architecture.
Hexagonal architecture, for example, places instrumentation at port boundaries, which aligns with the RED metrics recommendation to instrument every service boundary.

`preferences-distributed-systems` covers consistency models, failure modes, and coordination patterns for distributed systems.
Production readiness for distributed systems involves additional concerns — partition tolerance, consistency guarantees under failure, and the observability needed to distinguish between partial failures and total outages — that build on the foundations described here.

## Canonical references

- Majors, C., Fong-Jones, L. & Miranda, G. -- *Observability Engineering* (O'Reilly, 2022), especially chapters 11 (observability-driven development), 12-13 (SLOs and alerting), and 14 (software supply chain)
- Forsgren, N., Humble, J. & Kim, G. -- *Accelerate: The Science of Lean Software and DevOps* (IT Revolution, 2018), DORA metrics and speed/quality reinforcement
- Beyer, B., Jones, C., Petoff, J. & Murphy, N. -- *Site Reliability Engineering* (O'Reilly, 2016), chapters on SLOs, monitoring, and on-call
- Allspaw, J. -- "Trade-offs Under Pressure" (2020), incident learning and adaptive capacity
- Hollnagel, E. -- *Safety-II in Practice* (Routledge, 2018), systems operating on a degradation continuum
