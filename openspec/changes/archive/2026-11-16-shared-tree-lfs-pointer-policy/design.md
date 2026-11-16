## Context

The shared reference tree has one writer; its request handler runs git with no system or global configuration and a `PATH` of git and coreutils only, so it never had git-lfs.
Readers' git configuration, from Home Manager, enables git-lfs with smudging for every repository.
Trees an administrator owned before migration were moved in place with their working trees as they were, so LFS paths kept the content git-lfs had written.

## Goals / Non-Goals

**Goals:** updates of LFS repositories fast-forward; readers' git never writes in the shared tree; readers can read a blobless clone at any revision whose commit it holds.

**Non-Goals:** serving LFS object content from the shared tree; overriding a repository-local LFS filter setting for readers.

## Decisions

### D1: pointer-only, stated in every git invocation that touches the tree

The policy is four configuration keys: `filter.lfs.process`, `filter.lfs.clean` and `filter.lfs.smudge` empty, `filter.lfs.required` false.
An empty process or command makes git treat the path as unfiltered.
The handler passes them through `GIT_CONFIG_COUNT`, the command scope, which outranks a repository's own `.git/config`, so a repository whose configuration names git-lfs cannot re-enable it for the writer.
The migration tool's writer git uses the same keys.
`flake.lib.sharedReferenceTreeLfsPolicy` holds the attribute set the Home Manager include and the host assertions share; the handler and migration tool are Python and carry the same four keys literally, each naming the other.

### D2: readers through a conditional include per root form

`programs.git.includes` gains one entry per form git may resolve the root to, `gitdir:/var/lib/ghq/` and, on darwin, `gitdir:/private/var/lib/ghq/`.
On stibnite only the `/private` form matches, whether the repository is reached through `/var`, `/private/var` or `~/ghq`, because git matches the resolved git directory; both are kept so the include does not depend on that.
Home Manager renders includes after the `[filter "lfs"]` section, so the include's values win over the account's own LFS settings.
The darwin and NixOS adapters assert the include for every root form in `services.shared-reference-tree.rootForms` for each participant.

### D3: migration sets smudged LFS paths back to pointers, reversibly

After the root is opened to the writer and while the writer's socket is still stopped, the tool runs git as the writer, with umask `0027`, in each moved repository: it finds index paths with the `lfs` filter attribute whose file's SHA-256 and size equal the oid and size of the staged pointer, moves each such file into the record directory, records the step with a copy of the index, checks the paths out from the index, and refreshes the index.
A file whose content differs from its pointer's object is a real change and is left as it is.
Rollback moves each kept file back and restores the index, writing through no symbolic link and nothing outside the repository, before the ownership restore puts back owners and modes.

### D4: hydrate fetches exactly the missing objects of one revision's tree

`ghq-sync --hydrate REV` resolves REV to a commit already in the clone, with lazy fetching disabled, takes its tree from the commit object, lists the tree's missing objects with `git rev-list --objects --missing=print`, and fetches them in one request with the arguments git's own promisor fetch uses (`--filter=blob:none --stdin`, noop negotiation, no tags, no `FETCH_HEAD`), repeating while a fetched tree reveals more.
`git backfill <rev>` was rejected: it fetches the blobs of a revision range's history rather than of one tree, is documented as experimental, and with its default edges includes the parent's blobs.
The handler accepts `hydrate` with a `rev` matching a ref or object name optionally followed by `~N` or `^N`, without `..`, and a path inside the root, and runs `ghq-sync --hydrate REV PATH` as the writer under its protocol allow-list.

## Risks / Trade-offs

- A repository-local `filter.lfs.*` setting outranks a reader's global include; such a repository's reader git still runs git-lfs, which fails as before without changing the tree.
- An LFS-tracked binary reads as its pointer in the shared tree; its content comes from the upstream host.
- Migration's kept LFS content occupies the record directory until the operator authorizes deleting it.
