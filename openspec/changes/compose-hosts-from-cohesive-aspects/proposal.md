---
linear_story_id: CAM-132
linear_story_identifier: CAM-132
linear_story_title: "Compose each fleet host from reusable, named building blocks"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-132/compose-each-fleet-host-from-reusable-named-building-blocks
linear_story_state: In Progress
linear_team: CAM
linear_project: den-ready-fleet
last_synced_state: In Progress
last_synced_at: "2026-11-27T15:49:31Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-26T23:01:01Z", transition: "Backlog->Todo", outcome: "posted", note: "Issue CAM-132 created in Todo in project 06049a4f18a4 (Den-ready fleet architecture), no label, with description seeded from proposal.md's Why and What Changes; state and project confirmed by read-only view" }
  - { at: "2026-11-26T23:21:27Z", transition: "Backlog->Todo", outcome: "posted", note: "bind comment was missing from the creation write; posted now (comment 3d7176b3) after a read-only view showed no comments" }
  - { at: "2026-11-27T15:49:31Z", transition: "Todo->In Progress", outcome: "posted", note: "fired on the first checked task (1.7); state confirmed In Progress by read-only view; comment 24c52d27" }
---

## Why

A host should read as the list of capabilities it runs plus what is particular to it. Today magnetite's body carries ~520 lines of service wiring, cinnabar's features can only be used by cinnabar, five cloud servers and two Macs copy their templates, host facts are written as `mkForce` fights against base, features are opted into twice, and the darwin deploy record is last only because of import order. Each of these makes a new host or service a copy-and-edit job and makes a later move to den a semantic rewrite instead of a mechanical one. Composing hosts from named, reusable aspects with explicit identity and order fixes that, and a before/after drvPath diff shows every step changes only what it declares.

## What Changes

**Service wiring leaves the host bodies**
- From: magnetite's `default.nix` declares the omnigraph, GreptimeDB, Perses and fleet-alert generators, credentials and host settings (`machines/nixos/magnetite/default.nix:527-1050` at `ccc1a8db1932`, the parent of the commit that moved them); cinnabar's eight feature files are all keyed `flake.modules.nixos."machines/nixos/cinnabar"`.
- To: new `<svc>-server` aspects beside each site-neutral feature, which magnetite imports; cinnabar's features under their own `flake.modules.nixos.<feature>` keys, which cinnabar imports. The site-neutral keys the runtime tests import stay clan-free, and the store's credential-holder and unit-relation assertions stay in magnetite's body.
- Impact: non-breaking; drvPaths unchanged.

**Shared host shapes become aspects**
- From: the uplink network and ZFS `devNodes` copied into five cloud servers, `MaxAuthTries` into six NixOS hosts; blackphos and stibnite copying `darwin/laptop.nix`, which hard-codes cameron as admin.
- To: a `hetzner-cloud` aspect for cinnabar, electrum and magnetite (srvos's Hetzner hardware module, the uplink matching `en*`, by-path `devNodes`) and a separate `gcp-cloud` aspect for galena and scheelite (the uplink matching `en* eth*`, by-path `devNodes`, no srvos Hetzner module); pyrite imports neither. `MaxAuthTries` in `nixos.base`; a `darwin-workstation` aspect whose admin, primary user and uids come from each host's user relations, imported by all four Macs.
- The two providers get separate aspects rather than one aspect with the interface pattern as a parameter, because they differ in hardware module and uplink, and a host should import the provider it runs on instead of passing a provider switch to a shared aspect.
- Impact: non-breaking; drvPaths unchanged.

**Host facts and flags written once**
- From: `stateVersion`, documentation and zram written as `mkForce` over base; features imported and then enabled; `custom.profile`, `custom.homebrew.enable` and `services.moshi-hook.enable` always true or never read.
- To: base uses `mkDefault` and hosts write plain values, with darwin `stateVersion` read from the host record; importing is the decision, and the double opt-in and dead flags are deleted. mergify's default-on, dnscrypt-proxy and fleet-services-trust's per-host enable, and k3s-server are kept.
- Impact: resolved values unchanged. No module sets `documentation.nixos.includeAllModules`, so the option manuals document upstream modules only and deleting a repository option leaves them unchanged; the diff confirms it.

**Composition identity and order made explicit**
- Dual-exported home modules get a `key` (with the parameter for parameterised ones) through one `flake.lib.exportAs`.
- A `flake.lib.activationOrder` places each darwin `postActivation` snippet; `deploy-record-order` gains a "record is last" clause and a mutant. May change darwin activation scripts.
- `darwin/caches.nix` is deleted, so each darwin `nix.conf` lists every cache once instead of twice. Changes every darwin toplevel.

**Files split by unit, invariants generated from data**
- `clan/services/otel-collector/flake-module.nix` (1,743 lines) splits into `agent.nix`, `ingress.nix`, `service.nix` and an `_`-prefixed shared file, keeping its `flake.modules` names.
- magnetite's fourteen ZFS boot oneshots and their `notifiedUnits` are generated from a dataset table in `flake.lib`; `disko.nix` stays an independent literal so `greptimedb-envelope` still compares install-time with boot-time.
- `base` gets named sub-aspects, and `homeManager.ai` becomes one aspect per harness, with `ai` importing them all; the obligation modules stay in base.

**Acceptance, per commit**: the change ships as seven commits, one pull request each, each accepted on its own `just drv-diff <parent> <commit> openspec/changes/compose-hosts-from-cohesive-aspects/drv-delta-<n>.txt` (design D12). The oracle compares every NixOS and darwin toplevel, home activation package, `checks.{x86_64-linux,aarch64-darwin}` and `vmTests.{x86_64-linux,aarch64-linux}` derivation at the two commits and fails on any difference the allow-list does not name, or on a `changed` entry that did not change. Allow-lists name exact attribute paths, no globs:

- Commits 1-4 (otel-collector split, cinnabar keys, provider and workstation aspects with the state-version read, magnetite's server aspects with the ZFS table): no entries; every derivation is expected identical.
- Commit 5 (flags deleted): the runtime tests whose files are edited (`devloop-ingest`, `fleet-ingress`, `greptimedb-pipeline`, `greptimedb-oom-order`, `shared-reference-tree` and the attributes built from them), resolved to `changed` with their cause or removed.
- Commit 6 (identity, activation order, named parts): `checks.x86_64-linux.deploy-record-order changed`. The activation order reproduces today's, so no darwin activation script changes.
- Commit 7 (darwin caches): `darwin.{argentum,blackphos,rosegold,stibnite}` and `checks.aarch64-darwin.darwin-{argentum,blackphos,rosegold,stibnite}` `changed`: each `nix.conf` lists every cache once. This is the only commit that changes a host, and the four Macs are deployed after it.

`just eval-identity` is not this oracle: it compares two evaluators at one revision.

**Non-goals**: renaming the `machines/<class>/<host>` keys or the signing person or account keys; moving the credential-holder assertions into a flake check; generating disko from the dataset table; deriving the literal check oracles (`omnigent-workers.nix` host matrix, `nix-builders-wiring.nix`, `sops-correspondence.nix` anchors). Renaming stibnite's `controller` inventory tag to `deployer-workstation` is owned by `type-the-fleet-host-registry`; this change reads and writes no inventory tag.

### Depends on and landing order

- `establish-refactor-oracle`: `just drv-diff`, the acceptance above.
- `type-the-fleet-host-registry`: the typed `flake.fleet.hosts.<host>` record (read through `flake.lib.hosts`) with `system` and `stateVersion`. That change declares and fills `stateVersion` and reads it nowhere (its design D9); this change switches the darwin hosts and `darwin/base.nix` to read it, which removes the second copy D9 accepts until then.
- `declare-host-user-relations-once` (merged at `302236090`): the per-(host, account) attachments and the `home-manager-integration` aspect, which already generate each darwin host's admin, primary user, uids and homes; `darwin-workstation` keeps only the remaining template (imports, documentation, accounts' home fields, `knownUsers`).

This change lands after `declare-host-user-relations-once` and before `seam-secrets-away-from-clan-vars`, because all three edit `machines/nixos/magnetite/default.nix` and the cinnabar feature files. The full order is `establish-refactor-oracle`, `stop-reading-other-hosts-configs`, `type-the-fleet-host-registry`, `register-fleet-obligations`, `declare-host-user-relations-once`, this change, `seam-secrets-away-from-clan-vars`; it re-runs `just drv-diff` after rebasing onto its predecessor and archives in the same order.

Every dependency has landed; design.md is written against main at `302236090`. Another session is landing commits to `machines/nixos/magnetite/default.nix`, the backup modules, `lib/observability-hosts.nix` and the reference-tree modules; commits 3-5, which touch those files, land after it.

### Open questions

Carried to design.md's Open Questions for the operator, each with a recommended answer: the key spelling (`vanixiets/<name>`), the cinnabar feature keys, GRUB written plainly, NixOS state versions from the registry, the seven-commit split, the darwin deploy order, renaming `darwin/laptop.nix`, and the reference-tree flag.

## Capabilities

### New Capabilities

- `host-composition` (stratum: behavioral): each host's deployed system is the same before and after the restructuring, apart from the changes this proposal declares; a capability several hosts run is declared once and each host states only what is particular to it; a darwin host's deploy record is the last thing its activation writes.
- `host-composition-interface` (stratum: interface): the new aspect keys (`<svc>-server`, cinnabar's feature keys, the `hetzner-cloud`, `gcp-cloud` and `darwin-workstation` aspects, the named sub-aspects of `base` and the per-harness `ai` aspects), `flake.lib.exportAs` and the `key` it sets, `flake.lib.activationOrder` with the `deploy-record-order` clause and mutant, the ZFS dataset table and the oneshots and `notifiedUnits` generated from it, and the darwin hosts' read of the host record's `stateVersion`. Trust boundary: the `just drv-diff` acceptance shows only that evaluated derivations are the same at two revisions, not that a deployed host behaves the same; the order clause reads the generated activation script and does not show that activation runs or succeeds; the dataset table governs only what boot enforces, and disko's install-time declaration stays a separate literal that `greptimedb-envelope` compares against it.

### Modified Capabilities

- `devloop-collection-interface` (stratum: interface): "Each activation appends one deploy record" places the darwin snippet by its declared activation order, last among `postActivation` snippets, instead of by `mkAfter` and import order.
- `telemetry-store-interface` (stratum: interface): the scenario "The dataset properties are applied at boot and confirmed on magnetite" names the dataset table in `flake.lib` instead of magnetite's `greptimedbDataset` binding; disko stays the independent install-time declaration.
- `world-assumptions` (stratum: world): assumptions numbered from A350 (range A350–A359): nix-darwin concatenates `postActivation` lines in `mkOrder` priority order, and the module system imports a module once per `key`; designations for aspect (in its nix sense), host composition and cloud server.

## Impact

- Code: `machines/nixos/{magnetite,cinnabar,electrum,galena,scheelite,pyrite}/`, `machines/darwin/{blackphos,stibnite,argentum,rosegold}/default.nix`, `darwin/{laptop,base,homebrew,profile,caches}.nix`, `system/{zram-swap,deploy-record,stibnite-session,shared-reference-tree}.nix`, `nixos/{memory-pressure-guards,shared-reference-tree}.nix` and new `nixos/{omnigraph,greptimedb,perses,fleet-alert}-server.nix`, `nixos/{hetzner-cloud,gcp-cloud}.nix`, `lib/zfs-boot-invariants.nix`, `clan/services/otel-collector/`, `lib/observability-hosts.nix`, `home/terminal/`, `home/tools/agents-md.nix`, `home/development/{git,wezterm}`, `home/ai/` (moshi and the per-harness split), `checks/deploy-record-order`, and the runtime tests `devloop-ingest`, `fleet-ingress`, `greptimedb-pipeline`, `greptimedb-oom-order` and `shared-reference-tree` (all under `modules/`).
- Hosts: every NixOS and darwin host is re-evaluated; only the four darwin toplevels are declared to change, in commit 7 (`nix.conf` caches), and those four Macs are deployed after it.
- Checks: `greptimedb-envelope`, `omnigraph-retired-roots`, `deploy-record-order`, `otel-collector-config`, the `nixos-*`/`darwin-*` machine checks, and the runtime tests above; of these only the `darwin-*` machine checks (commit 7) and `deploy-record-order` (commit 6) are declared to change, and the edited runtime tests (commit 5) may.
