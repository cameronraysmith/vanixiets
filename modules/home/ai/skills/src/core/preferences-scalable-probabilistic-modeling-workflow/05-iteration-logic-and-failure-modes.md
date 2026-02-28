# Iteration logic and failure modes

The workflow is inherently iterative: most real analyses cycle through the steps multiple times, with each iteration refining the model in response to a specific diagnosed deficiency.
This section catalogs the failure modes, their diagnostic signatures, and the principled return-to-step mapping for each.

## Failure mode to return-to-step mapping

### Prior check failure

*Diagnostic*: prior pushforward or prior predictive distributions fall outside domain-expertise thresholds (Step 7).

*Return to*: Step 4.
Refine model assumptions, adjust priors, fix dynamical model structure.

### Simulator fidelity failure [D]

*Diagnostic*: NaNs, numerical explosions, implausible trajectories, or solver warnings across prior-supported parameter configurations (Step 4a).

*Return to*: Step 4a.
Improve the numerical solver: reduce step size, switch to an implicit integrator for stiff systems, add error checking, handle boundary cases.
If the pathology is fundamental (the model produces dynamics that no reasonable solver can handle), reconsider the model structure at Step 4.

### Approximator training failure [A]

*Diagnostic*: loss divergence, poor convergence, or large train/validation gap (Step 9).

*Return to*: Step 8.
Change architecture, adjust learning rate, increase simulation budget, improve adapter preprocessing.
If the problem persists despite architecture changes, the posterior geometry may be intrinsically difficult; consider reparameterizing the model at Step 4.

### Algorithmic calibration failure

*Diagnostic*: SBC rank histograms deviate from uniformity, calibration ECDFs fall outside confidence bands, recovery plots show systematic bias (Step 10).

*Return to*: Step 8 (tune algorithm or retrain with more data / better architecture), or Step 4 (reparameterize the dynamical model to ease the posterior geometry), or Step 1 (simplify goals if inference is fundamentally intractable).

**[D]** For dynamical systems, calibration failures often concentrate near bifurcation boundaries or in parameter regimes where the dynamics are qualitatively sensitive to small parameter changes.
Identifying these regions guides targeted reparameterization or prior adjustment.

### Inferential calibration failure

*Diagnostic*: posterior z-scores indicate poor recovery, contraction is low for parameters of interest, or NRMSE is unacceptable (Step 11).

*Return to*: Step 4 (add domain expertise, improve identifiability through reparameterization or stronger priors) or Step 1 (redesign experiment to observe more informative variables or at more time points).

**[D]** For dynamical systems, distinguish structural non-identifiability (intrinsic to the model; e.g., only a ratio of two parameters is identifiable) from practical non-identifiability (insufficient data; more observations or lower noise would resolve it).
The former requires reparameterization or acceptance; the latter motivates experimental redesign.

### Out-of-distribution detection at observed data [A]

*Diagnostic*: observed data summary falls outside the training distribution in summary space; Mahalanobis distance or density estimate flags the observation as atypical (Step 13).

*Return to*: Step 4 (expand the prior to cover the observed regime) or Step 8 (retrain the approximator with a broader simulation budget covering the observed regime).

### Posterior retrodictive failure (anticipated)

*Diagnostic*: posterior predictive re-simulations deviate from observed data along a dimension anticipated in the conceptual analysis (Step 14).

*Return to*: Step 4.
Expand the dynamical model to include the anticipated mechanism.
The failure was expected; the expansion was deferred to avoid premature complexity.

### Posterior retrodictive failure (surprising)

*Diagnostic*: posterior predictive re-simulations deviate from observed data in a way not anticipated by the conceptual analysis (Step 14).

*Return to*: Step 1.
Revisit the conceptual understanding of the dynamics, noise structure, and observation process with domain experts.
Carry only the qualitative failure forward, not the quantitative features of the data, to guard against overfitting.

## Model change invalidation rules

**[A]** When iterating the model (Steps 1-7), the approximator from the previous iteration is generally invalidated and must be retrained from scratch (or fine-tuned) on simulations from the updated model.
The simulation ensemble from Step 6 and the trained approximator from Step 9 are coupled to a specific model; changing the model changes both.

Specifically:

- Changing the prior $\pi(\theta)$ invalidates the simulation ensemble and the approximator.
- Changing the dynamical model $f, g$ invalidates the simulation ensemble and the approximator.
- Changing the observation model $p(y \mid \mathbf{x})$ invalidates the simulation ensemble and the approximator.
- Changing only the approximation architecture (Step 8) while keeping the model fixed allows reuse of the simulation ensemble.
- Adding training data to the existing ensemble without changing the model allows fine-tuning rather than retraining from scratch.

## Iteration strategy

Computational issues that frustrate the algorithm can sometimes be ameliorated by stronger priors, but *only* if the suppressed behavior genuinely conflicts with domain expertise.
Using priors to paper over computational difficulties without domain justification is a form of bias.

Sometimes computational or inferential inadequacy cannot be resolved, requiring less ambitious inferential goals and simpler models.
This is not a failure of the workflow but a legitimate outcome: the workflow has revealed that the question is harder than anticipated given the available data and computational resources.

**[DA]** The workflow does not yield a correct model -- only one that meets the needs of a given inferential task.
The amortized inference layer does not yield exact posteriors -- only approximations whose quality has been validated within the model's own prior predictive distribution.
Both model and approximator are provisional.
Thorough documentation of the model development and approximator training process is essential for reproducibility and community critique.

## References

- Betancourt, M. (2020). *Towards A Principled Bayesian Workflow*. <https://betanalpha.github.io/assets/case_studies/principled_bayesian_workflow.html>
- Schad, D. J., Betancourt, M., & Vasishth, S. (2021). Toward a principled Bayesian workflow in cognitive science. *Psychological Methods, 26*(1), 103.
- Talts, S., Betancourt, M., Simpson, D., Vehtari, A., & Gelman, A. (2018). Validating Bayesian inference algorithms with simulation-based calibration. *arXiv preprint arXiv:1804.06788*.
- Radev, S. T., Mertens, U. K., Voss, A., Ardizzone, L., & Kothe, U. (2020). BayesFlow: Learning complex stochastic models with invertible neural networks. *IEEE Transactions on Neural Networks and Learning Systems*.
- Cranmer, K., Brehmer, J., & Louppe, G. (2020). The frontier of simulation-based inference. *Proceedings of the National Academy of Sciences, 117*(48), 30055-30062.
- Li, S., Fearnhead, P., Friel, N., Mira, A., & Robert, C. P. (2026). Amortized Bayesian Workflow. *arXiv preprint*.
