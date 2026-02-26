---
name: issues-beads-prime
description: Minimal quick reference for beads commands when context is constrained.
---
# Beads quick reference

Symlink location: `~/.claude/skills/issues-beads-prime/SKILL.md`
Slash command: `/issues:beads-prime`

Minimal quick reference when context is constrained.
For session lifecycle, prefer `/session-orient` (start) and `/session-checkpoint` (wind-down).
In repos without the full workflow, use `/issues:beads-orient` and `/issues:beads-checkpoint` directly.
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
- Use `--type parent-child` when wiring parent-child relationships via `bd dep add`. Do not use `--type parent` or `--type child-of` — beads silently accepts both but neither is recognized for epic tracking. The only valid containment type is `parent-child`.
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

Valid dependency types: `blocks`, `tracks`, `related`, `parent-child`, `discovered-from`, `until`, `caused-by`, `validates`, `relates-to`, `supersedes`.
Any other value is silently accepted but functionally broken.

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
- Never close epics without explicit human request.
  Epics whose children are all closed are intentionally kept open for human validation, follow-up issue creation, and iterative refinement.
  This is a normal steady-state, not an action item.
  Do not prompt, offer, or suggest closing eligible epics during orientation, checkpoint, or any other workflow phase.
  The human will request epic closure when ready, at which point `bd epic close-eligible --dry-run` can confirm readiness.
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

## Dolt persistence

Beads mutations auto-commit to the dolt database when `dolt.auto-commit` is enabled (the default after migration).
After a batch of mutations, push to the dolt remote for backup:

```bash
bd dolt push
```

For explicit checkpoint labels:

```bash
bd dolt commit -m "checkpoint: <description>"
bd dolt push
```

Additional dolt operations:

```bash
bd dolt pull          # Pull from dolt remote
bd dolt status        # Check dolt server status
bd history <id>       # View version history for an issue
bd diff               # Show changes between dolt commits
```

## Orient

```bash
bd status                   # quick human-readable summary (~20 lines)
bd epic status              # epic progress
bd ready | head -1          # top ready-to-work issue
```

## Select work

```bash
# Top ready-to-work issues (priority-sorted, no blockers)
bd ready

# Show blocked issues
bd blocked

# Full dependency context (upstream + downstream)
bd dep tree <id> --direction both

# Issue details
bd show <id>
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
bd epic close-eligible --dry-run  # on-demand only, when user requests epic closure review
```

## Health

```bash
bd dep cycles               # must be zero
bd doctor                   # check and fix installation health
bd lint                     # check issues for missing template sections
```

## Key patterns

- `bd status` for quick summary, `bd ready` for actionable work, `bd blocked` for bottlenecks
- `bd dep tree <id> --direction both` shows full context (blockers + what completing it unblocks)
- Always close with `--reason` referencing the implementation
- Use `--type discovered-from` when creating issues found during other work
- After `bd` modifications, push to the dolt remote for backup: `bd dolt push`
