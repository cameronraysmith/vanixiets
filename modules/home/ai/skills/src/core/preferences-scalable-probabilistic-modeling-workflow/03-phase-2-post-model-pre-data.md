# Phase II: post-model, pre-data

This phase develops, validates, and calibrates the model and inference machinery entirely on simulated data, before any observed data enters the analysis.
It corresponds to Stages 4-5 of the general iterative methodology in `preferences-scientific-inquiry-methodology` section 03.

## Step 4: model development

Construct the complete Bayesian model.

**[D]** For stochastic dynamical systems, this means specifying:

(a) The dynamical model as a system of SDEs, ODEs with stochastic observation, jump processes, or similar, parameterized by $\theta$.

(b) The observation model $p(y \mid \mathbf{x}(\theta))$ linking latent states to data.

(c) The prior $\pi(\theta)$ over all parameters including dynamical rates, noise scales, initial conditions, and any hyperparameters.

Prefer *generative modeling* that specifies the full conditional decomposition sequentially -- draw parameters, solve dynamics, apply observation model -- so that the data-generating story is told as a forward simulation pipeline.
In the initial iteration, the model need only be sophisticated enough to attempt an answer to the inferential question.

The same structural advice applies regardless of domain: a climate model specifies forcing parameters, integrates the dynamics, and applies an observation operator; an epidemiological model specifies transmission rates, solves the compartmental dynamics, and applies a reporting model; a financial model specifies volatility parameters, simulates price paths, and applies a market microstructure observation model.

## Step 4a: verify simulator fidelity [D]

Before proceeding, verify that the numerical solver (integration scheme, step size, tolerance) faithfully represents the stochastic dynamical model across the prior-supported parameter range.
Solver pathologies (instability, excessive stiffness, numerical divergence) at certain parameter configurations can corrupt the entire downstream workflow.

Test the simulator on a grid or random sample of prior configurations and inspect for NaNs, explosions, or implausible trajectories.
Simulator bugs are the single most common source of failure in simulation-based workflows.

Common solver pathologies by domain:

- Stiff systems (chemical kinetics, fast-slow dynamics): require implicit solvers or adaptive step-size control.
- Near-bifurcation regimes (ecological, epidemiological models): trajectories can diverge or collapse depending on numerical precision.
- High-dimensional systems (spatial models, agent-based models): memory and runtime constraints may require approximation strategies.
- Jump processes (single-molecule dynamics, queueing models): exact algorithms (Gillespie) vs. tau-leaping approximations have different fidelity-cost tradeoffs.

## Step 5: construct summary functions

Define summary functions $t: \Theta \to U$ over the model configuration space for prior pushforward checks.

**[D]** For dynamical systems, include derived dynamical quantities: steady-state values, oscillation periods, bifurcation indicators, effective reproduction numbers, Lyapunov exponents, or analogous quantities computed from the parameterized dynamics.
These are not arbitrary projections but quantities that capture the qualitative behavior implied by a given parameter configuration.

**[A]** If learned summary networks will be used, this is the step to decide which hand-crafted statistics to retain for interpretable checks alongside the learned representations.
The learned network optimizes for inference performance, but hand-crafted statistics are needed for human-evaluable prior predictive and posterior retrodictive checks.

## Step 6: simulate Bayesian ensemble

Generate a large ensemble of $(\tilde{\theta}, \tilde{y})$ pairs by ancestral sampling: $\tilde{\theta} \sim \pi_{\mathcal{S}}(\theta)$, then $\tilde{\mathbf{x}} \sim \text{Solve}(f, g, \tilde{\theta}, \mathbf{x}_0)$, then $\tilde{y} \sim p(y \mid \tilde{\mathbf{x}})$.

**[D]** Each simulation involves running the full numerical solver, which may be expensive.
This motivates careful consideration of the simulation budget and parallelization strategy.
Simulation cost varies dramatically across domains: a simple SDE may take milliseconds, while a climate model simulation may take hours.

**[A]** In the amortized setting, this same ensemble (or an expanded version) will serve double duty as the *training data* for the neural approximator, so its size, diversity, and quality are critical.
Consider online vs. offline simulation strategies: offline pre-generates a fixed dataset, while online generates fresh simulations during training, reducing memorization risk at the cost of wall-clock time.

The ensemble must adequately cover the prior-supported parameter range.
Underrepresentation of any region means the approximator will be poorly calibrated there, and diagnostics will not detect this gap unless specifically probed.

## Step 7: prior checks

Perform prior pushforward checks and prior predictive checks to answer Question 1 (domain expertise consistency).
Compare pushforward distributions against domain-expertise thresholds.

**[D]** For dynamical systems, visually inspect the prior predictive distribution of *trajectories* (e.g., quantile ribbons over time) and dynamically meaningful summaries.
Verify that the prior does not place excessive mass on dynamically degenerate regimes (e.g., immediate extinction, divergence, absorbing states, or dynamically meaningless parameter combinations).

If conflicts arise, return to Step 4 and refine the model.
*No observed data enters this step.*

## Step 8: configure approximation architecture [DA]

Specify the computational method for posterior inference and its configuration.

**[A]** In the amortized setting, this means selecting:

(a) A *summary network* architecture $\mathbf{h}_\psi$ appropriate for the data modality.
Examples: recurrent networks or temporal convolutions for time series, set transformers for exchangeable observations, graph neural networks for spatial or relational data.

(b) A *conditional inference network* architecture $q_\phi(\theta \mid \mathbf{h}_\psi(y))$.
Examples: coupling flows, flow matching, diffusion models, consistency models.

(c) An *adapter/preprocessing pipeline* that transforms raw simulator outputs (potentially variable-length, high-dimensional, multi-modal) into a standardized format suitable for neural network training, including dtype conversions, log-transforms of positive quantities, and concatenation of parameter vectors.

(d) Training hyperparameters: learning rate, batch size, number of epochs, simulation budget.

For non-amortized methods (MCMC, variational inference), specify the sampler and its tuning as in the standard Bayesian workflow.

## Step 9: train approximator / fit simulated ensemble [DA]

**[A]** Train the neural approximator on the simulated ensemble (or via online simulation) by minimizing the appropriate loss: negative log-likelihood for normalizing flows, regression loss for flow matching or diffusion models, classification loss for ratio estimation.
Monitor training and validation loss curves for convergence and generalization.
The trained approximator $q_\phi(\theta \mid y)$ then provides instant approximate posteriors for any observation.

For non-amortized methods, fit posteriors $\pi_{\mathcal{S}}(\theta \mid \tilde{y})$ for each simulated observation in the ensemble, recording diagnostics, SBC ranks, z-scores, and contractions.

## Step 10: algorithmic calibration

Address Question 2 (computational faithfulness).

**[A]** For amortized methods:

(a) Inspect training/validation loss convergence and the gap between them (overfitting of the *approximator*, distinct from model overfitting).

(b) Perform SBC across a large held-out simulated ensemble.
This is computationally cheap because each posterior evaluation is a single forward pass.

(c) Examine calibration ECDFs with simultaneous confidence bands for a global assessment of calibration quality.

(d) Inspect *recovery plots* (posterior mean vs. true value) for systematic biases.

For MCMC: examine $\hat{R}$, divergences, E-BFMI across the ensemble.

**[D]** For dynamical systems, specific parameter regimes (e.g., near bifurcations, at the boundary between qualitatively different dynamical behaviors) often produce posteriors that are especially difficult to approximate.
Monitor calibration specifically in these regions.
Correlate failures with specific simulated $(\tilde{y}, \tilde{\theta})$ to identify pathological posterior geometries.

If failures are found, return to Step 8 (change architecture, increase training budget, improve adapter transforms) or Step 4 (reparameterize, strengthen priors consistent with domain expertise).

## Step 11: inferential calibration

Address Question 3 (inferential adequacy) by examining the joint distribution of posterior z-scores and contractions, NRMSE, and any explicit utility functions across the ensemble.

**[D]** For dynamical systems, pay special attention to parameters that enter the dynamics redundantly or are only weakly constrained by the observation design.
Examples include: a rate constant observable only through its ratio with another (in chemical kinetics), transmission-recovery rate confounding (in epidemiology), or degenerate initial conditions (in physical models).

**[A]** The amortized framework makes it cheap to sweep over different observation designs (number of time points, which variables are observed, noise levels) to determine the minimal experiment needed for adequate inference -- a form of *computational experimental design* that is prohibitively expensive with per-dataset inference.

If inferences are inadequate, return to Step 4 (incorporate more domain expertise, improve parameterization) or Step 1 (redesign experiment, temper scientific goals).

## Step 11a: amortization scope validation [A]

Verify that the approximator generalizes appropriately across the range of contexts it is intended to cover.
If the approximator is amortized over context variables (e.g., number of observations $N$, observation times, experimental conditions), validate calibration *conditional on each context*.

Performance may degrade in corners of the context space underrepresented during training.
This step catches a failure mode specific to amortized inference: an approximator that is well-calibrated on average but poorly calibrated for specific experimental configurations.
