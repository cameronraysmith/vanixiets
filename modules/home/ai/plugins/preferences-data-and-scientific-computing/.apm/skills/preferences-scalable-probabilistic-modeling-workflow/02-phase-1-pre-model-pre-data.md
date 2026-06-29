# Phase I: pre-model, pre-data

This phase establishes the conceptual and observational foundations before any model is specified or data is examined.
It corresponds to Stages 1-3 of the general iterative methodology in `preferences-scientific-inquiry-methodology` section 03.

## Step 1: conceptual analysis

Reason about the aspirational model.
Informally narrate the *generative process*: what are the latent dynamical variables, what governs their evolution (deterministic dynamics, stochastic forcing, external inputs), how does the measurement apparatus observe them (observation model, noise, censoring, subsampling), and what are the inferential goals?

**[D]** For stochastic dynamical systems this includes: the state space and its dimension, the nature of the dynamics (ODE, SDE, jump process, PDE, agent-based), the stochastic driving processes, boundary and initial conditions, and the temporal or spatial resolution of observations.
In subsequent iterations, expand this narrative to encompass previously unanticipated behavior.

The conceptual analysis should identify all systematic effects that could, in principle, matter.
Illustrative examples across domains:

- In epidemiology: compartmental structure, age stratification, spatial heterogeneity, reporting delays, underascertainment.
- In climate science: radiative forcing terms, ocean-atmosphere coupling, cloud parameterization, unresolved subgrid processes.
- In chemical kinetics: reaction network topology, diffusion limitations, spatial compartmentalization, catalyst deactivation.
- In population ecology: density dependence, predator-prey coupling, seasonal forcing, demographic stochasticity, environmental stochasticity.
- In molecular biology: transcriptional bursting, post-translational modification, feedback loop topology, cell-to-cell variability.
- In economics: agent heterogeneity, information asymmetry, regime switching, exogenous shocks.

The gap between the aspirational model and the current working model serves as a source of hypotheses for future expansion and guides the choice of summary statistics for diagnostic checks.

## Step 2: define observational space

Formalize the observational space $Y$: the number and type of components, their temporal or spatial structure (time series, spatial fields, event sequences), metadata, and constraints (non-negativity, integer counts, censoring bounds).

**[D]** For dynamical systems, this includes specifying the observation times $\{t_k\}$, which state variables are observed (partial vs. full observation), and the structure of observation noise.
Common observational configurations include:

- Discrete time series at regular or irregular intervals.
- Snapshot observations of a spatial field at a single time point.
- Event sequences (point processes) recording transition times.
- Aggregate statistics over populations (e.g., prevalence counts rather than individual trajectories).
- Censored or truncated observations where extreme values are clipped or below detection limits.

The observational space definition constrains which summary statistics are meaningful and which inference architectures are appropriate.

## Step 3: construct summary statistics

Design summary statistics $\hat{t}: Y \to U$ that isolate the consequences of the generative process most relevant to inferential goals and most difficult to model.

**[D]** For dynamical systems, summary statistics should be tailored to the temporal or spatial structure of the data.
Examples organized by the type of information they capture:

*Temporal structure*: autocorrelation functions, spectral power densities, peak counts, period estimates, return time distributions.

*Growth and stability*: growth rates, decay constants, Lyapunov exponents, phase-plane winding numbers.

*Regime behavior*: regime occupancy fractions, transition counts, dwell time distributions, bifurcation proximity indicators.

*Distributional summaries*: empirical quantiles of trajectory functionals, inter-event time distributions, marginal state distributions at selected time points.

*Spatial structure* (where applicable): spatial correlation functions, cluster size distributions, pattern wavelengths, anisotropy measures.

The appropriate statistics depend on the domain and the inferential question.
For oscillatory dynamics in any domain (neural circuits, cardiac rhythms, predator-prey cycles, business cycles), period and amplitude statistics are natural.
For diffusive or growth processes (tumor growth, population expansion, chemical front propagation), growth rate and saturation statistics are primary.

Pair each summary statistic with domain-expertise-informed thresholds for prior predictive and posterior retrodictive checks.
These thresholds capture the boundary between what domain experts consider plausible and what would provoke concern, not sharp classifications.
