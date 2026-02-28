---
name: preferences-adaptive-planning
description: >
  Adaptive planning and control theory foundations for AI agent engineering,
  including MPC receding-horizon planning, Viable System Model mapping, queue
  economics, Cynefin domain classification, and stigmergic coordination.
  Load when reasoning about planning depth optimization, buffer sizing,
  validation gate placement, replanning triggers, or understanding why session
  workflow skills work the way they do.
---

# Adaptive planning and control theory for AI agent engineering

This skill defines the problem space, theoretical foundations, and operational framework for co-optimizing planning, implementation, validation, and iteration cycles when using AI coding agents (Claude Code, etc.) with DAG-based issue trackers (Beads, etc.) to achieve maximal forward progress with minimal waste.

## Problem statement

We seek to maximize the rate of *validated, releasable product increments* produced by AI coding agents operating over a dependency-aware work graph, subject to three coupled constraints:

1. Planning accuracy degrades with depth: the further ahead we plan, the more errors accumulate in the plan, leading to wasted implementation effort.
2. Implementation throughput is bounded by plan availability: agents can only consume work as fast as valid, atomic, dependency-resolved plans are produced.
3. Unvalidated work is inventory, not progress: implemented but unvalidated work carries risk of rework and may constitute negative progress if it must be discarded.

The optimization target is the *net progress rate*: the rate of validated, correct work items produced.
A planning cycle at depth $d$ produces $d$ work items with accuracy $\alpha(d)$ (fraction surviving validation), taking time $T_{\text{plan}}(d)$ plus fixed replanning overhead $T_{\text{replan}}$.
The effective planning rate is:

$$R_{\text{plan}}(d) = \frac{d \cdot [\alpha(d)(1 + r) - r]}{T_{\text{plan}}(d) + T_{\text{replan}}}$$

where $r$ is the rework cost ratio (effort to discard and replan an invalid item, relative to implementing a valid one).
The net progress rate is $\text{NPR}(d) = \min(k,\; R_{\text{plan}}(d))$, bounded by agent implementation capacity $k$ (items/cycle).

Under standard assumptions — exponential accuracy decay $\alpha(d) = e^{-\lambda d}$ and superlinear planning cost $T_{\text{plan}}(d) = c \cdot d^\beta$ with $\beta > 1$ — $R_{\text{plan}}$ has an interior maximum at finite $d^*$: the depth where marginal yield from one additional planning step is exactly offset by marginal accuracy loss and planning cost.
When agent capacity exceeds optimal plan throughput ($k > R_{\text{plan}}(d^*)$), the effective depth must decrease below $d^*$ to sustain throughput.
Thus $d^*_{\text{eff}}$ *decreases* as $k$ increases — more agents demand shallower, faster planning cycles.

> TODO: Validate the $R_{\text{plan}}(d)$ formulation, functional form assumptions ($\alpha(d) = e^{-\lambda d}$, $T_{\text{plan}}(d) = c \cdot d^\beta$), and the MPC co-optimization statement (section 1 below) against Grune & Pannek (2017) Ch. 5 performance bounds and Rawlings, Mayne & Diehl (2017) Ch. 1-2 finite-horizon formulation.

## Theoretical foundations

### 1. Model Predictive Control (MPC)

- *Core idea*: plan over a finite prediction horizon $N_p$, commit only over a shorter control horizon $N_c \leq N_p$, then re-observe actual state and replan from scratch.
- *Mapping*: $N_p$ = planning depth (DAG decomposition lookahead), $N_c$ = commitment horizon (work assigned to agents before next replan), state = codebase + remaining spec, model mismatch = planning inaccuracy.
- *Key result*: optimal prediction horizon is finite and determinable — the point where marginal value of additional planning equals marginal cost of plan inaccuracy.
- *Co-optimization formulation*: the joint selection of prediction horizon $d$ and process parameters (validation frequency, batch sizing) maps to the MPC design problem: minimize $\sum_{\tau=0}^{d} \ell(x_\tau, u_\tau) + V_f(x_d) + C_{\text{plan}}(d)$ subject to dynamics $x_{\tau+1} = f(x_\tau, u_\tau)$, where $\ell$ is per-step cost, $V_f$ is terminal cost (value of work beyond the horizon), and $C_{\text{plan}}(d)$ captures planning cost at depth $d$. The receding-horizon principle commits only to the first $N_c \leq d$ steps, then replans from observed state. Near-optimality guarantees as a function of horizon length follow from controllability-based performance bounds (Grune & Pannek, 2017, Ch. 5).
- *References*: Camacho & Bordons, *Model Predictive Control*; Rawlings, Mayne & Diehl, *Model Predictive Control: Theory, Computation, and Design*.

### 2. Organizational cybernetics and the Viable System Model (VSM)

- *Core idea*: viable organizations exhibit a recursive five-system structure with distinct planning horizons and update frequencies at each level.
- *Mapping*: System 1 = implementation (agents executing atomic work items), System 2 = coordination (DAG dependency resolution, `bd ready`), System 3 = operational control (resource allocation, replanning triggers), System 3* = audit/validation (integration testing gates), System 4 = strategic planning (specification evolution, environmental scanning), System 5 = identity/policy (product vision, quality standards).
- *Key result*: Ashby's Law of Requisite Variety — the planning/control system must have at least as much variety as the system being controlled. Plans that are too coarse underspecify; plans that are too detailed are fragile.
- *References*: Beer, *Brain of the Firm*; Beer, *The Heart of Enterprise*; Beer, *Diagnosing the System for Organizations*; Ashby, *An Introduction to Cybernetics*.

### 3. Production flow and queue economics

- *Core idea*: product development is governed by queue dynamics where work-in-progress (WIP) is economic inventory with carrying costs.
- *Key results*:
  - Little's Law: $L = \lambda W$ — average WIP = arrival rate x average cycle time. Controls buffer sizing between planning and implementation.
  - Optimal batch size: U-shaped cost curve. Transaction costs (planning/validation overhead per item) vs. holding costs (staleness, integration risk). Optimal size shifts smaller as implementation cost decreases (AI agents).
  - Utilization trap: cycle time follows $M/M/1$ queueing curve — approaches infinity as utilization approaches 100%. Optimal agent utilization is 70-85%, not 100%.
  - Cost of delay: the economic framework for prioritization within the DAG. Weighted Shortest Job First (WSJF) as the priority function.
- *References*: Reinertsen, *The Principles of Product Development Flow*; Goldratt, *The Goal*; Hopp & Spearman, *Factory Physics*.

### 4. Cone of uncertainty and planning accuracy

- *Core idea*: estimation accuracy improves hyperbolically as specification detail increases. At inception: +/-4x. After detailed design: +/-1.25x.
- *Implication*: plan at multiple resolutions simultaneously. Coarse plans are cheap and give strategic shape. Fine plans are expensive but executable. Only invest in fine-grained planning for the near-term operational window.
- *References*: McConnell, *Software Estimation: Demystifying the Black Art*; Boehm, *Software Engineering Economics* (cost-of-change curves).

### 5. Verification and validation (V&V)

- *Verification* ("built the thing right"): per-node check — does implementation match the plan for that specific work item? Automatable via type checking, tests, CI.
- *Validation* ("built the right thing"): integration-point check — does the assembled system satisfy the higher-level requirement? Requires evaluation against the specification, not just the local plan.
- *Key result* (Boehm curve): cost of defect correction grows monotonically (often cited as exponentially) with the distance between injection and detection. Validation frequency should be calibrated to minimize total expected defect cost, not minimized for convenience.
- *References*: Boehm, *Software Engineering Economics*; IEEE 1012 (V&V standard); VDI 2206 (V-model for systems engineering).

### 6. Complex adaptive systems and domain classification

- *Cynefin framework* (Snowden): classify work items by the knowability of cause-effect relationships.
  - Clear: deterministic, plan fully, execute. (Boilerplate, standard patterns.)
  - Complicated: analyzable, plan with expertise, verify. (Architecture decisions, algorithms.)
  - Complex: emergent, probe-sense-respond. Plan only as experiments. (Novel features, UX, emergent behaviors.)
  - Chaotic: act-sense-respond. Stabilize first. (Production incidents.)
- *Implication*: planning depth should vary by node in the DAG based on its Cynefin domain. Front-load complex-domain probes to resolve uncertainty early; plan clear-domain work far ahead.
- *Real options theory*: a plan for a complex-domain item is an option (right but not obligation to implement). Defer exercise until uncertainty resolves. Value of the option increases with uncertainty and decreases with time.
- *References*: Snowden & Boone, "A Leader's Framework for Decision Making" (HBR, 2007); Denne & Cleland-Huang, *Software by Numbers: Low-Risk, High-Return Development*.

### 7. Stigmergy and decentralized coordination

- *Core idea*: agents coordinate through shared environmental state (the DAG) rather than direct communication. Local rules (pick highest-priority unblocked work) produce globally near-optimal behavior.
- *Mapping*: the issue DAG is the pheromone field. `bd ready` / `bd claim` are the local sensing/acting operations. Completion events are environmental modifications that update the field for other agents.
- *Key result*: stigmergic systems achieve near-optimal throughput under high agent count, limited individual knowledge, and dynamic environments.
- *References*: Theraulaz & Bonabeau, "A Brief History of Stigmergy" (Artificial Life, 1999); Dorigo & Stutzle, *Ant Colony Optimization*.

### 8. DAGs as algebraic structures

- *Core idea*: dependency graphs of work items are algebraic objects (partial orders, lattices) amenable to formal analysis — critical path computation, parallel front identification, incremental replanning.
- *Key constructs*:
  - Topological sort: determines valid execution orderings.
  - Anti-chains: maximal sets of mutually independent nodes = parallelizable work fronts.
  - Critical path: longest weighted path = minimum project duration. Determines where slack exists.
  - Graph homomorphisms: structural mappings between specification DAGs and implementation DAGs = traceability.
  - Incremental recomputation: when a spec node changes, the minimal subgraph requiring replanning is determinable (cf. build systems a la carte — Mokhov, Mitchell, Peyton Jones).
- *References*: Mokhov, *Algebraic Graphs with Class* (Haskell Symposium, 2017); Mokhov, Mitchell & Peyton Jones, "Build Systems a la Carte" (ICFP, 2018); Davey & Priestley, *Introduction to Lattices and Order*.

## Operational framework

### Multi-resolution rolling wave planning

| Horizon | Scope | Granularity | Accuracy target | Update trigger |
|---------|-------|-------------|-----------------|----------------|
| Strategic | Full remaining scope | Epics, major milestones | +/-4x | Spec change, major milestone completion |
| Tactical | Next 1-2 milestones | Features, interface contracts | +/-1.5x | Each replanning cycle |
| Operational | Implementation buffer | Atomic issues with acceptance criteria | >90% survival rate | After each validation gate |

### Planning-implementation pipeline

1. *Elaborate*: decompose tactical plan into atomic operational DAG nodes with explicit dependencies, acceptance criteria, and Cynefin classification.
2. *Verify the plan*: review DAG for completeness (all spec requirements trace to at least one node), consistency (no contradictory acceptance criteria), and feasibility (no impossible dependency orderings). Detect cycles. Compute critical path. Identify parallel fronts.
3. *Execute*: agents consume via `bd ready` then `bd claim` then implement then local verification (tests pass, types check) then `bd close`.
4. *Validate*: at DAG integration points (high in-degree convergence nodes), validate assembled subsystem against spec-level requirements. This is the System 3* audit function.
5. *Replan*: triggered by (a) validation gate completion, (b) spec change, or (c) accumulated information gain exceeding threshold (implementation revealed blocking surprise). Update operational DAG, potentially revise tactical plan.

### Buffer sizing heuristic

$$B^* \approx \frac{k}{p} \cdot (1 + \text{CV}_p)$$

where $k$ = agent throughput (items/cycle), $p = R_{\text{plan}}(d)$ = effective planning rate at the chosen depth (items/cycle), and $\text{CV}_p$ = coefficient of variation of planning throughput.
Keep the operational buffer at $B^*$ items — enough to absorb planning variability without starving agents, small enough to limit inventory carrying costs (plan staleness).

### Validation gate placement

Place validation gates at topological convergence points in the DAG — nodes where multiple independent implementation chains merge.
These are natural integration boundaries where architectural assumptions face reality.
The interval between gates should satisfy:

$$\text{Expected rework cost between gates} < \text{Validation overhead per gate}$$

This means more frequent gates when planning accuracy is lower (early project, complex domain) and less frequent when accuracy is high (clear domain, late project).

### Replanning decision rule

Replan the operational DAG when:

$$\sum_{\text{completed nodes}} I_{\text{surprise}}(n) > \theta$$

where $I_{\text{surprise}}(n)$ measures the information gain from node $n$'s implementation (deviation from plan assumptions) and $\theta$ is the replanning threshold.
Low $\theta$ = frequent replanning (high overhead, high accuracy).
High $\theta$ = infrequent replanning (low overhead, risk of drift).
Calibrate empirically; start with replanning after every validation gate.

*Refinement: scaled threshold for fan-in normalization.*
The flat threshold $\theta$ creates fan-in sensitivity at convergence points: a node with many completed dependencies accumulates surprise from each, potentially triggering replanning even when per-dependency surprise is low.
The operational refinement scales the threshold as $\theta \cdot N$, where $N$ is the number of dependencies at the convergence point, so the trigger condition becomes "average per-dependency surprise exceeds $\theta$" rather than "total surprise exceeds $\theta$."
This addresses the practical concern without abandoning the theoretical principle.
Compound integration risk at high-fan-in nodes — the legitimate concern that motivates evaluating convergence points — is better assessed by integration-level verification (the System 3* audit at validation gates) than by a threshold that fires on aggregate quantity alone.

## Tooling architecture

### DAG-native issue tracking (Beads)

- *Role*: reified execution plan — the dependency graph is the source of truth for what work exists, what's blocked, what's ready, and what's done.
- *Key operations*: `bd ready` (anti-chain query), `bd claim` (atomic assignment), `bd tree` (dependency visualization), `bd close` (completion + unblock dependents).
- *Integration pattern*: specification documents then (planning process) then Beads DAG then (agent execution) then implementation artifacts then (validation) then releasable increment.
- Beads is a materialized view of the plan, not the plan itself. The authoritative specification lives in design documents, ADRs, or formal specs. Issues are derived from and traced back to these.

### Claude Code agent skills and hooks

- *Skills*: encapsulated, reusable capabilities with documented interfaces. Each skill should map to a well-understood domain operation (file creation, testing, deployment, etc.) with clear pre/postconditions.
- *Hooks*: event-driven triggers that enforce workflow invariants (e.g., pre-commit validation, post-implementation test execution, DAG state updates after task completion).
- *Design principle*: skills and hooks should enforce the V&V structure — making it impossible for an agent to mark work complete without passing verification, and triggering validation automatically at integration points.

### The agent execution loop

```
while project.has_remaining_work():
    # 1. Sense: query DAG for ready work
    task = bd_ready(priority="highest")
    if task is None:
        signal_planning_bottleneck()  # pipeline starvation
        wait()
        continue

    # 2. Claim: atomic assignment
    bd_claim(task)

    # 3. Act: implement with local verification
    result = implement(task)
    assert passes_acceptance_criteria(task, result)
    assert passes_type_checks(result)
    assert passes_tests(result)

    # 4. Complete: update DAG, unblock dependents
    bd_close(task)

    # 5. Validate: if this node is a validation gate
    if is_convergence_point(task):
        validate_against_spec(task.integration_scope)
        if validation_fails():
            trigger_replan(task.subgraph)
```

## Key quantities to monitor and optimize

| Metric | What it measures | Target regime |
|--------|-----------------|---------------|
| Plan survival rate | % of planned work items that pass validation without rework | >90% (if lower, plan accuracy is insufficient) |
| Buffer depth | Number of ready (unblocked, unassigned) work items | $B^*$ +/- 20% (starving if below, stale if above) |
| Agent utilization | % of agent capacity actively implementing | 70-85% (higher leads to queueing instability) |
| Cycle time | Time from task claim to task close | Trending down or stable (increasing suggests growing complexity or bad plans) |
| Rework ratio | % of completed work requiring revision after validation | <10% (higher suggests planning or V&V failure) |
| Critical path length | Longest dependency chain in operational DAG | Monitored for bottleneck identification |
| Planning throughput | Validated plan items produced per cycle | Must exceed agent consumption rate |
| Validation gate pass rate | % of integration points passing on first attempt | Trending up (decreasing suggests systemic planning error) |

## Cross-domain applicability

The MPC receding-horizon structure, Cynefin classification, and surprise-driven replanning described in this skill are instances of Peircean self-correcting inquiry: abduction (form hypothesis about what work is needed and how to decompose it), deduction (derive predictions about implementation outcomes from the plan), induction (test predictions against validation results), then repeat from revised state.

This structural isomorphism spans three domains:

- Engineering workflow: plan / implement / validate / replan
- Scientific inquiry: hypothesize / predict / test / revise
- Bayesian modeling: prior-model / simulate / posterior-check / expand

The correspondence is not metaphorical.
Each domain instantiates the same abstract iterative structure with domain-specific content filling the slots.
The MPC formulation in section 1 provides the control-theoretic grounding; the Peircean triadic cycle provides the epistemological grounding; the Bayesian workflow provides the statistical grounding.

Cynefin classification of work items should be informed by domain-specific methodology rather than applied generically.
For scientific modeling projects, the effective theory scope (what degrees of freedom are being modeled vs. marginalized) and the Bayesian workflow phase (prior predictive checking, simulation-based calibration, posterior diagnostics) determine whether work is clear, complicated, or complex.
For software engineering, architectural pattern maturity and framework stability are the primary determinants.
The same work item may occupy different Cynefin domains depending on the practitioner's domain expertise and the project's epistemic state.

See `preferences-scientific-inquiry-methodology` for the epistemological foundations (Peircean pragmatism, Mayo's severity criterion, effective theory tradition) that this framework operationalizes for engineering workflow.
See `preferences-scalable-probabilistic-modeling-workflow` for the operational Bayesian workflow protocol for simulator-based models, the statistical instantiation of the same iterative self-correcting structure.

## Research threads for deeper investigation

- Algebraic graph theory for incremental DAG replanning: Mokhov's algebraic graphs formalism applied to work breakdown structures. Can we compute minimal replanning subgraphs?
- MPC theory for planning horizon optimization: the $R_{\text{plan}}(d)$ formulation provides $d^*$ under exponential accuracy decay and superlinear planning cost. Remaining work: validate functional forms $\alpha(d) = e^{-\lambda d}$ and $T_{\text{plan}}(d) = c \cdot d^\beta$ against empirical planning data; derive closed-form $d^*$ for specific $(\lambda, c, \beta, r)$ regimes; extend to stochastic formulations where accuracy and planning cost have known distributions.
- Multi-agent stigmergic scheduling: theoretical throughput bounds for $n$ agents operating over a shared DAG with stochastic task durations.
- Real options valuation for complex-domain planning: when should a probe be scheduled vs. deferred? Connection to Black-Scholes analogues for irreversible planning decisions.
- Requisite variety in specification languages: what level of formality in specifications (natural language to structured templates to formal methods) provides optimal variety matching for different project domains?
- Event sourcing as planning audit trail: using CQRS/event sourcing patterns to maintain full history of planning decisions, enabling retrospective analysis of planning accuracy and replanning triggers.
- Viable System Model instantiation for AI agent teams: concrete mapping of Beer's VSM recursion levels to agent team architecture, with specific protocols for each system.

## Canonical references

### Control theory and optimization

- Camacho, E.F. & Bordons, C. — *Model Predictive Control* (Springer)
- Rawlings, J.B., Mayne, D.Q. & Diehl, M. — *Model Predictive Control: Theory, Computation, and Design* (2nd ed., 2017)
- Grune, L. & Pannek, J. — *Nonlinear Model Predictive Control: Theory and Algorithms* (Springer, 2nd ed., 2017)
- Mayne, D.Q. — "Model predictive control: Recent developments and future promise" (Automatica, vol. 50, no. 12, 2014)

### Organizational cybernetics

- Beer, S. — *Brain of the Firm* (Wiley, 1972)
- Beer, S. — *The Heart of Enterprise* (Wiley, 1979)
- Beer, S. — *Diagnosing the System for Organizations* (Wiley, 1985)
- Ashby, W.R. — *An Introduction to Cybernetics* (Chapman & Hall, 1956)

### Production flow and queue economics

- Reinertsen, D.G. — *The Principles of Product Development Flow* (Celeritas, 2009)
- Goldratt, E.M. — *The Goal* (North River Press, 1984)
- Hopp, W.J. & Spearman, M.L. — *Factory Physics* (Waveland Press)

### Software engineering economics

- Boehm, B. — *Software Engineering Economics* (Prentice Hall, 1981)
- McConnell, S. — *Software Estimation: Demystifying the Black Art* (Microsoft Press, 2006)
- Denne, M. & Cleland-Huang, J. — *Software by Numbers* (Prentice Hall, 2003)

### Complex systems and decision frameworks

- Snowden, D.J. & Boone, M.E. — "A Leader's Framework for Decision Making" (HBR, 2007)
- Stacey, R.D. — *Strategic Management and Organisational Dynamics* (Pearson)

### Algebraic graphs and build systems

- Mokhov, A. — "Algebraic Graphs with Class" (Haskell Symposium, 2017)
- Mokhov, A., Mitchell, N. & Peyton Jones, S. — "Build Systems a la Carte" (ICFP, 2018)

### Multi-agent coordination

- Theraulaz, G. & Bonabeau, E. — "A Brief History of Stigmergy" (Artificial Life, 1999)
- Dorigo, M. & Stutzle, T. — *Ant Colony Optimization* (MIT Press, 2004)

### DAG-native issue tracking

- Yegge, S. — Beads: https://github.com/steveyegge/beads
- git-bug: https://github.com/git-bug/git-bug
- beads_viewer (Dicklesworthstone): https://github.com/Dicklesworthstone/beads_viewer

## See also

- `preferences-scientific-inquiry-methodology` for Peircean pragmatism, severity criterion, and effective theory epistemology that this framework operationalizes for engineering workflow
- `preferences-scalable-probabilistic-modeling-workflow` for the principled Bayesian workflow for simulator-based models, the statistical instantiation of the same iterative self-correcting structure
- `preferences-architectural-patterns` for software-specific domain knowledge that informs Cynefin classification of engineering work items
