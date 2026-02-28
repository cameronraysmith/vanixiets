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

Assemble these trails in topological order (respecting the dependency structure) to build a coherent picture of the integration context.
Pay attention to cases where one dependency's closure reason references interfaces, contracts, or assumptions that another dependency should have satisfied.
Mismatches between these references are candidates for integration failures.

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

#### Verification fails or surprise exceeds threshold

When integration verification fails or accumulated surprise exceeds theta, the existing plan has diverged from reality and corrective action is needed.

Create rework issues via `/issues-beads-evolve` to address integration failures.
Each rework issue should describe the specific failure, reference the convergence node and the relevant closed dependencies, and include acceptance criteria that would resolve the failure.

Update signal tables on affected issues via the read-modify-write protocol from `/stigmergic-convention`:
- Set escalation to *pending* on the convergence node if the failure requires human judgment about how to proceed.
- Increase surprise scores on the convergence node to reflect the integration divergence.

Flag the need for replanning via `/session-plan`.
The handoff to session-plan should include the rework issues created, the accumulated surprise score, and the specific integration failures that motivated replanning.

When deciding between rework and escalation, apply the self-verification gate's principle from `/stigmergic-convention`: if the failure can be fixed and retried, create rework issues; if the failure reveals an ambiguity that the DAG does not contain enough information to resolve, escalate with a precise question.

## Typical next steps

After review completes, the worker proceeds to one of:

- Implementation if verification passed and the operational buffer still contains ready issues.
- `/session-plan` if replanning was triggered by high surprise or failed verification.
- `/session-checkpoint` if the session is ending, to capture the review results in the handoff narrative.

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
