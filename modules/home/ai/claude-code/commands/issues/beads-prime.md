# Beads quick reference

Symlink location: `~/.claude/commands/issues/beads-prime.md`
Slash command: `/issues:beads-prime`

Minimal context for AI agents.
Use in hooks (SessionStart, PreCompact) or when context is constrained.
For full documentation: `/issues:beads` (concepts) and `/issues:beads-workflow` (operations).

## Orient

```bash
bd stats                    # counts: total, open, blocked, ready
bv --robot-plan             # execution plan with unblocks (JSON)
bd epic status              # epic progress
```

## Select work

```bash
# Highest-impact ready issue
bv --robot-plan | jq -r '.plan.summary.highest_impact'

# Full dependency context (upstream + downstream)
bd dep tree <id> --direction both

# Issue details
bd show <id>
```

## During work

```bash
# Create discovered issue
bd create "Found: ..." -t bug -p 2
bd dep add <new-id> <current-id> --type discovered-from

# Add blocker
bd create "Need X first" -t task -p 1
bd dep add <blocker-id> <current-id>
```

## Complete work

```bash
bd close <id> --comment "Implemented in commit $(git rev-parse --short HEAD)"
bd epic close-eligible --dry-run
```

## Health

```bash
bd dep cycles               # must be zero
bd validate                 # database integrity
```

## Key patterns

- `bd ready` shows ready work but lacks impact context
- `bv --robot-plan` adds unblocks analysis — prefer this for selection
- `bd dep tree <id> --direction both` shows full context (blockers + what completing it unblocks)
- Always close with `--comment` referencing the implementation
- Use `--type discovered-from` when creating issues found during other work
