---
name: preferences-scientific-inquiry-methodology
description: >
  Philosophical and methodological framework for scientific inquiry grounded in
  Peircean pragmatism, effective theory construction, and principled iterative
  model building. Load when reasoning about scientific methodology, model
  construction and criticism, evidential standards, or the relationship between
  mechanistic understanding and statistical modeling.
---

# Scientific inquiry methodology

This skill articulates a coherent philosophical and methodological framework for scientific inquiry.
It synthesizes classical pragmatist epistemology (Peirce), the philosophy of experimental evidence (Mayo, Lakatos, Galison, Hacking, Franklin), the effective theory tradition in physics (Wells, Weinberg, Wilson), and principled probabilistic modeling workflows (Betancourt) into a unified methodology for constructing, testing, and refining scientific models.

The central commitment is that all scientific models are *effective theories* — incomplete descriptions that successfully predict phenomena within a bounded domain by systematically identifying and marginalizing over degrees of freedom irrelevant at the scale of interest.
This is not a concession but the structure of scientific knowledge itself.

## Sections

| File | Contents |
|------|----------|
| [01-foundations-pragmatism-effective-theories.md](01-foundations-pragmatism-effective-theories.md) | Peircean pragmatism, the pragmatic maxim, fallibilism, the triadic inquiry cycle, and effective theories as their formal scientific expression |
| [02-epistemology-of-evidence.md](02-epistemology-of-evidence.md) | Mayo's severity criterion, Lakatos's progressive vs degenerating research programs, Hacking's manipulation criterion, Galison's convergent diagnostics, and how these diagnose pathologies like just so stories and cargo cult science |
| [03-iterative-methodology.md](03-iterative-methodology.md) | The unified iterative pipeline synthesizing Wells' effective theory construction with Betancourt's principled Bayesian workflow, structured as Peircean inquiry made operational |
| [04-hierarchy-of-approaches.md](04-hierarchy-of-approaches.md) | Ranking of computational approaches by the strength of evidence they provide for mechanistic claims, from derived effective theories through pure pattern recognition |
| [05-pragmatics.md](05-pragmatics.md) | When to use which approach, determined by the intersection of scientific question, available data, and computational budget |

## Core principles

These principles pervade all sections and should inform any reasoning about scientific methodology:

- The meaning of a scientific concept is exhausted by its observable consequences under specified conditions (pragmatic maxim).
- All models are effective theories; the question is never "is this model true?" but "at what scale and under what conditions does this model make severe, testable predictions that survive empirical scrutiny?"
- The method of inquiry must be self-correcting: each modeling choice is testable, tests are severe, and failures drive principled expansion rather than ad hoc patching.
- Consistency (observational and mathematical) takes precedence over simplicity, elegance, or parsimony in theory construction.
- Evidence is not data; evidence is data *that could have come out differently if the hypothesis were wrong*.

## See also

- `preferences-architectural-patterns` for analogous principles applied to software systems
- `preferences-domain-modeling` for type-driven modeling that mirrors the commitment to explicit structure
- `preferences-algebraic-laws` for property-based testing as a form of severity in software
- `preferences-adaptive-planning` for how the Peircean iterative cycle is operationalized as engineering workflow (session-orient/plan/review/checkpoint), and for the MPC and VSM theoretical foundations that govern planning depth and validation gate placement
- `preferences-scalable-probabilistic-modeling-workflow` for the operational Bayesian workflow protocol for simulator-based models, extending section 03's general iterative methodology to stochastic dynamical systems with amortized inference
