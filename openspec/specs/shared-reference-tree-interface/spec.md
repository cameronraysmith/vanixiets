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
`ghq-sync` SHALL use that same `ghq` command, its `--deepen` and in-place `--full` work SHALL be handed to the writer, and it SHALL register resulting paths with the calling account's own zoxide database.
Requests SHALL reach the writer only through a socket at `/run/ghq-writer.sock` (NixOS) or `/var/run/ghq-writer.sock` (darwin), owned by the writer's group with mode `0660`, whose service starts one handler per connection as the writer with umask `0027`.

#### Scenario: A participating account clones a missing repository

- **WHEN** a participating account runs `ghq get <url>` or `ghq-sync <url>` for a repository absent from the shared root
- **THEN** the repository appears beneath the shared root owned by the writer, `ghq list -p` as the participating account prints its path, and that path is in the participating account's zoxide database

#### Scenario: A participating account bypasses the wrapper

- **WHEN** a participating account runs `git fetch` or `git clone` directly against a path beneath the shared root
- **THEN** the operating system refuses the write with a permission error

#### Scenario: An account outside the writer's group connects to the socket

- **WHEN** an account that is not a member of the writer's group connects to the writer's socket
- **THEN** the connection is refused by the socket's mode, and a handler started by any other path refuses a caller whose connection identity is outside the group

### Requirement: The writer accepts only constrained requests

The writer SHALL accept one request per connection, at most 4 KiB, naming exactly one of `get` (a target, whether lazy, whether an update, whether every tag), `deepen` (a positive depth and a path) or `promote` (a path).
It SHALL refuse a target that begins with `-`, contains `..` as a path segment or `::`, contains a character outside `A-Za-z0-9._~:/@+%-`, or names a scheme outside its allowed protocols, and a path that does not resolve inside the shared root.
It SHALL run git and ghq without a shell, with no system or global git configuration, and with `protocol.allow=never` except for its allowed protocols, which default to `https`.
On an update of a full clone it SHALL fetch every remote tag.
On a `get` that asks for every tag in a shallow clone it SHALL fetch the tags whose commits are present without a depth limit and the tags whose commits are absent at depth 1, so no existing shallow boundary is removed and the branch's depth is unchanged.
It SHALL NOT force a local tag that moved upstream.

#### Scenario: A request carries an option, an unknown action, or a disallowed protocol

- **WHEN** a request reaches the writer whose target begins with `-`, whose action is outside the fixed set, whose depth is not a positive integer, or whose URL uses a protocol outside the allowed set, such as `ext::` or `file://`
- **THEN** the writer refuses it, the requester exits non-zero, and the shared root is unchanged

#### Scenario: A request asks for every tag in a shallow clone

- **WHEN** a `get` request with an update and every tag names a shallow clone whose branch was deepened
- **THEN** every remote tag is present afterwards, every shallow boundary present before remains, and the branch's depth is unchanged

#### Scenario: A request names a path outside the shared root

- **WHEN** a `deepen` or `promote` request names a path that resolves outside the shared root
- **THEN** the writer refuses it without running git

### Requirement: Migration moves only administrators' trees in place, sets other trees aside, and can be rolled back

Migration SHALL move an account's existing tree into the shared root in place only when that account is a member of the host's administrator group (`wheel` on NixOS, `admin` on darwin) at the time of the move; for any other account, and for a tree holding any entry owned by an account other than that administrator or root, writable by every account, group-writable for a group with other members, a non-directory with a hard link outside the tree, or carrying an ACL, an in-place move SHALL be refused with nothing changed, and the plan SHALL list each such entry.
While a tree moves, it and the shared root SHALL be reachable by no account but root and the writer SHALL be stopped, until the root is opened to the writer's group at the end.
An in-place move SHALL be made without re-fetching: by rename when the root is empty and on the same filesystem as the account's home, otherwise by copy followed by renaming the source to `~/ghq.pre-shared-<date>`.
Where two administrators hold the same repository, the deeper clone SHALL be kept and the other SHALL stay in that account's `~/ghq.pre-shared-<date>/`.
Every entry moved in SHALL be owned by the writer, SHALL NOT be group-writable or carry any permission for others, and SHALL carry no setuid, setgid or sticky bit; nothing else in a moved tree is changed.
Setting a tree aside SHALL rename that account's `~/ghq` to `~/ghq.pre-shared-<date>`, still owned by the account, and SHALL list each repository's upstream URL with the `ghq-sync` command that reacquires it through the writer as that account.
Migration SHALL list repositories with uncommitted changes or commits on no remote before applying, SHALL record each step, with prior ownership and modes, in a root-owned `0700` directory outside the shared root before taking it, and SHALL refuse an account whose record has not been rolled back.
`--rollback` SHALL restore each account's prior tree, ownership and modes, give the account every entry the writer created in that tree after migration, and read the records of earlier versions of the tool; a rollback that stopped part way SHALL resume when run again.

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

The declared properties above SHALL be checked by module assertions evaluated as part of the existing per-machine checks for magnetite, pyrite and stibnite, and the runtime properties SHALL be checked by an executed NixOS test whose node declares the writer, a human account and a worker account and uses only fixture repositories served inside the test.
The NixOS test SHALL include a control that proves its write probe can observe a successful write, so that a probe that always fails cannot pass.
Darwin runtime properties SHALL be observed by post-activation inspection on stibnite, recorded with the exact commands run.

#### Scenario: The write probe is broken

- **WHEN** the NixOS test's write probe would report refusal regardless of permissions
- **THEN** the control write, performed by the writer into the same tree, is reported as refused and the test fails

### Requirement: This capability states its own trust boundary

The properties above SHALL be read as holding at the boundary of the hosts' declared configuration and Unix discretionary permissions, observed by evaluation, by an executed NixOS test and by post-activation inspection.
They SHALL NOT be read as covering a participating account that sets `GHQ_ROOT` or passes `-c` overrides on its own command line, root or the `ghq` account acting against the tree, the content of upstream repositories, darwin runtime behaviour beyond what inspection on stibnite observed, or any confinement of code running inside an account.

#### Scenario: A guarantee about upstream content is sought

- **WHEN** a reader asks whether a reference repository's content is trustworthy because it sits in the shared tree
- **THEN** this capability answers nothing about that content beyond who wrote it to disk

#### Scenario: A participating account overrides its own root

- **WHEN** a participating account sets `GHQ_ROOT` to a directory it owns
- **THEN** ghq uses that directory for that process, and this capability makes no claim about it
