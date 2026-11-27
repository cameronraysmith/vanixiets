# shared-reference-tree-interface Specification

## Purpose
This capability (stratum: `interface`) states the properties at the machine's interface that discharge the `shared-reference-tree` requirements: the shared root's location, ownership and mode; the writer account (`ghq` on NixOS, `_ghq` on darwin) and its reader group; each participating account's resolved root, `~/ghq` link, `safe.directory` scope and `safe.bareRepository` setting; the socket-activated delegation entry point and the requests it accepts; the migration tool's administrator-only moves, its refusals, the set-aside path and rollback; and the evidence that each property holds.
Trust boundary: these properties hold at the boundary of the hosts' declared configuration and Unix discretionary permissions, observed by evaluation, an executed NixOS test and post-deploy inspection; they do not cover an account that overrides its own git or ghq configuration, root or the writer acting against the tree, the content of upstream repositories, or any confinement of code running inside an account.

## Requirements

### Requirement: Sharing hosts are declared, and only they change

The fleet configuration SHALL declare, per host, whether that host shares a reference tree and which Unix accounts participate, and SHALL declare exactly magnetite, pyrite and stibnite as sharing hosts.
On magnetite and pyrite the participating accounts SHALL be `cameron`, `omnigent-cameron` and `omnigent-janettesmith`; on stibnite they SHALL be `crs58` and `omnigent-cameron`.
A host not declared as sharing SHALL evaluate to a configuration with no writer account, no reader group, no shared root, and an unchanged git configuration for every account.

#### Scenario: A non-sharing host is evaluated

- **WHEN** the configuration of a host other than magnetite, pyrite or stibnite is evaluated
- **THEN** it declares no writer account or group, no shared root, and no `ghq.root` or `safe.directory` value in any account's Home Manager git settings

#### Scenario: A participant is added or removed without declaring it

- **WHEN** a sharing host's reader group membership differs from that host's declared participating accounts
- **THEN** that host's configuration fails evaluation, naming the extra or missing account

### Requirement: The shared root is owned by the writer and closed to everyone else

Each sharing host SHALL provision its shared root at `/var/lib/ghq`, owned by a dedicated writer system account, `ghq` on NixOS and `_ghq` on darwin, with a same-named primary group, with mode `0750`.
The writer account SHALL have no password, no interactive login shell, no SSH keys, no administrative group, no sudo grant, no Nix trusted-user standing and no credentials.
Every entry beneath the shared root other than a symbolic link SHALL carry no group-write bit and no permission bit for others; a symbolic link's own mode bits are exempt, because changing what a link points to requires write permission on its directory, which no participating account has.
No participating account SHALL own any entry beneath the shared root.

#### Scenario: A participating account attempts to write beneath the shared root

- **WHEN** a participating account attempts to create a file in the shared root, create a file inside a cloned repository, or write `.git/config` of a cloned repository
- **THEN** the operating system refuses the write with a permission error and the tree is unchanged

#### Scenario: An account outside the reader group lists the shared root

- **WHEN** an account that is neither the writer nor a member of the writer's group lists the shared root
- **THEN** the operating system refuses with a permission error

#### Scenario: The writer's umask or the root's mode is weakened

- **WHEN** a revision of the configuration provisions the root with a group- or other-write bit, or lets the writer create entries carrying either bit
- **THEN** the executed NixOS test's write-refusal assertions fail for that revision

### Requirement: Each participating account resolves the shared root

Each participating account's Home Manager git configuration SHALL set `ghq.root` to the host's shared root, and that account's `~/ghq` SHALL be a symbolic link to the shared root.
For each participating account, `ghq root` and `git config --get-all ghq.root` SHALL report the shared root when `GHQ_ROOT` is unset, and `ghq list -p` SHALL print paths beneath the shared root.
The discharge of this requirement depends on assumption A35.

#### Scenario: A participating account asks ghq for its root

- **WHEN** a participating account runs `ghq root` with `GHQ_ROOT` unset, from an interactive shell or from a process its supervisor started
- **THEN** it prints the host's shared root

#### Scenario: A participating account follows its home link

- **WHEN** a participating account resolves `~/ghq`
- **THEN** it resolves to the host's shared root

### Requirement: Readers trust the writer's tree and nothing broader

Each participating account's git configuration SHALL contain exactly one `safe.directory` entry introduced by this capability, with the value `<shared root>/*`, and SHALL NOT contain `safe.directory = *`.
No other account's git configuration SHALL contain `safe.directory = *` or a `<dir>/*` entry whose `<dir>` is a proper prefix of the shared root or of its real path.
Each participating account's git configuration SHALL set `safe.bareRepository` to `explicit`, so a bare repository inside the shared tree is used only when named explicitly; the setting is global to that account's git use, so any bare repository it uses must be named with `--git-dir` or `GIT_DIR`.
The writer's own git invocations SHALL run with no system or global configuration, and therefore with no `safe.directory` entry.
The discharge of this requirement depends on assumption A34.

#### Scenario: A participating account runs a read-only git command in a reference repository

- **WHEN** a participating account runs `git log` or `git status` in a repository beneath the shared root
- **THEN** git reads the repository and exits zero, without reporting dubious ownership

#### Scenario: A participating account runs git in a repository owned by another participant outside the shared root

- **WHEN** a participating account runs git in a repository it does not own that lies outside the shared root
- **THEN** git refuses it as dubiously owned, exactly as before this capability

#### Scenario: A wildcard trust entry is introduced

- **WHEN** any participating account's evaluated git settings contain `safe.directory = *`, or a `safe.directory` value other than `<shared root>/*` attributable to this capability
- **THEN** that host's configuration fails evaluation

### Requirement: Acquisition is delegated to the writer through a socket-activated entry point

For each participating account, the `ghq` command on its `PATH` SHALL run `list`, `root`, `help`, `--help` and `--version` directly as that account, SHALL refuse `create`, `rm` and `migrate`, and SHALL hand `get` and `get -u` to the writer, one request per target.
`ghq-sync` SHALL use that same `ghq` command, its `--deepen`, in-place `--full` and `--hydrate` work SHALL be handed to the writer, and it SHALL register resulting paths with the calling account's own zoxide database.
Requests SHALL reach the writer only through a socket at `/run/ghq-writer.sock` (NixOS) or `/var/run/ghq-writer.sock` (darwin), owned by the writer's group with mode `0660`, whose service starts one handler per connection as the writer with umask `0027`.

#### Scenario: A participating account clones a missing repository

- **WHEN** a participating account runs `ghq get <url>` or `ghq-sync <url>` for a repository absent from the shared root
- **THEN** the repository appears beneath the shared root owned by the writer, `ghq list -p` as the participating account prints its path, and that path is in the participating account's zoxide database

#### Scenario: A participating account hydrates a revision

- **WHEN** a participating account runs `ghq-sync --hydrate <rev> <path>` for a blobless clone beneath the shared root holding `<rev>`'s commit but not its file contents
- **THEN** `git show <rev>:<file>` as that account succeeds with lazy fetching disabled, and every entry beneath the shared root is still owned by the writer

#### Scenario: A participating account bypasses the wrapper

- **WHEN** a participating account runs `git fetch` or `git clone` directly against a path beneath the shared root
- **THEN** the operating system refuses the write with a permission error

#### Scenario: An account outside the writer's group connects to the socket

- **WHEN** an account that is not a member of the writer's group connects to the writer's socket
- **THEN** the connection is refused by the socket's mode, and a handler started by any other path refuses a caller whose connection identity is outside the group

### Requirement: The writer accepts only constrained requests

The writer SHALL accept one request per connection, at most 4 KiB, naming exactly one of `get` (a target, whether lazy, whether an update, whether every tag), `deepen` (a positive depth and a path), `promote` (a path) or `hydrate` (a revision and a path).
It SHALL refuse a target that begins with `-`, contains `..` as a path segment or `::`, contains a character outside `A-Za-z0-9._~:/@+%-`, or names a scheme outside its allowed protocols, a revision that does not begin with a letter or digit, contains a character outside `A-Za-z0-9._/+-` before an optional run of `~N` or `^N` suffixes, or contains `..`, and a path that does not resolve inside the shared root.
It SHALL run git and ghq without a shell, with no system or global git configuration, and with `protocol.allow=never` except for its allowed protocols, which default to `https`.
On an update of a full clone it SHALL fetch every remote tag.
On a `get` that asks for every tag in a shallow clone it SHALL fetch the tags whose commits are present without a depth limit and the tags whose commits are absent at depth 1, so no existing shallow boundary is removed and the branch's depth is unchanged.
It SHALL NOT force a local tag that moved upstream.
On a `hydrate` it SHALL fetch, in one request per pass, every object of the revision's tree the clone lacks, keeping the clone's filter and depth, and SHALL skip a revision whose commit the clone does not hold without fetching it.

#### Scenario: A request carries an option, an unknown action, or a disallowed protocol

- **WHEN** a request reaches the writer whose target begins with `-`, whose action is outside the fixed set, whose depth is not a positive integer, whose revision is a range, a reflog entry, a path within a tree or begins with `-`, or whose URL uses a protocol outside the allowed set, such as `ext::` or `file://`
- **THEN** the writer refuses it, the requester exits non-zero, and the shared root is unchanged

#### Scenario: A request asks for every tag in a shallow clone

- **WHEN** a `get` request with an update and every tag names a shallow clone whose branch was deepened
- **THEN** every remote tag is present afterwards, every shallow boundary present before remains, and the branch's depth is unchanged

#### Scenario: A hydrate request needs a protocol the writer does not allow

- **WHEN** a `hydrate` request names a clone whose remote uses a protocol outside the allowed set
- **THEN** the fetch fails, the requester is told the hydration failed, and the revision's contents remain absent

#### Scenario: A request names a path outside the shared root

- **WHEN** a `deepen`, `promote` or `hydrate` request names a path that resolves outside the shared root
- **THEN** the writer refuses it without running git

### Requirement: Migration moves only administrators' trees in place, sets other trees aside, and can be rolled back

Migration SHALL move an account's existing tree into the shared root in place only when that account is a member of the host's administrator group (`wheel` on NixOS, `admin` on darwin) at the time of the move; for any other account, and for a tree holding any entry owned by an account other than that administrator or root, writable by every account, group-writable for a group with other members, a non-directory with a hard link outside the tree, or carrying an ACL, an in-place move SHALL be refused with nothing changed, and the plan SHALL list each such entry.
While a tree moves, it and the shared root SHALL be reachable by no account but root and the writer SHALL be stopped, until the root is opened to the writer's group at the end.
An in-place move SHALL be made without re-fetching: by rename when the root is empty and on the same filesystem as the account's home, otherwise by copy followed by renaming the source to `~/ghq.pre-shared-<date>`.
Where two administrators hold the same repository, the deeper clone SHALL be kept and the other SHALL stay in that account's `~/ghq.pre-shared-<date>/`.
Every entry moved in SHALL be owned by the writer, SHALL NOT be group-writable or carry any permission for others, and SHALL carry no setuid, setgid or sticky bit.
After the root is opened to the writer's group and while the writer's socket is still stopped, migration SHALL, as the writer with umask `0027` and the shared tree's LFS settings, set back to its staged pointer file every LFS-tracked path whose file holds exactly the content that pointer names, keeping that content and the prior index in the record directory, and refresh the index of each repository it changed; a file whose content differs from its pointer's object SHALL be left as it is, and nothing else in a moved tree is changed.
Setting a tree aside SHALL rename that account's `~/ghq` to `~/ghq.pre-shared-<date>`, still owned by the account, and SHALL list each repository's upstream URL with the `ghq-sync` command that reacquires it through the writer as that account.
Migration SHALL list repositories with uncommitted changes or commits on no remote before applying, SHALL record each step, with prior ownership and modes, in a root-owned `0700` directory outside the shared root before taking it, and SHALL refuse an account whose record has not been rolled back.
`--rollback` SHALL restore each account's prior tree, ownership, modes and the content of every LFS path set back to its pointer, give the account every entry the writer created in that tree after migration, and read the records of earlier versions of the tool; a rollback that stopped part way SHALL resume when run again.

#### Scenario: A non-administrator's tree is to be moved in place

- **WHEN** `--apply` names an account that is not an administrator of the host
- **THEN** the tool refuses, and no account's tree, the shared root and the record directory are unchanged

#### Scenario: Another account could have written an administrator's tree

- **WHEN** an entry in an administrator's tree carries an ACL, is writable by every account, is owned by another account, or is a hard link to a file outside the tree
- **THEN** the plan lists that entry, `--apply` refuses, and no tree, the shared root and the record directory are changed

#### Scenario: A tree is moving

- **WHEN** an administrator's tree is being moved into the shared root
- **THEN** an account without administrative authority cannot read the shared root, and the writer accepts no request

#### Scenario: A non-administrator's tree is set aside

- **WHEN** `--set-aside` names an account
- **THEN** its tree is at `~/ghq.pre-shared-<date>`, still owned by it, `~/ghq` links to the shared root, and each repository's reacquisition command is printed

#### Scenario: An administrator's tree carries a setuid file

- **WHEN** an administrator's tree holding a setuid file is moved in place
- **THEN** nothing in the shared root carries a setuid, setgid or sticky bit

#### Scenario: An administrator's tree holds smudged LFS content

- **WHEN** an administrator's tree holding an LFS-tracked path whose file is the content its pointer names is moved in place
- **THEN** the path holds its pointer file afterwards, the writer's git reports it unchanged, every entry beneath the shared root is owned by the writer, and a rollback restores the content byte for byte

#### Scenario: A dry run is taken

- **WHEN** migration runs without `--apply` or `--set-aside`
- **THEN** it lists the planned moves, the repositories with uncommitted changes or local-only commits, and the refusal and reacquisition commands for each non-administrator, and changes nothing on disk

#### Scenario: Migration is rolled back for one account

- **WHEN** the rollback for one account is run before anything set aside is deleted
- **THEN** that account's `~/ghq` is again its own directory with its prior contents, ownership and modes

#### Scenario: A rollback stops part way

- **WHEN** a rollback fails after undoing some steps, and is run again once the cause is removed
- **THEN** it completes, and the account's tree is as it was before migration

### Requirement: Each property is backed by evidence that can fail

The declared properties above SHALL be checked by module assertions in the per-machine checks for magnetite, pyrite and stibnite, and the runtime properties by executed NixOS tests of one node declaring the writer, a human and a worker account, with fixture repositories served inside the test.
The test holding the write probe SHALL include a control proving the probe can observe a successful write.
Darwin runtime properties SHALL be observed by post-activation inspection on stibnite, recorded with the exact commands run.

#### Scenario: The write probe is broken

- **WHEN** the NixOS test's write probe would report refusal regardless of permissions
- **THEN** the control write, performed by the writer into the same tree, is reported as refused and the test fails

Witness: `vmTests.x86_64-linux.shared-reference-tree.mutations.broken-control`, built on demand, which fails at subtest "the writer's own write succeeds (control)".

### Requirement: This capability states its own trust boundary

The properties above SHALL be read as holding at the boundary of the hosts' declared configuration and Unix discretionary permissions, observed by evaluation, by an executed NixOS test and by post-activation inspection.
They SHALL NOT be read as covering a participating account that sets `GHQ_ROOT` or passes `-c` overrides on its own command line, root or the `ghq` account acting against the tree, the content of upstream repositories, darwin runtime behaviour beyond what inspection on stibnite observed, or any confinement of code running inside an account.
The writer SHALL NOT delete, rename or relocate a repository: retiring or relocating the clone of a renamed, transferred or deleted upstream is an administrator's act as the writer, which the audit only prints.

#### Scenario: A guarantee about upstream content is sought

- **WHEN** a reader asks whether a reference repository's content is trustworthy because it sits in the shared tree
- **THEN** this capability answers nothing about that content beyond who wrote it to disk

#### Scenario: A participating account overrides its own root

- **WHEN** a participating account sets `GHQ_ROOT` to a directory it owns
- **THEN** ghq uses that directory for that process, and this capability makes no claim about it

#### Scenario: An upstream repository is renamed

- **WHEN** an upstream repository is renamed or transferred, and its clone stays under the old name
- **THEN** no request to the writer removes or moves that clone; the audit prints the commands, and only an administrator acting as the writer runs them

### Requirement: The shared tree holds LFS pointer files, and the writer runs no LFS filter

Every working tree beneath the shared root SHALL hold each Git LFS path as the pointer file committed for it.
Every git invocation the writer's handler and the migration tool make SHALL carry, at command scope, `filter.lfs.process`, `filter.lfs.clean` and `filter.lfs.smudge` set empty and `filter.lfs.required` set to `false`, so that no repository-local setting re-enables an LFS filter for the writer.
Trust boundary: nothing here covers the content an LFS pointer names.

#### Scenario: An update changes an LFS path upstream

- **WHEN** the writer updates a clone whose configuration names `git-lfs` as a required filter, and the upstream changed an LFS-tracked file
- **THEN** the update fast-forwards and the file holds the new pointer, while the same update made without the four settings fails

### Requirement: Participating accounts' git runs no LFS filter beneath the shared root

Each participating account's git configuration SHALL include the writer's four LFS settings under a `gitdir:<form>/` condition for every form the shared root resolves to (`/var/lib/ghq` on NixOS; `/var/lib/ghq` and `/private/var/lib/ghq` on darwin), and the host's configuration SHALL fail evaluation when a participant lacks one.
Trust boundary: a repository-local `filter.lfs.*` setting outranks the account's global include and is not covered.

#### Scenario: A participating account runs git status in an LFS repository

- **WHEN** a participating account whose own git configuration enables git-lfs runs `git status` in a repository beneath the shared root
- **THEN** git runs no LFS filter, writes nothing beneath the shared root, and reports the repository as the writer's git does

#### Scenario: A participant's include is missing a root form

- **WHEN** a participating account's evaluated git includes lack the LFS settings for one of the shared root's forms
- **THEN** that host's configuration fails evaluation

### Requirement: An update follows the remote's default branch

On an update, the writer SHALL read the branch the remote's `HEAD` names and follow it: a clone that fetches single branches SHALL fetch the new one at its current depth and check it out, and any other clone SHALL move `origin/HEAD` and check out the new branch only when it was on the previous default with no local change.
The writer SHALL report each change of default branch in one status line.

#### Scenario: The remote renames its default branch

- **WHEN** an update meets a remote whose default branch changed from `master` to `main`, with `master` deleted or kept
- **THEN** a lazy clone is on `main` at the remote's tip with its depth and filter unchanged, a clean full clone on `master` is on `main`, a full clone on another branch or with local changes keeps its branch while its `origin/HEAD` names `main`, and the reply reports `default branch: master -> main`

### Requirement: The writer's request handler sets its own umask

The writer's request handler SHALL set its umask to `0027` before it reads a request, whatever umask its service starts it with, so that nothing the writer writes beneath the shared root carries a permission for others or group write.

#### Scenario: The service starts the handler with a permissive umask

- **WHEN** the handler is started with umask `022`, as launchd starts the instance it spawns per connection, and carries out clones, fetches and updates
- **THEN** no entry it wrote beneath the shared root grants any permission to others or write to its group

### Requirement: A participating account audits the tree against GitHub without changing it

`ghq-sync --audit [QUERY]` SHALL ask GitHub's API, with the calling account's own `gh` token, about every github.com repository in `ghq list [QUERY]`, and SHALL report renamed or transferred, deleted or inaccessible, archived, letter-case-only and default-branch differences, each rename with the commands that retire or relocate the clone as the writer.
It SHALL change nothing beneath the shared root, and without a token it SHALL say so and exit zero.

#### Scenario: Upstreams drifted

- **WHEN** a participating account runs `ghq-sync --audit` over clones whose upstreams were renamed, deleted, archived, renamed in letter case only, or given another default branch
- **THEN** it prints one finding for each with the commands for a rename, prints a count of repositories checked, and every entry beneath the shared root is unchanged

#### Scenario: No token

- **WHEN** a participating account without `gh` or without a stored token runs `ghq-sync --audit`
- **THEN** it says that nothing was checked and exits zero

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
