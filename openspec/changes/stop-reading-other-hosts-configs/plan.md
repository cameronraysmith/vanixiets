# Stop reading other hosts' configurations: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** no host configuration evaluates another host's configuration, every vars-tree reader uses one accessor, five vm-tests take magnetite's telemetry databases from flake data, and every drvPath is unchanged. The stibnite saving is measured A/B (tasks.md groups 1–7).

**Architecture:**
- `modules/lib/vars.nix` exports `flake.lib.vars`, the single reading of clan's committed vars layout.
- `modules/lib/host-keys.nix` builds `flake.lib.hostKeys` from it plus `darwinHostKeys`, and adds an own-host assertion to `nixos.base`.
- `ssh-known-hosts` and stibnite read committed files instead of other hosts' configurations.
- The readers elsewhere are rewritten in place, each keeping its read primitive and its path-or-string kind.

**Tech Stack:** flake-parts with import-tree; clan-core vars (`in_repo` public store, clan-core 78d5de23); the NixOS and nix-darwin module systems; `NIX_SHOW_STATS`; the refactor oracle's drvPath dump and diff.

**Spec:** `openspec/changes/stop-reading-other-hosts-configs/`:
- `design.md` (D1–D8);
- `specs/host-configuration-independence{,-interface}/spec.md`;
- `specs/world-assumptions/spec.md` (A320–A323);
- `tasks.md`, `brainstorm.md`, `proposal.md`.

---

## Global Constraints

- One stacked chain, with commits in the order of tasks.md groups 2–6. Each commit evaluates alone. Edits are made in `@` and routed into the chain with `jj squash --into <commit> --keep-emptied <paths>`. Never rebase another session's commits.
- Acceptance is `just drv-diff <parent> <tip> openspec/changes/stop-reading-other-hosts-configs/drv-delta.txt` (task 7.1), run after rebasing onto the tip of `establish-refactor-oracle`, which this change lands directly after. Outside the oracle's base allow-list, only `checks.x86_64-linux.host-key-obligations` (added) and `checks.x86_64-linux.fleet-alert` (changed, by the new size entry) may differ. A site whose drvPath moves is reverted to its previous path-or-string kind, never accepted as a Δ.
- `just eval-identity` is not this change's oracle: it compares stock nix with iets at one revision.
- Evaluations of x86_64-linux outputs use magnetite's store (`--eval-store auto --store ssh-ng://magnetite.zt`). The stibnite measurements (task 7.2) run on stibnite itself. No system closure is built.
- The run expected to exceed 5 minutes (task 7.1) is announced first with tasks.md's notice (duration, what it proves that a cheaper run cannot, what waits on it), and does not start until that notice has been given.
- Every regulator is seen failing on its mutant before it is trusted (tasks 4.2, 4.4, 5.4, 6.2), each in a throwaway tree that is never committed.
- Files outside this change's list are not touched, in particular `checks/sops-correspondence.nix`, the fixtures of `checks/fleet-deployer-obligations.nix`, `home/ai/omnigent/credentials.nix`, `checks/omnigent-workers.nix`, `checks/machines.nix` and every `_module.args.flake` setter line.

## Grounding: the vendored interfaces

- clan-core `nixosModules/clanCore/vars/public/in_repo.nix:14-21`: `flakePath = settings.directory + "/vars/${rel_dir}/${name}/value"`; `value = readFile flakePath` (untrimmed) when `exists`; `exists = pathExists flakePath`.
- clan-core `clanServices/sshd/default.nix:41-51`: generator `openssh`, files `ssh.id_ed25519` (secret) and `ssh.id_ed25519.pub` (`secret = false`), no `share`, `ssh-keygen -t ed25519 -N "" -C ""`. The empty comment is why each value ends in `" \n"` (`logs/cross-host-eval-cost-c-20261126-174313.log`).
- Re-read both files at the locked revision before task 2.1, from the flake input's source (`nix flake metadata --json | jq -r '.locks.nodes["clan-core"].locked.rev'` must be `78d5de23…`). Two clan-core source trees are present in the local store, and this plan's citations were read from one whose `in_repo.nix` is identical in both.
- `NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=<file>` writes `cpuTime`, `nrThunks` and `gc.totalBytes` (the fields the 2026-11-26 baseline used).

## Interface contract

| Kind | Name | Defined in |
|---|---|---|
| Lib | `flake.lib.vars.relPath : { generator; file; machine ? null } -> str` | Task 2 |
| Lib | `flake.lib.vars.path : args -> path` (repository root `../..` from `modules/lib`) | Task 2 |
| Lib | `flake.lib.vars.public : args -> str` (untrimmed `readFile (path args + "/value")`) | Task 2 |
| Lib | `flake.lib.vars.exists : args // { secret ? true } -> bool` | Task 2 |
| Lib | `flake.lib.vars.isRecipient : args -> { machine ? null; group ? null; user ? null } -> bool` | Task 2 |
| Lib | `flake.lib.hostKeys : attrsOf str` (six NixOS names via `vars.public`, plus `darwinHostKeys`) | Task 4 |
| Lib | `flake.lib.hostKeyObligations.failures : name -> hostConfig -> [ str ]` | Task 4 |
| Module | `flake.modules.nixos.base.imports = [ hostKeyAssertions ]` | Task 4 |
| Check | `checks.x86_64-linux.host-key-obligations`, `testSizes.checks.host-key-obligations.class = "small"` | Task 4 |

---

## Task 1: Baseline (tasks.md 1.1–1.3)

- [ ] **Step 1:** Confirm the operator's answers to design Open Questions 1 and 2 are recorded. If either is yes, stop: the added tasks are written into tasks.md before Task 2 starts.
- [ ] **Step 2:** Note the parent revision: `jj log -r @- --no-graph -T 'commit_id.short()'`. Record it in `logs/srohc-1-parent-<ts>.txt`.
- [ ] **Step 3:** Record, in one `nix eval --json` process at the parent revision, the drvPaths listed in tasks.md 1.2 into `logs/srohc-1-drv-before-<ts>.json`.
- [ ] **Step 4:** Record the before values:
  ```sh
  nix eval --json .#darwinConfigurations.stibnite.config.programs.ssh.knownHosts > logs/srohc-1-kh-stibnite-<ts>.json
  nix eval --json .#nixosConfigurations.cinnabar.config.programs.ssh.knownHosts > logs/srohc-1-kh-cinnabar-<ts>.json
  nix eval --json .#darwinConfigurations.stibnite.config.services.stibnite-session-host.keys > logs/srohc-1-session-<ts>.json
  nix eval --json .#lib.meshHostFiles > logs/srohc-1-mesh-<ts>.json
  ```
  Also record the local secret paths for magnetite. Find the attribute that exposes `localSecretsOf` by reading `modules/lib/fleet-deployer.nix`'s `flake.lib.fleetDeployer` export, and evaluate it at the parent revision.
- [ ] **Step 5:** Check that `jq -r '."magnetite.zt".publicKey' logs/srohc-1-kh-stibnite-*.json | od -c | tail -2` shows `   \n`.

## Task 2: The accessor (tasks.md 2.1–2.2)

**Files:** create `modules/lib/vars.nix`; modify `modules/lib/fleet-deployer.nix`.

- [ ] **Step 1:** Write `modules/lib/vars.nix`:
  ```nix
  # flake.lib.vars: the one reading of clan's committed vars layout
  # (clan-core in_repo public store; world assumption A320). A public file's
  # value is the untrimmed contents of <relPath>/value; a secret's encrypted
  # contents are <relPath>/secret, its recipients <relPath>/{machines,users,groups}/<n>.
  # `path` returns a path value so that interpolating it copies one file, as
  # the path literals it replaces did. Exempt, deliberately: the judge in
  # checks/sops-correspondence.nix, the literal fixtures of
  # checks/fleet-deployer-obligations.nix, home/ai/omnigent/credentials.nix
  # (clan's rel_dir) and checks/langfuse-query.nix.
  { lib, ... }:
  let
    relPath =
      { generator, file, machine ? null }:
      if machine == null then
        "vars/shared/${generator}/${file}"
      else
        "vars/per-machine/${machine}/${generator}/${file}";
    path = args: ../.. + "/${relPath args}";
    public = args: builtins.readFile (path args + "/value");
    exists =
      { secret ? true, ... }@args:
      builtins.pathExists (path (removeAttrs args [ "secret" ]) + (if secret then "/secret" else "/value"));
    isRecipient =
      args:
      { machine ? null, group ? null, user ? null }:
      let
        sub = lib.findFirst (s: s.v != null) (throw "vars.isRecipient: name one of machine, group, user") [
          { k = "machines"; v = machine; }
          { k = "groups"; v = group; }
          { k = "users"; v = user; }
        ];
      in
      builtins.pathExists (path args + "/${sub.k}/${sub.v}");
  in
  {
    flake.lib.vars = { inherit relPath path public exists isRecipient; };
  }
  ```
  `isRecipient` must refuse more than one non-null name. Add an assert that counts the non-null names equal 1.
- [ ] **Step 2:** `nix eval .#lib.vars.relPath --apply 'f: [ (f { generator = "langfuse"; file = "secret-key"; }) (f { machine = "cinnabar"; generator = "caddy-root-ca"; file = "root.crt"; }) ]'`. Expect `[ "vars/shared/langfuse/secret-key" "vars/per-machine/cinnabar/caddy-root-ca/root.crt" ]`.
- [ ] **Step 3:** In `fleet-deployer.nix`:
  - replace `varPath` (`:305-310`) with `varPath = generator: file: vars.relPath { inherit generator file; machine = if generators.${generator}.share then null else name; };`;
  - replace `requestKeyFile`/`requestKeyOf` (`:99-105`) with `vars.exists { generator = "omnigent-${owner}-deploy-request"; file = "key.pub"; secret = false; }` and `lib.trim (vars.public { … })`.

  Bind `vars` from `config.flake.lib.vars` at the file's top `let`. Do not shadow the module's `config`.
- [ ] **Step 4:** Re-evaluate the deployer values from Task 1 Step 4 and diff them. Expect no difference.
- [ ] **Step 5:** Commit: "Read the committed vars tree through flake.lib.vars". The body cites `in_repo.nix:14-21` and says `fleet-deployer`'s paths are unchanged.

## Task 3: Migrate the readers (tasks.md 3.1–3.4)

**Files:** modify the sites of design D5's table.

- [ ] **Step 1:** Path-literal sites. In modules whose outer function has flake-parts `config`, bind `vars = config.flake.lib.vars` in an outer `let` before the inner module shadows `config`. Then:
  - `fleet-services-trust.nix:8`: `caddyCert = vars.path { machine = "cinnabar"; generator = "caddy-root-ca"; file = "root.crt"; } + "/value";`
  - `workstation-ca-trust.nix:10`: the same expression in the list.
  - `crs58/default.nix:94`: `file = "${vars.path { … } + "/value"}";`
  - `home/users/lib.nix:101-104`: `lib.fileContents (flakeLib.vars.path { generator = flakeLib.commitSigningGenerator (flakeLib.signingPerson name); file = "key.pub"; } + "/value")`. Keep `defaultText`.
  - `commit-signing.nix:166`: `dir = vars.path { generator = commitSigningGenerator person; file = "key"; } + "/machines";`
- [ ] **Step 2:** Evaluate the drvPaths named in tasks.md 3.1 and compare them with the before dump. If one moved, revert that site to its literal and record why in design D5.
- [ ] **Step 3:** String sites:
  - `tincr.nix:36`: `peerKey = name: vars.public { machine = name; generator = "tincr-${mesh.instance}"; file = "ed25519_key.pub"; };`
  - the two otel checks: `ztAddress = lib.trim (self.lib.vars.public { generator = "zerotier-ip-magnetite-zerotier"; file = "ip"; });`
  - `otel-collector-agent.nix:451`: `builtins.hashFile "sha256" (vars.path { generator = "langfuse"; file = "secret-key"; } + "/secret")`.
- [ ] **Step 4:** Existence and recipient sites:
  - `postgresql-backup.nix`: drop `varsDir`, and use `vars.exists { machine = name; generator = generators.r2; file = "env"; } && vars.exists { machine = name; generator = generators.restic; file = "password"; }`.
  - `r2-usage.nix`: drop `varsDir`, and use `vars.exists { machine = name; inherit generator; file = "token"; }`.
  - `shared-vars-recipients.nix:45`: `isRecipient = gen: file: self.lib.vars.isRecipient { generator = gen; inherit file; } { machine = name; };`
- [ ] **Step 5:** Run the evaluations named in tasks.md 3.2 and 3.3, and compare them with the before values.
- [ ] **Step 6:** `rg -n 'vars/(per-machine|shared)' modules > logs/srohc-3-search-<ts>.log`. Annotate each hit as exempt, runtime path, comment or documentation.
- [ ] **Step 7:** Commit: "Migrate the vars-tree readers to flake.lib.vars".

## Task 4: Host keys and the obligation (tasks.md 4.1–4.4)

**Files:** create `modules/lib/host-keys.nix` and `modules/checks/host-key-obligations.nix`; modify the header of `modules/lib/darwin-host-keys.nix`.

- [ ] **Step 1:** Write `modules/lib/host-keys.nix`:
  ```nix
  # flake.lib.hostKeys: every fleet host's pinned SSH host key. The NixOS keys
  # are the committed public files of clan's sshd `openssh` generator, read
  # untrimmed exactly as clan's `.value` (A320, A321); the darwin keys are
  # flake.lib.darwinHostKeys. Each NixOS host asserts that its own generated
  # key equals its entry, so a regenerated but uncommitted key fails that
  # host's build. No host's configuration is read from another.
  { config, lib, ... }:
  let
    inherit (config.flake.lib) vars darwinHostKeys;
    nixosKeyHosts = [ "cinnabar" "electrum" "galena" "scheelite" "magnetite" "pyrite" ];
    hostKeys =
      lib.genAttrs nixosKeyHosts (machine: vars.public { inherit machine; generator = "openssh"; file = "ssh.id_ed25519.pub"; })
      // darwinHostKeys;
    hostKeyObligations.failures =
      name: hostConfig:
      let
        generated = hostConfig.clan.core.vars.generators.openssh.files."ssh.id_ed25519.pub".value or null;
      in
      lib.optional (hostKeys ? ${name} && (hostConfig.clan.core.vars.generators or { }) ? openssh && generated != hostKeys.${name})
        "${name}'s generated openssh public key is not flake.lib.hostKeys.${name}; commit vars/per-machine/${name}/openssh";
    assertionsModule =
      { config, ... }:
      {
        assertions = map (message: { assertion = false; inherit message; }) (
          hostKeyObligations.failures config.clan.core.settings.machine.name config
        );
      };
  in
  {
    flake.lib = { inherit hostKeys hostKeyObligations; };
    flake.modules.nixos.base.imports = [ assertionsModule ];
  }
  ```
- [ ] **Step 2:** `nix eval --json .#lib.hostKeys --apply builtins.attrNames` gives ten names. `nix eval --raw .#lib.hostKeys.magnetite | od -c | tail -2` ends in `   \n`.
- [ ] **Step 3:** Write the judge check in the house form of `checks/shared-vars-obligations.nix`. It calls `self.lib.hostKeyObligations.failures` over literal `hostConfig` fixtures with a fixture name from `hostKeys`:
  - accepted (0 failures);
  - one character off (1);
  - trimmed (1);
  - a name not in `hostKeys` (0);
  - no `openssh` generator (0).

  On a misjudged case it fails with `lib.assertMsg`. Gate it on `system == "x86_64-linux"`, and declare `testSizes.checks.host-key-obligations.class = "small"`.
- [ ] **Step 4:** Build the check. Then, in a throwaway tree, make `failures` return `[ ]` and see the check fail. Log both runs.
- [ ] **Step 5:** List the `nixos.base` importers outside `nixosConfigurations` (`rg -n 'modules.nixos.base' modules/vm-tests modules/checks`) with their machine names, and log them.
- [ ] **Step 6:** Run the mutant: in a throwaway tree, add `clan.core.vars.generators.openssh.files."ssh.id_ed25519.pub".value = lib.mkForce "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";` to cinnabar. Evaluate cinnabar's toplevel drvPath and expect the assertion. Log it.
- [ ] **Step 7:** Commit: "Pin fleet host keys from the committed vars and assert each NixOS host's own key".

## Task 5: Remove the cross-host reads (tasks.md 5.1–5.4)

**Files:** modify `modules/system/ssh-known-hosts.nix`, `modules/machines/darwin/stibnite/default.nix`, and the comments above `_module.args.flake` in the six NixOS host modules.

- [ ] **Step 1:** In `ssh-known-hosts.nix`:
  - make `mkKnownHosts` a plain attrset reading `hostKeys.<h>` for the ten fleet hosts, keeping `hostNames` and the pixel7 entry byte for byte;
  - set both modules to `programs.ssh.knownHosts = knownHosts;` with no module arguments;
  - rewrite the header's "Dynamic keys" line to name `flake.lib.hostKeys`.
- [ ] **Step 2:** Compare the `knownHosts` JSON for stibnite and cinnabar with the Task 1 files: `diff <(nix eval --json …) logs/srohc-1-kh-stibnite-*.json`. Expect no difference.
- [ ] **Step 3:** In stibnite, set `keys = [ (config.flake.lib.vars.public { machine = "magnetite"; generator = "stibnite-agent-session"; file = "key.pub"; }) ];`. Use the outer flake-parts `config`, bound before the inner module. Reword `:166-170` to say the key is read from the committed file and that `checks.x86_64-linux.nix-builders-wiring` holds it to magnetite's generator.
- [ ] **Step 4:** Compare `services.stibnite-session-host.keys` with the Task 1 file, and build `checks.x86_64-linux.nix-builders-wiring`.
- [ ] **Step 5:** Replace "Make flake available to all modules (required by ssh-known-hosts)" in the six NixOS host modules with a comment that names no reader the change removed, for example "Ambient flake argument; its removal is tracked with the poisoned-flake guard in checks/omnigent-workers.nix". Leave the setter lines unchanged.
- [ ] **Step 6:** `rg -n 'nixosConfigurations\.|darwinConfigurations\.' modules/system modules/nixos modules/darwin modules/home modules/clan modules/machines > logs/srohc-5-search-<ts>.log`. Expect comments only. Repeat the search in the throwaway tree with the stibnite line restored, and expect exactly that hit.
- [ ] **Step 7:** Commit: "Read fleet host keys and stibnite's session key from committed vars, not other hosts".

## Task 6: Telemetry databases in the vm-tests (tasks.md 6.1–6.2)

**Files:** modify `modules/vm-tests/{greptimedb-pipeline,fleet-ingress,devloop-ingest,greptimedb-oom-order,perses-greptimedb}.nix`.

- [ ] **Step 1:** In each test, replace `inherit (reference.services.greptimedb) databases;` (or the inner `inherit` at `greptimedb-oom-order.nix:113`) with `inherit (self.lib.otelCollectorSchema) databases;` at the test's `let`. Wrap the test value in `assert lib.assertMsg (reference.services.greptimedb.databases == databases) "<test>: magnetite does not declare flake.lib.otelCollectorSchema.databases";`.
- [ ] **Step 2:** Reword `greptimedb-pipeline.nix:72-74`: the databases are flake data, and the assertion keeps magnetite from drifting past the test.
- [ ] **Step 3:** For each test, `nix eval --raw .#vmTests.x86_64-linux.<t>.driver.drvPath` must equal the parent revision's value. This is evaluation only and runs no test.
- [ ] **Step 4:** Run the mutant: in a throwaway tree, add `services.greptimedb.databases.fleet = lib.mkForce "1d";` to magnetite and evaluate each test's driver drvPath. Expect seven failures, each with its file's message.
- [ ] **Step 5:** Commit: "Take magnetite's telemetry databases from flake data in vm-tests".

## Task 7: Integration verification (tasks.md 7.1–7.5)

- [ ] **Step 1:** Give the notice for task 7.1, then run `just drv-diff <parent> <tip> openspec/changes/stop-reading-other-hosts-configs/drv-delta.txt`. Expect exit 0 and, outside the base allow-list, exactly `checks.x86_64-linux.host-key-obligations` added and `checks.x86_64-linux.fleet-alert` changed; no `vmTests` difference.
- [ ] **Step 2:** On stibnite, run the A/B/A/B measurement, with a fresh process and a separate stats file per run:
  ```sh
  for rev in A B A B; do
    src=$([ $rev = A ] && echo "<parent-worktree>" || echo "<tip-worktree>")
    NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=logs/srohc-7-stats-stibnite-$rev-$(date +%s).json \
      nix eval --raw "$src#darwinConfigurations.stibnite.config.system.build.toplevel.drvPath"
  done
  ```
  Repeat for `nixosConfigurations.cinnabar`. Tabulate `cpuTime`, `nrThunks` and `gc.totalBytes` against A323.
- [ ] **Step 3:** Build `host-key-obligations`, `shared-vars-obligations` and `fleet-deployer-obligations`, and evaluate the machine checks.
- [ ] **Step 4:** Update AP's O18 entry and the ADR-0020 citation, unless the refactor-oracle change has already done so. Run `prek run --files` on them.
- [ ] **Step 5:** `rg -n 'flake \? nixosConfigurations' modules` returns nothing.
