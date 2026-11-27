# Compose each fleet host from cohesive aspects Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development
> to implement this plan task-by-task.

**Goal:** Restructure every host's composition into named, reusable aspects in seven separately accepted commits, of which only the last changes any host (the four Macs' `nix.conf`).

**Architecture:** Each commit moves one kind of statement out of host bodies into aspects or `flake.lib` data (design D1-D11), reproducing today's merge order so derivations stay equal, and is accepted on its own `just drv-diff` with an exact allow-list (D12, D13). Specs: `specs/host-composition` (behavioral), `specs/host-composition-interface`, the two modified interfaces and `specs/world-assumptions` (A350-A359).

**Tech Stack:** Nix flake-parts with import-tree, NixOS, nix-darwin, home-manager, clan-core, srvos; `just drv-diff`, `just drv-diff-rejudge`, `just eval-cost`, `nix-diff`.

**Grounding.** Design Context, read on main at `302236090`. Lines in `modules/machines/nixos/magnetite/default.nix`, `modules/nixos/{omnigraph-backup,postgresql-backup}.nix`, `modules/lib/observability-hosts.nix` and `modules/{nixos,darwin,system}/shared-reference-tree.nix` are valid only at the time of writing: another session is landing commits to them, and Task 0 re-reads them. This plan configures no vendored consumer (no collector, exporter or probe argument list changes), so no consumer argument list is recorded.

**Version control.** The working copy is a shared development join: the implementer runs no mutating `jj`/`git` command without the operator's go-ahead and routes each commit into its chain as the operator directs. New files are announced to the operator before any evaluation reads them.

**Commits and the other session's files.**

| Commit | Tasks | Touches the other session's files | Lands |
|---|---|---|---|
| 1 otel-collector split | 2 | no | any time |
| 2 cinnabar keys | 3 | no | any time |
| 3 provider/workstation aspects, state versions, host facts | 4 | magnetite `default.nix` | after that session's commits land; rebased onto them |
| 4 server aspects, ZFS table | 5 | magnetite `default.nix`, `lib/observability-hosts.nix` | after them |
| 5 flags deleted | 6 | magnetite `default.nix`, `{nixos,darwin,system}/shared-reference-tree.nix` | after them |
| 6 identity, today's activation order | 7 | no | any time after commit 1 |
| 6b deploy record last (planned, not started; design Open Question 9) | 7b | no | after 6, before 7; host-changing, deploys the four Macs |
| 7 darwin caches | 8 | no | last |

---

## Task 0: Re-read the files another session edits (tasks.md 0.1)

- [ ] **Step 1:** Confirm on main that the other session's four commits to magnetite, the backup modules and `observability-hosts.nix`, and any to the reference-tree modules, have landed: `jj log -r 'main' -n 10` (read-only).
- [ ] **Step 2:** For each file, `rg -n` the anchors design Context cites (`greptimedbDataset`, `services.omnigraph = {`, `services.greptimedb = {`, `assertions =`, `services.fleet-alert.evaluator`, `zramSwap.memoryPercent`, `10-uplink`, `MaxAuthTries`, `systemd.services.zfs-`, `onlyWithLocalRoot`, `services.shared-reference-tree`) and write `logs/chca-0-reread-<ts>.md` with old and new ranges.
- [ ] **Step 3:** Correct design.md's Context and this plan's line references; if the other session changed what a range does (not only where it is), stop and report to the operator before group 3.

## Task 1: Baseline (tasks.md 1.1-1.7)

- [ ] **Step 1:** Record the parent: `jj log -r @- --no-graph -T commit_id > logs/chca-1-parent-<n>-<ts>.txt`.
- [ ] **Step 2:** Write `logs/chca-1-baseline.nix`'s projection as `nix eval --json --apply` calls (one process per host) over `.#nixosConfigurations.<h>.config` and `.#darwinConfigurations.<h>.config` for the options listed in task 1.2; collect into `logs/chca-1-baseline-<ts>.json`; re-run once and `diff` (empty).
- [ ] **Step 3:** Activation order: `nix eval --raw .#darwinConfigurations.<h>.config.system.activationScripts.postActivation.text > logs/chca-1-postact-<h>.txt` for the four Macs; `rg -n 'resolver|Keychain|fleet-services|dnscrypt|casks|deploy-record' ` each; confirm fleet-services-trust < dnscrypt-proxy < casks < record where present.
- [ ] **Step 4:** Caches: `nix eval --json .#darwinConfigurations.<h>.config.nix.settings --apply 's: { inherit (s) substituters trusted-public-keys; }'` for the four; build stibnite's `nix.conf` (`nix build .#darwinConfigurations.stibnite.config.environment.etc."nix/nix.conf".source`) and `grep -E '^(substituters|trusted-public-keys) =' result`; quote under design D10.
- [ ] **Step 5:** Source reads for A350-A356 at the locked revisions (store paths from `flake.lock` narHashes); write `logs/chca-1-sources-<ts>.md`; fill each Evidence line.
- [ ] **Step 6:** `just eval-cost checks.x86_64-linux <parent> <parent> 2 keys` and the same for `checks.aarch64-darwin`; record the spread.
- [ ] **Step 7:** Obtain the operator's answers to Open Questions 1-8; record them under Resolved Questions in design.md.

## Task 2: Commit 1, the otel-collector split (tasks.md 2.1-2.4)

- [ ] **Step 1:** Create `modules/clan/services/otel-collector/_shared.nix` as a function `{ config, lib }: { … }` returning the bindings of `flake-module.nix:33-236`; announce it.
- [ ] **Step 2:** Create `agent.nix` (`flake.modules.nixos.otel-collector-agent`, the body of `:239-1065`), `ingress.nix` (`:1066-1378`, with the `forward` connector) and `service.nix` (`flake.clan.modules.otel-collector`, `:1379-`), each `let s = import ./_shared.nix { inherit config lib; }; in`; announce them; delete `flake-module.nix`.
- [ ] **Step 3:** `nix eval` the two `modules.nixos` names and `clan.modules.otel-collector` (task 2.1); `nix build .#checks.x86_64-linux.otel-collector-config`.
- [ ] **Step 4:** Compare `vmTests.x86_64-linux.{devloop-ingest,fleet-ingress,greptimedb-pipeline}` drvPaths and the six NixOS toplevels with the baseline (`nix eval --raw .#…drvPath`).
- [ ] **Step 5:** Write `drv-delta-1.txt` (header only); return `just drv-diff <parent> <commit-1> openspec/changes/compose-hosts-from-cohesive-aspects/drv-delta-1.txt` to the operator.

## Task 3: Commit 2, cinnabar keys (tasks.md 3.1-3.4)

- [ ] **Step 1:** `rg -n 'flake\.modules\.nixos\.(caddy|caddy-root-ca|caddy-root-check|fleet-alert-deadman|matrix-server|ntfy-server|radicle-node|zt-dns-server)\b' modules` finds nothing (keys free).
- [ ] **Step 2:** In each feature file replace `flake.modules.nixos."machines/nixos/cinnabar" =` with its key; in `default.nix` add the eight to the imports, in import-tree path order (`caddy-root-ca`, `caddy-root-check`, `caddy`, `fleet-alert`, `matrix`, `ntfy`, `radicle`, `zt-dns`).
- [ ] **Step 3:** `nix eval --raw .#nixosConfigurations.cinnabar.config.system.build.toplevel.drvPath`; on a difference, `nix run nixpkgs#nix-diff -- <before> <after>`, find the reordered list, and fix with import order or `lib.mkAfter`; repeat until equal.
- [ ] **Step 4:** `nix build .#checks.x86_64-linux.nixos-cinnabar`; evaluate `vmTests.x86_64-linux.caddy-root-from-vars`'s drvPath.
- [ ] **Step 5:** `drv-delta-2.txt` (header only); return the drv-diff command.

## Task 4: Commit 3, provider and workstation aspects, state versions, host facts (tasks.md 4.1-4.6)

- [ ] **Step 1:** Run Task 0 again at the rebased parent.
- [ ] **Step 2:** Create `modules/nixos/hetzner-cloud.nix` and `modules/nixos/gcp-cloud.nix` (announce), each with the D3 body and `assertions = [{ assertion = (hosts.${config.networking.hostName}.cloud.provider or null) == "<provider>"; message = "…"; }]` (provider strings as `flake.lib.cloudMachines` spells them, read first).
- [ ] **Step 3:** Edit cinnabar, electrum, magnetite, galena, scheelite: import the aspect, delete `devNodes`, `10-uplink`, the srvos Hetzner import; electrum/galena/scheelite `grub.enable = false` plain. Add `MaxAuthTries = 20` to a `nixos.base` contributor; delete the six host lines.
- [ ] **Step 4:** Evaluate the task 1.2 NixOS projections; equal. Run the electrum mutant in a throwaway tree (`jj workspace` is the operator's call; else a `git worktree`-free copy under `/tmp`), log it.
- [ ] **Step 5:** `darwin/base.nix`: `system.stateVersion = hosts.${config.networking.hostName}.stateVersion;` (and the NixOS base per Open Question 4); delete the host lines; reword the registry description and the nixbld comment; `zram-swap.nix` `lib.mkDefault 100`, magnetite `150` plain. Evaluate stateVersion, `ids.gids.nixbld`, `zramSwap.memoryPercent`; build `magnetite-zram-headroom`.
- [ ] **Step 6:** Move `darwin/laptop.nix` to `darwin/darwin-workstation.nix` with plain `mv` (announce the new path); rename the key; add the users/knownUsers generator over the attachments, primary-then-admin order; import from all four Macs; reduce blackphos and stibnite; move dnscrypt-proxy settings into argentum and rosegold. Evaluate the 4.4 projections; on a `knownUsers` order difference, fix the generator's order.
- [ ] **Step 7:** Compare all ten toplevels and every home with the baseline.
- [ ] **Step 8:** `drv-delta-3.txt` (header only, or the docs-package checks per Open Question 7, re-read with `nix derivation show` on each `package-vanixiets-docs*`, `apps-build`, `agent-skills-index`, `deploy-docs-rehearsal`); return the drv-diff command.

## Task 5: Commit 4, server aspects and the ZFS table (tasks.md 5.1-5.6)

- [ ] **Step 1:** Run Task 0 again at the rebased parent.
- [ ] **Step 2:** Create the four `modules/nixos/<svc>-server.nix` (announce); move each block from magnetite's body; for every list the body still also extends (`LoadCredential`, `assertions`, firewall ports), check its order by evaluation against the baseline and add `lib.mkAfter` where the body's definition was last.
- [ ] **Step 3:** Evaluate the 5.1 projections; equal in order.
- [ ] **Step 4:** Create `modules/lib/zfs-boot-invariants.nix` (announce) with the fourteen entries copied from magnetite's units at the rebased parent; replace the units with the generator; point `greptimedbDataset` and the envelope variables at the table; in `lib/observability-hosts.nix` replace the fourteen literal `zfs-*` names with the table's, sorted into the list inside `onlyWithLocalRoot`.
- [ ] **Step 5:** For each unit, `nix eval --raw .#nixosConfigurations.magnetite.config.systemd.units."<unit>.service".unit.drvPath` against the baseline; evaluate `flake.lib.observabilityHosts.magnetite`; evaluate the `r2` override's units.
- [ ] **Step 6:** `nix build .#checks.x86_64-linux.{greptimedb-envelope,omnigraph-retired-roots,otel-collector-config,nixos-magnetite}`; run the `17G` mutant in the throwaway tree.
- [ ] **Step 7:** `drv-delta-4.txt` (header only); return the drv-diff command.

## Task 6: Commit 5, flags deleted (tasks.md 6.1-6.6)

- [ ] **Step 1:** Run Task 0 again at the rebased parent.
- [ ] **Step 2:** Delete each flag and its `mkIf` in the defining module (`config = lib.mkIf cfg.enable {…}` becomes `config = {…}`); delete the host settings; delete `darwin/profile.nix`; replace the probes.
- [ ] **Step 3:** Edit the five runtime tests; in `greptimedb-oom-order` import memory-pressure-guards unconditionally and add the assertion on magnetite's `config.services ? memoryPressureGuards`.
- [ ] **Step 4:** Content search (task 6.1); compare toplevels and homes with the baseline; build the three checks.
- [ ] **Step 5:** Evaluate each runtime test's drvPath before and after; write `drv-delta-5.txt` with those that differ as `changed`, each with its cause; return the drv-diff command; after the run, `just drv-diff-rejudge <dir> <allow>` if the allow-list was corrected.

## Task 7: Commit 6, identity and today's activation order (tasks.md 7.1-7.6)

- [x] **Step 1:** Add `flake.lib.exportAs` (`modules/lib/export-as.nix`, announced), keying the module itself (`lib.setFunctionArgs`), never by a wrapping import level (design Context, "Import depth"); convert the seven files; migrate the three `vanixiets#` keys; evaluate every home's activation drvPath.
- [x] **Step 2:** Add `flake.lib.activationOrder` beside `deployRecordObligations` at the values that reproduce today's order (resolver 500, record 1501, casks 1502, dnscrypt-proxy 1503, fleet-services-trust 1504; above sops-nix's 1500); replace the five `lib.mkAfter`/`lib.mkBefore` with `lib.mkOrder`; evaluate each Mac's `postActivation.text` and `diff` against task 1 Step 3's files (empty).
- **Step 3-4:** moved to Task 7b (the record-last rule, its case and mutant change hosts).
- **Step 5:** not done: named import lists change hosts and homes (design D11, Open Question 10).
- [x] **Step 6:** `drv-delta-module-identity.txt` with no entries; return the drv-diff command.

## Task 7b: Commit 6b, the deploy record last (planned, not started; design D8, Open Question 9)

- [ ] **Step 1:** Set `activationOrder.deployRecord` above every other `postActivation` contributor (1900); evaluate each Mac's `postActivation.text` and confirm the record's invocation is the last non-comment line before the relink, and that nothing else moved.
- [ ] **Step 2:** Extend `orderProblems` with the darwin "nothing between record and relink" rule; add `darwinSnippetAfterRecord`; `nix build .#checks.x86_64-linux.deploy-record-order`. No `testSizes` entry changes, so `fleet-alert` is unaffected.
- [ ] **Step 3:** Mutant on argentum in the throwaway tree (a `lib.mkOrder 2000` snippet): `checks.aarch64-darwin.darwin-argentum` fails evaluation naming `deployRecordObligations`; log it.
- [ ] **Step 4:** `drv-delta-record-last.txt`: `darwin.{argentum,blackphos,rosegold,stibnite}`, `checks.aarch64-darwin.darwin-{argentum,blackphos,rosegold,stibnite}` and `checks.x86_64-linux.deploy-record-order`, each `changed`; return the drv-diff command.
- [ ] **Step 5:** After merge, the operator deploys stibnite, then argentum and rosegold, then blackphos when online, and reads each Mac's activation output and the last line of `/var/log/deploy-record.jsonl`.

## Task 8: Commit 7, one copy of each darwin cache (tasks.md 8.1-8.6)

- [ ] **Step 1:** Delete `modules/darwin/caches.nix`; fix the comments naming it.
- [ ] **Step 2:** Evaluate each Mac's `nix.settings` lists; compare with task 1 Step 4 (second copy gone, nothing else).
- [ ] **Step 3:** Per Mac, `nix run nixpkgs#nix-diff -- $(cat baseline drv) $(nix eval --raw .#darwinConfigurations.<h>.config.system.build.toplevel.drvPath)`; log it.
- [ ] **Step 4:** Confirm the six NixOS toplevels are unchanged.
- [ ] **Step 5:** `drv-delta-7.txt`: `darwin.argentum`, `darwin.blackphos`, `darwin.rosegold`, `darwin.stibnite`, `checks.aarch64-darwin.darwin-argentum`, `checks.aarch64-darwin.darwin-blackphos`, `checks.aarch64-darwin.darwin-rosegold`, `checks.aarch64-darwin.darwin-stibnite`, each `changed` with its cause; return the drv-diff command.
- [ ] **Step 6:** Hand the operator the deploy runbook of design Migration Plan step 3 (stibnite, argentum and rosegold, blackphos when online) with the read-back of `/etc/nix/nix.conf` and the alert-topic read.

## Task 9: Integration (tasks.md 9.1-9.5)

- [ ] **Step 1:** Write `drv-delta.txt` as the union of the seven; return the full-range drv-diff command (task 9.1).
- [ ] **Step 2:** Run the content searches of 9.2 and 9.3.
- [ ] **Step 3:** Update header comments, `modules/README.md` and `docs/notes/development/architectural-principles.md`; run `treefmt --fail-on-change` over every new and edited file.
- [ ] **Step 4:** After merge, return the merged-head drv-diff command (task 9.5).
