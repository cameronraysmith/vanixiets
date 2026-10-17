---
execution_mode: HIL
linear_story_id: "8e3dbe06-1450-440f-80c8-8bb6b9593665"
linear_story_identifier: CAM-77
linear_story_title: Share one ghq reference tree per host
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-77/share-one-ghq-reference-tree-per-host
linear_story_state: In Review
linear_team: CAM
linear_project: omnigent-magnetite
last_synced_state: In Review
last_synced_at: "2026-10-21T02:49:41Z"
review_round: 0
attempt_log:
  - at: "2026-10-16T17:06:03Z"
    transition: Backlog->Todo
    outcome: posted
    note: Created CAM-77 in Backlog in the existing omnigent-magnetite project with the business description seeded from this proposal, moved it to Todo, confirmed Todo by readback, and posted the binding comment.
  - at: "2026-10-16T17:29:46Z"
    transition: description-sync
    outcome: posted
    note: Re-synced the business description after the transport, migration and darwin-writer decisions.
  - at: "2026-10-16T17:31:47Z"
    transition: Todo->In Progress
    outcome: posted
    note: T2 on the first checked tasks.md box (1.1); state confirmed In Progress by readback and comment posted.
  - at: "2026-10-17T06:13:31Z"
    transition: description-sync
    outcome: posted
    note: Re-synced the business description after the darwin root moved to /var/lib/ghq and the _ghq UID/GID and delivery plan were approved; readback confirmed.
  - at: "2026-10-17T20:08:14Z"
    transition: In Progress->In Review
    outcome: posted
    note: T3 on verify.md (PASS WITH WARNINGS); state confirmed In Review by readback and comment posted.
  - at: "2026-10-17T20:15:30Z"
    transition: In Review->In Progress
    outcome: posted
    note: Re-queue after code review round 1 of 3 rejected the change (4 blockers in the migration tool); state confirmed In Progress by readback and comment posted.
  - at: "2026-10-17T23:30:12Z"
    transition: In Progress->In Progress
    outcome: dropped
    note: Code review round 2 of 3 rejected the change (G1 nested .git files and .git/modules commondir, G2 ACLs); the issue was already In Progress, so no Linear write was made.
  - at: "2026-10-18T05:26:54Z"
    transition: In Progress->In Progress
    outcome: dropped
    note: Code review round 3 of 3 found H1-H7; the user narrowed the migration trust boundary to administrators (design D10) instead of another hardening round; the issue stays In Progress, so no Linear write was made.
  - at: "2026-10-21T02:49:41Z"
    transition: In Progress->In Review
    outcome: posted
    note: T3 after code review rounds 1-4 closed and post-deploy checks passed on all three hosts; verify.md PASS WITH WARNINGS; state confirmed In Review by readback and comment posted.
---

## Why

Every account that reads upstream source keeps its own ghq tree, so magnetite and pyrite each hold three clones of the same reference repositories and stibnite holds two, each fetched and kept current separately.
An agent working as an Omnigent worker cannot see what its human owner already acquired, and the human cannot see what the agent fetched.
One tree per host removes the duplication and gives every account on a host the same view of upstream source.
Sharing it naively would let any account plant configuration that runs as the next account to use a repository, so the tree has one writer and every other account reads.

## What Changes

**Reference tree location**
- From: each account's `~/ghq`, ghq's built-in default; nothing in the fleet sets a root.
- To: one tree per participating host, `/var/lib/ghq` on every participating host; each participating account's `~/ghq` is a symlink to it and its git configuration names it as `ghq.root`.
- Reason: one copy per host, visible to every human and worker account there.
- Impact: non-breaking for readers of `~/ghq/<host>/<org>/<repo>` paths; `ghq list -p` now prints the shared path.

**Who writes the tree**
- From: every account writes its own tree.
- To: a dedicated system account (`ghq` on NixOS, `_ghq` on darwin) owns and writes the shared tree; `cameron`, `crs58`, `omnigent-cameron` and `omnigent-janettesmith` read it through a `ghq` group and cannot write it. The user confirmed this model on 2026-10-16, conditional on runtime evidence that it behaves as intended.
- Reason: repository-local git configuration can name programs that git runs as whichever account next uses that repository, and only a single writer keeps that power out of every reader's hands.
- Impact: readers cannot `git fetch`, `git gc` or refresh the index inside the tree; acquisition goes through the writer.

**Acquiring a repository the tree lacks**
- From: `ghq-sync <url>` clones into the caller's own tree.
- To: a Home Manager-delivered `ghq` wrapper runs read-only subcommands directly and hands `get` and `get -u` to the writer over a socket-activated service (systemd on NixOS, launchd on darwin); `ghq-sync` uses that wrapper and also hands its `--deepen` and `--full` modes to the writer.
- Reason: a reader must be able to obtain a missing repository without a person intervening.
- Impact: `ghq-sync` keeps its interface; each account's zoxide index stays its own.

**Existing per-account trees**
- An administrator's tree (a member of `wheel` on NixOS, `admin` on darwin) is moved into the shared tree as it is, never re-fetched: renamed where the home and the shared tree share a volume (stibnite), copied otherwise; duplicates keep the deeper clone and set the other aside. Any other account's tree, every Omnigent worker's included, is set aside in its home and its repositories are fetched again through the writer (user decision 2026-10-17); repositories with unpublished work are listed first and become read-only to their former owner. Every move can be rolled back per account, and deleting anything set aside is a separate step a person authorizes.

**Documentation**
- The `dependency-source-acquisition` skill, which wrongly says the fleet configures `ghq root` to `~/ghq`, and the vanixiets reference-repositories instruction fragment describe the shared root.

## Capabilities

### New Capabilities

- `shared-reference-tree` [behavioral]: one reference tree per participating host, read by every participating account, changed only by the writer, extended on request, and introduced without losing anyone's existing copies.
- `shared-reference-tree-interface` [interface]: the shared root's location, ownership and mode; the writer account (`ghq` on NixOS, `_ghq` on darwin) and reader group; each participating account's resolved root, `~/ghq` link and `safe.directory` scope; the socket-activated delegation entry point and the requests it accepts; the migration tool's administrator-only moves, set-aside path and rollback; and the evidence that each property holds.

The interface trust boundary covers what the hosts' declared configuration and Unix permissions enforce, observed by evaluation, an executed NixOS test and post-activation inspection.
It does not cover an account that sets `GHQ_ROOT` or a `-c` override on its own command line, root or the writer account itself acting maliciously, the content of upstream repositories, or any darwin runtime property beyond what post-activation inspection on stibnite observes.
It confers no confinement on code running inside an account.

### Modified Capabilities

- `world-assumptions` [world]: adds A34 (git runs programs named in repository-local configuration as the account invoking git, and refuses repositories owned by another account unless trusted) and A35 (ghq resolves its root from `GHQ_ROOT`, then `ghq.root`, then `$HOME/ghq`, through symlinks), and adds the designation rows this change's behavioral nouns need.

## Impact

Source: `modules/system/` (a platform-neutral participation option), `modules/nixos/` and `modules/darwin/` (writer account, group, directory provisioning, socket transport), `modules/home/development/repository-acquisition.nix` and `modules/home/tools/ghq-sync.nix` (root, link, `safe.directory`, wrapper), `pkgs/by-name/ghq-shared/` (wrapper, client, writer handler, migration tool), `pkgs/by-name/ghq-sync/` (writer delegation), `modules/checks/package-tests.nix`, `modules/lib/omnigent-fleet-obligations.nix` and `modules/nixos/omnigent-host.nix` / `modules/darwin/omnigent-host.nix` (worker group membership), `modules/checks/omnigent-workers.nix`, `modules/vm-tests/`, `modules/machines/darwin/stibnite/default.nix` (darwin writer UID/GID), and the two documentation sources named above.
Hosts: magnetite, pyrite and stibnite; no other host changes.
State: each administrator's existing `~/ghq` is moved into the shared tree and every other participating account's is set aside in its home; cross-volume sources and set-aside trees are retained until a person authorizes their deletion.
No new flake input.
