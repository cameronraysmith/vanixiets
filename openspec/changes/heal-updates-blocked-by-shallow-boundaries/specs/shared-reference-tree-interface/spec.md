## ADDED Requirements

### Requirement: The writer's reply names a shallow boundary between a failed update's branch and its upstream

When an update fails and a commit in the clone's `.git/shallow` lies among the commits its upstream reaches and `HEAD` does not, the writer SHALL keep the update's output and exit status and SHALL add two lines naming that commit and the repair `ghq-sync --deepen 1000000 <path>` then `ghq-sync -u <path>`, stating no cause the clone cannot show.
Finding the commit SHALL only read the clone (A381), and a failure while finding it SHALL add nothing.

#### Scenario: The lines' text

- **WHEN** an update with such a commit replies
- **THEN** its standard error ends `shallow boundary between the local branch and upstream's: <path> (the copy holds <commit> without its history, and it lies between the local branch and upstream's <remote>/<branch>)` and `to repair it: ghq-sync --deepen 1000000 <path> then ghq-sync -u <path> (that deepen hides none of the history the copy holds, where a smaller one can; if the update still fails with git's fast-forward refusal and without this line, upstream rewrote its branch and this boundary was not the cause; ghq-sync --help, under --deepen, says what the deepen costs and names the other repair)`

#### Scenario: Upstream's branch moves onto a tag's commit fetched at depth 1

- **WHEN** a depth-1 blobless clone has fetched with tags a tag at depth 1 whose commit upstream's `master` then reaches, and an update runs
- **THEN** the reply holds git's `fatal:` line and the two lines naming the tag's commit and `origin/master`, the request exits 1, and `.git/shallow`, `HEAD` and every ref outside `refs/remotes` are as before, no file under `.git` new but `FETCH_HEAD` and `ORIG_HEAD` outside the object store, the logs and the remote-tracking refs

#### Scenario: Upstream's branch moves past a commit fetched by id

- **WHEN** a blobless clone holding `master`'s whole history, or only its first three commits with the fifth fetched by id at depth 1, sees upstream's `master` move past a commit the clone fetched by id at depth 1, and an update runs
- **THEN** the reply holds the two lines naming that commit, the request exits 1, and the clone is as the failed update left it

#### Scenario: Upstream rewrites its branch through a commit held without its history

- **WHEN** a blobless clone holding `master`'s whole history fetched by id at depth 1 a commit of a branch forked three commits below its tip, and upstream force-pushes `master` to one commit past it, and an update runs
- **THEN** the reply holds the two lines naming that commit; after the named deepen, which hides nothing, the next update still fails, now with no `shallow boundary` line and no `boundary=` token

#### Scenario: An update fails for another reason

- **WHEN** upstream rewrote `master` of a depth-1 clone, whose only boundary is its tip, and an update runs
- **THEN** the update fails as before, its reply holds no `shallow boundary` line and its exit log line no `boundary=` token

#### Scenario: Finding the commit fails

- **WHEN** the finding's first git cannot start, or its listing times out, on an update with such a commit
- **THEN** the reply and exit status are git's alone, 1 with ` reason: ghq get exited 1`, with no `shallow boundary` line and no `boundary=` token, and the clone is as the failed update left it

#### Scenario: The named repair hides nothing

- **WHEN** an account runs the deepen the reply names, `deepen` with depth 1,000,000, on any clone of the scenarios above, then an update
- **THEN** every branch and remote-tracking ref reaches at least what it reached before, no boundary has a parent the clone holds, the clone holding a root commit has no boundary left, the clone keeps `remote.origin.partialclonefilter`, and the update fast-forwards to upstream's tip with exit 0 unless upstream rewrote its branch (A380, A382)

#### Scenario: A sized deepen can hide held history

- **WHEN** a twin of the clone holding `master`'s whole history is deepened by 2 instead
- **THEN** `master`'s commit reaches fewer commits than before, which is why the reply and `ghq-sync`'s usage text name the deepen of 1,000,000 (A380)

### Requirement: The writer's exit log line marks an update the shallow boundary line names

The exit log line of a request whose reply names a shallow boundary SHALL add ` boundary=blocked` after the history token, if any, and before ` reason:`; no other request's exit log line SHALL hold a `boundary=` token.

#### Scenario: An update with the line, and the update after its repair

- **WHEN** an update whose reply names a shallow boundary runs, then the named repair and another update
- **THEN** the first exit log line holds ` boundary=blocked` and the last none
