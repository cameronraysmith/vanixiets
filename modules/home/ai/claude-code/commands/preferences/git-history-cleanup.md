# git history cleanup

## purpose

Transform experimental development history into a clean, reviewable commit sequence where:

- Each commit is atomic: contains one logical change that builds/tests successfully
- Commits are logically ordered: dependencies come before dependents, related changes are grouped
- Intermediate commits are removed: no "WIP", "fix typo", "oops", or checkpoint commits
- Each commit message follows conventional commit format and accurately describes its diff

This prepares branches for PR review by creating a clear narrative of what changed and why.

## principle

Never trigger interactive editors. All operations use `GIT_SEQUENCE_EDITOR` and `GIT_EDITOR` environment variables with non-interactive commands.

## core technique

```bash
GIT_SEQUENCE_EDITOR="command-to-edit-todo" git rebase -i <base>
```

The rebase todo file has one line per commit: `<action> <hash> <message>`

## operations

### reorder commits

Use sed/awk to rearrange lines in the todo file:

```bash
# Move commit at line N to line M (example: move line 3 to line 1)
GIT_SEQUENCE_EDITOR="awk 'NR==3 {saved=\$0; next} NR==1 {print saved} {print}' > /tmp/rebase-todo && cat /tmp/rebase-todo" git rebase -i HEAD~5

# Reverse order
GIT_SEQUENCE_EDITOR="tac" git rebase -i HEAD~3

# Custom order: use awk to print lines in desired sequence
GIT_SEQUENCE_EDITOR="awk '{lines[NR]=\$0} END {for (i in order) print lines[order[i]]}'" git rebase -i HEAD~N
```

### squash/fixup commits

```bash
# Squash commit at line N into previous (N-1)
GIT_SEQUENCE_EDITOR="sed -i.bak 'Ns/^pick/squash/'" git rebase -i HEAD~5

# Fixup (squash without message)
GIT_SEQUENCE_EDITOR="sed -i.bak 'Ns/^pick/fixup/'" git rebase -i HEAD~5

# Squash all commits after first
GIT_SEQUENCE_EDITOR="sed -i.bak '2,\$s/^pick/squash/'" git rebase -i HEAD~5
```

### drop commits

```bash
# Drop commit at line N
GIT_SEQUENCE_EDITOR="sed -i.bak 'Nd'" git rebase -i HEAD~5

# Drop by marking as 'drop'
GIT_SEQUENCE_EDITOR="sed -i.bak 'Ns/^pick/drop/'" git rebase -i HEAD~5
```

### reword commit messages

```bash
# Mark for reword, then use GIT_EDITOR to set message
GIT_SEQUENCE_EDITOR="sed -i.bak 'Ns/^pick/reword/'" \
  GIT_EDITOR="echo 'new message' >" \
  git rebase -i HEAD~5

# For multiple rewords, use a script that checks commit hash
```

### edit commit content

```bash
# Mark commit for edit at line N
GIT_SEQUENCE_EDITOR="sed -i.bak 'Ns/^pick/edit/'" git rebase -i HEAD~5

# Rebase will pause; make changes, then:
git add <files>
git commit --amend --no-edit
git rebase --continue
```

### split commits

```bash
# Mark for edit
GIT_SEQUENCE_EDITOR="sed -i.bak 'Ns/^pick/edit/'" git rebase -i HEAD~5

# When paused:
git reset HEAD^
git add <files-for-first-commit>
git commit -m "first part"
git add <files-for-second-commit>
git commit -m "second part"
git rebase --continue
```

## robust patterns

### use temporary files for complex edits

```bash
#!/bin/bash
# reorder-script.sh
# Reads git-rebase-todo from $1, writes modified version back
awk '{lines[NR]=$0} END {
  # Print in desired order
  print lines[3]
  print lines[1]
  print lines[2]
}' "$1" > "$1.tmp" && mv "$1.tmp" "$1"

chmod +x reorder-script.sh
GIT_SEQUENCE_EDITOR="./reorder-script.sh" git rebase -i HEAD~3
```

### multi-step workflow

For complex history rewrites:

1. First pass: reorder commits
2. Second pass: squash/fixup related commits
3. Third pass: reword messages
4. Final pass: test and verify

Run separate rebase operations rather than one complex edit.

### handle conflicts

```bash
# If rebase conflicts:
git status  # identify conflicts
# Fix conflicts manually
git add <resolved-files>
git rebase --continue

# To abort:
git rebase --abort
```

## complete example

Clean up 5 commits: reorder, squash 2 & 3, drop 4, reword 5

```bash
# Step 1: Create reorder script
cat > /tmp/rebase-edit.sh << 'EOF'
#!/bin/bash
awk '{lines[NR]=$0} END {
  print lines[1]
  gsub(/^pick/, "squash", lines[3])
  print lines[3]
  gsub(/^pick/, "drop", lines[4])
  print lines[4]
  gsub(/^pick/, "reword", lines[5])
  print lines[5]
  print lines[2]
}' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
EOF
chmod +x /tmp/rebase-edit.sh

# Step 2: Run rebase
GIT_SEQUENCE_EDITOR="/tmp/rebase-edit.sh" \
  GIT_EDITOR="echo 'New message for commit 5' >" \
  git rebase -i HEAD~5
```

## verification

After any history rewrite:

```bash
git log --oneline --graph -n 10
git diff <original-branch>..HEAD  # Should be empty for pure history changes
```

## git revise (preferred for simple cases)

git revise is faster than git rebase (in-memory, doesn't touch working directory) and well-suited for linear history cleanup.

### key differences from git rebase

- No `drop` command: all commits must be accounted for (use fixup to absorb unwanted commits)
- Todo format: `<action> <hash> <message>` (simpler than rebase)
- Single-commit reword: `git revise -m <target> -m "new message"` (no editor needed)
- Undo with `git reset @{1}` (single reflog entry)

### non-interactive patterns

```bash
# Reword a specific commit without interactive mode
git revise --no-gpg-sign <target-hash> -m "new commit message"

# Apply fixups using GIT_SEQUENCE_EDITOR (same as rebase)
cat > /tmp/revise-editor.sh << 'SCRIPT'
#!/bin/bash
cat > "$1" << 'TODO'
pick <hash1> first commit message
fixup <hash2> fixup for first
pick <hash3> second commit message
fixup <hash4> fixup for second
TODO
SCRIPT
chmod +x /tmp/revise-editor.sh
GIT_SEQUENCE_EDITOR="/tmp/revise-editor.sh" git revise -i --no-gpg-sign <base>^
```

### multi-pass workflow (recommended)

Complex rewrites are safer as separate operations:

1. **Structure pass**: reorder and fixup/squash related commits
2. **Message pass**: reword each commit with `git revise -m <hash> -m "message"`
3. **Verify pass**: `git log --oneline`, `git show --stat <hash>` for each commit

### gpg signing

When commit.gpgSign is configured but key unavailable, use `--no-gpg-sign`:

```bash
git revise --no-gpg-sign -i <base>
git revise --no-gpg-sign <hash> -m "message"
```

### fixup ordering

Fixup commits must immediately follow their target:

```bash
# Correct: fixup follows its target
pick abc123 feature implementation
fixup def456 fix typo in feature

# Wrong: fixup before target (will squash into wrong commit)
fixup def456 fix typo in feature
pick abc123 feature implementation
```

### absorbing removal + restoration commits

When a commit removes something and a later commit restores it (net effect: just comments/modifications), squash them:

```bash
# Before: A removes X, B restores X with comment, C fixes comment
# After: single commit with just the comment

cat > /tmp/revise-editor.sh << 'SCRIPT'
cat > "$1" << 'TODO'
pick <hash-A> remove X
fixup <hash-B> restore X with comment
fixup <hash-C> fix comment
TODO
SCRIPT
GIT_SEQUENCE_EDITOR="/tmp/revise-editor.sh" git revise -i --no-gpg-sign <hash-A>^

# Then reword with correct message
git revise --no-gpg-sign <new-hash> -m "add comment explaining X"
```

## when to use which tool

| Scenario | Tool | Reason |
|----------|------|--------|
| Simple linear cleanup | git revise | Faster, in-memory |
| Reword single commit | `git revise -m` | No editor needed |
| Complex reordering | git rebase -i | More flexible |
| Conflicts expected | git rebase -i | Better conflict UX |
| exec/break needed | git rebase -i | revise lacks these |

## key reminders

- Always work on a backup branch first
- Use `-i.bak` with sed for safety (creates backup)
- Test rebase scripts on throwaway branches
- Check `git rebase --abort` or `git reset @{1}` is available if things go wrong
- For AI agents: create temporary shell scripts rather than inline complex sed/awk
- Never use bare `git rebase -i` or `git revise -i` without `GIT_SEQUENCE_EDITOR` set
- Use `--no-gpg-sign` when GPG key is unavailable
