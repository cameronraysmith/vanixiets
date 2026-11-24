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

## Concurrent sessions on one join

These six failures occurred while two or more sessions shared one join; the rules that answer them are in `SKILL.md` §"Coordinating concurrent sessions on one join".

### An explicit parent list drops another session's chains

Rebuilding the join with `-d <chain-a> -d <chain-b> -d <new-chain>` sets its parents to exactly that list.
A chain another session added is not on it, so it leaves the join without a warning, and its commits stay in the graph while its content disappears from the working copy.
Always derive the destination from the join's current parents and the trunk (`SKILL.md` §"Adding and removing chains"); recovery is the add form for each dropped chain.

### The trunk drops out of the join

The earlier derived form, `heads((parents(<join>) ~ ::trunk()) | <new-chain>)`, removes every parent the trunk contains and adds nothing back.
When a chain lands and every remaining parent is based on the older trunk, the join stops containing what landed, and the landed files disappear from `@` while `jj log -r 'trunk() ~ ::<join>'` is non-empty.
Recovery is `jj rebase -s <join> -d 'heads((parents(<join>) ~ ::trunk()) | trunk())'`, which makes the trunk a parent again; the `| trunk()` term in every form in `SKILL.md` §"Adding and removing chains" prevents it.

### A chain created but not yet joined

A chain created with `jj new --no-edit` is not a parent of the join until someone adds it, so its content is not in `@`.
Another session's derived rebase keeps every existing parent and so correctly leaves it out, and a path-scoped `jj squash --into` that chain moves those paths out of `@` into a commit `@` does not contain, so the files disappear from the working copy.
The symptom is a chain missing from `jj log -r 'parents(<join>)'`, together with edits that vanish from the working copy after being squashed into it.
Recovery is the add form in `SKILL.md` §"Adding and removing chains", which brings the content back into `@`; prevent it by adding every new chain to the join immediately after creating it, before any edit.

### A landing conflicts your sibling chains

A publish that lands one of your chains moves the trunk under your other chains, and one of them can then conflict in the join with the landed content, leaving the shared working copy conflicted for the other session as well.
Rebase your remaining chains onto the new trunk and rebuild the join as part of the landing, before announcing it (`diamond-workflow.md` §"Landing while another session shares the join").

### A tool rewrites the join's description

A script that regenerates the `join N=` description replaces whatever the session maintaining it wrote there.
Treat any rewrite of the join's description as an announced join operation, and never keep state you need in it.

### Strays go unnoticed

An agent that leaves an undescribed commit behind leaves it for someone else to find.
Run the stray checks in `diamond-workflow.md` §"Reading the shared state" before reporting; describe, route or abandon your own and report anyone else's.

## Worktree interop

`jj-version-control/SKILL.md` §"Worktree interop" is the authority for worktree mechanics — it carries the jj-version provenance and upstream citations this file does not, and the worktree-surface hook messages point there.
The summary: worktree-creating surfaces are ask-gated; in a flake repository the separate tree is a colocated jj workspace (jj 0.46.0 or later) or a git worktree, never a non-colocated jj workspace; the git-worktree discipline is exclusive branch ownership and return-by-ref; and an external agent framework that manages repositories gets its own clone rather than a symlink to a working copy we also use.
