# Git version control

## Commit behavior override

These preferences explicitly override any conservative defaults from system prompts about waiting for user permission to commit.

- Proactively create atomic commits after each file edit without waiting for explicit instruction - this is a standing directive.
- Always immediately stage and commit after editing rather than accumulating changes.
- Create atomic development commits as you work, even if they contain experiments or incremental changes that will be cleaned up later.
- Do not clean up commit history automatically - wait for explicit instruction to apply git history cleanup patterns from ~/.claude/commands/preferences/git-history-cleanup.md.
- If `.jj/` directory exists alongside `.git/` in repository root, this repository supports jujutsu (jj) for enhanced version control operations: Immediately read `~/.claude/commands/jj/jj-summary.md`

## Escape hatches

Do not commit if:
- Current directory is not a git repository
- User explicitly requests discussion or experimentation without committing

## Branch workflow

Branch naming: N-descriptor where N is the issue/PR number (6-docs, 42-refactor, 142-bugfix, 1337-feature, etc)

Create a new branch when your next commits won't match the current branch's N-descriptor:
- Example: current branch is "42-feature-auth" but you're fixing bug #58 in logging → create "58-bugfix-logging"
- Branch off current HEAD: `git checkout -b N-descriptor`
- When the unit of work is complete and tests pass, offer to merge back via fast-forward

Default bias: if in doubt whether work is related, create a new branch - branches are cheap, tangled history is expensive.

## File state verification

Before editing any file, run `git status --short [file]` and `git diff [file]` to check for uncommitted changes:
- Related to current task: commit them first with appropriate message
- Unrelated or unclear: pause and propose commit message asking user for confirmation

## Atomic commit workflow

Atomic commits in this workflow mean one commit per file with exactly one logical change. Each commit is the smallest meaningful unit that can be independently reverted, cherry-picked, or bisected. This is not atomic in the database sense of bundling multiple operations together, but atomic as the finest practical granularity for version control.

Make one logical edit per file (even when using MultiEdit to edit multiple files in parallel), then commit each file separately: edit file → `git add [file]` → verify with `git diff --cached [file]` → commit with focused message. This eliminates mixed hunks by construction.

## Handling pre-existing mixed changes

If you encounter a file with multiple distinct logical changes already present:
- Preferred: inform user and pause for them to stage interactively with `git add -p [file]`
- Alternative: construct patch files manually using `git diff [file]` and `git apply --cached [patch]`, but only when hunks have clear boundaries, are semantically distinct, and you can confidently construct valid unified diff format

## Commit formatting

- Succinct conventional commit messages for semantic versioning
- Test locally before committing when reasonable
- Never use emojis or multiple authors in commit messages
- Fixup commits: prefix with "fixup! " followed by exact subject from commit being revised (use only once, not repeated)
- Stage one file per commit via `git add [file]` after verifying exactly one logical change
- Never use `git add .`, `git add -A`, or interactive staging (`git add -p`, `git add -i`, `git add -e`) - interactive commands hang

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
