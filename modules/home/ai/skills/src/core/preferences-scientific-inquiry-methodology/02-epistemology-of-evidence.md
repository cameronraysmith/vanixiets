# Epistemology of evidence

This section develops the criteria for when data constitute genuine evidence for scientific claims, drawing on four complementary philosophical traditions.
Together they provide the apparatus for distinguishing rigorous science from its pathological imitations.

## Mayo's severity criterion

Deborah Mayo's severity principle (*Error and the Growth of Experimental Knowledge*, 1996; *Statistical Inference as Severe Testing*, 2018) provides the formal criterion for when evidence supports a claim: a test result e is good evidence for hypothesis H only if the test procedure had a high probability of *not* yielding e if H were false.

This is the operational formulation of the pragmatic maxim applied to evidence.
A model that accommodates known data is not thereby supported by that data — the question is whether the data could have looked different if the model were wrong.
Severity is what distinguishes genuine testing from post hoc accommodation.

Applied within the iterative workflow, severity operates at every diagnostic stage:

- Prior predictive checks are severe tests of domain expertise consistency: if the prior were badly wrong, the predictive distribution would look implausible.
- Simulation-based calibration is a severe test of computational faithfulness: if the inference algorithm were biased, rank histograms would be non-uniform.
- Posterior predictive checks are severe tests of model adequacy: if the model were inadequate, retrodictions would deviate systematically in directions predicted by the aspirational context.

The strength of severity as a criterion is that it applies uniformly across all methods.
A neural network that fits training data perfectly achieves zero severity for any mechanistic claim, because the network would have fit the data regardless of the underlying mechanism.
A mechanistic model with few free parameters and specific distributional predictions achieves high severity when those predictions are confirmed, because the predictions would have failed under most alternative mechanisms.

## Diagnosing pathological reasoning

Severity provides precise diagnoses of two common pathologies in scientific reasoning.

A *just so story* (after Kipling, formalized as critique by Gould and Lewontin in "The Spandrels of San Marco," 1979) is an explanation constructed after observing the phenomenon it purports to explain, designed to fit the known facts, and providing no independent way to test or falsify it.
The severity diagnosis: the "test" (fitting a narrative to known facts) has probability approaching 1 of succeeding whether or not the explanation is correct.
The degrees of freedom in constructing the narrative are so large that virtually any observation can be "explained."
The remedy is to identify predictions the hypothesis makes that competing hypotheses do not, and test them — which is exactly the iterative methodology's Stage 6 (retrodictive checks with summary statistics chosen to discriminate between candidate explanations).

*Cargo cult science* (Feynman, 1974 Caltech commencement) mimics the form of scientific investigation — hypotheses, experiments, statistics, peer review, publication — while missing the substance that makes science work.
The severity diagnosis: the apparatus nominally designed to test claims is not actually severe.
Controls are inadequate (the test would have "succeeded" without the effect), comparisons are post hoc (the specific comparison was chosen because it reached significance), or the flexibility of analysis is unacknowledged (many analyses were tried, only the "significant" one is reported).
The form of testing is present; the self-critical apparatus that makes testing severe is absent.

These two pathologies are complementary: a just so story is a failure of explanatory logic (unfalsifiable narrative); cargo cult science is a failure of methodological integrity (testing without severity).
Both can coexist in the same work.

## Lakatos's progressive and degenerating research programs

Imre Lakatos (*The Methodology of Scientific Research Programmes*, 1978) provides the macro-level criterion for evaluating scientific traditions over time.
A research program is *progressive* when its theoretical modifications predict novel facts that are subsequently confirmed.
It is *degenerating* when modifications only accommodate known facts through ad hoc adjustments.

The iterative effective theory methodology is progressive by construction: each model expansion, guided by symmetry constraints and domain expertise, generates new predictions (at higher precision, at different scales, for different observables) that can be tested.
Wells' harmonic oscillator allegory illustrates this: Theory 3 (anharmonic corrections) predicts amplitude-dependent period variations that Theory 1 (simple harmonic) does not, and these predictions are testable at higher measurement precision.

The key distinction from a degenerating program is that model expansions are *constrained*.
Betancourt's nested model expansion with penalized complexity priors ensures that added flexibility only manifests when data demand it.
Wells' symmetry constraints ensure that added operators are not arbitrary but follow from the mathematical structure of the theory.
These constraints prevent the iterative cycle from degenerating into overfitting — the Lakatosian equivalent of ad hoc accommodation.

## Hacking's manipulation criterion

Ian Hacking (*Representing and Intervening*, 1983) draws a philosophical distinction between theoretical representation and experimental intervention, arguing that what makes mature sciences reliable is not better theories but the ability to *manipulate* entities.
If you can spray electrons to investigate something else, electrons are real.

In computational science, this translates to the primacy of *generative simulation*.
If a mechanistic model with inferred parameters can generate synthetic data indistinguishable from observations — and if perturbations to the model produce predictable changes in the synthetic data — then we have computational evidence for the reality of the modeled process.
This is stronger evidence than statistical fit alone, because fit can be achieved by flexible models with no mechanistic content, while successful simulation under perturbation requires that the model captures causal structure.

The manipulation criterion distinguishes between models that *describe* patterns and models that *instantiate* processes.
A regression model describes a relationship; a stochastic dynamical system instantiates the process that generates the relationship.
Only the latter supports Hacking-style inferences about the reality of the modeled entities.

## Galison's convergent diagnostics

Peter Galison (*How Experiments End*, 1987) describes how physicists actually decide that an experiment has succeeded: through the convergence of multiple independent lines of evidence, each with its own systematic uncertainties.
No single measurement is decisive.
What provides confidence is convergence from independent angles.

This maps directly onto Betancourt's diagnostic framework.
No single check — prior predictive, simulation-based calibration, posterior predictive — is decisive.
A model that passes all four of Betancourt's questions (domain consistency, computational faithfulness, inferential adequacy, model adequacy) has been tested from independent angles, and the convergence of these tests is stronger evidence than any single test alone.

Allan Franklin (*The Neglect of Experiment*, 1986; *Experimentation, Right or Wrong*, 1990) provides the detailed epistemological taxonomy: rotation of independent checks, calibration against known phenomena, analysis of systematic error, and use of theory to validate experimental design.
These are the philosophical counterparts to the diagnostic toolkit of principled Bayesian workflows.
