# Git-native mode

Working branch isolation recipes for git-native mode.
Bead implementation work uses worktrees rooted in `.worktrees/` at the repository root.
This directory must be listed in `.gitignore`.

The worktree model has two tiers: epic worktrees for coordination and issue worktrees for implementation.

## Epic branches

Each active epic gets its own branch.
The *focus epic* — the primary epic being actively coordinated — is checked out in the repo root.
This keeps orientation commands (`bd status`, `bd epic status`) and code-level context aligned with the active work.

Create a focus epic branch when starting work on an epic:

```bash
git checkout -b {epic-ID}-descriptor main
```

*Secondary epics* being worked in parallel get worktrees in `.worktrees/`:

```bash
git worktree add .worktrees/{epic-ID}-descriptor -b {epic-ID}-descriptor main
```

When one epic depends on another, stack it on the parent epic's branch rather than main:

```bash
# nix-pxj depends on nix-1kj, so stack it
git checkout -b nix-pxj-ntfy-server nix-1kj-stigmergic-tooling
# or as a secondary worktree:
git worktree add .worktrees/nix-pxj-ntfy-server -b nix-pxj-ntfy-server nix-1kj-stigmergic-tooling
```

An epic branch accumulates all commits from its child issue worktrees via fast-forward merges.
When the epic is complete, it contains the full linearized commit history for review, validation, and merge to main.

## Switching focus

To promote a secondary epic to focus (and optionally demote the current focus):

```bash
# Remove the secondary epic's worktree
git worktree remove .worktrees/{new-focus-epic}-descriptor

# Optionally preserve the old focus as a secondary worktree
git worktree add .worktrees/{old-focus-epic}-descriptor {old-focus-epic}-descriptor

# Check out the new focus epic in repo root
git checkout {new-focus-epic}-descriptor
```

When no epic is active, the repo root returns to the default branch.

## Issue worktrees

Each issue within an epic gets its own worktree, branching from the parent epic's branch.
The working agent creates the issue worktree as its first action before any implementation begins.

```bash
git worktree add .worktrees/{issue-ID}-descriptor -b {issue-ID}-descriptor {epic-ID}-descriptor
```

When issue work is complete, rebase onto the epic branch and fast-forward merge back into it:

```bash
cd .worktrees/{issue-ID}-descriptor
git rebase {epic-ID}-descriptor
cd ../..
# merge into the epic branch (from repo root if it's the focus epic):
git merge --ff-only {issue-ID}-descriptor
# or from the epic worktree if it's a secondary epic:
git -C .worktrees/{epic-ID}-descriptor merge --ff-only {issue-ID}-descriptor
```

Then clean up the issue worktree:

```bash
git worktree remove .worktrees/{issue-ID}-descriptor
git branch -d {issue-ID}-descriptor
```

## General rules

Always specify an explicit start-point when creating branches or worktrees.
Epic branches start from `main` (or from another epic's branch when stacking).
Issue worktrees branch from their parent epic's branch.
Without a start-point, git branches from whatever happens to be checked out, which may not be the intended base.

Use worktrees for bead-tracked work; use plain branches (`git checkout -b`) for non-bead or quick-fix work.

## Direnv initialization in worktrees

Worktrees do not inherit the repository root's direnv environment.
If the repository uses direnv with a nix devshell (indicated by an `.envrc` file), the devshell creates ephemeral files like `.pre-commit-config.yaml` that are not checked into git.
After creating a worktree, initialize its environment before any git operations that trigger hooks:

```bash
cd .worktrees/{ID}-descriptor
direnv allow
```

For git commits and other hook-triggering operations, use `direnv exec .` to ensure the nix devshell is active:

```bash
direnv exec . git commit -m "message"
```

This is not needed for read-only git operations (`git log`, `git status`, `git diff`) which do not trigger hooks.

When the epic is complete and merged to main, clean up:

```bash
# If it was a secondary epic worktree:
git worktree remove .worktrees/{epic-ID}-descriptor
# Delete the branch:
git branch -d {epic-ID}-descriptor
```

## See also

- [`SKILL.md`](SKILL.md) — top-level git version control principles and policy
- [`02-gitbutler-mode.md`](02-gitbutler-mode.md) — GitButler mode isolation recipes
- [`03-jj-mode.md`](03-jj-mode.md) — jj mode isolation recipes
