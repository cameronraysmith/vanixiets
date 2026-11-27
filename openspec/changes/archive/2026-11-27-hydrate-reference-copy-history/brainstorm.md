# Brainstorm: hydrate reference copy history

Captured 2026-11-26 from the operator's approved outline for the shared reference tree's history, the analysis in `logs/agent-reports-20261126/LazygitSharedTree.md` (written without a shell, so its claims were rechecked here), and measurements made that day in scratch clones under `/tmp`, all since deleted.
No interactive brainstorming took place: the outline was decided first, and this log records how each open point in it was settled and on what evidence.

## Background

Copies in the shared tree are shallow, blobless clones.
An update (`ghq get -u`, a `git pull --ff-only` by the writer) brings in commits and trees but only the blobs of the new tip.
In `/private/var/lib/ghq/github.com/vidhanio/hypertext` (39 commits, git 2.56.0) 92 objects of that history were missing; `git show` of the second newest commit started an on-demand fetch whose `index-pack` could not write `.git/objects/pack/tmp_pack_*`, which is what lazygit's Patch pane showed.
lazygit's start-up fetch (`git.autoFetch`, default `true`) fails in the tree the same way.
The skill's advice, hydrate `<rev>` before `git show <rev>`, is insufficient: a diff needs the parents' blobs too.

The approved outline: (1) the writer fetches the blobs of the history it brings in, after an update and after a deepen, up to a bound, above which the copy behaves as today; (2) lazygit's start-up fetch is off inside the tree through a `.lazygit.yml` at the tree's root, if lazygit reads it from there; (3) remaining misses fail clearly, readers' git in the tree running with on-demand fetching disabled, and the skill and spec say what `git show` and `git diff` need.

## Measurements

What was run, in order, and what each attempt showed.

1. jj and perses, each window in its own scratch directory: `git fetch --filter=blob:none --depth=1 origin <OLD>` and checkout, then `git fetch --filter=blob:none origin <NEW>` and `git merge --ff-only`, as the writer's update does; OLD is GitHub's newest `main` commit before the window's start, NEW `main` on 2026-11-26. Both histories have no merges, so `git rev-list --objects --missing=print OLD..NEW` and the diff listing of Q1 give the same set (jj, one month: 951 both). Each run took 2 to 6 s.
2. nixpkgs the same way, one day: the update fetch was still running after 11 minutes, 430 MB on disk, and was stopped. A depth-1 copy of a repository with merges receives most of its history on its first update (Q9).
3. nixpkgs cloned with `--shallow-since` two or three days before each window: the first-parent chain from the tip was cut after six commits, because `--shallow-since` cuts at any commit older than the date, so the window's start was not held. Abandoned.
4. nixpkgs cloned with `--depth` equal to the window's first-parent length: depth counts along every parent, and the two-day clone passed 1.8 GB. Stopped.
5. nixpkgs through an alternate object directory pointing read-only at the tree's nixpkgs copy, checked out at OLD and then NEW (two-day window only, 320 s): the counts were skewed by the blobs the tree's copy already holds, but it showed that `git log -m --raw` over 1,354 commits takes 124 s and names 42,817 missing blobs, almost all on merges' side-parent diffs, which `git show` never reads.
6. Final method for nixpkgs: the blob ids of each window's diff listing (Q1) computed from the tree's nixpkgs copy, reading commits and trees only with `GIT_NO_LAZY_FETCH=1`, less the blobs of OLD's and NEW's trees (which a copy updated from OLD to NEW holds), fetched by id from GitHub into an empty scratch partial clone with the writer's hydrate flags. OLD is the first-parent commit of the tree copy's `master` before each window's start, NEW the tree copy's `HEAD` (`2a21d231`, 2026-11-26 21:01 UTC). Runs took 4 s, 30 s and 42 s.
7. nix (`NixOS/nix`, merge commits on `master`): a full blobless scratch clone, the same listing and fetch, and, with OLD written to `.git/shallow`, the range a depth-1 copy's first update brings in.
8. A depth-1 blobless clone of nixpkgs with checkout, the first acquisition: 14 s, 84 MB of `.git`.

| Repository, window to 2026-11-26 | Commits (merges) | Blobs fetched | Pack on disk | Uncompressed | Listing | Fetch |
|---|---|---|---|---|---|---|
| jj-vcs/jj, from 2026-11-25 | 11 (0) | 13 | 0.1 MB | 1.6 MB | <0.1 s | 0.3 s |
| jj-vcs/jj, from 2026-11-19 | 103 (0) | 264 | 0.9 MB | 26 MB | <0.1 s | 0.7 s |
| jj-vcs/jj, from 2026-10-26 | 381 (0) | 951 | 1.9 MB | 78 MB | <0.1 s | 1.1 s |
| perses/perses, from 2026-11-19 | 6 (0) | 0 | 0 | 0 | <0.1 s | none |
| perses/perses, from 2026-10-26 | 72 (0) | 211 | 0.5 MB | 4.0 MB | <0.1 s | 0.4 s |
| NixOS/nix, from 2026-11-19 | 79 (21) | 98 | 0.3 MB | 2.6 MB | <1 s | <1 s |
| NixOS/nix, from 2026-10-26 | 362 (95) | 565 | 1.2 MB | 12 MB | <1 s | 1 s |
| NixOS/nix, first update of a depth-1 copy made 2026-11-19 | 25,024 | 61,705 (counted, not fetched) | | | 1.0 s | |
| NixOS/nixpkgs, from 2026-11-25 | 1,354 (577) | 337 | 2.2 MB | 62 MB | 1.3 s | 1.2 s |
| NixOS/nixpkgs, from 2026-11-19 | 6,795 (2,951) | 77,424 | 159 MB | 3.3 GB | 3.4 s | 24.6 s |
| NixOS/nixpkgs, from 2026-10-26 | 28,935 (11,428) | 89,180 | 178 MB | 4.2 GB | 9.9 s | 27.9 s |

Every scratch clone and directory was deleted after its run; nothing was written in the shared tree, which was read only (with lazy fetching disabled), apart from `ghq-sync -u --tags jesseduffield/lazygit` and `ghq-sync --hydrate v0.66.3 jesseduffield/lazygit`, carried out by the writer to read lazygit's source at the installed version.

## Q1: Which blobs make a commit readable as a diff?

The analysis proposed fetching the missing objects of `git rev-list --objects --missing=print OLD..NEW`.
That is every object the range's trees reach and OLD's do not, which on history with merges includes old versions of files on side branches that no diff reads, and on a deepen misses the parent side of the old boundary commit's diff.
What a reader runs is lazygit's `git show … --submodule --stat --decorate -p <hash>`: for a non-merge commit both sides of each changed path; for a merge `--stat` against the first parent plus the combined diff.
Checked on a merge of nix: with only the combined set present the command failed; with the 9 blobs of the first-parent diff added it succeeded.
Decision: list blob ids from `git log --diff-merges=first-parent --raw` and `git log --merges --cc --raw` over the range, without rename detection so that no blob is read; keep the missing ones.
`-m` (every parent) was rejected on measurement 5.

## Q2: Where does it run?

In the writer's handler, after `ghq get -u` and after `ghq-sync --deepen`, inside the per-repository lock the handler holds for the whole request, so no other request sees the copy between the update and its hydrate.
`ghq-sync` stays unchanged apart from its usage text: on a sharing host its `--deepen` is the writer's own call.

## Q3: How are OLD and NEW found?

OLD is `HEAD` before `follow_default_branch`, NEW is `HEAD` after the update.
A changed default branch gives the new branch's commits that OLD does not reach; a forced upstream update fails `pull --ff-only` and leaves `HEAD` alone, so nothing is walked.
A deepen uses `.git/shallow` before and after: the range runs from the boundaries it removed down to, and excluding, the new ones.

## Q4: What form and value does the bound take?

The writer knows commits and trees before fetching blobs, so it can count missing blobs exactly, but cannot know bytes.
Commits are a loose proxy: two days of nixpkgs were 1,354 commits and 337 blobs, one week 6,795 commits and 77,424 blobs, nearly all from one merge's first-parent diff.
Decision: a count of missing blobs, streamed and abandoned once it passes 100,000, which covers every measured window including a month of nixpkgs (89,180, about 28 s and 178 MB) and nix's first-update range (61,705).
Above it: no fetch, the update succeeds, and the reply says `history not hydrated` and names `ghq-sync --hydrate`.

## Q5: What if the hydrate fails?

The copy stays valid; missing blobs are promised objects.
Decision: the reply gets a `history hydrate failed` line, the request's exit status stays the update's or deepen's own.

## Q6: How do the other verbs and policies interact?

`--hydrate` is unchanged (a revision's tree); the skill says a diff needs the parents too.
`promote` (`--full`) refetches every object, so nothing follows it.
Tags fetched at depth 1 by `--tags` are new boundaries outside any range and are not hydrated.
LFS: the fetched blobs are pointer files as committed; the handler's LFS policy applies to the fetch as to every git call it makes, and no checkout runs.
Submodules: gitlinks are skipped and the fetch passes `--recurse-submodules=no`.
A first acquisition has no OLD and is unchanged; measured as 14 s and 84 MB for nixpkgs.

## Q7: Disk growth and pruning

Each hydrating update adds one promisor pack of its window's blobs: under 2 MB a month for jj, perses and nix, about 178 MB for a month of nixpkgs in one update.
Nothing prunes reachable objects, and nothing does today either.
The tree's nixpkgs copy is 2.5 GB in 1,688 packs, so packs already accumulate without consolidation; repacking is left to a separate change.

## Q8: How do readers' misses fail clearly?

Three runs of `git show` of an older commit in a scratch blobless clone of hypertext whose `.git/objects` was made read-only, each exiting 128:
plain, `Unable to create temporary file … Permission denied`, `index-pack failed`, `could not fetch <oid> from promisor remote`;
with `GIT_NO_LAZY_FETCH=1`, `warning: lazy fetching disabled; some objects may not be available`, `could not fetch <oid> from promisor remote`;
with a global configuration including `protocol.allow = never` under `includeIf "gitdir:<scratch root>/"`, `transport 'https' not allowed`, `could not fetch <oid> from promisor remote`.
`git status` and `git log` still worked under the include, and a local `git clone` of the copy behaved the same with and without it.
The outline offered an environment variable set by the `ghq` and lazygit wrappers, or a `git` wrapper.
The repository installs a `ghq` wrapper that never runs a reader's git, and no lazygit wrapper (lazygit is reached through `lg`, an alias, and herdr's `htab lazygit`).
A lazygit wrapper would leave agents' `git -C <path>` uncovered; a `git` wrapper would cover it at the cost of parsing git's global options and of `PATH` order for every program.
The gitdir include is narrower than either and covers both, through the mechanism the LFS policy already uses and the hosts already assert.
Decision: `protocol.allow = never` under the existing includes, asserted, with no `protocol.<name>.allow` allowed in participants' settings (such a key outranks it).
It also refuses a reader's `git fetch`, `git ls-remote origin` and `git remote show origin` inside a copy; the first was refused anyway, the others are accepted losses.

## Q9: The first update of a depth-1 copy with merges

A depth-1 blobless clone of nix at `master` of 2026-11-19, updated a week later, received 25,024 commits for 21 first-parent ones: the shallow boundary is one commit, and every merge's second parent leads past it, so the server sends nearly all history.
The tree's nixpkgs copy, cloned shallow, holds 1,131,078 commits.
Decision: out of scope; the hydrate treats that range like any other, hydrating nix's (61,705 blobs) and reporting nixpkgs' as over the bound, and every later update brings in a true window.

## Q10: Does lazygit read `<root>/.lazygit.yml`?

Source, lazygit 0.66.3 (the installed version, read in the tree's copy at tag `v0.66.3`): `getPerRepoConfigFiles` in `pkg/gui/gui.go` prepends `.lazygit.yml` of every ancestor directory of `RepoPath`, which `repoPathsForDir` in `pkg/commands/git_commands/repo_paths.go` takes from `git rev-parse --show-toplevel`, a resolved path; `onNewRepo` loads them before `startBackgroundRoutines` (`pkg/gui/background.go`) starts the immediate fetch.
Run: lazygit 0.66.3 under a pseudo-terminal for 8 s with `CONFIG_DIR` set to a scratch directory (popups off), `GIT_TRACE` to a file, in a scratch blobless clone three levels below a scratch root: with `git.autoFetch: false` in the root's `.lazygit.yml` no `git fetch` was traced; without the file `git fetch --all --no-write-fetch-head` was.
Not shown: the accounts' own lazygit configuration on a sharing host, and lazygit's rendering of a refused diff.
Decision: the modules provision the file at the root, owned by the writer, and the migration tool keeps a root holding only it "empty".

## Q11: Where do the witnesses go?

Handler behaviour (ranges, merges, default-branch change, the bound, failure, deepen, first acquisition) in `pkgs/by-name/ghq-shared/test_handler.py`, where `historyLimit` can be set small and a failing fetch staged.
The reader's view end to end in `vmTests.x86_64-linux.shared-reference-tree-migration` (33 to 35 s of 60 s, the smaller of the two), whose node already runs the writer, readers with Home Manager includes and `git://` fixtures: about 2 to 3 s more.
`shared-reference-tree`'s "readers cannot write the tree" gains the `-c protocol.allow=always` probe, so its `git fetch` assertion keeps meeting the permission check.

## Q12: What stays manual

Reading a commit the writer did not hydrate (history from before the change, ranges over the bound or failed, depth-1 tags, the deepest commits after a deepen) needs `ghq-sync --hydrate` of the revision and of each parent.

## Open points

Carried in `design.md` under Open Questions, each with its recommended answer.
