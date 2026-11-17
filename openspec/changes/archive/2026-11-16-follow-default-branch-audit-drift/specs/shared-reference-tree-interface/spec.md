## ADDED Requirements

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

## MODIFIED Requirements

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
