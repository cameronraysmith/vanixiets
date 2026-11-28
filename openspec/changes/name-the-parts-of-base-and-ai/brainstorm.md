<!--
Raw capture of the brainstorming decision log.
-->

# Brainstorm: name the parts of `base` and `ai`

## Background

`flake.modules.nixos.base`, `flake.modules.darwin.base` and `flake.modules.homeManager.ai` are each assembled implicitly.
import-tree loads every file under `modules/`, and every file that assigns into one of the three adds a definition to it; flake-parts merges the definitions as a `deferredModule`.
No file says what `base` or `ai` consists of, and no host, home or test can take one part of either.

Evaluated at commit `fcf3a652e6f1` (the working copy's parent on 2026-11-27; the merged definitions of each aspect read from the flake's `modules` output, recorded in `logs/ntp-0-inventory-20261127-181533.log`):
- `nixos.base`: 33 definitions from 33 files under `modules/lib`, `modules/nixos`, `modules/nixpkgs` and `modules/system`.
- `darwin.base`: 37 definitions from 37 files: 21 under `modules/darwin` (nine under `modules/darwin/system-defaults/`), 2 under `modules/lib`, `modules/nixos/hm-sops-bridge.nix`, `modules/nixpkgs/base-defaults.nix` and 12 under `modules/system`. The darwin `hm-sops-bridge` module and `modules/system/secrets.nix` joined `darwin.base` on 2026-11-27, so the inventory is retaken at each pull request's parent before its edits.
- `homeManager.ai`: 19 definitions from 19 files, 17 under `modules/home/ai`, plus `modules/home/development/gh-dash.nix` (the `tuicr` review binding) and `modules/home/tools/omnigraph.nix` (the omnigraph skill).

Eleven of the NixOS definitions, five of the darwin ones and four of the ai ones only import a module that already has its own name (`nix-eval-lock`, `mesh-hosts`, `fleet-deploy-target`, `secrets`, `hm-sops-bridge`, `atomic`, `ai-capabilities`, `openspec`, `worktrunk`, ...).

Importers: `base` is imported by the six NixOS hosts (`machines/nixos/{cinnabar,electrum,galena,magnetite,pyrite,scheelite}/default.nix`) and by `darwin-workstation`, which the four Macs import; no check or runtime test imports either `base`.
`ai` is in the `aggregates` of crs58 (`home/users/crs58/meta.nix`), which the alias fold copies to cameron; no other user and no test imports it.
So `ai` reaches the standalone homes `crs58@*` and `cameron@*` (six) and every host carrying an integrated crs58 or cameron home: all ten.

The change was designed once (compose-hosts-from-cohesive-aspects, design D11) and set aside there because the module system collects imports breadth-first (A344): written as named import lists, each part landed two to three import levels deeper than its old direct definition, and argentum's system packages and every home importing `ai` changed.
That change could only accept drvPath-identical commits for this step, so it deferred the step to its own change (its Resolved Question 10).
Since then stibnite joined `darwin-workstation` as a declared order-only change: before and after lists shown, members equal, account and group sets and ids compared, and the toplevel declared changed in an allow-list (`drv-delta-stibnite-workstation.txt`).

## Q1: Which of the three options?

compose-hosts listed three:
(a) keep each file's named part and build `base`/`ai` as `lib.mkMerge` of the parts' raw definitions (read from `options.flake.modules.definitionsWithLocations`), so every definition keeps its depth;
(b) leave `base` and `ai` implicit;
(c) named import lists, declaring every reordered toplevel and home and deploying every host they reach.

(b) is what the fleet has: an aspect whose membership is implicit cannot be read in one place or taken in part, and every later file that assigns into it widens it silently.
(a) keeps derivations identical, but only by adding a mechanism (raw definitions re-merged at the old depth) whose one job is to keep merge order; every reader of `base` would have to understand it.
(c) costs, per pull request, one drvPath comparison with an exact allow-list, and per reached host one deploy and per reached home one activation.
stibnite's precedent shows that cost is a derivation comparison and an activation, not an investigation.

Decision: (c), as a declared order-only change.

## Q2: What is a part, and what is it called?

One part per contributing file, except where several files are one concern:
- darwin's nine `system-defaults/*.nix` files are one concern (macOS defaults by domain) and make one part, `base-system-defaults`;
- claude-code's five files (`default.nix`, `ccstatusline-settings.nix`, `hooks.nix`, `mcp-servers.nix`, `wrappers.nix`) are one harness and make one part, `ai-claude-code`.

A file whose definition only imports a module that already has a name contributes that name to the list directly and drops its assignment; no alias is added.
Every other file renames its assignment to `flake.modules.<class>.base-<concern>` or `flake.modules.homeManager.ai-<harness>`.
`darwin/base.nix` holds darwin's list, so its own settings (sudo, Touch ID, `MaxAuthTries`, nix features and trusted users, `nixbld` gid, `stateVersion`, time zone, vim and git, zsh) move to `darwin/base-essentials.nix` as `base-essentials`.

## Q3: Where does each list live, and in what order?

One file per class: `modules/nixos/base.nix` (new), `modules/darwin/base.nix` (now the list), `modules/home/ai/default.nix` (new).
Each lists the part names as data (`flake.lib.nixosBaseParts`, `flake.lib.darwinBaseParts`, `flake.lib.aiParts`) and sets the aspect's `imports` to those modules in that order; `flake.lib` is `lazyAttrsOf raw`, so each list file owns its own key.
The order is today's merge order (the contributing files' import-tree order).
No order reproduces today's derivations, because the depth change, not the sibling order, moves the definitions (A344, A375); `lib.mkOrder` cannot place a default-priority definition between two others of the same priority, so the order is taken as it falls, as for stibnite.

## Q4: What does each list change? (measured 2026-11-27)

A prototype of each rename (the renames and list files of Q2 and Q3, applied by a script to a scratch copy of `fcf3a652e6f1`) was evaluated, and the six NixOS and four darwin toplevels and the twenty home activation packages were compared before and after (recorded in `logs/ntp-1-drvpaths-20261127-181533.log`):
- NixOS `base`: no toplevel and no home changes.
- darwin `base`: the four darwin toplevels change; no NixOS host and no home.
- `ai`: all ten toplevels and the six homes `cameron@{aarch64-darwin,aarch64-linux,x86_64-linux}` and `crs58@{...}`; the other fourteen homes are unchanged.

For each change, the list options and the derivations (`logs/ntp-2-lists-20261127-181533.log`, `logs/ntp-3-derivations-20261127-181533.log`):
- darwin `base`, each Mac: `environment.systemPackages` keeps its members (argentum 37, blackphos 32, rosegold 37, stibnite 40) and moves two from after `nix-info`: `mosh` to the front (after `fleet-deploy-watch` on argentum and rosegold) and `dnscrypt-pin-dns` to after `git`.
  `users.knownUsers`, `users.knownGroups`, every uid and every gid are equal, and every integrated home's packages are equal.
  `nix derivation show`, followed down the changed inputs: `system-path` and `system-applications` differ only in the order of `chosenOutputs` (same entries); `etc` and the toplevel differ only in those paths.
- `ai`, each reached home (standalone or integrated): `home.packages` keeps its members (320 to 344) and moves eleven, the agent packages `devin-cli`, `omp`, `ocd`, `omnigent`, `moshi-hook-wrapped`, `claude-glm`, `claude-cerebras`, `nodejs-22`, `uv`, `docker` and `atomic`.
  `home-manager-path`, `home-manager-fonts` and `home-manager-applications` differ only in `chosenOutputs` order; `gh-dash-config.yml` differs only in the order of `keybindings.prs` (the same three bindings, keys `m`, `M`, `C`, all distinct).
  Every other changed derivation (`home-manager-files`, the activation script, `hm-putter.json`, the font config, the generation, `user-environment`, the units, `etc`, the toplevel) differs only in the paths of those.
  Every host's `systemPackages`, users, groups, `knownUsers`, `knownGroups`, uids and gids are equal; every other integrated home (christophersmith, raquel, janettesmith, tara, omnigent-cameron, omnigent-janettesmith) is equal.

Can a reorder change what a profile contains?
buildEnv keeps the first of two equal-priority members that provide one subpath; nix-darwin's `system-path` ignores collisions, and `home-manager-path` requires a collision's contents to be identical (A376).
So a reorder changes a profile only when a moved member shares a subpath with another member.
Listing every file of each member present in the local store (`logs/ntp-4-collisions-20261127-181533.log`): on stibnite and argentum, 383 subpaths are shared, none by `dnscrypt-pin-dns` or `mosh`; in `crs58@aarch64-darwin`'s 320 members, 5 are shared, none by a moved member.
Not covered: `bind` (darwin) and `go-containerregistry` (home) are absent from the local store; neither is moved. The comparison of built profiles before each pull request lands (Q6) covers them.

Nothing other than order differed.

## Q5: How many pull requests?

Three, each one commit accepted by `just drv-diff` against its parent with an exact allow-list:
1. NixOS `base` and the structure check: no toplevel or home changes; the check is added.
2. darwin `base`: the four darwin toplevels and their machine checks change.
3. `ai`: the ten toplevels, the six homes, and their machine and home checks change.

Splitting keeps each allow-list about one aspect, and the NixOS step lands with no deploy at all.
The Macs are reached by both 2 and 3; deploying after 3 lands deploys each host once.

## Q6: Deploy and activation

After 3 lands (with 2 below it): the operator deploys the ten hosts and activates the standalone `crs58@*` and `cameron@*` homes that are in use.
Before deploying a Mac, the account and group sets and every id are already shown equal by evaluation, so nix-darwin, which deletes an account in `users.knownUsers` that the configuration no longer declares (A377), deletes nothing.
Before each of pull requests 2 and 3 lands, every profile build the comparison reports as reordered (`system-path`, `system-applications`, `home-manager-path`, `home-manager-fonts`, `home-manager-applications`) is built at the pull request's parent and at its commit, and the link target of every file in the two is compared; this closes the two members not checked in Q4, since building realizes them.
Live hosts are not compared: a host's running generation is not the pull request's parent, and a deploy carries whatever else has landed. The deploys then check only that each host runs the system its branch evaluates to.
A Mac activated between 2 and 3 loses nothing: each comparison was made on built profiles before its pull request landed; that Mac is deployed again after 3.

## Q7: How does a later contributor add a part?

The list is the registration: a new file defines `flake.modules.<class>.base-<concern>` (or `ai-<harness>`) and adds its name to the class's list in one place.
A check, `checks.x86_64-linux.structure-aspect-parts`, fails when:
- any of the three aspects has a definition from a file other than its list file (a file assigned into `base` or `ai` directly), naming the file;
- a listed part has a definition from a file other than its own defining file (a second file assigning into `base-zram-swap`, say), naming the file; the parts built from several files on purpose, `base-system-defaults` (nine files) and `ai-claude-code` (five), each list their files in the check;
- a module named with the aspect's prefix (`base-`, `ai-`) is in no list, naming it; `ai-skills` and `ai-skills-compose`, which `ai-capabilities` imports, are exempt by name with that reason.
It reads only module values and the three lists (no nixpkgs instance, nothing built), through the repository's `mkStructuralCheck`, so its size class is `small`; it is declared `measured = false` until nixbot has runs to measure.
Its name is a literal and its value reads the flake's `modules` output, so the `checks.x86_64-linux` key set gains nothing strict.

## Agreed approach

Option (c), three pull requests (NixOS `base` with the check, darwin `base`, `ai`), each accepted on `just drv-diff` with an exact allow-list stating the reorders measured in Q4; deploy the ten hosts and activate the six reached homes once after the third lands.
Planned only; implementation waits for approval.
