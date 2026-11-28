# Name the parts of base and ai: implementation plan

**Goal:** `flake.modules.nixos.base`, `flake.modules.darwin.base` and `flake.modules.homeManager.ai` each become one definition importing a named list of parts; a small structure check keeps them that way; the reorders this causes are declared per pull request and deployed once. Covers tasks.md groups 1-6.

**Architecture:** each contributing file defines `flake.modules.<class>.base-<concern>` or `flake.modules.homeManager.ai-<harness>` (or contributes a name it already had); one list file per class holds the names in `flake.lib.{nixosBaseParts,darwinBaseParts,homeAiParts}` and maps them to `imports`; `modules/checks/structure/aspect-parts.nix` compares the aspects' definition files and the prefixed module names against the lists.

**Tech Stack:** flake-parts `flake.modules` (`deferredModule`), import-tree, `flake.lib.mkStructuralCheck`, `just drv-diff`, `nix-stock`.

**Spec:** `openspec/changes/name-the-parts-of-base-and-ai/`: `design.md` (D1-D7), `specs/aspect-parts`, `specs/aspect-parts-interface`, `specs/world-assumptions` (A375-A377), `tasks.md`.

## Global Constraints

- Implementation starts only after the operator approves the declared reorders (design D5) and the deploys they need (design D7).
- Three pull requests, one commit each, stacked in the order NixOS base, darwin base, ai.
- `just drv-diff <parent> <commit> openspec/changes/name-the-parts-of-base-and-ai/drv-delta-<step>.txt` (about 16 minutes) is the oracle for each; the implementer returns the command and does not run it.
- Evaluate with `nix-stock`; before each evaluation check `pgrep -fl nix-eval-jobs` and wait while one runs.
- `checks.<system>` names read only static data: the check's name is a literal; the modules are read only in its value.
- Mutants run in a throwaway tree under `/tmp` (`git archive HEAD | tar -x -C <dir>`, then `git init` and one commit), never in `@`.
- A leaf difference that `drv-order-trace.py` rejects stops the step; it is recorded as an open question in design.md and never added to an allow-list.

## Grounding

Read at the locked revisions (the root flake's inputs at `fcf3a652e6f1`):
- nixpkgs `bd5b7d01` `lib/modules.nix:600-614` and `:278`: modules are collected breadth-first and the list reversed before merging (A344). `lib/types.nix:1992-1997` and `lib/modules.nix:660-663`: the deferred-module merge wraps each definition in `{ _file = "<file>, via option <loc>"; imports = [ def ]; }` (A375).
- flake-parts `ea2630b7` `extras/modules.nix:12-27`: the `modules` output wraps each merged value in a function setting `_class` and `_file`, so `(builtins.head (out { }).imports).imports` is the list of wrapped definitions whose `_file` the check reads.
- nixpkgs `pkgs/build-support/buildenv/builder.pl:154-211`: the first equal-priority member providing a path wins; nix-darwin `663d8b96` `modules/config/system-path.nix:133-137` sets `ignoreCollisions = true`; home-manager `b56bcd04` `modules/home-environment.nix:985-991` does not (A376).
- nix-darwin `663d8b96` `modules/users/default.nix:20-26,236-276,278-330`: a name in `users.knownUsers`/`knownGroups` that is not declared is deleted at activation (A377).

What the prototypes measured at `fcf3a652e6f1` (design Context; the logs named there are where the results were recorded, not sources to open): the NixOS step changes no toplevel or home; the darwin step changes the four darwin toplevels, moving `mosh` and `dnscrypt-pin-dns` in `environment.systemPackages` with members, accounts, groups and ids equal; the ai step changes the ten toplevels and the six `cameron@*`/`crs58@*` homes, moving eleven agent packages in `home.packages` with members equal. The only differing leaf fields were `chosenOutputs` order in the five profile builds and the order of the three `gh-dash` bindings.

## Task 1: Baseline

- [ ] **Step 1:** Record the parent's commit id (`jj log -r <parent> --no-graph -T commit_id`).
- [ ] **Step 2:** Inventory each aspect's definitions:

```bash
for p in nixos.base darwin.base homeManager.ai; do
  nix-stock eval --json ".#.modules.$p" \
    --apply 'b: map (m: m._file) (builtins.head (b {}).imports).imports' | jq -r '.[]'
done | tee logs/ntp-1-inventory-$(date +%Y%m%d-%H%M%S).log
```

  Expected at `fcf3a652e6f1`: 33, 37 and 19 files, as design D2 lists. A new file goes into D2's lists first.
- [ ] **Step 3:** Record toplevel and home drvPaths and the list options (tasks.md 1.2):

```bash
nix-stock eval --json '.#.nixosConfigurations' --apply 'cs: builtins.mapAttrs (_: c: c.config.system.build.toplevel.drvPath) cs'
nix-stock eval --json '.#.darwinConfigurations' --apply 'cs: builtins.mapAttrs (_: c: c.config.system.build.toplevel.drvPath) cs'
nix-stock eval --json '.#.homeConfigurations' --apply 'cs: builtins.mapAttrs (_: c: c.activationPackage.drvPath) cs'
# per Mac:
nix-stock eval --json ".#.darwinConfigurations.<h>.config" --apply 'c: {
  systemPackages = map (p: p.name or "?") c.environment.systemPackages;
  inherit (c.users) knownUsers knownGroups;
  uids = builtins.listToAttrs (map (n: { name = n; value = c.users.users.${n}.uid or null; }) c.users.knownUsers);
  gids = builtins.listToAttrs (map (n: { name = n; value = c.users.groups.${n}.gid or null; }) c.users.knownGroups);
  homes = builtins.mapAttrs (_: h: map (p: p.name or "?") h.home.packages) c.home-manager.users;
}'
```

## Task 2: Pull request 1, NixOS base and the check

**Files:** the 33 NixOS files of design D2; new `modules/nixos/base.nix`; new `modules/checks/structure/aspect-parts.nix`.

- [ ] **Step 1:** In each file that defines settings, rename the target, for example `modules/system/zram-swap.nix`:

```nix
{
  flake.modules.nixos.base-zram-swap =
    { lib, ... }:
    {
      zramSwap.enable = true;
      zramSwap.memoryPercent = lib.mkDefault 100;
    };
}
```

  Files assigning both classes (`system/caches.nix`, `system/mosh.nix`, ...) rename both in pull request 2's commit for darwin and this one for NixOS. Files with the `flake.modules = { nixos.base = …; }` form (`system/mosh.nix`, `system/cli-tools/host-inspection.nix`) and the `nixos // { base.imports = …; }` form (`nixos/hm-sops-bridge.nix`, `system/secrets.nix`) are covered by the grep in tasks.md 2.1.
- [ ] **Step 2:** Delete each line that only imported a named module into `base` (working-copy line numbers on 2026-11-27, retaken at the parent: `nixos/nix-eval-lock.nix:46`, `nixos/node-exporter-textfile.nix:131`, `nixos/postgresql-backup.nix:418`, `nixos/postgresql-collation.nix:81`, `nixos/r2-usage.nix:440`, `nixos/zpool-probe.nix:223`, `system/fleet-deploy-target.nix:98`, `system/mesh-hosts.nix:113`, `system/cli-tools/host-inspection.nix:29`, `nixos/hm-sops-bridge.nix:185`, `system/secrets.nix:297`), and any `let` binding left unused.
- [ ] **Step 3:** Write `modules/nixos/base.nix`:

```nix
# The settings every NixOS host receives in common, as one list of named
# parts. A part is added by defining flake.modules.nixos.base-<concern> in one
# file and naming it here; checks.x86_64-linux.structure-aspect-parts fails on
# a file assigning into base or into an existing part, and on a part in no list.
{ config, ... }:
{
  flake.lib.nixosBaseParts = [
    "base-host-keys"
    "base-shared-vars-recipients"
    "base-source-context-obligations"
    "hm-sops-bridge"
    "nix-eval-lock"
    "node-exporter-textfile"
    "postgresql-backup"
    "postgresql-collation"
    "r2-usage"
    "zpool-probe"
    "base-nixpkgs"
    "base-admins"
    "base-caches"
    "cli-host-inspection"
    "base-commit-signing-key"
    "fleet-deploy-target"
    "base-harmonia-gc"
    "base-initrd-networking"
    "base-mesh-dns"
    "mesh-hosts"
    "base-mosh"
    "base-nix-cleanup-gcroots"
    "base-nix-download-timeout"
    "base-nix-optimization"
    "base-nix-package"
    "base-nix-settings"
    "base-nix-tarmac"
    "secrets"
    "base-command-not-found"
    "base-sshd-max-auth-tries"
    "base-zfs-force-import"
    "base-zfs-hm-ordering"
    "base-zram-swap"
  ];
  flake.modules.nixos.base.imports = map (
    name: config.flake.modules.nixos.${name}
  ) config.flake.lib.nixosBaseParts;
}
```

- [ ] **Step 4:** Write `modules/checks/structure/aspect-parts.nix`:

```nix
{ self, lib, ... }:
let
  aspects = [
    { class = "nixos"; aspect = "base"; prefix = "base-"; file = "modules/nixos/base.nix"; parts = self.lib.nixosBaseParts; exempt = [ ]; }
  ];
  # Parts stated in several files on purpose, with exactly those files.
  multiFile = { };
  definitionFiles =
    m: map (d: builtins.head (lib.splitString ", via option" d._file)) (builtins.head (m { }).imports).imports;
  relative = f: lib.last (lib.splitString "-source/" f);
  violations =
    { class, aspect, prefix, file, parts, exempt }:
    let
      foreign = builtins.filter (f: relative f != file) (definitionFiles self.modules.${class}.${aspect});
      partSites = lib.concatMap (
        n:
        let
          got = lib.sort lib.lessThan (map relative (definitionFiles self.modules.${class}.${n}));
          want = multiFile.${class}.${n} or null;
        in
        if want != null then
          lib.optional (got != lib.sort lib.lessThan want) "${class}.${n}: defined in ${toString got}, not exactly ${toString want}"
        else
          lib.optional (builtins.length got != 1) "${class}.${n}: defined in ${toString got}, not one file"
      ) parts;
      unlisted = builtins.filter (
        n: lib.hasPrefix prefix n && !(builtins.elem n parts) && !(builtins.elem n exempt)
      ) (builtins.attrNames self.modules.${class});
    in
    map (f: "${class}.${aspect}: defined in ${relative f}, not only in ${file}") foreign
    ++ partSites
    ++ map (n: "${class}.${n}: in no ${aspect} list") unlisted;
in
{
  perSystem =
    { pkgs, system, ... }:
    {
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        structure-aspect-parts = { class = "small"; measured = false; };
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        structure-aspect-parts = self.lib.mkStructuralCheck pkgs {
          name = "aspect-parts";
          actual = lib.concatMap violations aspects;
          expected = [ ];
        };
      };
    };
}
```

  If the `testSizes` entry's form differs from the sibling `modules/checks/structure/flake-shape.nix` (`<name>.class = "small"`), follow the sibling and add `measured = false` the way `darwin-uid-preflight` does.
- [ ] **Step 5:** `nix build .#checks.x86_64-linux.structure-aspect-parts`; record each listed part's definition files (each must be one); run the three mutants of tasks.md 2.4 in a throwaway tree (a file assigning into `base`, `base-zram-swap` removed from the list, a second file assigning into `base-zram-swap`); record them.
- [ ] **Step 6:** Evaluate the toplevel and home drvPaths (tasks.md 2.5); write `drv-delta-nixos-base.txt`; return the drv-diff and eval-cost commands.

## Task 3: Pull request 2, darwin base

**Files:** the 37 darwin-contributing files of design D2 (as at `fcf3a652e6f1`; retaken at the parent); `modules/darwin/base.nix`; new `modules/darwin/base-essentials.nix`; the check.

- [ ] **Step 1:** Move `darwin/base.nix`'s module body into a new `modules/darwin/base-essentials.nix` under `flake.modules.darwin.base-essentials`; rename the other darwin targets (the nine `system-defaults/*.nix` files to `base-system-defaults`); delete the five import-only lines (working-copy line numbers on 2026-11-27: `nixos/hm-sops-bridge.nix:188`, `system/cli-tools/host-inspection.nix:30`, `system/fleet-deploy-target.nix:104`, `system/mesh-hosts.nix:118`, `system/secrets.nix:300`).
- [ ] **Step 2:** Rewrite `modules/darwin/base.nix` as the list (29 names covering the 37 files, design D2 order, plus `base-package-order` from `shape-the-repository-for-its-readers`: 30) the way Task 2 Step 3 does, with `flake.lib.darwinBaseParts`.
- [ ] **Step 3:** Add `{ class = "darwin"; aspect = "base"; prefix = "base-"; file = "modules/darwin/base.nix"; parts = self.lib.darwinBaseParts; exempt = [ ]; }` and `multiFile.darwin.base-system-defaults = map (n: "modules/darwin/system-defaults/${n}.nix") [ "custom-user-prefs" "dock" "finder" "input-devices" "loginwindow" "misc-defaults" "nsglobaldomain" "screencapture" "window-manager" ]` to the check; confirm its drvPath equals Task 2's; run the tenth-file mutant.
- [ ] **Step 4:** Record the four Macs' lists (tasks.md 3.3). Expected: `mosh` to the front of `environment.systemPackages` (after `fleet-deploy-watch` on argentum and rosegold), `dnscrypt-pin-dns` after `git`; members, `knownUsers`, `knownGroups`, uids and gids equal.
- [ ] **Step 5:** For each Mac, `python3 openspec/changes/name-the-parts-of-base-and-ai/drv-order-trace.py <parent toplevel drv> <commit toplevel drv>`; it must print `RESULT: every difference is a declared reorder` and exit 0. A rejection stops the pull request.
- [ ] **Step 6:** Build and compare the reordered profiles at parent and commit (tasks.md 3.5):

```bash
links() { (cd "$1" && find . -type l | LC_ALL=C sort | while read -r l; do printf '%s %s\n' "$l" "$(readlink "$l")"; done); }
for side in parent commit; do
  nix build --no-link --print-out-paths "<drv of system-path at $side>^out" > /tmp/sp-$side.path
done
diff <(links "$(cat /tmp/sp-parent.path)") <(links "$(cat /tmp/sp-commit.path)")
```

  The `.drv` paths are the `system-path.drv` and `system-applications.drv` inputs the trace printed for each side; an empty `diff` is required for every pair.
- [ ] **Step 7:** Write `drv-delta-darwin-base.txt` with a header in the form of `openspec/changes/compose-hosts-from-cohesive-aspects/drv-delta-stibnite-workstation.txt` and the eight entries of design D5; return the drv-diff command.

  Not done as written (2026-11-28): Tasks 3 and 4 landed in one commit with `shape-the-repository-for-its-readers`' order step, under that change's `drv-delta-order.txt`; design D5, "Departure", and Open Question 2 record it.

## Task 4: Pull request 3, ai

**Files:** the 19 ai-contributing files of design D2; new `modules/home/ai/default.nix`; the check.

- [ ] **Step 1:** Rename targets (`homeManager.ai` to `ai-claude-code` in the five claude-code files, including `hooks.nix`'s `.imports`; `ai-codex`, `ai-devin`, `ai-moshi`, `ai-omnigent`, `ai-omp`, `ai-opencode`, `ai-pi`, `ai-tuicr`, `ai-omnigraph`; `ai` to `ai-gh-dash` in `development/gh-dash.nix`); drop `"ai"` from `atomic`'s `exportAs` names (`atomic/default.nix:141`); delete the import-only lines `capabilities.nix:17`, `openspec/default.nix:3`, `worktrunk/default.nix:14`. Comments that say "member of the homeManager.ai aggregate" stay true.
- [ ] **Step 2:** Write `modules/home/ai/default.nix` with `flake.lib.homeAiParts` (15 names, design D2 order) and `flake.modules.homeManager.ai.imports`.
- [ ] **Step 3:** Add `{ class = "homeManager"; aspect = "ai"; prefix = "ai-"; file = "modules/home/ai/default.nix"; parts = self.lib.homeAiParts; exempt = [ "ai-skills" "ai-skills-compose" ]; }` (a comment gives the exemption's reason: `ai-capabilities` imports them) and `multiFile.homeManager.ai-claude-code = map (n: "modules/home/ai/claude-code/${n}.nix") [ "ccstatusline-settings" "default" "hooks" "mcp-servers" "wrappers" ]` to the check; run the `homeAiParts` and sixth-file mutants.
- [ ] **Step 4:** Record the reached homes' lists (tasks.md 4.3). Expected: the eleven agent packages move; members equal.
- [ ] **Step 5:** Run `drv-order-trace.py` over the ten toplevels and six homes (Task 3 Step 5); then build and compare, as in Task 3 Step 6, every `home-manager-path`, `home-manager-fonts` and `home-manager-applications` pair the trace accepted.
- [ ] **Step 6:** Write `drv-delta-ai.txt` (header form as Task 3, the entries of design D5); return the drv-diff command.

  Not done as written (2026-11-28): see Task 3 Step 7.

## Task 5: Deploy (operator)

- [ ] **Step 1:** After pull request 3 lands, deploy each host (`clan machines update <host>`, or `just activate` on a Mac at the keyboard). The built-profile comparisons of Tasks 3 and 4 already showed what the reorders link, so live hosts are not compared; a Mac activated between pull requests 2 and 3 is simply deployed again here.
- [ ] **Step 2:** On each host, `readlink /run/current-system` must equal `nix-stock eval --raw .#<nixos|darwin>Configurations.<host>.config.system.build.toplevel.outPath` at the deployed main commit; on a Mac the deploy output must have no `deleting user` or `deleting group` line; read every alert posted since the deploy started and record each with its cause in `logs/ntp-5-<host>-<ts>.log`.
- [ ] **Step 3:** Activate the standalone homes named in tasks.md 5.1 and check each activated generation is the evaluated `activationPackage` at the activated main commit.

## Task 6: Integration verification

- [ ] tasks.md 6.1-6.4.
