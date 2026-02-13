---
name: issues-beads-prime
description: Minimal quick reference for beads commands when context is constrained.
---
# Beads quick reference

Symlink location: `~/.claude/skills/issues-beads-prime/SKILL.md`
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

### Dependency type discipline

Two dependency types serve fundamentally different purposes and must never be conflated.

*Containment* (issue belongs to an epic) uses `parent-child` type exclusively.
Establish at creation via `bd create "title" --parent <epic-id>`, or post-hoc via `bd dep add <child> <epic> --type parent-child`.
Every non-epic issue must have exactly one parent-child relationship to an epic.
An epic does not "block" its children — children are ready to work as soon as their sibling and cross-epic dependencies allow.

*Sequencing* (A must complete before B can start) uses `blocks` type, the default.
Establish via `bd dep add <blocked> <blocker>` between siblings, across epics, or between epics themselves.

The antipattern to avoid: wiring an issue as "blocked by" its containing epic instead of as a "child of" that epic.
This causes `bd epic status` to report 0 children for the epic and makes the issue appear blocked when it should be ready.

When an issue relates to multiple epics, use `parent-child` for the primary and `related` for secondary associations.
An issue can have at most one parent-child relationship.

Verification after bulk operations:

```bash
# Any epic showing 0/0 children that has BLOCKS deps to non-epic issues has the antipattern
bd epic status
```

If `bd epic status` shows `0/0 children` for an epic known to contain issues, the containment relationships were likely wired as `blocks` instead of `parent-child`.

### Status management

- When starting work on an issue, mark it `in_progress`: `bd update <id> --status in_progress`
- When starting work on any issue under an epic, also mark the parent epic `in_progress` if not already.
- Use `bd update <id> --status in_progress` before beginning implementation, not after.

### Closure policy

- LLMs and subagent Tasks can close individual issues automatically: `bd close <id> --reason "Implemented in $(git rev-parse --short HEAD)"`
- Never close epics directly. Use `bd epic close-eligible --dry-run` to surface readiness, then report to the human for review.
- After closing issues, check whether additional follow-up issues are needed. Use `bd close <id> --suggest-next` to see newly unblocked work.

### Worktree and branch workflow

Bead implementation work uses worktrees for isolation; non-bead work uses plain branches.
Branch naming follows the `{ID}-descriptor` pattern in lowercase kebab-case, with dots in bead IDs replaced by dashes.
Default granularity is per-issue; use epic-level worktrees only when the orchestrator explicitly specifies.

Worktree creation command (from repo root):

```bash
git worktree add .worktrees/{ID}-descriptor -b {ID}-descriptor main
```

The subagent creates the worktree as its first action before any implementation work begins.
The `.worktrees/` directory must be listed in `.gitignore`.

For non-bead or quick-fix work, use a plain branch instead: `git checkout -b {ID}-descriptor`.

Dispatch clarity:
- When dispatching subagent Tasks, the prompt must specify which worktree or branch the subagent works in.
- Subagents working on the same issue share a worktree.
- Subagents working on different issues get different worktrees.
- If a dispatch prompt does not mention a worktree or branch, the subagent should ask rather than assuming.

Worktree lifecycle (create, work, rebase, merge, clean up):

```bash
# 1. Create worktree and branch
git worktree add .worktrees/{ID}-descriptor -b {ID}-descriptor main

# 2. Work in the worktree, making atomic commits

# 3. When work is complete, rebase onto main
cd .worktrees/{ID}-descriptor
git rebase main

# 4. Fast-forward merge to main (from repo root)
cd ../..
git checkout main
git merge --ff-only {ID}-descriptor

# 5. Clean up
git worktree remove .worktrees/{ID}-descriptor
git branch -d {ID}-descriptor
```

All merges to main must be fast-forward.
Rebase the branch onto main before merging to ensure this.
The repository `merge.ff=only` git config rejects non-fast-forward merges as a safety net.

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
git commit -m "chore(beads): ..."
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

# Add blocker to current issue
bd create "Need X first" -t task -p 1
bd dep add <current-id> <blocker-id>
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
