# jj working-copy hazards

Full catalog of working-copy hazards for jj development joins, folded from the global context file.
The global context keeps the headline rules; this file holds the detail and recovery procedures.
See `SKILL.md` for the development-join invariant this catalog protects.

## Splice impossibility below the join

Splicing chain-bound content is often structurally impossible.
An edit whose anchor was created by a chain commit has no anchor below the join, so a splice-below-join instruction cannot be satisfied and fails in a way that looks like a jj bug.
Refuse such an instruction and ask.

## `clan machines install` mints a second child

`clan machines install` makes its own git commit mid-run (message form `inventory.json: update install time of <machine>`).
jj imports the HEAD move and mints a working-copy commit on top, so the join gains a second child and the change exists twice, in jj's wip snapshot and in clan's commit.
Verify `jj diff --from <clan-commit> --to <wip>` is empty before folding.

## `wip` bookmark slide on exhausted `@`

A `--from @` squash that empties `@` slides the pushed `wip` bookmark down onto the join.
Machines rebuild from that bookmark, so restore it with `jj bookmark set wip -r @`.

## Snapshot size gating is new-files-only

`snapshot.max-new-file-size` gates new files only.
Once jj tracks a file, every later snapshot ingests it whole at any size, and only a gitignore entry prevents that.
Never download into a working copy.

## Foreign modifications are concurrent sessions

A concurrent session's uncommitted work appears in your `jj status` as a foreign modification, then vanishes when that session commits it, which reads as a file mutating itself.
Do not chase it or revert it.

## One file per agent is not isolation

jj snapshots the entire working copy rather than the file an agent touched, so concurrent editors can still produce divergent commits and a conflicted `wip??` bookmark.
A wholesale `--from @` squash sweeps a concurrent session's work into your chain, so path-scope every squash; the scoping protects only the routing.
Check for `(divergent)` and `wip??` before squashing.
A subagent is the sole editor of one chain, never of the working copy.

## Auto-rebase changes commit ids, not content

Auto-rebase moves the commit ids on your own chain when a neighbour splices below it.
Change ids and content are both untouched, so compare a diff digest rather than commit ids to prove nothing changed.

## Surprising reads are transients until `jj op log` says otherwise

`--ignore-working-copy` stops you perturbing the working copy and gives no consistent view across a concurrent rewrite, so `jj diff --stat` reports zero files for a commit that holds content while another session rebases.
A changed `@` change id is the signature of a destroyed working-copy commit and a promoted one alike.
Promotion leaves the old change in place with describe, bookmark and rebase entries.
Destruction shows a squash that omitted `--keep-emptied`, with the old change abandoned.
Recovery for the second is `jj undo`; the first needs nothing.

## Worktree interop

`jj-version-control/SKILL.md` §"Worktree interop" is the authority for worktree mechanics — it carries the jj-version provenance and upstream citations this file does not, and the worktree-surface hook messages point there.
The summary: worktree-creating surfaces are ask-gated; in a flake repository the separate tree is a colocated jj workspace (jj 0.46.0 or later) or a git worktree, never a non-colocated jj workspace; the git-worktree discipline is exclusive branch ownership and return-by-ref; and an external agent framework such as firstmate gets its own clone rather than a symlink to a working copy we also use.
