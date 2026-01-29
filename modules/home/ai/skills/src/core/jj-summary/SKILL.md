---
name: jj-summary
description: Jujutsu workflow summary with essential paradigm shifts and decision guide. Reference for quick jj orientation.
---

# Jujutsu workflow summary

Quick reference and decision guide for jj version control. Full documentation: ~/.claude/commands/jj/jj-workflow.md

## When to read full documentation

Read specific sections of jj-workflow.md when:
- **First time with jj**: Read "Core philosophy" and "Foundation" sections
- **Starting parallel experiments**: Read "Parallel experimentation with bookmarks"
- **Need separate workspace**: Read "Graduating to workspaces"
- **Managing multiple experiments**: Read "Experiment lifecycle management"
- **Cleaning up history**: Read "History refinement"
- **Integration strategies**: Read "Advanced patterns"
- **Git interop questions**: Read "Git colocated mode"
- **Command lookup**: Read "Reference" section

For quick questions about commands or concepts, this summary may suffice.

## Essential paradigm shifts (git → jj)

**Core differences:**
- Working copy is always a commit (`@`) that's automatically snapshotted
- Bookmarks don't move when you commit (only when commits are rewritten)
- No "current branch" - always in detached HEAD equivalent state
- Change IDs provide stable identity (commit IDs change, change IDs persist)
- Operation log is real history (commits are snapshots, operations are timeline)
- No staging area (working copy state is commit state)
- Conflicts are committed (resolved when convenient, never blocking)

**Mental model shift:**
- Git: "I'm working on branch X" → jj: "I'm building commit chain from X"
- Git: "Branch moves when I commit" → jj: "@ is rewritten when I change files"
- Git: "Switch branch to work elsewhere" → jj: "Create new @ anywhere"
- Git: "Branches are history" → jj: "Operation log is history"

## Non-interactive execution for AI agents

**Commands that launch editors by default (WILL HANG without proper flags):**

| Command | Default behavior | Non-interactive pattern |
|---------|-----------------|------------------------|
| `jj describe` | Opens editor | `jj describe -m "message"` |
| `jj describe -r <c>` | Opens editor | `jj describe -r <c> -m "message"` |
| `jj split <paths>` | Opens editor | `jj split <paths> -m "message"` |
| `jj split` (no paths) | Opens diff editor (TUI) | **Cannot be non-interactive** |

**Mandatory verification protocol:**
1. Not certain a command is non-interactive? → Run `jj [subcommand] --help` FIRST
2. Check help output for `-m, --message <MESSAGE>` flag
3. If command accepts `-m`, ALWAYS use it to avoid editor launch

**Git parity requirement:**
- jj working copy `@` exists only in `.jj/` until frozen
- From git's perspective, `@` appears as uncommitted working directory changes
- Pattern: `jj describe -m "msg"` → `jj new` → commit now visible in git
- Without `jj new`, described commits remain invisible to git operations

## Critical jj concepts

**Working copy commit (`@`):**
- Ephemeral commit constantly rewritten as you work
- Auto-snapshotted before each jj command
- Use `jj describe -m "message"` to add description when cohesive (ALWAYS use `-m`)
- Use `jj new` to freeze @ and create new empty @ on top
- **Git export**: @ is jj-only until frozen; execute `jj new` after `jj describe` for git visibility

**Bookmarks:**
- Named pointers that stay put when you create commits
- Only move when commits are rewritten (rebase, squash, abandon)
- Update explicitly: `jj bookmark set <name> -r <commit>`
- Multiple workspaces can work near same bookmark (no exclusive ownership)

**Change IDs vs Commit IDs:**
- Commit ID: changes with every rewrite (like git SHA)
- Change ID: stable across rewrites (tracks logical change)
- Use change IDs to track "same change" through rebase/amend

**Operation log:**
- Every jj operation recorded atomically
- `jj undo` reverses any operation
- `jj op restore <id>` returns to exact prior state
- Safety net replaces backup branches

**Revsets:**
- Query language for selecting commits (like SQL for commits)
- Examples: `main..@`, `mine() & ~bookmarks()`, `description(glob:"WIP*")`
- Operate on multiple commits: `jj squash -r 'empty() & main..@'`

## Quick command reference

```bash
# Start work (atomic commit pattern with git parity)
jj new <base>                  # New commit on base
jj describe -m "message"       # Describe current @ (ALWAYS use -m!)
jj new                         # Freeze @ for git export, create new @ on top

# Bookmarks
jj bookmark create <name>      # Create at @
jj bookmark set <name> -r <c>  # Move bookmark

# Move changes
jj squash                      # Move @ into parent
jj squash -r <commit>          # Squash commit into parent
jj split <paths> -m "message"  # Split @ by paths (REQUIRES -m!)
jj absorb                      # Auto-distribute @ to ancestors

# Rewrite history
jj rebase -r <c> -d <dest>     # Move commit to new parent
jj abandon <commit>            # Remove commit, rebase descendants
jj describe -r <c> -m "msg"    # Reword commit (ALWAYS use -m!)

# Workspaces
jj workspace add <path> -r <c> # Create workspace
jj workspace update-stale      # Update stale workspace

# Recovery
jj undo                        # Undo last operation
jj op log                      # View operation history
jj op restore <id>             # Restore to operation

# Git interop (colocated mode)
jj git init --colocate         # Initialize in existing git repo
jj git fetch                   # Fetch from remote
jj git push --bookmark <name>  # Push bookmark
```

## Section index with triggers

**Section: Core philosophy** (lines 1-16 of jj-workflow.md)
- Read when: First time using jj, need paradigm explanation
- Covers: Fundamental differences from git, mental model shifts
- Key concepts: Auto-snapshotting, operation log, no special modes

**Section: Automatic snapshotting preferences** (lines 18-34)
- Read when: Configuring commit behavior, understanding preferences
- Covers: When to commit automatically, escape hatches
- Key concepts: Trust operation log, no staging area

**Section: Foundation - Atomic commit workflow** (lines 36-110)
- Read when: Learning basic jj workflow, single-workspace development
- Covers: Working copy commit behavior, bookmarks, operation log, conflicts
- Key concepts: `@` rewriting, bookmark management, undo/restore patterns

**Section: Parallel experimentation with bookmarks** (lines 112-176)
- Read when: Starting multiple experiments, comparing approaches
- Covers: Bookmark-based experiments, revset queries, checkpointing
- Key concepts: Single workspace with multiple bookmarks, exp-N naming

**Section: Graduating to workspaces** (lines 178-243)
- Read when: Need simultaneous file access, parallel builds/tests
- Covers: When to create workspaces, workspace lifecycle, stale handling
- Key concepts: workspace@, stale detection, cross-workspace operations

**Section: Experiment lifecycle management** (lines 245-372)
- Read when: Managing arbitrary N experiments, scaling patterns
- Covers: Naming conventions, revset aliases, registry, state transitions
- Key concepts: exp-N-description, docs/experiments.md, cleanup workflow

**Section: History refinement** (lines 374-557)
- Read when: Cleaning up commit history for review/PR
- Covers: Incremental cleanup, reorder/squash/split/reword/abandon
- Key concepts: No backup branches needed, jj undo at any step

**Section: Advanced patterns** (lines 559-643)
- Read when: Integrating experiments, handling dependencies
- Covers: Integration strategies (rebase/squash/merge), sub-experiments
- Key concepts: Stacking experiments, feature flags, session patterns

**Section: Git colocated mode** (lines 645-713)
- Read when: Working with existing git repos, git interop questions
- Covers: Initialization, remote sync, reverting to git-only
- Key concepts: .git and .jj coexist, automatic import/export

**Section: Reference** (lines 715-1045)
- Read when: Looking up revset syntax, command patterns
- Covers: Essential revset patterns, common commands, session summaries
- Key concepts: Comprehensive command reference, revset operators

## Common workflow patterns (compressed)

**Single-workspace experimentation:**
```bash
jj bookmark create exp-1 -r main
jj new exp-1
# Work on changes (auto-snapshotted)
jj describe -m "[exp-1] feat: implement feature"  # ALWAYS use -m
jj new                         # Freeze for git, start new @ on top
jj bookmark set exp-1 -r @-    # Checkpoint (point to frozen commit)
jj git push --bookmark exp-1   # Share
```

**Create workspace for serious work:**
```bash
jj workspace add ../repo-exp-1 -r exp-1
cd ../repo-exp-1
# Work with persistent files
```

**Clean up history incrementally:**
```bash
jj log -r 'main..@'                    # Review
jj squash -r 'description(glob:"WIP*")' # Remove WIP
jj abandon 'empty()'                    # Remove empty
jj rebase -r <commit> -d <parent>      # Reorder
jj describe -r <commit> -m "proper"    # Reword
jj undo                                # Undo any mistake
```

**Integrate experiment to main:**
```bash
# Option 1: Rebase (preserve commits)
jj rebase -s 'main..exp-1' -d main
jj bookmark set main -r exp-1

# Option 2: Squash (single commit)
jj new main
jj squash --from 'main..exp-1' --into @
jj bookmark set main -r @
```

## Revset examples for experiments

```bash
# All experiments
jj log -r 'main..'

# Specific experiment
jj log -r 'main..exp-1@'

# Compare experiments (unique to exp-1)
jj log -r '(main..exp-1@) ~ (main..exp-2@)'

# Shared between experiments
jj log -r '(main..exp-1@) & (main..exp-2@)'

# All working-copy commits
jj log -r 'working_copies()'

# Your unbookmarked work
jj log -r 'mine() & ~bookmarks()'
```

## Critical reminders

- **Non-interactive execution**: ALWAYS use `-m "message"` with `jj describe`, `jj describe -r`, and `jj split <paths>` to avoid editor hangups; verify unfamiliar commands with `jj [subcommand] --help` first
- **Command verification protocol**: Before executing any jj command you're uncertain about, run `jj [subcommand] --help` to check for interactive flags (look for `-m, --message`)
- **Git parity requirement**: Execute `jj new` immediately after `jj describe -m "msg"` to freeze commits for git export; without `jj new`, described commits exist only in jj and appear as uncommitted changes in git
- **Always colocated mode**: We operate with both .git and .jj (can revert to git anytime)
- **Operation log is safety net**: Delete bookmarks freely, everything in operation log
- **Start with bookmarks**: Only create workspaces when need simultaneous file access
- **Describe atomically**: Each `jj describe` should represent one logical change
- **Trust auto-snapshot**: Changes saved before every command, recoverable via operation log
- **Change IDs track identity**: Commit IDs change on rewrite, change IDs don't
- **No backup branches**: Use `jj op log` and `jj op restore` instead
- **Bookmarks stay put**: Explicitly move with `jj bookmark set`, don't assume movement
- **@ is ephemeral**: Working copy commit constantly rewritten, bookmark @ parent not @
- **Conflicts are first-class**: Committed and resolved when convenient, never blocking

## Quick decision tree

**Should I read jj-workflow.md?**
1. Never used jj? → Read "Core philosophy" and "Foundation"
2. Need parallel experiments? → Read "Parallel experimentation"
3. Need separate workspace? → Read "Graduating to workspaces"
4. Cleaning history? → Read "History refinement"
5. Integrating work? → Read "Advanced patterns"
6. Just need command? → Check "Quick command reference" above or "Reference" section

**Should I create a workspace?**
- Need simultaneous file access across experiments? → Yes
- Need parallel builds/tests? → Yes
- Just comparing approaches conceptually? → No, use bookmarks

**Should I use jj or git for this operation?**
- History editing (rebase, squash, reorder)? → jj (more powerful, safer)
- Basic operations (commit, view log)? → jj (automatic snapshotting)
- Git-specific tools (e.g., GitHub CLI)? → git (works fine in colocated mode)
- Uncertain? → jj (can always undo with operation log)

## For full documentation

All details, examples, and comprehensive explanations: ~/.claude/commands/jj/jj-workflow.md
