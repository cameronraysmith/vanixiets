## Context

Copies in the shared reference tree (`/var/lib/ghq`, `/private/var/lib/ghq` on stibnite, 668 repositories in 201 GB there) are shallow blobless clones: `remote.origin.promisor = true`, `remote.origin.partialclonefilter = blob:none`.
The writer (`pkgs/by-name/ghq-shared/ghq-writer-handler.py`) updates one with `ghq get -u`, which runs `git pull --ff-only`: the commits and trees of the new history arrive, but only the blobs the new checkout needs.
On 2026-11-26 `/private/var/lib/ghq/github.com/vidhanio/hypertext` held 39 commits with 92 objects of their history missing.
A reader's `git show` of the second newest commit starts an on-demand fetch whose `index-pack` cannot create `.git/objects/pack/tmp_pack_*` (`Permission denied`, then `could not fetch <oid> from promisor remote`); lazygit's Patch pane shows exactly that.
lazygit also fetches at start-up (`git.autoFetch`, default `true`), which fails in the tree for the same reason.
`ghq-sync --hydrate <rev>` fetches the blobs of `<rev>`'s tree, which readies `git show <rev>:<path>` but not `git show <rev>`, whose diff needs the parents' blobs too.

The writer holds an exclusive lock per repository for each request's whole operation (`hold` in the handler); the work this change adds runs inside it.
The tree's readers are participating accounts whose Home Manager git configuration already carries the LFS policy under `includeIf "gitdir:<root form>/"` (`modules/home/development/repository-acquisition.nix`), and every sharing host asserts those includes (`modules/nixos/shared-reference-tree.nix`, `modules/darwin/shared-reference-tree.nix`).
The measurements behind the decisions below, with what was run, are in `brainstorm.md`.

Boundaries: every file this change edits is first-party source (the handler, the migration tool, `ghq-sync`'s usage text, the modules, the runtime test, the skill under `modules/home/ai/plugins/`); lazygit is vendored and only read, at the installed version 0.66.3.
Delivery to the hosts is by deploy; a copy changes only at its next update or deepen after its host's deploy.

## Goals / Non-Goals

**Goals:**
- After an update or a deepen, every commit it brought in is readable as lazygit shows it (`git show --stat -p <commit>`) with on-demand fetching disabled, up to a bound the writer checks before fetching.
- Above the bound, or when the fetch fails, the update or deepen succeeds as today and the reply says so, naming `ghq-sync --hydrate`.
- A reader's git never attempts an on-demand fetch beneath the shared root: a read that needs absent content fails at once with git's missing-object message, never a permission error.
- lazygit started in a copy shows no fetch error.
- A first acquisition (depth 1) costs what it costs today.

**Non-Goals:**
- Hydrating history fetched before this change, or history a skipped or failed hydrate left behind; `ghq-sync --hydrate` stays the way to read it.
- Changing which commits and trees an update fetches, including the first update of a depth-1 copy of a repository with merges, which brings in most of its history (D9).
- Repacking or pruning copies.
- LFS content, submodule contents, and the trees of tags fetched at depth 1.

## Decisions

### D1: Fetch the blobs each brought-in commit's diff needs, as lazygit shows it

- **Choice**: with `GIT_NO_LAZY_FETCH=1`, the writer lists the blob ids on every side of each raw line of `git log --diff-merges=first-parent --raw --no-abbrev --no-renames --format= <range>` and of `git log --merges --cc --raw --no-abbrev --no-renames --format= <range>`, skipping gitlinks (mode `160000`) and the null id; keeps those `git cat-file --batch-check` reports missing; and fetches them as `hydrate_one` in `pkgs/by-name/ghq-sync/ghq-sync.sh` does: `git -c fetch.negotiationAlgorithm=noop fetch --no-tags --no-write-fetch-head --recurse-submodules=no --filter=blob:none --stdin origin`, a further pass only while the missing set shrinks, and never with an empty list (an empty `--stdin` fetch falls back to the remote's default refspec: 31 MB of `NixOS/nix` in a scratch clone).
- **Rationale**: lazygit's Patch pane runs `git show` with its common diff arguments, which include rename detection, and `--submodule --stat --decorate -p <hash>` (lazygit 0.66.3, `ShowCmdObj` in `pkg/commands/git_commands/commit.go`). For a non-merge commit that reads both sides of every path it changed (rename detection reads only added and deleted paths, which the raw lines name). For a merge, `--stat` is taken against the first parent, and the combined diff reads every side of the paths that differ from all parents. Shown on 2026-11-26 in a scratch blobless clone of `NixOS/nix` with lazy fetching disabled: lazygit's command line on merge `a347df06` failed with only the combined set fetched (empty) and succeeded once the 9 blobs of its first-parent diff were fetched. The listing reads commits and trees only, never a blob: 9.9 s for one month of nixpkgs `master` (28,935 commits).
- **Alternatives considered**: `git rev-list --objects --missing=print OLD..NEW` (the analysis's proposal): equal on linear history (jj, one month: 951 objects both ways), but on history with merges it takes every object a side branch's trees reach rather than what a diff reads, and it misses the parent side of a deepen's old boundary. `git log -m --raw` (every parent of a merge): adds each merge's diff against its side parent, which `git show` never reads; for nixpkgs from 2026-11-25 to 2026-11-26 (1,354 commits) it named 42,817 blobs a scratch copy lacked and took 124 s to list, against 337 blobs and 1.3 s for D1's listing.
- **Boundary**: first-party handler; the listing's form follows vendored lazygit's command, re-checked by task 4.1 at a lazygit bump.

### D2: OLD and NEW for an update

- **Choice**: OLD is `HEAD`'s commit before `follow_default_branch` runs; NEW is `HEAD`'s commit after `ghq get -u`. The walk runs only when the clone existed before the request, `remote.origin.promisor` is `true`, and OLD and NEW both resolve and differ.
- **Rationale**: `OLD..NEW` is what the request brought in as a reader sees it, including a new default branch's commits (the range is then NEW's commits that OLD does not reach). A forced update upstream makes `pull --ff-only` fail, `HEAD` stays at OLD and nothing is walked; the update's own failure is reported as today. A first acquisition has no OLD and is untouched.
- **Alternatives considered**: remote-tracking refs before and after: they move on a `--tags` fetch and on `follow_default_branch`'s fetch without changing what is checked out.

### D3: Deepen

- **Choice**: before running `ghq-sync --deepen`, the handler reads `.git/shallow`; after it, the range is `<boundaries removed> ^<boundaries now present>`, listed as in D1.
- **Rationale**: the commits a deepen brings in lie between the old and new boundaries; the old boundary commits gain a parent and so a diff, whose parent side D1's listing names. The new boundary commits show as root commits, adding every file; a blob of their trees is present when the checkout or a later commit's hydrated diff needed it, which covers the whole tree when every commit above has been hydrated, but no whole tree is fetched for them, so a reader may still need `ghq-sync --hydrate` for one. Boundaries the deepen did not move, such as a tag fetched at depth 1, are not walked.
- **Boundary**: the deepen itself stays in `ghq-sync.sh` (`deepen_one`), which the handler runs as today.

### D4: The bound counts missing blobs, 100,000, and stops early

- **Choice**: the writer counts missing blobs from the D1 listing as it streams and stops reading, terminating the `git log` it reads from, once the count exceeds `historyLimit`: 100,000 unless the handler's configuration names another value (decided 2026-11-27). It checks the listed ids with `git cat-file --batch-check` in batches of the smaller of 10,000 ids and the larger of one more than the count still allowed and a sixteenth of the ids listed so far, so the walk stops at the first batch that passes the limit, and a long walk close to it still checks in few batches. Above it nothing is fetched and the reply carries `history not hydrated: <path> (more than <limit> blobs missing; ghq-sync --hydrate REV makes a revision readable)`.
- **Rationale**: bytes cannot be known before fetching, and the commit count is a loose proxy (nixpkgs, about two days: 1,354 commits, 337 blobs; one week: 6,795 commits, 77,424 blobs, almost all from one merge's first-parent diff). The missing-blob count is known from local trees before any blob moves and is what the fetch's time and size follow. 100,000 covers every window measured: a month of nixpkgs `master` (89,180 blobs, 178 MB of pack, 28 s of fetch), a month of jj (951), perses (211) and nix (565), and the first update of a depth-1 copy of nix, which brought in 25,024 commits (61,705 blobs). The request then holds its lock for well under a minute more, against the 3600 s a queued request waits. Stopping the stream keeps the walk cheap when an update brought in a very long history (D9).
- **Alternatives considered**: a commit count (known earlier, loosely tied to cost); a byte bound (unknowable before fetching); no bound (a long-unrefreshed nixpkgs copy could hold its lock for minutes and add gigabytes).
- **Boundary**: first-party handler configuration; the NixOS and darwin modules pass no `historyLimit`, so the default applies; the handler tests set a small one.

### D5: A failed or skipped hydrate never fails the request

- **Choice**: the work appends one status line with exit status zero: `hydrated history: <path> (<n> objects fetched)`, `history not hydrated: …` or `history hydrate failed: <path> (<reason>)`. Objects already fetched stay. The request's exit status remains the first non-zero status of the update or deepen itself.
- **Rationale**: the copy is valid either way: a missing blob is a promised object, which a reader's `ghq-sync --hydrate` fetches later. Failing the update would make `ghq-sync -u` report a fault the reader cannot act on.
- **Alternatives considered**: recording an unhydrated range for a later request to retry: not adopted on 2026-11-27, `ghq-sync --hydrate` serves unhydrated history.

### D6: Readers' git refuses every transport beneath the shared root

- **Choice**: the include under each `gitdir:` form of the shared root that already carries the LFS policy also sets `protocol.allow = never`; the hosts' assertions require it for every participant and form, and reject a `protocol.<name>.allow` key in a participant's git settings, since such a key outranks `protocol.allow`.
- **Rationale**: git has no configuration key that disables on-demand fetching (only `--no-lazy-fetch` and `GIT_NO_LAZY_FETCH`), but the on-demand fetch is a `git fetch` child reading the same configuration, so refusing its transport stops it before `index-pack` tries to write. Measured on 2026-11-26 in a scratch blobless clone of `vidhanio/hypertext` with `.git/objects` made read-only (git 2.56.0), `git show` of an older commit exiting 128 each time: plainly, `Unable to create temporary file '…/tmp_pack_XXXXXX': Permission denied`, `index-pack failed`, `could not fetch <oid> from promisor remote`; with `GIT_NO_LAZY_FETCH=1`, `warning: lazy fetching disabled; some objects may not be available` and `could not fetch <oid> from promisor remote`; with the include, `transport 'https' not allowed` and `could not fetch <oid> from promisor remote`. `git status` and `git log` were unaffected, and a local `git clone <copy> <dir>` behaved the same with and without the include. Scoped by git itself to repositories beneath the root, the include covers lazygit, an agent's `git -C <path>` run from anywhere, editors, and every other program that runs git as the account, with no wrapper.
- **What it does not cover**: an account's own `-c` or `GIT_CONFIG_*` overrides; programs that read objects without git's configuration (libgit2, gitoxide), which do not fetch on demand anyway. It also refuses readers' network reads from inside a copy, `git ls-remote origin` and `git remote show origin`, and `git fetch --no-write-fetch-head`; `git ls-remote <url>` run outside a copy still works. A plain `git fetch` opens `.git/FETCH_HEAD` for writing before it connects, so the operating system still refuses it first, with `cannot open '.git/FETCH_HEAD': Permission denied`, as before this change (runtime test, 2026-11-27).
- **Path forms**: git matches a `gitdir:` pattern against the repository path as reached and against its resolved path. On stibnite (git 2.56.0, 2026-11-27, a copy of `vidhanio/hypertext`, a scratch global configuration holding one include at a time), the `/private/var/lib/ghq/` form applied in every spelling (`~/ghq/…`, `/var/lib/ghq/…` and `/private/var/lib/ghq/…`, as the working directory and through `git -C`), and the `/var/lib/ghq/` form only when the shell's working directory was spelled `/var/lib/ghq/…`; darwin's includes therefore carry both forms, which the module asserts. On NixOS `/var/lib/ghq` is its own resolved path and `~/ghq` a link to it, so the one form covers every spelling.
- **Alternatives considered**: `GIT_NO_LAZY_FETCH=1` set by wrappers. The `ghq` wrapper (`pkgs/by-name/ghq-shared/ghq.sh`) runs no reader git, and lazygit has no wrapper, only the `lg` alias (`modules/home/shell/aliases.nix`); a new lazygit wrapper would cover lazygit started inside the root but not an agent's plain `git -C`. A `git` wrapper ahead of git on `PATH`, setting the variable when `-C`, `--git-dir`, `GIT_DIR` or the working directory resolves beneath the root: covers both, but must parse git's global options, depends on `PATH` order for every program that runs git (lazygit and jj take `git` from `PATH`), and runs on every git call the account makes. A global `GIT_NO_LAZY_FETCH` in the session environment: also turns off on-demand fetching in the account's own partial clones.
- **Boundary**: first-party Home Manager and host modules.

### D7: lazygit's start-up fetch is off through `<root>/.lazygit.yml`

- **Choice**: each sharing host provisions `<root>/.lazygit.yml` holding `git:` / `  autoFetch: false`, a regular file owned by the writer and its group with mode `0640`: a tmpfiles `f+` rule on NixOS, and on darwin the activation step that provisions the root before the writer's daemon loads. `ghq-shared-migrate` counts a root holding only that file as empty, moving the file into its record directory around a whole-tree rename and back.
- **Rationale**: lazygit 0.66.3 reads `.lazygit.yml` in every ancestor directory of the repository path (`pkg/gui/gui.go`, `getPerRepoConfigFiles`), which it takes from `git rev-parse --show-toplevel` (`pkg/commands/git_commands/repo_paths.go`, `repoPathsForDir`), a resolved path; `onNewRepo` loads those files before `startBackgroundRoutines` starts the fetch (`pkg/gui/gui.go`, `pkg/gui/background.go`). It loads the account's own configuration files first and then the per-repository ones, outermost ancestor first and `<gitdir>/lazygit.yml` last, each decoded onto the same settings (`ReloadUserConfigForRepo` and `loadUserConfig` in `pkg/config/app_config.go`), so a later file overrides only the keys it sets: the root file decides `git.autoFetch`, every other key of the account's configuration stays in force, and custom commands accumulate. Shown on 2026-11-26 by running lazygit 0.66.3 under a pseudo-terminal for 8 s with `CONFIG_DIR` pointing at a scratch directory, start-up popups off and `GIT_TRACE` set, in a scratch blobless clone three directories below a scratch root: with the file at the root no `git fetch` ran; without it `git fetch --all --no-write-fetch-head` ran. Repeated on stibnite on 2026-11-27 with a copy of the account's own lazygit configuration (which sets no `git.autoFetch`) and with that configuration plus `git.autoFetch: true`, the intro marked seen in `state.yml`: without the root file one `git fetch --all --no-write-fetch-head` ran within 8 s; with it none ran under either configuration. (`disableStartupPopups: true` in a configuration keeps lazygit 0.66.3 from fetching at all, so it cannot stand in for a seen intro in such a run.) A writer-owned file keeps the root's ownership invariant (`find <root> ! -user <writer>` is empty, which the runtime tests assert); lazygit's automatic config migration never needs to rewrite a file holding only this key.
- **Alternatives considered**: `autoFetch: false` in each account's lazygit settings (turns it off everywhere); `/var/lib/.lazygit.yml` (outside the tree, but read for every repository under `/var/lib`); `<gitdir>/lazygit.yml` in each copy (written into every repository at every acquisition).
- **Boundary**: first-party modules and migration tool; the lookup is vendored lazygit behaviour, observed at 0.66.3.

### D8: Readers are told what a diff needs

- **Choice**: the skill's reference-repository paragraph, `ghq-sync --hydrate`'s usage text and the interface spec say that commits an update or deepen brought in are readable up to the bound, that `git show <rev>` otherwise needs `<rev>` and each parent hydrated (`ghq-sync --hydrate <rev>` and `--hydrate <rev>^<n>`), that `git diff A B` needs `A` and `B`, and what the refusal looks like.
- **Rationale**: the approved outline; `--hydrate` stays a one-revision tree fetch.
- **Alternatives considered**: making `--hydrate <rev>` also fetch the D1 set for `<rev>` alone, so one request readies `git show <rev>`: left to a later change on 2026-11-27.

### D9: The first update of a depth-1 copy of a repository with merges

- **Choice**: unchanged in what it fetches; its range is walked like any other, so it is hydrated when its missing blobs are within the bound and reported otherwise.
- **Rationale**: measured on 2026-11-26: a depth-1 blobless clone of `NixOS/nix` at `master` of 2026-11-19, updated a week later (21 first-parent commits), received 25,024 commits, because each merge's second parent leads past the single shallow boundary; that range needs 61,705 missing blobs, within the bound. A depth-1 copy of nixpkgs updated one day later was still transferring after 11 minutes and 430 MB when stopped, and the tree's own nixpkgs copy, cloned shallow, holds 1,131,078 commits; such a range exceeds the bound, and the early stop keeps its walk cheap. Every later update brings in a true window. Changing how updates fetch changes which history a copy holds, which is outside this change and left to a later one (decided 2026-11-27).

### D10: The exit log line carries the history fetch's outcome

- **Choice**: when a request ran a history walk, its exit log line adds `history=hydrated:<n>`, `history=not-hydrated` or `history=failed` after the duration and before a failure's ` reason:`; a request that ran none adds nothing.
- **Rationale**: the replies go to the readers; the writer's journal then shows which updates left history unreadable. The token names neither the target nor a command's arguments, as the requirement defining the line asks (`The writer logs each request without its target`, archived with `serialise-shared-reference-tree-writes`).
- **Alternatives considered**: the failure's reason on the line as well: the reply carries it, and the reason of a failed request already follows ` reason:`.

### D11: The history fetch and automatic maintenance

- **Choice**: the history fetch runs after `ghq get -u` or `ghq-sync --deepen` has returned, so after the automatic maintenance that git runs at the end of the update's own fetch. The history fetch is a `git fetch` too, so git runs automatic maintenance again after it, in the foreground with the gc strategy (the handler's `MAINTENANCE_POLICY`), under the same lock. The order within a request is: update, its maintenance, history fetch, maintenance.
- **Rationale**: each history fetch adds one promisor pack. The gc strategy consolidates promisor packs once more than `gc.autoPackLimit` (default 50) are present, and repacks promisor objects into a promisor pack, keeping them; the blobs are reachable from the copy's history in any case. Shown by the handler test case "An update of a blobless clone makes every commit it brought in readable as a diff with lazy fetching disabled" with `gc.autoPackLimit` 1 and `gc.pruneExpire` now set on the clone: after the request the clone holds one pack, so the maintenance after the history fetch consolidated that fetch's pack, and every commit the update brought in still reads with lazy fetching disabled.
- **Alternatives considered**: `--no-auto-maintenance` on the history fetch, leaving consolidation to a later request's fetch: the pack would wait for that request, with nothing gained.

## Risks / Trade-offs

- [Risk] The hydrate lengthens a request that holds the repository's lock, so a queued request waits longer. → Mitigation: the bound keeps the added fetch under about 30 s on every window measured; the lock wait is 3600 s.
- [Trade-off] Disk grows by each update's fetched blobs: about 178 MB of pack for a month of nixpkgs in one update, and at most a few MB a month for the other repositories measured; nothing prunes it, as nothing prunes the history updates already add. Each history fetch adds a promisor pack, which the maintenance after it consolidates with the others once more than `gc.autoPackLimit` are present (D11). → Accepted.
- [Trade-off] Readers' `git ls-remote origin` and `git remote show origin` inside a copy are refused. → Accepted; `git ls-remote <url>` from elsewhere and `ghq-sync --audit` serve.
- [Risk] A lazygit release changes its per-repository configuration lookup or its show command. → Mitigation: task 4.1's inspection at each deploy that bumps lazygit; D6 keeps any failure immediate and clear.
- [Risk] The runtime test's write probe `git fetch` becomes vacuous, refused before any write. → Not so: a plain `git fetch` still meets the permission error on `.git/FETCH_HEAD` before connecting; task 2.3 runs it, and `git fetch --no-write-fetch-head`, which reaches the transport and is refused there.

## Migration Plan

Deploy order: magnetite, pyrite, stibnite, each by its usual deploy; a host's copies gain the hydrate at their next update or deepen after its deploy, and its readers the include at their next Home Manager activation.
`<root>/.lazygit.yml` appears at activation; on a host not yet migrated, `ghq-shared-migrate` moves it aside around the rename (D7).
Rollback: revert the commits and deploy; fetched blobs stay as valid objects, and the include goes with the configuration; the tmpfiles rule's removal leaves `.lazygit.yml`, which an administrator removes as the writer.

## Decisions of 2026-11-27

The plan's open questions were settled on 2026-11-27.

1. The bound is 100,000 missing blobs per update or deepen, `historyLimit`, as D4 proposed.
2. The read-side refusal is `protocol.allow = never` under the shared root's existing `gitdir:` includes, as D6 proposed, accepting that a reader's `git ls-remote origin` and `git remote show origin` inside a copy are refused.
3. `ghq-sync --hydrate <rev>` fetching the parent side of `<rev>`'s diff is left to a later change; the skill keeps the per-parent step (D8).
4. Unhydrated history gets no retry record; `ghq-sync --hydrate` serves it (D5).
5. The rewording of the scenario "A participating account bypasses the wrapper" of `Acquisition is delegated to the writer through a socket-activated entry point` was to follow in a later spec-only change. The runtime test of 2026-11-27 showed it unnecessary: a reader's plain `git fetch` opens `.git/FETCH_HEAD` before it connects and is still refused by the operating system with a permission error, so the scenario stays true as written.
6. The first update of a depth-1 copy of a repository with merges, which brings in most of its history (D9), is left to a later change.
7. The hydrate's outcome is on the writer's exit log line (D10), delivered with the commit that adds the history fetch.
8. Pack accumulation is no longer open: the writer runs git's automatic maintenance in the foreground with the gc strategy, which consolidates promisor packs within the request; D11 places the history fetch before the maintenance that consolidates its pack.

## Open Questions

None.
