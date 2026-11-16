# Brainstorm: a pointer-only LFS policy and revision hydration for the shared reference tree

This records the diagnosis behind the change, made on stibnite on 2026-11-16 with read-only commands only.

## Problem

`ghq-sync -u` on `github.com/bastani-inc/atomic` failed every time it was requested since the tree was migrated, with `error: Your local changes to the following files would be overwritten by merge: assets/feature-wall/02-hashline-edits.gif`.
crs58 cloned the repository on 2026-08-16 with Home Manager's `programs.git.lfs` (`skipSmudge = false`), so every LFS path in the working tree held the content its pointer names while the index and every commit held the pointer.
The migration's ownership pass on 2026-10-17 changed every entry's ctime and owner, which made git re-read each file's content, and the writer runs git with no system or global configuration and no `git-lfs` on its `PATH`.
Without a clean filter, git hashes the real content, which is not the pointer, so the writer sees all 42 LFS paths as changed and a fast-forward that touches one of them is refused.
Ten of the eleven repositories on stibnite with `.git/lfs` show the same state from the writer's view, every changed path among them LFS-tracked.

The `permission denied` errors seen by an agent the same day came from its own git commands as crs58, not from `ghq-sync`: `git status` ran crs58's `git-lfs filter-process`, which tries to write `.git/lfs/tmp`, and `git show <tag>:<path>` in the blobless clone tried to fetch the missing blob, which means writing `.git/objects/pack`.
Neither write is open to a reader, by design.

## Options

- O1: a pointer-only policy: no account's git runs an LFS filter in the shared tree; the writer sets it in its own invocations, readers through a `gitdir:` conditional include, and migration sets smudged paths back to their pointers.
- O2: give the writer `git-lfs` and smudge every LFS path.
- O3: have the writer reset every working tree to its upstream before each update.
- O4: weaken git's stat checks (`core.trustctime=false`, `core.checkStat=minimal`).
- O5: give readers group-write on `.git/lfs/tmp` and `.git/objects/pack`.
- H1: a delegated writer action that makes present the objects a named revision's tree needs, so a reader can read at a revision other than the checked-out one.
- H2: tell readers to promote to a full clone (`ghq-sync --full`) before reading at another revision.

## Outcome

O1 and H1, approved by the operator on 2026-11-16.
O2 makes the reference tree download large binaries the lazy tree is designed not to hold, and git-lfs follows the upstream-controlled `.lfsconfig`, whose `lfs.url` the writer's `protocol.allow` does not govern.
O3 hides drift from the invariant instead of exposing it.
O4 hides the mismatch until git re-reads the files for another reason.
O5 breaks the single-writer property.
H2 fetches a repository's whole history to read one revision.
