## Context

### Current state

`flake.modules.nixos.base`, `flake.modules.darwin.base` and `flake.modules.homeManager.ai` are `deferredModule` options that import-tree fills from every file assigning into them.
Read from the flake's `modules` output at commit `fcf3a652e6f1` (recorded in `logs/ntp-0-inventory-20261127-181533.log`), they hold 33, 37 and 19 definitions, one per contributing file (D2 lists them). The darwin `hm-sops-bridge` module and `modules/system/secrets.nix` joined `darwin.base` on 2026-11-27; task 1.1 retakes the inventory at each pull request's parent.
`base` is imported by each NixOS host's module (`machines/nixos/<host>/default.nix`) and by `darwin-workstation`, which all four Macs import; `ai` is one of crs58's `aggregates` (`home/users/crs58/meta.nix`), copied to cameron by the alias fold, and so reaches the standalone `crs58@*` and `cameron@*` homes and the integrated crs58 or cameron home on every host.
No check or runtime test imports either.

### Import depth decides list order

The module system collects modules breadth-first and merges equal-priority list definitions in the reverse of that order (A344), so a definition's place in a list option depends on how deep it is imported.
Hosts import the option value `config.flake.modules.<class>.base`, whose `deferredModule` merge imports each definition through a location wrapper (A375).
A definition assigned into `base` today is three levels below the importing host's module (the merged value, the wrapper, the definition); written as a part listed by `base`, it is six (the list's merged value, wrapper and definition, then the part's), three levels deeper.
A file that today only imports an already named module (`flake.modules.nixos.base.imports = [ modules.nixos.zpool-probe ]`) reaches that module's merged value at level four, and listing the module by name in `base` reaches it at level four too, so those modules keep their depth.
`lib.mkOrder` cannot place a default-priority definition between two others of the same priority, so the order that results is taken as it falls.

### What naming the parts changes (measured 2026-11-27)

A prototype of each rename (D2, D3), applied by a script to a scratch copy of `fcf3a652e6f1`, was evaluated with `nix-stock` (nix-classic 2.35.6) on stibnite, with no other evaluation running.

| Step | Toplevels changed | Homes changed | Machine and home checks changed |
|---|---|---|---|
| NixOS `base` | none | none | none |
| darwin `base` | argentum, blackphos, rosegold, stibnite | none | `checks.aarch64-darwin.darwin-{argentum,blackphos,rosegold,stibnite}` |
| `ai` | all ten | `cameron@{aarch64-darwin,aarch64-linux,x86_64-linux}`, `crs58@{aarch64-darwin,aarch64-linux,x86_64-linux}` | `checks.x86_64-linux.nixos-{cinnabar,electrum,galena,magnetite,pyrite}`, `checks.aarch64-darwin.darwin-{argentum,blackphos,rosegold,stibnite}`, `checks.{x86_64-linux,aarch64-darwin}.home-manager-crs58` |

Sources: `logs/ntp-1-drvpaths-20261127-181533.log` (toplevels and homes), `logs/ntp-5-check-drvpaths-20261127-181533.log` (the 21 checks named `nixos-*`, `darwin-*` and `home-manager-*`).
Every changed configuration was compared list by list (recorded in `logs/ntp-2-lists-20261127-181533.log`) and derivation by derivation (`nix-stock derivation show` followed down the changed inputs; recorded in `logs/ntp-3-derivations-20261127-181533.log`, and re-judged with this change's `drv-order-trace.py` for argentum and magnetite, both accepted):

- darwin `base`, on each Mac: `environment.systemPackages` keeps its members (argentum 37, blackphos 32, rosegold 37, stibnite 40) and moves two that followed `nix-info`: `mosh` to the front (after `fleet-deploy-watch` on argentum and rosegold) and `dnscrypt-pin-dns` to after `git`.
  `system-path` and `system-applications` differ only in the order of their `chosenOutputs`, the same entries; `etc` and the toplevel differ only in those two paths.
  `users.knownUsers` and `users.knownGroups` are equal, in the same order, and so is every uid and gid; every integrated home's packages are equal.
- `ai`, in every reached home (the six standalone homes and the integrated cameron home on argentum, rosegold and the six NixOS hosts, crs58 on blackphos and stibnite): `home.packages` keeps its members (320 to 344) and moves the same eleven, the agent packages `devin-cli`, `omp`, `ocd`, `omnigent`, `moshi-hook-wrapped`, `claude-glm`, `claude-cerebras`, `nodejs-22`, `uv`, `docker` and `atomic`.
  `home-manager-path`, `home-manager-fonts` and `home-manager-applications` differ only in `chosenOutputs` order; `gh-dash-config.yml` only in the order of `keybindings.prs`, the same three bindings on the distinct keys `m`, `M` and `C`.
  The other changed derivations (`home-manager-files`, the activation script, `hm-putter.json`, the font configuration, the generation, `user-environment`, the home-manager unit, `etc`, `system-units`, `activate`, the toplevel) differ only in those paths.
  Every host's `systemPackages`, users and groups (and on the Macs `knownUsers`, `knownGroups`, uids and gids) are equal, and every other integrated home is equal (christophersmith, raquel, janettesmith, tara, omnigent-cameron, omnigent-janettesmith).

Across the twenty traced configurations, the only fields that differ at a leaf, once changed inputs' paths are substituted, are `structuredAttrs.chosenOutputs` of `system-path`, `system-applications`, `home-manager-path`, `home-manager-fonts` and `home-manager-applications` (40 leaves, same entries) and `structuredAttrs.value.keybindings.prs` of `gh-dash-config.yml` (16 leaves, the same three bindings).

A reorder changes a profile's contents only where a moved member shares a subpath with another member at the same priority (A376).
Listing every file of every member present in the local store (`logs/ntp-4-collisions-20261127-181533.log`): stibnite's and argentum's system packages share 383 subpaths, none provided by `mosh` or `dnscrypt-pin-dns`; `crs58@aarch64-darwin`'s 320 home packages share 5, none provided by a moved member.
`bind` (system packages) and `go-containerregistry` (home packages) were absent from the local store and are not covered here; neither moves, and the built-profile comparison of D4 covers them.

Nothing other than order differed.

### Requirements and the world they rest on

- `aspect-parts` (behavioral): the base settings of each kind of host and the agent tooling are each one stated list of parts; a part can be taken alone; restating them changes nothing delivered beyond declared order.
- `aspect-parts-interface` (interface): the list files and `flake.lib` lists, `checks.x86_64-linux.structure-aspect-parts`, and the per-pull-request comparison.
- `world-assumptions`: A375 (import levels), A376 (buildEnv collisions), A377 (nix-darwin deletes a known account it no longer declares); A344 is relied on as stated in the corpus.

## Goals / Non-Goals

**Goals:**
- What `nixos.base`, `darwin.base` and `ai` consist of is one list each, readable in one file.
- Each part is a named module a host, home or test can import alone.
- A later file cannot add to `base` or `ai` without a list naming it; the structure check fails otherwise.
- Every delivered difference is declared before it lands, shown to be order only, and deployed once per host and activated once per home.

**Non-Goals:**
- Pinning today's order with `lib.mkOrder` or a raw-definition merge (option (a) in D1).
- Changing what any part does, or moving parts between aspects.
- Naming the parts of other aggregates (`development`, `shell`, `core`, ...).
- Renaming `ai-skills` and `ai-skills-compose`, which `ai-capabilities` imports.

## Decisions

### D1: Named import lists, declared as an order-only change
- **Choice**: option (c) of the earlier design: each aspect becomes an import list of named parts, and every reordered toplevel and home is declared and deployed.
- **Rationale**: an aspect whose membership is implicit cannot be read in one place or taken in part. The cost of (c) is, per pull request, a derivation comparison with an exact allow-list, and per reached host one deploy and per reached home one activation; stibnite's move into `darwin-workstation` showed that cost to be a derivation comparison and an activation.
- **Alternatives considered**: (a) build each aspect as `lib.mkMerge` of its parts' raw definitions (read from `options.flake.modules.definitionsWithLocations`) so every definition keeps its depth: derivation-identical, but it adds a mechanism whose only job is to keep merge order, which every reader of `base` must then understand; (b) leave the aspects implicit, the state the fleet is in.
- **Boundary**: source-versus-delivered: the source change is a rename; the delivered change is a reorder of lists whose members are equal.

### D2: One part per contributing file, unless several files are one concern
- **Choice**: a file defining settings renames its assignment to `flake.modules.<class>.base-<concern>` or `flake.modules.homeManager.ai-<harness>`; a file whose definition only imported an already named module drops that assignment and the list names the module; darwin's nine `system-defaults/*.nix` files are one part, `base-system-defaults`, and claude-code's five files one part, `ai-claude-code`. `darwin/base.nix`'s own settings move to `darwin/base-essentials.nix` as `base-essentials`.

  NixOS `base`, in list order (existing names in italics):
  `base-host-keys` (`lib/host-keys.nix`), `base-shared-vars-recipients` (`lib/shared-vars-recipients.nix`), `base-source-context-obligations` (`lib/source-context-obligations.nix`), *`hm-sops-bridge`*, *`nix-eval-lock`*, *`node-exporter-textfile`*, *`postgresql-backup`*, *`postgresql-collation`*, *`r2-usage`*, *`zpool-probe`*, `base-nixpkgs` (`nixpkgs/base-defaults.nix`), `base-admins`, `base-caches`, *`cli-host-inspection`*, `base-commit-signing-key`, *`fleet-deploy-target`*, `base-harmonia-gc`, `base-initrd-networking`, `base-mesh-dns`, *`mesh-hosts`*, `base-mosh`, `base-nix-cleanup-gcroots`, `base-nix-download-timeout`, `base-nix-optimization`, `base-nix-package`, `base-nix-settings`, `base-nix-tarmac`, *`secrets`*, `base-command-not-found` (`system/srvos/command-not-found.nix`), `base-sshd-max-auth-tries`, `base-zfs-force-import`, `base-zfs-hm-ordering`, `base-zram-swap` (the unattributed ones from `system/<name>.nix`): 33 entries.

  darwin `base`: `base-essentials`, `base-etc-hosts`, `base-homebrew`, `base-launchd-wait4path`, `base-nix-cleanup-gcroots`, `base-nix-eval-jobs`, `base-nix-settings`, `base-pmset`, `base-resolver-reload`, `base-secure-input-watch`, `base-sops-boot-install`, `base-sshd-declaration` (12 parts, each from `darwin/<name>.nix`), `base-system-defaults` (the 9 `darwin/system-defaults/*.nix`), `base-shared-vars-recipients`, `base-source-context-obligations` (the 2 under `lib/`), *`hm-sops-bridge`* (`nixos/hm-sops-bridge.nix`), `base-nixpkgs` (`nixpkgs/base-defaults.nix`), and from the 12 under `system/`: `base-caches`, *`cli-host-inspection`*, `base-commit-signing-key`, *`fleet-deploy-target`*, `base-harmonia-gc`, `base-mesh-dns`, *`mesh-hosts`*, `base-mosh`, `base-nix-download-timeout`, `base-nix-optimization`, `base-nix-package`, *`secrets`*: 29 entries covering all 37 files (12 + 9 + 2 + 1 + 1 + 12). A file contributing to both classes defines the same part name in each.

  `ai`: *`atomic`* (its `exportAs` names drop `ai`), *`ai-capabilities`*, `ai-claude-code` (`claude-code/*.nix`; `hooks.nix` imports `claude-code-hooks` into it), `ai-codex`, `ai-devin`, `ai-moshi`, `ai-omnigent`, `ai-omp`, `ai-opencode`, *`openspec`*, `ai-pi`, `ai-tuicr`, *`worktrunk`*, `ai-gh-dash` (`development/gh-dash.nix`), `ai-omnigraph` (`tools/omnigraph.nix`): 15 entries from 19 files.
- **Rationale**: a part is the unit a host or test takes; files split by domain inside one concern are not separate units. Listing an existing name adds no alias and keeps that module at its old depth (Context, "Import depth").
- **Alternatives considered**: one part per file everywhere (nine darwin defaults parts and five claude-code parts, none of which a host would take alone); a `base-` alias for each existing named module (a second name for one module).

### D3: One list file per class, the names as data
- **Choice**: `modules/nixos/base.nix` sets `flake.lib.nixosBaseParts` to the names and `flake.modules.nixos.base.imports = map (n: config.flake.modules.nixos.${n}) config.flake.lib.nixosBaseParts`; `modules/darwin/base.nix` the same with `darwinBaseParts`; `modules/home/ai/default.nix` with `aiParts`. The order is today's merge order, the contributing files' import-tree order.
- **Rationale**: the names as data let the structure check compare names; `flake.lib` is `lazyAttrsOf raw` (`modules/lib/option.nix`), so each list file owns its own key rather than three files merging one.
- **Alternatives considered**: `with config.flake.modules.<class>; [ ... ]` (no names for the check to read); one shared `flake.lib.aspectParts` (would need one file for all three classes).
- **Boundary**: source-only.

### D4: The acceptance rule
- **Choice**: each pull request is one commit accepted by `just drv-diff <parent> <commit> openspec/changes/name-the-parts-of-base-and-ai/drv-delta-<step>.txt`, which names exactly the attributes D5 lists. Every changed toplevel and home is then judged by `openspec/changes/name-the-parts-of-base-and-ai/drv-order-trace.py <before.drv> <after.drv>`, committed with this change, which follows `nix-stock derivation show` down the changed inputs. A difference is accepted only if it is one of:
  - (a) the order of `structuredAttrs.chosenOutputs`, holding the same entries, in a build named `system-path`, `system-applications`, `home-manager-path`, `home-manager-fonts` or `home-manager-applications`;
  - (b) the order of `structuredAttrs.value.keybindings.prs` in `gh-dash-config.yml`, holding exactly the three bindings measured (`m` "enqueue", `M` "enqueue stack", `C` "code review");
  - a derivation whose own fields are equal once its changed inputs' paths are substituted.

  Every other differing field at a leaf (an activation snippet, shell init text, a `nix.conf` list, PATH words, any other list or string, even when it holds the same entries or words), any input present on one side only and any pair of same-named inputs the tool cannot match stops the pull request and is reported as an open question; it is never added to an allow-list. A drv-diff difference outside the allow-list goes through the same tool: it is added to the allow-list only when every leaf it reaches is (a) or (b), with the tool's output as its reason.

  Beside the derivations, each changed configuration's list options are recorded before and after: `environment.systemPackages` and `home.packages` keep their members, and on the Macs `users.knownUsers`, `users.knownGroups` and every uid and gid are equal.

  Before the pull request lands, every build the tool reports under (a) is built at the parent and at the commit, and the `readlink` target of every symlink in the two outputs, listed without following links, is compared: the same paths with the same targets are required. Building realizes every member, so `bind` and `go-containerregistry`, absent from the store when this was planned, are covered. Live hosts are not compared: a host's running generation is not the pull request's parent, and a deploy carries whatever else has landed.
- **Rationale**: the allow-list says which attributes move; the tool says how, accepting only the two kinds of reorder measured (Context), so a reordered activation snippet or configuration file cannot pass as "the same lines"; the built-profile comparison shows what the reordered profiles link (A376). nix-darwin deletes an account in `users.knownUsers` that is no longer declared (A377), so the account and group sets and ids are compared before any Mac is deployed.
- **Alternatives considered**: drvPath identity (not achievable, Context); `may-change` entries (would accept a difference nobody looked at); treating any permutation of a list's entries or a string's words or lines as order only (would pass reordered activation snippets, shell init or PATH); comparing live hosts (compares against the wrong generation).

### D5: Three pull requests, each with an exact allow-list
- **Choice**:

| Pull request | Changes | Allow-list (`drv-delta-<step>.txt`) | Deploy |
|---|---|---|---|
| 1 `nixos-base` | NixOS list, its parts, the structure check | `checks.x86_64-linux.structure-aspect-parts added`, `checks.x86_64-linux.fleet-alert changed` (it renders every `testSizes.checks` entry) | none |
| 2 `darwin-base` | darwin list, its parts, `base-essentials`, the check covers darwin `base` | `darwin.{argentum,blackphos,rosegold,stibnite} changed`, `checks.aarch64-darwin.darwin-{argentum,blackphos,rosegold,stibnite} changed` | the four Macs (after 3) |
| 3 `ai` | ai list, its parts, `atomic`'s names, the check covers `ai` | `nixos.{cinnabar,electrum,galena,magnetite,pyrite,scheelite} changed`, `darwin.{argentum,blackphos,rosegold,stibnite} changed`, `home."{cameron,crs58}@{aarch64-darwin,aarch64-linux,x86_64-linux}" changed`, `checks.x86_64-linux.nixos-{cinnabar,electrum,galena,magnetite,pyrite} changed`, `checks.aarch64-darwin.darwin-{argentum,blackphos,rosegold,stibnite} changed`, `checks.{x86_64-linux,aarch64-darwin}.home-manager-crs58 changed` | all ten hosts and the reached standalone homes |

  The check's drvPath does not change in 2 and 3: its value is a structural comparison whose expected and actual values stay the empty list.
- **Rationale**: one aspect per comparison keeps each allow-list readable and each reorder attributable; the NixOS step lands with nothing to deploy. Deploying after 3 reaches each Mac once instead of twice.
- **Alternatives considered**: one pull request (one allow-list mixing three causes); deploying the Macs after 2 (a second deploy of each Mac after 3).

### D6: The structure check, and how a later contributor adds a part
- **Choice**: a contributor adds a part by defining `flake.modules.<class>.base-<concern>` (or `ai-<harness>`) in one file and adding the name to that class's list; the list is the registration. `checks.x86_64-linux.structure-aspect-parts` (`modules/checks/structure/aspect-parts.nix`, `self.lib.mkStructuralCheck`, `expected = [ ]`) fails, naming each violation, when (1) one of the three aspects has a definition from any file other than its list file; (2) a listed part has definitions from more than one file, except the parts built from several files on purpose, each listed in the check with its files and failing when its definitions come from any other set: `base-system-defaults` (the nine `darwin/system-defaults/*.nix`) and `ai-claude-code` (`claude-code/{default,ccstatusline-settings,hooks,mcp-servers,wrappers}.nix`); or (3) a module named with the aspect's prefix (`base-` in `nixos` and `darwin`, `ai-` in `homeManager`) is in no list; `ai-skills` and `ai-skills-compose` are exempt by name because `ai-capabilities` imports them. Definitions are read from the `_file` of each merged definition in the flake's `modules` output (A375). `testSizes.checks.structure-aspect-parts = { class = "small"; measured = false; }`.
- **Rationale**: (1) catches a file assigning into `base` or `ai` directly; (2) catches a file assigning into an existing part, which import-tree would merge just as silently and which would make that part's membership implicit; (3) catches a part that was named and never listed. Together they keep "no other statement adds to them" true. The check reads module values and three lists: no nixpkgs instance, nothing built, so `small`. Its name is a literal and only its value reads the modules, so the `checks.x86_64-linux` key set gains nothing strict. Rule (2) also covers the existing named modules a list names (`secrets`, `mesh-hosts`, ...); task 2.3 records each one's definition files, and one with more than one file is an open question, not an exemption.
- **Mutants**: in a throwaway tree, a file adding `flake.modules.nixos.base = { }` fails naming that file; a second file assigning `flake.modules.nixos.base-zram-swap = { }` fails naming that file and `base-zram-swap`; `base-zram-swap` removed from `nixosBaseParts` fails naming it; a tenth file assigning into `base-system-defaults` fails naming it.
- **Alternatives considered**: a source grep for `modules.<class>.base` (misses `flake.modules = { nixos.base = …; }` and `nixos // { base.imports = …; }`, both in use today); no check (the next file would make membership implicit again).

### D7: Deploy plan
- **Choice**: no deploy after 1. After 3 lands, with 2 below it, the operator deploys the ten hosts and activates the standalone `crs58@*` and `cameron@*` homes that are in use; each deploy checks that the host runs the system its branch evaluates to (`readlink /run/current-system` equals the evaluated toplevel's `outPath`), shows no `deleting user` or `deleting group` line on a Mac, and reads every alert posted since it started. A Mac activated between 2 and 3 loses nothing: each comparison was made on built profiles before its pull request landed; that Mac is deployed again after 3.
- **Rationale**: a host reached by 2 and 3 is deployed once; integrated homes ride their host's deploy.
- **Boundary**: source-versus-delivered: until a host is deployed, it runs the old order, which has the same members.

## Risks / Trade-offs

- [Risk] A moved member shares a subpath with another member at equal priority, and the reorder changes which file a profile links (A376). → Mitigation: measured none for the moved members present locally; the built-profile comparison before each pull request lands (D4) covers every member; a difference stops the pull request and becomes an open question.
- [Risk] A check outside the 21 measured ones embeds a reordered derivation, and drv-diff reports it. → Mitigation: judged by `drv-order-trace.py`; added to that step's allow-list only when every leaf it reaches is (a) or (b) of D4.
- [Risk] A file assigning into `base` or `ai` is added between planning and apply. → Mitigation: task 1.1 retakes the inventory at each parent; the structure check fails on any such file after 1 lands.
- [Trade-off] Ten deploys and up to six home activations buy no behaviour change; they buy aspects that can be read and taken in part. → Accepted (D1).
- [Risk] A Mac's deploy deletes an account. → Mitigation: `users.knownUsers`, `users.knownGroups`, uids and gids measured equal on every Mac (A377), and re-measured at apply (tasks 3.3 and 4.3).

## Migration Plan

1. Land 1 (`nixos-base`): `just drv-diff` against `drv-delta-nixos-base.txt`; nothing to deploy.
2. Land 2 (`darwin-base`) against `drv-delta-darwin-base.txt`, with the before and after lists recorded.
3. Land 3 (`ai`) against `drv-delta-ai.txt`, with the before and after lists recorded.
4. **[operator]** Deploy cinnabar, electrum, galena, magnetite, pyrite and scheelite, then stibnite, blackphos, argentum and rosegold; activate each standalone `crs58@*` or `cameron@*` home in use.
5. Rollback: revert the pull request and redeploy, or roll a host back to its previous generation; the members of every list are the same either way.

## Open Questions

1. Which standalone homes among `crs58@{aarch64-darwin,aarch64-linux,x86_64-linux}` and `cameron@{...}` are activated on some machine today, and where? Their activation task (5.4) names only those; the integrated homes ride the host deploys.
