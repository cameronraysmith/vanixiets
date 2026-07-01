# Two streams and the mutation firewall

The outer loop constrains implementation with two test streams that answer different questions, and it optionally closes with a mutation firewall that checks the streams actually catch bugs rather than merely running the code.

## Why two streams

The acceptance stream fixes what the system does as an external observable, in the domain's language, at its public surface.
The unit stream fixes how the system does it, at the granularity of the internal structure the implementer is building.
Each stream constrains the design differently, and neither subsumes the other: acceptance tests alone leave the internal structure unchecked and permit a tangled implementation that happens to behave, while unit tests alone verify the parts in isolation and miss the integration that only the surface exercises.
The discipline is that both go green together on a full run before a unit of work is complete; a green acceptance suite over a red unit suite, or the reverse, is an incomplete unit of work, not a passing one.
The inner red-green-refactor that grows the unit stream defers to `test-driven-development`; this skill owns only the constraint that the acceptance stream is co-equal and gates completion alongside it.

## Two mutation checks, two purposes

Mutation is used at two distinct points for two distinct purposes, and conflating them is a common error.

The first is an acceptance-wiring check: perturb an expected value the scenario asserts — for a Scenario Outline, a cell in an `Examples` column — regenerate or re-run, and confirm the acceptance suite goes red.
A scenario whose `Examples` mutation does not turn the suite red is not wired to the system; it is asserting against something the production path also computed, and it would pass no matter what the system did.
This is the tautology trap surfacing at the scale of a data table, and it is the mechanical complement to the observable-outcome gate: the gate reasons about whether the oracle is independent, the wiring check proves it by breaking the expectation and demanding a failure.

The second is a source-code mutation firewall over the unit stream: perturb the production source one operator at a time — an arithmetic or comparison or boolean flip, a negated condition, a stripped method call, a constant swap — run the covering tests, and expect each mutant to be killed.
A surviving mutant is a bug the unit suite would not catch, and a suite with full line coverage can still let a large fraction of mutants survive, which is why coverage alone is not adequacy.
Differential re-running keeps this affordable: re-mutate only the functions whose code, covering tests, or operator set changed, and reuse cached results for the rest.

The wiring check asks whether the acceptance scenarios are connected to the app at all; the source-code firewall asks whether the unit suite would notice a regression.
They live at opposite ends of the loop and answer opposite questions.

## The firewall is optional and severity-gated

The source-code mutation firewall is P8's optional hardening, run after both streams are green, not a routine step on every change.
Whether a survivor matters, how severe a gap it represents, and whether the suite is adequate are judgments that defer to `preferences-validation-assurance`: severity, evidence quality, the confidence promotion chain, and the test-adequacy criterion.
A survivor on a trivial or unreachable branch is triaged differently from a survivor on a domain invariant, and that triage is a validation-assurance decision, not a mechanical pass/fail.

## Provenance

The two-test-stream constraint and the differential-mutation insight are re-authored from the ideas of Disciplined Agentic Engineering and its Robert C. Martin acceptance-test lineage; the acceptance-wiring mutation is this group's native-runner analog of DAE's intermediate-representation example mutator, applied directly to `Examples` columns rather than to a regenerated JSON representation.
