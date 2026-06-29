# Foundations and framework

## The Bayesian model with implicit likelihood

The goal is to iteratively build a complete Bayesian model $\pi_{\mathcal{S}}(y, \theta) = \pi_{\mathcal{S}}(y \mid \theta)\,\pi_{\mathcal{S}}(\theta)$ adequate for answering specific inferential questions.
The workflow is not a deterministic algorithm but a coherent set of evaluation techniques guiding a unique path through model space, because every application poses different questions in different contexts.
It requires both *domain expertise* (knowledge of the latent dynamics, measurement process, experimental design, and stakeholder needs) and *statistical expertise* (proficiency in probabilistic modeling, numerical simulation, and computational inference).

**[D]** When the forward model is a stochastic dynamical system, the observational model $\pi_{\mathcal{S}}(y \mid \theta)$ is typically an *implicit* likelihood defined only through a simulator rather than a closed-form expression.
Concretely, this covers systems of stochastic differential equations $d\mathbf{x} = f(\mathbf{x}, \theta)\,dt + g(\mathbf{x}, \theta)\,dW$, Markov jump processes, agent-based models, partial differential equations with stochastic forcing, and any model where forward simulation is feasible but likelihood evaluation is not.
The model is defined implicitly through a simulator $\mathbf{x} \sim \text{Solve}(f, g, \theta, \mathbf{x}_0)$ composed with an observation model $y \sim p(y \mid \mathbf{x})$.

This framework applies across scientific domains: gene regulatory network dynamics in molecular biology, general circulation models in climate science, compartmental models in epidemiology, stochastic volatility models in economics, reaction networks in chemical kinetics, predator-prey dynamics in ecology, and any setting where the generative model is a simulator with intractable likelihood.

The true data generating process $\pi^{\dagger}$ is a single point in the space of all data generating processes; the model defines a subset.
Formal comparison requires reducing the model to a single *predictive distribution* (prior predictive or posterior predictive) that can be compared pointwise to $\pi^{\dagger}$.
Model evaluation is iterative: begin with a simple model, investigate its consequences, identify deficiencies, and refine, cycling until the model meets the needs of the analysis.

## The amortized inference paradigm

**[A]** In the amortized Bayesian inference (ABI) paradigm, a neural network $q_\phi(\theta \mid \mathbf{h}(y))$ consisting of a learned summary network $\mathbf{h}$ and a conditional generative inference network is trained on a large ensemble of simulated $(\theta, y)$ pairs to approximate the posterior mapping for *any* new observation, thereby amortizing the computational cost of inference across datasets.

The amortized approach separates the workflow into a computationally expensive *offline* phase (simulation and training) and a computationally cheap *online* phase (inference on new observations via a single forward pass).
This asymmetry has profound consequences for workflow validation: simulation-based calibration and inferential diagnostics that would be prohibitively expensive with per-dataset MCMC become computationally trivial, enabling far more thorough validation than traditional approaches allow.

Frameworks implementing this paradigm include BayesFlow (Radev et al., 2020), sbi (Tejero-Cantero et al., 2020), and other simulation-based inference libraries in the broader landscape surveyed by Cranmer, Brehmer, and Louppe (2020).

## The four guiding questions

Four questions structure every iteration of the workflow:

*Question 1 -- domain expertise consistency.*
Is the model, including the dynamical structure, noise model, and priors over all parameters (dynamical rates, noise scales, initial/boundary conditions), consistent with domain expertise?

*Question 2 -- computational faithfulness.* **[DA]**
Will the computational tools (whether MCMC, variational inference, or a trained neural approximator) accurately approximate posterior expectations $\mathbb{E}_{\pi(\theta \mid \tilde{y})}[f]$ for the posteriors arising from this model?

*Question 3 -- inferential adequacy.*
Will the inferences (or decisions based on them) provide enough information to answer the questions motivating the analysis?

*Question 4 -- model adequacy.*
Is the model rich enough to capture the structure of $\pi^{\dagger}$ relevant to the inferential goals?

## Summary functions and statistics

High-dimensional models cannot be reasoned about as a whole; we project to interpretable lower-dimensional subspaces via *summary functions* $t: Y \times \Theta \to U$ and analyze the pushforward distribution $\pi_{t(Y \times \Theta)}(t)$.

*Prior pushforward checks* use summary functions $t: \Theta \to U$ on the model configuration space.
Coordinate functions, internal nodes of the directed graphical model, and derived dynamical quantities are natural candidates.
**[D]** For dynamical systems, these include steady-state values, eigenvalues of Jacobians, regime indicators, oscillation periods, bifurcation thresholds, and similar quantities derived from the parameterized dynamics.

*Summary statistics* $\hat{t}: Y \to U$ restricted to the observational space enable prior predictive checks and posterior retrodictive checks without requiring domain experts to understand model internals.
**[D]** For dynamical systems, summary statistics should be tailored to the temporal or spatial structure of the data: autocorrelation functions, spectral densities, peak counts, period estimates, growth rates, phase-plane winding numbers, Lyapunov exponents, empirical quantiles of trajectory functionals, inter-event time distributions, and regime occupancy fractions.
The appropriate statistics depend on the domain: spectral densities for oscillatory dynamics, cluster size distributions for spatial models, return time statistics for population processes, volatility measures for financial models, and so on.

**[A]** In the amortized setting, a learned summary network $\mathbf{h}_\psi: Y \to \mathbb{R}^d$ replaces or supplements hand-crafted summary statistics with representations that are jointly optimized with the inference network.
Nevertheless, hand-crafted statistics remain essential for interpretability and for prior predictive / posterior retrodictive checks that require human evaluation.

Domain expertise is elicited as approximate *thresholds* separating "reasonable" from "extreme" values of each summary function -- thresholds that capture the boundary between ambivalence and unease, not sharp classifications.
Domain expertise elicitation is itself iterative: quantifications evolve with effort, and we need only a self-consistent approximation sufficient for the analysis at hand.

## Posterior retrodiction and model adequacy

The *posterior predictive distribution* $\pi_{\mathcal{S}}(y \mid \tilde{y}) = \int d\theta\,\pi_{\mathcal{S}}(\theta \mid \tilde{y})\,\pi_{\mathcal{S}}(y \mid \theta)$ reduces the entire Bayesian model to a single predictive distribution averaging over all posterior uncertainty.

**[D]** For dynamical-system models with implicit likelihoods, posterior predictive samples are generated by drawing $\tilde{\theta} \sim q_\phi(\theta \mid \tilde{y})$ (or from MCMC) and then *re-simulating* trajectories $\tilde{y}' \sim \text{Simulator}(\tilde{\theta})$, including all stochastic and observational noise.
This is sometimes called the *posterior predictive re-simulation* or *generative performance* check.

*Posterior retrodictive checks* compare the pushforward of the posterior predictive distribution $\pi_{t(Y)|Y}(t \mid \tilde{y})$ against the observed summary statistic $t(\tilde{y})$.
If $t(\tilde{y})$ falls in the bulk of the pushforward distribution, there is no indication of model inadequacy along that dimension.
If it falls in the tails, domain expertise must arbitrate whether this reflects a rare fluctuation or genuine model misspecification.

Posterior retrodictive checks assess only self-consistency at a particular observation.
Proper *posterior predictive checks* against held-out observations provide a broader view of model-$\pi^{\dagger}$ compatibility.

## Simulation-based calibration

SBC validates computational faithfulness: if $\tilde{\theta} \sim \pi(\theta)$ and $\tilde{y} \sim \pi(y \mid \tilde{\theta})$, the rank of $\tilde{\theta}$ within posterior samples from $\pi(\theta \mid \tilde{y})$ should be uniformly distributed.
Systematic deviations in the rank histogram diagnose specific computational failures (bias, over/under-dispersion, miscalibration).

**[A]** Because amortized inference provides instant approximate posteriors for any simulated $\tilde{y}$, SBC can be performed over thousands of simulated datasets at negligible marginal cost.
This is computationally prohibitive with per-dataset MCMC or ABC, making it a major practical advantage of amortization for workflow validation.

SBC assesses accuracy only within the context of the model's own prior predictive distribution; it says nothing about faithfulness for data generated by a very different $\pi^{\dagger}$.

## Inferential calibration via z-scores and contraction

The *posterior z-score* $z[f \mid \tilde{y}, \theta^{\dagger}] = \frac{\mathbb{E}_{\text{post}}[f \mid \tilde{y}] - f(\theta^{\dagger})}{\mathbb{s}_{\text{post}}[f \mid \tilde{y}]}$ quantifies how accurately the posterior recovers the true configuration.

The *posterior contraction* $c = 1 - \frac{\mathbb{s}_{\text{post}}^2[f]}{\mathbb{s}_{\text{prior}}^2[f]}$ quantifies how much the posterior has learned relative to the prior.

Jointly examining the distribution of $(c, z)$ over the simulated ensemble diagnoses: non-identifiability (low contraction), overfitting (high contraction with large z-scores), and computational artifacts.

**[A]** Additional amortized diagnostics include *normalized root mean squared error* (NRMSE) between posterior means and true values across the simulated ensemble, and *calibration ECDFs* that generalize SBC rank histograms to continuous diagnostics with simultaneous confidence bands.

**[D]** For dynamical-system models, some parameters (e.g., redundant kinetic rates in chemical reaction networks, symmetry-related initial conditions in physical models) may be structurally non-identifiable regardless of data quality.
The $(c, z)$ diagnostic helps distinguish structural non-identifiability (intrinsic to the model) from practical non-identifiability (insufficient data), guiding whether to reparameterize, add informative priors, or redesign the experiment.

## Overfitting vigilance

Overfitting arises when model development is driven by the quantitative features of the observed data rather than by domain expertise triggered by qualitative failures.
A posterior retrodictive check should serve only to *trigger* domain expertise; the domain expertise should then be solely responsible for continued model development.

**[A]** In the amortized setting, a distinct form of overfitting can occur at the *approximator* level: the neural network may memorize the finite training set of simulations rather than learning a generalizable posterior mapping.
This is monitored via the train/validation loss gap and by evaluating SBC and recovery diagnostics on held-out simulated datasets not seen during training.

Thorough documentation of the model development process is the best protection, enabling a community to leverage collective expertise to identify overfitting.
