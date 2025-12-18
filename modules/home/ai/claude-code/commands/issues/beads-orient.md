# Session orientation

Symlink location: `~/.claude/commands/issues/beads-orient.md`
Slash command: `/issues:beads-orient`

Action prompt for session start.
Run the commands below, synthesize results, and present project state to the user.

## Run orientation commands

Execute these commands now:

```bash
# Unified triage — the single entry point for project state
bv --robot-triage

# Epic progress (not included in triage output)
bd epic status
```

For minimal context when token-constrained:

```bash
# Just the single top pick with claim command
bv --robot-next
```

## Interpret results

From `bv --robot-triage`:
- `quick_ref` = at-a-glance counts + top 3 picks
- `recommendations` = ranked actionable items with scores, reasons, unblock info
- `quick_wins` = low-effort high-impact items
- `stale_alerts` = issues needing attention
- `project_health` = status/type/priority distributions, graph metrics, cycles
- `commands` = copy-paste shell commands for next steps

Key jq extractions:
```bash
bv --robot-triage | jq '.quick_ref'           # summary counts and top picks
bv --robot-triage | jq '.recommendations[0]'  # top recommendation with full context
bv --robot-triage | jq '.project_health.graph_metrics.cycles'  # circular deps (must be empty)
```

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
