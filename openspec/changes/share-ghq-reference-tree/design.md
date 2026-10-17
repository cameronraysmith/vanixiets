## Context

Each account that reads upstream source keeps its own ghq tree under `~/ghq`, ghq's built-in default; no module sets `ghq.root` or `GHQ_ROOT`.
On magnetite and pyrite the accounts that read reference source are `cameron`, `omnigent-cameron` and `omnigent-janettesmith`; on stibnite they are `crs58` (UID 501, primary user) and `omnigent-cameron` (UID/GID 551).
There is no Unix account named `janettesmith` on any of these hosts, and no human account other than `cameron` on magnetite or pyrite.

ghq resolves its root from `GHQ_ROOT`, then the `ghq.root` values in git configuration (last primary), then `$HOME/ghq`, and resolves symbolic links in each root (`~/ghq/github.com/x-motemen/ghq/local_repository.go:381-450`; recorded as A35).
Git runs programs named in repository-local configuration as whichever account invokes git there, ranks that configuration above the account's global configuration, and refuses foreign-owned repositories unless `safe.directory` admits them (recorded as A34).

ghq reaches accounts through `homeManager.ghq` and `homeManager.repository-acquisition` (`modules/home/development/repository-acquisition.nix`) and `homeManager.ghq-sync` (`modules/home/tools/ghq-sync.nix`).
`pkgs/by-name/ghq-sync/` is a `writeShellApplication` with nixpkgs `ghq` and `git` in `runtimeInputs`, so it calls its own `ghq`, not the one an account's profile provides.
Its fetch and update modes call `ghq get`; its `--deepen` mode and the in-place half of `--full` call `git fetch` and `git config` directly in the clone (`ghq-sync.sh:97-143`).

Worker accounts carry existing guards that this change touches.
`flake.lib.omnigentFleetObligations` requires a worker to belong to no group but its own and to have `extraGroups == [ ]` (`modules/lib/omnigent-fleet-obligations.nix:64-97`), and these obligations ride on `checks.x86_64-linux.nixos-magnetite`, `checks.x86_64-linux.nixos-pyrite` and `checks.aarch64-darwin.darwin-stibnite`.
The Linux host adapter rejects any `security.sudo.extraRules` rule that names a worker, whatever its run-as target (`modules/nixos/omnigent-host.nix:235-260`).
Linux worker homes are `home-manager.users.<worker>` entries (`modules/nixos/omnigent-host.nix:287-300`); darwin worker homes are standalone `homeManagerConfiguration` values with `osConfig = null` (`modules/darwin/omnigent-host.nix:95-140`), so a darwin worker cannot read host configuration through `osConfig`.
`checks.<system>.omnigent-worker-capabilities` asserts `pkgs.ghq` and `pkgs.ghq-sync` are in a fixture worker's home packages (`modules/checks/omnigent-workers.nix:171-181`).

On magnetite, `/var/lib` sits on the `zroot/root/nixos` dataset, which carries a 10G reservation and the host's auto-snapshot policy, in a 304G pool where `/nix` is capped at 250G (`modules/machines/nixos/magnetite/default.nix:171-252`).
On magnetite and pyrite `/home` and `/var/lib` are separate ZFS datasets (`modules/machines/nixos/*/disko.nix`), so a tree cannot be renamed from a home into the shared root there; on stibnite `/Users/crs58` and `/var/lib` (`/private/var/lib`, root-owned `0755`) are on the same APFS data volume, where a rename is O(1).
Runtime VM tests that need KVM live in the non-gating `vmTests` lane because the CI builder exposes no `/dev/kvm`; pyrite does (`modules/vm-tests/omnigent-worker-isolation.nix`).

## Goals / Non-Goals

**Goals:**

- One reference tree per sharing host, at `/var/lib/ghq` on every sharing host, read by every participating account.
- A single writer account, so no participating account can plant repository-local configuration that runs as another.
- Acquisition, update, deepen and promotion keep working for every participating account through the existing `ghq` and `ghq-sync` commands, delegated to the writer.
- Every security property maps to a check that fails under a plausible incorrect implementation: module assertions on the real machine checks, an executed NixOS test with a negative control, and recorded post-activation inspection on each host.
- Migration that moves existing trees into the shared root without re-fetching them, loses nothing, and can be reversed per account until a person authorizes deleting what was set aside.

**Non-Goals:**

- Sharing across hosts, or hosts other than magnetite, pyrite and stibnite.
- Confining code running inside any account; this is discretionary Unix permission, not a sandbox.
- Vetting upstream repository content.
- Changing per-account zoxide databases into a shared index.
- Patching ghq.

## Decisions

### D1: Shared root location — revised 2026-10-17

- **Choice**: `/var/lib/ghq` on every sharing host, NixOS and darwin alike; each participating account's `~/ghq` is a symbolic link to it.
- **Rationale**: `/var/lib` is the NixOS location for service-owned state, and on stibnite `/var/lib` (`/private/var/lib`) is root-owned `0755` on the same APFS volume as `/Users/crs58`, which keeps D10's rename O(1). One path on every host removes per-platform branches from the options, the migration tool and the documentation.
- **Alternatives considered**: `/Users/Shared/ghq` on darwin, the original choice, rejected by the user on 2026-10-17. It trips the worker guard in `modules/home/ai/omnigent/worker.nix` that rejects any `/Users/` path outside the worker's own home, which the user chose to keep untouched, and its parent is world-writable with the sticky bit, so any account could create the root first. A dedicated ZFS dataset on magnetite was also deferred: disko applies dataset options only at creation, so it is a manual pool operation; revisit if the tree's size or snapshot churn becomes a problem (see Risks).
- **Boundary**: source-versus-delivered. The directory is created by activation (tmpfiles on NixOS, `postActivation` on darwin), so its existence and mode are observed after activation, not by reading the module.

### D2: Root reaches ghq through git configuration

- **Choice**: each participating account's Home Manager git settings set `ghq.root` to the shared root.
- **Rationale**: launchd agents and systemd units do not inherit an interactive shell's environment, so `GHQ_ROOT` would resolve differently for a supervised worker and the same account's shell. Every git-driven process reads `~/.config/git/config`.
- **Alternatives considered**: `GHQ_ROOT` in session variables (rejected for the reason above); relying on the `~/ghq` link alone without `ghq.root` (rejected: it works only while ghq's `$HOME/ghq` default holds and gives no evaluable signal).
- **Boundary**: source-versus-delivered. `programs.git.settings` evaluates in source; `~/.config/git/config` is delivered by Home Manager activation.

### D3: Single writer — decided, user-confirmed 2026-10-16

- **Choice**: a dedicated system account owns and writes the shared tree: `ghq` on NixOS and `_ghq` on darwin, each with a same-named primary group. `cameron`, `crs58`, `omnigent-cameron` and `omnigent-janettesmith` are members of that group where they participate and read the tree. Root mode `0750`, writer umask `0027`, so nothing beneath the root is group- or other-writable and no participant owns anything there. Each participant's git configuration admits exactly `<shared root>/*` through `safe.directory`.
- **Rationale**: repository-local `.git/config` can name programs git runs (`core.fsmonitor`, `core.hooksPath`, and others listed in A34) as whichever account next runs git in that repository. A prompt that shows git status runs git on every `cd`, so a planted program fires on entering the directory. Repository-local configuration outranks the victim's global configuration, so nothing in the victim's own configuration neutralises it. `safe.directory` is git's protection against exactly this; a tree several accounts write must be admitted through it, which disables that protection for every repository in the tree. With a single writer that no person or agent works under, admitting the tree trusts only the writer.
- **Alternatives considered**: O2, every member writes the tree (setgid `2775`, default ACL, `core.sharedRepository=group`, `safe.directory` admitting the root). Rejected: any member, including an agent working as `omnigent-cameron`, could plant configuration that runs as `cameron` or `crs58`, who hold signing keys, secrets and sudo. O3, human accounts write and agent accounts read. Rejected: it removes the agent-to-human direction but keeps every human able to plant configuration that runs as the other human and as every agent, and it still admits the tree through `safe.directory`.
- **Accepted costs**: every acquisition, update, deepen and promotion is delegated (D5); readers' `git fetch` and `git gc` fail; `git status` cannot refresh the index and reports from the stale one.
- **Condition**: the user's approval is conditional on runtime evidence that the model works as intended (D8, D9).
- **Darwin naming — decided 2026-10-16**: the darwin writer is `_ghq`, following the macOS convention for system accounts.
- **Darwin UID/GID — approved by the user 2026-10-17**: `_ghq` takes UID 460 and GID 460 on stibnite, declared as `services.shared-reference-tree.writerId`. Live `dscl` evidence on stibnite (recorded in `logs/ghq-dscl-evidence-20261017-*.log`, outside version control) showed 460 free as both UID and GID; in use nearby were Apple system accounts 200–308, rosettabuilder 349, nixbld 350–382, `com.apple.access_*` groups 395–400, `_oahd` 441, nix-grpc-daemon 450, crs58 501, runner 502, nixbuild 530, `_dnscrypt-proxy` 535 and omnigent-cameron 551. 460 sits below 500, in the macOS system-account range the `_` prefix denotes, clear of Apple's growing range, the nix build users and the nix-grpc-daemon default.
- **Boundary**: first-party. No vendored module is modified; the writer, group and directory are first-party NixOS and nix-darwin declarations.

### D4: Participation is a platform-neutral host option consumed by a Home Manager option

- **Choice**: `modules/system/shared-reference-tree.nix` declares `services.shared-reference-tree` (enable, participants, writer, root, allowed protocols) for NixOS and darwin. A Home Manager option `programs.ghq-shared.root` (default null), declared once and imported by both `homeManager.ghq` and `homeManager.ghq-sync`, carries the root into each participating account. When set it produces `ghq.root`, the single `safe.directory` entry, the delegating `ghq` and `ghq-sync` of D5, and a `~/ghq` link created by a Home Manager activation step only when `~/ghq` is absent or already a link. The NixOS and darwin adapters set that option for participating accounts through `home-manager.users.<name>` and, for darwin workers, through the darwin worker-home builder.
- **Rationale**: darwin worker homes have `osConfig = null`, so the Home Manager side cannot discover the root on its own. A null default leaves every non-sharing account and every standalone `homeConfigurations` output unchanged. Creating the link in activation rather than through `home.file` lets the generation activate while a real `~/ghq` directory still exists, so the writer account exists before D10 moves the tree; until then that account already reads the shared root through `ghq.root`.
- **Alternatives considered**: `home-manager.sharedModules` (rejected: it does not reach darwin's standalone worker homes); reading `osConfig` (rejected for the same reason); `home.file` with `mkOutOfStoreSymlink` (rejected: Home Manager refuses to replace an existing directory, which would force migration before the writer account exists).
- **Boundary**: first-party, source-versus-delivered as in D2.

### D5: Delegation through a `ghq` wrapper over a socket-activated writer — decided 2026-10-16

- **Client**: when `programs.ghq-shared.root` is set, the account's `ghq` is the wrapper from `pkgs/by-name/ghq-shared/` rather than nixpkgs `ghq`. The wrapper defers to the writer only when the caller's effective ghq root (a nonempty `GHQ_ROOT`, else `git config --path --get ghq.root`) resolves, by `realpath` on both sides, to the shared root `/var/lib/ghq`; for any other root, or none, it executes nixpkgs `ghq` for every subcommand. When it defers, it runs `list`, `root`, `help`, `--help` and `--version` by executing nixpkgs `ghq` directly, refuses `create`, `rm` and `migrate` as read-only, and turns `get` and `get -u` into one request per target to the writer; an unreachable writer fails rather than falling back. Because it is plain `ghq` everywhere else, the repository's development shell carries it too (task 7.4, user-approved 2026-10-17), so `ghq get` inside this checkout on a sharing host goes through the writer instead of failing on permissions. The account's `ghq-sync` is `pkgs.ghq-sync` overridden with the wrapper as its `ghq` and with a delegate, so its `--deepen` and in-place `--full` work is sent to the writer instead of running git in the clone. zoxide registration stays in the calling account.
- **Transport (D-miss) — decided 2026-10-16, option (b)**: on NixOS, `ghq-writer.socket` listens on `/run/ghq-writer.sock`, group `ghq`, mode `0660`, `Accept=yes`, and starts `ghq-writer@.service` per connection as `User=ghq`, `UMask=0027`, with the connection on standard input and output. On darwin, a launchd daemon with a `Sockets` entry at `/var/run/ghq-writer.sock` and `inetdCompatibility` starts one handler per connection as `_ghq` with umask `027`. Its standard error goes to `/var/log/ghq-writer/writer.log` in a `_ghq`-owned `0750` directory that activation creates before launchd loads the job, because launchd opens `StandardErrorPath` as the job's user before spawning it; the first run, in task 9.3, used `/var/log/ghq-writer.log` and failed to spawn. The NixOS unit sends standard error to the journal, so it has no such file. The handler reads the caller's identity from the connection (`SO_PEERCRED` on Linux, `LOCAL_PEERCRED` on darwin) and refuses a caller that is not a member of the writer's group, in addition to the socket's own mode.
- **Writer side**: one JSON request per connection, at most 4 KiB: `get` (target, lazy, update), `deepen` (positive depth, path) or `promote` (path). A target must match `^[A-Za-z0-9][A-Za-z0-9._~:/@+%-]*$`, contain no `..` segment and no `::`, and, if it names a scheme, name an allowed one; a path must resolve inside the root. The handler never uses a shell: `get` runs `ghq get [--shallow --partial blobless --no-recursive] [-u] <target>`, `deepen` runs `ghq-sync --deepen N <path>`, `promote` runs `ghq-sync --full <path>`, with `GHQ_ROOT` set to the root, zoxide registration disabled, `GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null`, and `protocol.allow=never` plus `protocol.<p>.allow=always` for each allowed protocol (`https` by default; the NixOS test adds `git` for its in-VM fixture). Because the writer has no `safe.directory` entry, its git also refuses any repository it does not own. The writer holds no credentials, so private repositories are out of scope.
- **Alternatives considered**: (a) a `sudo -u ghq` rule, rejected because it requires weakening the Linux worker guard that rejects any sudo rule naming a worker; (c) a watched request directory, rejected because `ghq get` would become asynchronous behind a bounded wait and the requester's identity would be only a file owner.
- **Boundary**: first-party. `pkgs/by-name/ghq-sync/` and `pkgs/by-name/ghq-shared/` are first-party packages; nixpkgs `ghq` is consumed unmodified.

### D6: Worker group membership becomes a declared exception

- **Choice**: the fleet obligations permit exactly one additional group, the writer's group, for a worker that the host declares as participating, and still reject every other group. The Linux and darwin adapter guards reject only privileged groups and sudo rules, so the membership passes them unchanged.
- **Rationale**: the obligation `lib.all (name: name == user) memberships` would otherwise fail on every sharing host. Allowing exactly the writer's group keeps the obligation severe against any other added group.
- **Boundary**: first-party.

### D7: Declared facts are module assertions on the existing machine checks

- **Choice**: the adapters assert, against each host's own evaluated configuration: the writer group's members equal the declared participating accounts; the writer has no password, login shell, SSH key, extra group, sudo rule or trusted-user entry; no account's evaluated git settings contain `safe.directory = *`; every participant with a Home Manager entry has `programs.ghq-shared.root` equal to the root; the provisioned root mode is `0750`. These ride on `checks.x86_64-linux.nixos-magnetite`, `checks.x86_64-linux.nixos-pyrite` and `checks.aarch64-darwin.darwin-stibnite` and add no check attributes.
- **Rationale**: the placement ladder in `preferences-nix-checks-architecture` puts configuration facts on the cheapest rung that observes them, which is evaluation of the configuration that must be evaluated anyway. Each assertion relates independently declared values (participants against group members; participants' Home Manager settings against the root), not a read-back of the literal that set it.
- **Alternatives considered**: a new structural check attribute (rejected: it would add a key-set entry and re-evaluate machine configurations).
- **Known limit**: stibnite's obligations are outside CI because the CI evaluator scopes to `checks.x86_64-linux` (`modules/clan/services/omnigent/README.md:152-161`); they are enforced when anyone evaluates the darwin check.

### D8: Runtime behaviour is an executed NixOS test with a negative control

- **Choice**: `vmTests.x86_64-linux.shared-reference-tree`, a `pkgs.testers.runNixOSTest` in `modules/vm-tests/`, single system, static attribute name, one node importing the real `shared-reference-tree` aspect and Home Manager with `repository-acquisition` for a human account `cameron`, a worker account `omnigent-cameron`, and an outsider account. A fixture repository is served inside the VM by `git daemon` over `git://`, which the test adds to the writer's allowed protocols, so no external network is used. Reader assertions: delegated `ghq get` succeeds and the clone is owned by `ghq`; `ghq list -p` prints it; `git log` and `git status` exit zero; `ghq-sync --deepen` and `ghq-sync --full` work through the writer; writing `.git/config`, creating a file in the tree, and `git fetch` fail; requests with a leading `-`, an `ext::` URL or a `file://` URL are refused; git refuses a foreign-owned repository outside the root; the outsider can neither list the root nor connect to the socket. A `core.fsmonitor` the test plants as the writer runs as the reader on the reader's `git status`, demonstrating the threat; no reader can produce that state. The control: the writer's own write into the same tree succeeds, so a probe that always reports refusal fails the test.
- **Rationale**: whether a reader can write is a property of the running system, unobservable by evaluation. The planted-as-writer case shows the probe detects execution, so the reader-cannot-plant assertions are not vacuous.
- **Placement**: the `vmTests` lane, following `omnigent-worker-isolation`, because it needs KVM, which the CI builder lacks. It runs on pyrite's builder and is on-demand evidence, not merge-gating coverage.
- **Alternatives considered**: a clan nspawn container test (not chosen: no precedent here); a pure derivation test of the handler (kept as a complement for request validation, not a substitute).

### D9: Post-activation smoke on each host

- **Choice**: after activation, run the same assertions as D8 as each real participating account on magnetite, pyrite and stibnite, with the exact commands recorded in `tasks.md`. On stibnite this is the only runtime evidence, because no darwin VM test node type exists.

### D10: Migration by move — decided 2026-10-16

- **Choice**: existing trees are moved into the shared root, never re-fetched, by `ghq-shared-migrate`, run as root per host after the generation from D1–D7 is active. It is a dry run unless `--apply` is given.
  - Same volume (stibnite): when the shared root is empty and `stat -f %d` of the root's parent equals that of the account's home, the primary account's `~/ghq` is renamed to the root, an O(1) operation, and the root's mode is reset to `0750`.
  - Across volumes (magnetite and pyrite, whose `/home` and `/var/lib` are separate datasets): repositories are copied with `cp -a --reflink=auto` (`cp -c` on darwin), and the source tree is renamed to `~/ghq.pre-shared-<date>` rather than deleted.
  - Further accounts on the same host are merged per repository. A repository absent from the root is moved in. A repository present in both keeps the deeper clone (full over partial over shallow, then more commits), and the other is moved to `~/ghq.set-aside-<date>/<host>/<owner>/<repo>` in its account's home, unchanged.
  - Ownership: `chown -R -h` to the writer and its group, then `chmod -R g+rX,g-w,o-rwx`; metadata only.
  - Sanitisation, because the writer runs `git fetch` in these repositories and readers run git in them: every `.git/config`, `.git/config.worktree` and `.git/modules/**/config` is rewritten to an allow-list (`core.repositoryformatversion`, `core.bare`, `core.filemode`, `core.logallrefupdates`, `core.ignorecase`, `core.precomposeunicode`, `core.symlinks`, `extensions.*`, `remote.*.url`, `remote.*.fetch`, `remote.*.promisor`, `remote.*.partialclonefilter`, `remote.*.tagopt`, `branch.*.remote`, `branch.*.merge`, `submodule.*.url`, `submodule.*.active`), and every hook other than git's `*.sample` files is removed. The original files are recorded in a per-repository sidecar under `/var/lib/ghq-migration/`, root-owned `0700`, outside the root, so nothing is lost.
  - Every repository moves as it is, including ones with uncommitted changes or commits that exist on no remote. The tool lists them before `--apply` changes anything.
  - The tool writes a manifest of every rename, copy, chown and rewrite to the sidecar directory. `--rollback` replays it in reverse per account: renames back, copies removed, ownership and mode restored, sanitised files restored from the sidecar, and `~/ghq` made a directory again.
  - After an account's tree is moved, the tool replaces its `~/ghq` with a link to the root.
  - Deleting `~/ghq.pre-shared-<date>`, `~/ghq.set-aside-<date>` or the sidecar is a separate step, per account per host, only on the operator's explicit authorization.
- **Accepted cost — decided 2026-10-16**: after the move, uncommitted changes and local-only commits in a moved repository are owned by the writer and read-only to the account that made them, including `crs58` on stibnite. Recovering one means copying it out (`git clone` or `cp -a` into the account's own directory). The pre-switch list is the record of which repositories this affects.
- **Alternatives considered**: re-acquiring every repository by URL (rejected by the user: stibnite's `crs58` tree is large and must not be re-fetched); excluding dirty repositories (rejected by the user: everything moves as it is).
- **Boundary**: source-versus-delivered for the tool; the move itself is state on each host, outside version control.

### D11: Documentation edits at their sources

- **Choice**: edit `modules/home/ai/plugins/version-control-and-forge/.apm/skills/dependency-source-acquisition/SKILL.md` (correct line 40; state that on sharing hosts `$(ghq root)` is the shared root, `ghq list -p` prints the resolved shared path, acquisition is delegated, and readers cannot fetch or promote in place) and `modules/home/ai/plugins/agent-context-vanixiets/.apm/instructions/30-reference-repositories.instructions.md`; update `modules/home/README.md` and `modules/clan/services/omnigent/README.md` for the new option and the worker group exception. Never edit generated `AGENTS.md` or delivered skill copies.
- **Boundary**: source-versus-delivered. Verified on the composed corpus and the evaluated agent-context body, not by reading the source file.

## Risks / Trade-offs

- [Risk] A participant still runs raw nixpkgs `ghq` or `git clone` into the tree and fails confusingly → Mitigation: the wrapper replaces `ghq` on PATH; raw writes fail with a permission error, which the skill text explains.
- [Risk] Two `ghq` executables on one profile collide in Home Manager's `buildEnv` → Mitigation: the Home Manager option swaps the package rather than adding the wrapper beside `pkgs.ghq`; the non-sharing default keeps `pkgs.ghq`, so `omnigent-worker-capabilities` keeps passing for its non-sharing fixture.
- [Risk] On darwin, the worker credential delivery takes its group from `lib.head (groupsFor worker)` (`modules/darwin/omnigent-host.nix:44-57`), and `groupsFor` returns group names in sorted order, so adding `omnigent-cameron` to `_ghq` would make `_ghq` the group of its delivered credentials, readable by `crs58` → Mitigation: task 8.1 changes that selection to the worker's own primary group in the same commit that adds the membership, and verifies the delivery group by evaluation.
- [Risk] The writer becomes an attack surface for request injection → Mitigation: a fixed action set, target and path validation, no shell, a protocol allow-list, peer identity checked against the writer's group, and D8 assertions that inject each refused form.
- [Risk] Upstream content is attacker-controlled → Accepted: the writer clones without submodules by default and has no credentials; nothing about content trust is claimed.
- [Risk] Between activation and migration a participant's `ghq.root` names an empty shared root → Mitigation: migrate each host directly after its activation; the old tree is untouched until then.
- [Risk] A moved worker tree carries worker-written content into a tree humans read → Mitigation: D10's configuration and hook sanitisation removes the repository-local settings git executes; working-tree files themselves execute nothing without a separate approval such as direnv's.
- [Risk] Magnetite's shared tree competes with `/` for pool headroom and multiplies snapshot churn → Mitigation: measure after migration; a dedicated dataset with auto-snapshot disabled is the follow-up if needed.
- [Trade-off] Readers' `git status` reports from a stale index and readers cannot `git fetch` → accepted for reference reading.
- [Trade-off] Stibnite's obligations and runtime facts are outside CI → accepted, matching the existing stibnite posture; D9 records the inspection.
- [Risk] Several active changes replace the `Grounded vocabulary for behavioral requirements` requirement in full → Mitigation: rebase this change's table onto whichever version is in the corpus at archive time.

## Migration Plan

1. Land and verify, by evaluation and build only, tasks groups 1–7 (Linux, Home Manager, delegation, checks, migration tool, documentation); activate nothing.
2. Run D8 on pyrite's builder.
3. After the `_ghq` UID/GID is approved, land and verify group 8 (darwin).
4. Per host (pyrite, then magnetite, then stibnite), as human-gated steps: activate; run `ghq-shared-migrate` as a dry run and present its dirty and local-only list; run it with `--apply`; run D9's smoke as each account; on failure run `--rollback` for the affected account.
5. Delete each set-aside or pre-shared copy and each sidecar only on the operator's explicit authorization.

## Delivery

- **Approved by the user 2026-10-17**: the change is activated host by host from the chain-tip commit (pyrite, then magnetite, then stibnite, where the user runs activation), and lands as one pull request for the whole chain after group 9 passes. This is an explicit exception to the fleet's one-pull-request-per-commit practice: the hosts must run the same reviewed revision, and group 9's runtime evidence covers the chain as a whole.

## Gate 1 modality verdicts

This table is the pre-apply spec-and-feature alignment record required by `openspec-bdd-bridge`.
No row routes to a Gherkin scenario, so this change lays out no `.feature` file.
The repository has no BDD runner (no pytest-bdd, cucumber or behave dependency, and no `.feature` file in the tree), so a laid-out scenario would be an unbound surface nothing executes.
Every observable here is either a property of an evaluated configuration, witnessed by `nix eval` and the machine checks, or a property of a running system, witnessed by the executed NixOS test and by post-activation smoke on each host.
A `world`-stratum requirement is witnessed by its own violation condition; an `interface`-stratum requirement is witnessed at the machine boundary.

| Requirement | Capability | Stratum | Modality | Witness |
|---|---|---|---|---|
| Every participating account reads one reference tree per host | `shared-reference-tree` | behavioral | executed NixOS test and smoke (deployment) | tasks 5.2, 9.1–9.3 |
| Only the writer changes the reference tree | `shared-reference-tree` | behavioral | executed NixOS test and smoke (deployment) | tasks 5.2, 9.1–9.3 |
| A missing reference repository can be requested without a person | `shared-reference-tree` | behavioral | executed NixOS test and smoke (deployment) | tasks 5.2, 9.1–9.3 |
| Only participating accounts can read the reference tree | `shared-reference-tree` | behavioral | executed NixOS test and smoke (deployment) | tasks 5.2, 9.1–9.3 |
| Sharing the reference tree leaves every private home private | `shared-reference-tree` | behavioral | build gate (existing worker obligations) and executed NixOS test | tasks 1.2, 5.2 |
| Moving per-account copies into the reference tree loses nothing and is reversible | `shared-reference-tree` | behavioral | executed NixOS test and smoke (deployment) | tasks 6.1, 9.1–9.3 |
| Sharing hosts are declared, and only they change | `shared-reference-tree-interface` | interface | build gate (`nix eval`) | tasks 1.1, 10.2 |
| The shared root is owned by the writer and closed to everyone else | `shared-reference-tree-interface` | interface | build gate (assertions) and executed NixOS test | tasks 5.1, 5.2, 8.5 |
| Each participating account resolves the shared root | `shared-reference-tree-interface` | interface | build gate (`nix eval`) and executed NixOS test | tasks 3.2, 5.2, 8.3 |
| Readers trust the writer's tree and nothing broader | `shared-reference-tree-interface` | interface | build gate (assertions) and executed NixOS test | tasks 5.1, 5.2 |
| Acquisition is delegated to the writer through a socket-activated entry point | `shared-reference-tree-interface` | interface | handler build-time test and executed NixOS test | tasks 4.1, 5.2 |
| The writer accepts only constrained requests | `shared-reference-tree-interface` | interface | handler build-time test and executed NixOS test | tasks 4.1, 5.2 |
| Migration moves trees, sanitises repository-local configuration, and can be rolled back | `shared-reference-tree-interface` | interface | executed NixOS test and dry run on stibnite | task 6.1 |
| Each property is backed by evidence that can fail | `shared-reference-tree-interface` | interface | negative controls and mutations recorded per task | tasks 5.1, 5.2 |
| This capability states its own trust boundary | `shared-reference-tree-interface` | interface | capability text and documentation | specs text, tasks 7.1 |
| A34 — git runs repository-local programs as the invoking account | `world-assumptions` | world | violation-condition witness | its own scenario |
| A35 — ghq's root resolution | `world-assumptions` | world | violation-condition witness | its own scenario |
| Grounded vocabulary for behavioral requirements | `world-assumptions` | world | designation table and its lint | the table itself |

No row carries an `est-property`, `est-contract`, or `est-symbolic` modality, so this change carries no executable-specification-testing obligation and lays out no EST artifact.

## Open Questions

- Whether `vmTests.x86_64-linux.shared-reference-tree` should become merge-gating once a KVM-capable CI builder exists.
