# Beads quick reference

Symlink location: `~/.claude/commands/issues/beads-prime.md`
Slash command: `/issues:beads-prime`

Minimal quick reference when context is constrained.
For session lifecycle, prefer action commands: `/issues:beads-orient` (start), `/issues:beads-checkpoint` (wind-down).
For deeper patterns: `/issues:beads` (concepts), `/issues:beads-workflow` (operations), `/issues:beads-evolve` (refinement).

## Orient

```bash
bv --robot-triage           # unified triage: counts, recommendations, health (JSON)
bv --robot-next             # minimal: just the single top pick
bd epic status              # epic progress
```

## Select work

```bash
# Top recommendation with full context
bv --robot-triage | jq '.recommendations[0]'

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

- `bv --robot-triage` is the single entry point — unified counts, recommendations, health
- `bv --robot-next` for minimal context — just top pick with claim command
- `bd dep tree <id> --direction both` shows full context (blockers + what completing it unblocks)
- Always close with `--comment` referencing the implementation
- Use `--type discovered-from` when creating issues found during other work
