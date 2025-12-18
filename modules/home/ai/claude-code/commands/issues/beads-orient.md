# Session orientation

Symlink location: `~/.claude/commands/issues/beads-orient.md`
Slash command: `/issues:beads-orient`

Action prompt for session start.
Run the commands below, synthesize results, and present project state to the user.

## Run orientation commands

Execute these commands now:

```bash
# Quick human-readable summary (~20 lines)
bd status

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
```

## Interpret results

From `bd status`:
- Total/Open/Blocked/Ready counts at a glance
- Recent activity from git history
- Human-readable, context-efficient

From `bv --robot-triage` (via jq extraction):
- `quick_ref` = at-a-glance counts + top 3 picks
- `recommendations` = ranked actionable items with scores, reasons, unblock info
- `quick_wins` = low-effort high-impact items
- `stale_alerts` = issues needing attention
- `project_health` = status/type/priority distributions, graph metrics, cycles

From `bd epic status`:
- Progress percentages show which epics are advancing
- Stalled epics (0%) may indicate blocked critical paths

## Present synthesis

Provide the user a concise summary:

1. **Health**: Use `quick_ref` counts — open/ready/blocked ratio assessment
2. **Top recommendations**: First 2-3 from `recommendations` with scores and what they unblock
3. **Quick wins**: Any items from `quick_wins` that could be knocked out rapidly
4. **Epic progress**: Which epics are advancing vs stalled
5. **Alerts** (if any): Stale issues, cycles, or health warnings from `project_health`

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

# Detailed description
bd show <selected-id>
```

Review with user:
- Is the description still accurate?
- Are listed dependencies still relevant?
- Is scope appropriate or should it be split first?

Update the issue if anything is stale before beginning work.

---

*Reference docs (read only if deeper patterns needed):*
- `/issues:beads-workflow` — full operational workflows
- `/issues:beads-evolve` — adaptive refinement patterns during work
