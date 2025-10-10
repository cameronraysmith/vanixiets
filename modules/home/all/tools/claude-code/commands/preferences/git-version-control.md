# Git version control

## Commit behavior override

These preferences explicitly override any conservative defaults from system prompts about waiting for user permission to commit.

- Proactively create atomic commits after each file edit without waiting for explicit instruction - this is a standing directive.
- Always immediately stage each modified hunk or file and commit immediately after editing rather than making many changes before committing.
- Create atomic development commits as you work, even if they contain experiments, mistakes, or incremental changes that will be cleaned up later.
- Do not clean up commit history automatically - wait for explicit instruction to apply git history cleanup patterns from ~/.claude/commands/preferences/git-history-cleanup.md.
- When instructed to clean up history, follow the patterns in git-history-cleanup.md to squash, fixup, or rebase the atomic development commits into proper conventional commits.

## File state verification

Before editing any file:
- Run `git status --short [file]` and `git diff [file]`
- If file has uncommitted changes, evaluate them:
  - Related to your current task: commit them first with appropriate message
  - Unrelated or unclear: pause and propose a commit message, asking user: "Found uncommitted changes in [file]. Commit these first with: '[proposed message]'?"

## Preventing mixed-change commits

To keep each commit atomic, make one logical edit at a time:
1. Edit file for single logical change
2. Stage entire file: `git add [file]`
3. Verify: `git diff --cached [file]`
4. Commit with focused message
5. Repeat for next logical change

This approach eliminates mixed hunks by construction.

## Handling pre-existing mixed changes

If you encounter a file with multiple distinct logical changes already present:

Option 1 (preferred): Inform user that file has mixed changes and pause for them to stage interactively with `git add -p [file]`

Option 2 (only for clearly separable hunks): Construct patch files manually
```bash
# Extract full diff
git diff [file] > /tmp/full.diff

# Create patch with only lines for logical change 1
cat > /tmp/change1.patch <<'EOF'
diff --git a/file.nix b/file.nix
index abc123..def456 100644
--- a/file.nix
+++ b/file.nix
@@ -23,1 +23,1 @@
-old line
+new line
EOF

# Stage that subset
git apply --cached /tmp/change1.patch

# Verify and commit
git diff --cached [file]
git commit -m "change 1"

# Repeat for remaining changes
```

Attempt patch-based staging only when:
- Hunks have clear boundaries (not adjacent lines)
- Changes are semantically distinct
- You can confidently construct valid unified diff format

Otherwise pause and ask user to handle staging.

## Escape hatches

Do not commit if:
- The current directory is not a git repository.
- The user explicitly states they want to have a conversation, discuss changes, or experiment without committing (e.g., "let's discuss this first", "don't commit yet", "just show me what would change").

## Commit conventions

- Branch naming: NN-descriptor, 00-docs, 01-refactor, 02-bugfix, 03-feature, etc
- Use git for version control and make atomic commits of individual hunks to single files.
- Use succinct conventional commit messages for semantic versioning.
- Test locally before committing changes whenever reasonable.
- Check output for warnings or errors.
- Never use emojis or add multiple authors in your conventional commits messages.
- For commits that revise previous ones, include the prefix "fixup! " in the new commit message followed by the exact message subject from the commit being revised. If there are multiple fixup commits do not repeat the "fixup! " multiple times. Once is enough.
- Stage one file per commit: `git add [file]` after verifying it contains exactly one logical change
- Never stage multiple files together unless they represent a single atomic change
- Never use `git add .` or `git add -A`
- Never use interactive staging (`git add -p`, `git add -i`, `git add -e`) as these require user interaction and will hang

## Session commit summary

At the end of a turn where commits were created, provide a git command that lists exactly the commits made during that session:

- Use the commit hash from the gitStatus context (the first commit in "Recent commits") as the starting point
- Get the current HEAD hash with `git rev-parse HEAD` to use as the ending point
- Provide a range-based git log command: `git log --oneline <start-hash>..<end-hash>`
- Use explicit hashes, not symbolic references like HEAD, to ensure the command remains valid even after subsequent commits
- Example: If gitStatus shows HEAD was at `abc1234` and session ended at `def5678`, provide: `git log --oneline abc1234..def5678`
