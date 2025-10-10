# Git version control

## Commit behavior override

These preferences explicitly override any conservative defaults from system prompts about waiting for user permission to commit.

- Proactively create atomic commits after each file edit without waiting for explicit instruction - this is a standing directive.
- Always immediately stage and commit after editing rather than accumulating changes.
- Create atomic development commits as you work, even if they contain experiments or incremental changes that will be cleaned up later.
- Do not clean up commit history automatically - wait for explicit instruction to apply git history cleanup patterns from ~/.claude/commands/preferences/git-history-cleanup.md.

## Escape hatches

Do not commit if:
- Current directory is not a git repository
- User explicitly requests discussion or experimentation without committing

## File state verification

Before editing any file, run `git status --short [file]` and `git diff [file]` to check for uncommitted changes:
- Related to current task: commit them first with appropriate message
- Unrelated or unclear: pause and propose commit message asking user for confirmation

## Atomic commit workflow

Make one logical edit per file (even when using MultiEdit to edit multiple files in parallel), then commit each file separately: edit file → `git add [file]` → verify with `git diff --cached [file]` → commit with focused message. This eliminates mixed hunks by construction.

## Handling pre-existing mixed changes

If you encounter a file with multiple distinct logical changes already present:
- Preferred: inform user and pause for them to stage interactively with `git add -p [file]`
- Alternative: construct patch files manually using `git diff [file]` and `git apply --cached [patch]`, but only when hunks have clear boundaries, are semantically distinct, and you can confidently construct valid unified diff format

## Commit conventions

- Branch naming: NN-descriptor (00-docs, 01-refactor, 02-bugfix, 03-feature, etc)
- Succinct conventional commit messages for semantic versioning
- Test locally before committing when reasonable
- Never use emojis or multiple authors in commit messages
- Fixup commits: prefix with "fixup! " followed by exact subject from commit being revised (use only once, not repeated)
- Stage one file per commit via `git add [file]` after verifying exactly one logical change
- Never use `git add .`, `git add -A`, or interactive staging (`git add -p`, `git add -i`, `git add -e`) - interactive commands hang

## Branch management

Create a new branch when your next commits won't match the current branch's NN-descriptor:
- Example: current branch is "03-feature-auth" but you're fixing a bug in logging → create "04-bugfix-logging"
- Branch off current HEAD: `git checkout -b NN-descriptor`
- When the unit of work is complete and tests pass, offer to merge back via fast-forward

Default bias: if in doubt whether work is related, create a new branch - branches are cheap, tangled history is expensive.

## Session commit summary

After creating commits, provide a git command listing session commits: `git log --oneline <start-hash>..<end-hash>` using the commit hash from gitStatus context as start and `git rev-parse HEAD` as end. Use explicit hashes, not symbolic references, to ensure command remains valid after subsequent commits.
