# Seam secrets away from clan vars implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** every first-party module declares and reads secrets through one option, `vanixiets.secrets.<name>`, and homes through a host-provided view, so that clan vars is named only in `modules/system/secrets.nix` (with `modules/lib/vars.nix` for the committed layout) and in the named judges that run a generator's recipe. This covers tasks.md groups 1–15.

**Architecture:** `modules/system/secrets.nix` declares the option on the NixOS and nix-darwin classes, translates each non-provided entry into `clan.core.vars.generators.<name>` with only its defined fields when clan-core is present, reads clan's paths back into read-only fields, exposes the backend's whole tree to two obligations through `flake.lib.secretsBackend.generatorsOf`, and declares the home option. `nixos/hm-sops-bridge.nix` (and a new darwin export in the same file) sets each home's view. Thirteen delivery steps move closed sets of secrets, each proven by its own drvPath diff; a structural check confines the backend and shrinks with every step.

**Tech Stack:** flake-parts with import-tree; the nixpkgs module system (`types.submodule`, `nullOr`, `readOnly`); clan-core's vars interface (`clan.core.vars.generators`) and its sops backend; sops-nix (`sops.placeholder`); home-manager's NixOS and nix-darwin modules (`home-manager.sharedModules`, `home-manager.users`); `flake.lib.mkStructuralCheck`; `just drv-diff` and `just drv-diff-rejudge`.

**Spec:** `openspec/changes/seam-secrets-away-from-clan-vars/`: `design.md` (D1–D12, the pre-apply alignment table), `specs/secret-consumption-seam`, `specs/secret-consumption-seam-interface`, `specs/world-assumptions` (A360–A364), `tasks.md`, `drv-delta/*.txt`, `brainstorm.md`, `proposal.md`.

---

## Global Constraints

- Lands after compose-hosts-from-cohesive-aspects. Before step 1, and before each step whose files that change moved, re-read the sections design.md's Migration Plan item 1 lists and update the file names in this plan and in tasks.md. Line numbers below are at `main` `9055ae0f1333` and will move.
- Thirteen delivery steps, each one commit in one pull request, rebased onto the previous step's merge. Edits are made in `@` and routed into the step's commit with `jj squash --into <step> --use-destination-message --keep-emptied <paths>`. This repository is a shared jj development join: never `jj new`, `describe` or `commit` on another session's chain.
- Each step is accepted on one full `just drv-diff <parent> <step commit> openspec/changes/seam-secrets-away-from-clan-vars/drv-delta/<step>.txt` (about 16 minutes). The implementer does not run it: the step's last task returns the exact command. If the diff names an undeclared check, trace it with `nix derivation show`, declare it with its cause, and re-judge with `just drv-diff-rejudge <dir> <allow>`; an undeclared NixOS, darwin or home toplevel or vmTests difference blocks the step.
- Known drvPath movers in this repository: `checks.x86_64-linux.fleet-alert` changes whenever a `testSizes.checks` entry is added (step 1 adds two); every check that builds or consumes `packages.vanixiets-docs` changes whenever a file under `packages/docs/` changes (only step 13 may edit documents); a test importing `${./x.nix}` changes when `x.nix` changes (none of the six such files is edited here); a new check is declared `class = "medium"; measured = false;`.
- Every new or edited file passes `treefmt` before its commit is published.
- Within a step, evidence is by evaluation against task 1.2's baseline projections; mutants run in a throwaway tree (`jj workspace add` under `/tmp`, or a `git worktree`), never in `@`, and each evaluates only the expression it must fail.
- A step moves every definition of a generator together, in its original order (A363), and every reader of the secrets it covers. The first task of each step is the closed-set search that proves it.

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
| `modules/checks/secrets-seam-{translation,confinement}.nix` (new) | the two judges | 1; confinement shrinks in 2–13 |
| feature files of design D10's table | declarations and readers | 2–12 |
| `modules/lib/{shared-vars-recipients,fleet-deployer,vars}.nix`, `modules/README.md` | whole-tree obligations, the seam's documentation | 13 |

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
rg -l --glob '*.nix' --glob '!**/_*/**' -e '^\s*[^#\s].*clan\.core\.vars' -e '^\s*[^#\s].*vars/(shared|per-machine)/' modules | sort > logs/sscv-1-files-<ts>.txt
```

  Assign each file to a step of design D10 or to design D8's final set; the sorted list is task 2.4's `expected`.

## Task 2: Step 1, the seam with no consumer (tasks 2.1–2.5)

- [ ] **Step 1:** Write `modules/system/secrets.nix`. Shape (names fixed, layout free):

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
    key = "<spelling settled by compose-hosts-from-cohesive-aspects>";
    options.vanixiets.secrets = lib.mkOption { type = lib.types.attrsOf (lib.types.submodule secretModule); default = { }; };
    config = lib.optionalAttrs (options ? clan.core.vars) {
      clan.core.vars.generators = lib.mapAttrs (_: toClan) (lib.filterAttrs (_: s: !s.provided) config.vanixiets.secrets);
      # read-only fields: set from config.clan.core.vars.generators.<n>.files.<f> and
      # config.sops.placeholder."vars/${rel_dir}/${f}" through each file submodule's config
    };
  };
in
{
  flake.modules.nixos.secrets = module;
  flake.modules.darwin.secrets = module;
  flake.modules.homeManager.secrets = { lib, ... }: { options.vanixiets.secrets = /* attrsOf { files.<f>.{path,placeholder} } */ lib.mkOption { default = { }; }; };
  flake.lib.secretsBackend.generatorsOf = hostConfig: hostConfig.clan.core.vars.generators or { };
  flake.modules.nixos.base.imports = [ flakeConfig.flake.modules.nixos.secrets ];
  flake.modules.darwin.base.imports = [ flakeConfig.flake.modules.darwin.secrets ];
}
```

  A `nullOr` field must never write a definition; check the `toClan` output with the translation judge before anything else.
- [ ] **Step 2:** Evaluate `vanixiets.secrets` on cinnabar and stibnite; both `{}`.
- [ ] **Step 3:** Edit `nixos/hm-sops-bridge.nix`: a `view` function (entries with a file whose `owner` is the user, projected to `{ files.<f>.{path,placeholder} }`), `home-manager.sharedModules` and `home-manager.users.<u>.vanixiets.secrets` for every `home-manager.users` name, outside `lib.mkIf (cfg.users != { })`; a `flake.modules.darwin.hm-sops-bridge` with only those two; both into the class bases; delete the six per-host `hm-sops-bridge` imports. Import `homeManager.secrets` in `home/mk-home.nix`.
- [ ] **Step 4:** Evaluate the three views of task 2.2; each `{}`.
- [ ] **Step 5:** Write `modules/checks/secrets-seam-translation.nix` (fixtures of design D11; `lib.evalModules` over `flake.modules.nixos.secrets` plus a stub `options.clan.core.vars.generators = lib.mkOption { type = lib.types.attrsOf (lib.types.submodule { freeformType = lib.types.attrsOf lib.types.anything; }); }`), the gating and `testSizes` entry as `checks/host-key-obligations.nix:62-73` does. Build it; run the `restartUnits` mutant; record.
- [ ] **Step 6:** Write `modules/checks/secrets-seam-confinement.nix`: `actual` from `lib.filesystem.listFilesRecursive ../.` filtered to `.nix`, no `/_` component, and a non-comment line matching the two patterns (`lib.splitString "\n"` + `builtins.match`); `expected` the literal list from Task 1 Step 4; `flake.lib.mkStructuralCheck`. Build it; run the mutant of task 2.4.
- [ ] **Step 7:** `treefmt` the new and edited files; squash into step 1's commit; return `just drv-diff <parent> <commit> openspec/changes/seam-secrets-away-from-clan-vars/drv-delta/01-seam.txt`.

## Tasks 3–13: Steps 2–12, one closed set each (task groups 3–13)

The same five moves per step; tasks.md names each step's files, generators and checks.

- [ ] **Step 1 (closed set):** `rg -n -e '<gen1>' -e '<gen2>' … modules` and `rg -n 'mkDefault|mkForce|mkOverride|mkMerge|mkIf'` inside each declaration; save the log; every hit is a file of this step or of design D8's set.
- [ ] **Step 2 (declarations):** in each owning file, replace `clan.core.vars.generators.<name> = { … };` with `vanixiets.secrets.<name> = { … };`, field for field, all definitions of a generator in one edit and in order. A module evaluated without clan elsewhere (fixtures, `vm-tests/postgresql-backup-restore.nix`) adds `imports = [ <class>.secrets ]` and loses its `options ? clan.core.vars` guard.
- [ ] **Step 3 (readers):** replace `config.clan.core.vars.generators.<name>.files.<f>.path` with `config.vanixiets.secrets.<name>.files.<f>.path` (and `.value`, `.exists`); a read guarded by `or null` becomes a test of the read-only field against `null`; an obligation reads `hostConfig.vanixiets.secrets.<name>`.
- [ ] **Step 4 (evidence):** evaluate the step's generators' baseline projection on each host that declares them and diff against Task 1 Step 3; run the step's named check builds and mutants; delete the cleared files from the confinement `expected`; build the confinement check.
- [ ] **Step 5 (deliver):** `treefmt`; squash into the step's commit; return `just drv-diff <parent> <commit> openspec/changes/seam-secrets-away-from-clan-vars/drv-delta/<step>.txt`; after the operator's run, resolve every `may-change` in that file to `changed` or delete it, and re-judge.

Step-specific points:
- Step 2 (group 3): the recipe mutant of task 3.4 changes `niks3-api-token`'s script and must move magnetite's toplevel.
- Step 7 (group 8): `langfuse` has two definitions in `clan/services/otel-collector` (`:1569`, `:1690` on main); the six recipe-running judges stay untouched and task 8.5 checks their drvPaths.
- Step 9 (group 10): the credential adapter keeps its assertions but compares `osConfig.vanixiets.secrets.<gen>.files.<f>` (path, placeholder, custody fields) with `osConfig.sops.secrets`; `secretName` disappears with `rel_dir`. Update `lib/vars.nix`'s exemption comment.
- Step 10 (group 11): `vcs-signing.nix` reads `config.vanixiets.secrets.${commitSigningGenerator (signingPerson username)}.files.key.path or null` from the home view, and keeps its machine-name read for the legacy branch; `defaultText` stops naming clan.
- Step 11 (group 12): the two provided entries; the host-key mutant of task 12.6.

## Task 14: Step 13, close (tasks 14.1–14.6)

- [ ] **Step 1:** Replace `hostConfig.clan.core.vars.generators` in `lib/shared-vars-recipients.nix:43` and `lib/fleet-deployer.nix:306` with `self.lib.secretsBackend.generatorsOf hostConfig` (or `config.flake.lib…`, as each file already reaches `flake.lib`); diff the baselines; build the two obligation checks.
- [ ] **Step 2:** Set the confinement `expected` to the final list; update `lib/vars.nix`'s header; run the gitea mutant.
- [ ] **Step 3:** Close-out search for guards and fallbacks (task 14.4).
- [ ] **Step 4:** Documents (task 14.5); `prek run --files`.
- [ ] **Step 5:** `treefmt`; squash; return the step 13 drv-diff command.

## Task 15: Integration verification (tasks 15.1–15.3)

- [ ] **Step 1:** Copy every resolved `changed` entry of the step files into `drv-delta/whole-change.txt`; return `just drv-diff <step 1 parent> <step 13 merge> openspec/changes/seam-secrets-away-from-clan-vars/drv-delta/whole-change.txt`.
- [ ] **Step 2:** Re-run Task 1 Step 3's projections at the final merge and diff them; all empty.
- [ ] **Step 3:** Build the confinement check at the final merge and compare its literal with design D8.
