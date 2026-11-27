## Context

### Current state

Paths are relative to `modules/` unless they start with `openspec/`, `docs/`, `packages/`, `lib/` or `logs/`. Every file:line below was read on main at `302236090` (declare-host-user-relations-once merged) on 2026-11-27. Lines in `machines/nixos/magnetite/default.nix`, `nixos/omnigraph-backup.nix`, `nixos/postgresql-backup.nix`, `lib/observability-hosts.nix` and `{nixos,darwin,system}/shared-reference-tree.nix` are cited **at the time of writing only**: another session is landing commits to those files (the OmniGraph store, backup and reference-tree settings), and task 0.1 re-reads them before any edit. brainstorm.md's line numbers predate four merged changes; the current ones are given here.

**What the predecessors provide, and what is stale in the proposal.** Every change this one depends on has landed:
- `flake.fleet.hosts.<host>` (`lib/hosts.nix`) is a typed record with read-only `class` and `cloud` (provider, machine type, enabled; `lib/hosts.nix:171-182,221`), and `stateVersion` (`:109-125`), whose description still says "not yet read by the host modules"; the values are `"25.05"` for five NixOS hosts, `"26.05"` for pyrite, `4` for the four Macs (`:249-367`). The proposal's "read through the read-only `flake.lib.hosts` alias" holds.
- The per-account attachments `flake.fleet.hosts.<host>.users.<account>` (`lib/host-users.nix`) and the integration aspect `flake.modules.{nixos,darwin}.home-manager-integration` (`system/home-manager-integration.nix`) already generate `system.primaryUser`, the darwin human uids and every home. So brainstorm Q5's "parameterised by the admin and primary user and their uids" is already done: what remains in `darwin/laptop.nix` and the blackphos and stibnite bodies is the import list, the documentation block, `targetHost`, `stateVersion`, `custom.profile`, `custom.homebrew`, `declaredSshd.serving`, dnscrypt-proxy, the `users.users.<a>` blocks (home, shell, description, keys) and `users.knownUsers`. `flake.fleet.workers` (`lib/fleet-workers.nix`) and `flake.lib.workerAccountsOn` give the reference-tree participants.
- Host judges register through `fleetObligations` (`lib/fleet-obligations.nix`, folded by `checks/machines.nix:30-68`); fixture checks use `flake.lib.judgeCases`/`mkJudgeCheck` (`lib/judge-check.nix`); `checks.x86_64-linux.deploy-record-order` is a `judgeCases` check over literal scripts, and the real darwin scripts are judged by `deployRecordObligations` (`system/deploy-record.nix:143-177`) in every `darwin-<host>` machine check.
- `flake.lib.vars` (`lib/vars.nix:75`) and `flake.lib.hostKeys` (`lib/host-keys.nix:25`) are the one reading of clan's committed vars; nothing here reads vars by path.
- Runtime tests are `vmTests.<system>` built on the per-system package set (`vm-tests/default.nix`).
- `just drv-diff <before> <after> [allow]`, `just drv-diff-rejudge <dir> [allow]` and `just eval-cost` (justfile:457-475) are the acceptance tools. drv-diff dumps `nixos`, `darwin`, `home`, `checks.{x86_64-linux,aarch64-darwin}` and `vmTests.{x86_64-linux,aarch64-linux}` (`apps/drv-diff.sh:10-19`) and takes exact `<set>.<attr> <expect>` lines.

**Host bodies at main (sizes at the time of writing).** magnetite 1,120 lines; pyrite 748; cinnabar 91, electrum 90, galena 86, scheelite 97; stibnite 237, blackphos 147, argentum and rosegold 15 each over `darwin/laptop.nix` (108).

**magnetite's service wiring** (at the time of writing): imports `:63-130`; the omnigraph generators and `services.omnigraph` `:531-743` with `omnigraphRootStore` (`:58`, declared as an option `:111-128` so that `checks/omnigraph-retired-roots.nix:34-35` can `extendModules` it), `cookbooks` (`:41-52`) and `r2Endpoint`; the GreptimeDB and Perses generators, `LoadCredential` and `EnvironmentFile` `:745-871`; the store's credential-holder and unit-relation `assertions` `:881-1005`; `greptimedb-envelope` and `devloop-reconcile` credentials `:1010-1039`; the fleet-alert evaluator `:1046-1051`.

**cinnabar's features.** `machines/nixos/cinnabar/{caddy,caddy-root-ca,caddy-root-check,fleet-alert,matrix,ntfy,radicle,zt-dns,disko}.nix` all assign `flake.modules.nixos."machines/nixos/cinnabar"` (`caddy.nix:7`, `caddy-root-ca.nix:13`, `caddy-root-check.nix:11`, `fleet-alert.nix:7`, `matrix.nix:55`, `ntfy.nix:3`, `radicle.nix:3`, `zt-dns.nix:51`, `disko.nix:4`). Taken site-neutral keys: `fleet-alert` (`nixos/fleet-alert.nix:587`), `matrix` (`nixos/matrix.nix:60`), `zt-dns` (`system/zt-dns.nix:27`), `caddy-local-root`, `ntfy-alerter`.

**Cloud boilerplate.** `boot.zfs.devNodes = "/dev/disk/by-path"` at `cinnabar:39`, `electrum:35`, `galena:34`, `magnetite:141`, `scheelite:38` (pyrite `/dev/disk/by-id` at `:140`); `10-uplink` matching `en*` at `cinnabar:69-70`, `electrum:68-69`, `magnetite:1087-1088`, and `en* eth*` at `galena:64-65`, `scheelite:75-76`; srvos's `hardware-hetzner-cloud` imported at `cinnabar:22`, `electrum:22`, `magnetite:67`; `MaxAuthTries = 20` at `cinnabar:89`, `electrum:88`, `galena:84`, `magnetite:1113`, `scheelite:95`, `pyrite:630` (darwin once, `darwin/base.nix:20`); `boot.loader.grub.enable = lib.mkForce false` at `electrum:42`, `galena:40`, `scheelite:44`. srvos's Hetzner module sets `boot.loader.grub.devices` with `mkDefault` and networkd (`nixos/hardware/hetzner-cloud/default.nix:16,23-24` at srvos `e151e24a`), not `grub.enable`.

**Priority fights.** `darwin/base.nix:54` sets `system.stateVersion = 5`; `laptop.nix:59`, `blackphos:55`, `stibnite:68` force 4. The seven documentation `mkForce` lines are at `laptop.nix:45-51`, `blackphos:38-44`, `stibnite:50-56`. Read at the locked revisions, nothing forces them: srvos sets them with `mkDefault` (`shared/server.nix:26-29`, `darwin/server/default.nix:14-15`), and clan-core's `documentation.{doc,info}.enable = mkDefault false` is in `nixosModules/clanCore/defaults.nix:42,45`, a NixOS module. `system/zram-swap.nix:11` sets `memoryPercent = 100` plainly; magnetite forces 150 (`:1061`).

**Double opt-in and dead flags.** `services.memoryPressureGuards.enable` (magnetite `:1076`, pyrite `:718`), `services.colima.enable` (stibnite `:172`), `services.shared-reference-tree.enable` (magnetite `:132-135`, pyrite `:87`, stibnite `:40`; `vm-tests/shared-reference-tree.nix:85-86`), `services.greptimedb.enable` (magnetite `:846-847`; `vm-tests/{devloop-ingest:1657,fleet-ingress:2152,greptimedb-oom-order:111,greptimedb-pipeline:144}`), `services.stibnite-session.enable` (magnetite `:180`) and `services.stibnite-session-host.enable` (stibnite `:160`), each set wherever its module is imported. `custom.homebrew.enable` (`darwin/homebrew.nix:96`) is set by all four Macs; `osConfig.custom.homebrew.enable or false` is read at `home/development/wezterm/default.nix:24`. `services.moshi-hook.enable = lib.mkDefault true` (`home/ai/moshi/default.nix:181`) is set false nowhere. `custom.profile` (`darwin/profile.nix:16-38`) is set by three hosts and read by none. The otel-collector role reads `config.services.greptimedb.enable or false` five times (`clan/services/otel-collector/flake-module.nix:517,876,877,1107,1372`).

**Dual exports without identity.** `home/terminal/{fd,jq,ripgrep}.nix:10-11`, `home/terminal/direnv.nix:86-87`, `home/tools/agents-md.nix:81-82`, `home/ai/atomic/default.nix:138-139`; `home/development/git.nix:170-171` exports `content true` as `development` and `content false` as `git`. claude-sandbox imports `terminal` and `fd`, `jq`, `ripgrep` (`home/users/claude-sandbox/meta.nix:26-48`); the worker home imports `cli-tools`, which imports `jq` (`system/cli-tools/default.nix:31`). flake-parts' `flake.modules` values carry `_class` and `_file` but no `key` (`extras/modules.nix:24-26`, "TODO: set key?"), so importing one value from two parents applies it twice (A351). Key spellings: `vanixiets/<name>` 22 times, `vanixiets#<name>` 3 times (`clan/services/otel-collector/flake-module.nix:94`, `nixos/node-exporter-textfile.nix:38`, `nixos/observability-notify.nix:82`).

**darwin `postActivation`.** `resolver-reload` leads with `mkBefore` (`darwin/resolver-reload.nix:96`); stibnite's keychain snippet is plain (`stibnite:221`); `casks` (`darwin/casks.nix:33`), `fleet-services-trust` (`darwin/fleet-services-trust.nix:25`), `dnscrypt-proxy` (`system/dnscrypt-proxy.nix:305`) and the deploy record (`system/deploy-record.nix:213`) all use `mkAfter`. Among equal priorities the module system concatenates later-listed siblings first (A344, A352), which is why the record, listed first among them, ends last today.

**otel-collector.** `clan/services/otel-collector/flake-module.nix` is 1,750 lines: the shared `let` `:33-237`, `otel-collector-agent` `:239`, `otel-collector-ingress` `:1066`, `flake.clan.modules.otel-collector` `:1379`. The runtime tests `devloop-ingest`, `fleet-ingress` and `greptimedb-pipeline` import the two `flake.modules.nixos` keys.

**ZFS boot invariants.** Fourteen `systemd.services.zfs-*` oneshots in magnetite's body (`:230-432` at the time of writing), two gated on `vanixiets.postgresqlBackup.enable` (`:387,400`) and one on `omnigraphRootStore == "local"` (`:422`); the greptimedb three read `greptimedbDataset` (`:28-33`). `lib/observability-hosts.nix` lists the fourteen as magnetite's notified units; the other session has just wrapped that list in `onlyWithLocalRoot` so local-root units drop out when the store is `r2`. `checks/greptimedb-envelope.nix:514-551` compares disko's dataset with the oneshots' `ExecStart` by suffix.

**Aggregates.** 37 files contribute to `darwin.base`, 30 to `nixos.base`, 14 define `homeManager.ai`.

**Caches.** `darwin/caches.nix:9-11` and `system/caches.nix:8-10` both add `lib/caches.nix`'s ten substituters and ten keys to `darwin.base`. nix-darwin types both as `listOf str` and renders a list by `toString`, space-joined, without removing duplicates (`modules/nix/default.nix:38-50,622-657` at nix-darwin `663d8b96`), and adds `https://cache.nixos.org/` with `mkAfter` and the cache.nixos.org key plainly (`:947-949`). So every darwin `nix.conf` lists each of the ten twice. Its activation sends the daemon `HUP` when `/etc/nix/nix.conf` differs from the running one (`:934-936`).

### Requirements and the world they rest on

| Req | Statement (behavioral, `host-composition`) | Rests on | Breaks if it fails | Discharged by |
|---|---|---|---|---|
| R1 | Each host's deployed system is the same before and after, apart from the declared differences | A351, A352, A356 | a host silently changes at its next deploy | D12, D13 |
| R2 | A capability several hosts run is declared once; each host states only what is particular to it | A359 | a new host or service is a copy-and-edit job | D1-D5 |
| R3 | A cloud server takes its provider's shape from one declaration per provider | A355, A359 | a Hetzner host boots with the GCP uplink, or a fix reaches four of five servers | D3 |
| R4 | A Mac's state version is declared once, as the version it was first set up with | A358 | a Mac's system defaults move (nixbld gid) | D4 |
| R5 | A darwin host's deploy record is the last thing its activation writes | A350, A352 | a later snippet fails after the record and the record claims a deploy that did not finish | D8 |
| R6 | Each darwin host consults each binary cache once | A353, A354 | — (a cosmetic duplicate today) | D10 |
| R7 | The dataset properties magnetite enforces at boot are stated once, independently of the install-time declaration | A357 | boot enforces one size and the envelope regulator expects another | D9 |

### Stakeholders

The operator, who reads this before any code and deploys the four Macs. The session landing the OmniGraph store, backup and reference-tree commits, whose files three of this change's commits touch (Migration Plan). seam-secrets-away-from-clan-vars, which lands next and edits magnetite's body and the cinnabar feature files this change moves. A later den migration, which maps aspects onto den's.

## Goals / Non-Goals

**Goals:**
- Service wiring out of magnetite's body into `<svc>-server` aspects; cinnabar's features under their own keys.
- `hetzner-cloud` and `gcp-cloud` aspects; `MaxAuthTries` in `nixos.base`; a `darwin-workstation` aspect imported by all four Macs.
- Hosts read `stateVersion` from their registry record; base modules set what a host may change with `mkDefault` and hosts write plain values; double opt-ins and dead flags deleted.
- `flake.lib.exportAs` with one key spelling; `flake.lib.activationOrder` and a "record is last" judge; named sub-aspects of `base` and per-harness `ai` aspects.
- The otel-collector file split; magnetite's ZFS invariants generated from a dataset table.
- One copy of each darwin cache.
- Seven pull requests, each accepted on its own `just drv-diff`; only the last changes any host toplevel, and only the four Macs'.

**Non-Goals:**
- Renaming `machines/<class>/<host>` keys, person or account keys, or the stibnite `controller` inventory tag.
- Removing the mergify default-on, dnscrypt-proxy's or fleet-services-trust's per-host `enable`, or k3s-server.
- Changing the keys of site-neutral service modules the runtime tests import (`greptimedb`, `perses`, `fleet-alert`, `devloop-collection`, `omnigraph`, `otel-collector-{agent,ingress}`), or adding clan vars to them.
- Moving the store's credential-holder and unit-relation assertions out of magnetite's body; generating disko from the dataset table.
- Deriving literal check oracles (`omnigent-workers.nix` matrices, `nix-builders-wiring.nix`, `sops-correspondence.nix` anchors, `magnetite-zram-headroom`'s fleet default).

## Decisions

### D1: magnetite's service wiring moves into `<svc>-server` aspects in sibling files

- **Choice**: new files `nixos/{omnigraph,greptimedb,perses,fleet-alert}-server.nix`, each defining `flake.modules.nixos.<svc>-server` with that service's clan generators, `LoadCredential`/`EnvironmentFile` wiring and the host-side settings now in magnetite's body: omnigraph-server takes the four omnigraph generators, `services.omnigraph`, the `vanixiets.omnigraphRootStore` option (so `omnigraph-retired-roots`' `extendModules` still reaches it), `cookbooks` and `r2Endpoint`; greptimedb-server takes `greptimedb-users`, `greptimedb-r2`, `services.greptimedb`'s settings, the store's credentials and the `greptimedb-envelope` and `devloop-reconcile` credentials; perses-server takes `perses-encryption-key` and perses' `LoadCredential`; fleet-alert-server takes the evaluator. magnetite imports the four. Each aspect reads the generators another defines (fleet-alert-server and perses-server read `greptimedb-users`) through `config.clan.core.vars.generators`, without importing that aspect, so a host that forgets greptimedb-server fails evaluation naming the generator; no aspect imports another from `flake.modules`, because those values carry no key and would apply twice (A351). The credential-holder and unit-relation assertions stay in magnetite's body. magnetite's own list definitions that the moved code shared (`networking.firewall.interfaces.<if>.allowedTCPPorts`, `systemd.tmpfiles.rules`) stay where they are.
- **Rationale**: one reason to change per file (Lowy): the site-neutral module changes with the service, the server aspect with how this fleet deploys it. The site-neutral files promise no clan in their headers (`nixos/greptimedb.nix:3-4`) and the runtime tests import them with their own credentials; a sibling file keeps that promise at file level, where a reader checks it. Moving a definition from the host body into an imported aspect moves it earlier in every list it joins (A344, A352); each moved list definition whose relative order reaches a derivation (`LoadCredential` lists that the body also extends, `assertions`) is written so the merged list is unchanged, with `lib.mkAfter` where the body's definition came last, and the drvPath diff decides. Boundary: vendored-versus-first-party: clan's vars and the services are used as documented, nothing vendored is patched.
- **Alternatives considered**: (a) the `<svc>-server` key in the feature's existing file (brainstorm Q2): two contracts in one file, one of them clan-free. (b) moving the wiring into the site-neutral keys: breaks the runtime tests. (c) moving the assertions into a flake check: evaluates magnetite again.

### D2: cinnabar's features take their own keys; the files stay

- **Choice**: each of the eight files assigns `flake.modules.nixos.<key>` and cinnabar's `default.nix` imports them, in the order that reproduces today's merge; `disko.nix` stays on the host key. Keys (Open Question 2): `caddy`, `caddy-root-ca`, `caddy-root-check`, `fleet-alert-deadman`, `matrix-server`, `ntfy-server`, `radicle-node`, `zt-dns-server`, each checked free at apply. The per-machine generators (`caddy-root-ca`, `ntfy-alerter-env`) stay in modules only cinnabar imports.
- **Rationale**: a feature with its own key can be imported by another host or a runtime test. Today the nine files are sibling definitions of one `deferredModule`, merged as separate imports in definition order; after, eight are imports of the body, so the body's definitions move after theirs (A352). The import order is chosen to reproduce today's list order; the drvPath diff decides. The files do not move, so world assumptions citing `machines/nixos/cinnabar/caddy.nix` and `ntfy.nix` keep their evidence. Boundary: source-only.
- **Alternatives considered**: moving the files under `nixos/`: breaks those citations for no gain.

### D3: `hetzner-cloud` and `gcp-cloud`; `MaxAuthTries` in `nixos.base`; GRUB written plainly

- **Choice**: new `nixos/hetzner-cloud.nix` (`flake.modules.nixos.hetzner-cloud`: srvos's `hardware-hetzner-cloud` import, `boot.zfs.devNodes = "/dev/disk/by-path"`, `10-uplink` matching `en*` with today's DHCP and DNS settings) imported by cinnabar, electrum and magnetite; new `nixos/gcp-cloud.nix` (`devNodes` by-path, `10-uplink` matching `en* eth*`, no srvos Hetzner module) imported by galena and scheelite; pyrite imports neither. Each aspect asserts that the importing host's `flake.fleet.hosts.<host>.cloud.provider` is its provider, naming the host, so the registry and the composition cannot disagree. `services.openssh.settings.MaxAuthTries = 20` moves into `nixos.base` (a file beside `system/caches.nix`'s NixOS half) and leaves all six bodies. `boot.loader.grub.enable` is written `false` plainly on electrum, galena and scheelite: nothing sets it above the option default (srvos sets `grub.devices` with `mkDefault`), so the priority change leaves the value and the drvPath the same (Open Question 3).
- **Rationale**: decided 2026-11-26: the providers differ in hardware module and uplink, so a host imports the provider it runs on. The provider assertion reads `cloud.provider`, which the registry derives from `cloudMachines`; this keeps one source for which provider a host is on (A359). Boundary: vendored-versus-first-party: srvos's module is imported, not copied.
- **Alternatives considered**: one aspect parameterised by provider (rejected 2026-11-26); generating the import from `cloud.provider` (`imports` cannot read `config`; it could read `flake.lib.hosts`, but an aspect that chooses its own body by host name is a provider switch in disguise).

### D4: host facts written once

- **Choice**:
  - `darwin/base.nix` sets `system.stateVersion = hosts.${config.networking.hostName}.stateVersion` and the three `mkForce 4` lines go; every Mac resolves 4 (A358). `nixos.base` does the same for NixOS and the six `system.stateVersion = "…"` lines go (Open Question 4); the registry field's description drops "not yet read". `ids.gids.nixbld`'s comment (`darwin/base.nix:43-52`) is reworded: hosts no longer force the version; the registry holds 4.
  - `system/zram-swap.nix:11` becomes `lib.mkDefault 100`; magnetite writes `150` plainly.
  - `darwin-workstation` writes the seven documentation options plainly once; nothing forces them (Context).
- **Rationale**: base states what a host may change; the host states its value without a priority. The registry already holds the version; reading it removes the copy type-the-fleet-host-registry's D9 accepted. Boundary: source-only.
- **Alternatives considered**: `mkDefault 5` in base with plain `4` in hosts: keeps two copies.

### D5: `darwin-workstation` replaces `laptop` and the blackphos and stibnite copies

- **Choice**: `darwin/laptop.nix` is renamed `darwin/darwin-workstation.nix` and defines `flake.modules.darwin.darwin-workstation` (Open Question 7): today's import list (home-manager, srvos darwin server, `base`, `home-manager-integration`, `deploy-record`, `ssh-ca-trust`, `ssh-known-hosts`, `dnscrypt-proxy`, `zt-dns`, `fleet-services-trust`), the documentation block, `networking.computerName`, `clan.core.networking.targetHost` from the record, `declaredSshd.serving = true`, `custom.homebrew`'s import, and `users.users.<a>` (home, shell, description, `openssh.authorizedKeys.keys`) and `users.knownUsers` for each human attachment, in attachment order. Each host keeps only its delta: argentum and rosegold `networking.hostName` and dnscrypt-proxy (today in the template, moved to the two laptops as their delta, since blackphos and stibnite set it differently); blackphos its casks, dnscrypt-proxy and `fleet-services-trust.enable`; stibnite its extra imports (`casks`, `colima`, `stibnite-session-host`, `shared-reference-tree`), the worker account, the reference tree, colima, the CA and its keychain snippet, its `knownSha256Hashes`. `users.knownUsers` is a list whose order reaches the activation script; the aspect's entries come first and stibnite adds `omnigent-cameron` after them, giving today's `[ "crs58" "omnigent-cameron" ]`; the laptops' order `[ primaryUser "cameron" ]` is the attachments' primary-then-admin order, which the generator follows. `cameron` on the laptops keeps no shell and keys (the user service provides them).
- **Rationale**: the four Macs are one shape with different attachments; the uids and admin already come from the attachments. Boundary: vendored-versus-first-party: nix-darwin's options as documented.
- **Alternatives considered**: a second template for single-user Macs: stibnite is a parameter value.

### D6: importing is the decision; flags deleted

- **Choice**: delete `enable` (and its `mkIf`) from memory-pressure-guards, colima, shared-reference-tree (NixOS and darwin), greptimedb, `stibnite-session`, `stibnite-session-host`, and `custom.homebrew.enable`; delete `services.moshi-hook.enable` and its `mkIf`; delete `darwin/profile.nix` and the three `custom.profile.isDesktop` lines. `osConfig.custom.homebrew.enable or false` becomes `osConfig ? custom && osConfig.custom ? homebrew`. The otel-collector role's five `config.services.greptimedb.enable or false` become `config.services ? greptimedb` (the option exists only where the module is imported). The runtime tests stop setting the deleted flags: `devloop-ingest`, `fleet-ingress`, `greptimedb-pipeline`, `greptimedb-oom-order` and `shared-reference-tree` already import the module, so they only drop `enable = true`. `greptimedb-oom-order:116` copies magnetite's `memoryPressureGuards.enable` today; it imports the module unconditionally and asserts that magnetite's configuration has `services ? memoryPressureGuards`, so the test fails evaluation if magnetite stops importing it. Kept: mergify's default-on, dnscrypt-proxy's and fleet-services-trust's `enable`, k3s-server.
- **Rationale**: two decisions for one fact let them disagree. No module sets `documentation.nixos.includeAllModules`, so removing a first-party option changes no manual (the drvPath diff confirms it). Boundary: source-only.
- **Alternatives considered**: keeping `enable` with `default = true`: still two places.

### D7: `flake.lib.exportAs` and one key spelling

- **Choice**: `flake.lib.exportAs = { key, names, module }` returns the attrset assigning `module // { key = "vanixiets/${key}"; }` (wrapped as `{ inherit key; imports = [ module ]; }` when `module` is a function) under each name in `names`; the seven dual-exporting files use it. A parameterised value's key carries its parameter: `vanixiets/git?full=true` (`development`) and `vanixiets/git?full=false` (`git`). The three `vanixiets#…` keys become `vanixiets/…` (Open Question 1). With the key, the module system applies each value once per home (A351): claude-sandbox's `fd`, `jq`, `ripgrep` and the worker's `jq` stop being applied twice. Those modules set only booleans, so the merged values and every home's drvPath are unchanged; the drvPath diff confirms it.
- **Rationale**: identity stated, not inferred from which parent imported a value. Boundary: source-only.
- **Alternatives considered**: deleting the aggregate export: every importer of `terminal` changes.

### D8: `flake.lib.activationOrder` and the "record is last" judge

- **Choice**: `flake.lib.activationOrder` (in `system/deploy-record.nix`) names each darwin `postActivation` contributor's `mkOrder` priority: `resolverReload = 500` (today's `mkBefore`), `fleetServicesTrust = 1497`, `dnscryptProxy = 1498`, `casks = 1499`, `deployRecord = 1900`. The four writers use `lib.mkOrder activationOrder.<name>`; stibnite's plain snippet stays at the default 1000. The values reproduce today's concatenation on every Mac (fleet-services-trust, then dnscrypt-proxy, then casks, then the record; task 1.3 measures it first), so every darwin toplevel keeps its drvPath. `deployRecordObligations.orderProblems` gains a darwin rule: between the record's invocation and the relink there is no other `postActivation` text. `checks.x86_64-linux.deploy-record-order` gains the mutant case `darwinSnippetAfterRecord` (one problem), so that check's drvPath changes; the machine checks keep theirs, because a judge is an evaluation-time assertion (A332).
- **Rationale**: the record's place is stated, and a later snippet fails the machine check instead of silently following the record (A350). 1900 is above `mkAfter` (1500), so a future `mkAfter` snippet stays before the record. Boundary: vendored-versus-first-party: nix-darwin's `types.lines` ordering is used as documented.
- **Alternatives considered**: reading order from the import list (today): implicit.

### D9: magnetite's ZFS boot invariants generated from a table

- **Choice**: `flake.lib.zfsBootInvariants.magnetite` (new `lib/zfs-boot-invariants.nix`): a list of `{ unit, dataset, property, value, when ? null }`, one entry per oneshot, in today's order, with `when` one of `null`, `"postgresqlBackup"` or `"omnigraphLocalRoot"`. A generator in magnetite's body (or an aspect it imports) maps the table to the fourteen `systemd.services.<unit>` with today's description `Assert ${property}=${value} on ${dataset}`, `wantedBy`, `after`, `Type`, `RemainAfterExit` and `ExecStart`, gated by `when`. `greptimedbDataset` and the envelope's `GREPTIMEDB_ENVELOPE_{DATASET,QUOTA_BYTES,RESERVATION_BYTES}` read the table's greptimedb entries. `lib/observability-hosts.nix` takes magnetite's `zfs-*` names from the table, merged into its sorted list, keeping the other session's `onlyWithLocalRoot` filter. `disko.nix` stays a literal; `greptimedb-envelope`'s `diskoMatchesDataset` is unchanged and still compares install time with boot time (A357).
- **Rationale**: one statement of what boot enforces, not fourteen copies and a name list. Every unit must be byte-identical: task 6.2 compares each unit's derivation before and after. Boundary: source-only.
- **Alternatives considered**: generating disko too (the envelope would compare a value with itself).

### D10: one copy of the darwin caches

- **Choice**: delete `darwin/caches.nix`; `system/caches.nix` stays the source for both classes.
- **Before** (each Mac, at the time of writing; task 1.4 records the exact evaluated lists): `config.nix.settings.substituters` is the ten URLs of `lib/caches.nix`, then the same ten again, then `https://cache.nixos.org/`; `trusted-public-keys` is the ten keys twice plus nix-darwin's own cache.nixos.org key. `/etc/nix/nix.conf` renders each as one space-joined line: `substituters = https://cache.nixos.org https://nix-community.cachix.org https://cache.numtide.com?priority=42 https://cache.clan.lol?priority=42 https://pyproject-nix.cachix.org https://catppuccin.cachix.org https://cache.nixos-cuda.org https://cache.scientistexperience.net?priority=45 https://cameronraysmith.cachix.org?priority=50 https://cache.thalheim.io?priority=55 <the same ten> https://cache.nixos.org/`.
- **After**: the same line with the ten once, followed by `https://cache.nixos.org/`; `trusted-public-keys` the ten once plus cache.nixos.org's key (wherever nix-darwin's plain definition merges today; task 1.4 records the position and 7.2 confirms it is unchanged apart from the removed copy).
- **Proof it is the only difference**: per Mac, `nix eval --json` of `nix.settings.{substituters,trusted-public-keys}` at both commits (seconds), and `nix run nixpkgs#nix-diff -- <before toplevel .drv> <after toplevel .drv>` (evaluation only, minutes), which must show only the `nix.conf` derivation and the `etc` and system derivations that embed it differing, and in `nix.conf` only those two lines.
- **Deploy**: argentum, blackphos, rosegold, stibnite each need a deploy for nix.conf to change. At activation `/etc/nix/nix.conf` is replaced and nix-darwin sends `nix-daemon` `HUP` (A354); no cache is added or removed, so substitution behaves the same, without querying each cache twice. Nothing else changes at runtime.
- **Rationale**: two writers for one list. Boundary: source-versus-delivered: the delivered `nix.conf` changes, which is declared.
- **Alternatives considered**: deduplicating with `lib.unique` in base: keeps two writers.

### D11: `base` and `ai` get named parts; otel-collector splits by unit

- **Choice**: each file contributing to `flake.modules.{darwin,nixos}.base` defines its own `flake.modules.<class>.base-<concern>` instead, and one file per class sets `flake.modules.<class>.base.imports` to the named list (caches, nix settings, ssh, obligations, and the rest; the obligation modules `postgresql-backup.nix:44`, `r2-usage.nix:35`, `zpool-probe.nix:184` stay in it). `homeManager.ai` likewise becomes one aspect per harness (claude-code, codex, opencode, pi, omp, devin, omnigent, atomic and the shared settings), with `ai` importing them all. The lists are ordered to reproduce today's merge order (A352): a `deferredModule` with several definitions imports them in definition order, so the named list follows import-tree's path order of the contributing files. The otel-collector's shared `let` moves into `clan/services/otel-collector/_shared.nix` (import-tree skips `_`-prefixed paths, A356), imported by `agent.nix`, `ingress.nix` and `service.nix`, each assigning the same output it assigns today; the `forward` connector moves to ingress, the agent's `!ingress` branches stay.
- **Rationale**: a reader can say what base is made of, and a host or test can take one part. Boundary: source-only.
- **Alternatives considered**: leaving base implicit.

### D12: seven pull requests, each accepted on its own drvPath diff

- **Choice**: the change is delivered as seven commits, one pull request each, in this order; each has its own `drv-delta-<n>.txt` under this change directory and its acceptance `just drv-diff <parent> <commit> openspec/changes/compose-hosts-from-cohesive-aspects/drv-delta-<n>.txt` (about 16 minutes; the operator runs it). The four allow-list facts every commit carries: any `packages/docs` edit adds the twenty-eight docs-package checks as `changed`; any `testSizes.checks` entry added or edited adds `checks.x86_64-linux.fleet-alert changed`; a new check is `class = "medium"; measured = false;` (none is planned); a `may-change` entry is resolved before the next commit starts.

| # | Commit | Touches the other session's files | Toplevels that change | Allow-list beyond the base |
|---|---|---|---|---|
| 1 | Split the otel-collector flake-module by unit | no | none | none |
| 2 | Give cinnabar's features their own keys | no | none | none |
| 3 | Compose hosts from provider and workstation aspects; read state versions from the registry; write host facts once | `machines/nixos/magnetite/default.nix` (devNodes, uplink, MaxAuthTries, zram, stateVersion lines) | none | none |
| 4 | Move magnetite's service wiring into server aspects; generate its ZFS invariants | `machines/nixos/magnetite/default.nix`, `lib/observability-hosts.nix` | none | none |
| 5 | Make importing a module the decision; delete dead flags | `machines/nixos/magnetite/default.nix`, `{nixos,darwin,system}/shared-reference-tree.nix` | none | `vmTests.x86_64-linux.{devloop-ingest,devloop-ingest-reconcile,fleet-ingress,fleet-ingress-outage,greptimedb-oom-order,greptimedb-pipeline,shared-reference-tree,shared-reference-tree-migration}` and `vmTests.aarch64-linux.shared-reference-tree` where it exists, each `may-change` and resolved |
| 6 | State module identity, activation order and the named parts of base and ai | no | none | `checks.x86_64-linux.deploy-record-order changed` |
| 7 | List each darwin cache once | no | `darwin.{argentum,blackphos,rosegold,stibnite}` | those four `changed`, and `checks.aarch64-darwin.darwin-{argentum,blackphos,rosegold,stibnite}` `changed` |

- **Rationale**: one commit per reason to change, so a failed diff points at one cause and each can be reverted alone. Commits 1-6 are derivation-neutral for every host and home, so each ships with no deploy and none depends on a later one; 1, 2 and 6 touch none of the other session's files and can land before or between its commits; 3, 4 and 5 are rebased onto its landed commits. Commit 7 is last and alone because it is the only one that changes a host, so its deploy is explained by one cause. Every exact attribute in the allow-lists is re-read at the parent before the run (a `vmTests` attribute absent at both commits is a usage error).
- **Alternatives considered**: one commit (declare-host-user-relations-once's choice): there the groups shared files and were not separately shippable; here they are, and one diff over all of them could not say which commit changed what. Nine commits (activation order and caches split from identity): commit 6 is neutral for hosts and commit 7 already isolates the one host change.

### D13: the acceptance oracle per commit

- **Choice**: per commit, `just drv-diff` over parent and commit with that commit's allow-list. A difference the allow-list does not name is traced with `nix derivation show` (or `nix-diff`) to its definition order and fixed, never declared, unless the commit is 7. `just drv-diff-rejudge` re-judges a run after an allow-list correction without re-evaluating. `just eval-cost checks.x86_64-linux <parent> <commit> 2 keys` (and `aarch64-darwin`) runs for commits 6 (base and ai become named import lists) and is accepted within the parent's run-to-run spread.
- **Rationale**: equal drvPaths say the delivered closures are unchanged. Boundary: source-versus-delivered.

## Risks / Trade-offs

- [Risk] Moving a list definition into an imported aspect reorders the list (A344, A352) → Mitigation: write the moved definition with `lib.mkAfter` where the body's definition came last, order import lists to reproduce today's merge, and trace any drvPath difference with `nix derivation show`.
- [Risk] An aspect from `flake.modules` imported from two parents is applied twice, doubling a list (A351) → Mitigation: no aspect imports another from `flake.modules` (D1); `exportAs` keys the dual exports (D7).
- [Risk] Commits 3-5 conflict with the other session's edits of magnetite and the reference-tree files → Mitigation: those three are rebased onto that session's landed commits, and task 0.1 re-reads every cited line first.
- [Risk] A host imports the wrong provider aspect → Mitigation: each provider aspect asserts the registry's `cloud.provider` (D3).
- [Risk] The activation order values reproduce today's order on one Mac but not another → Mitigation: task 1.3 measures the order on all four before choosing values; the drvPath diff of commit 6 shows all four toplevels identical.
- [Risk] A generated ZFS unit differs in a description or condition → Mitigation: per-unit derivation comparison (task 6.2) before the full diff.
- [Risk] An archive-time conflict on `world-assumptions`' vocabulary → Mitigation: the delta copies the requirement as declare-host-user-relations-once's delta leaves it and only appends rows; rows added since are merged by hand at archive.
- [Trade-off] Seven diffs of about 16 minutes each → accepted: each commit is reviewable and revertible alone.
- [Trade-off] `knownUsers` order on the laptops now follows attachment order → accepted only because it reproduces today's order; a later attachment edit can reorder it, which the drvPath diff of that edit shows.
- [Known gap] The drvPath diff shows evaluated derivations equal, not that a deployed Mac behaves the same; the deploy of commit 7 is read from its activation output and the fleet alert topics.

## Migration Plan

1. Land this change after declare-host-user-relations-once (merged at `302236090`) and before seam-secrets-away-from-clan-vars. Commits 1, 2 and 6 may land while the other session is landing its four commits; commits 3, 4 and 5 wait until those have landed and are rebased onto them, and each re-records its task 1 baseline at its new parent.
2. Each commit is one pull request accepted on its own `just drv-diff` (D12). No deploy follows commits 1-6: every NixOS and darwin toplevel keeps its drvPath, so those hosts take the change at their next deploy without changing.
3. After commit 7 merges, deploy the four Macs (`clan machines update <h>`, or `just activate` on stibnite locally), in this order: stibnite first (the operator's own machine, deployed locally, where the `nix.conf` and daemon reload are observed), then argentum and rosegold, then blackphos when it is next online. For each: confirm `/etc/nix/nix.conf`'s `substituters` and `trusted-public-keys` lines list each cache once, and read every post on the fleet alert and failure topics since the deploy began. A Mac not deployed keeps the duplicate lines, which is harmless; it takes the change at its next deploy.
4. No NixOS host is deployed.
5. Rollback: revert the commit's pull request; for commit 7 on a deployed Mac, activate the previous generation (`sudo /nix/var/nix/profiles/system-<N>-link/activate`). No state is migrated.

## Pre-apply alignment

This table is the pre-apply spec-and-feature alignment record: one row per requirement in this change's delta specs, with the capability's stratum tag from the proposal and the executable check that realizes it. No row routes to a Gherkin scenario: the repository has no BDD runner, and every observable here is an evaluated value or a drvPath, which `nix eval`, the flake checks and their mutants, and `just drv-diff` witness. No row routes to an executable-specification modality: the mutants are example-based.

| Requirement | Capability | Stratum | Executable check | Witness |
|---|---|---|---|---|
| Each host's deployed system is unchanged apart from declared differences | `host-composition` | behavioral | `just drv-diff` per commit with its allow-list | tasks 2.4, 3.4, 4.6, 5.6, 6.6, 7.6, 8.5, 9.1 |
| A capability several hosts run is declared once | `host-composition` | behavioral | content searches; machine checks | tasks 3.1, 4.1, 4.4, 5.1, 6.1, 9.2 |
| A cloud server takes its provider's shape from one declaration | `host-composition` | behavioral | provider assertion and its mutant; machine checks `nixos-{cinnabar,electrum,galena,magnetite}` | tasks 4.1, 4.2 |
| A Mac's state version is declared once | `host-composition` | behavioral | `nix eval` of `system.stateVersion` per host; content search | task 4.3 |
| A darwin host's deploy record is the last thing its activation writes | `host-composition` | behavioral | `deployRecordObligations` in `darwin-*` machine checks; `deploy-record-order`'s `darwinSnippetAfterRecord` | tasks 7.3, 7.4 |
| Each darwin host consults each binary cache once | `host-composition` | behavioral | `nix eval` of `nix.settings`; `nix-diff`; deploy read-back | tasks 8.2-8.6 |
| magnetite's boot-enforced dataset properties are stated once | `host-composition` | behavioral | per-unit derivation comparison; `greptimedb-envelope` and its mutant; `otel-collector-config` | tasks 5.2-5.4 |
| The server aspects and cinnabar feature keys | `host-composition-interface` | interface | `nix eval` of `flake.modules.nixos` names and of magnetite's credentials; machine checks; runtime tests unchanged | tasks 3.1-3.3, 5.1, 5.5 |
| The provider aspects | `host-composition-interface` | interface | provider-assertion mutant | task 4.2 |
| The darwin-workstation aspect | `host-composition-interface` | interface | projections of users and knownUsers; `darwin-*` checks | task 4.4 |
| Hosts read their state version from the registry | `host-composition-interface` | interface | `nix eval` | task 4.3 |
| Importing a module is the decision | `host-composition-interface` | interface | content search; runtime tests resolved | tasks 6.1-6.6 |
| exportAs and the key spelling | `host-composition-interface` | interface | `nix eval` of keys; home drvPaths | task 7.1 |
| The activation order and the record-last judge | `host-composition-interface` | interface | `deploy-record-order`; mutant on a host | tasks 7.2-7.4 |
| The ZFS dataset table | `host-composition-interface` | interface | per-unit comparison; envelope check and mutant | tasks 5.2-5.4 |
| One cache writer per class | `host-composition-interface` | interface | content search; `nix eval` | task 8.1 |
| Named parts of base and ai; the otel-collector split | `host-composition-interface` | interface | `nix eval` of import lists; `eval-cost`; drv-diff | tasks 2.1-2.3, 7.5 |
| Only the declared derivations change | `host-composition-interface` | interface | `just drv-diff` per commit | each group's diff task |
| Trust boundary | `host-composition-interface` | interface | capability text | specs text |
| Each activation appends one deploy record (modified) | `devloop-collection-interface` | interface | `devloop-ingest` switch case; `deploy-record-order` | task 7.4 |
| The telemetry store and the collector run inside a declared envelope (modified) | `telemetry-store-interface` | interface | `greptimedb-envelope` and its mutant | tasks 5.2-5.4 |
| A350-A359 | `world-assumptions` | world | source reads (task 1.5); drv-diff (A351, A352, A356); deploy read-back (A353, A354); registry comparison (A358, A359) | tasks 1.5, 8.6 |
| Grounded vocabulary | `world-assumptions` | world | capability text | specs text |

## Open Questions

Each needs the operator; each carries the recommended answer.

1. **Key spelling.** Recommended: `vanixiets/<name>` (22 uses against 3), a parameter as `vanixiets/<name>?<param>=<value>` (`vanixiets/git?full=true`), and the three `vanixiets#…` keys migrated in commit 6. Keys affect deduplication only, so no drvPath changes.
2. **cinnabar feature keys.** Recommended: `caddy`, `caddy-root-ca`, `caddy-root-check`, `fleet-alert-deadman`, `matrix-server`, `ntfy-server`, `radicle-node`, `zt-dns-server`.
3. **GRUB on electrum, galena and scheelite.** Recommended: plain `false` on all three, since nothing sets `grub.enable` above its option default (srvos sets only `grub.devices`); if an evaluation or the diff disagrees, keep `mkForce` on that host with a comment naming the setter.
4. **NixOS state versions from the registry too.** Recommended: yes, in commit 3, so no host body states its version; every value is unchanged.
5. **Seven pull requests.** Recommended: as D12, about 16 minutes of operator-run diff each; the alternative of fewer commits loses the one-cause-per-diff property.
6. **The darwin deploy after commit 7.** Recommended: stibnite at once, argentum and rosegold at their next convenient deploy, blackphos when it is next online; nothing breaks while a Mac keeps the duplicate lines.
7. **Renaming `darwin/laptop.nix`.** Recommended: rename it to `darwin/darwin-workstation.nix` to match its key, and leave the ADRs under `packages/docs` that cite `modules/darwin/laptop.nix:69` unedited as dated records, so no docs-package check changes. The alternative edits those two ADRs and declares the twenty-eight docs checks `changed` in commit 3.
8. **The reference-tree flag.** Recommended: delete `services.shared-reference-tree.enable` in commit 5, after the other session's commits to those files land; the alternative leaves it, and commit 5 then touches only magnetite among that session's files.
