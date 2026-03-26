---
name: session-review
description: Operational-to-tactical feedback skill that verifies assembled subsystems at topological convergence points in the DAG, functioning as the System 3* audit from the Viable System Model.
---
# Session review

Symlink location: `~/.claude/skills/session-review/SKILL.md`
Slash command: `/session-review`

Session review protocol that verifies assembled subsystems at topological convergence points in the issue DAG, where multiple independent implementation chains merge.
This skill operates at the operational-to-tactical feedback boundary, validating that independently completed work integrates correctly and measuring accumulated surprise to determine whether replanning is needed.
It implements the System 3* audit function from the Viable System Model.

This skill is distinct from the per-issue self-verification gate defined in `/stigmergic-convention`.
The self-verification gate runs at issue granularity as part of `bd close`, verifying that a single issue's acceptance criteria are met.
Session review runs at convergence-point granularity, verifying that multiple closed issues integrate correctly as a subsystem.
Workers do not invoke `/session-review` for every issue close; they invoke it when a convergence node becomes ready because all its blocking dependencies are closed.

This is the default review command for repositories with the full stigmergic workflow installed.
For repositories without the full workflow (no session-layer skills, small utility repos, quick fixes), the self-verification gate in `/stigmergic-convention` provides the only review mechanism.

## Theoretical grounding

This skill is one component of a lifecycle that co-optimizes planning time against execution time.
The underlying model: planning depth has an optimal finite value where marginal yield from one additional planned step equals marginal accuracy loss and planning cost.
This optimum *decreases* as agent execution capacity increases — more agents demand shallower, faster planning cycles to avoid starving them on stale plans.
Model Predictive Control provides the structural answer: plan over a finite prediction horizon, commit only to a shorter control horizon of items dispatched to agents, then re-observe actual codebase state and replan from scratch.
Cynefin domain classification makes planning depth per-item rather than global: clear-domain work (known patterns) is planned far ahead at low cost, while complex-domain work (emergent behavior) is planned only as probes whose outcomes inform the next cycle.
The Viable System Model maps this to an organizational lifecycle where each session skill implements a specific regulatory function: System 4 (orient), System 3 (plan), System 1 (implement), System 3* (review), System 5 (checkpoint).
Stigmergic coordination binds it together — agents orient by reading structured signal tables on the issue DAG rather than receiving centralized briefings, achieving near-optimal throughput via local sensing and acting.
Queue economics calibrates the pipeline: buffer sizing via Little's Law, agent utilization at 70-85% (not 100%, due to queueing instability), and batch sizing via the U-curve between planning overhead and plan staleness.

This skill implements System 3*: the audit and monitoring function that closes the feedback loop.
It runs at topological convergence points in the DAG where multiple independent implementation chains merge, verifying integration correctness and measuring accumulated surprise against the replanning threshold theta (scaled by Cynefin domain).
When surprise exceeds theta, the plan has diverged enough from reality to warrant replanning.
This is the MPC "re-observe actual state" step — without it, the system operates open-loop and plan accuracy degrades unboundedly.

This lifecycle is subject to its own standards.
When patterns suggest the framework itself is producing poor outcomes — systematic surprise across multiple issues, recurring ambiguity in acceptance criteria, Cynefin classifications that consistently shift during implementation, validation that stalls because infrastructure doesn't support the prescribed methodology, or requirements that decompose cleanly but don't compose into a working system — the agent's obligation is to pause execution and surface the observation rather than pressing on within a framework it perceives as inadequate.
The plan is a tool for achieving outcomes; when the tool is counterproductive, the agent's duty is to say so.
See `preferences-validation-assurance` for the full set of double-loop learning triggers and the reflexive severity framework.

For the full theoretical derivation including the R_plan(d) formulation, buffer sizing heuristic, and validation gate placement theory, see `preferences-adaptive-planning`.

## Composed skills

This skill orchestrates a higher-level protocol that uses the following skills as components.
Do not duplicate their functionality; delegate to them.

- `/stigmergic-convention` provides the self-verification gate protocol, signal table schema, field definitions, and the read-modify-write protocol for reading surprise scores from closed dependencies and writing updated signals on the convergence node.
- `/issues-beads-evolve` creates rework issues when integration verification fails or accumulated surprise exceeds the replanning threshold.

Load `/issues-beads-prime` for core beads conventions and command quick reference before running review commands.

## Validation gate frequency

Validation gate placement follows the principle that expected rework cost between gates should be less than validation overhead per gate.
Cynefin classification modulates gate frequency:

- *Clear* domain: less frequent review; run acceptance criteria automatically at convergence points.
  Low surprise is expected, so validation overhead should be kept minimal.
- *Complicated* domain: standard frequency; verify integration against architecture at each convergence point.
- *Complex* domain: more frequent review; evaluate emergence against original intent at each convergence point and consider intermediate reviews when surprise scores on closed children are high.
- *Chaotic* domain: rapid review after each stabilizing intervention; assess whether the intervention achieved stabilization before planning further work.

## Protocol

Execute the following steps in order.

### Step 1: identify convergence point

A convergence point is a node in the issue DAG whose blocking dependencies are all closed.
Nodes with high in-degree (many blocking dependencies) are the primary targets for review because they represent integration points where multiple independent work streams merge.

Identify candidate convergence points:

```bash
bd status
bd dep tree <epic-id> --direction both
```

Examine the dependency tree for nodes where all blockers are closed.
Prioritize nodes with the highest in-degree, as these represent the most significant integration boundaries.

A convergence node that is itself an epic containing child issues represents a subsystem-level integration point.
A convergence node that is a leaf task with multiple blockers represents a narrower interface integration point.
Both warrant review, but epic-level convergence points typically require more thorough integration verification.

### Step 2: assemble pheromone trails from closed dependencies

Read closure reasons and checkpoint context from all closed dependencies of the convergence node.
This is pheromone trail assembly: the closure reasons from each dependency describe what was delivered and how it was validated, while checkpoint contexts describe what was learned during implementation.

```bash
# For each closed dependency of the convergence node
bd show <dependency-id> --json | jq -r '.[0] | {close_reason, notes}'
```

For each closed dependency, extract:

- The *closure reason* from `close_reason`, which answers "what exists now that did not before?" and "how do I know it works?"
- The *checkpoint context* from the `<!-- checkpoint-context -->` section in the notes field, which describes state estimates and discoveries made during implementation.
- The *surprise score* from the signal table in the notes field, which quantifies plan-versus-reality divergence experienced during that issue's implementation.
- The *confidence level* and *evidence-freshness* from the signal table, which indicate how strong the supporting evidence is and when it was last produced.

Assemble these trails in topological order (respecting the dependency structure) to build a coherent picture of the integration context.
Pay attention to cases where one dependency's closure reason references interfaces, contracts, or assumptions that another dependency should have satisfied.
Mismatches between these references are candidates for integration failures.

When closed dependencies show low confidence relative to their role (e.g., `prototype` or `undemonstrated` on implementation work), flag this as a confidence gap in the integration context.
Integration verification at a convergence point inherits the weakest link: if a dependency's claim is poorly supported, the integration claim built on it is also poorly supported.

### Step 3: execute integration-level verification

Integration verification goes beyond individual issue self-verification.
It tests that the assembled subsystems work together, not just that each part passes its own acceptance criteria independently.

The convergence node's acceptance criteria define the integration tests.
Read the convergence node's acceptance criteria:

```bash
bd show <convergence-id> --json | jq -r '.[0].acceptance_criteria // ""'
```

Execute each verification command specified in the acceptance criteria.
These commands should exercise the interfaces between the subsystems assembled by the closed dependencies.

When the convergence node lacks explicit acceptance criteria, derive integration verification from the closure reasons of its dependencies.
Identify the interfaces between the delivered subsystems and construct verification that exercises those interfaces together.

Cynefin modulates the rigor of integration verification:

- *Clear*: automated; run the acceptance criteria verification commands and confirm pass/fail.
- *Complicated*: expert; verify against architecture documentation and interface contracts, checking that the assembled subsystems satisfy the architectural intent.
- *Complex*: adaptive; evaluate whether the emergent behavior of the assembled subsystems aligns with the original intent, even if the specific implementation diverged from the plan.
- *Chaotic*: rapid; confirm that the stabilizing intervention achieved its immediate goal before investing in deeper verification.

After running verification, assess severity: would these tests have failed under the most plausible alternative implementations that do not satisfy the requirement?
A test that always passes regardless of implementation has zero severity and provides no evidence.
When verification passes but severity is low (the tests check syntax rather than semantics, verify happy paths but miss edge cases, or test mocks rather than real integrations), flag the acceptance criteria as insufficient.
Either create a rework issue for stronger tests or note the severity gap in the checkpoint handoff for the next session to address.
See `preferences-validation-assurance` for the full severity criterion and evidence quality dimensions.

### Step 4: assess accumulated surprise

Sum the surprise scores from all closed dependencies of the convergence node.
Compare the accumulated surprise against the replanning threshold theta.

```bash
# For each closed dependency, extract surprise from its signal table
bd show <dependency-id> --json | jq -r '.[0].notes // ""'
# Parse the signal table between <!-- stigmergic-signals --> delimiters
# Extract the surprise value
```

The replanning threshold theta is context-dependent.
Complex-domain convergence points have a lower per-dependency threshold because surprise in complex domains has higher downstream impact: a small deviation in a complex subsystem can cascade unpredictably.
Clear-domain convergence points tolerate higher accumulated surprise because deviations in clear domains tend to be bounded and predictable.

As a starting heuristic:
- *Clear* domain: theta = 0.5 per dependency (high tolerance; clear-domain surprise is usually bounded).
- *Complicated* domain: theta = 0.3 per dependency (moderate tolerance).
- *Complex* domain: theta = 0.2 per dependency (low tolerance; complex-domain surprise cascades).
- *Chaotic* domain: theta = 0.1 per dependency (very low tolerance; any surprise in a stabilization context warrants reassessment).

Compute accumulated surprise as the sum of surprise scores across all closed dependencies.
If accumulated surprise exceeds (theta * number of dependencies), flag for replanning.

### Step 5: handle verification results

Verification produces one of two outcomes.

#### Verification passes and surprise is within threshold

Produce a verification report summarizing:
- Which convergence node was reviewed
- How many closed dependencies were assembled
- What integration verification was performed and its results
- The accumulated surprise score and its relationship to theta

Update the convergence node's signal table via the read-modify-write protocol from `/stigmergic-convention`:
- Set progress to *verifying* during review, then to *implementing* or the appropriate next state after review completes.
- Record the accumulated surprise on the convergence node itself (as a synthesized value reflecting its children's experience).

Close the convergence node with a closure reason that includes the integration verification results:

```bash
bd close <convergence-id> --reason "Integration verified: [summary of what was assembled and how it was verified]. Accumulated surprise: [score]/[theta threshold]. All [N] dependencies integrated successfully."
```

The closure reason on a convergence node is a high-value pheromone trail because downstream nodes inherit this integration context.
Make it specific about what was verified and what the assembled subsystem can now do.

Update the convergence node's confidence signals:
- Promote `confidence` based on what the verification actually demonstrated. Integration-level verification with severe tests warrants `integration-verified`. End-to-end verification against the specification warrants `validated`. Promotion requires that the evidence is fresh and severe — passing tests that lack severity does not warrant promotion.
- Set `evidence-freshness` to today's date when fresh evidence was produced.
- Record `regression-guard` if the verification is automated and will run on future changes (CI-enforced tests warrant `automated`; manual verification procedures warrant `manual`).

#### Verification fails or surprise exceeds threshold

When integration verification fails or accumulated surprise exceeds theta, the existing plan has diverged from reality and corrective action is needed.

Create rework issues via `/issues-beads-evolve` to address integration failures.
Each rework issue should describe the specific failure, reference the convergence node and the relevant closed dependencies, and include acceptance criteria that would resolve the failure.

Update signal tables on affected issues via the read-modify-write protocol from `/stigmergic-convention`:
- Set escalation to *pending* on the convergence node if the failure requires human judgment about how to proceed.
- Increase surprise scores on the convergence node to reflect the integration divergence.

Flag the need for replanning via `/session-plan`.
The handoff to session-plan should include the rework issues created, the accumulated surprise score, and the specific integration failures that motivated replanning.

If the convergence node previously had a higher confidence level, demote `confidence` to `regressed` to reflect that a previously supported claim no longer holds.
Record what evidence failed in the checkpoint context so the next worker understands the regression.

When deciding between rework and escalation, apply the self-verification gate's principle from `/stigmergic-convention`: if the failure can be fixed and retried, create rework issues; if the failure reveals an ambiguity that the DAG does not contain enough information to resolve, escalate with a precise question.

### Step 6: documentation and convention health at convergence

When verification completes at a convergence point, perform additional checks on the specifications and conventions that motivated the converging work.

#### Spec accuracy at convergence

Check whether the specs that motivated the converging work are still accurate.
Compare the acceptance criteria in the converging issues against what was actually implemented.
If implementation diverged from spec, flag the spec for revision.

#### Cross-doc consistency

For docs referenced by the converging issues, check that they are mutually consistent.
If issue A's work changed an assumption that issue B's spec relies on, flag the inconsistency.

#### Diagram coverage at convergence

Check whether the converging work introduced or modified architectural boundaries that the existing diagram set does not cover.
Compare the C4 levels touched by the converging issues against the diagram categories in `preferences-architecture-diagramming/04-diagram-compendium.md`.
When a convergence point assembles a new subsystem boundary or changes deployment topology and no corresponding diagram exists, flag the gap.
When existing diagrams depict structures that the converging implementation changed, flag those diagrams as stale.

#### Review gate (periodic)

Every 3rd convergence point reviewed in the project (or on explicit user request), run a lightweight meta-evaluation:

- *Advisory coupling*: Is it decreasing? Are workers needing less human intervention to find the right next action from DAG context alone?
- *Signal table calibration*: Are Cynefin classifications matching observed work complexity? Are planning-depth values producing appropriately scoped briefings?
- *Checkpoint state transfer*: Can new sessions reconstruct context from the graph alone, without supplemental briefing?
- *Surprise calibration*: Are surprise values in signal tables reflecting actual deviation from expectations, or reflexively set to 0.0?

Distinguish between "advisory input needed because the DAG could have answered" (convention gap: fix the convention) and "advisory input needed for genuinely complex-domain reasons" (validates the escalation protocol).
Record observations via `bd update <epic-id> --append-notes "Review gate [N]: ..."` for the relevant epic.

## Typical next steps

After review completes, the worker proceeds to one of:

- Implementation if verification passed and the operational buffer still contains ready issues.
- `/session-plan` if replanning was triggered by high surprise or failed verification.
- `/session-checkpoint` if the session is ending, to capture the review results in the handoff narrative.
- `/session-plan` to decompose validation or regression-protection work when review reveals a severity gap — the implementation exists but confidence cannot advance without stronger evidence.

---

*Composed skills (delegate, do not duplicate):*
- `/stigmergic-convention` -- signal table schema, self-verification gate, read-modify-write protocol
- `/issues-beads-evolve` -- rework issue creation when integration verification fails

*Related skills:*
- `/session-orient` -- strategic horizon session start, provides initial context for work selection
- `/session-plan` -- tactical-to-operational decomposition, invoked when replanning is triggered
- `/session-checkpoint` -- all-horizon state capture and handoff
- `/issues-beads-prime` -- core beads conventions and command quick reference

*Theoretical foundations:*
- `preferences-adaptive-planning` for the Viable System Model mapping (System 3* audit context), validation gate placement theory, and surprise threshold derivation
- `preferences-validation-assurance` for the severity criterion, evidence quality dimensions, and confidence promotion/demotion rules applied during integration verification
