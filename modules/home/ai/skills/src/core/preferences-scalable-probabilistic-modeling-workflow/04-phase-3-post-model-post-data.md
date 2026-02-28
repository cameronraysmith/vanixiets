# Phase III: post-model, post-data

This phase applies the validated model and inference machinery to observed data.
It corresponds to Stages 6-7 of the general iterative methodology in `preferences-scientific-inquiry-methodology` section 03.
This is the first point at which observed data enters the analysis proper.

## Step 12: fit the observation

**[A]** In the amortized setting, inference on the actual observed data $\tilde{y}_{\text{obs}}$ is a single forward pass through the trained approximator: $\hat{\theta} \sim q_\phi(\theta \mid \tilde{y}_{\text{obs}})$.

For non-amortized methods, fit the posterior using the algorithmic configuration from Step 8.

This is the first moment observed data enters the analysis.
All preceding steps operated entirely on simulated data drawn from the model's own prior predictive distribution.

## Step 13: diagnose posterior fit

Re-check all computational diagnostics on this specific fit.

**[A]** For amortized methods, the in-silico calibration from Step 10 is relevant only insofar as $\tilde{y}_{\text{obs}}$ lies within the support of the prior predictive distribution seen during training.
If the observed data is *out-of-distribution* relative to the training simulations (e.g., a dynamical regime not well-covered by the prior), the approximator's output may be unreliable.

Diagnostic strategies for detecting out-of-distribution observations include:

- Checking whether the observation's learned summary $\mathbf{h}_\psi(\tilde{y}_{\text{obs}})$ falls within the training distribution of summaries, via Mahalanobis distance or density estimation in summary space.
- Comparing hand-crafted summary statistics of $\tilde{y}_{\text{obs}}$ against their distribution in the training ensemble.
- Running additional simulations near the inferred posterior to verify local approximation quality.

For MCMC, check standard diagnostics ($\hat{R}$, divergences, effective sample size) on the observed-data fit.

**[D]** Out-of-distribution detection is especially important for dynamical systems because the prior predictive distribution may not cover all dynamical regimes.
A system observed in a regime (e.g., oscillatory) that the prior concentrates away from (e.g., toward fixed-point behavior) will produce unreliable posteriors regardless of the approximator's global calibration.

## Step 14: posterior retrodictive checks

Address Question 4 (model adequacy) by comparing pushforwards of the posterior predictive distribution against observed summary statistics.

**[D]** For dynamical-system models, this means drawing posterior samples $\tilde{\theta} \sim q_\phi(\theta \mid \tilde{y}_{\text{obs}})$, re-simulating full stochastic trajectories $\tilde{y}' \sim \text{Simulator}(\tilde{\theta})$, and comparing ensembles of re-simulated trajectories to the observed data via the summary statistics from Steps 3 and 5.

Concrete diagnostic visualizations:

- Overlay quantile ribbons of re-simulated trajectories on the observed time series.
- Compare temporal, spectral, and distributional summaries between re-simulated and observed data.
- Check regime occupancy, transition statistics, and any domain-specific diagnostics.

Interpreting failures:

If a failure corresponds to a behavior already anticipated in the conceptual analysis (Step 1), return to Step 4 to expand the model with the anticipated mechanism.
If the failure is surprising, return to Step 1 to reconsider the dynamical model with domain experts.
Examples of surprising failures include missing forcing terms, unmodeled feedback loops, incorrect noise structure, or state-dependent observation error.

*Carry only the qualitative failure forward, not the quantitative features of the data, to guard against overfitting.*

## Step 15: celebrate

If the model passes all checks relevant to the inferential goals, the iteration terminates.
The model is not "correct" in any absolute sense but meets the needs of the given inferential task.

Both the model and the approximator are provisional: the model is adequate for the current inferential question within the tested domain, and the approximator is validated within the model's prior predictive distribution.
Future data, new questions, or higher precision may reveal inadequacies that restart the cycle.
