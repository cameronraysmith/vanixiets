## ADDED Requirements

### Requirement: The writer acts on one repository at a time

Each request that writes a repository SHALL hold, for its whole operation, an exclusive lock on a file in `/var/lib/ghq-writer`, a directory outside the shared root owned by the writer with mode `0700`, named by the SHA-256 of the repository's path relative to the resolved shared root, case-folded, so every spelling of one repository, and one not yet cloned, names one lock.
Requests for different repositories SHALL NOT wait for each other.

#### Scenario: Two requests for one repository

- **WHEN** a second request for a repository arrives while a first request for it is fetching, including one that spells the repository differently
- **THEN** the second request's fetch begins only after the first request's operation has ended, and both requests succeed

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "Two updates of one repository, the second spelled owner/repo and sent through the client"; `vmTests.x86_64-linux.shared-reference-tree`, subtest "a request takes its repository's lock in the writer's lock directory, and a second one waits".

#### Scenario: Requests for different repositories

- **WHEN** requests for two different repositories arrive together
- **THEN** their fetches overlap in time and neither request waits

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "Updates of two repositories run side by side".

#### Scenario: Spellings of one repository

- **WHEN** requests name one repository as `host/owner/repo`, `owner/repo`, an `https` or `scp`-style URL with or without credentials, a path with a trailing slash, a path inside the clone, a path through a symbolic link to the shared root, or a spelling differing only in letter case
- **THEN** they all name one lock, and a repository not yet cloned has a lock name too

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "Every spelling of a repository, and a repository not cloned yet, names one lock; two names differing only in case share it".

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

Each accepted request SHALL leave a line on the writer's standard error when it starts, while it waits for its lock, and when it ends, each carrying a UTC timestamp, the handler's process id, the caller's uid, user name and process id, the verb and the repository, the last adding the exit status and the duration.
No line SHALL carry the target as the caller gave it, which may hold credentials.

#### Scenario: Log lines

- **WHEN** a request is accepted, waits for its lock, and ends
- **THEN** the writer's standard error holds a line for each, of the form `<UTC timestamp> ghq-writer pid=<pid> uid=<uid> user=<user> caller-pid=<pid> verb=<verb> repo=<repository>` followed by `start`, `waiting held-by: <holder>` or `exit status=<status> duration=<seconds>s`, and no line holds the target's URL

Witness: `pkgs/by-name/ghq-shared/test_handler.py`, case "Log lines: a UTC timestamp, the handler's pid, the caller, verb and repository, at start and exit; a waiting request logs its wait too".

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
