# Seam secrets away from clan vars implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** every first-party module declares and reads secrets through one option, `vanixiets.secrets.<name>`, and homes through a host-provided view, so that clan vars is named only in `modules/system/secrets.nix` (with `modules/lib/vars.nix` for the committed layout) and in the named judges that run a generator's recipe. This covers tasks.md groups 1–15.

**Architecture:** `modules/system/secrets.nix` declares the option on the NixOS and nix-darwin classes, translates each non-provided entry into `clan.core.vars.generators.<name>` with only its defined fields when clan-core is present, reads clan's paths back into read-only fields, exposes the backend's whole tree to two obligations through `flake.lib.secretsBackend.generatorsOf`, and declares the home option. `nixos/hm-sops-bridge.nix` (and a new darwin export in the same file) sets each home's view. Thirteen delivery steps move closed sets of secrets, each proven by its own drvPath diff; a structural check confines the backend and shrinks with every step.

**Tech Stack:** flake-parts with import-tree; the nixpkgs module system (`types.submodule`, `nullOr`, `readOnly`); clan-core's vars interface (`clan.core.vars.generators`) and its sops backend; sops-nix (`sops.placeholder`); home-manager's NixOS and nix-darwin modules (`home-manager.sharedModules`, `home-manager.users`); `flake.lib.mkStructuralCheck`; `just drv-diff` and `just drv-diff-rejudge`.

**Spec:** `openspec/changes/seam-secrets-away-from-clan-vars/`: `design.md` (D1–D12, the pre-apply alignment table), `specs/secret-consumption-seam`, `specs/secret-consumption-seam-interface`, `specs/world-assumptions` (A360–A364), `tasks.md`, `drv-delta/*.txt`, `brainstorm.md`, `proposal.md`.

---

## Global Constraints

- Lands after compose-hosts-from-cohesive-aspects (the prerequisite section below names its two remaining commits). Before step 1, and before each step whose files that change moved, re-read the sections design.md's Migration Plan item 1 lists and update the file names in this plan and in tasks.md. Line numbers below are at `main` `0f98c236fefd` (2026-11-27), where every cited file is identical to the working copy, and will move.
- Thirteen delivery steps, each one commit in one pull request, rebased onto the previous step's merge. Edits are made in `@` and routed into the step's commit with `jj squash --into <step> --use-destination-message --keep-emptied <paths>`. This repository is a shared jj development join: never `jj new`, `describe` or `commit` on another session's chain.
- Each step is accepted on one full `just drv-diff <parent> <step commit> openspec/changes/seam-secrets-away-from-clan-vars/drv-delta/<step>.txt` (about 16 minutes). The implementer does not run it: the step's last task returns the exact command. If the diff names an undeclared check, trace it with `nix derivation show`, declare it with its cause, and re-judge with `just drv-diff-rejudge <dir> <allow>`; an undeclared NixOS, darwin or home toplevel or vmTests difference blocks the step.
- Known drvPath movers in this repository: `checks.x86_64-linux.fleet-alert` changes whenever a `testSizes.checks` entry is added (step 1 adds two); every check that builds or consumes `packages.vanixiets-docs` changes whenever a file under `packages/docs/` changes (only step 13 may edit documents); a test importing `${./x.nix}` changes when `x.nix` changes (design D12 lists those files; the one edited here is `home/users/lib.nix`, in step 10, which moves `checks.x86_64-linux.eval-users-lib`); a new check is declared `class = "medium"; measured = false;`.
- Every new or edited file passes `treefmt` before its commit is published.
- Within a step, evidence is by evaluation against task 1.2's baseline projections; mutants run in a throwaway tree (`jj workspace add` under `/tmp`, or a `git worktree`), never in `@`, and each evaluates only the expression it must fail.
- A step moves every definition of a generator together, in its original order (A363), and every reader of the secrets it covers. The first task of each step is the closed-set search that proves it.

## Prerequisite: the remaining commits of compose-hosts-from-cohesive-aspects

Step 1's parent is the merge of compose-hosts-from-cohesive-aspects' last commit. At `main` `0f98c236fefd` two of its commits are still to land, and step 1's parent follows both:

- The deletion of `services.shared-reference-tree.enable` (its task 6.1, the one flag of its D6 left). It edits `modules/darwin/omnigent-host.nix:157`, the flag's reader, which step 9 here also edits; `modules/{system,nixos,darwin}/shared-reference-tree.nix`; `modules/vm-tests/shared-reference-tree.nix`; and the three hosts that set `enable = true`: `modules/machines/darwin/stibnite/default.nix:26`, `modules/machines/nixos/magnetite/default.nix:74` and `modules/machines/nixos/pyrite/default.nix:88`. It waits for hydrate-reference-copy-history to release the shared-reference-tree files.
- Stibnite joining the `darwin-workstation` aspect (its task 4.4; `modules/darwin/darwin-workstation.nix` exists, and argentum, blackphos and rosegold already import it). It edits `modules/machines/darwin/stibnite/default.nix`.

Neither pull request 1 nor pull request 2 edits `modules/darwin/omnigent-host.nix` or `modules/machines/darwin/stibnite/default.nix`:

- Pull request 1 (step 1) edits `modules/system/secrets.nix` (new), `modules/nixos/hm-sops-bridge.nix`, `modules/home/mk-home.nix`, `modules/checks/secrets-seam-{translation,confinement}.nix` (new), and the `hm-sops-bridge` import lines of `modules/machines/nixos/{cinnabar,electrum,galena,magnetite,pyrite,scheelite}/default.nix` (`:41`, `:28`, `:27`, `:40`, `:78`, `:30`). Magnetite's and pyrite's `default.nix` are also edited by the flag deletion, at other lines.
- Pull request 2 (step 2) edits `modules/nixos/{niks3,nixbot}.nix`, `modules/effects/{vanixiets,ironstar}/secrets.nix` and `modules/checks/secrets-seam-confinement.nix`.

## Other unarchived changes that edit this change's files

Found by searching each unarchived change's `tasks.md` and `proposal.md` for the files this change edits; a change is listed when it has an open task naming the file, or when design.md or the prerequisite above names it.

| Change | File | This change's step | State of that change's work on the file |
|---|---|---|---|
| filter-check-sources-for-substitution | `modules/nixos/hm-sops-bridge.nix` | 1 | Task 4.2 (replace the `inputs.self + "/secrets/bridge/…"` path with `../../secrets/bridge + …`) is unticked; `main` already reads `../../secrets/bridge/${userCfg.sopsIdentity}-age-key.enc` (`:89,126`). Its task 6.3 scope check lists the file. |
| evaluate-nixbot-with-iets | `modules/nixos/nixbot.nix` | 2 | Its edits to the file (tasks 1.1, 1.4, 5.2) are ticked and on `main`. Open task 6.3, an operator capacity decision, may tune `evalWorkerCount` or `evalMaxMemorySize` there. |
| back-up-postgresql-off-host | `modules/nixos/postgresql-backup.nix` (and magnetite's `default.nix`) | 8 (1 and 7 for `default.nix`) | No task is ticked, but the file edits of tasks 1.1, 1.4, 4.4 and 5.3 are on `main` (`flake.lib.postgresqlBackup`, the module imported from `nixos.base` at `:415`, `awaitingSecrets = [ ]` at `:67`, magnetite's `vanixiets.postgresqlBackup.enable = true` at `default.nix:197`, the rerun note at `:44-45`); its open work is operator and verification tasks. |
| stand-up-gitea-mq-on-magnetite | `modules/machines/nixos/magnetite/default.nix`, `modules/nixos/gitea-mq.nix` | 1 and 7; 6 | Tasks 3.1, 4.2, 4.3 and 5.1 are unticked, but their edits are on `main` (the two generators in `gitea-mq.nix`, `batchMax`, `skipQueueIfUpToDate`, `requiredChecks` and the assertions; the module import at `default.nix:33` and `gitea-mq` in the aspect list at `:49`). Its open work is DNS, deploy and verification. |
| hydrate-reference-copy-history | `modules/darwin/omnigent-host.nix` | 9 | Its proposal lists the file under Code; all 36 of its tasks are ticked, and none names the file. compose-hosts-from-cohesive-aspects holds the flag deletion until it releases the shared-reference-tree files. |
| migrate-mesh-to-tincr | `modules/machines/nixos/cinnabar/zt-dns.nix` | 11 | Open task 12.1 removes the file with the `zerotier` instance; step 11's provided `zerotier-network-zerotier` entry (design D4) goes with it if that task lands first. |
| declarative-cognee-endpoint | `modules/machines/nixos/magnetite/default.nix` | 1 and 7 | Open task 10.1 imports any new `flake.modules.nixos.<svc>` there. |
| bind-mesh-writes-to-their-host, verify-ntfy-before-sending-tokens | `modules/README.md` | 13 | Open tasks 7.2 and 8.3 respectively edit it. |

## Grounding: the vendored consumers' interfaces

- clan-core generator submodule: `modules/clan/export-modules/generic-generator.nix` — generator options `name` `:79`, `validation` `:91`, `files` `:132`, file options `owner` `:149`, `group` `:159`, `mode` `:170`, `neededFor` `:175`, `restartUnits` `:193`, `prompts` `:217` (`description`, `type`, `persist`), `runtimeInputs` `:282`, `script` `:290`, `finalScript` `:304,325`, `share` `:314`; `dependencies` and `deploy` in `nixosModules/clanCore/vars/interface.nix:81-107`. Read on 2026-11-27 from a store copy whose revision was not confirmed; re-read at the locked revision 78d5de23 in task 1.1.
- clan-core `rel_dir`: `nixosModules/clanCore/vars/interface.nix:76-80` (`shared/<gen>` or `per-machine/<machine>/<gen>`). Sops name and path: `nixosModules/clanCore/vars/secret/sops/default.nix:36` (A361).
- clan-core services' own generators: `clanServices/sshd/default.nix:57` (`openssh-ca`), `clanServices/zerotier/default.nix:222` (`zerotier-network-${instanceName}`), sshd's `openssh` (A321, A364).
- Option manuals: nix-darwin `modules/documentation/default.nix:24-45`, home-manager `modules/manual.nix:12-15`, `docs/default.nix:206`; NixOS `documentation.nixos.includeAllModules` unset (A362).

## Interface contract

| Kind | Name | Defined in |
|---|---|---|
| Option (NixOS, darwin) | `vanixiets.secrets.<name>`: writable `share`, `dependencies`, `validation`, `runtimeInputs`, `script`, `prompts.<p>.{description,type,persist}`, `files.<f>.{secret,deploy,owner,group,mode,neededFor,restartUnits}`, `provided` | Task 2 |
| Option (read-only) | `vanixiets.secrets.<name>.files.<f>.{path,value,exists,placeholder}`, `null` without clan | Task 2 |
| Option (home) | `vanixiets.secrets.<name>.files.<f>.{path,placeholder}`, default `{ }` | Task 2 |
| Module | `flake.modules.{nixos,darwin,homeManager}.secrets`; `flake.modules.darwin.hm-sops-bridge` | Task 2 |
| Lib | `flake.lib.secretsBackend.generatorsOf : hostConfig -> attrsOf generator` | Task 2 |
| Check | `checks.x86_64-linux.secrets-seam-translation`, `checks.x86_64-linux.secrets-seam-confinement`, each `medium`, `measured = false` | Task 2 |

## File map

| File | Responsibility | Step |
|---|---|---|
| `modules/system/secrets.nix` (new) | option, translation, read-back, home option, `secretsBackend` | 1 |
| `modules/nixos/hm-sops-bridge.nix` | the home view on both classes | 1 |
| `modules/home/mk-home.nix` | standalone homes import the home option | 1 |
| `modules/machines/nixos/{cinnabar,electrum,galena,magnetite,pyrite,scheelite}/default.nix` | lose their `hm-sops-bridge` import, which `nixos.base` now carries | 1 |
| `modules/checks/secrets-seam-{translation,confinement}.nix` (new) | the two judges | 1; confinement shrinks in 2–13 |
| feature files of design D10's table | declarations and readers | 2–12 |
| `modules/lib/{shared-vars-recipients,fleet-deployer,vars}.nix`, `modules/README.md` | whole-tree obligations, the seam's documentation, `lib/vars.nix`'s exemption list | 13 |

---

## Task 1: Baseline and re-reads (tasks 1.1–1.3)

- [ ] **Step 1:** Confirm compose-hosts-from-cohesive-aspects has landed; record the parent revision in `logs/sscv-1-parent-<ts>.txt`.
- [ ] **Step 2:** Re-read the clan-core files of the Grounding section at the locked revision (`nix flake metadata --json | jq -r '.locks.nodes."clan-core".locked.rev'`, then the store path from `nix flake archive --json` or the lock's `narHash`). Record differences in `logs/sscv-1-rereads-<ts>.md`.
- [ ] **Step 3:** Dump the baseline, one process per class:

```bash
nix eval --json .#nixosConfigurations --apply 'cs: builtins.mapAttrs (_: c: builtins.mapAttrs (_: g: {
  inherit (g) share dependencies;
  finalScript = g.finalScript.drvPath or (toString g.finalScript);
  files = builtins.mapAttrs (_: f: { inherit (f) secret deploy owner group mode neededFor restartUnits path; }) g.files;
}) c.config.clan.core.vars.generators) cs' > logs/sscv-1-nixos-generators-<ts>.json
nix eval --json .#darwinConfigurations --apply '<same lambda>' > logs/sscv-1-darwin-generators-<ts>.json
```

  Then the obligations' `failures` per host, `flake.lib.fleetDeployer`'s local secret paths, and `vcs.signing.keyFile` of every home under every host and of every `homeConfigurations` entry, into `logs/sscv-1-baseline-<ts>.json`.
- [ ] **Step 4:** Build the file list:

```bash
rg -l --glob '*.nix' --glob '!**/_*' --glob '!modules/lib/vars.nix' -e '^\s*([^#\s].*)?clan\.core\.vars' -e '^\s*([^#\s].*)?vars/(shared|per-machine)/' modules | sort > logs/sscv-1-files-<ts>.txt
```

  The optional prefix matters: a pattern requiring a character before `clan.core.vars` misses a line that starts with it, such as `modules/nixos/ntfy-alerter.nix:23`. `modules/lib/vars.nix` is excluded here as the confinement check excludes it (design D9). At `0f98c236fefd` the search returns 66 files. Assign each to a step of design D10 or to design D8's final set; the sorted list is task 2.4's `expected`.

## Task 2: Step 1, the seam with no consumer (tasks 2.1–2.5)

- [ ] **Step 1:** Write `modules/system/secrets.nix`. Shape (names fixed, layout free). Module identity is `vanixiets/<name>`, set through `flake.lib.exportAs` (`modules/lib/export-as.nix`), as `home/terminal/jq.nix` uses it; a module joins a class's `base` through `base.imports`, as `lib/host-keys.nix:58` does:

```nix
{ config, lib, ... }:
let
  flakeConfig = config;
  nullOr = t: lib.mkOption { type = lib.types.nullOr t; default = null; };
  listOf = t: lib.mkOption { type = lib.types.listOf t; default = [ ]; };
  fileModule = { ... }: {
    options = {
      secret = nullOr lib.types.bool; deploy = nullOr lib.types.bool;
      owner = nullOr lib.types.str; group = nullOr lib.types.str; mode = nullOr lib.types.str;
      neededFor = nullOr lib.types.str; restartUnits = listOf lib.types.str;
      path = nullOr lib.types.str // { readOnly = true; };  # and value, exists, placeholder
    };
  };
  # secretModule: share, dependencies, validation, runtimeInputs, script, prompts, files, provided
  prune = lib.filterAttrs (_: v: v != null && v != [ ]);
  toClan = s: prune { inherit (s) share dependencies validation runtimeInputs script; }
    // lib.optionalAttrs (s.prompts != { }) { prompts = lib.mapAttrs (_: prune) s.prompts; }
    // { files = lib.mapAttrs (_: f: prune { inherit (f) secret deploy owner group mode neededFor restartUnits; }) s.files; };
  module = { config, options, lib, ... }: {
    options.vanixiets.secrets = lib.mkOption { type = lib.types.attrsOf (lib.types.submodule secretModule); default = { }; };
    config = lib.optionalAttrs (options ? clan.core.vars) {
      clan.core.vars.generators = lib.mapAttrs (_: toClan) (lib.filterAttrs (_: s: !s.provided) config.vanixiets.secrets);
      # read-only fields: set from config.clan.core.vars.generators.<n>.files.<f> and
      # config.sops.placeholder."vars/${rel_dir}/${f}" through each file submodule's config
    };
  };
  homeModule = { lib, ... }: { options.vanixiets.secrets = /* attrsOf { files.<f>.{path,placeholder} } */ lib.mkOption { default = { }; }; };
  exportSecrets = m: flakeConfig.flake.lib.exportAs { key = "secrets"; names = [ "secrets" ]; module = m; };
  nixos = exportSecrets module;
  darwin = exportSecrets module;
in
{
  flake.modules.nixos = nixos // { base.imports = [ nixos.secrets ]; };
  flake.modules.darwin = darwin // { base.imports = [ darwin.secrets ]; };
  flake.modules.homeManager = exportSecrets homeModule;
  flake.lib.secretsBackend.generatorsOf = hostConfig: hostConfig.clan.core.vars.generators or { };
}
```

  A `nullOr` field must never write a definition; check the `toClan` output with the translation judge before anything else.
- [ ] **Step 2:** Evaluate `vanixiets.secrets` on cinnabar and stibnite; both `{}`.
- [ ] **Step 3:** Edit `nixos/hm-sops-bridge.nix`: a `view` function (entries with a file whose `owner` is the user, projected to `{ files.<f>.{path,placeholder} }`), `home-manager.sharedModules` and `home-manager.users.<u>.vanixiets.secrets` for every `home-manager.users` name, outside `lib.mkIf (cfg.users != { })` (`:83`); a `flake.modules.darwin.hm-sops-bridge` with only those two; both into the class bases; delete the six per-host `hm-sops-bridge` imports (cinnabar `default.nix:41`, electrum `:28`, galena `:27`, magnetite `:40`, pyrite `:78`, scheelite `:30`). Import `homeManager.secrets` in `home/mk-home.nix`.
- [ ] **Step 4:** Evaluate the three views of task 2.2; each `{}`.
- [ ] **Step 5:** Write `modules/checks/secrets-seam-translation.nix` (fixtures of design D11; `lib.evalModules` over `flake.modules.nixos.secrets` plus a stub `options.clan.core.vars.generators = lib.mkOption { type = lib.types.attrsOf (lib.types.submodule { freeformType = lib.types.attrsOf lib.types.anything; }); }`), gated, sized and built as `checks/host-key-obligations.nix` does: `lib.optionalAttrs (system == "x86_64-linux")` (`:59`), the `testSizes.checks` entry (`:60-66`) and the check through `self.lib.mkJudgeCheck` (`:67`). Build it; run the `restartUnits` mutant; record.
- [ ] **Step 6:** Write `modules/checks/secrets-seam-confinement.nix`: `actual` from `lib.filesystem.listFilesRecursive ../.` filtered to `.nix`, no `/_` component, and a non-comment line matching the two patterns (`lib.splitString "\n"` + `builtins.match`); `expected` the literal list from Task 1 Step 4; `flake.lib.mkStructuralCheck`. Build it; run the mutant of task 2.4.
- [ ] **Step 6a:** Measure the import moves (task 2.4a, design D5): the ten toplevel drvPaths and every home's activation drvPath at the parent, with only the secrets module in the base aspects, and with the bridge moved. If the bridge move changes any, put the six per-host `hm-sops-bridge` imports back and keep only the secrets module in the base aspects; declare no host changed.
- [ ] **Step 7:** `treefmt` the new and edited files; squash into step 1's commit; return `just drv-diff <parent> <commit> openspec/changes/seam-secrets-away-from-clan-vars/drv-delta/01-seam.txt`.

## Tasks 3–13: Steps 2–12, one closed set each (task groups 3–13)

The same five moves per step; tasks.md names each step's files, generators and checks.

- [ ] **Step 1 (closed set):** `rg -n -e '<gen1>' -e '<gen2>' … modules` and `rg -n 'mkDefault|mkForce|mkOverride|mkMerge|mkIf'` inside each declaration; save the log; every hit is a file of this step or of design D8's set.
- [ ] **Step 2 (declarations):** in each owning file, replace `clan.core.vars.generators.<name> = { … };` with `vanixiets.secrets.<name> = { … };`, field for field, all definitions of a generator in one edit and in order. A module evaluated without clan elsewhere (fixtures, `vm-tests/postgresql-backup-restore.nix`) adds `imports = [ <class>.secrets ]` and loses its `options ? clan.core.vars` guard.
- [ ] **Step 3 (readers):** replace `config.clan.core.vars.generators.<name>.files.<f>.path` with `config.vanixiets.secrets.<name>.files.<f>.path` (and `.value`, `.exists`); a read guarded by `or null` becomes a test of the read-only field against `null`; an obligation reads `hostConfig.vanixiets.secrets.<name>`.
- [ ] **Step 4 (evidence):** evaluate the step's generators' baseline projection on each host that declares them and diff against Task 1 Step 3; run the step's named check builds and mutants; delete the cleared files from the confinement `expected`; build the confinement check.
- [ ] **Step 5 (deliver):** `treefmt`; squash into the step's commit; return `just drv-diff <parent> <commit> openspec/changes/seam-secrets-away-from-clan-vars/drv-delta/<step>.txt`; after the operator's run, resolve every `may-change` in that file to `changed` or delete it, and re-judge.

Step-specific points:
- Order: steps 2–12 may be reordered, except that step 10 follows step 9 (design D10).
- Step 2 (group 3): the recipe mutant of task 3.4 changes `niks3-api-token`'s script and must move magnetite's toplevel.
- Step 4 (group 5): `ntfy-alerter` has a second definition at `clan/services/otel-collector/service.nix:314` and reads at `:220` and `darwin/otel-collector-agent.nix:319,483`; they move here, in one edit with `nixos/ntfy-alerter.nix:23`, in order.
- Step 7 (group 8): `langfuse` has two definitions in `clan/services/otel-collector/service.nix` (`:232`, `:353`); the six recipe-running judges stay untouched and task 8.5 checks their drvPaths. `checks/obs-query.nix:28` takes the regulator password's path from magnetite's `vanixiets.secrets.greptimedb-users` and still compares it with `apps/obs-query.sh:46`.
- Step 9 (group 10): the credential adapter keeps its assertions but compares `osConfig.vanixiets.secrets.<gen>.files.<f>` (path, placeholder, custody fields) with `osConfig.sops.secrets`; `secretName` disappears with `rel_dir`. Update `lib/vars.nix`'s exemption comment.
- Step 10 (group 11): `vcs-signing.nix` reads `config.vanixiets.secrets.${commitSigningGenerator (signingPerson username)}.files.key.path or null` from the home view, and keeps its machine-name read for the legacy branch; `defaultText` stops naming clan. `home/users/lib.nix:108`'s `defaultText` states the default through `flake.lib.vars.path` as `:101-107` computes it, instead of spelling `vars/shared/`; this moves `checks.x86_64-linux.eval-users-lib`, which step 10's allow-list declares.
- Step 11 (group 12): the `openssh` provided entry, and the `zerotier-network-zerotier` one only while `machines/nixos/cinnabar/zt-dns.nix` exists at the step's parent (design D4); `lib/host-keys.nix:43`'s message builds its path with `flake.lib.vars.relPath` (design D9); the host-key mutant of task 12.6.

## Task 14: Step 13, close (tasks 14.1–14.6)

- [ ] **Step 1:** Replace `hostConfig.clan.core.vars.generators` in `lib/shared-vars-recipients.nix:43` and `lib/fleet-deployer.nix:303` with `self.lib.secretsBackend.generatorsOf hostConfig` (or `config.flake.lib…`, as each file already reaches `flake.lib`), and build `lib/shared-vars-recipients.nix:42`'s message path with `flake.lib.vars.relPath` (design D9); diff the baselines, message text included; build the two obligation checks.
- [ ] **Step 2:** Set the confinement `expected` to the final list (design D8); add `checks/commit-signing-key.nix` to `lib/vars.nix`'s exemption list and name the secrets module as the seam's other half in its header; run the gitea mutant.
- [ ] **Step 3:** Close-out search for guards and fallbacks (task 14.4).
- [ ] **Step 4:** Documents (task 14.5); `prek run --files`.
- [ ] **Step 5:** `treefmt`; squash; return the step 13 drv-diff command.

## Task 15: Integration verification (tasks 15.1–15.3)

- [ ] **Step 1:** Copy every resolved `changed` entry of the step files into `drv-delta/whole-change.txt`; return `just drv-diff <step 1 parent> <step 13 merge> openspec/changes/seam-secrets-away-from-clan-vars/drv-delta/whole-change.txt`.
- [ ] **Step 2:** Re-run Task 1 Step 3's projections at the final merge and diff them; all empty.
- [ ] **Step 3:** Build the confinement check at the final merge and compare its literal with design D8.
