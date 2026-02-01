# Hierarchy of approaches by evidential rigor

Different computational approaches occupy different positions within the framework based on the strength of evidence they can provide for mechanistic claims.
This is not a ranking of engineering usefulness — predictive utility and scientific evidence are different things — but a ranking of what kind of scientific claim each approach can support under the severity criterion.

## Tier 1: derived effective theories with controlled approximations

Starting from a fine-grained description (a master equation for molecular state transitions, a quantum field theory, a detailed kinetic model) and *deriving* a coarse-grained description (a piecewise deterministic Markov process, a system-size expansion yielding a Fokker-Planck equation, an RG flow yielding universality classes) with explicit mathematical control over the approximation.

The relationship between scales is derived, not assumed.
The approximation errors are bounded, at least in principle.
The predictions at the coarser scale are specific enough to fail.
This is the effective theory methodology in its strongest form.

It provides the most severe evidence for mechanistic claims because the coarse-grained predictions are *consequences* of the fine-grained mechanism, not free parameters.
If the coarse-grained predictions are confirmed, the fine-grained mechanism (or at least its universality class) is supported with high severity — the predictions would have failed under most alternative mechanisms.

Examples: deriving transcriptional bursting statistics from promoter switching kinetics; deriving collective fluctuation behavior from single-gene stochastic models via system-size expansion; deriving macroscopic transport properties from microscopic kinetics via renormalization group methods.

## Tier 2: mechanistic generative models with principled Bayesian inference

The generative model — a stochastic dynamical system, a network of biochemical reactions, a kinetic model — instantiates a specific mechanism with parameters that have defined physical or biological meaning (interaction strengths, rate constants, burst frequencies, degradation rates).

Bayesian inference quantifies uncertainty over these parameters.
The full diagnostic workflow (Stages 3-7 of the iterative methodology) provides severe tests at each stage.
When neural networks are used for inference (amortized simulation-based inference), they are computational tools for approximating the posterior of the mechanistic model.
The scientific content is entirely in the generative model.
The network's internal representations need not be interpretable because the output — a posterior distribution over mechanistic parameters — is interpretable by construction.

The distinction from Tier 1 is that the generative model is *posited* at the scale of interest rather than derived from a finer-grained theory.
Its parameters are meaningful, its predictions are testable, but the relationship to finer-grained descriptions is not mathematically controlled.
This means the model may capture the wrong universality class — a risk that Tier 1 approaches mitigate by derivation.

## Tier 3: phenomenological models with statistical discipline

Hierarchical Bayesian models, Gaussian processes, sparsity-inducing priors (horseshoe, regularized horseshoe), and other flexible statistical models that do not derive from first principles but make explicit, testable assumptions and quantify uncertainty honestly.

These are effective theories in the pragmatic sense: useful within a stated domain, with known limitations, and subject to the same diagnostic workflow.
They provide weaker evidence for mechanism than derived or mechanistic models because their parameters typically do not correspond to identifiable physical quantities.
A hierarchical model with partial pooling captures population structure, but the hierarchical structure is a statistical convenience, not a mechanistic claim.

Their strength is honest uncertainty quantification and the ability to detect structure in data that motivates mechanistic hypotheses.
They serve the abductive stage of inquiry — generating hypotheses for subsequent mechanistic investigation — rather than the inductive stage of testing mechanistic claims.

## Tier 4: neural surrogate models in service of mechanistic inquiry

Using neural networks to approximate likelihoods, solve differential equations, emulate expensive simulators, or accelerate sampling — in contexts where the scientific question is defined by a mechanistic model and the neural network is a computational tool for making inference on that model tractable.

The neural network introduces approximation error that must be diagnosed (Stage 4 of the iterative methodology), but the scientific claims are about the mechanistic model, not the surrogate.
If the surrogate is faithful (verified by SBC or equivalent diagnostics), the inferences inherit the interpretability of the mechanistic model.

The distinction from Tier 2 is that Tier 2 uses neural networks specifically for posterior approximation (amortized inference), while Tier 4 encompasses a broader range of uses — likelihood emulation, differential equation solving, simulator acceleration — all in service of a mechanistic model.

## Tier 5: pure pattern recognition without mechanistic grounding

Models that learn mappings from input to output without instantiating any generative process.
This includes sequence-to-phenotype neural networks, genomic foundation models, and other approaches where the model's internal representations are the primary object of study.

These can be powerful predictive tools.
They fail the severity criterion for mechanistic claims because the model has sufficient flexibility to fit essentially any mapping: no particular fit constitutes severe evidence for any specific mechanism.
A model with enough capacity to approximate any function cannot fail any distributional test, and therefore no distributional match constitutes severe evidence for any particular hypothesis about the underlying process.

Post hoc interpretability methods — attention visualization, gradient-based attribution, feature importance scores, concept probing — are, in the precise sense developed in the epistemology of evidence, just so stories about what the network has learned.
They are narratives constructed after the fact that accommodate the known behavior of the network.
They would have been constructed regardless of the network's true internal structure, because the space of possible narratives is large enough to accommodate any observed behavior.

This does not mean such models are useless for science.
Their evidential contribution is in identifying statistical regularities that *suggest* hypotheses for mechanistic investigation through the approaches in Tiers 1-4.
They serve the abductive function — generating candidate hypotheses — but the hypotheses must then be formulated as mechanistic models and tested with severity.

## The tier boundary that matters most

The critical boundary in this hierarchy is between Tiers 1-4 and Tier 5.
Tiers 1-4 all share a common structure: a mechanistic generative model defines the scientific hypothesis, and computational tools (analytical, sampling-based, or neural) serve that model.
The interpretability of scientific claims is preserved because the claims are about the generative model's parameters and mechanisms, not about the computational tool's internal representations.

Tier 5 inverts this relationship: the computational tool *is* the model, and scientific claims must be extracted from its internal representations — a process that lacks severity.

This boundary is not about the presence or absence of neural networks.
Neural networks appear in Tiers 2 and 4 as well.
The distinction is whether the neural network serves a mechanistic model (Tiers 2, 4) or replaces it (Tier 5).
