<!--
Raw capture of the brainstorming step for this change.

Procedural note, recorded rather than elided: the interactive `superpowers:brainstorming`
dialogue was not run. This change was authored by a delegated session whose brief
pre-settled the root, wiring and documentation decisions; the writer model was put to the
user and confirmed on 2026-10-16 while this capture was being written, and the delegation
transport and the migration procedure remain open. The schema-sanctioned manual-write path
was taken. What follows is the decision log the interactive skill would have produced.
Questions answered by the brief are marked `[given]`; questions answered from repository or
upstream evidence are marked `[decided]` with the evidence inline; questions the user
answered are marked `[user]`; questions awaiting the user are marked `[open]`.
-->

# Background

Every account that reads upstream source keeps its own ghq tree today.
On magnetite and pyrite that is `cameron`, `omnigent-cameron` and `omnigent-janettesmith`; on stibnite it is `crs58` and `omnigent-cameron`.
Each tree is a separate clone of the same repositories, so the same reference repository is fetched, stored and kept current once per account, and an agent working as `omnigent-cameron` cannot see what `cameron` already acquired.

ghq resolves its root in a fixed order (`~/ghq/github.com/x-motemen/ghq/local_repository.go:381-450`, read at the local clone): a nonempty `GHQ_ROOT` is the sole root; otherwise every `ghq.root` value from `git config --get-all`, the last one primary; otherwise `$HOME/ghq`.
Per-URL roots come from `ghq.<url>.root`.
Each root passes through `filepath.EvalSymlinks`, so `~/ghq` may be a symlink to a shared directory and ghq reports the resolved path.
No ghq patch is needed for any option below.

Nothing under `modules/` sets `ghq.root` or `GHQ_ROOT`; `~/ghq` is ghq's built-in default.
The `dependency-source-acquisition` skill nonetheless says "This fleet configures `ghq root` to `~/ghq`" (`modules/home/ai/plugins/version-control-and-forge/.apm/skills/dependency-source-acquisition/SKILL.md:40`), which is wrong today and becomes more wrong after this change.

ghq reaches accounts through two Home Manager exports.
`modules/home/development/repository-acquisition.nix` defines `homeManager.ghq` and `homeManager.repository-acquisition`; `modules/home/tools/ghq-sync.nix` defines `homeManager.ghq-sync`.
The wrapper `pkgs/by-name/ghq-sync/` is a `writeShellApplication` whose `runtimeInputs` include nixpkgs `ghq` and `git`, so it calls its own store-path `ghq` rather than whatever `ghq` an account's profile provides.
It clones shallow and blobless and registers the path with the invoking account's zoxide; `--seed-zoxide` re-indexes without network.
`checks.<system>.omnigent-worker-capabilities` asserts that `ghq` and `ghq-sync` are in a worker's home packages (`modules/checks/omnigent-workers.nix:171-181`).

Accounts and their isolation are declared in several places.
Linux workers are declared in `modules/clan/inventory/services/users/omnigent-workers.nix` with private groups, empty `extraGroups` and `0700` homes.
Stibnite declares `crs58` (UID 501, primary user) and `omnigent-cameron` (UID/GID 551) in `modules/machines/darwin/stibnite/default.nix:114-139`.
No Unix account named `janettesmith` exists on any host; Janette participates only through `omnigent-janettesmith`.
`flake.lib.omnigentFleetObligations` asserts that a worker belongs to no group but its own and has `extraGroups == [ ]` (`modules/lib/omnigent-fleet-obligations.nix:64-97`).
The Linux host adapter rejects any `security.sudo.extraRules` entry that names a worker, regardless of its run-as target (`modules/nixos/omnigent-host.nix:235-260`).
On stibnite, worker homes are standalone `homeManagerConfiguration` values with `osConfig = null` (`modules/darwin/omnigent-host.nix:95-140`); on Linux they are `home-manager.users.<worker>` entries (`modules/nixos/omnigent-host.nix:287-300`).

Git refuses to read a repository owned by another account unless that repository matches a `safe.directory` entry in protected configuration; a value ending in `/*` admits every repository beneath that directory, and `*` disables the check (`git help config`, installed git 2.55.0).
Repository-local configuration can name programs git runs: `core.fsmonitor`, `core.hooksPath`, `core.pager`, `core.sshCommand`, `diff.external`, and filter and textconv drivers among them.

# Decision chain

## Q1 [given]: one tree per host, or one per account?

One shared tree per host, used by every human and worker account on that host, on magnetite, pyrite and stibnite.

## Q2 [given]: where does the shared tree live?

`/var/lib/ghq` on NixOS and `/Users/Shared/ghq` on darwin.
Each participating account's `~/ghq` becomes a symlink to it, so existing references to `~/ghq/<host>/<org>/<repo>` keep resolving.

## Q3 [given]: how does ghq learn the root — `GHQ_ROOT` or `ghq.root`?

`ghq.root`, set in each participating account's Home Manager git configuration.
`GHQ_ROOT` is an environment variable, and launchd agents and systemd units do not inherit an interactive shell's environment, so a worker started by its supervisor would resolve a different root from the same account's shell.
Git's global configuration is read by every git-driven process regardless of how it was started.

## Q4 [user, 2026-10-16]: who may write the shared tree?

A single writer.
A dedicated `ghq` system account owns and fetches the tree; every other participating account (`cameron`, `crs58`, `omnigent-cameron`, `omnigent-janettesmith`) reads it through a `ghq` group and cannot write it.
The user confirmed this on 2026-10-16, conditional on runtime evidence that it behaves as intended.

Two alternatives were rejected.
O2, every member writes the tree through a `ghq` group (setgid `2775`, a default ACL, `core.sharedRepository=group`, `safe.directory` admitting the shared root).
O3, human accounts write and agent accounts read.
Both fail on the same mechanism: repository-local `.git/config` can name programs git runs, such as `core.fsmonitor` and `core.hooksPath`, and the next account that runs git in that repository executes them as itself.
A prompt that shows git status runs git on every `cd`, so the planted program fires on entering the directory, not only on an explicit git command.
Repository-local configuration outranks global configuration, so no setting in the victim's own `~/.config/git/config` neutralises it.
`safe.directory` is the mechanism git provides against exactly this, and O2 must admit the shared root through it to function, which disables the protection for every repository in the tree.
Under O2 an agent working as `omnigent-cameron` could thereby run code as `cameron` or `crs58`, who hold signing keys, secrets and sudo.
O3 removes the agent-to-human direction but keeps every human able to plant configuration that runs as the other human and as every agent, and it still admits the tree through `safe.directory`.

The accepted costs of the single writer: every acquisition, update, deepen and promotion is delegated to the writer; readers' `git fetch` and `git gc` fail; `git status` cannot refresh the index and reports from the stale one.

## Q5 [user + open]: how does a read-only account obtain a repository the tree lacks?

The client shape is decided by the user: a Home Manager-delivered `ghq` wrapper runs read-only subcommands (`list`, `root`, `--help`) directly and hands `get` and `get -u` to the writer.
`ghq-sync` must use that wrapper, because it otherwise calls its own `runtimeInputs` copy of nixpkgs `ghq`, and its `--deepen` and `--full` modes call git directly in the clone, so they must be handed to the writer too.

The transport between reader and writer is open: (a) a narrow `sudo -u ghq` rule; (b) a socket-activated systemd unit on NixOS and a launchd socket daemon on darwin; (c) a request directory the writer watches (systemd path unit, launchd `QueueDirectories`).
Option (a) conflicts with the existing Linux worker guard that rejects any sudo rule naming a worker, whatever its run-as target.

## Q6 [open]: how do existing per-account trees move to the shared root?

Copy, verify, then switch, with a recorded rollback; deleting a per-account copy is a separate human-gated step.
Stibnite's `crs58` tree is large.
A copied repository brings its `.git/config` and hooks with it, and a worker-owned tree is untrusted input, so the procedure must not carry repository-local executable configuration into a tree other accounts will run git in.

## Q7 [decided]: what happens to zoxide?

It stays per account.
zoxide's database lives in each account's home, and `ghq-sync --seed-zoxide` re-indexes the shared tree into the calling account's database without network.

## Q8 [decided]: where do the invariants get checked?

On the cheapest rung that can observe each failure, per the `preferences-nix-checks-architecture` placement ladder.
Declared facts (group membership equals the declared participant set, `safe.directory` never `*`, root mode carries no world bits) are module `assertions` riding on the per-machine toplevel checks that already evaluate magnetite, pyrite and stibnite.
Behaviour that only a running system shows (a read-only account's write to `.git/config` fails; a member's write succeeds under option 2) needs an executed NixOS VM test with a negative control.
No darwin VM test node type exists, so stibnite's runtime facts are post-activation inspection.

## Q9 [given]: which documentation changes?

The `dependency-source-acquisition` skill and `modules/home/ai/plugins/agent-context-vanixiets/.apm/instructions/30-reference-repositories.instructions.md`, edited at their sources, never in generated `AGENTS.md`.
`ghq list -p` prints the resolved shared path rather than `~/ghq/...`.

# Addendum, 2026-10-16: user decisions after the first capture

## Q5 [user]: transport

Option (b): a socket-activated systemd unit on NixOS (group `ghq`, mode `0660`, `Accept=yes`, caller identity by `SO_PEERCRED`) and a launchd daemon with `Sockets` on darwin (caller identity by `LOCAL_PEERCRED`). The Linux worker sudo guard stays untouched.

## Q6 [user]: migration

Move the existing trees; re-cloning is rejected because stibnite's `crs58` tree is large and must not be re-fetched.
Rename where root and home share a volume (`/Users/crs58/ghq` to `/Users/Shared/ghq` on one APFS volume is O(1), confirmed with `stat -f %d` first); copy with clonefile or reflink only across volumes; then a metadata-only `chown -R` to the writer.
Rollback is the reverse rename and chown.
Keep the sanitisation: strip non-sample hooks and rewrite each `.git/config` to an allow-list, recording the originals in a per-repository sidecar outside the shared root.
Where two accounts hold the same repository, keep the deeper clone and set the other aside.
Move everything as it is, including repositories with uncommitted changes or local-only commits, and list them before the switch; after the move they belong to the writer and are read-only to their former owner, which is an accepted cost.

## Q7 [user]: darwin writer

`_ghq`, with its UID/GID chosen at apply time from live `dscl` collision evidence and approved by the user before it is committed.

## Q8 [user]: execution

HIL; `tasks.md` is the ledger; one task is one commit on the change's chain.
