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
<!-- /stigmergic-signals -->
```

When no signal table exists, use defaults: cynefin=complicated, surprise=0.0, progress=not-started, escalation=none, planning-depth=standard.

## Field definitions

| Signal | Type | Valid values | Semantics |
|---|---|---|---|
| schema-version | integer | `1` | Convention version for forward compatibility. Warn on unrecognized values. |
| cynefin | enum | `clear`, `complicated`, `complex`, `chaotic` | Snowden domain classification. Drives planning-depth default. Update during checkpoint if implementation experience reveals a different domain. |
| surprise | float | `0.0` to `1.0` | Normalized divergence between issue description expectations and actual implementation experience. 0.0 = exactly as described, 1.0 = bore no resemblance. |
| progress | enum | `not-started`, `exploring`, `implementing`, `verifying`, `blocked` | Lifecycle state within current work session. `exploring` vs `implementing` distinction matters for complex-domain probe phases. |
| escalation | enum | `none`, `pending`, `resolved` | System 5 (human policy authority) interface state. Orthogonal to progress. |
| planning-depth | enum | `shallow`, `standard`, `deep`, `probe` | Controls orient briefing assembly depth. Derived from cynefin by default, manually overridable. |

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

## Checkpoint context format

The `<!-- checkpoint-context -->` section describes current state, not history.
Each checkpoint replaces the prior content (the signal table carries cumulative summary via surprise and progress; checkpoint context describes what the next worker needs to know).

```
<!-- checkpoint-context -->
## State estimate (YYYY-MM-DD)

[What was done, what was learned, what remains, what downstream issues should know]
<!-- /checkpoint-context -->
```

Trajectory data (how surprise evolved, how many handoffs occurred) is available through git history of `.beads/issues.jsonl` via `chore(beads): checkpoint <id>` commits.

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
