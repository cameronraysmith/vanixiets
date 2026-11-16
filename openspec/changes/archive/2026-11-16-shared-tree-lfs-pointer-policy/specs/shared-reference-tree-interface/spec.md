## ADDED Requirements

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

## MODIFIED Requirements

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
