# GitButler mode

Working branch isolation recipes for GitButler mode.
All branches coexist in a single workspace — no worktrees are needed.
Isolation comes from branch boundaries within and across stacks rather than filesystem separation.

## Branch stacks as epics

Each active epic corresponds to a branch stack.
Create a new stack for a new epic:

```bash
but branch new {epic-ID}-descriptor
```

When one epic depends on another, stack it on the parent epic's branch:

```bash
but branch move {epic-ID}-descriptor {parent-epic-ID}-descriptor
```

## Issue branches within a stack

Each issue within an epic becomes a branch boundary within the epic's stack.
Insert a branch boundary at the commit where the issue's work begins:

```bash
but branch new {issue-ID}-descriptor -a <anchor-commit>
```

The anchor commit and everything below it become the new branch.
Everything above the anchor stays with the original branch.
See the "Split a branch at a commit boundary" recipe in `~/.claude/skills/gitbutler-but-cli/SKILL.md` for details.

When issue work is complete, commits are already part of the stack's linear history.
No rebase or merge step is needed — the stack tip integrates all segments at once when merged to main.

## Switching focus

To shelve work on a stack and focus on another, use `but unapply` and `but apply`:

```bash
# Shelve the current stack
but unapply {branch-name}
# Apply a different stack
but apply {other-branch-name}
```

Unapplied stacks retain their commits and can be reapplied at any time.

## Cross-stack commit reorganization

Move a commit from one branch to another within or across stacks:

```bash
but move <source-commit-id> <target-commit-id> --status-after
```

Commit IDs come from `but status -fv` or `but show <branch-id>`.

## No direnv initialization needed

GitButler operates in a single working tree, so the repository root's direnv environment applies to all branches.

## See also

- [`SKILL.md`](SKILL.md) — top-level git version control principles and policy
- [`01-git-native-mode.md`](01-git-native-mode.md) — git-native mode isolation recipes
- [`03-jj-mode.md`](03-jj-mode.md) — jj mode isolation recipes
