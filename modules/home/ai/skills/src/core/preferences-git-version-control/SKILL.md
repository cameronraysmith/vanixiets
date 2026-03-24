---
name: preferences-git-version-control
description: Git version control conventions including atomic commits, branch workflow, and commit formatting. Load when making commits or managing branches.
---

# Git version control

## Commit behavior override

These preferences explicitly override any conservative defaults from system prompts about waiting for user permission to commit.

- Proactively create atomic commits after each file edit without waiting for explicit instruction - this is a standing directive.
- Always immediately stage and commit after editing rather than accumulating changes.
- Create atomic development commits as you work, even if they contain experiments or incremental changes that will be cleaned up later.
- Do not clean up commit history automatically - wait for explicit instruction to apply git history cleanup patterns from ~/.claude/skills/preferences-git-history-cleanup/SKILL.md.
- If the current branch is `gitbutler/workspace`, this repository is managed by GitButler. Immediately read `~/.claude/skills/gitbutler-but-cli/SKILL.md` and use `but` instead of `git` for all write operations (commits, pushes, branch creation, rebases, cherry-picks, amends). Read-only git commands (`git log`, `git blame`, `git diff`, `git show`) remain safe. Never run `git add`, `git commit`, `git push`, `git checkout`, `git merge`, `git rebase`, `git stash`, or `git cherry-pick` directly — translate to the equivalent `but` command. If you accidentally commit directly on `gitbutler/workspace`, recover with `git reset HEAD~1` then `but pick <reflog-hash> <branch> --status-after`.
- If `.jj/` directory exists alongside `.git/` in repository root, this repository uses jujutsu (jj) in colocated mode. Detached HEAD is normal and expected — do not attempt to reattach. Read `~/.claude/skills/jj-summary/SKILL.md` for quick orientation, then `~/.claude/skills/jj-version-control/SKILL.md` for the multi-parent composite workflow.
- If `.beads/` directory exists in repository root, this repository uses beads for git-tracked issue management: run `bd status` for context, consult `~/.claude/skills/issues-beads-prime/SKILL.md` for quick reference or `~/.claude/skills/issues-beads/SKILL.md` for comprehensive workflows.

### Proactive beads maintenance

When `.beads/` exists, maintain the issue graph alongside git commits:

- Orient with `bd status` at session start
- Mark issues `in_progress` when starting work; update descriptions when assumptions prove incorrect
- Create issues discovered during work and wire with `bd dep add <new> <current> --type discovered-from`
- Close with implementation context: `bd close <id> --reason "Implemented in $(git rev-parse --short HEAD)"`
- Check what's unblocked after completion; consider updating newly-ready issues with helpful context
- After completing a batch of mutations, push to the dolt remote for backup: `bd dolt push`

For beads usage conventions (epic structure, status management, closure policy), see the conventions section of issues-beads-prime.
Consult `~/.claude/skills/issues-beads-prime/SKILL.md` for command quick reference.

## VCS terminology glossary

This glossary defines abstract terms for version control operations that remain stable across tools.
Each abstract term maps to concrete equivalents in the four VCS tools used across this repository's skill set.

| Abstract term | Git | GitButler | Jujutsu (jj) | Gerrit |
|---|---|---|---|---|
| Branch stack | Feature branch (single) or graphite stack | Stack (chain of stacked branches sharing one linear history) | Bookmark chain | Topic (group of related changes) |
| Branch boundary | N/A (one branch = one unit) | Branch name within a stack, inserted via `but branch new -a` | Change boundary (each change is a boundary) | Change boundary |
| Change set | Commits on a branch between two merge points | Commits within one branch segment of a stack | Single change (jj's atomic unit) | Patchset (version of a change) |
| Working branch | Checked-out branch (`git checkout`) | Applied branch (multiple coexist in workspace) | Current change (`@`); multi-parent `@` for multi-parent working copy | Checked-out change |
| Integrate to main | Fast-forward merge (`git merge --ff-only`) | Fast-forward merge of stack tip | `jj git push` + bookmark advance | Submit (merge to target) |
| Isolate work | `git worktree add` or `git checkout -b` | `but branch new` (independent stack) or `but branch new -a` (stacked segment) | `jj new` (new change) | New change |
| Reorder history | `git rebase -i` | `but move` (within stack), `but squash`, `but reword` | `jj rebase`, `jj squash` | Amend patchset |
| Shelf/stash | `git stash` | `but unapply` (removes branch from workspace, preserves commits) | `jj new` (just start new work, old change preserved) | N/A |

All skills in this repository use the abstract terms from the left column when describing VCS operations.
The git-preferences skill translates these to concrete commands based on the active VCS mode: git-native (default), GitButler (when `gitbutler/workspace` is checked out), or jj (when `.jj/` exists).
Skills that need VCS operations should delegate to git-preferences rather than embedding tool-specific commands.
This decoupling ensures skills remain correct across all three modes without conditional logic of their own.

### Naming modes for branch stacks

When a beads epic is active (`.beads/` exists and an epic is in progress), branch stacks correspond to epics and branch boundaries correspond to issues:

- Stack name: `{epic-ID}-descriptor` (e.g., `nix-f85-gitbutler-adoption`)
- Branch name at each boundary: `{issue-ID}-descriptor` (e.g., `nix-f85-1-terminology-glossary`)

When working ad hoc (no beads, or outside an epic), stacks and boundaries are named descriptively:

- Stack name: descriptive (e.g., `gitbutler-skill`)
- Branch name at each boundary: descriptive (e.g., `fix-gitbutler-version`)

Both modes use identical mechanical operations.
The difference is purely in naming conventions and whether `bd` lifecycle commands accompany the VCS operations.

## Escape hatches

Do not commit if:

- Current directory is not a git repository
- User explicitly requests discussion or experimentation without committing

## Branch workflow

File edits on main/master are blocked by the `enforce-branch-before-edit` hook.
Before attempting to edit any files, create a working branch to which you will commit your changes.
If you haven't already, invoke `/issues-beads-prime` for beads command reference before proceeding with any editing.

In jj mode, this hook is unnecessary.
Anonymous chains are first-class and never garbage-collected.
Create bookmarks when initiating a second chain or when working on beads epics — see the bookmark creation threshold in `~/.claude/skills/jj-version-control/SKILL.md`.

Whenever you are working on a beads issue or epic, check the current branch name first.
If it does not correspond to the issue you're working on, pause to ask the user whether to create or switch to a matching branch before proceeding.

Branch naming follows the pattern `ID-descriptor` in lowercase kebab-case, where ID references the issue tracker:

- **Beads repos** (`.beads/` exists): Use the beads issue ID with dots replaced by dashes.
  Examples: `nix-pxj-ntfy-server` (epic), `nix-pxj-4-deploy-validate` (task under epic), `nix-i37-fix-flake-lock` (standalone issue).
- **GitHub-only repos**: Use the issue or PR number.
  Examples: `42-refactor-auth`, `1337-add-feature`.

Never use forward slashes in branch names as they break compatibility with URLs, docker image tags, and other tooling that embeds branch names.

Create a new working branch when your next commits won't match the current branch's ID-descriptor:

- Example: current branch is `nix-pxj-4-deploy-validate` but you discover issue `nix-di8` needs fixing first → create `nix-di8-fix-dependency`
- When the unit of work is complete and tests pass, offer to integrate to main

To isolate work in a new branch:

- **Git-native mode:** `git checkout -b ID-descriptor` to branch off current HEAD, or `git worktree add` for bead-tracked isolation (see working branch isolation below).
- **GitButler mode:** `but branch new ID-descriptor` to create a new independent stack, or `but branch new ID-descriptor -a <commit>` to split an existing stack at a branch boundary.
- **jj mode:** `jj new <base>` to create a new change from a single base, or `jj new bookmark-a bookmark-b` to create a multi-parent working copy with multiple bookmarks merged in one working tree.

Default bias: if in doubt whether work is related, create a new branch — branches are cheap, tangled history is expensive.

### Working branch isolation

Implementation work uses isolated working contexts to prevent tangled history.
The mechanism differs by VCS mode.

#### Git-native mode

Bead implementation work uses worktrees rooted in `.worktrees/` at the repository root.
This directory must be listed in `.gitignore`.

The worktree model has two tiers: epic worktrees for coordination and issue worktrees for implementation.

##### Epic branches

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

##### Switching focus

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

##### Issue worktrees

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

##### General rules

Always specify an explicit start-point when creating branches or worktrees.
Epic branches start from `main` (or from another epic's branch when stacking).
Issue worktrees branch from their parent epic's branch.
Without a start-point, git branches from whatever happens to be checked out, which may not be the intended base.

Use worktrees for bead-tracked work; use plain branches (`git checkout -b`) for non-bead or quick-fix work.

##### Direnv initialization in worktrees

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

#### GitButler mode

All branches coexist in a single workspace — no worktrees are needed.
Isolation comes from branch boundaries within and across stacks rather than filesystem separation.

##### Branch stacks as epics

Each active epic corresponds to a branch stack.
Create a new stack for a new epic:

```bash
but branch new {epic-ID}-descriptor
```

When one epic depends on another, stack it on the parent epic's branch:

```bash
but branch move {epic-ID}-descriptor {parent-epic-ID}-descriptor
```

##### Issue branches within a stack

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

##### Switching focus

To shelve work on a stack and focus on another, use `but unapply` and `but apply`:

```bash
# Shelve the current stack
but unapply {branch-name}
# Apply a different stack
but apply {other-branch-name}
```

Unapplied stacks retain their commits and can be reapplied at any time.

##### Cross-stack commit reorganization

Move a commit from one branch to another within or across stacks:

```bash
but move <source-commit-id> <target-commit-id> --status-after
```

Commit IDs come from `but status -fv` or `but show <branch-id>`.

##### No direnv initialization needed

GitButler operates in a single working tree, so the repository root's direnv environment applies to all branches.

#### jj mode

jj provides a multi-parent working copy that achieves the same simultaneous multi-branch editing as GitButler's applied-branches model.
All bookmarks coexist in a single working tree — no worktrees are needed.

##### Creating a multi-parent working copy

Create a working copy commit with multiple parent bookmarks:

```bash
jj new bookmark-a bookmark-b bookmark-c
```

The resulting `@` is a merge commit whose working tree merges all parent bookmarks.
Edits made in `@` can be routed to any parent bookmark.

##### Change routing

Route changes from the multi-parent `@` to the appropriate parent bookmark:

```bash
# Manual: squash specific changes into a named parent
jj squash --into <parent-bookmark>

# Automatic: distribute changes based on blame ancestry
jj absorb
```

`jj absorb` analyzes which ancestor last touched each modified line and routes changes automatically.
Use `jj squash --into` when changes belong to a specific parent that blame cannot determine.

##### Adding and removing parents

Modify the set of parent bookmarks in the multi-parent working copy:

```bash
# Add a parent bookmark
jj rebase -r @ -d 'all:(@- | new-bookmark)'

# Remove a parent bookmark
jj rebase -r @ -d 'all:(@- ~ removed-bookmark)'
```

The `all:` prefix ensures the revset resolves to multiple parents rather than a single ancestor.

##### Auto-rebase behavior

When a parent bookmark advances (via commits on that bookmark from another workspace or collaborator), jj automatically rebases `@` onto the updated parents.
This keeps the multi-parent working copy current without manual intervention.

##### Epic and issue mapping

Bookmarks correspond to epics or independent work streams.
Changes within each bookmark's chain correspond to issues.
This mapping parallels the git-native worktree model and the GitButler stack model, but without filesystem separation.

Create a bookmark per active epic following the standard naming convention:

```bash
jj bookmark create {epic-ID}-descriptor
```

Build changes as a chain descending from each bookmark.
Each change in the chain corresponds to an issue within the epic:

```bash
# Start work on an issue within the epic
jj new {epic-ID}-descriptor
jj describe -m "feat: implement issue description"
# edit files...
jj new  # freeze and start next issue
```

When working across multiple epics simultaneously, create a multi-parent working copy compositing the active epic bookmarks:

```bash
jj new {epic-a}-descriptor {epic-b}-descriptor
```

Route changes from the multi-parent `@` to the appropriate epic bookmark:

```bash
# Automatic: distribute changes by blame ancestry
jj absorb

# Manual: route specific changes to a named epic
jj squash --into {epic-b}-descriptor
```

##### Subagent dispatch in jj mode

In jj mode, subagents do not create bookmarks or worktrees.
All agents — including parallel agents — edit files directly in the shared `@` working copy.
The orchestrator routes changes to the correct chain via `jj absorb` or `jj squash --into` after each subagent completes.

Coordination protocol: atomic one-file changes, periodic `jj log` review, prompt routing to keep `@` clean.
Subagent dispatch prompts specify which files to edit and the target chain context but do not include jj routing commands.
See the parallel agent coordination protocol in `~/.claude/skills/jj-version-control/SKILL.md` for the full model.

##### Completing issues and epics

When an issue is complete, close the bead:

```bash
bd close {issue-ID} --reason "Implemented in $(jj log -r '{epic-ID}-descriptor' --no-graph -T 'commit_id.short(8)')"
```

To merge a completed epic to main, advance the main bookmark:

```bash
jj new
jj bookmark set main -r @-
jj git push --bookmark main
jj bookmark delete {epic-ID}-descriptor
```

##### No direnv initialization needed

jj multi-parent working copies operate in a single working tree, so the repository root's direnv environment applies to all parent bookmarks.

##### GitButler equivalence mapping

| GitButler | jj multi-parent working copy |
|---|---|
| Applied branches | Parent bookmarks of multi-parent `@` |
| `gitbutler/workspace` commit | Multi-parent `@` commit |
| `but commit --changes` | `jj squash --into` or `jj absorb` |
| `but unapply` | Remove parent from merge via `jj rebase -r @ -d 'all:(@- ~ bookmark)'` |
| `but apply` | Add parent to merge via `jj rebase -r @ -d 'all:(@- | bookmark)'` |
| Branch stacks | Bookmark chains (linear descendant sequences) |
| `but move` (cross-stack) | `jj squash --from <src> --into <dst>` |

### Fast-forward-only merge policy

All merges to main must be fast-forward.
This preserves linear history, making bisect, revert, and log traversal straightforward.
The `git config merge.ff only` guardrail rejects non-fast-forward merges automatically in both modes, serving as a safety net.

In git-native mode, rebase the branch onto main before merging:

```bash
git checkout {branch}
git rebase main
# resolve any conflicts, then:
git checkout main
git merge --ff-only {branch}
```

Never use `git merge` without `--ff-only` on main.
If a branch has diverged and rebase produces conflicts, resolve them during the rebase rather than creating a merge commit.

In GitButler mode, stacked branches are already linear by construction.
Fast-forward merge of the stack tip integrates all stacked segments at once.
Exit GitButler before merging to main: `but teardown`, then `git merge --ff-only`, then `but setup`.
Do not use `but merge` for this — it always creates merge commits and has no fast-forward mode.
See the "Stacked PRs with single fast-forward merge" and "Merging multiple independent stacks" recipes in `~/.claude/skills/gitbutler-but-cli/SKILL.md` for the full workflow.

In jj mode, the equivalent of fast-forward merge is bookmark advancement: `jj bookmark set main -r <chain-tip>`.
This is inherently linear — jj does not create merge commits for bookmark moves.
See the integration strategies section in `~/.claude/skills/jj-version-control/SKILL.md` for the full completion workflow.

### Stack management

Branch stacks mirror beads issue dependencies: when issues form a dependency chain (e.g., `nix-pxj.2` blocks `nix-pxj.3`), the corresponding branches should form a stack with matching parent-child relationships.
If you identify a reason to modify beads dependencies while working, evaluate and present a plan to reorder the branches associated with previously completed work in the stack, handling any conflicts that arise.

In git-native mode, use the graphite CLI (invoke as `graphite`, not `gt` as shown in official documentation) to manage stacks:

- `graphite log` — view branch stack relationships
- `graphite track` — register an existing branch with graphite, selecting its parent
- `graphite create -m "message"` — create a new branch stacked on current, with initial commit

In GitButler mode, native stack operations replace graphite entirely.
`but branch new -a`, `but branch move`, and `but move` provide all stack management without an external tool.
See `~/.claude/skills/gitbutler-but-cli/SKILL.md` for the full command reference.

## Merge strategy selection

Two strategies exist for integrating branches into main.
The choice depends on whether the project benefits from CI validation or historical change visibility for a given unit of work.

Fast-forward merge to main is the default.
Branch from main, work in atomic commits, rebase onto main, then `git merge --ff-only` and clean up the branch.
This suits new projects, straightforward changes, and early-stage repositories where the overhead of a pull request adds no value.
The fast-forward-only merge policy described above applies in all cases regardless of strategy.

The GitHub PR workflow is preferred when change visibility matters.
Mature repositories, public-facing changes, and collaborative projects benefit from PRs because the full changeset is referenceable as a single unit with discussion history.
PRs are also the appropriate path when CI workflow validation via PR checks provides meaningful confidence in the change, beyond what local testing alone offers.
Follow the PR creation protocol documented below when using this strategy.

When uncertain which strategy to use, ask the user.
The user can always override in either direction on a per-change basis.

## File state verification

Before editing any file, check for uncommitted changes:

- Related to current task: commit them first with appropriate message
- Unrelated or unclear: pause and propose commit message asking user for confirmation

In git-native mode, run `git status --short [file]` and `git diff [file]`.
In GitButler mode, `but status -fv` provides richer state including branch assignment and CLI IDs for each changed file.
In jj mode, `jj status` and `jj diff` show working copy state. There is no staging area — all tracked file changes are the commit.

## Atomic commit workflow

Atomic commits in this workflow mean one commit per file with exactly one logical change.
Each commit is the smallest meaningful unit that can be independently reverted, cherry-picked, or bisected.
This is not atomic in the database sense of bundling multiple operations together, but atomic as the finest practical granularity for version control.

Make one logical edit per file (even when using MultiEdit to edit multiple files in parallel), then commit each file separately.
This eliminates mixed hunks by construction.

In git-native mode: edit file, `git add [file]`, verify with `git diff --cached [file]`, then `git commit -m "msg"`.

In GitButler mode: edit file, run `but status -fv` to get the file's CLI ID, then `but commit <branch> -m "msg" --changes <id> --status-after`.
The `--changes` flag provides explicit file selection equivalent to staging one file at a time.

In jj single-chain mode: edit one file, then immediately `jj describe -m "msg"` followed by `jj new` to freeze the change and start a new empty `@`.
This is the jj equivalent of `git add [file] && git commit` — the `describe` + `new` cycle is the atomic commit boundary.
Without `jj new`, the next edit accumulates into the same change, breaking atomicity.
If multiple files were edited before freezing, use `jj split <path> -m "msg"` to separate them into atomic changes after the fact.

In jj multi-parent composite mode: edit one file, then `jj describe -m "msg"` followed by `jj squash --into <target-parent>` to route the change to the correct parent chain, or `jj absorb` to auto-distribute based on blame ancestry.
Do not use `jj new` in multi-parent mode — it creates a new change descending from the composite `@` rather than routing to a parent chain.
See the edit-route cycle in `~/.claude/skills/jj-version-control/SKILL.md` for the full workflow.

## Handling pre-existing mixed changes

If you encounter a file with multiple distinct logical changes already present:

- Preferred: inform the user that the file contains mixed changes and pause for them to stage interactively with `git add -p [file]` (this is a human-delegated action; the AI does not execute interactive staging)
- Alternative: construct patch files manually using `git diff [file]` and `git apply --cached [patch]`, but only when hunks have clear boundaries, are semantically distinct, and you can confidently construct valid unified diff format

## Commit formatting

- Succinct conventional commit messages for semantic versioning
- Test locally before committing when reasonable
- Never use emojis or multiple authors in commit messages
- Never @-mention usernames or reference issues/PRs (#NNN, URLs) in commit messages - causes unwanted notifications and immutable backlinks
- Fixup commits: prefix with "fixup! " followed by exact subject from commit being revised (use only once, not repeated)
- Stage one file per commit after verifying exactly one logical change.
  In git-native mode: `git add [file]`.
  In GitButler mode: use `--changes <id>` on `but commit` to select specific files by CLI ID.
- In git-native mode, never use `git add .`, `git add -A`, or interactive staging (`git add -p`, `git add -i`, `git add -e`) — interactive commands hang in AI tool execution (the human may run `git add -p` when delegated; see "Handling pre-existing mixed changes").
  In GitButler mode, this concern does not apply — `but commit` requires explicit `--changes` selection by design.
  In jj mode, there is no staging area — all working copy changes are the commit.
  Use `jj split <paths> -m "msg"` to separate concerns within a single change when multiple logical edits accumulate in `@`.

## History investigation with pickaxe

When searching for when/why code changed, use git pickaxe options strategically to avoid context pollution:

Default search strategy (focused):

- Use `-G"pattern"` to find commits where lines matching pattern were added/removed
- Use `-S"string"` to find commits where the occurrence count of string changed (not in-file moves)
- Examine specific files: `git show <hash> -- <file>` or `git diff <base>..<hash> -- <file>`

Avoid `--pickaxe-all` by default:

- Without `--pickaxe-all`: shows only files matching the search (optimal for AI context)
- With `--pickaxe-all`: shows entire changeset if any file matches (causes information overload)
- Only use `--pickaxe-all` when broader context is explicitly needed to understand why a change was made

Key differences:

- `-S"numpy"` finds commits where "numpy" was added/removed (count changed)
- `-G"numpy"` finds commits where lines containing "numpy" were modified
- `-S` misses refactors that move text without changing occurrence count
- `-G` is more expensive but catches structural changes

Practical examples:

- `git log -G"dependencies" --oneline` then `git show <hash> -- <file>` (targeted)
- `git log -S"function_name" --pickaxe-regex --oneline` (exact occurrences)
- Avoid `git log -S"pattern" --pickaxe-all -p` unless user needs full changeset context

## Session commit summary

After creating commits, provide a git command listing session commits: `git log --oneline <start-hash>..<end-hash>` using the commit hash from gitStatus context as start and `git rev-parse HEAD` as end. Use explicit hashes, not symbolic references, to ensure command remains valid after subsequent commits.

In jj mode: `jj log --no-graph -r 'main@origin..main' -T 'separate(" ", change_id.short(8), description.first_line()) ++ "\n"'`

## GitHub PR and Issue creation safety

GitHub's immutability policies require careful workflow to avoid permanent unwanted records:

- PR and Issue titles and descriptions cannot be edited after creation
- GitHub will not delete PRs or Issues without proof of sensitive data

Always use placeholder content in immutable fields, then update mutable fields after human review.

### PR creation protocol

Create PRs in draft mode with generic placeholder content:

```sh
gh pr create \
  -d \
  -a "@me" \
  -B main \
  -t "[conventional commits-formatted terse PR title]" \
  -b ""
```

After creation, provide follow-up commands for human review:

- Update PR title using `gh pr edit <number> --title "conventional: commits format"`
- Add actual description as second comment using `gh pr comment <number> --body "markdown description"`
- Never edit the immutable PR description field created at PR creation time
- Wait for user approval before executing

### Issue creation protocol

Apply identical safety patterns to `gh issue create`:

- Create with placeholder title and "empty" body
- Provide follow-up commands for title update and comment-based description
- Never edit the immutable Issue description field

### Cross-reference safety

Include `www` in GitHub URLs to prevent automatic backlinking:

- Use: `https://www.github.com/org/repo/issues/123`
- Avoid: `https://github.com/org/repo/issues/123` (creates immediate backlink)
- User removes `www` after confirming reference is intentional

### Uncertainty protocol

When uncertain about any aspect of PR or Issue creation:

1. Pause execution
2. Present proposed creation command with placeholders
3. Show intended title and description separately
4. Provide follow-up commands for mutable field updates
5. Await user confirmation

This ensures immutable GitHub records stay generic while preserving user control over deletable content.
