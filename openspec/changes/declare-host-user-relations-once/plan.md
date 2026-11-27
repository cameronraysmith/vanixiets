# Declare host-user relations once implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** one attachment record per (host, account) on `flake.fleet.hosts.<host>.users`, from which the clan user machine lists, the primary user, the darwin admin and uids, the secret bridge, the homes and `checkedUsers` are generated; one home-manager integration aspect per class; no ambient `flake` argument, with worker homes closed over a restricted value and a mutant check; the Omnigent worker relation declared once; `accountOf` beside `personOf`. This covers tasks.md groups 1-9.

**Architecture:** `modules/lib/host-users.nix` re-declares the host submodule with a `users` field and holds the fifteen attachments; `modules/system/home-manager-integration.nix` turns a host's attachments into its home-manager and bridge settings; `modules/lib/fleet-workers.nix` holds the worker relation; `home/ai/omnigent/worker.nix` binds the worker's restricted `flake`. Nothing vendored is patched: clan-core's user and inventory interfaces, home-manager's and nix-darwin's options are used as documented.

**Tech Stack:** flake-parts with import-tree; the nixpkgs module system (`submodule` merging, `readOnly`, `apply`, `_module.args`, `deferredModule`); home-manager's NixOS and nix-darwin modules; clan-core inventory; nix-darwin.

**Spec:** `openspec/changes/declare-host-user-relations-once/`: `design.md` (D1-D12, Pre-apply alignment, Open Questions), `specs/host-user-attachment`, `specs/host-user-attachment-interface`, `specs/world-assumptions` (A340-A348), `tasks.md`, `drv-delta.txt`, `brainstorm.md`, `proposal.md`.

## Global Constraints

- Lands after register-fleet-obligations, whose tip is the parent, and before compose-hosts-from-cohesive-aspects. After any rebase, task 1's baselines are re-recorded.
- One pull request of one commit. Edits are made in `@` and routed into the change's chain with `jj squash --into <chain> --use-destination-message --keep-emptied <paths>`. This is a shared jj development join: never `jj new`, `describe` or `commit` on another session's chain.
- `just drv-diff <parent> <commit> openspec/changes/declare-host-user-relations-once/drv-delta.txt` (about 16 minutes) is the acceptance oracle and runs once over the commit and once at the merged head. The implementer returns the command to the operator; it does not run it. `just eval-identity` is not this oracle.
- No person or account key is renamed. nix-darwin's `system.primaryUser` comes from `admin`, never from `primary`. Worker accounts get no attachment.
- `checks.<system>` names read only static data: the attachments, `flake.users` names, `flake.userAliases` and each user's `systems`. Never `aggregates`, a machine configuration or `pkgs`.
- Literal oracles stay literal: `hostMatrix`, `serverMatrix`, `expectedOwners`, `omnigent-acp-spawn-env`'s host list, `sops-correspondence`'s anchors, `structure-home-configurations`' pin, `operators`.
- The new check is `testSizes.checks.omnigent-worker-scope = { class = "medium"; measured = false; }`.
- Mutants run in a throwaway tree (`jj workspace add` under `/tmp`), never in `@`.
- Every new file passes treefmt before the commit is published.

## Review Focus

- A list option inside an attached home reorders because a definition moved (stibnite's `home.packages`, pyrite's imports). Task 4's home drvPath comparison is the test; the generated entry puts `overrides` first in `imports`.
- A home module outside the six reads `flake` in `imports` (infinite recursion). Task 5 Step 2's multi-line search, then evaluation of every configuration.
- A host-wide `extraSpecialArgs.flake` reappears and silently shadows the worker's value. The aspect's assertion (task 5) and `omnigent-worker-scope`'s `noShadow` case (task 6).
- A real worker home needs a name outside `workerFlake` and fails uncatchably. Task 6 Step 4 evaluates the magnetite, pyrite and stibnite worker homes.
- A runtime-test node imports the integration aspect without a registry entry. The aspect reads `hosts.${hostName}.users or { }` only where the D7 fixture supplies its own table. Task 6's fixture host is the test.

## Grounding: the vendored interfaces

Read at the locked revisions in task 1 Step 4 and cite in `logs/dhuro-1-sources-<ts>.md`:
- home-manager `nixos/common.nix`: `extraSpecialArgs : attrs`, passed to every `home-manager.users.<n>`; `osConfig` passed; `sharedModules`. Not used here: a host's `_module.args`.
- nixpkgs `lib/modules.nix`: special arguments take precedence over `_module.args`; `_module.args` cannot feed `imports`; `collectModules` order (a module, then its imports).
- clan-core `clanServices/users`: `roles.default.machines.<m>`, `settings.{user,groups,share,prompt}`, `extraModules`. Settings apply on NixOS only.
- nix-darwin: `system.primaryUser`; `users.users.<n>.uid` with `users.knownUsers`, and its activation's uid-mismatch refusal.
- flake-parts `mkFlake`: outputs are `config.flake`.

## Interface contract

| Kind | Name | Defined in |
|---|---|---|
| Lib | `flake.lib.accountOf : str -> str`, `flake.lib.personOf : str -> str` (throws on an unknown name); `flake.lib.signingPerson` removed | Task 2 |
| Option | `flake.fleet.hosts.<h>.users.<account>`: `primary : bool`, `admin : bool`, `sopsBridge : bool` (default `class == "nixos"`), `uid : nullOr ints.positive`, `extraImports : listOf deferredModule`, `overrides : deferredModule` | Task 3 |
| Option (read-only) | `flake.fleet.hosts.<h>.primaryUser` from the `primary` attachment | Task 3 |
| Lib | `flake.lib.hostsOfAccount : str -> [str]` (sorted) | Task 3 |
| Module | `flake.modules.{nixos,darwin}.home-manager-integration` | Task 4 |
| Lib | `flake.lib.homeFlake = config.flake // { inherit inputs; }` | Task 5 |
| Module arg | `_module.args.flake`, set only by the integration aspect, `flake.lib.mkHome` and the worker aspect | Tasks 5, 6 |
| Value | `workerFlake` (worker.nix scope): `{ inputs = { llm-agents; contentPrivate = throw …; }; packages; users = throw …; userAliases = throw …; }` | Task 6 |
| Check | `checks.x86_64-linux.omnigent-worker-scope`: cases `positive`, `reachUsers`, `reachContentPrivate`, `allowedNames`, `noShadow` | Task 6 |
| Option | `flake.fleet.workers.<owner>`: `linearLabels : listOf str`, `hosts.<h>.containers : attrs` (default `{ }`) | Task 7 |
| Lib | `flake.lib.workerAccountsOn : str -> [str]` (sorted `omnigent-<owner>`) | Task 7 |

---

### Task 1: Baseline (tasks 1.1-1.6)

**Files:** none in `modules/`; logs only.

- [ ] **Step 1:** Confirm the four prerequisite changes are on the parent (tasks 1.1). Record the parent in `logs/dhuro-1-parent-<ts>.txt`.
- [ ] **Step 2:** Dump task 1.2's projections in one `nix eval --json` process per configuration class, for example:

```bash
nix eval --json .#nixosConfigurations --apply 'cs: builtins.mapAttrs (_: c: {
  homes = builtins.attrNames c.config.home-manager.users;
  bridge = builtins.attrNames (c.config.hm-sops-bridge.users or { });
  homeDrvs = builtins.mapAttrs (_: h: h.home.activationPackage.drvPath) c.config.home-manager.users;
  participants = c.config.services.shared-reference-tree.participants or null;
}) cs' > logs/dhuro-1-nixos-<ts>.json
```

  Do the same for `darwinConfigurations`, adding `system.primaryUser` and `uid` of each human account. Then dump `homeConfigurations` drvPaths, the two options of task 1.2 per home, `lib.hosts` projected to `primaryUser`, the three user instances' machines, the omnigent `roles.host.machines`, `lib.fleetDeployer.requesters` names, and both systems' check names. Announce before starting if this is expected to take more than 5 minutes.
- [ ] **Step 3:** Run task 1.3's per-darwin-host `flake` probe and quote the result under design D5.
- [ ] **Step 4:** Read and cite the grounding sources above, plus a search of the locked inputs' module sources for a `flake` formal (A342).
- [ ] **Step 5:** `just eval-cost checks.x86_64-linux <parent> <parent> 2 keys`, and the same for `checks.aarch64-darwin`.
- [ ] **Step 6:** Stop for the operator's answers to design Open Questions 1-7 (task 1.6).

### Task 2: Vocabulary and the session file (tasks 2.1-2.4)

**Files:** Modify `modules/home/users/aliases.nix`, `modules/home/ai/agent-telemetry.nix:25-43,148`, `modules/lib/commit-signing.nix:5,201-272`, `modules/system/commit-signing-key.nix:14-23`, `modules/home/development/vcs-signing.nix:14,27`, `modules/home/users/lib.nix:103`, `modules/home/ai/omnigent/credentials.nix:143`, `modules/lib/omnigent-fleet-obligations.nix:286`. Rename `modules/system/stibnite-access.nix` → `modules/system/stibnite-session.nix`.

**Interfaces:** Produces `flake.lib.accountOf`, `flake.lib.personOf`.

- [ ] **Step 1:** Write the evaluation probe first and see it fail: `nix eval .#lib.accountOf --apply 'f: f "cameron"'` errors, because the attribute is missing.
- [ ] **Step 2:** Define both functions in `aliases.nix`. `personOf`'s throws: `"personOf: ${name} is the target of several flake.userAliases (…)"` and `"personOf: ${name} is neither a flake.users key nor a flake.userAliases key"`.
- [ ] **Step 3:** Switch the readers and delete `signingPerson` (task 2.2).
- [ ] **Step 4:** Run task 2.1's probe over every key; compare `agentTelemetry.person` and the commit-signing generator names with the baseline; build `eval-users-lib` and `agent-telemetry-emitters`.
- [ ] **Step 5:** Rename the session file, update its header, and build `nix-builders-wiring`.

### Task 3: The attachment field (tasks 3.1-3.5)

**Files:** Create `modules/lib/host-users.nix`. Modify `modules/lib/hosts.nix:77-85` (the `primaryUser` option) and the five `primaryUser =` values.

**Interfaces:** Consumes `config.flake.fleet.hosts.<h>.class`. Produces the attachment option, the read-only `primaryUser`, and `flake.lib.hostsOfAccount`.

- [ ] **Step 1:** Write the projection test as a `nix eval` against the baseline: `primaryUser` per member, and `hostsOfAccount` for cameron, crs58 and tara. It fails until Step 3.
- [ ] **Step 2:** Declare the option. The shape, with field types from the contract table:

```nix
{ config, lib, ... }:
let
  attachment = hostClass: { name, ... }: {
    options = { primary = …; admin = …; sopsBridge = …; uid = …; extraImports = …; overrides = …; };
  };
in
{
  options.flake.fleet.hosts = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule ({ config, ... }: {
      options.users = lib.mkOption { type = lib.types.attrsOf (lib.types.submodule (attachment config.class)); default = { }; };
    }));
  };
}
```

  Put each D2 constraint in the constrained field's `apply`, as `lib.assertMsg … "flake.fleet.hosts.<h>.users.<a>.<field>: …"`, so it throws on read.
- [ ] **Step 3:** Fill the fifteen attachments of task 3.2. Make `primaryUser` `readOnly`, set it from the attachments, and delete its five values.
- [ ] **Step 4:** Run Step 1's test and task 3.4's deployer and `nix-classic` comparisons.
- [ ] **Step 5:** Run the seven mutants of task 3.5 and log them.

### Task 4: The integration aspect and generated consumers (tasks 4.1-4.9)

**Files:** Create `modules/system/home-manager-integration.nix`. Modify `modules/clan/inventory/services/users/{cameron,crs58,tara}.nix`; `modules/darwin/laptop.nix`; `modules/machines/darwin/{argentum,rosegold,stibnite,blackphos}/default.nix`; `modules/machines/nixos/{cinnabar,electrum,galena,scheelite,magnetite,pyrite}/default.nix`; `modules/lib/host-users.nix` (`extraImports`, `overrides`); `modules/home/development/jj-pr-tags.nix:297-305`; `modules/home/users/crs58/default.nix:70-76`; `modules/checks/home.nix:9-66`.

**Interfaces:** Consumes Task 3. Produces `flake.modules.{nixos,darwin}.home-manager-integration`.

- [ ] **Step 1:** Generate the three instances' machine lists (task 4.1) and evaluate them against the baseline.
- [ ] **Step 2:** Write the aspect. For each attachment `a` of `host = hosts.${config.networking.hostName}`:

```nix
home-manager.users.${account} = {
  imports = [ a.overrides ] ++ config'.flake.users.${account}.modules ++ a.extraImports;
};
```

  Add `useGlobalPkgs`, `useUserPackages` and `backupFileExtension`. On NixOS, add `hm-sops-bridge.users`. On darwin, add `system.primaryUser` and `users.users.${account}.uid`. Add the per-attachment `users.users ? account` assertion. Task 5 adds `_module.args.flake` to the entry.
- [ ] **Step 3:** Import the aspect in the ten hosts and delete the hand-written blocks of tasks 4.2 and 4.3. Bind `primaryUser` in `laptop.nix` from the registry.
- [ ] **Step 4:** Move the per-pair settings of task 4.4, and the two flags of task 4.5.
- [ ] **Step 5:** Evaluate the task 4.2, 4.3 and 4.5 projections against the baseline. Run task 4.6's mutant.
- [ ] **Step 6:** Compare every integrated home's drvPath (task 4.7). For any difference, `nix derivation show` both drvPaths, find the reordered list, and adjust the entry's `imports` order.
- [ ] **Step 7:** Generate `checkedUsers` (task 4.8). Compare check names, then re-measure the key-set cost (task 4.9). If the cost moves outside the spread, restore the literal and add the evaluation-time judge on the checks' values.

### Task 5: One flake value, no ambient argument (tasks 5.1-5.6)

**Files:** Modify `modules/system/home-manager-integration.nix`, `modules/home/mk-home.nix:17-20`, `modules/home/base/sops.nix`, `modules/home/core/catppuccin.nix`, `modules/home/shell/tmux.nix`, `modules/home/development/neovim/default.nix`, `modules/home/terminal/{direnv,nix-index}.nix`, `modules/darwin/omnigent-host.nix:107-110`, `modules/vm-tests/{omnigent-worker-isolation,shared-reference-tree}.nix`, and the nine host modules' `_module.args.flake` lines.

**Interfaces:** Produces `flake.lib.homeFlake`. Consumes Task 4's aspect.

- [ ] **Step 1:** Add `flake.lib.homeFlake` and `_module.args.flake = config.flake.lib.homeFlake;` to the aspect's entry and to `mkHome`'s modules. Drop `mkHome`'s `extraSpecialArgs.flake` and keep its `osConfig = null`.
- [ ] **Step 2:** Rewrite the six import sites to read the flake-parts scope (task 5.2). Run the multi-line search.
- [ ] **Step 3:** Delete the remaining `extraSpecialArgs.flake` writers and the nine `_module.args.flake` lines (tasks 5.3, 5.4).
- [ ] **Step 4:** Add the no-specialArg assertion to both aspects and run its mutant (task 5.5).
- [ ] **Step 5:** Re-run Task 4 Step 6's comparison and the `homeConfigurations` drvPath comparison (task 5.6). Record any difference, with its traced cause, for `drv-delta.txt`.

### Task 6: Worker aspect and mutant check (tasks 6.1-6.5)

**Files:** Modify `modules/home/ai/omnigent/worker.nix:1-15`, `modules/darwin/omnigent-host.nix:103-131`, `modules/checks/omnigent-workers.nix:16-35,225-229,928-955` (and add the new check beside `omnigent-worker-capabilities`).

**Interfaces:** Consumes the NixOS integration aspect (for `noShadow`). Produces `workerFlake` and `checks.x86_64-linux.omnigent-worker-scope`.

- [ ] **Step 1:** Write the check first, with its five cases as `lib.assertMsg`s over a `cases` attrset. It follows the `omnigent-worker-capabilities` shape (`failedCases cases == [ ]`, then a `runCommand` writing the case names), and it uses the existing `mkHome` fixture. The literal for `allowedNames` is `[ "inputs" "packages" "userAliases" "users" ]`, with inputs `[ "contentPrivate" "llm-agents" ]`. The `noShadow` probe is a fixture NixOS host, modelled on the `linux` fixture, that imports `home-manager-integration` with one attachment of its own. Its worker home writes `builtins.toJSON (builtins.attrNames flake)` to a `home.file` text.
- [ ] **Step 2:** Build the check. It fails, because the fixtures still pass the poisoned `flake` and the aspect sets nothing.
- [ ] **Step 3:** Bind `workerFlake` in `worker.nix` and set `_module.args.flake` in the aspect. Delete the check-local poison and the fixtures' and darwin builder's `extraSpecialArgs.flake` (tasks 6.1-6.3).
- [ ] **Step 4:** Build `omnigent-worker-scope`, `omnigent-worker-capabilities`, `omnigent-worker-linux` and `omnigent-worker-inventory`. Compare the magnetite, pyrite and stibnite worker homes' drvPaths with the baseline. Run the `users = config.flake.users` mutant.
- [ ] **Step 5:** Register `testSizes.checks.omnigent-worker-scope = { class = "medium"; measured = false; };` in the same file. Hand task 6.5's darwin builds to the operator.

### Task 7: The worker relation (tasks 7.1-7.4)

**Files:** Create `modules/lib/fleet-workers.nix`. Modify `modules/clan/inventory/services/omnigent.nix:57-125`, `modules/lib/fleet-deployer.nix:46-51`, `modules/machines/nixos/magnetite/default.nix:131-138`, `modules/machines/nixos/pyrite/default.nix:87-94`, `modules/machines/darwin/stibnite/default.nix:46-51`.

**Interfaces:** Produces `flake.fleet.workers` and `flake.lib.workerAccountsOn`.

- [ ] **Step 1:** Declare the option and its two owners (task 7.1).
- [ ] **Step 2:** Generate `roles.host.machines`, keeping `roles.server` literal. Diff the JSON against the baseline, then build `omnigent-worker-inventory`.
- [ ] **Step 3:** Derive `requesterNames` and build `fleet-deployer-obligations`.
- [ ] **Step 4:** Derive the participants and compare them, in order, with the baseline. Confirm the four literal oracles are untouched.

### Task 8: Documents and formatting (tasks 8.1-8.3)

- [ ] **Step 1:** Update the READMEs, header comments and principles entries of task 8.1.
- [ ] **Step 2:** Update the four `packages/docs` pages of task 8.2, then build `package-vanixiets-docs-test-linkcheck`.
- [ ] **Step 3:** Run `treefmt --fail-on-change` on the new and edited files, and `prek run --files` on the documents.

### Task 9: Commit, oracle and integration (tasks 9.1-9.6)

- [ ] **Step 1:** Route the change into its chain as one commit, "hosts: declare each host-user relation once". Re-read the docs-consumer list and correct `drv-delta.txt` if it differs.
- [ ] **Step 2:** Return to the operator: `just drv-diff <parent> <commit> openspec/changes/declare-host-user-relations-once/drv-delta.txt`. The run takes about 16 minutes; it alone proves that the host and home configurations are unchanged, and the pull request waits on it.
- [ ] **Step 3:** With the report, resolve every `may-change` entry. Trace any undeclared difference with `nix derivation show`. Either declare it with its cause, or fix it and re-judge with `just drv-diff-rejudge`.
- [ ] **Step 4:** Run tasks 9.2-9.4's projection diffs and searches. Deploy only the hosts the diff declares (task 9.5), and read the fleet alert and failure topics afterwards.
- [ ] **Step 5:** After merge, the operator runs the merged-head diff (task 9.6).
