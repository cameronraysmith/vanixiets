# Session orientation

Symlink location: `~/.claude/commands/issues/beads-orient.md`
Slash command: `/issues:beads-orient`

Action prompt for session start.
Run the commands below, synthesize results, and present project state to the user.

## Run orientation commands

Execute these commands now:

```bash
# Quick health check
bd stats

# Execution plan with impact analysis
bv --robot-plan

# Epic progress
bd epic status
```

If `bd stats` shows blocked > 50% of open issues, also run:

```bash
# Identify structural bottlenecks
bv --robot-insights | jq '{bottlenecks: .Bottlenecks[:5], cycles: .Cycles, density: .ClusterDensity}'
```

## Interpret results

From `bd stats`:
- Ready count = work that can start immediately
- Blocked count = work waiting on dependencies
- Healthy ratio: ready should be >10% of open

From `bv --robot-plan`:
- `tracks` = independent parallel work streams
- `items[].unblocks` = what completing each item frees up
- `summary.highest_impact` = single best item to work on for maximum downstream effect

From `bd epic status`:
- Progress percentages show which epics are advancing
- Stalled epics (0%) may indicate blocked critical paths

## Present synthesis

Provide the user a concise summary:

1. **Health**: X open, Y ready, Z blocked (ratio assessment)
2. **Highest-impact ready work**: Top 2-3 items from robot-plan with what they unblock
3. **Epic progress**: Which epics are advancing vs stalled
4. **Structural issues** (if any): Cycles, bottlenecks, density concerns

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
