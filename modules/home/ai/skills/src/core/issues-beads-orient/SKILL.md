---
name: issues-beads-orient
description: Session start action to run diagnostics, synthesize project status, and identify next actions.
disable-model-invocation: true
---
# Session orientation

Symlink location: `~/.claude/skills/issues-beads-orient/SKILL.md`
Slash command: `/issues:beads-orient`

This is the beads-layer orientation substrate.
For full workflow sessions, use `/session-orient` which composes this skill with AMDiRE documentation reading and cross-project context assembly.
This skill remains independently invocable for repos that do not use the full workflow.

Action prompt for session start.
This skill operates in two phases: a graph-wide scan to establish project state and identify candidates, then a signal-table-driven briefing once the user selects an issue.
Run the commands below, synthesize results, and present project state to the user.

This command assumes the issue graph is healthy.
If you discover structural problems (cycles, broken references, inconsistent states), use `/issues:beads-evolve` instead.
If you need to validate graph health, use `/issues:beads-audit` first.

Before running orientation commands, load `/issues:beads-prime` for core beads conventions and command quick reference.
The conventions section in that skill establishes the rules that govern all beads operations during this session.

## Phase 1: graph-wide scan

This phase runs at session start before any issue is selected.
Its purpose is to establish the overall project state and help the user choose what to work on.

### Run orientation commands

Execute these commands now:

```bash
# For formatted ready/blocked output, use bd list --ready --pretty / bd list --blocked --pretty
# (--pretty is a bd list flag, not available on bd ready/bd blocked subcommands)

# First, ensure local DB is current
bd sync --import-only

# Quick human-readable summary (~20 lines)
bd status

# Recent activity (last 100 events)
bd activity

# Stale issues that may need attention
bd stale

# Epic progress
bd epic status
```

For structured data when needed (redirect to avoid context pollution):

```bash
# Create repo-specific temp file — bv JSON outputs can be thousands of lines
REPO=$(basename "$(git rev-parse --show-toplevel)")
TRIAGE=$(mktemp "/tmp/bv-${REPO}-triage.XXXXXX.json")
bv --robot-triage > "$TRIAGE"

# Extract specific fields (all nested under .triage)
jq '.triage.quick_ref' "$TRIAGE"              # summary counts and top picks
jq '.triage.recommendations[:3]' "$TRIAGE"    # top 3 recommendations
jq '.triage.project_health.graph_metrics.cycles' "$TRIAGE"  # circular deps

# Clean up when done
rm "$TRIAGE"
```

For minimal structured output (safe for direct consumption):

```bash
# Just the single top pick — small JSON output
bv --robot-next

# Additional diagnostic tools
bv --robot-alerts           # drift + proactive alerts
bv --robot-drift            # detect configuration drift
```

For drift detection with exit codes (useful for automation):

```bash
# Exit codes: 0=OK, 1=critical drift, 2=warning
bv --check-drift
```

### Structural integrity check

Before proceeding with execution planning, verify that the parent-child structure is sound.
This detects the most common structural error: containment relationships wired as `blocks` instead of `parent-child`.

#### Detect empty epics with mistyped containment

Check `bd epic status` output for epics that report 0 children:

```bash
bd epic status | grep "0/0"
```

For each epic showing `0/0 children`, check whether it has `blocks` relationships to non-epic issues:

```bash
bd show <epic-id>
```

If the BLOCKS section lists non-epic issues, those are likely containment relationships that should be `parent-child`.
An epic blocking its own child issues is the antipattern — child issues should be connected via `parent-child`, not `blocks`.

Also check for dependencies typed as `child-of` on any epic in scope.
The `child-of` type is silently accepted by bd but not recognized by `bd epic status` for child counting, producing the same symptom as `blocks` misuse: epics that appear to have 0 children.
Inspect dependency details with `bd show <epic-id> --json` or review `bd dep tree <epic-id>` output for non-standard relationship types.

If either pattern is detected (`blocks` or `child-of` used for containment), report to the user:

```
Structural issue: <epic-id> has 0 children per bd epic status but has
N non-epic issues connected via blocks or child-of that appear to be
its children. These containment relationships need conversion to
parent-child.

Suggested fix for each affected child:
  bd dep remove <child-id> <epic-id>
  bd dep add <child-id> <epic-id> --type parent-child
```

Offer to apply corrections before continuing orientation, or note the issue and proceed if the user prefers.

#### Detect orphan issues

Compare the total non-epic open issue count against the sum of epic child counts from `bd epic status`.
If significantly fewer issues appear as epic children than exist in the database, some issues lack parent-child relationships.
Use `bd list --pretty` to identify which issues appear at the top level without an epic parent.

Systemic issues (all containment wired as blocks) should be corrected before orientation proceeds.
Minor issues (1-2 orphans from recent ad-hoc creation) can be noted and deferred.

### Run execution planning commands

Extract three complementary perspectives on work prioritization:

```bash
# Parallel entry points (independent roots with no blockers)
bv --robot-plan | jq '[.plan.tracks[] | select(.reason == "Independent work stream") | .items[]] | map({id, title, unblocks})'

# Critical path (serialization bottleneck)
bv --robot-capacity | jq '{critical_path, critical_path_length}'

# Top 3 high-impact items (PageRank-based)
bv --robot-triage | jq '.triage.recommendations[:3] | map({id, title, score, action})'
```

For additional topological context:

```bash
# Full execution order respecting dependencies
bv --robot-insights | jq '.Stats.TopologicalOrder'
```

### Interpret results

From `bd status`:
- Total/Open/Blocked/Ready counts at a glance
- Recent activity from git history
- Human-readable, context-efficient

From `bd activity`:
- Real-time feed of issue mutations (create, update, delete)
- Event symbols: + (created), -> (in_progress), check (completed), x (failed), null (deleted)
- Shows workflow progress and recent changes

From `bd stale`:
- Issues not updated in last 30 days (configurable with --days)
- Identifies potentially abandoned in_progress items
- Highlights forgotten or outdated issues

From `bv --robot-triage` (via jq extraction):
- `quick_ref` = at-a-glance counts + top 3 picks
- `recommendations` = ranked actionable items with scores, reasons, unblock info
- `quick_wins` = low-effort high-impact items
- `stale_alerts` = issues needing attention
- `project_health` = status/type/priority distributions, graph metrics, cycles

From `bd epic status`:
- Progress percentages show which epics are advancing
- Stalled epics (0%) may indicate blocked critical paths

From execution planning commands:

*Parallel entry points* (from `--robot-plan` Track-B items): issues with no blockers that can start immediately.
Multiple entry points can be worked in parallel by different sessions or agents.
The `unblocks` field shows downstream impact of completing each.

*Critical path* (from `--robot-capacity`): the longest chain of dependent issues in the graph.
Completing critical path items reduces total project duration.
Items not on critical path have slack, so delays there do not extend the project.

*High-impact items* (from `--robot-triage` recommendations): PageRank-based scoring identifies issues that unlock the most downstream work.
Score reflects influence in the dependency graph, not urgency or effort.
Optimizes for "maximum downstream unlock" rather than "what to do first".

These three perspectives answer different questions:
- "What can I start now?" -> Parallel entry points
- "What reduces total duration?" -> Critical path
- "What has the most influence?" -> High-impact items

#### Implementation vs verification readiness

The dependency graph models *code/logical dependencies*, not *environment prerequisites*.
All graph roots (parallel entry points) are implementation-ready.
A subset of these are also verification-ready.

Distinguishing heuristics:

*Pure code modules* are usually verification-ready: Nix modules verifiable with `nix eval`, `nix build --dry-run`, or `nix-unit`; library code verifiable with type checking, unit tests, or static analysis.
These can be implemented and verified in any order.

*Infrastructure-creating issues* become verification-ready once their dependencies complete: VM images, cluster provisioning, environment setup.
Once created, they establish the environment for downstream verification.

*Infrastructure-deploying issues* are verification-blocked until their target environment exists: Kubernetes manifests, CNI plugins, certificates, operators.
Implementation-ready (can write the code) but verification requires the target environment.

The *foundation chain* is the sequence of infrastructure-creating issues that establishes verification environments.
Completing the foundation chain unblocks verification for all infrastructure-deploying issues.

### Present synthesis

Determine presentation depth based on graph scale, then provide the user a concise summary with three prioritization perspectives.

#### Scale-aware presentation

Tailor output verbosity to issue count to avoid overwhelming users with large graphs while providing complete information for small ones.

*Small graphs (< 30 open issues)*: enumerate all parallel entry points with full details, show complete critical path with all nodes, full detail on all ready issues including descriptions, show complete dependency chains for recommendations.

*Medium graphs (30-100 open issues)*: show top 10 parallel entry points sorted by unblock count descending, show critical path with length and key milestones, group ready issues by epic with counts, summarize recommendations with links to full details.

*Large graphs (> 100 open issues)*: show top 5 parallel entry points by unblock count descending, show critical path length and first/last 3 nodes only, epic-level aggregation mandatory, per-epic top picks (best ready issue per major epic), partially-complete epic analysis for epics with progress > 0%.

Determine scale tier at session start:

```bash
# Extract open count to determine tier
bd status | grep "Open:"
```

#### Selection criteria

When showing a subset of issues at medium/large scale, apply these selection criteria.

*Parallel entry points*: sorted by unblock count (descending), then by PageRank score as tiebreaker.
This prioritizes issues that unlock the most downstream work.

```bash
# Extract parallel entry points sorted by unblock count
bv --robot-plan | jq '[.plan.tracks[] | select(.reason == "Independent work stream") | .items[]] | sort_by(-.unblocks | length) | .[:10]'
```

*High-impact items*: sorted by PageRank score from `--robot-triage` recommendations.
Score reflects influence in the dependency graph.

*Critical path*: computed by `bv --robot-capacity`, representing the longest dependency chain.
Items on this path determine minimum project duration.

#### Epic-level aggregation

For medium and large graphs, aggregate ready issues by epic to help users select a workstream:

```
Ready issues by epic:
- Domain layer (ironstar-abc): 12 ready, 8 blocked
- Frontend pipeline (ironstar-xyz): 5 ready, 15 blocked
- Event sourcing (ironstar-def): 3 ready, 10 blocked
```

Extract epic-level counts:

```bash
# Epic progress with ready/blocked breakdown
bd epic status

# Ready issues with hierarchy (shows parent epic)
bd list --ready --pretty
```

For large graphs, this aggregation is mandatory: show epic-level summaries before individual issue recommendations.

#### Per-epic top picks

For large graphs, identify the best entry point for each major epic rather than only global recommendations:

```
Top pick per epic:
- Domain: ironstar-abc.5 (unblocks 4, verification-ready)
- Frontend: ironstar-xyz.1 (on critical path, unblocks 3)
- Event sourcing: ironstar-def.2 (unblocks 2, starts foundation chain)
```

This provides entry points into each workstream.
Users can then focus on a specific epic without reviewing all 72+ ready issues.
Selection within each epic uses the same criteria: unblock count descending, PageRank as tiebreaker.

#### Partially-complete epic analysis

For large graphs with epics showing progress > 0%, provide completion context:

```
Domain layer (42% complete):
- 12 issues closed, 8 ready, 12 blocked
- Next milestone: Complete aggregate implementations
- Blocking: ironstar-abc.7 (waiting on infrastructure)
```

This answers "why is X at Y%?" and "what's next for this epic?" without requiring users to drill into individual issues.

Extract progress data:

```bash
# Epic completion percentages
bd epic status

# Blocked issues within an epic
bd list --blocked | grep "ironstar-abc"
```

#### Parallel track expansion

For parallel work recommendations at medium/large scale, show 2-3 issues per track rather than just the first:

```
Parallel tracks:
- Track 1 (foundation): A -> B -> C (creates environment)
- Track 2 (domain): D -> E -> F (core business logic)
- Track 3 (frontend): G -> H (UI components)
```

This shows the next few issues in sequence, helping users understand what follows their immediate work item.

Extract track sequences:

```bash
# Full track sequences from robot-plan
bv --robot-plan | jq '.plan.tracks[] | {reason, items: [.items[] | {id, title}]}'
```

#### Prioritization perspectives

Provide the user a concise summary with three prioritization perspectives:

*Health overview*: use `quick_ref` counts for open/ready/blocked ratio assessment, epic progress showing which epics are advancing vs stalled, and alerts (stale issues, cycles, or health warnings from `project_health`).

*Start here* (parallel entry points): list N issues that have no blockers and can be worked in parallel, show what each unblocks downstream, classify each as verification-ready (pure code, can test now) or verification-blocked (needs environment first), and identify the foundation chain if infrastructure-creating issues exist among roots.

*Critical path* (serialization bottleneck): show the chain that determines minimum project duration, highlight which items on the path are ready vs blocked.

*High impact* (PageRank recommendations): first 2-3 from `recommendations` with scores and what they unblock, quick wins from `quick_wins` that could be knocked out rapidly, note overlap or divergence with critical path items.

#### Example interpretation

Given parallel entry points `[A, B, C]` where A creates an environment, B deploys to that environment, and C is pure code:

The foundation chain might be: `A -> D -> E -> ENVIRONMENT_EXISTS`

For solo work: start with A (verification-ready), complete D and E (each verification-ready after predecessor), then B and C can both be implemented and verified.
C could have been done earlier but verification order does not matter for pure code.

For parallel work: Track 1 handles A -> D -> E (foundation chain, creates environment), Track 2 handles B (implement now, verify after Track 1 completes), Track 3 handles C (implement and verify immediately, no environment dependency).

The key insight: all three roots (A, B, C) are implementation-ready, but only A and C are verification-ready at session start.

### Prompt work selection

Ask the user:
- Are you working solo (optimize for verification sequence) or parallel (maximize implementation throughput)?
- Which area would you like to focus on?
- Should we drill into a specific issue? (offer to run `bd dep tree <id> --direction both` and `bd show <id>`)
- Any context about priorities or constraints for this session?

For solo work, recommend the foundation chain first: the sequence of infrastructure-creating issues that establishes environments.
Complete and verify each step before moving to the next, then branch to parallel implementation of deployment modules.

For parallel work, recommend distributing across all implementation-ready roots.
Assign foundation chain to one track and pure code / deployment modules to others.
Verification will happen in waves as environments come online.

## Phase 2: signal-table-driven briefing

This phase activates after the user selects an issue.
It reads the selected issue's signal table and closed dependency context to assemble a tailored briefing calibrated by the cynefin domain classification and planning-depth signal.

Load `/stigmergic-convention` for the full signal table protocol reference if not already loaded.

### Read issue signals

Extract the signal table and dependency context from the selected issue:

```bash
# Full dependency context
bd dep tree <selected-id> --direction both

# Detailed description
bd show <selected-id>

# Reverse cross-references from other issues (surfaces impact beyond direct dependencies)
bd show <selected-id> --refs

# Full conversation thread if prior workers left messages or checkpoint notes
bd show <selected-id> --thread

# Structured data for signal parsing
bd show <selected-id> --json
```

Extract the signal table from the JSON output.
The output is an array; use index `[0]` to access the issue object.
The `notes` field is absent (not null, not empty string) when no notes have been set.
Parse the signal table from the text between `<!-- stigmergic-signals -->` and `<!-- /stigmergic-signals -->` delimiters within the notes field.

```bash
# Extract notes field (handles absent field)
bd show <selected-id> --json | jq -r '.[0].notes // ""'
```

From the signal table, extract these values:
- `cynefin` — domain classification (clear, complicated, complex, chaotic)
- `planning-depth` — briefing depth override (shallow, standard, deep, probe)
- `surprise` — divergence score from prior workers (0.0 to 1.0)
- `progress` — lifecycle state (not-started, exploring, implementing, verifying, blocked)
- `escalation` — System 5 interface state (none, pending, resolved)

If no signal table exists in the notes, apply defaults: cynefin=complicated, surprise=0.0, progress=not-started, escalation=none, planning-depth=standard.

### Read pheromone trails from closed dependencies

For each blocking dependency that is closed, read its closure reason and checkpoint context.
These are the pheromone trails that propagate implementation context through the DAG.

First, identify closed dependencies from the embedded dependency list:

```bash
bd show <selected-id> --json | jq '[.[0].dependencies[] | select(.status == "closed") | {id, title}]'
```

The embedded dependency objects include `notes` and `status` but do not include `close_reason`.
To read the closure reason, query each closed dependency individually:

```bash
bd show <dep-id> --json | jq '.[0].close_reason // empty'
```

The `close_reason` field contains what was implemented and how it was verified.
The `notes` field (available on the embedded dependency object or via direct query) may contain a `<!-- checkpoint-context -->` section with additional state from the worker who closed the issue.

Present closed dependency context in topological order (dependencies before dependents) so the worker understands the foundation their work builds on.

### Check escalation state

If the escalation signal is `resolved`, extract the resolution from the `<!-- escalation-context -->` section in the issue's notes.
The resolution contains the human's answer to a prior worker's question and must be surfaced prominently in the briefing so the current worker can act on it.

If the escalation signal is `pending`, inform the worker that an unresolved question exists.
The worker should read the pending question and either wait for resolution (if the answer is blocking) or proceed with other work.

### Calibrate briefing depth

Assemble the briefing based on the `planning-depth` signal.
The planning-depth value is derived from the cynefin classification by default but can be manually overridden.

The cynefin-to-planning-depth default mapping:

| Cynefin domain | Default planning-depth |
|---|---|
| clear | shallow |
| complicated | standard |
| complex | deep |
| chaotic | probe |

#### Shallow briefing (clear domain)

Emit a brief summary consisting of the acceptance criteria and verification commands only.
The worker already knows how to do this kind of work; they just need to know what specifically to produce and how to verify it.
Omit dependency context unless a closed dependency's completion changed an interface the worker needs to target.

Present: acceptance criteria, verification commands, and any interface-affecting dependency closure context.

#### Standard briefing (complicated domain)

Emit full context: the issue description, all closed dependency closure context in topological order, any resolved escalations, and the complete acceptance criteria with verification commands.
This is the default level and the most common case.

Present: issue description, closed dependency context (topological order), resolved escalation context, acceptance criteria, verification commands.

If the surprise score from a prior worker is above 0.3, highlight the divergence and include any checkpoint context that explains what was unexpected.
This alerts the current worker that the description may not fully match reality.

#### Deep briefing (complex domain)

Emit everything from standard plus an explicit exploration phase directive.
Instruct the worker to spend their first phase probing the problem space before committing to an implementation approach.

Structure the briefing to separate "what we know" (from dependency context and prior checkpoint context) from "what we need to discover" (from the issue description's open questions or areas where surprise was high).

The worker is expected to checkpoint after the exploration phase with findings before proceeding to implementation.
Remind them to set progress=exploring initially, then update to progress=implementing after the exploration checkpoint.

#### Probe briefing (chaotic domain)

Emit a minimal commitment directive.
The briefing focuses on experiment design: what hypothesis to test, what the smallest possible intervention is, and what the rapid feedback loop looks like.

The worker is expected to act first to stabilize, then sense to understand what happened, then checkpoint with observations.
Long-term planning is explicitly deferred.

Present: the immediate hypothesis, the smallest intervention, the feedback mechanism, and the checkpoint expectation.

### Review with user

After assembling the briefing, review with the user:
- Is the description still accurate?
- Are listed dependencies still relevant?
- Is scope appropriate or should it be split first?
- Does the cynefin classification match their assessment? (Offer to override planning-depth if not.)

Update the issue if anything is stale before beginning work.
If updates were made, commit the database from the repo root or focus epic branch:

```bash
git add .beads/issues.jsonl && git commit -m "chore(beads): sync issues"
```

If you are working in a `.worktrees/` subdirectory, skip the JSONL commit.
The orchestrator handles serialization after merging worktree branches back.

Before starting implementation, ensure a branch is created following the worktree and branch conventions in `/issues:beads-prime`.

---

*Reference docs (read only if deeper patterns needed):*
- `/issues:beads` — comprehensive reference for all beads workflows and commands
- `/issues:beads-evolve` — adaptive refinement patterns during work
- `/stigmergic-convention` — signal table protocol reference
