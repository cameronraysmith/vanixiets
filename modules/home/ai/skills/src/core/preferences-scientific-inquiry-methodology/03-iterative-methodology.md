# The iterative methodology

This section synthesizes Wells' effective theory construction with Betancourt's principled Bayesian workflow into a unified pipeline for scientific model building.
The stages constitute Peircean inquiry made operational.

## Stage 1: establish the aspirational context

Before writing any model, articulate the *aspirational model* — a hypothetical, possibly unrealizable description incorporating all potentially relevant systematic effects.
This serves not as a target to be achieved but as a map of what the current model ignores.

In Wells' terms, this means identifying all operators consistent with the symmetries of the problem.
In Betancourt's terms, this means listing all systematic effects that could, in principle, matter — heterogeneity, temporal variation, environmental corruption, latent complexities, measurement artifacts.

The gap between the aspirational model and the current model is a source of hypotheses for future expansion.
It also guides the choice of summary statistics in later diagnostic stages: summary statistics should be chosen to probe the structure that the current model omits but the aspirational model includes.

## Stage 2: build the simplest consistent model

Begin with a model that is as simple as possible while respecting three constraints:

- The symmetries and conservation laws of the domain.
- Known scale separations that determine which degrees of freedom are relevant.
- Domain expertise about the dominant mechanisms at the scale of interest.

In the effective theory tradition, this means including only leading-order operators — but including *all* leading-order operators consistent with the symmetries.
Omitting terms for simplicity while retaining others at the same order introduces artificial structure (Wells' consistency principle).

In the Bayesian tradition, this means choosing priors that concentrate around simple configurations (penalized complexity) and a likelihood that captures the dominant data-generating mechanism.
The prior must be consistent with all known domain expertise, not just the subset that produces convenient posteriors.

Betancourt emphasizes that domain expertise is elicited *iteratively*, not specified once upfront.
Begin with an initial model just sophisticated enough to capture the phenomena of interest, with minimal systematic effects.
The difference between this and the aspirational model encapsulates ignored structure that will guide subsequent diagnostic and expansion stages.

## Stage 3: test domain expertise consistency

Before observing data, interrogate the model's prior predictive distribution.

*Prior pushforward checks* examine summary functions of the parameter space alone: do the implied parameter ranges correspond to physically or biologically meaningful values?
Are interaction strengths within plausible bounds?
Are timescales consistent with known kinetics?

*Prior predictive checks* project to the observational space: does the model generate outcomes consistent with what domain experts consider plausible?
Would the synthetic data be recognized as reasonable by someone familiar with the system?

Betancourt's key insight is that *thresholds* — boundaries separating reasonable from extreme values — are easier to elicit from domain experts than full probability distributions.
Humans are better at rejecting implausible values than specifying plausible ones.
Visualize where prior predictive summaries fall relative to these thresholds using quantile ribbons.

This stage corresponds to the Peircean deductive phase: derive the model's consequences and check them against existing knowledge before confronting new data.

## Stage 4: test computational faithfulness

Verify that the inference machinery accurately recovers the model's posterior.
This tests the *tool*, not the science — but a tool that fails this test produces unreliable results regardless of how good the science is.

*Simulation-based calibration* (SBC) exploits a consistency property of Bayesian models: the average posterior distribution over prior predictive draws recovers the prior distribution exactly.
Generate many synthetic datasets from the prior predictive, run inference on each, and compute the rank of the true parameter value within the posterior samples.
If computation is faithful, ranks are uniformly distributed.
Systematic deviations in rank histograms expose bias, underdispersion, overfitting, and other computational pathologies.

This stage applies equally to MCMC, variational inference, and amortized neural inference.
When using neural networks for amortized inference, SBC verifies that the network's posterior approximation is faithful — that the computational acceleration does not introduce systematic bias.

## Stage 5: assess inferential adequacy

Given the data available, determine whether the posterior provides enough information to answer the scientific question.

Betancourt introduces two diagnostics applied to simulation-based calibration results:

*Posterior z-score*: how far posterior estimates deviate from the true simulated value, normalized by posterior standard deviation.
Small values indicate good parameter recovery; large values indicate the posterior is drawn away from truth by data or prior conflict.

*Posterior contraction*: how much the likelihood reduces posterior variance relative to prior variance.
Near zero means data are uninformative for that parameter; near one means data are highly informative.

Scatter plots of z-score against contraction create a diagnostic landscape that identifies: ideal learning (small z-score, large contraction), overfitting (high z-score, high contraction), uninformative data (low z-score, low contraction), and prior-likelihood conflict (large z-score, small contraction).

This stage determines whether the question being asked is answerable with the data at hand — a determination that must precede any claims about model adequacy.

## Stage 6: test model adequacy through retrodiction

Compare posterior predictive distributions against observed data.
This is not prediction of new data but *retrodiction* of existing observations, incorporating all inferential uncertainty from both the prior and the likelihood.

Generate posterior predictive samples by ancestral sampling: draw parameters from the posterior, then draw data from the generative model conditional on those parameters.
Apply summary statistics — chosen to probe the gap between the current model and the aspirational model — to both observed and retrodicted data.

If observed summary statistics fall within the bulk of the posterior predictive distribution, no model deficiency is evident for that summary.
If they fall in the tails, tension exists.
Betancourt is careful to note that this tension is inherently ambiguous: you cannot discriminate between a rare fluctuation and genuine model inadequacy from a single dataset, because the data are being used twice (once for inference, once for checking).

The ambiguity is resolved not by any single check but by the *pattern* of checks across multiple summary statistics — Galison's convergent diagnostics.
Systematic deviations across summaries sensitive to the same unmodeled structure provide stronger evidence of inadequacy than any single outlying summary.

## Stage 7: expand the model and iterate

When retrodictive checks reveal inadequacy, expand the model by incorporating the next most relevant systematic effect from the aspirational context.

The expansion must be *nested*: the previous model's configurations must remain accessible within the expanded model's parameter space.
Formally, this means the expansion satisfies the inclusion relation between model spaces.
Parameterize new structure so that it "turns off" when new parameters equal zero, and use penalized complexity priors that concentrate around the simpler configuration.

This nesting provides two protections.
First, it guards against overfitting: if added flexibility doesn't improve fit, posteriors collapse back to simpler configurations.
Second, it makes the expansion conservative: added flexibility manifests only when data demand it.

Return to Stage 3 and repeat.
The cycle is Peircean inquiry made operational: surprise (retrodictive failure) generates hypothesis (model expansion guided by aspirational context and symmetry constraints), which generates prediction (prior predictive of expanded model), which is tested (the full diagnostic workflow applied to the expanded model).

## The cycle as method

The entire workflow formalizes iterative model development as the scientific method applied with mathematical precision.
Betancourt's four questions structure every iteration:

1. Is the model consistent with domain expertise? (Stages 2-3)
2. Are computational tools faithful? (Stage 4)
3. Do inferences provide enough information? (Stage 5)
4. Is the model rich enough to capture relevant structure? (Stage 6)

Wells' effective theory perspective provides the theoretical framework: each iteration produces a better effective theory — one that accommodates more data, makes more precise predictions, and has a clearer understanding of its own domain of applicability and the structure it ignores.

Peirce's pragmatism provides the philosophical foundation: the method is self-correcting not because any single iteration reaches truth, but because the *process* is structured so that errors are exposed and drive principled refinement.
The method's reliability is in the method, not in any particular model it produces.
