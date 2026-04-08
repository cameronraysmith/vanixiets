# SLO-driven alerting and error budgets

## SLI design

A service-level indicator categorizes each unit of system work as good or bad.
The categorization must be unambiguous: every request, every event, every time window receives exactly one label.
This binary classification is the foundation that SLOs, error budgets, and burn rate alerts build upon.

Two approaches to SLI measurement exist: time-based and event-based.
Time-based SLIs divide time into windows (typically one minute or five minutes) and mark each window as good or bad based on whether the aggregate metric for that window meets the threshold.
Event-based SLIs mark each individual request or event as good or bad based on whether it met the criterion.

Event-based SLIs are strongly preferred.
Time-based SLIs are too coarse for stringent SLO targets because they mark entire windows as bad even for partial brownouts.
A five-minute window containing one slow request out of ten thousand is marked identically to a window where every request was slow.
This coarseness burns disproportionate error budget during minor transient issues and understates the impact of severe but brief outages that fall within a single window.

The most common SLI categories are availability (did the request succeed?), latency (did the request complete within the threshold?), and correctness (did the request return the right answer?).
Latency SLIs typically use a threshold rather than a percentile: each request is good if its duration is below the threshold, bad otherwise.
Percentile-based SLIs (p99 over a window) are a time-based approach with the coarseness problems described above.

## SLO targets

A service-level objective is an internal reliability target expressed as a percentage of good events over a defined time window.
SLOs are more stringent than external service-level agreements because internal teams need early warning before customer-facing commitments are at risk.

SLO targets should be set before writing code, not discovered after deployment.
They are architectural constraints that influence design decisions: a 99.99% availability SLO implies different architecture (redundancy, failover, connection pooling) than a 99% SLO.
Setting SLOs retroactively based on observed performance describes the system as-built rather than establishing what users need.

Critical end-user journeys determine which SLOs matter.
Not every endpoint requires the same reliability target.
The login flow, the checkout flow, and the data export flow may each have different SLOs reflecting their different importance to users.
An SLO strategy that applies a single target uniformly across all endpoints either over-invests in low-importance paths or under-invests in critical ones.

## Error budgets

The error budget is the maximum tolerable quantity of bad events within the SLO window.
A 99.9% SLO over 30 days with 1,000,000 requests per month allows 1,000 bad requests.
A 99.99% SLO on the same volume allows 100.

A sliding 30-day window is recommended over a fixed calendar window.
Fixed calendar windows (monthly, quarterly) create perverse incentives: a team that exhausted its budget on the first day of the month has no incentive to protect reliability for the remaining 29 days, while a team approaching month-end hoards budget.
A sliding window ensures that every bad event matters equally regardless of when it occurs, because it will remain in the window for 30 days before expiring.

The error budget creates a natural tension between velocity and reliability.
When budget remains, the team has empirical evidence that feature velocity is sustainable.
When budget is exhausted, the team shifts from feature work to stability work: hardening, redundancy, observability improvements, and root cause fixes.
This is not a punishment but a structural incentive that aligns engineering effort with user experience.
The budget provides an objective criterion for the otherwise subjective question of "how much reliability is enough."

## Error budget as linear resource

The error budget is a consumable quantity that depletes monotonically within the sliding window.
Each bad event consumes one unit.
Recovery occurs only as old bad events age out of the window's trailing edge.
The burn rate is the derivative of budget consumption: the rate at which bad events are arriving relative to the rate at which the budget can sustain.

This resource model maps to linear logic's consumption semantics.
Budget units cannot be duplicated (a good event does not restore spent budget) and cannot be discarded (every bad event must be accounted for).
The budget is spent, and spending is irreversible within the window.

A burn rate of 1x means the budget will be exactly exhausted at the end of the window.
A burn rate of 10x means the budget will be exhausted in one-tenth of the window.
Burn rates above 1x indicate the current failure rate is unsustainable; burn rates below 1x indicate the current failure rate is within budget.

## Burn rate alerts

Rather than alerting when the error budget reaches zero (at which point the damage is done), burn rate alerts forecast whether current conditions will exhaust the budget.
The alert fires when the observed burn rate, sustained for a projected period, would consume the remaining budget.

Two approaches to burn rate calculation serve different purposes.
Short-term (ahistorical) alerts extrapolate from a recent baseline only, ignoring historical patterns.
They detect sudden spikes quickly but may false-alarm during expected traffic variations.
Context-aware (historical) alerts maintain a rolling total over the entire SLO window, factoring in remaining budget.
They are more accurate but slower to detect sudden changes.

The baseline-to-lookahead ratio determines how far forward a given baseline window can predict.
In practice, a baseline window predicts forward by a factor of four without seasonality compensation.
A 24-hour alarm uses the last 6 hours of data; a 4-hour alarm uses the last 1 hour.
These ratios balance detection speed against false alarm rate.

## Proportional over linear extrapolation

Linear extrapolation assumes uniform traffic: 25 failures in 6 hours becomes 100 projected failures in 24 hours.
This misses traffic volume changes.
If the 6-hour window contained low-traffic overnight hours, the projected failure count for the full day (which includes high-traffic daytime hours) will be wrong.

Proportional extrapolation accounts for volume: 25 failures out of 50 requests is a 50% failure rate.
Applied to the expected daily volume of 1,440 requests, this projects 720 failures.
Proportional extrapolation is far more accurate because it separates the failure rate from the traffic volume, allowing each to vary independently.

## Decoupling "what" from "why"

SLOs tell you what is wrong: user experience is degraded beyond the acceptable threshold.
Observability tells you why: through the core analysis loop described in the main skill document, you systematically narrow the search space until the root cause is identified.

Traditional monitoring fuses "what" and "why" by detecting a potential cause (high CPU, full disk, elevated error rate on a dependency) and inferring that user experience must be degraded.
This fusion produces false positives (the cause is present but user experience is fine), false negatives (user experience is degraded but none of the monitored causes are present), and diagnostic dead ends (the cause is a symptom of a deeper problem).

The SLO-based approach cleanly separates detection from diagnosis.
Detection is cheap: a small number of well-chosen SLIs covering critical user journeys.
Diagnosis is expensive but targeted: it only happens when detection signals a real problem, and it uses the full power of high-cardinality, high-dimensional telemetry to investigate.

## Criteria for helpful alerts

Two criteria determine whether an alert is helpful.
First, it must be a reliable indicator that user experience is degraded.
This means symptom-based, not cause-based: the alert fires because users are experiencing errors or latency, not because a thread count is high or a dependency is slow.

Second, it must be actionable.
There must be a systematic way to investigate the alert and reach a diagnosis without relying on intuition or guesswork.
An alert that says "error budget burning at 5x" combined with observability tooling that supports the core analysis loop is actionable.
An alert that says "CPU is high" with no further investigation path is not.

## Acting on burn alerts

The response to a burn alert depends on the burn pattern.
Burst burns are sudden spikes: the burn rate jumps from baseline to a high multiple in a short period.
These typically indicate a discrete event (a bad deployment, a dependency outage, a configuration change) and the response pattern is to identify the triggering event and remediate it (rollback, failover, configuration revert).

Gradual burns are slow degradation: the burn rate is modestly elevated over a long period.
These typically indicate a systemic issue (resource exhaustion, growing data volume, accumulating technical debt) and the response pattern is to investigate the trend, identify the underlying cause, and address it structurally.

When the error budget is fully exhausted, the team should halt feature work and focus on stability.
This is the error budget's structural incentive in action: the budget provides an objective, quantitative answer to the question of when reliability work should take priority over feature work.
The shift is temporary: once the budget recovers (as old bad events age out of the sliding window and the failure rate drops), feature work resumes.

## Multi-SLO coordination

Production systems typically have multiple SLOs covering different user journeys and different quality dimensions (availability, latency, correctness).
These SLOs interact: a latency degradation that does not breach the latency SLO may cause downstream timeout errors that breach the availability SLO of a dependent service.

When multiple SLOs are burning simultaneously, the investigation should start with the SLO closest to the user.
The user-facing SLO identifies the symptom; the internal SLOs help localize the cause.
If an external availability SLO and an internal latency SLO are both burning, the latency SLO likely explains the availability SLO (timeouts from slow responses).
Investigating the latency SLO using the core analysis loop from the main skill document will likely resolve both.

SLO coverage should be reviewed periodically.
As the system evolves, new user journeys emerge and existing journeys change shape.
An SLO set that was comprehensive six months ago may have gaps today.
The diagnostic question is: could a user have a degraded experience that no current SLO would detect?
If so, a new SLI and SLO are needed for that journey.
