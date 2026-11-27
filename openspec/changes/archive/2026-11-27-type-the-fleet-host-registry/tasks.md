The change lands after stop-reading-other-hosts-configs (whose tip is its parent) as one pull request of one commit: the task groups are not separately shippable, and a drvPath diff costs about 15 minutes. Each group keeps its own evidence by evaluation against the 1.2 baselines, and `just drv-diff` runs once, from the parent to the commit (task 5.5), and again at the merged head (task 8.1).
Verification is by evaluation (`nix eval`), by building the named checks (`nix build`), or by reading cinnabar after its deploy; each task says which. Reading the source is never the verification for a nix-managed output.
Size classes follow `references/test-sizes.md` of the `preferences-nix-checks-architecture` skill. A run expected to exceed 5 minutes is announced first with its expected duration, what it proves and what waits on it.
**[operator]** marks a task that waits on the operator.

## 1. Baseline

- [x] 1.1 Confirm establish-refactor-oracle and stop-reading-other-hosts-configs have landed and this change's chain is parented on the latter's tip; read `just drv-diff`'s usage and its base allow-list — verify: the parent revision's `modules/lib/host-keys.nix` holds the literal `nixosKeyHosts` list; `justfile`'s `drv-diff` recipe and `modules/apps/drv-diff-base-allow.txt` read
- [x] 1.2 Record the comparison baselines at the parent revision by evaluation:
  - `nix eval --json .#lib.hosts` projected to the eleven prior fields;
  - `.#lib.machineSystems`;
  - `.#clan.inventory.machines` projected to `machineClass` and `deploy`;
  - the cinnabar controller's `allowedIps`;
  - the tincr peer names;
  - every member's `memoryGiB`;
  - `checks.x86_64-linux` and `checks.aarch64-darwin` attribute names;
  - the `observabilityHosts` platforms.

  Also measure the cold evaluation of `checks.x86_64-linux` attribute names (`NIX_SHOW_STATS`, fresh process, three runs) — verify: `logs/thr-1-baseline-<ts>.json` and `logs/thr-1-keyset-cost-<ts>.log`

## 2. The typed record and its alias (design D1, D9)

- [x] 2.1 In `modules/lib/hosts.nix`, declare `options.flake.fleet.hosts` with the fields of design D1, including `system`, `checked` and `stateVersion`. Move the twelve members' values into it, with `system` from `clan/inventory/machines.nix:10-21` and null for `pixel7` and `pixel11`. Copy `stateVersion` from `darwin/laptop.nix:72`, `machines/darwin/{blackphos:63,stibnite:79}`, `machines/nixos/{cinnabar:59,electrum:58,galena:56,scheelite:60,magnetite:155,pyrite:160}`. Set `checked = false` for scheelite. Replace the header comment's one-file rationale — verify: `nix eval --json .#fleet.hosts --apply builtins.attrNames` lists the twelve members
- [x] 2.2 Implement the read-only fields `class`, `fqdn`, `address`, `targetHost`, `memoryGiB` (declared memory only for now) and the class-dependent `throw`s on `memoryGiB`, `nixClassic` and `stateVersion` — verify: by evaluation, for every member, each read-only field equals the baseline from 1.2; `stateVersion` reads 4 on the darwin hosts, the release strings on NixOS and null on the phones
- [x] 2.3 Set `flake.lib.hosts = config.flake.fleet.hosts` and delete the old `hosts` let-binding and the three cross-table asserts at `hosts.nix:196-205` — verify: the alias projection from 1.2 is equal to its baseline (JSON diff empty)
- [x] 2.4 Mutants (small): in a throwaway tree, run each of the following and observe its failure:
  - `memory = 0` on pyrite;
  - `stateVersion = "4"` on stibnite;
  - `nixClassic = true` on cinnabar, which has no primary user;
  - `primaryUser = "nobody"`.

  — verify: each fails evaluation naming the host; `builtins.tryEval` of pyrite's `memoryGiB` under the first mutant returns `success = false`; log in `logs/thr-2-mutants-<ts>.log`

## 3. Derive system, class and the composition seam (design D2, D3, D4)

- [x] 3.1 Define `flake.lib.machineSystems` in `hosts.nix` from the record (non-null `system` only) and delete its literal in `clan/inventory/machines.nix` — verify: by evaluation, equal to the 1.2 baseline
- [x] 3.2 Generate `machineClass`, and `deploy.targetHost` for NixOS entries only, in `clan/inventory/machines.nix`, keeping each host's literal `tags` and `description` — verify: the inventory projection from 1.2 is equal to its baseline, with no darwin entry having `deploy`; `checks.x86_64-linux.network-target-obligations` builds
- [x] 3.3 Generate `flake.clan.machines` from the record with `imports` and `nixpkgs.hostPlatform`. Delete the nine `nixpkgs.hostPlatform` lines in `machines/nixos/{cinnabar,electrum,galena,scheelite,magnetite,pyrite}/default.nix`, `machines/darwin/{blackphos,stibnite}/default.nix` and `darwin/laptop.nix` — verify: `rg -n 'nixpkgs.hostPlatform =' modules/machines modules/darwin/laptop.nix` is empty; by evaluation, each configuration's `nixpkgs.hostPlatform.system` equals its baseline system
- [x] 3.4 Replace the seven `hasSuffix "-darwin"` host tests:
  - `checks/machines.nix:63,67`
  - `lib/commit-signing.nix:188`
  - `lib/omnigent-fleet-obligations.nix:179`
  - `system/deploy-record.nix:148`
  - `system/harmonia-gc.nix:79`
  - `system/mesh-hosts.nix:84`

  Each becomes `hosts.${name}.class == "darwin"`. Drop the `machineSystems` inherit in `mesh-hosts.nix` if nothing else uses it — verify: `rg -n 'hasSuffix "-darwin"' modules` lists only `lib/hosts.nix` and `containers/default.nix`
- [x] 3.5 Set each `observabilityHosts` row's `platform` from `config.flake.fleet.hosts.<name>.class`, leaving the `agent` helper's shape for VM-test rows unchanged. Delete the `mismatched` assert in `clan/inventory/services/otel-collector.nix` and update its header comment — verify: by evaluation, the platforms equal the 1.2 baseline; `checks.x86_64-linux.fleet-alert` and `otel-collector-config` build
- [x] 3.6 In `modules/lib/host-keys.nix` (added by stop-reading-other-hosts-configs), replace the literal `nixosKeyHosts` list with the names of the `flake.fleet.hosts` entries whose `class` is `nixos` (design D11) — verify: by evaluation, `builtins.attrNames flake.lib.hostKeys` equals its parent-revision value; `rg -n 'nixosKeyHosts = \[' modules` finds nothing
- [x] 3.7 Keep every assert in `checks/machines.nix:100-123`, including the `machineSystems`-vs-inventory and `clan.machines`-vs-inventory name asserts (design D4); only the owners assert's `deferred` test changes, in task 4.3 — verify: the `checks.x86_64-linux` and `checks.aarch64-darwin` attribute names equal the baseline; `rg -c 'assert lib.assertMsg' modules/checks/machines.nix` gives the parent revision's count
- [x] 3.8 Mutants (small, throwaway tree):
  - flip one NixOS host's `system` to `aarch64-darwin` and build `structure-fleet`;
  - add a NixOS record with no inventory entry and evaluate `checks.x86_64-linux` names;
  - add a NixOS record and its inventory entry with no machine directory and evaluate `checks.x86_64-linux` names.

  — verify: each fails evaluation with the `readDir` directory assert's message (`modules/machines/nixos/ directories must match the NixOS inventory machines`). clan-core adds every `flake.clan.machines` name to the inventory (`modules/clan/module.nix:151`, revision 78d5de23), so the record without an inventory entry still appears in it and the name asserts pass, and the machine-check asserts guard the whole `checks` set, so the flip fails there before `structure-fleet` compares (design D4); `logs/thr-3-mutants-<ts>.log`
- [x] 3.9 Re-measure the key-set cost — verify: the cost is within the run-to-run spread of the 1.2 baseline; `logs/thr-3-keyset-cost-<ts>.log`

## 4. Lifecycle, cloud and memory (design D5, D6)

- [x] 4.1 Add the read-only `enrolled` field (`builtins.pathExists (self + "/sops/machines/${name}")`, reading the committed flake source) and `cloud` (from `flake.lib.cloudMachines`, `type` = `serverType` or `machineType`) — verify: by evaluation, `enrolled` is false for blackphos, pixel7 and pixel11 and true for the other nine; `cloud` is non-null for cinnabar, electrum, galena, magnetite and scheelite, with `enabled` matching `cloud-machines.nix`
- [x] 4.2 Add `flake.lib.cloudMachineMemoryGiB`, derive a cloud host's `memoryGiB` from it, and delete the five cloud literals at `hosts.nix:168-172` — verify: every member's `memoryGiB` equals the 1.2 baseline; a throwaway mutant giving cinnabar `serverType = "cx99"` fails naming `cx99`
- [x] 4.3 Replace `deferred` in `checks/machines.nix`, both the machine-check filter and the omnigent owners assert, with `checked` — verify: `checks.x86_64-linux` names equal the baseline, with `nixos-electrum` and `nixos-galena` present and `nixos-scheelite` absent
- [x] 4.4 Replace tincr's `name != "blackphos"` with `host.enrolled` and update its header comment and `observability-hosts.nix:152`'s comment — verify: by evaluation, the tincr peer names equal the baseline
- [x] 4.5 Have `lib/fleet-deployer.nix`'s `enabledOf` read `hosts.${name}.cloud.enabled` (true when `cloud` is null). Leave `excluded` and `commitSigningLegacyMachines` where they are — verify: by evaluation, `flake.lib.fleetDeployer.targets` and `problems` equal their parent-revision values; `checks.x86_64-linux.fleet-deployer-obligations` builds
- [x] 4.6 Build `checks.x86_64-linux.nix-eval-jobs-iets` (small) — verify: it succeeds, so `unclassifiedIets` is still reported for blackphos

## 5. Role membership, ZeroTier admission and the stibnite tag (design D7, D8, D12)

- [x] 5.1 Add `modules/lib/inventory-members.nix` with `flake.lib.inventoryMembers` and `inventoryMembersIn`, plus its evaluation test covering:
  - named members;
  - tagged members;
  - `all`;
  - a role with neither (empty result);
  - de-duplication.

  — verify: the new evaluation check builds; a mutant that ignores `all` fails it
- [x] 5.2 Use the resolver in `lib/fleet-topology.nix` (`membersOf`), `checks/zerotier-mss-clamp.nix`, `checks/zerotierone-controller.nix` and `apps/omnigent-worker-login.nix`. The last asserts exactly one member named in `.machines`. Add `inventoryMembersIn` to the `config.flake.lib` stub in `lib/fleet-topology.test.nix` — verify: `checks.x86_64-linux.{eval-fleet-topology,fleet-topology-fresh,zerotier-mss-clamp}` and the `zerotierone-controller-*` checks build; `nix eval .#apps.x86_64-linux.omnigent-worker-login.program` succeeds
- [x] 5.3 Derive the cinnabar controller's `allowedIps` from class in `clan/inventory/services/zerotier.nix` — verify: by evaluation, the list holds the same six addresses as the baseline, in name order
- [x] 5.4 Rename stibnite's inventory tag `controller` to `deployer-workstation` in `modules/clan/inventory/machines.nix`, keeping cinnabar's `controller` (design D12). Regenerate the fleet map with `just topology-generate` — verify: `nix eval --json .#clan.inventory.machines.stibnite.tags` lists `deployer-workstation` and not `controller`; by evaluation, the inventory machines carrying `controller` are exactly `[ "cinnabar" ]`; `rg -n '"controller"' modules/clan/inventory/machines.nix` finds only cinnabar's line; the committed `fleet.json` differs from its parent only in stibnite's `tags`; `checks.x86_64-linux.fleet-topology-fresh` builds
- [x] 5.5 Run `just drv-diff <parent> <the commit> openspec/changes/type-the-fleet-host-registry/drv-delta.txt` once over the change's single commit (design D10: `nixos.cinnabar`, `checks.x86_64-linux.nixos-cinnabar`, `checks.x86_64-linux.eval-fleet-topology`, `checks.x86_64-linux.fleet-topology-fresh`, `checks.x86_64-linux.fleet-alert` and the checks that build or consume the docs package changed; `checks.x86_64-linux.eval-inventory-members` added) — verify: exit 0; `logs/thr-5-drv-diff-<ts>.log`
  - Done 2026-11-27 from `07e3f1affe2d` (main) to `66c5a7768fc5` in 978.0 s; evidence `logs/drv-diff-07e3f1affe2d-66c5a7768fc5-20261127T055715Z` (run log `logs/thr-drv-diff-20261127-005713.log`). The first judgement failed on 29 undeclared check differences, each traced with `nix derivation show`: the 24 docs-package checks, `agent-skills-index` and `deploy-docs-rehearsal` (`fleet.json` is docs-package source), `apps-build` on both systems (only through its `deploy-docs` input; the edited `omnigent-worker-login` app's derivation is unchanged) and `fleet-alert` (its size-rule clause renders every `testSizes.checks` entry). They are declared in `drv-delta.txt`, and the re-judgement of the same dumps passes (`report.20261127T061438Z`): nixos 5 identical and cinnabar changed; darwin 4, home 20 and all 24 vmTests identical. The commit was then rewritten for its description only; its tree differs from `66c5a7768fc5` only in `drv-delta.txt`.

## 6. Documents

- [x] 6.1 Update `modules/README.md`'s description of the host registry, its `memoryGiB` paragraph (:51) and any statement that the registry is one raw file. Check ADR-0019 (:70-75) and ADR-0020 (:116-121), which place `hostPlatform` in `clan.machines`. This change makes that true again, so add no amendment unless their wording still differs — verify: `prek run --files` on every changed document passes
  - Done: the `modules/README.md` edit is in main `9055ae0f1333` (#4386); `prek` (gitleaks, treefmt) passed on every file of the commit before publishing. ADR-0019 (:70-75) and ADR-0020 (:116-121) show `clan.machines.<name>` setting `nixpkgs.hostPlatform` and importing `machines/<class>/<name>`; at `9055ae0f1333`, `modules/clan/machines.nix` generates exactly that from `flake.fleet.hosts` (`imports` and `nixpkgs.hostPlatform = h.system`), so their wording holds and no amendment is added.

## 7. Deploy

- [x] 7.1 After the pull request merges, deploy cinnabar with `clan machines update cinnabar` — verify: the deploy log in `logs/thr-7-cinnabar-deploy-<ts>.log`; every post on the fleet alert and failure topics since the deploy began is read and each is explained in the log
  - Done 2026-11-27: `clan machines update cinnabar` pinned to main `9055ae0f1333`, start 07:00:25Z, clan exit 0 at 07:03:31Z; closure `3r6nw4b8…` → `9iwn1g18…` (main's cinnabar toplevel); `systemctl is-system-running` = running, no failed units, deploy record 07:03:15Z. The first read-back failed with "Network is unreachable" while `tincr-vanixiets` restarted; reachable 9 s after activation (07:03:40Z). Nothing was posted to `fleet-alerts` or `fleet-deploy` in the 30 minutes around the deploy. cinnabar had run a closure from 2026-11-24, so this deploy also applied other merged work: the new `zpool-probe` timer, `prometheus-node-exporter` and `opentelemetry-collector` restarts, `tincr-vanixiets` and `hermes-agent` restarts and package updates. Log `logs/thr-7-cinnabar-deploy-20261127-020025.log`
- [x] 7.2 Read the controller's admitted members on cinnabar — verify: the list the controller's authorisation script holds, or the controller's member list via `zerotier-cli`, contains the six external addresses; `logs/thr-7-controller-<ts>.log`
  - Done 2026-11-27: the controller's authorisation script holds 12 addresses, and its member list shows all 12 fleet members authorized, including the six external ones (argentum `f754d5ad7e`, blackphos `0ee971d9e0`, pixel11 `3c89999bb8`, pixel7 `9fc45d577c`, rosegold `1534310ee8`, stibnite `2419d93451`); the four other member ids on the controller are unauthorized and are not fleet members. Log `logs/thr-7-controller-20261127-020351.log`

## 8. Integration Verification

- [x] 8.1 Verify the whole change against the parent revision: `just drv-diff <parent> <merged head> openspec/changes/type-the-fleet-host-registry/drv-delta.txt` — verify: exit 0; `logs/thr-8-drv-diff-<ts>.log`
  - Done 2026-11-27: `just drv-diff 07e3f1affe2d 9055ae0f1333 …/drv-delta.txt` PASS, exit 0, 934.8 s; nixos 5 identical and cinnabar changed, darwin 4, home 20, vmTests 21 + 3 identical; checks x86_64-linux 22 changed and 1 added (`eval-inventory-members`), aarch64-darwin 15 changed, every one declared or base-allowed; no entry failed to occur. Evidence `logs/drv-diff-07e3f1affe2d-9055ae0f1333-20261127T063647Z`, log `logs/thr-8-drv-diff-20261127-013645.log`
- [x] 8.2 Verify that every value the record now derives equals its baseline from 1.2 — verify: all JSON projections from 1.2 diffed at the merged head, empty except `allowedIps` order
  - Done 2026-11-27: the 1.2 projections evaluated with `nix-stock eval --impure` against `getFlake` at main `9055ae0f1333` and diffed key by key with the baseline: hosts (eleven prior fields incl. `memoryGiB`), `machineSystems`, `hostKeys`, tincr peers, `observabilityHosts` platforms, `fleetDeployer` and `checks.aarch64-darwin` names equal; `allowedIps` the same six addresses in name order; inventory differs only in stibnite's tag (`controller` → `deployer-workstation`, task 5.4), machines tagged `controller` = `["cinnabar"]`; `checks.x86_64-linux` names are the baseline plus `eval-inventory-members` (task 5.1). Log `logs/thr-8-projections-20261127T070505Z.log`
- [x] 8.3 Verify that no migration flag or one-shot conditional remains — verify: this change adds none; `rg -n 'deferred = \[|machineSystems = \{|name != "blackphos"|nixosKeyHosts = \[' modules` finds nothing
  - Done 2026-11-27: the `rg` over `modules` exits 1 with no match, and `git grep` of the same pattern at `9055ae0f1333 -- modules` also finds nothing
