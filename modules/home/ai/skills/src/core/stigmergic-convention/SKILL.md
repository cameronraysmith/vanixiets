---
name: stigmergic-convention
description: Signal table schema, field definitions, update protocol, and CUE validation for stigmergic workflow coordination.
---
# Stigmergic convention reference

Symlink location: `~/.claude/skills/stigmergic-convention/SKILL.md`
Slash command: `/stigmergic-convention`

Protocol reference for stigmergic workflow coordination via structured signal tables on beads issues.
Workers orient by reading the DAG rather than receiving briefings.
Context flows through the graph as structured signals, not through the orchestrator as prose summaries.

The signal table now carries both coordination state (cynefin, surprise, progress, escalation, planning-depth) and confidence state (confidence, evidence-freshness, regression-guard).
These serve a unified purpose — telling the next agent everything it needs to know about this issue — but they answer different questions.
Coordination state answers "what should I do?" while confidence state answers "what has been achieved and how certain are we?"

## Signal table template

Every issue carries this table in its `notes` field, delimited by HTML comments for machine parsing.

```
<!-- stigmergic-signals -->
| Signal | Value | Updated |
|---|---|---|
| schema-version | 1 | YYYY-MM-DD |
| cynefin | complicated | YYYY-MM-DD |
| surprise | 0.0 | YYYY-MM-DD |
| progress | not-started | YYYY-MM-DD |
| escalation | none | — |
| planning-depth | standard | YYYY-MM-DD |
| confidence | undemonstrated | YYYY-MM-DD |
| evidence-freshness | — | — |
| regression-guard | none | YYYY-MM-DD |
<!-- /stigmergic-signals -->
```

When no signal table exists, use defaults: cynefin=complicated, surprise=0.0, progress=not-started, escalation=none, planning-depth=standard, confidence=undemonstrated, evidence-freshness=absent, regression-guard=none.

## Field definitions

| Signal | Type | Valid values | Semantics |
|---|---|---|---|
| schema-version | integer | `1` | Convention version for forward compatibility. Warn on unrecognized values. |
| cynefin | enum | `clear`, `complicated`, `complex`, `chaotic` | Snowden domain classification. Drives planning-depth default. Update during checkpoint if implementation experience reveals a different domain. |
| surprise | float | `0.0` to `1.0` | Normalized divergence between issue description expectations and actual implementation experience. 0.0 = exactly as described, 1.0 = bore no resemblance. |
| progress | enum | `not-started`, `exploring`, `implementing`, `verifying`, `blocked` | Lifecycle state within current work session. `exploring` vs `implementing` distinction matters for complex-domain probe phases. |
| escalation | enum | `none`, `pending`, `resolved` | System 5 (human policy authority) interface state. Orthogonal to progress. |
| planning-depth | enum | `shallow`, `standard`, `deep`, `probe` | Controls orient briefing assembly depth. Derived from cynefin by default, manually overridable. |
| confidence | enum | `undemonstrated`, `finding-recorded`, `prototype`, `locally-verified`, `integration-verified`, `validated`, `regression-protected`, `regressed` | Evidence-based confidence level. Promoted only by fresh, severe evidence at the target level. `regressed` is a demotion target, not a promotion step. See `preferences-validation-assurance` for promotion rules and demotion triggers. |
| evidence-freshness | date | ISO date or `—` | When the current confidence level was last earned by fresh evidence. Not when the issue was last touched — when evidence was last produced. Absent (`—`) when confidence is `undemonstrated`. |
| regression-guard | enum | `none`, `manual`, `automated`, `runtime` | What mechanism protects the validated claim against regression. `manual` = documented verification procedure. `automated` = CI-enforced tests. `runtime` = monitors or health checks in production. See `preferences-validation-assurance` for tier descriptions. |

## Cynefin-to-planning-depth default mapping

| Cynefin domain | Default planning-depth | Orient behavior |
|---|---|---|
| clear | shallow | Brief summary: acceptance criteria and verification commands only. Dependency context omitted unless interface-affecting. |
| complicated | standard | Full context: description, all closed dependency context in topological order, resolved escalations, complete acceptance criteria. |
| complex | deep | Standard plus explicit exploration phase directive. Separates "what we know" from "what we need to discover". Worker checkpoints after exploration before implementing. |
| chaotic | probe | Minimal commitment: hypothesis, smallest intervention, rapid feedback loop. Act-sense-respond. Long-term planning deferred. |

## Read-modify-write protocol

Signal tables are updated via `bd update <id> --notes "..."` which *replaces* the entire notes field.
The `--append-notes` flag is not suitable because signal values change in place rather than accumulating.

Workflow for updating signals:

```bash
# 1. Read current notes
NOTES=$(bd show <id> --json | jq -r '.[0].notes // ""')

# 2. Parse: extract block between <!-- stigmergic-signals --> and <!-- /stigmergic-signals -->
# 3. Modify: update specific signal values and their Updated timestamps
# 4. Reconstruct: reassemble full notes with modified signal table, preserving all other sections

# 5. Write back
bd update <id> --notes "$RECONSTRUCTED_NOTES"
```

The notes field is *absent* (not null, not empty string) in JSON output when unset.
Parsers must handle field absence by treating it as empty notes with no signal table.
The checkpoint skill creates the table on first write, inserting it at the beginning of the notes field.

Preserved sections that must survive round-trips:
- `<!-- stigmergic-signals -->` ... `<!-- /stigmergic-signals -->` (the signal table itself)
- `<!-- checkpoint-context -->` ... `<!-- /checkpoint-context -->` (current state estimate, replaced each checkpoint)
- `<!-- escalation-context -->` ... `<!-- /escalation-context -->` (pending/resolved questions, accumulates chronologically)

## Escalation section format

When escalation is set to `pending`, write the question in a dedicated section.
The question must be precise enough for the human to answer without the worker's full context, referencing specific alternatives and explaining why the DAG does not contain enough information to choose.

```
<!-- escalation-context -->
## Pending (YYYY-MM-DD)
[Specific question with alternatives and rationale for why DAG context is insufficient]
<!-- /escalation-context -->
```

When the human resolves, they append a resolution subsection and set escalation to `resolved`:

```
<!-- escalation-context -->
## Pending (YYYY-MM-DD)
[Original question]

## Resolved (YYYY-MM-DD)
[Human's answer and any directives]
<!-- /escalation-context -->
```

Multiple escalation cycles on the same issue accumulate chronologically within the section, providing a decision audit trail.

## Process-improvement escalation

A second escalation type exists for double-loop learning: observations that the requirements, decomposition, or validation methodology should change.
Unlike resolution escalation (which expects an answer to a specific question), process-improvement escalation expects a discussion about whether the framework should evolve.

When an agent recognizes a pattern suggesting structural process issues (see the double-loop learning triggers in `preferences-validation-assurance`), it sets escalation to `pending` and writes the observation in the escalation-context section with a `## Process improvement (YYYY-MM-DD)` heading instead of `## Pending (YYYY-MM-DD)`.

The content should describe:
- The pattern observed (e.g., "surprise consistently > 0.5 across the last 4 issues in this epic")
- The evidence for the pattern (specific issues, specific signals)
- A proposed improvement to the process, requirements, or methodology
- Why the agent believes this cannot be resolved by local correction within the existing framework

Process-improvement escalations follow the same resolution lifecycle as resolution escalations: the human appends a `## Resolved (YYYY-MM-DD)` subsection with their assessment.

## Checkpoint context format

The `<!-- checkpoint-context -->` section describes current state, not history.
Each checkpoint replaces the prior content (the signal table carries cumulative summary via surprise and progress; checkpoint context describes what the next worker needs to know).

```
<!-- checkpoint-context -->
## State estimate (YYYY-MM-DD)

[What was done, what was learned, what remains, what downstream issues should know]
<!-- /checkpoint-context -->
```

Trajectory data (how surprise evolved, how many handoffs occurred) is available through `bd history <id>` which provides native dolt version history per-issue.

## CUE schema

The machine-checkable schema defines signal table constraints.
Source: `schemas/stigmergic-workflow/schema.cue` in the planning repository.

```cue
package stigmergic

#SchemaVersion: 1
#CynefinDomain: "clear" | "complicated" | "complex" | "chaotic"
#PlanningDepth: "shallow" | "standard" | "deep" | "probe"
#Progress: "not-started" | "exploring" | "implementing" | "verifying" | "blocked"
#EscalationState: "none" | "pending" | "resolved"
#ConfidenceLevel: "undemonstrated" | "finding-recorded" | "prototype" | "locally-verified" | "integration-verified" | "validated" | "regression-protected" | "regressed"
#RegressionGuard: "none" | "manual" | "automated" | "runtime"

#CynefinToDepth: {
	clear:       "shallow"
	complicated: "standard"
	complex:     "deep"
	chaotic:     "probe"
}

#SignalTable: {
	schema_version: #SchemaVersion
	cynefin:        #CynefinDomain
	surprise:       number & >=0.0 & <=1.0
	progress:       #Progress
	escalation:     #EscalationState
	planning_depth: #PlanningDepth
	confidence:         #ConfidenceLevel
	evidence_freshness: string  // ISO date or "—"
	regression_guard:   #RegressionGuard
}
```

Validation workflow:

```bash
# Extract signal table from issue notes to JSON, then validate against schema
just schema-vet-issue <id>
```

The extraction reads the issue's notes via `bd show <id> --json`, parses the markdown table between delimiters into JSON (mapping signal names to `snake_case` keys), and validates with `cue vet`.

## Self-verification gate

Before closing an issue, verify against its `acceptance_criteria` field.
Parse for verification commands (code blocks or inline code with shell commands).
Execute each and observe results.

On success, close with a reason describing what was implemented and verified:

```bash
bd close <id> --reason "Verified: implemented X, Y, Z. All acceptance criteria pass: [specific results]."
```

The closure reason is the primary pheromone trail for downstream workers.
A good closure reason answers "what exists now that did not before?" and "how do I know it works?".

On failure, either fix and retry, or escalate with the specific failure details (command, output, assessment).

## Graph health checks

After checkpoint or close operations, verify structural integrity:

```bash
bd dep cycles    # must be zero
bd lint          # check for missing template sections
```

---

*Theoretical foundations:*
- `preferences-adaptive-planning` for the stigmergy and Viable System Model theoretical foundations underlying the signal table design and the System 5 escalation interface
- `preferences-validation-assurance` for the evidence quality dimensions, confidence promotion chain, and regression harness design underlying the confidence, evidence-freshness, and regression-guard signals

*Composed by:*
- `/session-orient` -- reads signal tables during orientation briefing assembly
- `/session-plan` -- sets signal tables on newly created issues
- `/session-review` -- reads signal tables for surprise accumulation at convergence points
- `/session-checkpoint` -- updates signal tables during session wind-down
