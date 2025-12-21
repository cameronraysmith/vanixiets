---
description: Minimal quick reference for beads commands when context is constrained
---

# Beads quick reference

Symlink location: `~/.claude/commands/issues/beads-prime.md`
Slash command: `/issues:beads-prime`

Minimal quick reference when context is constrained.
For session lifecycle, prefer action commands: `/issues:beads-orient` (start), `/issues:beads-checkpoint` (wind-down).
For deeper patterns: `/issues:beads` (concepts), `/issues:beads-workflow` (operations), `/issues:beads-evolve` (refinement).

## Command index

- `beads-init` - Initial setup for beads issue tracking
- `beads-seed` - Generate issues from architecture documentation
- `beads-orient` - Session start diagnostics and work selection
- `beads-evolve` - Issue graph refactoring patterns
- `beads-checkpoint` - Session wind-down and handoff prep
- `beads-audit` - Database health check and validation

## Manual sync workflow

After git operations that modify beads state (pull, checkout, merge, rebase):

```bash
# Import changes from git into beads database
bd sync --import-only
```

Before committing beads changes:

```bash
# Run pre-commit validation
bd hooks run pre-commit

# Commit beads changes
git add .beads/issues.jsonl
git commit -m "chore(issues): ..."
```

## Orient

```bash
bd status                   # quick human-readable summary (~20 lines)
bd epic status              # epic progress
bv --robot-next             # minimal JSON: just the single top pick
```

## Select work

```bash
# Top pick (small JSON, safe for direct consumption)
bv --robot-next

# Full dependency context (upstream + downstream)
bd dep tree <id> --direction both

# Issue details
bd show <id>
```

For deeper analysis (redirect to file to avoid context pollution):

```bash
REPO=$(basename "$(git rev-parse --show-toplevel)")
TRIAGE=$(mktemp "/tmp/bv-${REPO}-triage.XXXXXX.json")
bv --robot-triage > "$TRIAGE"
jq '.recommendations[:3]' "$TRIAGE"
rm "$TRIAGE"
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
- After `bd` modifications: `git add .beads/issues.jsonl && git commit -m "chore(beads): sync issues"`
