# Commit workflow

Operational recipes for the atomic commit workflow across all three VCS modes (git-native, GitButler, jj).
This file covers file state verification, the per-mode atomic commit cycle, handling pre-existing mixed changes, commit formatting, and session commit summary.
For the top-level routing index, commit behavior override, VCS terminology glossary, branch workflow, and merge strategy selection, see [`SKILL.md`](SKILL.md).
For the deep operational detail of the jj development-join edit-route cycle, see `~/.claude/skills/jj-version-control/SKILL.md` §"Development join".

## File state verification

Before editing any file, check for uncommitted changes:

- Related to current task: commit them first with appropriate message
- Unrelated or unclear: pause and propose commit message asking user for confirmation

In git-native mode, run `git status --short [file]` and `git diff [file]`.
In GitButler mode, `but status -fv` provides richer state including branch assignment and CLI IDs for each changed file.
In jj mode, `jj status` and `jj diff` show working copy state. There is no staging area — all tracked file changes are the commit.
In development-join mode the expected state is an empty `@` (the `[wip]` commit) directly atop the multi-parent join; any content `jj diff` shows for `@` is unrouted work to send DOWNWARD into a chain (via `jj absorb` or `jj squash --from @ ... --keep-emptied`), not committed by describing `@`.
Describing or rebasing `@` drifts it off `[wip]`, vanishing the shared editing surface other actors depend on and (in this repo) dragging the pushed `wip` deploy bookmark below the join.
The "commit them first" rule above therefore means route-downward, not `jj describe @`, when a development join is present.

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
This `describe @` + `new` boundary is single-chain ONLY; in development-join mode `@` is never described (see below).
Without `jj new`, the next edit accumulates into the same change, breaking atomicity.
If multiple files were edited before freezing, use `jj split <path> -m "msg"` to separate them into atomic changes after the fact.

In jj development join mode (multi-parent composite): edit one file, then route it to the correct chain.
In this mode `@` is always the empty `[wip]` commit sitting directly on the multi-parent development join; every editor edits that same shared `[wip]` and routes each change DOWNWARD into a chain, leaving `@` empty in place.
Never `jj describe @` into content and never relocate `@` via the positional rebase forms `jj rebase -r @ --insert-before/--insert-after <target>` (nor `jj rebase --revisions @ --insert-before/--insert-after <target>`).
Doing so drifts `@` off `[wip]`, destroys the shared editing surface concurrent actors are writing, and — in this repo — drags the pushed `wip` deploy bookmark below the join and breaks the join's single-`[wip]`-child invariant; recover any drift with `jj op restore`.
The one sanctioned `jj rebase` that may name `@` is the destination add/remove-chain form `jj rebase -r @ -d 'all:(…)'`, which re-anchors the empty `@` onto a rebuilt join without drifting it.
See `~/.claude/skills/jj-version-control/SKILL.md` §"Development join" for the canonical invariant, splice/by-relocation recipes, and the full concurrency rationale — this section is a routing summary, not the source of truth.
Two routing patterns exist:

- *Amend existing chain commit:* `jj squash --from @ --into <target-parent> --keep-emptied -- <path>` routes the file into the existing commit while leaving `@` the empty `[wip]` on the join.
  Always pass `--from @` (a bare `--into` is a no-op when `@` is empty) and `--keep-emptied` (otherwise the emptied source is abandoned and the join + wip structure is disrupted).
  Omit `-m` so the target chain commit's existing description is preserved; the empty `[wip]` carries no description, so the description-merge editor never opens.
  Use when the chain commit already exists and the change belongs in it.
- *Extend chain with new commit:* use the route-and-extend pattern from `~/.claude/skills/jj-version-control/SKILL.md`.
  Use when the change is a logically separate commit that should extend the chain.
- *Auto-route by blame:* `jj absorb` distributes changes to appropriate ancestors automatically.

Routing in development-join mode NEVER describes `@`.
`@` is always the empty `[wip]` directly on the join; every routing verb (`jj squash --from @ --insert-after/--into <target> --keep-emptied [-- <paths>]`, `jj absorb`, or `jj split` keeping the wip) moves content DOWNWARD into a chain commit while leaving `@` in place and empty.
`[wip]`'s description is ephemeral and is never maintained, so there is nothing to clear after a route.
This is the whole point: the shared `[wip]` is the stable coordination surface that makes N concurrent editors safe by construction, and in this repo `@`/wip also backs the pushed `wip` deploy bookmark (machines rebuild from it) and is the join's required single child.
If `@` somehow acquired a description or drifted off the join, treat it as an error to recover via `jj op restore`, not a routine cleanup.

Do not use `jj new` (without `-A`) in development join mode — it creates a new change descending from the development join `@` rather than routing to a chain.
`jj new -A <bookmark> --no-edit` is safe because it inserts after the specified bookmark without moving `@`.
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

## Session commit summary

After creating commits, provide a git command listing session commits: `git log --oneline <start-hash>..<end-hash>` using the commit hash from gitStatus context as start and `git rev-parse HEAD` as end. Use explicit hashes, not symbolic references, to ensure command remains valid after subsequent commits.

In jj mode: `jj log --no-graph -r 'main@origin..main' -T 'separate(" ", change_id.short(8), description.first_line()) ++ "\n"'`

## See also

- [`SKILL.md`](SKILL.md) — top-level git version control principles, glossary, and routing index
- [`06-github-pr-issue-safety.md`](06-github-pr-issue-safety.md) — GitHub PR and Issue creation safety protocol
- [`01-git-native-mode.md`](01-git-native-mode.md) — git-native mode working-branch isolation recipes
- [`02-gitbutler-mode.md`](02-gitbutler-mode.md) — GitButler mode working-branch isolation recipes
- [`03-jj-mode.md`](03-jj-mode.md) — jj mode working-branch isolation recipes
- `~/.claude/skills/jj-version-control/SKILL.md` §"Development join" — operational detail for jj development-join edit-route cycle
