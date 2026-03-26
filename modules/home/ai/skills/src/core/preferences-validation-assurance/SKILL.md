---
name: preferences-validation-assurance
description: >
  Validation assurance foundations for evidence-based confidence in software
  systems, including Mayo's severity criterion for engineering, refinement as
  spec-implementation freedom preservation, mutation analysis, observability,
  regression harness design, reflexive severity, and double-loop learning
  triggers. Load when reasoning about test adequacy, confidence levels,
  evidence quality, regression protection, or whether the process itself
  should change.
---

# Validation assurance and evidence-based confidence

## Problem statement

"Tests pass" and "we have confidence" are not the same thing.
Tests can pass while being inadequate — they would also pass with a wrong implementation.
Implementations can be correct while being over-constrained by brittle tests that prevent legitimate evolution.
The beads issue graph can say "closed" while the codebase is in a partially functional state.

Three coupled failure modes drive this gap:

1. False confidence: tests pass but are not severe — they do not discriminate between correct and plausible-but-wrong implementations.
2. Over-constraint: tests are too specific, coupling to implementation details rather than specification properties, preventing refactoring and evolution.
3. State drift: the issue tracker's view of "done" diverges from the codebase's actual functional state.

The optimization target is to maximize confidence per unit of testing investment, where confidence is measured by the severity of the evidence, not the volume of tests.
A small number of high-severity tests that would fail under any plausible-but-wrong implementation provides stronger confidence than a large suite of low-severity tests that pass regardless.
This document establishes the theoretical foundations for reasoning about this optimization across the full lifecycle of an AI-agent-driven engineering workflow.

## Mayo's severity criterion for engineering

The severity criterion, adapted from `preferences-scientific-inquiry-methodology`, provides the foundational question for all validation reasoning: would this test have failed if the implementation were wrong?

A test result *e* is good evidence for claim *H* only if the test procedure had a high probability of not yielding *e* if *H* were false.
This means a test that always passes regardless of implementation has zero severity and provides no evidence.
A test that discriminates between correct and plausible-but-wrong implementations has high severity.
Severity is not binary — it exists on a continuum.

Consider three engineering examples.
`nix build` succeeding has low severity for correctness because builds can succeed with wrong behavior.
A property-based test that generates 1000 random inputs and verifies an algebraic law has high severity because it would fail under most incorrect implementations.
An integration test that exercises the specific interface contract between two subsystems has high severity for that contract.

Property-based tests, as described in `preferences-algebraic-laws`, are the primary mechanism for high-severity evidence because they test universal properties across generated inputs rather than specific examples.
The severity of a property test scales with the diversity of generated inputs and the discriminating power of the property being tested.

When assessing whether to invest in a new test, the severity question should be primary.
A test that is easy to write but would pass under most incorrect implementations is not worth writing — it adds maintenance cost without adding confidence.
A test that is harder to write but would fail under any plausible-but-wrong implementation is worth the investment because it provides genuine evidence.

## Refinement and freedom preservation

The relationship between specification and implementation forms a partial order.
Implementation *P* refines specification *S* if every observable behavior of *P* is allowed by *S*.
The specification's looseness — the set of behaviors it permits but does not require — represents the intended degrees of freedom for implementors.

Tests should constrain exactly what the specification requires, no more and no less.
Property-based tests preserve more freedom than example-based tests because properties express "what must hold for all inputs" without specifying "what the output looks like for this specific input."
Algebraic laws from `preferences-algebraic-laws` are the ideal test form: they express structural properties that any correct implementation must satisfy while permitting arbitrary implementation strategies.

The validation ladder orders testing approaches from least constraining to most constraining:

| Rung | Mechanism | Freedom preserved |
|---|---|---|
| Type-level constraints | Illegal states unrepresentable (from `preferences-domain-modeling`) | Maximum — the type system enforces invariants without runtime tests |
| Algebraic law tests | Structural properties (from `preferences-algebraic-laws`) | High — any implementation satisfying the laws is valid |
| Property-based tests | Behavioral properties across generated inputs | High — specifies what, not how |
| Contract tests | Interface conformance between components | Moderate — constrains interaction shape |
| Integration tests | Assembled subsystem behavior | Moderate — constrains end-to-end paths |
| Example-based tests | Specific input-output pairs | Low — most constraining, use sparingly |

Lower rungs preserve more freedom.
Prefer the lowest rung that provides sufficient severity for the claim being tested.

The ladder is not a maturity model where you ascend from top to bottom.
It is a tool selection guide.
A claim about monoidal associativity belongs on the algebraic law rung; an algebraic law test is both more severe and less constraining than an example-based test for that claim.
A claim about end-user workflow completion belongs on the integration rung; no amount of algebraic law testing would address it.
The claim determines the rung, not the project's maturity.

## Evidence quality dimensions

Five orthogonal dimensions for assessing evidence quality, adopted from assurance case literature (Goal Structuring Notation — Kelly & Weaver, 2004):

Directness measures whether the evidence tests the actual claim or a proxy.
Direct evidence tests the thing itself; indirect evidence tests something correlated.
A unit test that exercises the function under test is direct; code coverage metrics are indirect.

Severity (Mayo) asks whether the evidence would have come out differently if the claim were false.
This is the core discriminating dimension — evidence with low severity is noise regardless of the other dimensions.

Coverage measures what fraction of the specification's requirements the evidence addresses.
A test suite with 100% severity on 10% of requirements still leaves 90% unvalidated.

Freshness reflects when the evidence was last produced.
Evidence decays as the codebase evolves.
A test that passed 6 months ago on a different commit provides weak evidence for today's code.

Independence captures whether the evidence comes from a source independent of the implementation.
Self-testing (the implementer writes the tests) provides less independence than adversarial testing (a reviewer or separate agent writes the tests).

These dimensions are not a checklist but a lens for assessing whether confidence is warranted.
An agent reading an issue's evidence-freshness date and seeing it is months old should recognize this as a confidence concern without being told to check.

In practice, most evidence portfolios are strong on some dimensions and weak on others.
A freshly run, high-severity property test may lack independence if the same agent wrote the implementation and the test.
A thorough adversarial review may lack freshness if the code has changed since the review.
The goal is not perfection across all five dimensions but awareness of where the gaps are, so that confidence claims remain calibrated to the actual strength of the evidence supporting them.

## Confidence as a promotion chain

Confidence levels form a monotone chain ordered by evidence strength:

| Level | Meaning | Evidence required |
|---|---|---|
| `undemonstrated` | No evidence exists | Default state |
| `finding-recorded` | Probe produced documented findings | Written findings that inform next steps |
| `prototype` | Working code exists but untested | Code runs in at least one scenario |
| `locally-verified` | Unit/property tests pass locally | Automated tests with meaningful severity |
| `integration-verified` | Assembled subsystems work together | Integration tests at component boundaries |
| `validated` | Higher-level requirement is satisfied | End-to-end or acceptance tests against spec |
| `regression-protected` | Automated harness prevents backsliding | CI-enforced tests that would detect regression |
| `regressed` | Previously validated claim no longer holds | Evidence of failure (demotion target, not a promotion step) |

Promotion requires fresh, severe evidence at the target level — not just the passage of time or the closing of issues.
Skipping levels is permitted when evidence directly supports the higher claim; an end-to-end test can promote directly to `validated` without passing through `locally-verified`.

The chain is monotone in the sense that each level subsumes the evidence requirements of all lower levels.
`regression-protected` implies `validated` implies `integration-verified`, and so on.
An implementation cannot be `regression-protected` if no integration test has ever passed, because the CI harness would be guarding a claim that was never established.

Demotion to `regressed` is triggered by six conditions:

1. A test that previously passed now fails.
2. A dependency changed an interface that the evidence relies on.
3. The specification changed, invalidating the claim the evidence supports.
4. Evidence freshness exceeds the staleness threshold (evidence was produced too long ago to be credible for today's code).
5. A severity gap is discovered — the tests would have passed even with a wrong implementation.
6. An environmental change (OS upgrade, dependency version bump) that the evidence did not account for.

Demotion is not failure; it is the system working correctly.
A confidence chain that never demotes is either stable (nothing changes) or dishonest (changes happen but confidence is never reassessed).
In an actively evolving codebase, periodic demotion and re-promotion is the expected steady state.

## Regression harness design

Three tiers of regression protection serve different contexts:

| Guard type | Mechanism | Strength | When to use |
|---|---|---|---|
| `manual` | Documented verification procedure that a human or agent runs | Weak — depends on discipline | When automation is infeasible or disproportionately expensive |
| `automated` | CI-enforced tests that run on every commit/PR | Strong — continuous, objective | Default target for production code |
| `runtime` | Monitors, health checks, or canary deployments that detect regression in production | Strongest — catches environmental failures automation misses | For properties that depend on deployment environment |

Mutation analysis serves as meta-validation: inject known faults into the implementation and check whether the test suite detects them.
The mutation score (percentage of injected faults detected) quantifies test suite adequacy.
A surviving mutant — a fault not detected — identifies a gap in the regression harness.
Tools include `cargo-mutants` (Rust), `mutmut` (Python), and Stryker (TypeScript/JavaScript).
These are advisory; the framework does not require mutation testing, but agents should be aware it exists as a meta-validation technique for assessing the severity of existing test suites.

The three tiers are not exclusive.
A well-defended property typically has `automated` guards in CI and may additionally have `runtime` monitors in production for environment-sensitive behavior.
The tier selection determines the minimum acceptable level of protection for a given claim, not an upper bound on how many mechanisms can guard it.

Runtime verification, as formalized by Leucker and Schallhart (2009), provides a theoretical foundation for the `runtime` tier.
Runtime monitors observe execution traces and check them against formal specifications, catching violations that static test suites cannot anticipate because they depend on deployment context, timing, or external service behavior.

## Anti-patterns

Three anti-patterns that agents should recognize and flag when encountered.

Green-suite theater occurs when the test suite is green but has low severity.
Tests check syntax rather than semantics, verify mocks rather than real integrations, or cover the happy path but miss edge cases.
The diagnostic question: what implementation bugs would this test suite miss?
If the answer is "many plausible ones," the suite has low severity regardless of its pass rate.

Confidence-by-proximity occurs when a closed issue is conflated with a validated implementation.
Closure means "the planned work was performed," not "the claim is supported by evidence."
The diagnostic: check the confidence signal.
If it is `undemonstrated` or `prototype` on a closed issue, there is a gap between what the tracker says and what the evidence supports.

Over-specification theater occurs when tests are coupled to implementation details — specific function call sequences, exact output formatting, internal data structures — rather than specification properties.
Any legitimate refactoring breaks tests, so refactoring is avoided and the codebase ossifies.
The diagnostic question: would this test still pass if the same specification were reimplemented with a different algorithm?
If not, the test is coupled to implementation, not specification.

## Reflexive severity and double-loop learning

Severity applies to the process itself, not just to individual tests.
The meta-level question: would our planning and validation methodology have produced a different outcome if our understanding of the problem were wrong?
If the answer is no — if the methodology produces the same plan regardless of whether assumptions are correct — then the methodology has zero severity and provides no information about whether we are on the right track.

This is the bridge from single-loop learning (correct errors within the existing framework) to double-loop learning (question whether the framework itself should change), following Argyris and Schon's organizational learning theory.

Agents should recognize and surface these double-loop learning signals:

1. Systematic surprise: surprise is consistently high across multiple issues, indicating the planning methodology is systematically miscalibrated rather than locally wrong.
2. Recurring ambiguity: acceptance criteria are consistently ambiguous or unfalsifiable, indicating the requirements methodology is producing poorly formed work items.
3. Classification drift: Cynefin classifications keep shifting in one direction during implementation, indicating the classification methodology is miscalibrating.
4. Validation stalling: confidence stalls at a consistent level because infrastructure does not support the prescribed validation methodology, indicating a methodology-reality mismatch.
5. Requirements incoherence: requirements decompose cleanly into issues but issues do not compose into a working system, indicating an integration architecture gap.
6. Severity failure: the testing strategy would not detect known failure modes, indicating the regression harness has a systematic gap.

When an agent recognizes any of these patterns, the correct response is to pause execution and surface the observation rather than pressing on within a framework it perceives as inadequate.
The agent's primary obligation is to the quality of the outcome, not to compliance with the plan.
The plan is a tool for achieving the outcome — when the plan is counterproductive, the agent's duty is to say so.

This meta-cognitive capacity is not a separate phase or skill.
It is a pervasive quality of how the agent engages with its work at every level of the session lifecycle.

## Cross-domain applicability

The reflexive severity principle extends the Peircean self-correcting inquiry structure identified in `preferences-adaptive-planning` section "Cross-domain applicability."

| Domain | Single-loop | Double-loop |
|---|---|---|
| Engineering | Plan/implement/validate/replan | Question whether the planning methodology is fit for the problem |
| Scientific inquiry | Hypothesize/predict/test/revise | Question whether the experimental methodology is severe |
| Bayesian modeling | Prior/simulate/posterior-check/expand | Question whether the model class is adequate for the phenomenon |

The Peircean fixation of belief applies at every level: the method by which we fix belief must itself be subject to scrutiny, or it becomes dogma.
This holds for individual tests, test suites, validation strategies, planning methodologies, and the overall process.

The practical implication is that validation assurance is not a phase that happens after implementation.
It is a perspective that pervades every phase — from specification decomposition (are these requirements falsifiable?) through implementation (is this testable at the appropriate rung?) through review (does the evidence actually discriminate?) through maintenance (has the evidence gone stale?).
When this perspective is internalized rather than proceduralized, the overhead of validation assurance approaches zero because it becomes indistinguishable from careful engineering.

## Canonical references

- Mayo, D. — *Statistical Inference as Severe Testing* (Cambridge, 2018)
- Back, R. & von Wright, J. — *Refinement Calculus: A Systematic Introduction* (Springer, 1998)
- Jia, Y. & Harman, M. — "An Analysis and Survey of the Development of Mutation Testing" (IEEE TSE, 2011)
- Argyris, C. & Schon, D. — *Organizational Learning* (Addison-Wesley, 1978)
- Kelly, T. & Weaver, R. — "The Goal Structuring Notation" (DSN Workshop, 2004)
- Leucker, M. & Schallhart, C. — "A Brief Account of Runtime Verification" (J. Logic and Algebraic Programming, 2009)

## See also

- `preferences-adaptive-planning` for the MPC/VSM/Cynefin framework this skill extends with evidence-based confidence
- `preferences-scientific-inquiry-methodology` for the epistemological foundations (Mayo's severity criterion, Peircean pragmatism) that this skill operationalizes for engineering
- `preferences-algebraic-laws` for property-based testing as the primary mechanism for high-severity, freedom-preserving evidence
- `preferences-domain-modeling` for type-level constraints as the first rung of the validation ladder
