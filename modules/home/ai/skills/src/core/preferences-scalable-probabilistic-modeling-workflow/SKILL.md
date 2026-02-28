---
name: preferences-scalable-probabilistic-modeling-workflow
description: >
  Principled Bayesian workflow for simulation-based inference on stochastic
  dynamical systems, extending Betancourt's iterative methodology with
  adaptations for implicit likelihoods and amortized neural posterior
  approximation. Load when doing simulation-based inference, stochastic
  dynamical systems modeling, amortized inference architecture design,
  or principled Bayesian workflow planning.
---

# Scalable probabilistic modeling workflow

This skill provides the operational protocol for principled Bayesian inference when the model is a stochastic dynamical system and the likelihood is defined implicitly through a simulator.
It extends Betancourt (2020)'s principled Bayesian workflow with two adaptation dimensions: **[D]** for stochastic dynamical systems and **[A]** for amortized (simulation-based, likelihood-free) inference.
The workflow applies to any domain where a forward simulator defines the generative model and the likelihood is intractable: gene regulatory networks, climate models, population dynamics, epidemiological compartmental models, economic agent-based models, chemical kinetics, and beyond.

## Relationship to scientific inquiry methodology

This skill is the operational instantiation of the general iterative methodology described in `preferences-scientific-inquiry-methodology` section 03.
Where that skill provides the epistemological framework (Peircean pragmatism, Mayo's severity criterion, the effective theory tradition), this skill provides the concrete workflow steps for a specific methodological niche: simulator-based models with neural posterior approximation.

The scientific inquiry methodology's 7-stage pipeline maps to the three phases here.
Stages 1-3 (aspirational context, simplest consistent model, domain expertise consistency) correspond to Phase I (pre-model, pre-data).
Stages 4-5 (computational faithfulness, inferential adequacy) correspond to Phase II (post-model, pre-data), specifically steps 4-11a.
Stages 6-7 (model adequacy through retrodiction, expansion and iteration) correspond to Phase III (post-model, post-data) together with the iteration logic.

The epistemological commitments carry over unchanged: every modeling choice is testable, tests are severe, failures drive principled expansion, and the method's reliability lies in the self-correcting process rather than any particular model it produces.

## Sections

| File | Contents |
|------|----------|
| [01-foundations-and-framework.md](01-foundations-and-framework.md) | Bayesian model with implicit likelihood, the amortized inference paradigm, the four guiding questions, summary functions and statistics |
| [02-phase-1-pre-model-pre-data.md](02-phase-1-pre-model-pre-data.md) | Steps 1-3: conceptual analysis, observational space definition, summary statistic construction |
| [03-phase-2-post-model-pre-data.md](03-phase-2-post-model-pre-data.md) | Steps 4-11a: model development, simulator fidelity, ensemble simulation, prior checks, approximation architecture, training, algorithmic calibration, inferential calibration, amortization scope validation |
| [04-phase-3-post-model-post-data.md](04-phase-3-post-model-post-data.md) | Steps 12-15: fitting observation, posterior fit diagnostics including OOD detection, posterior retrodictive checks, celebration |
| [05-iteration-logic-and-failure-modes.md](05-iteration-logic-and-failure-modes.md) | Failure mode to return-to-step mapping, model change invalidation rules, iteration strategy |

## Core principles

- The likelihood is defined by the simulator, not by a closed-form expression.
  The model exists as a forward simulation pipeline: draw parameters, solve dynamics, apply observation model.
- Amortized inference invests computation once (training a neural approximator on simulated data) and amortizes the cost across observations.
  Inference on new data is then a single forward pass.
- The scientific content is entirely in the generative model; the inference network is a computational tool.
  Changing the model invalidates the approximator.
- Every modeling choice is testable through the diagnostic workflow; failures at any step drive principled return to the appropriate earlier step.
- There is no free lunch in amortization: changing the model invalidates the simulation ensemble and the trained approximator, both of which are coupled to a specific generative model.
- Summary statistics should be informed by the dynamics of the system under study, not chosen for computational convenience.
  For temporal systems, this means autocorrelation, spectral density, trajectory envelopes, and regime occupancy; for spatial systems, correlation functions, cluster statistics, and field summaries appropriate to the domain.
- Both the model and the approximator are provisional.
  The workflow does not yield a correct model, only one that meets the needs of the given inferential task within the bounds of validated approximation quality.

## See also

- `preferences-scientific-inquiry-methodology` for the epistemological foundations, severity criterion, and the general iterative pipeline this skill operationalizes
- `preferences-adaptive-planning` for how the same iterative self-correcting structure governs engineering workflow, and for the Cynefin-Bayesian workflow phase mapping
- `preferences-architectural-patterns` for analogous principles applied to software systems
