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

## Bookmark workflow

Bookmarks are named pointers that don't move automatically with new commits.

Bookmark management:
- Bookmarks stay on their target when you create new commits (unlike git branches)
- Update bookmarks explicitly: `jj bookmark set <name> -r <commit>`
- Always work in "detached HEAD" state - this is normal in jj
- Create bookmarks for important points: `jj bookmark create <name>`

Integration with issue tracking:
- Use bookmark names like `issue-N-descriptor` for clarity
- When work diverges from current bookmark's purpose, create new bookmark at current `@`
- Example: bookmark is "issue-42-auth" but fixing unrelated bug → `jj bookmark create issue-58-logging`

Default bias: bookmarks are cheap, use them liberally to mark important commits.

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
When in a jj-managed repo, create a bookmark at the working copy for bead work rather than using `git worktree add`:

```bash
jj bookmark create {ID}-descriptor
# work, then push:
jj git push --bookmark {ID}-descriptor
```

After completing bead work, commit beads changes following the manual sync workflow and update the bookmark before pushing.
