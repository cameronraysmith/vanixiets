# Foundations: pragmatism and effective theories

## Peircean pragmatism

The philosophical bedrock of this framework is Charles Sanders Peirce's pragmatism — specifically three ideas that, taken together, provide the epistemological foundation for effective theories and iterative model building.

The *pragmatic maxim* states: "Consider what effects, that might conceivably have practical bearings, we conceive the object of our conception to have. Then, our conception of these effects is the whole of our conception of the object."
This is not instrumentalism or anti-realism.
It is a claim about meaning: the content of a scientific concept is exhausted by its observable consequences under specified conditions.
An effective theory, in Wells' formulation, is precisely this — a theory that systematizes which consequences matter at a given scale and which are irrelevant.
The meaning of "gravitational interaction" at planetary scales *is* Newton's inverse-square law, not because general relativity doesn't exist, but because the pragmatic content of the concept at that scale is fully captured by the Newtonian effective theory.
The corrections from GR are not part of the concept's meaning at that scale because they have no practical bearing there.

Peirce's *fallibilism* insists that no belief is immune from revision.
This is the philosophical warrant for treating all models as effective theories.
The question is never whether a model is "true" but whether it has survived severe testing within its domain of applicability and whether it makes novel predictions that extend that domain.

Peirce's *theory of inquiry as self-correcting* holds that inquiry is not a procedure that terminates in certainty but an ongoing process in which beliefs are fixed by their consequences, destabilized by surprising observations, and refined through a triadic cycle of abduction, deduction, and induction.

## The triadic inquiry cycle

Peirce's three modes of inference map directly onto the iterative workflows of both Wells (effective theory construction) and Betancourt (principled Bayesian modeling):

*Abduction* (hypothesis generation): given a surprising observation — a deviation in posterior predictive checks, an anomalous measurement at higher precision — generate a candidate model expansion consistent with known symmetries or domain expertise.
This is Wells' "add all operators consistent with symmetries" and Betancourt's "expand the model toward the aspirational model to address the strongest revealed deviation."

*Deduction* (prediction): derive the consequences of the expanded model — its prior predictive distribution, its predictions at new scales, its implications for summary statistics not yet examined.
This is where mathematical rigor enters: the predictions must follow from the model, not from intuition about what the data should look like.

*Induction* (testing): subject those predictions to severe empirical scrutiny.
This is Mayo's severity criterion, Betancourt's posterior predictive checks and simulation-based calibration, and Wells' precision measurements targeting predicted deviations.

The cycle does not terminate in certainty.
It terminates in *adequacy* — when the model's retrodictions are consistent with observations for all summary statistics relevant to the scientific question — and resumes when new data, new questions, or new precision reveal inadequacy.

## Effective theories as scientific knowledge

Wells defines effective theories as theories that "organize phenomena under an efficient set of principles" without "impossibly complex" computation.
The only way a theory can be effective in this sense is if it is manifestly incomplete.

The formal insight: an effective theory enables useful predictions with a finite number of input parameters by explicitly acknowledging and systematizing what is irrelevant to the questions asked.
As Wells puts it: "Most things are irrelevant for all practical purposes. A tree falling in Peru does not appreciably affect a cannonball's flight in Australia. Any good effective theory systematizes what is irrelevant for the purposes at hand."

This is not a weakness but a structural feature of how scientific knowledge works.
The power of effective theories comes from *scale separation* — understanding which phenomena matter at which scales.
When scale separation holds, the effective theory is not approximately true; it is exact within its domain of applicability.
Galileo's law of falling bodies is not an approximation to Newtonian mechanics with air resistance — it is exact for dense objects in air, because air resistance is genuinely irrelevant at that scale.

## Consistency as the preeminent criterion

Wells argues, and this framework adopts, that consistency takes precedence over all other criteria in theory construction.
Two forms of consistency are non-negotiable:

*Observational consistency*: compatibility with all known experimental data within the theory's stated domain of applicability.

*Mathematical consistency*: internal coherence — no uncontrolled infinities, preservation of symmetries, no violation of causality or unitarity.

The completeness principle follows: unless there is good explicit reason otherwise, a theory must include all possible interactions consistent with its symmetries at every order.
Omitting terms for simplicity while retaining others at the same order is not simplification but inconsistency that introduces artificial structure.

This has a direct analogue in principled Bayesian modeling: the prior must be consistent with all known domain expertise, not just the subset that produces convenient posteriors.
Betancourt's iterative elicitation process — checking the prior's consequences against domain knowledge and revising until consistent — is the Bayesian counterpart of Wells' consistency requirement.

## Effective theories and universality

The concept of *universality classes* explains why effective theories work: many different microscopic details produce the same macroscopic behavior, so you don't need to know the microscopic details to make macroscopic predictions.
The renormalization group provides the mathematical apparatus for this — a systematic procedure for deriving effective theories at one scale from theories at a finer scale, with explicit control over what information is lost.

Applied to biological systems, this means: many different molecular mechanisms of (for example) transcriptional regulation produce the same population-level statistics when observed at the resolution of current measurement technologies.
A well-constructed effective theory captures the universality class of mechanisms, not any single molecular implementation.
This is a feature, not a limitation — it means the theory's predictions are robust to microscopic details that are unknown or unmeasurable.
