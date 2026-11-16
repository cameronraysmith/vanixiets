## Why

Updates of shared reference repositories that track files with Git LFS fail: a working tree an account's git-lfs smudged before migration shows every LFS path as changed to the writer, whose git runs no LFS filter, so a fast-forward touching one is refused. Readers' own git-lfs fails writing an LFS cache it cannot write. A reader also cannot read a blobless clone at any revision other than the checked-out one, because the missing contents can only be fetched by a write.

## What Changes

**LFS in the shared tree**
- From: undefined; the writer runs no LFS filter by omission, readers run their own git-lfs, and migrated trees keep smudged content.
- To: every working tree in the shared tree holds LFS pointer files as committed; the writer sets an empty LFS filter explicitly in every git invocation, each participating account's git applies the same setting beneath the shared root through a `gitdir:` conditional include, and migration sets smudged LFS paths back to their pointers as the writer, keeping the content for rollback.
- Reason: updates of LFS repositories fail and readers' git-lfs fails writing.
- Impact: non-breaking for reading source; an LFS-tracked binary in the shared tree reads as its pointer file.

**Reading at another revision**
- From: a blobless reference repository is readable only at its checked-out revision.
- To: `ghq-sync --hydrate <rev> <repo>` has the writer fetch every object that revision's tree lacks, over its allowed protocols only, keeping the clone's filter and depth.
- Reason: reading at a pinned revision is the documented way to cite a reference repository.
- Impact: non-breaking; a new request action.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `shared-reference-tree` (stratum: `behavioral`): an acquisition request may also make a reference repository readable at a named revision, and every participating account reads the same committed content.
- `shared-reference-tree-interface` (stratum: `interface`): the pointer-only LFS policy for the writer and for participating accounts, the `hydrate` request, and the migration step that sets smudged LFS paths back to their pointers. Trust boundary: these properties hold for git invocations the writer's handler, the migration tool and each participating account's declared git configuration make; a repository-local LFS filter setting still outranks a participant's include, and nothing here covers the content LFS objects name.

## Impact

- `pkgs/by-name/ghq-shared/` (`ghq-writer-handler.py`, `ghq-writer-client.py`, `ghq-shared-migrate.py`, `test_handler.py`), `pkgs/by-name/ghq-sync/ghq-sync.sh`.
- `modules/system/shared-reference-tree.nix` (`flake.lib.sharedReferenceTreeLfsPolicy`), `modules/{darwin,nixos}/shared-reference-tree.nix` (assertions), `modules/home/development/repository-acquisition.nix` (the include), `modules/vm-tests/shared-reference-tree.nix`.
- Agent guidance: the `dependency-source-acquisition` skill and the reference-repositories context.
- Existing smudged trees on stibnite, magnetite and pyrite need a one-time repair by the writer after deployment.
