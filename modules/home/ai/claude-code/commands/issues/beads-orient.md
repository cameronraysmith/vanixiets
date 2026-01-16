---
description: Session start action - run diagnostics, synthesize project state, select work
---

# Session orientation

Symlink location: `~/.claude/commands/issues/beads-orient.md`
Slash command: `/issues:beads-orient`

Action prompt for session start.
Run the commands below, synthesize results, and present project state to the user.

This command assumes the issue graph is healthy.
If you discover structural problems (cycles, broken references, inconsistent states), use `/issues:beads-evolve` instead.
If you need to validate graph health, use `/issues:beads-audit` first.

## Run orientation commands

Execute these commands now:

```bash
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

# Extract specific fields
jq '.quick_ref' "$TRIAGE"              # summary counts and top picks
jq '.recommendations[:3]' "$TRIAGE"    # top 3 recommendations
jq '.project_health.graph_metrics.cycles' "$TRIAGE"  # circular deps

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

## Run execution planning commands

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

## Interpret results

From `bd status`:
- Total/Open/Blocked/Ready counts at a glance
- Recent activity from git history
- Human-readable, context-efficient

From `bd activity`:
- Real-time feed of issue mutations (create, update, delete)
- Event symbols: + (created), → (in_progress), ✓ (completed), ✗ (failed), ⊘ (deleted)
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

**Parallel entry points** (from `--robot-plan` Track-B items):
- Issues with no blockers that can start immediately
- Multiple entry points can be worked in parallel by different sessions or agents
- The `unblocks` field shows downstream impact of completing each

**Critical path** (from `--robot-capacity`):
- The longest chain of dependent issues in the graph
- Completing critical path items reduces total project duration
- Items not on critical path have slack — delays there do not extend the project

**High-impact items** (from `--robot-triage` recommendations):
- PageRank-based scoring identifies issues that unlock the most downstream work
- Score reflects influence in the dependency graph, not urgency or effort
- Optimizes for "maximum downstream unlock" rather than "what to do first"

These three perspectives answer different questions:
- *"What can I start now?"* → Parallel entry points
- *"What reduces total duration?"* → Critical path
- *"What has the most influence?"* → High-impact items

## Present synthesis

Provide the user a concise summary with three prioritization perspectives:

**Health overview**:
- Use `quick_ref` counts — open/ready/blocked ratio assessment
- Epic progress — which epics are advancing vs stalled
- Alerts (if any) — stale issues, cycles, or health warnings from `project_health`

**Start here** (parallel entry points):
- List N issues that have no blockers and can be worked in parallel
- Show what each unblocks downstream
- Example: "These 3 issues are independent roots: nix-50f.2, nix-50f.5, nix-l2a.1"

**Critical path** (serialization bottleneck):
- Show the chain that determines minimum project duration
- Highlight which items on the path are ready vs blocked
- Example: "6-issue critical path: nix-50f → nix-50f.5 → ... → nix-50f.12"

**High impact** (PageRank recommendations):
- First 2-3 from `recommendations` with scores and what they unblock
- Quick wins from `quick_wins` that could be knocked out rapidly
- Note overlap or divergence with critical path items

## Prompt work selection

Ask the user:
- Which area would you like to focus on?
- Should we drill into a specific issue? (offer to run `bd dep tree <id> --direction both` and `bd show <id>`)
- Any context about priorities or constraints for this session?

## Pre-work validation

Once an issue is selected, before starting implementation:

```bash
# Full dependency context
bd dep tree <selected-id> --direction both

# Detailed description (choose format based on needs)
bd show <selected-id>              # detailed view
bd show <selected-id> --refs       # show issues that reference this issue
bd show <selected-id> --short      # compact one-line output
bd show <selected-id> --thread     # show full conversation thread
```

Review with user:
- Is the description still accurate?
- Are listed dependencies still relevant?
- Is scope appropriate or should it be split first?

Update the issue if anything is stale before beginning work.
If updates were made, commit the database:

```bash
git add .beads/issues.jsonl && git commit -m "chore(beads): sync issues"
```

---

*Reference docs (read only if deeper patterns needed):*
- `/issues:beads` — comprehensive reference for all beads workflows and commands
- `/issues:beads-evolve` — adaptive refinement patterns during work
