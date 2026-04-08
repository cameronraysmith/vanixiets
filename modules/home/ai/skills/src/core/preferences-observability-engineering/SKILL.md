---
name: preferences-observability-engineering
description: >
  Observability engineering foundations for understanding system behavior
  through structured events, distributed traces, and service-level objectives.
  Covers the observability paradigm (structured events, high cardinality,
  high dimensionality, explorability), SLO-driven reliability, instrumentation
  principles, telemetry architecture, tool category taxonomy, anti-patterns,
  and maturity model. Load when designing instrumentation, adding telemetry,
  working with OpenTelemetry, structured events, tracing, metrics, analyzing
  production behavior, SLO definition, or alerting strategy.
---

# Observability engineering

## Core model

Observability for software systems is the ability to understand any state the system can get into, no matter how novel, without shipping new code.
This definition originates from Rudolf Kalman's 1960 control theory work: a system is observable if every internal state can be inferred from external outputs.
For software, this means understanding states you have never seen before using only external tools and existing telemetry.

The atomic unit of observability is the arbitrarily wide structured event: a single key-value record capturing everything that occurred while one request interacted with one service.
Initialize an empty map when a request enters a service.
Append every interesting detail as the request proceeds: identifiers, variable values, headers, parameters, execution times, remote call results, durations.
Emit the completed map when the request exits or errors.
Mature instrumentation commonly produces 300-400 dimensions per event, and the cost of adding a new field is negligible once the infrastructure exists.

The structured event is not a log line.
Log lines are unstructured strings optimized for human reading; structured events are key-value maps optimized for programmatic querying.
A log line that says "User 12345 purchased item 67890 in 234ms" contains all the relevant information but in a format that resists aggregation, filtering, and correlation.
The equivalent structured event `{user_id: 12345, item_id: 67890, duration_ms: 234, action: "purchase"}` supports arbitrary queries without parsing.
This distinction is foundational: the shift from unstructured logs to structured events is not a formatting preference but an epistemic upgrade that makes the data explorable.

The actual pillars of observability are properties of the data and the analysis it enables, not data format categories.

High cardinality refers to the uniqueness of field values.
User IDs, request IDs, build IDs, and session tokens are high-cardinality fields because each value appears rarely or uniquely.
High-cardinality fields are always the most useful for debugging because they let you follow a specific request, user, or session through the system.
When a user reports a problem, the user ID is the dimension that isolates their experience from all other users.
When a deployment introduces a regression, the build ID is the dimension that isolates the affected deployment.
Without high-cardinality fields, investigation can only identify patterns across aggregates ("latency increased for the east region") but cannot identify specific entities ("user X experienced 30-second latency because request Y hit a cold cache on shard Z").
Cardinality can be downsampled but never upsized: once you aggregate away individual values, you cannot recover them.

High dimensionality refers to the number of keys per event.
Wider events carry richer context and enable discovery of patterns that narrow events cannot reveal.
An event with 5 fields allows investigation along 5 axes; an event with 300 fields allows investigation along 300 axes.
Each additional dimension is an additional question you can ask during debugging without shipping new instrumentation.

Explorability is the ability to iteratively investigate any system state without predicting your debugging needs in advance.
This is the capability that distinguishes observability from monitoring.
A monitoring system requires you to decide in advance what questions to ask (by defining dashboards, alerts, and detectors).
An observable system lets you ask questions you never anticipated, because the raw high-cardinality, high-dimensional data is available for ad hoc exploration.

Monitoring addresses known-unknowns: failure modes you predicted could happen, for which you built specific detectors.
Observability addresses unknown-unknowns: novel failures you could not have predicted, which you investigate by exploring high-cardinality, high-dimensional data after the fact.
In modern distributed systems, the ratio of novel failures to predicted failures is heavily weighted toward the novel.
Systems composed of many services interacting in complex ways produce emergent failure modes that no one anticipated during design.
The combinatorial explosion of interaction patterns between services, versions, configurations, and traffic patterns produces a state space that no team can enumerate in advance.

The framing of observability as "metrics, logs, and traces" is vendor marketing that reduces the discipline to data format categories while ignoring the analysis practices and data properties that actually matter.
This framing is addressed further in the anti-patterns section.

## Observability in distributed systems

The need for observability grows superlinearly with system distribution.
A monolithic application has a single process, a single log stream, and a single stack trace per error.
Debugging is difficult but tractable: attach a debugger, read the logs, step through the code.
A distributed system has N processes, N log streams, and errors that manifest as cascading failures across service boundaries where the root cause may be in a different service from the one that produced the user-visible error.

The fundamental challenge is that no single service has a complete view of any request's lifecycle.
Each service sees only its own processing of the request.
The request's journey through multiple services — including retries, timeouts, fallbacks, and partial failures — is visible only by correlating data across all participating services.
This correlation is the primary function of distributed tracing, described in detail in `03-telemetry-architecture.md`.

Distributed systems also exhibit emergent behavior that is not present in any individual service.
A service that is individually healthy may participate in system-level pathologies: retry storms, cascading timeouts, load-induced feedback loops, and resource contention across shared infrastructure.
These emergent behaviors are invisible to per-service monitoring but visible through cross-service trace analysis and system-wide SLI measurement.

The partial failure model of distributed systems means that requests succeed or fail depending on which subset of services and infrastructure they happen to touch.
Two identical requests issued one second apart may follow different paths, hit different caches, reach different database replicas, and experience different outcomes.
Observability must capture this path diversity: the trace shows which specific path a request took, which specific infrastructure it touched, and which specific conditions it encountered.
Aggregate metrics that report "99th percentile latency is 500ms" cannot reveal why a specific user's request took 30 seconds.

The implication for instrumentation is that every service boundary — every HTTP call, every message publish, every database query, every cache lookup — is a potential observation point that should carry trace context.
Gaps in trace propagation create blind spots where the request's journey becomes invisible, forcing investigators to guess at what happened between the last observed span and the next.

The "works on my machine" phenomenon is a special case of this challenge.
A developer testing locally exercises a single service in isolation.
The production system exercises that service as part of a distributed computation involving many services, each with their own state, configuration, and failure modes.
Observability bridges this gap by making the distributed production behavior visible in a way that local testing cannot replicate.
This is the operational manifestation of the testing-observability duality: testing validates the single-service closed world, observability validates the multi-service open world.

## The duality with testing

Testing and observability are dual disciplines addressing complementary epistemic regimes.
Testing operates in a closed world with controlled inputs and deterministic verification.
It is catamorphic in nature: an initial algebra that folds inputs through the system under test, yielding a verdict.
The test author controls the inputs, the environment, and the success criteria.
The verdict is binary: the test passes or fails.

Observability operates in an open world with unbounded inputs and coinductive validation.
It is anamorphic in nature: a final coalgebra that unfolds behavior to reconstruct the internal state from external outputs.
The observer does not control the inputs; real users, real traffic, and real environmental conditions drive the system.
The goal is not a binary verdict but a reconstruction of what happened and why.

A system with comprehensive test coverage but no observability has proven its rocket launches but not that it stays in orbit.
Testing verifies that the system handles the scenarios the test author anticipated.
Observability reveals what the system does when confronted with scenarios no one anticipated.
A system with full observability but no tests can detect failure but cannot prevent predictable regressions.
Neither discipline subsumes the other; they form a duality where each covers the other's blind spots.

The practical implication is that investment in one without the other yields diminishing returns.
A heavily tested system without observability will eventually encounter a production failure that no test anticipated, and the team will have no tools to investigate it.
A heavily observed system without tests will repeatedly encounter failures that testing would have caught before deployment, wasting production debugging effort on preventable problems.
The optimal allocation invests in both, with the balance determined by the system's maturity and failure mode distribution.

Full observability in the formal sense means bisimilarity implies state equality: you can distinguish any two distinct internal states by their observable behavior alone.
When two states are observationally equivalent (they produce the same outputs for all inputs), they are behaviorally interchangeable, and the system has no hidden modes that telemetry cannot reach.
This is the coinductive counterpart to the severity criterion from `preferences-validation-assurance`: severity asks whether a test would distinguish correct from incorrect implementations, while observational completeness asks whether telemetry would distinguish any two distinct internal states.

The theoretical treatment of this duality, including the categorical foundations and the relationship between initial algebras and final coalgebras, is developed in `docs/notes/research/continuous-validation-observability-engineering-guide.md`.
The testing side of the duality is covered in `preferences-validation-assurance`, which establishes the severity criterion and confidence promotion chain for the catamorphic regime.

## The core analysis loop

The debugging methodology that replaces dashboard-staring and intuition-based troubleshooting is a systematic loop that narrows the search space with each iteration.

Start with the overall view of what prompted the investigation: an SLO burn alert, a user report, or an anomalous pattern in a summary view.
This starting point establishes the scope: which service, which time range, which user-facing behavior is affected.

Verify that something is actually changing by comparing the current state to a recent baseline.
The baseline is a time range where behavior was known to be normal — typically the same time range on the previous day or the previous week, depending on traffic patterns.
If the current state looks the same as the baseline, the investigation may be a false alarm or the wrong signal.

Search for dimensions that drive the change by diffing all dimension values between the anomalous population and the baseline population.
This is a brute-force comparison across every attribute in the structured events: for each dimension, compute the distribution of values in the anomalous population and the baseline population, and measure the divergence.
Sort the dimensions by divergence percentage.
The dimension with the largest divergence is the strongest signal for what distinguishes the anomalous behavior from normal behavior.

Filter to isolate that dimension (e.g., "show me only requests where build_id = abc123") and repeat the process on the filtered population.
Now the question becomes: within this filtered population, which remaining dimensions drive the anomaly?
Each iteration narrows the scope further.

The loop is a fixed-point computation: it converges when the filtered population is narrow enough to identify the root cause, or narrow enough that switching to code-level debugging (a debugger, profiler, or source code review) is productive.
The brute-force dimension diff can be automated; some backends provide this capability under various names.
Even without automation, the discipline of systematically diffing dimensions rather than guessing at causes produces faster and more reliable investigations.

This methodology works because wide structured events capture the dimensions needed for investigation at emit time, before anyone knows which dimensions will matter.
The alternative — instrumenting after the fact to answer specific questions — requires the problem to recur, which may not happen, and delays resolution by the time needed to deploy new instrumentation.

Observability is the telescope: finding where in the system to look.
The debugger or profiler is the microscope: understanding the specific code once the location is known.
Trying to use a telescope as a microscope (drilling into code from a dashboard) or a microscope as a telescope (stepping through code without knowing which service is the culprit) wastes effort.
The core analysis loop is the discipline of using the right instrument at the right scale.

The loop has an important property: it does not require expertise in the specific system being debugged.
An engineer who has never seen a service before can run the dimension diff, identify the divergent dimensions, and narrow down to the root cause without prior knowledge of the service's architecture or failure modes.
This democratization of debugging is one of the most significant organizational benefits of observability: it breaks the dependency on hero culture and enables any engineer to investigate any service.

The loop also has a learning property: each investigation teaches the engineer about the system.
After following the dimension diff to discover that a latency spike was caused by a specific database shard under contention, the engineer understands something about the system's data distribution and infrastructure that no documentation conveyed.
Over time, the core analysis loop produces engineers who understand the system deeply through direct investigation rather than through tribal knowledge transfer.

A common failure mode is abandoning the loop prematurely.
When the dimension diff reveals a plausible cause (a specific deployment, a specific host, a specific region), the temptation is to stop investigating and remediate immediately.
But correlation is not causation: the deployment may correlate with the anomaly because of timing, not because it caused the problem.
The discipline of continuing to narrow the scope until the causal mechanism is clear prevents wasted remediation effort and ensures the actual root cause is addressed.

## Tool category taxonomy

Observability tooling divides into categories by function.
The categories below are architectural roles, not vendor recommendations.
This skill deliberately avoids naming specific products because the categories are stable while the products that fill them change.

| Category | Purpose | Signal types | Selection criteria |
|---|---|---|---|
| Instrumentation SDK | In-process telemetry generation | Traces, metrics, logs, events | OpenTelemetry is the standard; vendor SDKs supplement |
| Telemetry collector/pipeline | Receive, process, route telemetry | All signals | Decouples producers from backends |
| Observability backend | Store and query traces/metrics/logs | Traces, metrics, logs | OTel-native vs adapter-based ingestion |
| Error tracking | Capture, group, prioritize errors with rich context | Errors, crashes, performance | Complementary to traces: adds grouping, alerting, release correlation |
| Product analytics | Track user behavior, funnels, retention | User events, sessions | Measures product health, not system health |
| Feature management | Feature flags, progressive rollout, A/B testing | Flag evaluations, experiments | Often colocated with product analytics |
| Continuous profiling | Runtime CPU/memory/allocation profiling | Profiles | Explains why code is slow, not just that it is slow |
| Chaos engineering | Active fault injection, resilience validation | Probe results, failure modes | Active complement to passive telemetry |
| Incident management | Alert routing, on-call, incident lifecycle | Alerts, pages, incidents | Consumes SLO burn alerts, routes to humans |
| SLO management | Error budget tracking, burn rate alerting | SLI measurements | May be native in observability backend or standalone |

The instrumentation SDK is the universal entry point.
OpenTelemetry provides a vendor-neutral instrumentation layer that generates traces, metrics, and logs conforming to an open specification.
Vendor-specific SDKs (error tracking, product analytics, feature management) supplement OTel instrumentation for their specialized signal types.

The categories are not mutually exclusive in deployment.
A single observability backend may incorporate SLO management, continuous profiling, and incident management features.
The taxonomy describes functional roles, not deployment boundaries.
Understanding the roles helps evaluate whether a system's observability needs are covered, regardless of how many products or services fill those roles.

## Signal routing matrix

The composability principle is: instrument once, route to multiple backends via the telemetry collector.
Each signal type has a primary home and may flow to secondary destinations depending on the system's needs.

| Signal type | Observability backend | Error tracking | Product analytics |
|---|---|---|---|
| Request traces | Primary home | Performance sampling | Not typically |
| Custom spans | Yes | Error spans | Not typically |
| Application metrics | Primary home | Not typically | Not typically |
| Errors and panics | Yes (in trace context) | Primary home (grouping, alerting) | Not typically |
| Product analytics events | Not typically | Not typically | Primary home |
| Feature flag evaluations | As span attributes | As context | Primary home |
| Continuous profiles | If backend supports | Not typically | Not typically |

The composability question for any system is: which signals flow through the OpenTelemetry pipeline versus through dedicated SDK transport, and where does acceptable duplication exist?
Errors appearing in both trace context (for debugging in the observability backend) and in the error tracking system (for grouping, alerting, and release correlation) is normal and useful duplication.
Product analytics events flowing through the product analytics SDK rather than the OTel pipeline is normal because the signal types and query patterns differ.
The goal is not eliminating all duplication but understanding which paths each signal takes and ensuring no signal type lacks a home.

The routing architecture should be documented as part of the system's operational documentation.
A signal routing diagram showing which telemetry flows through which pipeline to which backend prevents the common failure mode where signals are assumed to exist somewhere but no one can find them during an incident.
The diagram also reveals gaps: if no path exists for a signal type that the team needs during debugging, the gap should be addressed before the next incident rather than during it.

## Anti-patterns

The three pillars myth frames observability as "metrics, logs, and traces," reducing the discipline to data format categories.
This framing ignores the analysis practices, data properties, and organizational capabilities that distinguish observability from monitoring.
The logical flaw is assembling one data type (metrics), one anti-data-type (unstructured log strings that resist programmatic analysis), and one visualization approach (traces as waterfall diagrams) into a supposedly foundational triad.
The actual foundations are high cardinality, high dimensionality, and explorability, as described in the core model section.
The three pillars framing also implies that having all three data types constitutes observability, which conflates data collection with the ability to understand system behavior.
A system that collects metrics, logs, and traces but stores them in separate backends with no correlation, no high-cardinality support, and no exploratory query interface has three data silos, not observability.

Dashboard-driven debugging requires predeclaring the conditions you want to monitor, is limited by the cardinality the dashboard's backing data store can handle, and requires visual pattern-matching to detect anomalies.
Engineers who rely on dashboards develop what amounts to tea-leaf reading: an intuitive skill for spotting visual patterns that does not transfer to other engineers, does not scale to unfamiliar failure modes, and degrades as system complexity grows.
Dashboards are useful for ambient awareness of known metrics; they are not useful for investigating novel problems.

Intuition-based troubleshooting follows a pattern of guessing at root causes, jumping to confirm the guess, and alleviating symptoms without investigating the actual cause.
Confirmation bias is the dominant force: the engineer forms a hypothesis and then searches for evidence supporting it, ignoring evidence that contradicts it.
The core analysis loop replaces this pattern with a systematic dimension diff that lets the data surface the distinguishing factors rather than relying on the engineer's prior experience.

Alert fatigue cascades begin with post-incident reviews that generate action items creating new alerts.
Each incident adds alerts; no process removes them.
The resulting flood creates cognitive overload, and teams suppress or ignore alerts as a coping mechanism.
This is a normalization of deviance: the team adapts to the noise by treating all alerts as non-urgent, including the ones that matter.
SLO-based alerting, described in `01-slo-alerting.md`, addresses this by replacing cause-based alerts with a small number of symptom-based alerts tied to error budgets.

The reactive runbook spiral is the complement to alert fatigue: after each outage, write a runbook, create dashboards, add alerts.
In systems where truly novel problems constitute the bulk of incidents, this is wasted effort because the next outage will be a novel failure mode that no existing runbook addresses.
The effort invested in runbooks for past failures would be better spent on improving observability for future unknown failures.

The metrics arms race is the pattern of continuously adding custom metrics to answer questions during debugging.
Each new metric adds cost (storage, indexing, cardinality management), and the engineer still cannot go back in time to answer questions about past incidents using the newly added metric.
Structured events with high dimensionality solve this by capturing all relevant context at emit time, making retroactive analysis possible without retroactive instrumentation.

Glass castle production treats the production environment as fragile, instinctively rolling back at the slightest trouble because controls for small tweaks, graceful degradation, and progressive deployment are absent.
The fear of production changes becomes self-fulfilling: without the ability to make small, safe changes in production, every change is large and dangerous.
Feature flags, canary deployments, and progressive rollouts are the engineering controls that make production resilient rather than fragile.
Observability is what makes these controls practical: without the ability to detect degradation in a canary population, canary deployments are theater.

Cause-based alerting detects a potential cause (abnormal thread count, elevated garbage collection time) and infers that user experience must be degraded.
This fuses "what is wrong" (user experience) with "why it is wrong" (the cause), producing unreliable signals.
The thread count may be abnormal but harmless; the garbage collection may be elevated but within budget.
SLO-based alerting inverts this: detect that user experience is degraded (the "what"), then investigate the cause using the core analysis loop (the "why").

Hero culture elevates a senior engineer to the role of ultimate escalation point who can diagnose anything through intuition and experience.
This is damaging to the organization (single point of failure), to the hero (unsustainable workload and on-call burden), and to junior engineers (who never develop debugging skills because the hero solves problems before they can learn).
Observability practices that enable systematic investigation rather than intuition-based debugging are the structural remedy.
When any engineer can follow the core analysis loop to diagnose an unfamiliar service, the hero's unique value diminishes and the organization's resilience increases.

Starting small is the anti-pattern of piloting observability on small, unobtrusive services to minimize risk.
This captures all the adoption effort (SDK integration, pipeline setup, team training) and none of the benefits (the small service rarely has interesting problems to debug).
Start with the biggest pain points: the services that page on-call most frequently, the endpoints with the worst latency, the workflows that generate the most support tickets.
The value of observability is proportional to the complexity and pain of the system being observed.

Pre-aggregation destroys signal by aggregating data before it arrives in the debugging tools.
Once data is aggregated to 1-minute windows or averaged across instances, you can never dig past the aggregation granularity.
Sampling preserves full cardinality by keeping complete individual events at a reduced rate; metrics collapse cardinality by discarding individual events entirely.
When debugging requires high-cardinality data and you only have pre-aggregated metrics, the investigation halts.
The distinction between sampling and aggregation is fundamental: a sampled dataset at 1-in-100 still contains full individual events that support the core analysis loop; an aggregated dataset at 1-minute resolution contains no individual events regardless of the volume of original data.
This is why sampling is the correct strategy for managing telemetry volume, and pre-aggregation is an anti-pattern that destroys the data properties observability depends on.

## Maturity model

The observability maturity model evaluates five capabilities that collectively determine how well an organization understands and operates its systems in production.
These capabilities are not sequential stages to be achieved in order but concurrent dimensions that each mature independently.
An organization may be advanced in failure response but immature in understanding user behavior, or vice versa.
The model provides a vocabulary for discussing where observability investment will yield the greatest return.

The first capability is responding to system failure with resilience.
This encompasses mean time to recovery, on-call sustainability (measured by page frequency, off-hours interruptions, and rotation health), and systematic education that spreads debugging skills across the team rather than concentrating them in a few individuals.
Organizations at the low end of this capability have long recovery times, burnt-out on-call engineers, and a hero culture where a small number of individuals carry disproportionate incident response burden.
Organizations at the high end recover quickly through systematic investigation, maintain sustainable on-call rotations, and treat each incident as a learning opportunity that improves the team's collective capability.
The transition between these states is driven by tooling (can any engineer investigate any service?) and process (do blameless reviews produce instrumentation improvements?).

The second capability is delivering high-quality code.
Quality in this context is measured by production behavior under chaotic, real-world conditions, not solely by CI results.
A codebase that passes all tests but produces confusing errors, leaks resources under load, or degrades gracefully in theory but catastrophically in practice has low quality by this measure.
Observability provides the feedback loop that connects production behavior back to development decisions.
Without this feedback loop, developers make architectural and implementation choices based on assumptions about production behavior that may be incorrect, and the incorrectness is never surfaced.

The third capability is managing complexity and technical debt.
The diagnostic metric is the proportion of engineering time spent on forward progress (new features, architectural improvements, developer experience) versus reactive work (debugging, firefighting, manual remediation).
Teams spending over half their time on reactive work have a complexity management problem that observability can illuminate by making the sources of reactive work visible and quantifiable.

The fourth capability is releasing on a predictable cadence.
Code reaches production shortly after writing, enabled by feature flags for progressive rollout, automated deployment pipelines, and fast rollback mechanisms.
Organizations with long release cycles accumulate risk: each release bundles many changes, making it difficult to attribute production problems to specific changes.
Short release cycles with observability-backed progressive rollout reduce the blast radius of each change.
Observability provides the feedback signal that makes rapid release safe: the team can detect degradation from a new release within minutes and roll back before the blast radius widens.
Without this feedback signal, rapid release is reckless rather than agile.

The fifth capability is understanding user behavior.
Instrumentation provides product managers and stakeholders with self-service access to production data about how users interact with the system.
When product questions require engineering effort to answer (custom queries, ad-hoc data pulls, new dashboard creation), the organization has a user-understanding bottleneck that well-designed telemetry can remove.
The product analytics category in the tool taxonomy serves this capability specifically, but the observability backend may also contribute when product-relevant data (feature usage, workflow completion rates, error rates per feature) is captured as span attributes.

Teams that adopt observability practices are significantly more likely to report confidence in their software's quality in production.
Teams without observability spend a disproportionate fraction of their time on non-feature work: debugging, firefighting, and manual investigation.
The correlation is not coincidental: observability reduces the time spent on each incident, reduces the frequency of incidents through better feedback loops, and redirects engineering effort from reactive diagnosis to proactive improvement.
The compounding effect is significant: time recovered from incident response becomes available for feature development and architectural improvement, which in turn reduces the incidence of future failures.

Maturity indicators that signal an organization is advancing along these capabilities include several observable changes in engineering practice.
Code reviews routinely consider telemetry adequacy alongside correctness and style: "does this change include instrumentation for the new code path?" becomes a standard review question.
Engineers watch deployments in real time as second nature rather than deploying and hoping, because the observability tooling makes deployment monitoring low-effort and high-value.
Product managers self-serve production questions without filing engineering tickets, because telemetry is accessible through query interfaces that do not require engineering expertise.
The proportion of unresolved "mystery" incidents decreases over time as observability improves the team's ability to reach root cause rather than alleviating symptoms and moving on.

The maturity model connects to the confidence promotion chain from `preferences-validation-assurance`.
A system at low observability maturity can reach `locally-verified` or `integration-verified` confidence through testing, but cannot reach `regression-protected` for production-environment properties because it lacks the runtime monitoring tier.
Advancing observability maturity enables the `runtime` regression guard type, which catches environmental failures that automated tests in CI cannot anticipate.
The two maturity models are complementary: validation assurance addresses pre-deployment confidence and observability addresses post-deployment confidence.
Together, they cover the full lifecycle: testing catches what can be predicted, observability catches what cannot, and the confidence promotion chain from `preferences-validation-assurance` tracks which claims have evidence at each stage.

## Observability-driven development

Observability can serve as a development practice, not just an operational one.
When engineers add instrumentation as part of feature development (rather than after deployment or after an incident), the telemetry reflects the developer's intent and understanding of the code.
This intent-driven instrumentation is higher quality than reactive instrumentation added under incident pressure.

The practice involves asking, during development: "When this code runs in production, what questions will I need to answer?"
The structured event should capture the dimensions needed to answer those questions.
Feature flags, experiment assignments, and A/B test variants should appear as span attributes so that production behavior can be sliced by feature state.
Error paths should capture enough context (input parameters, intermediate state, dependency responses) to diagnose failures without reproducing them locally.
The structured event for an error should be self-contained: an engineer reading it should be able to understand what happened without consulting additional data sources.

This practice aligns with the iterative instrumentation principle from `02-instrumentation-patterns.md` but shifts the timing: instead of adding instrumentation after the first incident reveals a gap, add it during development when the engineer's understanding of the code is freshest.
The result is telemetry that covers the new code path from its first production request.
The alternative — discovering the instrumentation gap during the first incident involving the new code — wastes both incident response time and the developer's fresh understanding of the code, which fades as they move on to other work.

## Sociotechnical considerations

Observability is not purely a technical discipline.
The organizational context in which observability tools are deployed determines whether they improve system understanding or become shelfware.

Ownership of instrumentation should follow ownership of code.
The team that writes and deploys a service is the team best positioned to instrument it, because they understand the business logic, the failure modes, and the questions they need to answer during incidents.
Centralizing instrumentation in a platform team creates a bottleneck: the platform team lacks the domain context to instrument effectively, and the service team lacks access to add the instrumentation they need.
The platform team's role is to provide the infrastructure (SDKs, pipelines, backends, documentation, and training) that makes instrumentation easy for service teams.

Blameless incident review is the organizational practice that converts incidents into observability improvements.
When the review focuses on "what happened and how do we detect it faster next time" rather than "who is at fault," engineers are motivated to add instrumentation that reveals failure modes.
When the review focuses on blame, engineers are motivated to hide failure modes, which is the opposite of observability.

The feedback loop between incidents and instrumentation should be short.
If adding a new span attribute requires a multi-week approval process, the engineer will not add it after an incident, and the same investigation gap will persist for the next incident.
The organizational goal is to make instrumentation changes as lightweight as code changes: reviewed, tested, and deployed through the same pipeline.

Cost transparency is an organizational concern that affects observability adoption.
Telemetry volume drives storage and query costs.
When cost is invisible to the teams generating telemetry, there is no incentive to manage volume through sampling, retention tiering, or signal routing.
When cost is attributed to generating teams, there is a natural incentive to be thoughtful about what telemetry is emitted and at what rate, without a central team acting as gatekeeper.
The telemetry pipeline architecture described in `03-telemetry-architecture.md` provides the mechanisms (sampling, routing, tiering) that make cost management practical.

## Cross-references

Reference files in this skill:

- `01-slo-alerting.md` covers the SLI/SLO/error budget framework and alerting strategy
- `02-instrumentation-patterns.md` covers OpenTelemetry instrumentation and metrics design patterns
- `03-telemetry-architecture.md` covers trace structure, context propagation, telemetry pipelines, and sampling

Related skills:

- `preferences-validation-assurance` establishes the testing side of the testing-observability duality
- `preferences-architectural-patterns` addresses where observability infrastructure fits in the system architecture
- `preferences-distributed-systems` covers distributed system patterns where observability is particularly critical
- `preferences-production-readiness` covers operational practices that observability enables

The testing-observability duality is a recurring theme: `preferences-validation-assurance` covers the catamorphic (closed-world) regime, this skill covers the anamorphic (open-world) regime, and production systems require both.
When designing a new system or adding a new feature, consider both the test plan (what can be verified before deployment?) and the observability plan (what telemetry will be available to understand behavior after deployment?).

## Canonical references

- Majors, C., Fong-Jones, L. & Miranda, G. -- *Observability Engineering* (O'Reilly, 2022)
- Kalman, R. -- "On the General Theory of Control Systems" (IFAC Proceedings, 1960)
- Sridharan, C. -- *Distributed Systems Observability* (O'Reilly, 2018)
- Beyer, B., Jones, C., Petoff, J. & Murphy, N. -- *Site Reliability Engineering* (O'Reilly, 2016), chapters on SLOs and monitoring
- OpenTelemetry specification -- opentelemetry.io/docs/specs/
