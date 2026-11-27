## ADDED Requirements

### Requirement: An update makes every commit it brought in readable as a diff

On a `get` of a clone already present whose `remote.origin.promisor` is true, the writer SHALL, after every command that can move a branch ref and before any tag fetch at depth 1, fetch every blob the clone lacks that `git log --diff-merges=first-parent --raw` or `git log --merges --cc --raw` names for the commits the refs under `refs/heads` and `refs/remotes` gained that none reached before, reporting the outcome in one status line.

#### Scenario: An update brings in commits

- **WHEN** a `get` with an update of a blobless clone brings in commits, including merges and a change of default branch
- **THEN** a participating account's `git --no-lazy-fetch show --stat -p <commit>` succeeds for every commit it brought in, the clone's filter and shallow boundaries are unchanged, and the reply holds `hydrated history: <path> (<N> objects fetched)`

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "An update of a blobless clone makes every commit it brought in readable as a diff with lazy fetching disabled"; `vmTests.x86_64-linux.shared-reference-tree-migration`, subtest "an update makes the commits it brought in readable, and a read the writer did not prepare fails at once".

#### Scenario: An update of a full clone

- **WHEN** a `get` with an update names a clone with no promisor remote, or brings in no commit
- **THEN** the writer runs no history walk and fetches nothing more than the update did

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "An update of a full clone, or one that brings in nothing, walks no history".

### Requirement: Tag commits fetched at depth 1 stay unhydrated

The writer SHALL NOT walk or hydrate a tag's commit: one a `get` with tags fetches at depth 1 is a shallow boundary, whose `git show` diffs against nothing and needs its whole tree, and it stays unhydrated until `ghq-sync --hydrate <tag>`.

#### Scenario: A get with tags moves the remote-tracking branch

- **WHEN** a `get` with tags, and no update, of a shallow blobless clone fetches its tracked branch, which upstream has advanced, and a tag on a branch never merged
- **THEN** every commit the remote-tracking branch gained is readable as a diff, and the tag's commit arrives and stays unhydrated

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "A get with tags of a shallow clone fetches its branches first"; `vmTests.x86_64-linux.shared-reference-tree-migration`, subtest "an update makes the commits it brought in readable, and a read the writer did not prepare fails at once" (`git show t-unmerged` after `ghq-sync -u --tags` fails at once).

### Requirement: The history fetch keeps the clone's partial-clone filter

The history fetch SHALL pass the filter the clone records in `remote.origin.partialclonefilter`, at the clone's depth.
A promisor clone that records no filter, as a `ghq-sync --full` whose refetch failed leaves one, SHALL get no history listing or fetch, its configuration unchanged, and the report `history not hydrated: <path> (the clone records no partial-clone filter; ghq-sync --hydrate REV makes a revision readable)`.

#### Scenario: The clone records a filter of its own

- **WHEN** an update brings commits into a promisor clone whose `remote.origin.partialclonefilter` is `blob:limit=1`
- **THEN** every commit it brought in is readable as a diff and the recorded filter is still `blob:limit=1`

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "The history fetch passes the filter the clone records" (first half).

#### Scenario: A promisor clone records no filter

- **WHEN** an update brings commits into a clone whose `remote.origin.promisor` is true and which has no `remote.origin.partialclonefilter`
- **THEN** the writer runs no history listing and no history fetch, the clone still has no `remote.origin.partialclonefilter`, the reply holds the `history not hydrated` line naming the missing filter, and the exit log line holds `history=not-hydrated`

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "The history fetch passes the filter the clone records" (second half).

### Requirement: A deepen makes every commit it brought in readable as a diff

On a `deepen` of a clone whose `remote.origin.promisor` is true, the writer SHALL, before releasing the repository's lock, fetch every blob the clone lacks that the same two listings name for the commits from each shallow boundary commit the deepen removed down to, and excluding, the boundary commits now present, and for the commits the deepen's fetch brought into any branch or remote-tracking branch it moved, as for an update, by the same passes and with the same status line as an update.

#### Scenario: A blobless clone is deepened

- **WHEN** a participating account deepens a blobless clone by N commits
- **THEN** its `git --no-lazy-fetch show --stat -p <commit>` succeeds for every commit the deepen brought in except the new boundary commits, and for the previous boundary commits

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "A deepen makes every commit it brought in, but the new deepest, readable as a diff".

#### Scenario: A deepen also moves the remote-tracking branch

- **WHEN** a participating account deepens a blobless clone whose upstream has gained commits since its last update, so that `git fetch --deepen` also moves `origin/<branch>`
- **THEN** every commit `origin/<branch>` gained, and every deepened commit but the new boundary, is readable as a diff

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "A deepen also moves the remote-tracking branch to the commits upstream gained since the last update".

### Requirement: The writer bounds the history it makes readable

Before fetching any blob for a request, the writer SHALL count the missing blobs of every range the request brought in together, stopping once the count exceeds its history limit, 100,000 unless its configuration's `historyLimit` says otherwise; above the limit it SHALL fetch none and report `history not hydrated: <path> (more than <limit> blobs missing; ghq-sync --hydrate REV makes a revision readable)`.

#### Scenario: An update brings in more missing blobs than the limit

- **WHEN** a `get` with an update brings in commits whose diffs need more missing blobs than the history limit
- **THEN** the writer fetches no blob for them, the update's exit status is unchanged, the reply holds the `history not hydrated` line, and the walk stopped once the count passed the limit

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "An update bringing in more missing blobs than the limit fetches none and says so".

### Requirement: A failed history fetch leaves the request's outcome as it was

When reading the clone's refs or shallow boundaries, the walk or the history fetch fails, including when git cannot be started (`OSError`) or outlasts the command timeout, the writer SHALL leave the request's exit status as its other commands set it and report `history hydrate failed: <path> (<reason>)` in one status line, keeping every object it already fetched.

#### Scenario: The remote refuses the history fetch

- **WHEN** the remote serves an update but refuses the fetch of the missing blobs
- **THEN** the update's exit status is zero, its new commits are checked out, and the reply holds the `history hydrate failed` line

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "A history fetch that fails leaves the update's exit status and says so".

#### Scenario: git cannot be started for the walk

- **WHEN** starting git for the history listing raises `OSError`
- **THEN** the update's exit status is zero, the reply holds the `history hydrate failed` line, and the exit log line holds `history=failed` and no ` reason:`

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "The history fetch passes the filter the clone records" (its third clone, "An error starting git in the history walk is the history fetch's failure, not the request's").

### Requirement: The history walk gives git its lists on standard input

The writer SHALL give git every list whose length the clone decides (revisions, shallow boundaries, blob ids) on standard input, never as arguments.

#### Scenario: A clone holds many shallow boundaries

- **WHEN** a participating account deepens a blobless clone holding a shallow boundary for each of 200 commits fetched at depth 1, besides its branch's
- **THEN** the deepen succeeds, every commit it brought in but the new boundary is readable as a diff, no git the writer starts gets one of those boundaries as an argument, and the walk's `git log --stdin` reads all of them on standard input, so their number is bounded by no argument list

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "A deepen also moves the remote-tracking branch to the commits upstream gained since the last update" (its boundary and argument assertions).

### Requirement: The writer's exit log line names what the history fetch did

When a request runs the walk that makes its commits readable, the writer SHALL add to the request's exit log line, after the duration and before any failure's reason, `history=hydrated:<N>`, `history=not-hydrated` or `history=failed`, naming neither the target nor a command's arguments, on every path after the walk returns, including a later command's timeout and an unexpected error, whose reply SHALL then hold the history fetch's status line; a request that runs no walk SHALL add none.

#### Scenario: Requests that run a history walk end

- **WHEN** a `get` with an update of a blobless clone is hydrated, exceeds the history limit, or meets a refused history fetch
- **THEN** its exit log line holds `history=hydrated:<N>`, `history=not-hydrated` or `history=failed` respectively, and the refused fetch adds no ` reason:`

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, cases "An update of a blobless clone makes every commit it brought in readable as a diff with lazy fetching disabled", "An update bringing in more missing blobs than the limit fetches none and says so" and "A history fetch that fails leaves the update's exit status and says so".

#### Scenario: A command after the walk outlasts the command timeout

- **WHEN** a `get` with an update and tags of a shallow blobless clone hydrates the commits it brought in, and then its fetch of a tag at depth 1 outlasts `commandTimeout`
- **THEN** the request exits 124, its reply holds `hydrated history: <path> (<N> objects fetched)`, and its exit log line holds `history=hydrated:<N>` before ` reason: timed out after <n> s running git fetch`

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "A command after the history fetch that outlasts the command timeout".

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

Each participating account's git configuration SHALL set `protocol.allow` to `never` under the `gitdir:` conditions that carry the LFS settings, and no `protocol.<name>.allow` key in its settings, so its git fetches nothing beneath the shared root; evaluation SHALL fail otherwise.
Trust boundary: `-c` or environment overrides, a hand-written `~/.gitconfig`, an include given only as a path outside the Nix evaluation, and programs that read no git configuration, are not covered.

#### Scenario: A participating account reads content the clone lacks

- **WHEN** a participating account runs `git show <commit>` in a clone beneath the shared root that lacks a blob the diff needs
- **THEN** git exits non-zero at once with `transport '<scheme>' not allowed` and `could not fetch <oid> from promisor remote`, reports no permission error, and nothing beneath the shared root changes

Witness: `vmTests.x86_64-linux.shared-reference-tree-migration`, subtest "an update makes the commits it brought in readable, and a read the writer did not prepare fails at once".

#### Scenario: A participating account fetches directly

- **WHEN** a participating account runs `git fetch` in a clone beneath the shared root, and again with `--no-write-fetch-head`, and runs `git ls-remote origin` and `git remote show origin` there
- **THEN** the first is refused by the operating system with a permission error on `.git/FETCH_HEAD`, which git opens before it connects, and each of the others is refused before any transport starts with `transport '<scheme>' not allowed`

Witness: `vmTests.x86_64-linux.shared-reference-tree`, subtest "readers cannot write the tree" (both fetches); `vmTests.x86_64-linux.shared-reference-tree-migration`, subtest "an update makes the commits it brought in readable, and a read the writer did not prepare fails at once" (`ls-remote` and `remote show`).

#### Scenario: A participant lacks the setting

- **WHEN** a participating account's evaluated git includes lack `protocol.allow = never` for a form of the shared root, or its settings set a `protocol.<name>.allow` key
- **THEN** that host's configuration fails evaluation, naming that account

Witness: the assertions of `modules/nixos/shared-reference-tree.nix`, `modules/darwin/shared-reference-tree.nix` and, for darwin Omnigent workers, `modules/darwin/omnigent-host.nix`, evaluated by the per-machine checks of magnetite, pyrite and stibnite; `checks.x86_64-linux.eval-shared-reference-tree`, cases `testMissingForm` and `testSettingsNamedKey`.

### Requirement: Evaluation rejects an include that reopens a transport beneath the shared root

A participating account's Home Manager git configuration SHALL declare no include with inline contents whose condition can hold beneath the shared root (none, a `gitdir:` or `gitdir/i:` path enclosing the root or beneath it, or a condition evaluation cannot rule out, such as a glob or `onbranch:`) that sets a `protocol.<name>.allow` key or a `protocol.allow` other than `never`; evaluation SHALL fail otherwise, naming the account and the include.

#### Scenario: An include that applies beneath the root reopens a transport

- **WHEN** a participating account's Home Manager git configuration adds an unconditional include setting `protocol.https.allow`, a second include under the root's own `gitdir:` condition setting it, or an include under a broader `gitdir:` such as `gitdir:/var/` setting `protocol.allow = always`
- **THEN** that host's configuration fails evaluation, naming the account and the include by its position and condition; an include under a `gitdir:` that neither encloses the root nor lies beneath it, and an include given only as a path, do not fail it

Witness: `checks.x86_64-linux.eval-shared-reference-tree` (`modules/system/shared-reference-tree.test.nix`), cases `testUnconditionalIncludeNamedKey`, `testSecondIncludeUnderRoot`, `testBroaderGitdirAllowAlways`, `testNarrowerGitdirNamedKey`, `testGlobGitdirNamedKey`, `testUnrelatedGitdir` and `testPathInclude`; the module assertions name each finding as `<account>: include <n> (<condition>) sets …`.

### Requirement: lazygit fetches nothing at start-up beneath the shared root

Each sharing host SHALL provision `<shared root>/.lazygit.yml`, a regular file owned by the writer and its group with mode `0640`, setting `git.autoFetch` to `false`; darwin activation SHALL stop with a message when that path is a directory or a link to one.
Migration SHALL leave that file in place, owned by the writer.
lazygit reads that file after the account's own configuration, so it decides `git.autoFetch` for every copy, and every other key the account sets still applies.

#### Scenario: A participating account opens lazygit in a clone

- **WHEN** a participating account starts lazygit in a clone beneath the shared root
- **THEN** lazygit runs no `git fetch` and shows no fetch error

Witness: `vmTests.x86_64-linux.shared-reference-tree-migration`, subtest "lazygit's start-up fetch is off beneath the shared root" (the file, its owner, mode and setting); post-activation inspection on stibnite running lazygit under a terminal with `GIT_TRACE`, recorded with the commands run.

#### Scenario: A participating account's own lazygit configuration sets autoFetch

- **WHEN** a participating account whose own lazygit configuration sets `git.autoFetch: true` starts lazygit in a clone beneath the shared root
- **THEN** lazygit runs no `git fetch`

Witness: the run of lazygit 0.66.3 under a pseudo-terminal with `GIT_TRACE` recorded in `design.md` D7 (a clone three directories below a scratch root, with and without the root file, and with an account configuration setting `git.autoFetch: true`); post-activation inspection on stibnite.

### Requirement: Migration keeps the provisioned .lazygit.yml over an administrator's own

When an administrator's tree renamed whole to the shared root brings a `.lazygit.yml` of its own, migration SHALL move that file to the tree's set-aside directory (`~/ghq.pre-shared-<date>`), still the administrator's, say so, and put the provisioned file back with its owner, mode and content; rollback SHALL return the administrator's file to its tree and leave the provisioned one at the root.

#### Scenario: A tree is migrated into a root holding the file

- **WHEN** an administrator's tree holding a `.lazygit.yml` of its own is moved into a shared root holding only the provisioned `.lazygit.yml`, and later rolled back, and applies refused before it leave the root alone
- **THEN** the tree is renamed whole as into an empty root; after each refused apply the root holds exactly the provisioned file with its owner, mode and content; after migration and after rollback the root's `.lazygit.yml` has the provisioned content, owner and mode; after migration the administrator's file is in `~/ghq.pre-shared-<date>`, still the administrator's, and the output says so; after rollback it is back in the administrator's tree

Witness: `vmTests.x86_64-linux.shared-reference-tree-migration`, subtest "migration moves only an administrator's tree in place, sets other trees aside, and rolls back".

### Requirement: A revision's diff is readable once the revision and its parents are hydrated

After `ghq-sync --hydrate <rev>` and `ghq-sync --hydrate <rev>^<n>` for each parent `n` of a commit the clone holds, a participating account's `git --no-lazy-fetch show <rev>` SHALL succeed; after `ghq-sync --hydrate A` and `ghq-sync --hydrate B`, its `git --no-lazy-fetch diff A B` SHALL succeed.

#### Scenario: A participating account reads an older commit's diff

- **WHEN** a participating account hydrates a commit the writer did not make readable, and then each of its parents
- **THEN** `git --no-lazy-fetch show <rev>` fails after the first hydrate alone when a parent's blob is missing, and succeeds after the parents are hydrated

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "Hydrating a commit and then each of its parents makes its diff readable, and the commit alone does not" (updates run with `historyLimit` 0, so no range is hydrated).
