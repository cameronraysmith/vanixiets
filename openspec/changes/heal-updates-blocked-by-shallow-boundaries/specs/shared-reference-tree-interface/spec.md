## ADDED Requirements

### Requirement: An update heals a fast-forward a shallow boundary blocks

When `ghq get -u` of a clone already present exits non-zero and, read with lazy fetching disabled, the clone has a `.git/shallow`, `HEAD` is a branch whose upstream it is not an ancestor of, and `git rev-list <upstream> ^HEAD` lists a commit `.git/shallow` names, the writer SHALL heal under the same lock and, once healed, run `ghq get -u` once more.

Trust boundary: an upstream serving depth fetches; nothing about what it serves.

#### Scenario: A branch moves onto a tag's commit fetched at depth 1

- **WHEN** a `get` with tags of a depth-1 blobless clone fetches at depth 1 a tag on a branch never merged, upstream fast-forwards `master` onto that tag's commit, and an update follows
- **THEN** the update exits 0, `master` names upstream's tip, the old `master`'s reachable commit count is no smaller than before, and `git --no-lazy-fetch fsck --connectivity-only` passes

Witness: `pkgs/by-name/ghq-shared/test_handler_history.py`, case "An update whose branch moves onto a tag's commit fetched at depth 1 heals".

#### Scenario: An update that needs no heal

- **WHEN** an update of a shallow clone fast-forwards, or upstream rewrites the branch of a clone with no `.git/shallow` and an update follows
- **THEN** no `git fetch --depth` runs, the exit log line holds no `heal=` token, and the full clone's update fails as before

Witness: `pkgs/by-name/ghq-shared/test_handler_history.py`, case "An update that needs no heal attempts none".

### Requirement: A heal fetches the upstream branch to a doubling depth

A heal SHALL run `git fetch --no-tags --depth=<K> origin <upstream branch>`, K first one more than the commits `git rev-list <upstream> ^HEAD` lists and doubling each round, until `HEAD` is an ancestor of the upstream (healed); it SHALL stop without healing when a merge base exists and `HEAD` is not an ancestor, or when no boundary lies between them and `HEAD` is not an ancestor. A heal SHALL keep the clone's `remote.origin.partialclonefilter`.

#### Scenario: A branch moves past a commit fetched by id at depth 1

- **WHEN** a blobless clone holding its whole history and a second branch also holds a later `master` commit fetched by id at depth 1, upstream's `master` moves past it, and an update follows
- **THEN** the update exits 0 with `master` at upstream's tip, and the clone's filter is unchanged

Witness: `pkgs/by-name/ghq-shared/test_handler_history.py`, case "An update past a commit fetched by id at depth 1 heals without hiding held history".

#### Scenario: Upstream rewrote its branch past a boundary

- **WHEN** upstream force-pushes `master` to unrelated history past a boundary, and an update follows
- **THEN** the heal stops at the first round that finds a merge base without `HEAD` as an ancestor, or finds no boundary left, and no second `ghq get -u` runs

Witness: `pkgs/by-name/ghq-shared/test_handler_history.py`, case "A heal that cannot complete leaves the update's outcome and the clone's history".

### Requirement: A heal removes the boundaries its fetch placed on held history

After a heal's fetches, the writer SHALL remove from `.git/shallow` each boundary absent when the heal began whose every parent the clone holds, until none is left, writing `.git/shallow.lock`, created exclusively, renamed over `.git/shallow`, and removing the file when no boundary remains.

#### Scenario: The depth fetch reaches the local branch's held history

- **WHEN** a heal's last round marks the old tip of `master`, and a commit of another remote-tracking branch, as boundaries though the clone holds their parents
- **THEN** after the heal neither is a boundary, and `rev-list --count` of the old tip and of every ref is no smaller than before the heal

Witness: `pkgs/by-name/ghq-shared/test_handler_history.py`, case "An update past a commit fetched by id at depth 1 heals without hiding held history".

### Requirement: A heal checks that every ref still reaches what it reached

After the repair, the writer SHALL walk, with lazy fetching disabled, every commit reached by the refs under `refs/heads` and `refs/remotes` as they were before the heal; the walk SHALL succeed and list no boundary the heal added, or the writer SHALL restore the `.git/shallow` the heal's fetches wrote and report the heal failed.

#### Scenario: The check fails

- **WHEN** the walk after the repair fails or lists a boundary the heal added
- **THEN** `.git/shallow` is as the heal's fetches left it, the update's exit status is that of its first attempt, and the reply holds `shallow boundary heal failed: <path> (check: <reason>)`

Witness: `pkgs/by-name/ghq-shared/test_handler_history.py`, case "A heal that cannot complete leaves the update's outcome and the clone's history".

### Requirement: A heal is bounded by the commits it brings in

Before each round, the first included, the writer SHALL count, with lazy fetching disabled, the commits the upstream reaches that no ref named before the heal reaches, and SHALL stop without healing once that count exceeds its heal limit, 100,000 unless its configuration's `healLimit` says otherwise.

#### Scenario: The gap is larger than the limit

- **WHEN** an update needs a heal whose gap holds more commits than `healLimit`, here 0
- **THEN** no `git fetch --depth` and no second `ghq get -u` run, the update exits with its first attempt's status, `HEAD` stays where it was, and the reply holds `shallow boundary not healed: <path> (more than 0 commits)`

Witness: `pkgs/by-name/ghq-shared/test_handler_history.py`, case "A boundary present when a request begins counts as held when no heal runs".

### Requirement: The writer's reply says what a heal did

A request that attempts a heal SHALL carry, after its first `ghq get -u`'s output, one status line: `healed shallow boundary: <path> (depth <K>; <n> boundaries on held history removed)`, `shallow boundary not healed: <path> (<reason>)` or `shallow boundary heal failed: <path> (<phase>: <reason>)`; a healed update's exit status SHALL be its second `ghq get -u`'s.

#### Scenario: Healed and not

- **WHEN** an update heals, and another meets upstream's rewritten branch past a boundary
- **THEN** the first's reply holds the `healed shallow boundary` line, exit 0; the second's holds `shallow boundary not healed: <path> (upstream's branch does not contain the local branch)`, exit 1

Witness: `pkgs/by-name/ghq-shared/test_handler_history.py`, cases "An update whose branch moves onto a tag's commit fetched at depth 1 heals" and "A heal that cannot complete leaves the update's outcome and the clone's history".

### Requirement: The writer's exit log line names what a heal did

A request that attempts a heal SHALL add to its exit log line, after the duration and before any `history=` token, `heal=healed:<K>`, `heal=not-healed` or `heal=failed`, naming neither the target nor a command's arguments; a request that attempts none SHALL add none.

#### Scenario: Requests that attempt a heal end

- **WHEN** an update heals, one is not healed, and one's heal fails
- **THEN** their exit log lines hold `heal=healed:<K>`, `heal=not-healed` and `heal=failed` respectively, each before any `history=` token, and the last two end with ` reason:` naming `ghq get`

Witness: `pkgs/by-name/ghq-shared/test_handler_history.py`, cases "An update whose branch moves onto a tag's commit fetched at depth 1 heals" and "A heal that cannot complete leaves the update's outcome and the clone's history".

### Requirement: A heal that cannot complete leaves the update's outcome as it was

When a heal stops without healing, or anything raises during it, the writer SHALL run no second `ghq get -u`, SHALL leave the request's exit status as the first attempt set it, never 70 for the heal's own failure, SHALL leave every ref reaching at least what it reached before the heal, and SHALL report the phase (`fetch`, `repair` or `check`) with its own failure's message or the exception's type alone.

#### Scenario: The remote refuses the depth fetch

- **WHEN** an update needs a heal and the remote refuses `git fetch --depth`
- **THEN** the update exits with its first attempt's status, the reply holds `shallow boundary heal failed: <path> (fetch: …)`, the exit log line holds `heal=failed` and no traceback, and every ref reaches what it reached before

Witness: `pkgs/by-name/ghq-shared/test_handler_history.py`, case "A heal that cannot complete leaves the update's outcome and the clone's history".

### Requirement: The history walk of a healed update stops at what the clone held before

The walk of a request whose heal or deepen removed boundaries from `.git/shallow` SHALL exclude those boundaries as it excludes the boundaries now present, so that it lists only the commits the request brought in, and the record SHALL name the refs and boundaries after the repair.

#### Scenario: A healed update of a blobless clone

- **WHEN** an update heals a blobless clone and brings in commits
- **THEN** every commit it brought in reads with `git --no-lazy-fetch show --stat -p`, the walk lists no commit the clone's branch held before, and the tag commit the branch moved onto is hydrated against its parent, not as a root commit

Witness: `pkgs/by-name/ghq-shared/test_handler_history.py`, cases "An update whose branch moves onto a tag's commit fetched at depth 1 heals" (`hydrated history: … (1 objects fetched)`) and "An update past a commit fetched by id at depth 1 heals without hiding held history" (its held history unlisted).

### Requirement: A deepen removes the boundaries it placed on held history

After `ghq-sync --deepen N`, the writer SHALL remove and check the boundaries the deepen added as it does after a heal.

#### Scenario: A deepen reaches the local branch's held history

- **WHEN** a blobless clone holding its whole history below an upstream-side boundary is deepened by the number of commits between that boundary and `master`'s tip
- **THEN** the deepen exits 0, `master` and every remote-tracking ref reach at least the commits they reached before, and `.git/shallow` names no commit whose parents the clone holds that it did not name before

Witness: `pkgs/by-name/ghq-shared/test_handler_history.py`, case "A deepen never hides history a branch reached".

## MODIFIED Requirements

### Requirement: A request that brings in no commit runs no history walk

When no ref under `refs/heads` or `refs/remotes` reaches, after a request, a commit that no ref the clone's record names, no boundary it names and no boundary present when the request began reached, and no such boundary is gone, the request brings in nothing, and the writer SHALL run no history listing and no history fetch for it.

#### Scenario: An update moves refs only to commits the clone held

- **WHEN** upstream force-resets the branch to an ancestor the clone holds, adds a branch at a commit the clone holds, or deletes a branch, and an update of a blobless clone holding the whole history follows each
- **THEN** each update moves a remote-tracking ref, runs no history listing and no history fetch, its reply holds no history status line, and its exit log line no `history=` token

Witness: `pkgs/by-name/ghq-shared/test_handler_history.py`, case "A request that brings no commit in walks nothing, lists nothing and fetches nothing".

#### Scenario: A branch moves onto a boundary a tag fetch added after the walk

- **WHEN** a `get` with tags of a shallow blobless clone, after the record was written, fetches at depth 1 a tag on a branch never merged, upstream moves `master` onto that tag's commit, and an update follows under a `healLimit` of 0, so that it does not heal
- **THEN** that update's reply holds no history status line and its exit log line no `history=` token, the boundary present when it began counting as held

Witness: `pkgs/by-name/ghq-shared/test_handler_history.py`, case "A boundary present when a request begins counts as held when no heal runs".
