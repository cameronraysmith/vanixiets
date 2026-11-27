## ADDED Requirements

### Requirement: The writer acts on one repository at a time

Each request that writes a repository SHALL hold, for its whole operation, an exclusive lock on a file in `/var/lib/ghq-writer`, the writer's `0700` directory outside the root, named by the SHA-256 of the repository's case-folded path under the resolved shared root, so every spelling of a repository, cloned or not, names one lock.
Requests for repositories whose paths differ by more than letter case SHALL NOT wait for each other; those differing only in case share a lock and run in sequence.

#### Scenario: Two requests for one repository

- **WHEN** a second request for a repository arrives while a first request for it is fetching, including one that spells the repository differently
- **THEN** the second request's fetch begins only after the first request's operation has ended, and both requests succeed

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "Two updates of one repository, the second spelled owner/repo and sent through the client"; `vmTests.x86_64-linux.shared-reference-tree`, subtest "a request takes its repository's lock in the writer's lock directory, and a second one waits".

#### Scenario: Requests for different repositories

- **WHEN** requests for two repositories whose paths differ by more than letter case arrive together
- **THEN** their fetches overlap in time and neither request waits

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "Updates of two repositories run side by side".

#### Scenario: Spellings of one repository

- **WHEN** requests name one repository as `host/owner/repo`, `owner/repo`, an `https` or `scp`-style URL with or without credentials, a path with a trailing slash, a path inside the clone, a path through a symbolic link to the shared root, or, on a case-insensitive file system such as darwin's, a spelling differing only in letter case
- **THEN** they all name one lock, and a repository not yet cloned has a lock name too

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "Every spelling of a repository, and a repository not cloned yet, names one lock; two names differing only in case share it".

#### Scenario: Repositories differing only in letter case

- **WHEN** a request names a repository whose path differs only in letter case from one whose lock is held, as two clones can only on a case-sensitive host
- **THEN** it takes the same lock, and so waits for the request holding it

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "Every spelling of a repository, and a repository not cloned yet, names one lock; two names differing only in case share it", in which the second name's request finds the lock held.

#### Scenario: The lock directory

- **WHEN** a request has taken its repository's lock on a NixOS host
- **THEN** `/var/lib/ghq-writer` is owned by the writer and its group with mode `0700`, and the lock file in it is owned by the writer with mode `0600`

Witness: `vmTests.x86_64-linux.shared-reference-tree`, subtest "a request takes its repository's lock in the writer's lock directory, and a second one waits".

### Requirement: A request waits a bounded time for its repository, and only a caller that asks is told

A request that finds its repository's lock held SHALL wait at most 3600 s for it, then fail with exit status 75, naming the repository and the request holding the lock.
A request MAY be followed by a line `{"accept": ["note"]}`; only to a caller that sent it SHALL the writer send `{"note": TEXT}` before its reply when the request waits, naming the repository, the limit and the holder.
Trust boundary: the lock orders only the writer's own handlers on one host.

#### Scenario: A waiting caller that accepts notes

- **WHEN** a caller that sent `{"accept": ["note"]}` on its second line makes a request whose repository's lock is held
- **THEN** before its reply it receives a note `ghq-writer: waiting up to 3600 s for <repository>, in use by another request (<holder>)`, which `ghq-writer-client` prints on its standard error at once

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "Two updates of one repository, the second spelled owner/repo and sent through the client"; `vmTests.x86_64-linux.shared-reference-tree`, subtest "a request takes its repository's lock in the writer's lock directory, and a second one waits".

#### Scenario: A waiting caller that does not accept notes

- **WHEN** a caller that sent no second line makes a request whose repository's lock is held
- **THEN** it receives its reply alone, with no note line before it

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "A request still waiting when the lock timeout passes gives up, saying why".

#### Scenario: A wait outlasts its limit

- **WHEN** a request is still waiting for its repository's lock when its wait limit passes
- **THEN** it fails with exit status 75 and a message saying it gave up after that many seconds waiting for the repository, while the request holding the lock completes

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "A request still waiting when the lock timeout passes gives up, saying why", run with a 1 s limit; the 3600 s default appears in the note of the scenario "A waiting caller that accepts notes".

### Requirement: The writer refuses a get that names no directory under the shared root

The writer SHALL refuse a `get` whose target names no directory under the shared root, such as a bare name or a path through a symbolic link out of the root, since such a request has no repository to lock.

#### Scenario: A get names no directory under the shared root

- **WHEN** a `get` request's target is a bare name, or resolves through a symbolic link to a directory outside the shared root
- **THEN** the writer refuses it, and the repository the link points to is unchanged

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "Every spelling of a repository, and a repository not cloned yet, names one lock; two names differing only in case share it", in which a bare target is refused, and case "Tag fetches act only on a clone inside the root: not through a symbolic link out of it, and not for a bare name", in which neither repository gains a tag.

### Requirement: The writer logs each request without its target

Each accepted request SHALL log a line on the writer's standard error when it starts, while it waits for its lock, and when it ends, each with a UTC timestamp, the handler's pid, the caller's uid, user name and pid, the verb and the repository; the last adds the exit status, the duration and a failure's reason, naming a command by program and subcommand only.
No line, nor the reply to a timed-out or unexpectedly failed request, SHALL carry the target as given, which may hold credentials.

#### Scenario: Log lines

- **WHEN** a request is accepted, waits for its lock, and ends
- **THEN** the writer's standard error holds a line for each, of the form `<UTC timestamp> ghq-writer pid=<pid> uid=<uid> user=<user> caller-pid=<pid> verb=<verb> repo=<repository>` followed by `start`, `waiting held-by: <holder>` or `exit status=<status> duration=<seconds>s`, the last followed by ` reason: <reason>` when the request fails, and no line holds the target's URL

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "Log lines: a UTC timestamp, the handler's pid, the caller, verb and repository, at start and exit; a waiting request logs its wait too".

#### Scenario: A command fails

- **WHEN** a command the request runs exits non-zero, for a target holding credentials
- **THEN** the exit line ends `reason: <program> <subcommand> exited <status>`, such as `git fetch exited 128`, and no line holds the credentials or a URL

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "A command that fails: the update of a clone whose remote is gone fails at its first fetch".

#### Scenario: A command times out

- **WHEN** a `get`'s clone, or a git step of an update, outlasts the command limit, for a target holding credentials
- **THEN** the caller receives exit status 124 and a message, and the exit line ends `reason: timed out after <limit> s running ghq get` or `running git <subcommand>`, neither holding the credentials, a URL or a traceback

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, cases "A get whose clone outlasts the command timeout: ghq and the git it started are stopped, and git removes its partial clone" and "A git step that outlasts the command timeout: an update's first step lists the remote".

#### Scenario: An unexpected error

- **WHEN** the handler raises an error it does not expect, whose message holds the target
- **THEN** the caller receives exit status 70, the exit line ends `reason: unexpected <type>: <message>` with the target replaced by `<target>`, and the handler exits non-zero

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "An unexpected error whose message holds the target: the handler exits non-zero after replying and logging the error's type and its message with the target replaced".

### Requirement: A command that outlasts its limit is stopped with all it started

Each command the writer runs SHALL be given at most 3600 s; one that outlasts it SHALL be stopped together with every process it started, first with `SIGTERM` so git can remove a partial clone, then with `SIGKILL`, and its request SHALL end with exit status 124, a reply and its lock released.

#### Scenario: A clone hangs

- **WHEN** a `get`'s clone, or a git step of an update, waits on its remote past the command limit
- **THEN** no process the command started still waits on the remote, the repository's lock is free, and no partial clone is left

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, cases "A get whose clone outlasts the command timeout: ghq and the git it started are stopped, and git removes its partial clone" and "A git step that outlasts the command timeout: an update's first step lists the remote", each run with a 1 s limit.

### Requirement: Git's automatic maintenance is part of the request that starts it

The writer's git SHALL run automatic maintenance in the foreground (`maintenance.autoDetach` and `gc.autoDetach` false), inside the command that starts it, so under its repository's lock and within the command's limit, and with the `gc` strategy (`maintenance.strategy=gc`), so a clone whose promisor packs exceed `gc.autoPackLimit` is consolidated; objects in promisor packs SHALL be kept.

#### Scenario: An update starts maintenance

- **WHEN** an update's fetch leaves a blobless clone with more packs than `gc.autoPackLimit`
- **THEN** before the handler exits the packs are consolidated into new packs readable by the writer's group, no process the request started is running, the lock is free, and blobs hydrated for an older commit and for a commit a forced update left unreachable are still present

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "Auto maintenance after an update runs gc in the foreground, inside the request".

#### Scenario: Maintenance outlasts the command limit

- **WHEN** the maintenance an update's fetch starts is still running when the command limit passes
- **THEN** it is stopped with the command, and the request ends with exit status 124

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "A timed-out command's stop ends the maintenance it started", run with a 3 s limit.

### Requirement: A caller that disconnects does not stop its request

When a caller closes its connection before its reply, the writer SHALL finish the request's operation, log the disconnection, drop the reply, and release the repository's lock when its handler exits.

#### Scenario: A caller disconnects

- **WHEN** a caller closes its connection while its update is running
- **THEN** the update completes, the writer logs `caller disconnected` and `exit status=0` with no traceback, and the next request for that repository takes the lock without waiting

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "A caller that disconnects: the update finishes, the handler logs the disconnection rather than a traceback, and the lock is free once it exits".

### Requirement: Each runtime test of the shared tree fits its size class

The runtime properties SHALL be divided between `vmTests.x86_64-linux.shared-reference-tree` (acquisition, the writer's requests, lock and refusals, and the permission model) and `vmTests.x86_64-linux.shared-reference-tree-migration` (tag fetches on update and migration), built from one node definition, each declared in the class its measured script time fits; a test that outgrows its class SHALL be split again, not given a larger class.

#### Scenario: A runtime test lacks a class or outlasts it

- **WHEN** a runtime test of the shared reference tree is added or renamed without a size class, or its script outlasts its class limit
- **THEN** `checks.x86_64-linux.test-size-classes` fails naming it, or the run is terminated at the limit and fails

Witness: `checks.x86_64-linux.test-size-classes`; each test's driver timeout, set to its class limit by `modules/vm-tests/default.nix`.

## MODIFIED Requirements

### Requirement: Each property is backed by evidence that can fail

The declared properties above SHALL be checked by module assertions in the per-machine checks for magnetite, pyrite and stibnite, and the runtime properties by executed NixOS tests of one node declaring the writer, a human and a worker account, with fixture repositories served inside the test.
The test holding the write probe SHALL include a control proving the probe can observe a successful write.
Darwin runtime properties SHALL be observed by post-activation inspection on stibnite, recorded with the exact commands run.

#### Scenario: The write probe is broken

- **WHEN** the NixOS test's write probe would report refusal regardless of permissions
- **THEN** the control write, performed by the writer into the same tree, is reported as refused and the test fails

Witness: `vmTests.x86_64-linux.shared-reference-tree.mutations.broken-control`, built on demand, which fails at subtest "the writer's own write succeeds (control)".
