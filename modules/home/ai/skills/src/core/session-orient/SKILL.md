---
name: session-orient
description: Strategic horizon session skill that assembles complete session context, calibrates by Cynefin domain and planning-depth signal, and produces a self-directing briefing.
---
# Session orientation

Symlink location: `~/.claude/skills/session-orient/SKILL.md`
Slash command: `/session-orient`

Session start protocol that assembles context from all available sources, calibrates work selection by Cynefin domain and planning-depth, and produces a briefing that enables the worker to self-direct.
This skill operates at the strategic planning horizon, reading the full remaining scope at low resolution.

This is the default session start command for repositories with the full stigmergic workflow installed.
For repositories without the full workflow (no session-layer skills, small utility repos, quick fixes), use `/issues-beads-orient` directly.

## Composed skills

This skill orchestrates a higher-level protocol that uses the following skills as components.
Do not duplicate their functionality; delegate to them.

- `/issues-beads-orient` provides DAG diagnostics and work selection (phase 1 graph-wide scan, phase 2 signal-table-driven briefing).
- `/stigmergic-convention` provides the signal table schema, field definitions, and read-modify-write protocol for parsing and interpreting signal tables on candidate issues.

Load `/issues-beads-prime` for core beads conventions and command quick reference before running orientation commands.

## Protocol

Execute the following steps in order.

### Step 1: load beads-orient diagnostics

Delegate the graph-wide scan to `/issues-beads-orient` phase 1.
Run `bd status`, `bd activity`, `bd epic status`, and the beads-view triage and plan commands (`bv --robot-triage`, `bv --robot-plan`, `bv --robot-capacity`) to establish the current state of the issue graph.

```bash
bd sync --import-only
bd status
bd activity
bd stale
bd epic status
```

For structured data when analyzing larger graphs:

```bash
REPO=$(basename "$(git rev-parse --show-toplevel)")
TRIAGE=$(mktemp "/tmp/bv-${REPO}-triage.XXXXXX.json")
bv --robot-triage > "$TRIAGE"
jq '.triage.quick_ref' "$TRIAGE"
jq '.triage.recommendations[:3]' "$TRIAGE"
rm "$TRIAGE"
```

Extract the three prioritization perspectives described in `/issues-beads-orient`: parallel entry points, critical path, and high-impact items.
Use the structural integrity checks from that skill (empty epic detection, orphan issue detection) to verify graph health before proceeding.

### Step 2: read AMDiRE documentation relevant to the selected work area

For each candidate issue, identify the documentation tree path covering architecture decisions, specifications, context documents, and research notes.
Load relevant documentation to provide domain context beyond what the issue description contains.

Locate documentation by scanning the repository's `docs/` directory structure and any paths referenced in the candidate issue's description or notes.
Architecture decisions (ADRs), specification documents, and context notes provide the domain background needed to calibrate the briefing.

When documentation references exist but the files are absent or outdated, note this as a gap in the synthesis output.
Missing documentation in a complex-domain issue increases the case for exploration phase directives in step 5.

### Step 3: parse signal tables on candidate issues

For each candidate issue, extract the signal table from the issue's notes field using the delimiter-based parsing protocol from `/stigmergic-convention`.

```bash
bd show <id> --json | jq -r '.[0].notes // ""'
```

Parse the block between `<!-- stigmergic-signals -->` and `<!-- /stigmergic-signals -->` delimiters.
Read the following values:

- *schema-version* (integer, currently `1`)
- *cynefin* (clear, complicated, complex, chaotic)
- *planning-depth* (shallow, standard, deep, probe)
- *surprise* (0.0 to 1.0)
- *progress* (not-started, exploring, implementing, verifying, blocked)
- *escalation* (none, pending, resolved)

If *schema-version* is absent, treat the table as version 1.
If *schema-version* is present and not `1`, warn the worker that the signal table uses an unrecognized schema version and that field semantics may have changed.
Continue parsing best-effort but surface the warning prominently in the step 6 synthesis.

When no signal table exists, apply defaults: cynefin=complicated, surprise=0.0, progress=not-started, escalation=none, planning-depth=standard.

If escalation is `resolved`, extract the resolution from the `<!-- escalation-context -->` section and surface it prominently.
If escalation is `pending`, inform the worker that an unresolved question exists and assess whether it blocks the candidate.

### Step 4: calibrate briefing depth per planning-depth signal

Assemble the briefing based on the planning-depth value.
Planning-depth is derived from the Cynefin classification by default but can be manually overridden.

At *shallow* depth (clear domain): emit acceptance criteria and verification commands only.
The worker knows how to do this kind of work; they need to know what to produce and how to verify it.
Omit dependency context unless a closed dependency changed an interface the worker must target.

At *standard* depth (complicated domain): emit full context including the issue description, all closed dependency closure context in topological order, resolved escalations, and complete acceptance criteria with verification commands.
If the surprise score from a prior worker exceeds 0.3, highlight the divergence and include checkpoint context that explains what was unexpected.

At *deep* depth (complex domain): emit everything from standard plus explicit exploration phase directives.
Separate "what we know" (from dependency context and prior checkpoint context) from "what we need to discover" (from the issue description's open questions or areas where surprise was high).
Instruct the worker to checkpoint after exploration before implementing.

At *probe* depth (chaotic domain): emit a minimal commitment directive focusing on hypothesis, smallest intervention, and rapid feedback loop.
The worker acts first to stabilize, senses what happened, then checkpoints with observations.
Long-term planning is explicitly deferred.

### Step 5: produce exploration phase directives for complex and chaotic domains

When planning-depth is *deep* or *probe*, orient shifts from "read the landscape" to "explore the problem space."
This is discovery mode, activated within orient rather than as a separate command.

Structure the output to separate known information from open questions:

*Known* (assembled from closed dependency closure reasons, checkpoint context, and documentation):
- What has been implemented and verified in upstream dependencies
- What interfaces and constraints exist from prior work
- What the documentation establishes about the domain

*Unknown* (identified from the issue description, documentation gaps, and high surprise scores):
- Questions the issue description leaves open
- Areas where prior workers reported high surprise
- Gaps between documentation and observed reality

Direct the worker to:
1. Spend their first phase probing the problem space before committing to an implementation approach.
2. Set progress=exploring initially via signal table update.
3. Checkpoint after exploration with findings (what was discovered, what approach is recommended, what risks remain).
4. Update progress=implementing only after the exploration checkpoint.

For *probe* depth specifically, frame the exploration as hypothesis testing.
Define the hypothesis, the smallest intervention that could confirm or refute it, and the feedback mechanism for observing results.
The worker is expected to act-sense-respond rather than sense-analyze-respond.

### Step 6: present synthesis with prioritization and work plan

Combine the diagnostics from step 1, documentation context from step 2, signal table state from step 3, and calibrated briefing from steps 4-5 into a single coherent output.

The synthesis includes:

*Health overview*: open/ready/blocked ratio, epic progress, alerts from stale issues or graph health warnings.

*Candidate assessment*: for each candidate issue, the Cynefin classification, planning-depth, surprise score, escalation state, and documentation coverage.

*Calibrated briefing*: the depth-appropriate briefing assembled in step 4, with exploration directives from step 5 when applicable.

*Work plan with phase recommendation*:
- Recommend `/session-plan` if the operational buffer is depleted (few ready issues relative to work capacity) or if decomposition is needed before implementation can begin.
- Recommend proceeding to implementation if the operational buffer is full and selected issues are ready with clear acceptance criteria.
- Recommend discovery mode (within this orient session) if planning-depth is deep or probe, before either planning or implementing.

*Cross-project context* (when available): any cross-repo references discovered during orientation, with confidence levels for each (see the cross-project context loading section below).

## Cross-project context loading

When operating in multi-repo ecosystems, session-orient assembles cross-project context to provide visibility beyond the current repository's DAG.
This context is advisory, not authoritative: it reflects the last-known state of external repositories and may be stale.

### Scan for cross-references

Examine issue descriptions and notes for cross-repo references using the format `see {prefix}-{id} in {repo}`.
This format is the convention for description cross-references between paired epics and their children across repositories.

When cross-references are found:

1. Check whether the referenced repository is accessible on the local filesystem.
2. If accessible, load the referenced issue's status and checkpoint context from that repository's beads database.
3. If not accessible, note the cross-reference as unresolvable and include only the information available in the local issue's description and notes.

### Load referenced issue status

For each resolvable cross-reference, query the external repository's beads database:

```bash
# From the external repo's working directory
bd show <referenced-id> --json | jq '.[0] | {id, title, status, close_reason, notes}'
```

Extract the referenced issue's status (open, in_progress, closed), closure reason if closed, and any checkpoint context from its notes field.
This provides the current state of the external dependency without requiring synchronous coordination between repositories.

### Leverage context symlinks in planning repos

Planning repositories may maintain `contexts/*.md` symlinks pointing to each project repo's `CLAUDE.md`.
When the current repository is a planning repo or when the planning repo is accessible on the local filesystem, read these symlinks to survey project-level architectural decisions and current state across the ecosystem.

```bash
# List available context symlinks
ls contexts/*.md 2>/dev/null
```

Each context file represents a project's orientation document.
Read them to understand cross-project constraints, shared conventions, and architectural decisions that affect the current work.

### Synthesize with confidence levels

Present cross-project context with explicit confidence ratings:

*High confidence*: the referenced repository was accessible and the issue's current status was read directly from its beads database.
The information is current as of the local filesystem state.

*Moderate confidence*: the referenced repository was accessible but the specific issue could not be found, or the issue exists but has no checkpoint context.
The cross-reference in the local issue's description provides partial information.

*Low confidence*: the referenced repository was not accessible on the local filesystem.
Only the prose cross-reference in the local issue's description is available.
The actual state of the external work is unknown.

Include the confidence level with each piece of cross-project context so the worker can weight it appropriately in their planning.

### Cross-project context integration with briefing depth

Cross-project context modulates the briefing in the same way as local context:

At *shallow* depth: mention cross-project references only if they affect interfaces the worker must target.

At *standard* depth: include cross-project dependency status and any propagated checkpoint context.

At *deep* depth: include everything from standard plus analysis of how cross-project state affects the exploration phase.
Unknown cross-project state (low confidence references) becomes an explicit item in the "what we need to discover" section.

At *probe* depth: include only cross-project context that directly informs the hypothesis or intervention design.

## Typical next steps

After orientation completes, the worker proceeds to one of:

- `/session-plan` if decomposition is needed (operational buffer depleted, scope unclear, or new epic requiring breakdown).
- Implementation if the operational buffer is full and the selected issue has clear acceptance criteria and verification commands.
- Discovery mode within this orient session if planning-depth is deep or probe, followed by `/session-checkpoint` after exploration and then either `/session-plan` or implementation.

---

*Composed skills (delegate, do not duplicate):*
- `/issues-beads-orient` -- DAG diagnostics, graph-wide scan, signal-table-driven briefing
- `/stigmergic-convention` -- signal table schema and parsing protocol

*Related skills:*
- `/session-plan` -- tactical-to-operational decomposition
- `/session-checkpoint` -- all-horizon state capture and handoff
- `/issues-beads-prime` -- core beads conventions and command quick reference
