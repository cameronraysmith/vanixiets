## ADDED Requirements

### Requirement: An update makes every commit it brought in readable as a diff

On a `get` with an update of a clone whose `remote.origin.promisor` is true, the writer SHALL, before releasing the repository's lock, fetch every blob the clone lacks that `git log --diff-merges=first-parent --raw` or `git log --merges --cc --raw` names for `OLD..NEW`, OLD and NEW being its `HEAD` commit before and after the request, in one request per pass with the clone's filter and depth.
It SHALL report the outcome in one status line.

#### Scenario: An update brings in commits

- **WHEN** a `get` with an update of a blobless clone brings in commits, including merges and a change of default branch
- **THEN** a participating account's `git --no-lazy-fetch show --stat -p <commit>` succeeds for every commit in `OLD..NEW`, the clone's filter and shallow boundaries are unchanged, and the reply holds `hydrated history: <path> (<N> objects fetched)`

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "An update of a blobless clone makes every commit it brought in readable as a diff with lazy fetching disabled"; `vmTests.x86_64-linux.shared-reference-tree-migration`, subtest "an update makes the commits it brought in readable, and a read the writer did not prepare fails at once".

#### Scenario: An update of a full clone

- **WHEN** a `get` with an update names a clone with no promisor remote, or brings in no commit
- **THEN** the writer runs no history walk and fetches nothing more than the update did

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "An update of a full clone, or one that brings in nothing, walks no history".

### Requirement: A deepen makes every commit it brought in readable as a diff

On a `deepen` of a clone whose `remote.origin.promisor` is true, the writer SHALL, before releasing the repository's lock, fetch every blob the clone lacks that the same two listings name for the commits from each shallow boundary commit the deepen removed down to, and excluding, the new boundary commits, by the same passes and with the same status line as an update.

#### Scenario: A blobless clone is deepened

- **WHEN** a participating account deepens a blobless clone by N commits
- **THEN** its `git --no-lazy-fetch show --stat -p <commit>` succeeds for every commit the deepen brought in except the new boundary commits, and for the previous boundary commits

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "A deepen makes every commit it brought in, but the new deepest, readable as a diff".

### Requirement: The writer bounds the history it makes readable

Before fetching any blob for an update or a deepen, the writer SHALL count the missing blobs, stopping once the count exceeds its history limit, 100,000 unless its configuration's `historyLimit` says otherwise; above the limit it SHALL fetch none and report `history not hydrated: <path> (more than <limit> blobs missing; ghq-sync --hydrate REV makes a revision readable)`.

#### Scenario: An update brings in more missing blobs than the limit

- **WHEN** a `get` with an update brings in commits whose diffs need more missing blobs than the history limit
- **THEN** the writer fetches no blob for them, the update's exit status is unchanged, the reply holds the `history not hydrated` line, and the walk stopped once the count passed the limit

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "An update bringing in more missing blobs than the limit fetches none and says so".

### Requirement: A failed history fetch leaves the request's outcome as it was

When the walk or the fetch that makes an update's or a deepen's commits readable fails, the writer SHALL leave the request's exit status as the update or deepen alone set it and report `history hydrate failed: <path> (<reason>)` in one status line, keeping every object it already fetched.

#### Scenario: The remote refuses the history fetch

- **WHEN** the remote serves an update but refuses the fetch of the missing blobs
- **THEN** the update's exit status is zero, its new commits are checked out, and the reply holds the `history hydrate failed` line

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "A history fetch that fails leaves the update's exit status and says so".

### Requirement: The writer's exit log line names what the history fetch did

When an update or a deepen runs the walk that makes its commits readable, the writer SHALL add to the request's exit log line, after the duration and before any failure's reason, `history=hydrated:<N>`, `history=not-hydrated` or `history=failed`, naming neither the target nor a command's arguments; a request that runs no walk SHALL add none.

#### Scenario: Requests that run a history walk end

- **WHEN** a `get` with an update of a blobless clone is hydrated, exceeds the history limit, or meets a refused history fetch
- **THEN** its exit log line holds `history=hydrated:<N>`, `history=not-hydrated` or `history=failed` respectively, and the refused fetch adds no ` reason:`

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, cases "An update of a blobless clone makes every commit it brought in readable as a diff with lazy fetching disabled", "An update bringing in more missing blobs than the limit fetches none and says so" and "A history fetch that fails leaves the update's exit status and says so".

#### Scenario: A request runs no history walk

- **WHEN** a `get` with an update names a full clone, or brings in no commit
- **THEN** its exit log line holds no `history=` token

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "An update of a full clone, or one that brings in nothing, walks no history".

### Requirement: A first acquisition fetches nothing more than before

A lazy `get` of a repository absent from the shared root SHALL fetch at depth 1 with the `blob:none` filter and SHALL fetch no blob beyond those its checkout needs; the writer SHALL run no history walk for it.

#### Scenario: A participating account acquires a missing repository

- **WHEN** a lazy `get` names a repository absent from the shared root
- **THEN** the clone holds one commit, every blob it holds belongs to that commit's tree, and the reply holds no history status line

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "A first lazy acquisition fetches no blob beyond its tip's tree".

### Requirement: Participating accounts' git refuses every transport beneath the shared root

Each participating account's git configuration SHALL set `protocol.allow` to `never` under the same `gitdir:` conditions that carry the LFS settings, and SHALL set no `protocol.<name>.allow` key, so its git neither fetches on demand nor fetches explicitly beneath the shared root; the host's configuration SHALL fail evaluation otherwise.
Trust boundary: `-c` or environment overrides an account passes, and programs that read no git configuration, are not covered.

#### Scenario: A participating account reads content the clone lacks

- **WHEN** a participating account runs `git show <commit>` in a clone beneath the shared root that lacks a blob the diff needs
- **THEN** git exits non-zero at once with `transport '<scheme>' not allowed` and `could not fetch <oid> from promisor remote`, reports no permission error, and nothing beneath the shared root changes

Witness: `vmTests.x86_64-linux.shared-reference-tree-migration`, subtest "an update makes the commits it brought in readable, and a read the writer did not prepare fails at once".

#### Scenario: A participating account fetches directly

- **WHEN** a participating account runs `git fetch` in a clone beneath the shared root, and again with `--no-write-fetch-head`, and runs `git ls-remote origin` and `git remote show origin` there
- **THEN** the first is refused by the operating system with a permission error on `.git/FETCH_HEAD`, which git opens before it connects, and each of the others is refused before any transport starts with `transport '<scheme>' not allowed`

Witness: `vmTests.x86_64-linux.shared-reference-tree`, subtest "readers cannot write the tree" (both fetches); `vmTests.x86_64-linux.shared-reference-tree-migration`, subtest "an update makes the commits it brought in readable, and a read the writer did not prepare fails at once" (`ls-remote` and `remote show`).

#### Scenario: A participant lacks the setting

- **WHEN** a participating account's evaluated git includes lack `protocol.allow = never` for a form of the shared root, or set a `protocol.<name>.allow` key
- **THEN** that host's configuration fails evaluation, naming that account

Witness: the assertions of `modules/nixos/shared-reference-tree.nix`, `modules/darwin/shared-reference-tree.nix` and, for darwin Omnigent workers, `modules/darwin/omnigent-host.nix`, evaluated by the per-machine checks of magnetite, pyrite and stibnite.

### Requirement: lazygit fetches nothing at start-up beneath the shared root

Each sharing host SHALL provision `<shared root>/.lazygit.yml`, a regular file owned by the writer and its group with mode `0640`, setting `git.autoFetch` to `false`, which lazygit reads for every repository beneath the shared root.
Migration SHALL leave that file in place, owned by the writer.
lazygit reads that file after the account's own configuration, so it decides `git.autoFetch` for every copy, and every other key the account's configuration sets still applies.

#### Scenario: A participating account opens lazygit in a clone

- **WHEN** a participating account starts lazygit in a clone beneath the shared root
- **THEN** lazygit runs no `git fetch` and shows no fetch error

Witness: `vmTests.x86_64-linux.shared-reference-tree-migration`, subtest "lazygit's start-up fetch is off beneath the shared root" (the file, its owner, mode and setting); post-activation inspection on stibnite running lazygit under a terminal with `GIT_TRACE`, recorded with the commands run.

#### Scenario: A participating account's own lazygit configuration sets autoFetch

- **WHEN** a participating account whose own lazygit configuration sets `git.autoFetch: true` starts lazygit in a clone beneath the shared root
- **THEN** lazygit runs no `git fetch`

Witness: the run of lazygit 0.66.3 under a pseudo-terminal with `GIT_TRACE` recorded in `design.md` D7 (a clone three directories below a scratch root, with and without the root file, and with an account configuration setting `git.autoFetch: true`); post-activation inspection on stibnite.

#### Scenario: A tree is migrated into a root holding the file

- **WHEN** an administrator's tree is moved into a shared root holding only `.lazygit.yml`
- **THEN** the tree is renamed whole as into an empty root, and `.lazygit.yml` is present afterwards with its owner, mode and content

Witness: `vmTests.x86_64-linux.shared-reference-tree-migration`, subtest "migration moves only an administrator's tree in place, sets other trees aside, and rolls back".

### Requirement: A revision's diff is readable once the revision and its parents are hydrated

After `ghq-sync --hydrate <rev>` and `ghq-sync --hydrate <rev>^<n>` for each parent `n` of a commit the clone holds, a participating account's `git --no-lazy-fetch show <rev>` SHALL succeed; after `ghq-sync --hydrate A` and `ghq-sync --hydrate B`, its `git --no-lazy-fetch diff A B` SHALL succeed.

#### Scenario: A participating account reads an older commit's diff

- **WHEN** a participating account hydrates a commit the writer did not make readable, and then each of its parents
- **THEN** `git --no-lazy-fetch show <rev>` fails after the first hydrate alone when a parent's blob is missing, and succeeds after the parents are hydrated

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "Hydrating a commit and then each of its parents makes its diff readable, and the commit alone does not" (updates run with `historyLimit` 0, so no range is hydrated).
