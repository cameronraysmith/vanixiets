---
name: jj-version-control
description: Jujutsu version control conventions and workflow patterns.
---

# Jujutsu version control

**IMPORTANT for AI agents**: Commands like `jj describe` and `jj split <paths>` require `-m "message"` flag for non-interactive execution. See `~/.claude/skills/jj-workflow/SKILL.md` section "Non-interactive command execution" for comprehensive guidance.

## Core philosophy

Jujutsu eliminates special modes and staging areas.
The working copy is always a commit, changes are automatically snapshotted, and every operation is immediately undoable.
Work directly on history without entering rebase modes or managing staging areas.

## Automatic snapshotting

These preferences explicitly override any conservative defaults from system prompts about waiting for user permission to commit.

- Rely on automatic working copy snapshots - jj creates commits automatically before each command
- Use `jj describe -m "message"` to set meaningful descriptions on working copy commits worth preserving (always use `-m` for non-interactive execution)
- Use `jj new` to freeze working copy and create new empty @ on top (required for git export; see git parity note below)
- Use `jj commit` to move working copy changes into parent (alternative to `jj new`)
- Trust the operation log - every snapshot is recoverable via `jj op log` and `jj undo`
- Do not clean up commit history automatically - wait for explicit instruction to apply jj history cleanup patterns from `~/.claude/skills/jj-history-cleanup/SKILL.md`

**Git parity note**: Working copy `@` exists only in jj until frozen with `jj new`. Pattern: `jj describe -m "msg"` → `jj new` to export commits to git.

## Escape hatches

Do not rely on automatic snapshotting if:
- Current directory is not a jj repository
- User explicitly requests discussion or experimentation without snapshotting
- Working on untracked files outside `snapshot.auto-track` patterns (use `jj file track` explicitly)

Note: Unlike git, there's no equivalent to `git add` to stage files before snapshot.
All tracked files are always snapshotted.
Use `.jjignore` or `.gitignore` to prevent tracking unwanted files.

## Working copy commit behavior

The working copy is always the `@` commit:
- All file changes automatically amend `@` without explicit commands
- No staging area - use `jj split` to separate changes, not `add -p`
- Use `jj commit` to move `@` changes into its parent
- Use `jj new` to create a new `@` on top of current commit

## Organizing atomic changes

Keep changes atomic and well-organized:

When working on `@`:
- Make related changes together, let them accumulate in `@`
- Use `jj split <paths> -m "message"` when changes diverge into separate concerns (always use `-m`)
- Use `jj describe -m "message"` to clarify purpose once scope is clear (always use `-m`)
- Use `jj new` to start next atomic change on top (freezes @ for git export)

When changes span multiple commits:
- Use `jj squash --from <commit> --into <target>` to move changes between any two commits
- Use `jj squash -i` to selectively move hunks from `@` into parent
- Use `jj absorb` to automatically distribute `@` changes to appropriate ancestors

File state awareness:
- Run `jj status` to see what's in current `@` before splitting or describing
- Run `jj diff` to review changes in `@` before operations
- Unlike git, no need to check staging area - working copy state is the commit state

## Session detection

When an agent detects `.jj/` alongside `.git/` in a repository root, jj colocated mode is active.
Detached HEAD is normal and expected in this configuration — do not attempt to reattach it.
The combined signal means the agent should adopt the jj workflow described in this skill, with the multi-parent composite model as the default operating mode for sessions with multiple active chains.

For quick command orientation, see `~/.claude/skills/jj-summary/SKILL.md`.
For comprehensive command reference, see `~/.claude/skills/jj-workflow/SKILL.md`.
For git-mode equivalents and beads integration, see `~/.claude/skills/preferences-git-version-control/SKILL.md`.
For beads command quick reference, see `~/.claude/skills/issues-beads-prime/SKILL.md`.

## Bookmark workflow

Bookmarks are named pointers that don't move automatically with new commits.

Bookmark management:
- Bookmarks stay on their target when you create new commits (unlike git branches)
- Update bookmarks explicitly: `jj bookmark set <name> -r <commit>`
- Always work in "detached HEAD" state — this is normal in jj
- Create bookmarks for important points: `jj bookmark create <name>`

Integration with issue tracking:
- Use bookmark names like `issue-N-descriptor` for clarity
- When work diverges from current bookmark's purpose, create new bookmark at current `@`
- Example: bookmark is "issue-42-auth" but fixing unrelated bug → `jj bookmark create issue-58-logging`

Default bias: bookmarks are cheap, use them liberally to mark important commits.

### Bookmark creation threshold

Unlike git, where the `enforce-branch-before-edit` hook forces branching before any work, jj anonymous chains are first-class and never garbage-collected.
The trigger for bookmark creation is chain differentiation, not the first edit.

Three tiers govern when bookmarks become necessary:

1. *Single chain, ad hoc work*: no bookmark needed.
   Work on an anonymous chain descending from main.
   When done, advance main: `jj bookmark set main -r @-`.

2. *Second chain initiated*: bookmarks become required for both chains.
   Bookmark the existing chain tip, create a new chain from main, bookmark its tip, then create a multi-parent `@` over both.

3. *Beads epic session*: create bookmarks at session start following the `{epic-ID}-descriptor` naming convention.

The discipline is "create bookmarks at the moment you need to distinguish chains" — not "always create a bookmark before working."

## Operation log and recovery

Every jj operation is atomic and recorded:

Undo operations:
- `jj undo` - undo last operation (any operation, not just commits)
- `jj op log` - view complete operation history
- `jj op restore <id>` - restore repo to exact prior state
- `jj op show <id>` - see what an operation changed

Recovery patterns:
- Made mistake in last operation: `jj undo`
- Made mistake several operations ago: `jj op log` then `jj op restore <id>`
- Want to undo operation N but keep operation N+1: `jj op restore` to N-1, then manually redo N+1
- Concurrent operations created divergence: inspect with `jj log` and resolve with `jj bookmark set`

The operation log is your safety net - use it fearlessly.

## Conflict management

Conflicts are first-class citizens, committed and resolved when convenient:

Conflict workflow:
- Operations never fail due to conflicts - conflicts are committed with "conflict" marker
- Continue working on other commits while conflicts exist
- View conflicted commits: `jj log -r 'conflict()'`
- Resolve when ready: `jj new <conflicted-commit>`, fix files, `jj squash` resolution back
- Or resolve in place: `jj edit <conflicted-commit>`, fix files (automatically amends)

Conflict tools:
- `jj resolve` - launch merge tool for each conflict
- `jj resolve --list` - see all conflicts in current commit
- Conflict markers in files are automatically tracked - edit them directly or use merge tools

Never blocked by conflicts - they're just another commit state to handle when convenient.

## Change organization

Move changes between commits fluidly without special modes:

Squashing and moving:
- Move `@` into parent: `jj squash`
- Move specific files into parent: `jj squash <files>`
- Interactive squash: `jj squash -i` (choose hunks)
- Move between any commits: `jj squash --from <src> --into <dest>`
- Auto-distribute changes: `jj absorb` (moves changes to commits that last touched those lines)

Splitting and extracting:
- Split by paths (non-interactive): `jj split <paths> -m "message"` (always use `-m`)
- Split specific commit by paths: `jj split -r <commit> <paths> -m "message"`
- Create new commit on top: `jj new <commit>`
- Move working copy to new commit: `jj commit`

Editing commits:
- Edit commit directly: `jj edit <commit>` (checkout commit, changes amend it)
- Edit without checkout: `jj diffedit -r <commit>`
- Change description: `jj describe -r <commit> -m "message"`
- Duplicate commit: `jj duplicate <commit>`

All operations execute immediately and descendants auto-rebase.

## Revset-based workflows

Use revsets to operate on multiple commits:

Common revset patterns:
- Select by description: `jj log -r 'description(glob:"WIP:*")'`
- Select by author: `jj rebase -s 'author("name@example.com")' -d main`
- Select empty commits: `jj abandon 'empty()'`
- Select your commits not on bookmarks: `jj log -r 'mine() & ~bookmarks()'`
- Select conflicted commits: `jj log -r 'conflict()'`
- Select commits in range: `jj log -r 'A..B'` or `jj log -r 'B::A'`

Revset flags for rebase:
- `-r <revset>`: rebase only specified commits (not descendants)
- `-s <revset>`: rebase commit and all descendants
- `-b <revset>`: rebase commits reachable from revset but not from destination
- `-d <revset>`: destination (new parent)

Batch operations via revsets:
- Describe multiple: `jj describe -r 'author("alice")' -m "Alice's work"`
- Abandon multiple: `jj abandon 'description(glob:"tmp:*")'`
- Rebase multiple: `jj rebase -s 'mine() & ::@' -d main`

## Description conventions

- Use conventional commit format for descriptions that will be pushed
- Work-in-progress commits can have informal descriptions
- Use `jj describe -m ""` to clear placeholder descriptions
- Empty descriptions are fine for intermediate commits that will be squashed
- Update descriptions as changes evolve: `jj describe -r <commit> -m "new message"`

Description timing:
- Set descriptions on significant commits when their purpose is clear
- Leave WIP commits with empty or placeholder descriptions
- Batch update descriptions before pushing: `jj describe -r <commit>` opens editor

## History investigation

Use revsets and operation log for powerful history queries:

Finding changes:
- View evolution of single change: `jj evolog -r <commit>`
- Find when content changed: `jj log --patch -r 'file("path/to/file")'`
- Search in descriptions: `jj log -r 'description(glob:"*pattern*")'`
- Find commits touching paths: `jj log -r '~/path/to/file'` or `jj log path/to/file`
- Track bookmark movement: `jj log -r 'bookmark()' --op-log`

Operation archaeology:
- What changed in operation: `jj op show <id>`
- Diff between operations: `jj diff --from <op1> --to <op2>`
- Find when bookmark moved: `jj op log --op-diff` and search for bookmark name

Combined queries:
- Your changes to specific file: `jj log -r 'mine() & ~/path'`
- Recent changes by others: `jj log -r '~author("your@email") & @- ::@'`
- Abandoned commits in operation: `jj op show <id>` and look for "hidden" commits

## Bookmark synchronization

Coordinate with remotes explicitly:

Fetching and tracking:
- Fetch all remotes: `jj git fetch --all-remotes`
- Track remote bookmark: `jj bookmark track <name>@<remote>`
- Untrack remote bookmark: `jj bookmark untrack <name>@<remote>`
- View tracking status: `jj bookmark list` (shows `*` for out-of-sync bookmarks)

Pushing changes:
- Push bookmark: `jj git push --bookmark <name>`
- Push all changed bookmarks: `jj git push --all`
- Push all tracked: `jj git push --tracked`
- Create bookmark and push: `jj bookmark create <name> && jj git push --bookmark <name>`

Bookmark conflicts:
- Local and remote diverged: bookmark shows conflicted state in `jj bookmark list`
- Resolve by setting to desired target: `jj bookmark set <name> -r <target>`
- Or abandon one side: let operation log help you find the right target

## Session workflow pattern

Effective jj session structure:

Starting work:
1. Update from remote: `jj git fetch`
2. Review state: `jj log`
3. Create new commit: `jj new <base>` or work on existing `@`
4. Work freely - changes auto-snapshot

During work:
- Describe commits when purpose is clear: `jj describe -m "message"`
- Split when changes diverge: `jj split`
- Squash when changes belong together: `jj squash`
- Abandon mistakes immediately: `jj abandon <commit>` or `jj undo`

Preparing to push:
1. Review outgoing commits: `jj log -r 'main..@'`
2. Clean up descriptions: `jj describe -r <commits>`
3. Squash or split as needed
4. Set bookmark: `jj bookmark set <name> -r @`
5. Push: `jj git push --bookmark <name>`

After mistakes:
- Undo last operation: `jj undo`
- Check operation log: `jj op log`
- Restore to known good state: `jj op restore <id>`

## Session operation summary

After working session, provide operation summary: `jj op log --limit 20` to show recent operations.
This shows the actual work done, including undos and restores.

For commit-focused summary, use: `jj log --limit 10` to show recent commits on current branch.

When sharing work done, combine both:
- Operation summary: `jj op log --limit N` (where N covers session operations)
- Commit summary: `jj log -r 'bookmark()..@'` (commits not yet on any bookmark)

Use explicit operation IDs from session start if you noted them, otherwise count backwards from `@`.

## Multi-parent composite workflow

The multi-parent composite working copy is the default operating mode for any jj session with two or more active chains.
Single-chain mode is the exception, reserved for simple ad hoc work on one anonymous chain descending from main.

When multiple chains are active, the working copy commit `@` composites all active chains by descending from multiple parents.
This provides continuous integration feedback (conflicts between chains surface immediately as first-class conflicts in `@`), shared visibility (every operation sees the full integrated state), modular separation (each chain remains independently inspectable, pushable, and reviewable), and flexible integration (chains can merge to main individually or be linearized into a single chain).

### The edit-route cycle

All edits land in `@`.
The discipline is to route each completed change out of `@` into the correct parent chain, then verify the routing was correct.

The cycle proceeds as follows:

1. Edit files — changes accumulate in `@`
2. `jj describe -m "message"` — describe the change
3. Route the change:
   - `jj squash --into <chain>` for explicit routing to a named parent chain
   - `jj absorb` for blame-based auto-routing across all parent chains
4. `@` auto-rebases onto updated parents after routing
5. `jj log` — verify changes routed to the correct chain
6. Repeat

The invariant is that `@` is always empty or contains only in-progress work.
All completed changes live in their respective parent chains.

In single-chain mode, the cycle is simpler: `jj describe -m "message"` followed by `jj new` freezes the change and advances `@`.
Do not use `jj new` in multi-parent composite mode — it creates a new change descending from the composite `@` rather than routing to a parent chain.

### Conflict behavior in composite `@`

When parent chains contain conflicting changes, `@` displays first-class jj conflicts.
These conflicts are informational — they tell you the parent chains will conflict when merged.
You can resolve them in `@` (the resolution stays in `@` and may need re-resolution when parents change), continue working with conflict markers present, or resolve the underlying conflict in one of the parent chains directly.

Conflicts in `@` do not prevent work.
They are a continuous integration signal, not a blocking error.

### `jj absorb` scope and limitations

`jj absorb` works for modifications to existing lines by analyzing blame ancestry to determine which parent chain last touched each modified line.
It routes changes automatically based on this analysis.

`jj absorb` does not work for:
- New files (no blame history exists)
- Deleted files (no blame target)
- Hunks where blame is ambiguous (multiple ancestors modified the same lines)

For any case where `jj absorb` cannot route changes, fall back to `jj squash --into <chain>` for explicit routing.

### Parallel agent coordination

Multiple agents share one filesystem and edit files in the same `@`.
This is the intended model.
All agents see the integrated state of all active chains, reducing merge conflict risk.
Conflicts between concurrent edits are detected immediately as first-class jj conflicts.

Coordination protocol for parallel agents:
- Atomic one-file changes
- Periodic `jj log` review to verify routing
- Prompt `jj absorb` or `jj squash --into` so `@` does not accumulate unrouted changes
- If two agents edit the same file, resolve the conflict immediately, then describe, split, and absorb

The orchestrator routes changes to the correct chain via `jj absorb` or `jj squash --into` after each subagent completes.
Subagent prompts specify which files to edit and the target chain context but do not include jj routing commands.

### Adding and removing chains

Add a parent chain to the composite `@`:

```bash
jj rebase -r @ -d 'all:(@- | new-bookmark)'
```

Remove a parent chain from the composite `@`:

```bash
jj rebase -r @ -d 'all:(@- ~ removed-bookmark)'
```

The `all:` prefix is required to ensure the revset resolves to multiple parents rather than collapsing to a single common ancestor.
Without `all:`, jj would compute the nearest common ancestor of the revset members, producing a single-parent `@` instead of a multi-parent one.

### Teardown

To collapse back to a single-parent `@`, either iteratively remove parents using the removal command above, or reset directly:

```bash
jj new <single-bookmark>
```

This creates a fresh `@` descending from only the specified bookmark.

### Session persistence

Multi-parent `@` state persists across sessions.
When a new session detects an existing multi-parent `@` (visible via `jj log -r @` showing multiple parents), it should resume the composite workflow rather than starting fresh.
Run `jj log -r '@-+' -s` to identify the active parent chains and their bookmarks.
Check `jj status` and `jj log -r 'mutable() ~ @ ~ ::main'` to understand in-progress work before making changes.

### Integration strategies at completion

When chains are complete, three integration strategies are available:

*Separate PRs*: push each chain's bookmark independently.
Push all at once: `jj git push --bookmark chain-a --bookmark chain-b --bookmark chain-c`.
Or push one at a time: `jj git push --bookmark chain-a`.
Each pushed bookmark becomes a branch on the remote, suitable for PR creation via `gh pr create`.
When creating PRs, use the bookmark name as the head branch and main as the base:

```bash
jj git push --bookmark chain-a
gh pr create -d -a "@me" -B main -H chain-a -t "feat: description" -b ""
```

Follow the PR creation protocol in `~/.claude/skills/preferences-git-version-control/SKILL.md` for placeholder content and safety conventions.

*Linearize then PR*: rebase chains into a single linear sequence, then push as one bookmark.
Order matters: dependent chains come first (if chain-b depends on chain-a's changes, chain-a must precede chain-b in the linearized sequence), then independent chains in any order.

For each subsequent chain, find its base (the first change descending from main) and rebase it onto the previous chain's tip.
The procedure generalizes to N chains:

```bash
# Determine linearization order (dependent chains first)
# Chain A: main -> a1 -> a2 -> a3 (tip: chain-a bookmark)
# Chain B: main -> b1 -> b2 (tip: chain-b bookmark)
# Chain C: main -> c1 (tip: chain-c bookmark)

# Stack B onto A's tip
jj rebase -s b1 -d chain-a

# Stack C onto B's new tip
jj rebase -s c1 -d chain-b

# Result: main -> a1 -> a2 -> a3 -> b1 -> b2 -> c1
# Advance main and push
jj bookmark set main -r chain-c
jj git push --bookmark main
```

After linearization, exit multi-parent mode since the chains are now one linear sequence.
Use `jj new main` or `jj new chain-c` to reset `@` to a single parent.
Individual chain bookmarks can be deleted in the post-session cleanup.

*Direct merge to main*: advance the main bookmark to the chain tip.
Use `jj bookmark set main -r <chain-tip>` followed by `jj git push --bookmark main`.
This is the jj equivalent of fast-forward merge — jj does not create merge commits for bookmark moves.

## `jj revert` usage

`jj revert` creates a new change that applies the inverse of a given revision.
The command requires explicit placement via `--onto`, `--insert-after`, or `--insert-before`.

Create a revert as a child of the current `@`:

```bash
jj revert -r <change> --onto @
```

Insert a revert into a linear chain before `@`:

```bash
jj revert -r <change> --insert-before @
```

Insert a revert after the parent of `@` (equivalent to inserting before `@`):

```bash
jj revert -r <change> --insert-after @-
```

To test a revert non-destructively, apply it and then undo if the result is undesirable:

```bash
jj revert -r <change> --onto @
# inspect the result...
jj undo  # roll back if not what you wanted
```

## `jj tidy` safety

The `jj tidy` alias uses the revset `mutable() ~ @ ~ ::main`.
This abandons all mutable changes not in main's ancestry and not at `@`.

Before running `jj tidy`, always advance main to cover any work-in-progress you want to keep.
Preview what tidy will affect:

```bash
jj log -r 'mutable() ~ @ ~ ::main' -s
```

If tidy sweeps too broadly, recover with `jj undo`.

## Post-session cleanup

After advancing the main bookmark to the tip of completed work (whether from a single chain or a linearized multi-parent session), present a cleanup summary for user approval before executing.

Gather diagnostics:

```bash
# Orphaned/divergent changes (anonymous heads, divergent change IDs)
jj orphans

# Stale bookmarks (local bookmarks not tracking a remote, excluding main)
jj bookmark list | grep -v '@'

# Mutable changes outside main and @ (what tidy would sweep)
jj log -r 'mutable() ~ @ ~ ::main' -s

# Git-side merged branches (colocated mode)
git branch --merged main | grep -Ev '^[*]|^  main$'
```

Present a summary to the user structured as:

- Stale bookmarks to delete (and why each is stale — integrated into main, or orphaned)
- Changes that `jj tidy` would abandon (with descriptions, so the user can verify nothing valuable is swept)
- Git branches that `git prune-merged` would delete
- Any caveats specific to the session (e.g., chains that were not fully integrated, divergent changes that may need manual resolution, work-in-progress that should be preserved)

After user approval, execute in order:

```bash
jj bookmark delete <stale-bookmarks>
jj tidy
git prune-merged
jj gc
```

Do not execute cleanup automatically.
Always present the summary and wait for explicit approval.

## Integration with git repositories

### Initializing jj in existing git repository

To use jj with an existing git repository in colocated mode:

```bash
# Navigate to git repository
cd /path/to/git/repo

# Initialize jj in colocated mode
jj git init --colocate

# Verify setup
ls -la  # Should see both .git/ and .jj/ directories
jj log  # Shows git history imported into jj
```

The `--colocate` flag creates `.jj/` alongside `.git/` so both tools work on the same repository.
All git branches become jj bookmarks automatically.
From this point forward, use jj commands for history editing and git features work normally.

Alternative for new repositories:

```bash
# Clone git repo with jj (automatically colocated)
jj git clone <url> <directory>

# Or initialize new jj repo backed by git
jj git init --git-repo=.  # Creates .jj/ and .git/ in current directory
```

### Working in colocated repos

When working in colocated repos (`.git` and `.jj` siblings):

Colocated workflow:
- All jj bookmark operations automatically sync to git branches
- Run `jj git export` if you need explicit sync to git refs
- Run `jj git import` to import git changes (automatic in colocated repos)
- Git commands work directly on same repo - changes appear in `jj log`

Mixed tool usage:
- Prefer jj commands for history editing - they're more powerful and safer
- Use git commands for operations not yet in jj
- After git operations, check `jj log` to see imported changes
- `jj git` subcommands bridge any gaps

Pushing to git remotes:
- `jj git push` works identically to git push for bookmarks
- Remote bookmark tracking is automatic
- Git-specific features (like GitHub PRs) work normally with jj-managed bookmarks

## Beads integration

When `.beads/` exists alongside `.jj/` in a colocated repository, beads issue tracking integrates with jj bookmarks.

Bookmark naming for bead work follows the same `{ID}-descriptor` pattern used in git branch naming, with dots in bead IDs replaced by dashes.
For example, beads issue `nix-pxj.4` becomes bookmark `nix-pxj-4-deploy-validate`.

Beads IDs take precedence over the `exp-N-description` experiment naming convention when working on tracked issues.
Use experiment naming only for exploratory work not tied to a beads issue.

Worktrees are a git-only mechanism; jj uses bookmarks for branch-like semantics.
When in a jj-managed repo, create a bookmark for bead work rather than using `git worktree add`:

```bash
jj bookmark create {epic-ID}-descriptor
# work on issues as changes within the bookmark chain:
jj new {epic-ID}-descriptor
jj describe -m "feat: implement issue description"
# edit files...
jj new  # freeze and start next issue
jj git push --bookmark {epic-ID}-descriptor
```

When working across multiple epics simultaneously, create a multi-parent working copy:

```bash
jj new {epic-a}-descriptor {epic-b}-descriptor
# edit files in the shared @ working copy
jj absorb              # auto-route changes by blame
jj squash --into {epic-b}-descriptor  # manual routing
```

Subagent dispatch in jj mode: subagents edit files directly in the shared `@` working copy.
The orchestrator routes changes to the correct epic bookmark after the subagent returns.
See the parallel agent coordination protocol in the multi-parent composite workflow section above.

### Completing issues and epics

Issue-level completion within a chain:

1. The issue's changes are complete within the epic's bookmark chain.
2. Close the bead: `bd close {issue-ID} --reason "Implemented in $(jj log -r '{epic-ID}-descriptor' --no-graph -T 'commit_id.short(8)')"`
3. The epic bookmark already points to the chain tip (bookmarks follow rewrites automatically).
4. Continue the chain with new changes for the next issue.

Epic-level completion:

1. All issues within the epic are closed.
2. Advance main to the epic chain tip: `jj bookmark set main -r {epic-ID}-descriptor`
3. Delete the epic bookmark: `jj bookmark delete {epic-ID}-descriptor`
4. Push main: `jj git push --bookmark main`
5. Push beads state: `bd dolt push`
