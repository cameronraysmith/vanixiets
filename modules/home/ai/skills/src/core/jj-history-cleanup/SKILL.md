---
name: jj-history-cleanup
description: Jujutsu history cleanup patterns for rewriting and reorganizing change history.
disable-model-invocation: true
---

# Jujutsu history cleanup

**IMPORTANT for AI agents**: Commands like `jj describe -r` and `jj split <paths>` require `-m "message"` flag for non-interactive execution. See `~/.claude/skills/jj-workflow/SKILL.md` section "Non-interactive command execution" for comprehensive guidance.

## Purpose

Transform experimental development history into a clean, reviewable commit sequence where:

- Each commit is atomic: contains one logical change that builds/tests successfully
- Commits are logically ordered: dependencies come before dependents, related changes are grouped
- Intermediate commits are removed: no "WIP", "fix typo", "oops", or checkpoint commits
- Each commit description follows conventional commit format and accurately describes its diff

This prepares bookmarks for PR review by creating a clear narrative of what changed and why.

## Principle

Operations execute immediately and atomically.
No special modes, no interactive editors, no rebase sequences.
Every operation is recorded in the operation log and can be undone instantly with `jj undo`.
Work directly on history without preparation or mode switching.

## Core technique

Unlike git's batch rebase mode, jj operates on commits directly:

```bash
jj <command> -r <revset>  # Execute immediately on specified commits
```

All operations automatically rebase descendants.
Use the operation log (`jj op log`) as your safety net instead of backup branches.

## Operations

For detailed command mappings from git interactive rebase, see `~/.claude/skills/jj-git-interactive-rebase-to-jj/SKILL.md`.

### Reorder commits

Move commits to different positions in history:

```bash
# Move commit C before commit B (where C currently comes after B)
jj rebase -r C -B B

# Move commit C after commit A (where C currently comes before A or elsewhere)
jj rebase -r C -A A

# Move commit to new parent
jj rebase -r C -d <parent>

# Move entire subtree
jj rebase -s C -d <new-base>
```

Key insight: `-B` inserts before, `-A` inserts after, `-d` sets new parent directly.
Descendants of the moved commit automatically follow.

### Squash/fixup commits

Combine commits by moving changes between them:

```bash
# Squash commit into its parent (equivalent to git fixup)
jj squash -r <commit>

# Squash with specific message
jj squash -r <commit> -m "combined message"

# Squash commit into specific ancestor
jj squash --from <commit> --into <ancestor>

# Interactive squash (select hunks)
jj squash -i -r <commit>

# Squash all WIP commits into their parents
jj squash -r 'description(glob:"WIP:*")'
```

Source commit is emptied after squash and becomes hidden.
Use `--keep-emptied` if you need to preserve the commit shell.

### Drop commits

Remove commits from history:

```bash
# Abandon specific commit
jj abandon <commit>

# Abandon multiple commits by description
jj abandon 'description(glob:"tmp:*")'

# Abandon empty commits
jj abandon 'empty()'

# Abandon range of commits
jj abandon <start>::<end>
```

Abandoned commits become hidden.
Their descendants are automatically rebased onto the abandoned commit's parent(s).

### Reword commit descriptions

Change commit messages without touching content:

```bash
# Reword single commit (ALWAYS use -m for non-interactive)
jj describe -r <commit> -m "new description"

# Reword multiple commits by pattern
jj describe -r 'description(glob:"WIP:*")' -m "proper description"

# Clear description (useful for commits that will be squashed)
jj describe -r <commit> -m ""
```

**CRITICAL**: Always include `-m` flag. Without it, `jj describe -r <commit>` opens an editor and hangs in automation.

Descriptions can be updated at any time without special preparation.

### Edit commit content

Modify the actual changes in a commit:

```bash
# Approach 1: Edit in place (checkout commit)
jj edit <commit>
# Make changes to files
# Changes automatically amend the commit
jj new @-  # Return to previous location

# Approach 2: Edit without checkout
jj diffedit -r <commit>
# Opens diff editor, changes apply directly to commit

# Approach 3: Move specific changes
jj edit <commit>
# Make partial changes
jj commit <files>  # Move some changes to new child
# Remaining changes stay in edited commit
jj new @-  # Return to original location
```

### Split commits

Divide a commit into multiple logical commits:

```bash
# Non-interactive split by paths (ALWAYS use -m)
jj split <paths> -m "description for selected changes"
# Specified paths go to first commit with description, rest to second

# Split specific commit by paths (non-interactive)
jj split -r <commit> <paths> -m "description"

# Interactive split (TUI to select hunks) - avoid in automation
jj split -r <commit>
# Opens diff editor - cannot be non-interactive

# Split current working copy (non-interactive)
jj split <paths> -m "description"
# Without -r, splits @ commit
```

**CRITICAL**: `jj split` requires `-m "message"` even when providing paths. Without `-m`, it hangs waiting for editor input after file selection.

First commit gets selected changes with description, second commit gets remainder.
Both commits end up in series with same parent.

### Combine multiple operations

Chain operations using revsets:

```bash
# Squash all WIP commits, then abandon empty commits
jj squash -r 'description(glob:"WIP:*")'
jj abandon 'empty()'

# Reword all commits by author before squashing
jj describe -r 'author("alice")' -m "Alice's changes"
jj squash -r 'author("alice")'

# Move all unfinished commits to separate branch
jj rebase -s 'description(glob:"TODO:*")' -d <elsewhere>
```

## Robust patterns

### Incremental cleanup workflow

Unlike git's all-or-nothing rebase, clean up history incrementally:

```bash
# Phase 1: Review what needs cleaning
jj log -r 'main..@'

# Phase 2: Squash obvious fixups (commits with "fixup", "oops", etc)
jj squash -r 'description(glob:"fixup*")'
jj squash -r 'description(glob:"oops*")'

# Phase 3: Reorder if needed
jj log -r 'main..@'  # Identify order issues
jj rebase -r <commit> -A <after> -B <before>

# Phase 4: Abandon or squash temporary commits
jj abandon 'empty()'
jj squash -r 'description(glob:"WIP:*")'

# Phase 5: Reword remaining commits
jj log -r 'main..@'
jj describe -r <commit1> -m "proper message"
jj describe -r <commit2> -m "proper message"

# Phase 6: Verify
jj log -r 'main..@'
```

Each step executes immediately.
Use `jj undo` to back out of any step.
Continue from where you left off.

### Use operation log instead of backup branches

```bash
# Before starting cleanup, note operation ID
jj op log | head -n 3
# @  a1b2c3d4 ...

# Do cleanup operations
jj squash -r X
jj rebase -r Y -A Z
jj describe -r W -m "message"

# If unhappy with results
jj undo        # Undo last operation
jj undo        # Undo one more
jj op restore a1b2c3d4  # Or restore to beginning

# Alternative: View operation log and selectively restore
jj op log
jj op restore <specific-operation>
```

No need to create backup branches - operation log is your backup.

### Handle conflicts during cleanup

Conflicts are committed and can be resolved later:

```bash
# After operation that creates conflict
jj log
# Shows: @  abc123 (conflict) my commit

# Option 1: Resolve immediately
jj new @
# Fix conflicts in working copy
jj squash  # Move resolution into conflicted commit

# Option 2: Resolve in place
jj edit abc123
# Fix conflicts (automatically amends)
jj new @-

# Option 3: Undo and try different approach
jj undo  # Undo the operation that caused conflict
# Try different operation order

# Check for any conflicts in range
jj log -r 'conflict() & main..@'
```

Unlike git, conflicts don't stop the workflow.
Resolve when convenient or undo and reorganize.

### Verify atomicity

Test each commit independently:

```bash
# Build/test each commit in range
for commit in $(jj log -r 'main..@' --no-graph --template 'commit_id ++ "\n"'); do
  echo "Testing $commit"
  jj new $commit
  # Run build
  cargo build || echo "Build failed in $commit"
  # Run tests
  cargo test || echo "Tests failed in $commit"
done

# Return to original location
jj new @-
```

Or use external script:

```bash
# test-range.sh
#!/bin/bash
for commit in $(jj log -r "$1" --no-graph --template 'commit_id ++ "\n"'); do
  jj new $commit --no-edit
  if ! cargo build; then
    echo "Build failed: $commit"
    jj log -r $commit
    exit 1
  fi
done

# Usage
./test-range.sh 'main..@'
```

### Auto-distribute changes with absorb

For fixing earlier commits automatically:

```bash
# Make fixes in working copy
# Fix bug in file1.txt (last modified by commit A)
# Improve file2.txt (last modified by commit B)
# Refactor file3.txt (last modified by commit C)

# Automatically move each change to the commit that last touched it
jj absorb

# jj analyzes blame info and distributes changes
# file1.txt fix goes to commit A
# file2.txt improvement goes to commit B
# file3.txt refactor goes to commit C
```

Most powerful for fixing issues found during review without manual squashing.

## Complete example

Starting state: 8 commits with various issues

```bash
$ jj log -r 'main..@'
@  mno345 WIP: more fixes
○  jkl012 fix typo
○  ghi789 add feature Y
○  def456 WIP: feature Y work
○  abc123 add feature X
○  zzz999 fixup: feature X test
○  yyy888 temp debug
○  xxx777 feature X implementation
```

Goal: 2 clean commits: one for feature X, one for feature Y

```bash
# Step 1: Review and identify cleanup strategy
# - Squash zzz999 into abc123
# - Drop yyy888 (debug)
# - Squash mno345 and jkl012 into ghi789
# - Squash def456 into ghi789
# - Potentially reorder or combine X and Y features

# Step 2: Squash feature X fixup
jj squash --from zzz999 --into abc123

# Step 3: Drop temporary debug commit
jj abandon yyy888

# Step 4: Combine feature X commits
jj squash -r xxx777  # Squash into abc123
# Now abc123 contains all feature X work

# Step 5: Combine all feature Y commits
jj squash -r def456  # Into ghi789
jj squash -r jkl012  # Into ghi789
jj squash -r mno345  # Into current @
# Now ghi789 contains all feature Y work

# Step 6: Reword both commits
jj describe -r abc123 -m "feat: implement feature X with comprehensive tests"
jj describe -r ghi789 -m "feat: implement feature Y with error handling"

# Step 7: Verify
jj log -r 'main..@'
# @  ghi789 feat: implement feature Y with error handling
# ○  abc123 feat: implement feature X with comprehensive tests

# Step 8: Test each commit
jj new abc123 && cargo test && jj new @-
jj new ghi789 && cargo test && jj new @-

# Step 9: If all good, update bookmark
jj bookmark set feature-xy -r @
```

If any step fails, `jj undo` backs out immediately.
No need to abort and restart - fix the issue and continue.

## Verification

After cleanup:

```bash
# View final history
jj log -r 'main..@'

# Verify diff against target base is unchanged
jj diff -r main..@
# Should show same total changes as before cleanup

# Check each commit builds
for commit in $(jj log -r 'main..@' --no-graph --template 'commit_id ++ "\n"'); do
  jj new $commit --no-edit
  cargo build || echo "FAIL: $commit"
done
jj new @-

# Verify descriptions follow conventions
jj log -r 'main..@' --template 'description ++ "\n"'

# Check for conflicts
jj log -r 'conflict() & main..@'
# Should be empty

# Review operation history
jj op log --limit 20
# Shows all cleanup operations performed
```

## Key reminders

- No backup branches needed - operation log is your safety net
- Operations execute immediately - no todo file, no editor
- `jj undo` reverses any operation instantly
- Descendants auto-rebase when ancestors change
- Conflicts are committed, not blocking
- Use revsets to operate on multiple commits at once
- `jj op restore <id>` returns to any prior state
- Test incrementally instead of at the end
- Reference `~/.claude/skills/jj-git-interactive-rebase-to-jj/SKILL.md` for detailed command mappings

## Advanced patterns

### Linearize merge commits

Convert merge-heavy history to linear sequence:

```bash
# Identify merge commits
jj log -r 'merge() & main..@'

# For each merge, decide to keep or linearize
# To linearize: rebase one branch onto the other
jj rebase -s <branch-head> -d <main-branch>
```

### Extract commits to separate branch

Move unrelated work to different branch:

```bash
# Identify commits to extract
jj log -r 'description(glob:"*unrelated*") & main..@'

# Create new bookmark for extracted work
jj bookmark create unrelated-work -r <first-unrelated-commit>

# Rebase unrelated work onto main
jj rebase -s <first-unrelated-commit> -d main

# Original branch now has hole - descendants rebased appropriately
jj log -r 'main..@'
```

### Reorder and group by semantic category

Group commits by type (feat/fix/refactor/test/docs):

```bash
# List all commits with types
jj log -r 'main..@' --template 'description ++ "\n"'

# Reorder so similar types are adjacent
# feat commits first
jj rebase -r <feat-commit-1> -d main
jj rebase -r <feat-commit-2> -A <feat-commit-1>

# Then fix commits
jj rebase -r <fix-commit-1> -A <feat-commit-2>

# Then refactor commits
jj rebase -r <refactor-commit-1> -A <fix-commit-1>

# Review grouping
jj log -r 'main..@'
```

### Batch operations with shell loops

Process multiple commits programmatically:

```bash
# Reword all commits matching pattern
for commit in $(jj log -r 'description(glob:"WIP*") & main..@' \
                --no-graph --template 'commit_id ++ "\n"'); do
  jj describe -r $commit -m "feat: $(jj log -r $commit --no-graph --template 'description')"
done

# Abandon all empty commits in range
jj abandon 'empty() & main..@'

# Squash all fixup-style commits
for commit in $(jj log -r 'description(glob:"fixup:*") & main..@' \
                --no-graph --template 'commit_id ++ "\n"'); do
  jj squash -r $commit
done
```

## Integration with bookmarks

Set bookmarks after cleanup:

```bash
# After cleaning up history
jj log -r 'main..@'

# Set bookmark on final commit
jj bookmark set feature-complete -r @

# Or set bookmark on specific commit
jj bookmark set feature-partial -r <commit>

# Push cleaned history
jj git push --bookmark feature-complete

# If bookmark already exists and needs updating
jj bookmark set feature-complete -r @ --allow-backwards
```

## Session workflow

Typical cleanup session:

```bash
# 1. Start session
jj op log | head -n 1  # Note starting operation for possible restore

# 2. Survey work
jj log -r 'main..@'
jj log -r 'empty() & main..@'
jj log -r 'description(glob:"WIP*") & main..@'

# 3. Clean in phases
jj abandon 'empty() & main..@'
jj squash -r 'description(glob:"WIP*") & main..@'
jj squash -r 'description(glob:"fixup*") & main..@'

# 4. Reorder if needed
jj log -r 'main..@'
# Manually rebase commits into logical order

# 5. Update descriptions
jj log -r 'main..@'
# Manually describe each commit

# 6. Verify atomicity
# Test each commit individually

# 7. Set bookmark and push
jj bookmark set feature-name -r @
jj git push --bookmark feature-name

# 8. View operation summary
jj op log --limit 20
```

Each step is undoable.
Stop at any point and continue later.
