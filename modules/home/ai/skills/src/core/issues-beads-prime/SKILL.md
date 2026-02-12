---
name: issues-beads-prime
description: Minimal quick reference for beads commands when context is constrained.
---
# Beads quick reference

Symlink location: `~/.claude/commands/issues/beads-prime.md`
Slash command: `/issues:beads-prime`

Minimal quick reference when context is constrained.
For session lifecycle, prefer action commands: `/issues:beads-orient` (start), `/issues:beads-checkpoint` (wind-down).
For comprehensive reference: `/issues:beads` (complete workflows, concepts, and operations).

This module serves as the common conventions and quick-reference layer that other beads skills reference for core context.
In particular, orient loads prime as a conventions preamble before performing session diagnostics.
All beads-related skills should treat the conventions defined here as authoritative.

## Command index

- `beads-init` - Initial setup for beads issue tracking
- `beads-seed` - Generate issues from architecture documentation
- `beads-orient` - Session start diagnostics and work selection
- `beads-evolve` - Issue graph refactoring patterns
- `beads-checkpoint` - Session wind-down and handoff prep
- `beads-audit` - Database health check and validation

## Conventions

### Epic structure

- Single-layer parent-child only: epics contain issues, not sub-epics. Do not create nested epics without explicit human request.
- Use `--type parent-child` when wiring parent-child relationships via `bd dep add`. Do not use `--type parent` — beads silently accepts it but does not recognize it for epic tracking.
- Every issue should be a child of an epic. Standalone orphan issues are discouraged.
- Create children with `bd create "title" --parent <epic-id>` for auto-incrementing hierarchical IDs, or create standalone and wire with `bd dep add <child> <epic> --type parent-child`.

### Status management

- When starting work on an issue, mark it `in_progress`: `bd update <id> --status in_progress`
- When starting work on any issue under an epic, also mark the parent epic `in_progress` if not already.
- Use `bd update <id> --status in_progress` before beginning implementation, not after.

### Closure policy

- LLMs and subagent Tasks can close individual issues automatically: `bd close <id> --reason "Implemented in $(git rev-parse --short HEAD)"`
- Never close epics directly. Use `bd epic close-eligible --dry-run` to surface readiness, then report to the human for review.
- After closing issues, check whether additional follow-up issues are needed. Use `bd close <id> --suggest-next` to see newly unblocked work.

### Worktree and branch workflow

- When to create: after session discussion clarifies what to work on, not at session start.
  The orient, discuss, decide cycle completes before any branch is created.
- Branch naming: follow the `<issue-id>-descriptor` pattern in lowercase kebab-case, dots replaced with dashes.
  Use epic-level branches (e.g. `nix-c6z-beads-conventions`) when working across multiple children; per-issue branches when work is isolated.
- Creation command: `git checkout -b <branch-name>` from the appropriate base (usually main).
- Dispatch clarity: when dispatching subagent Tasks for implementation work, the prompt must specify which branch the subagent works in.
  Subagents working on the same issue share a branch.
  Subagents working on different issues get different branches.
- No implicit assumptions: if a dispatch prompt does not mention a branch, the subagent should ask rather than assuming.

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

Additional sync flags:

```bash
bd sync --flush-only    # Only export to JSONL (useful for pre-commit)
bd sync --check         # Pre-sync integrity check
bd sync --dry-run       # Preview sync without changes
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

# Show ready-to-work issues (no blockers, open or in_progress)
bd ready

# Show blocked issues
bd blocked

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
# Create discovered issue (priority: 0=highest, 4=lowest, default=2)
bd create "Found: ..." -t bug -p 2
bd dep add <new-id> <current-id> --type discovered-from

# Add blocker
bd create "Need X first" -t task -p 1
bd dep add <blocker-id> <current-id>
```

## Complete work

```bash
bd close <id> --reason "Implemented in commit $(git rev-parse --short HEAD)"
bd epic close-eligible --dry-run  # report readiness to user; epic closure is human-only
```

## Health

```bash
bd dep cycles               # must be zero
bd doctor                   # check and fix installation health
bd lint                     # check issues for missing template sections
```

## Key patterns

- `bv --robot-triage` is the single entry point — unified counts, recommendations, health
- `bv --robot-next` for minimal context — just top pick with claim command
- `bd ready` / `bd blocked` for quick work selection without JSON parsing
- `bd dep tree <id> --direction both` shows full context (blockers + what completing it unblocks)
- Always close with `--reason` referencing the implementation
- Use `--type discovered-from` when creating issues found during other work
- After `bd` modifications: `git add .beads/issues.jsonl && git commit -m "chore(beads): sync issues"`

Other useful robot flags:
- `bv --robot-plan` - Dependency-respecting execution plan
- `bv --robot-insights` - Graph analysis
