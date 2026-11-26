<!--
Raw capture of the decision chain for this change.
No interactive brainstorming session ran. The operator settled the scope on 2026-11-26 from a static-reading review of the fleet's module composition (a session artifact outside the repository, whose figures are restated here so this file stands alone), together with four decisions: the person and account keys are not renamed, the host registry becomes a typed option, disko stays an independent declaration of the ZFS datasets, and stibnite's `controller` inventory tag is renamed to `deployer-workstation` by `type-the-fleet-host-registry`, not by this change.
Every file:line below was re-read against the working tree on 2026-11-26; paths are relative to `modules/` unless they begin with `openspec/`.
This change's design waits on two others (Q1); the forks that cannot be settled until they land are left open in Q14 and repeated in proposal.md. The darwin `stateVersion` fork was closed on 2026-11-26: `type-the-fleet-host-registry` owns and fills the field, and this change makes hosts read it (Q4). The cloud-server fork was closed the same day: separate Hetzner and GCP aspects (Q4).
-->

# Brainstorm: compose each host from cohesive, reusable aspects

## Background

Every feature in the fleet is an import-tree aspect under `flake.modules.<class>.<name>`, and each host is one deferred module imported once by `clan/machines.nix`.
That is the right shape, but the host bodies still carry service wiring, copied boilerplate and priority fights, and the composition depends on facts nothing names: import order, the attribute a module was imported under, and duplicated aggregates.

What the tree shows today:

- **magnetite's body is a service host.** `machines/nixos/magnetite/default.nix` is 1,140 lines. Lines 536–1058 declare the omnigraph generators and `services.omnigraph` (536–743), the GreptimeDB and Perses generators and credentials (745–880), the store's credential-holder and unit-relation assertions (886–1011), the `greptimedb-envelope` and `devloop-reconcile` credentials (1013–1047) and the fleet-alert evaluator (1049–1058).
- **cinnabar's features are keyed to the host.** Nine files under `machines/nixos/cinnabar/` (`caddy.nix:7`, `caddy-root-ca.nix:13`, `caddy-root-check.nix:11`, `fleet-alert.nix:7`, `matrix.nix:55`, `ntfy.nix:3`, `radicle.nix:3`, `zt-dns.nix:51`, plus `disko.nix:4`) all assign `flake.modules.nixos."machines/nixos/cinnabar"`, so none of them can be reused or tested apart from cinnabar.
- **Five cloud servers repeat the same boilerplate.** `systemd.network.networks."10-uplink"` (`cinnabar:75`, `electrum:74`, `galena:70`, `magnetite:1091`, `scheelite:81`), `boot.zfs.devNodes = "/dev/disk/by-path"` (`cinnabar:45`, `electrum:41`, `galena:40`, `magnetite:146`, `scheelite:44`) and `MaxAuthTries = 20` (those five plus `pyrite:640`; darwin sets it once in `darwin/base.nix:20`). pyrite uses `/dev/disk/by-id` (`pyrite:150`) and is not a cloud server. Of the five, only cinnabar, electrum and magnetite import `srvos.nixosModules.hardware-hetzner-cloud`; galena (`:22`) and scheelite (`:25`) are GCP and say so, and their uplink matches `en* eth*` where the Hetzner hosts match `en*`.
- **Host facts are written as priority fights.** `darwin/base.nix:54` sets `system.stateVersion = 5` and `darwin/laptop.nix:72`, `blackphos:63` and `stibnite:79` force it to 4, so no darwin host uses the base value. Documentation is re-enabled with seven `mkForce` lines in each of `laptop.nix:55-61`, `blackphos:44-50` and `stibnite:59-65`. `system/zram-swap.nix:11` sets `memoryPercent = 100` plainly, so magnetite must force 150 (`magnetite:1069`). `boot.loader.grub.enable = lib.mkForce false` appears at `electrum:48`, `galena:46` and `scheelite:50`.
- **blackphos and stibnite copy `darwin/laptop.nix`.** argentum and rosegold import `flake.modules.darwin.laptop`; blackphos (`:25-62`) and stibnite (`:28-92`) restate its imports, documentation block, target host, platform, state version and `custom.profile`. The template hard-codes `system.primaryUser = "cameron"` (`laptop.nix:75`) with cameron at uid 502 (`:108-109`) and the primary user at uid 501 (`:100-101`); blackphos's admin is crs58 at uid 502 with raquel at 506 (`blackphos:87,133-143`), and stibnite's crs58 is both admin and primary at uid 501 (`stibnite:90,132-134`).
- **Features are opted into twice, and some flags are dead.** A host imports a module and then sets its `enable`: memory-pressure-guards (`magnetite:80/1084`, `pyrite:80/728`), colima (`stibnite:38/179`), shared-reference-tree (`stibnite:43/46`, `magnetite:103/131`, `pyrite:81/87`), greptimedb (`magnetite:96/855`), and the stibnite-session pair (`system/stibnite-access.nix:45,82`). `custom.homebrew.enable` (`darwin/homebrew.nix:97`) is true wherever the module is imported, and `services.moshi-hook.enable` defaults to true inside the module that declares it (`home/ai/moshi/default.nix:181`). `custom.profile` (`darwin/profile.nix:16-38`) is set by three hosts and read by none.
- **Dual-exported modules have no identity.** `home/terminal/{fd,jq,ripgrep}.nix:10-11`, `home/terminal/direnv.nix:87-88`, `home/tools/agents-md.nix:81-82` and `home/ai/atomic/default.nix:138-139` export one value under an aggregate and under its own name; `home/development/git.nix:170-171` exports a parameterised value under two names. claude-sandbox imports both the `terminal` aggregate and `fd`, `jq` and `ripgrep` (`home/users/claude-sandbox/meta.nix:26-48`). Without a `key`, the module system cannot tell that the two are one module. Two spellings of `key` are already in use: `vanixiets#…` (`nixos/observability-notify.nix:82`, `clan/services/otel-collector/flake-module.nix:94`) and `vanixiets/…` (`home/ai/agent-telemetry.nix:133`, `home/ai/openspec/default.nix:21`).
- **The darwin deploy record is last only by import order.** `system/deploy-record.nix:192-195` says `mkAfter` places the record after every other `postActivation` addition, but `darwin/casks.nix:33`, `darwin/fleet-services-trust.nix:16` and `system/dnscrypt-proxy.nix:305` add at the same `mkAfter` priority, so the order among them follows the import list (`laptop.nix:36-44`).
- **The otel-collector flake-module holds three units.** `clan/services/otel-collector/flake-module.nix` is 1,743 lines: a shared `let` (from :33), `flake.modules.nixos.otel-collector-agent` (:232), `flake.modules.nixos.otel-collector-ingress` (:1059) and the clan service `flake.clan.modules.otel-collector` (:1372).
- **magnetite's ZFS boot invariants are written out by hand.** Fourteen `systemd.services.zfs-*` oneshots (`magnetite:238-440`) each set or assert one dataset property; their names are repeated in `lib/observability-hosts.nix:82-95` as magnetite's `notifiedUnits`. Only GreptimeDB's three already read a `greptimedbDataset` binding (`magnetite:24-33`), and `checks/greptimedb-envelope.nix:544-549` compares those against `disko.nix` by string suffix.
- **The base and ai aggregates have no named parts.** 32 files contribute to `darwin.base`, 27 to `nixos.base`, and 19 to `homeManager.ai`; a reader cannot say which concerns base is made of, and a host cannot take one harness without the rest.
- **darwin's caches are declared twice.** `darwin/caches.nix:9-11` and `system/caches.nix:8-10` both append `lib/caches.nix` to `darwin.base`'s `nix.settings.substituters` and `trusted-public-keys`, which are lists, so every darwin `nix.conf` lists each cache twice.

## Decision chain

Q1. What must land before this change?
Two changes introduce the contracts this one reads: `type-the-fleet-host-registry` (the typed `flake.fleet.hosts.<host>` record with `system` and `stateVersion`, read through the read-only `flake.lib.hosts` alias) and `declare-host-user-relations-once` (the per-(host, user) record with each user's role on the host and darwin uid, and the single `flake` value that replaces the ambient specialArg).
The darwin-workstation aspect (Q5) reads the admin and uids from the second; the state-version read (Q4) uses the field the first declares and fills.
Every other part (Q2, Q3, Q6–Q13) reads neither contract and could land before them; they are kept in this change because they edit the same host bodies.
A third, `establish-refactor-oracle`, provides `just drv-diff`, the acceptance for every step (Q13).
Landing order: after `declare-host-user-relations-once` and before `seam-secrets-away-from-clan-vars`, because all three edit `machines/nixos/magnetite/default.nix` and the cinnabar feature files. The full chain is `establish-refactor-oracle`, `stop-reading-other-hosts-configs`, `type-the-fleet-host-registry`, `register-fleet-obligations`, `declare-host-user-relations-once`, this change, `seam-secrets-away-from-clan-vars`; this change re-runs `just drv-diff` after rebasing onto its predecessor and archives in the same order.
Rejected: designing the darwin aspect against today's `custom.laptop.primaryUser` and literals, then redoing it when the relation record lands.

Q2. Where does magnetite's service wiring go?
Into a new `<svc>-server` aspect in each feature's file: `omnigraph-server`, `greptimedb-server`, `perses-server` and `fleet-alert-server`, holding the clan generators, `LoadCredential` and `EnvironmentFile` wiring, and host-side settings now in magnetite's body; magnetite imports them.
The site-neutral keys `flake.modules.nixos.{greptimedb,perses,fleet-alert,devloop-collection}` stay clan-free (`nixos/greptimedb.nix:3-4`), because the runtime tests import them with their own credentials.
The store's credential-holder and unit-relation assertions (`magnetite:886-1011`) stay in magnetite's body: they judge relations among one host's units, and evaluating them anywhere else would evaluate magnetite again.
Rejected: moving the wiring into the site-neutral keys (breaks the runtime tests and puts clan vars in modules that promise none); moving the assertions into a flake check.

Q3. How are cinnabar's features re-keyed?
Each of the eight feature files assigns `flake.modules.nixos.<feature>` under a name not already taken, and cinnabar's `default.nix` imports them; `disko.nix` stays on the host key.
The generators that are per-machine (`caddy-root-ca`, `ntfy-alerter-env`) stay in modules only cinnabar imports.
The files do not move, so the world assumptions that cite `machines/nixos/cinnabar/caddy.nix:29-34` and `ntfy.nix` keep their evidence.
Open: names that collide with existing site-neutral keys (`fleet-alert`, `matrix`, `zt-dns`) need a suffix; Q14.

Q4. How are host facts written once?
Base modules set what a host may change with `mkDefault`, and hosts write plain values: `darwin/base.nix:54` sets `system.stateVersion` with `mkDefault`, `system/zram-swap.nix:11` uses `mkDefault 100` so magnetite writes `150`, and the darwin-workstation aspect (Q5) writes the seven documentation options plainly, once, instead of three hosts forcing them.
The darwin `stateVersion` is read from the host record's `stateVersion` field, which `type-the-fleet-host-registry` declares and fills (4 for the four Macs) but reads nowhere (its design D9); this change switches the darwin hosts to it, every darwin host's resolved value stays 4, and the second copy D9 accepts until then disappears.
The resolved value of every option must be unchanged; the before/after drvPath diff (Q13) decides it.
`mkForce` stays where it overrides an upstream module that itself forces (`nixpkgs/per-system.nix:36-47`, `system/kvm-declaration.nix:60`).
The review's claim that clan-core disables darwin documentation is unverified, so `srvos.server.docs.enable` is set plainly and the diff confirms nothing else forces it.
GRUB: `boot.loader.grub.enable = lib.mkForce false` stays on each of electrum, galena and scheelite rather than moving into a shared aspect, because cinnabar and magnetite boot with GRUB. Only electrum's force is proven necessary (it imports srvos's Hetzner hardware module, which sets GRUB); galena's and scheelite's become plain values only if the diff shows nothing else sets GRUB there.
`services.openssh.settings.MaxAuthTries = 20` moves into `nixos.base`, because all six NixOS hosts set it, matching `darwin/base.nix:20`; pyrite gets it from base too and imports neither cloud-server aspect.
Cloud servers: the operator decided on 2026-11-26 for two aspects, one per provider. `hetzner-cloud`, imported by cinnabar, electrum and magnetite, holds srvos's `hardware-hetzner-cloud` import, the `10-uplink` network matching `en*`, and by-path `devNodes`. `gcp-cloud`, imported by galena and scheelite, holds the `10-uplink` network matching `en* eth*` and by-path `devNodes`, and imports no srvos Hetzner module. The providers differ in hardware module and uplink, so a host imports the provider it runs on instead of passing a provider switch to a shared aspect; the by-path `devNodes` line is written in both.
Rejected: one aspect for all five with the interface pattern as a parameter and srvos's Hetzner import left in the three Hetzner hosts.

Q5. How are blackphos and stibnite brought back to the template?
`darwin/laptop.nix` becomes `flake.modules.darwin.darwin-workstation`, parameterised by the host's admin and primary user and their uids, read from the per-(host, user) record; each darwin host imports it and keeps only its delta.
argentum and rosegold keep cameron as admin at 502 and their primary user at 501; blackphos keeps crs58 at 502 and raquel at 506; stibnite keeps crs58 at 501 as both.
stibnite's imports are a superset of the template's and stay in its delta.
nix-darwin's `system.primaryUser` (the admin who runs homebrew) stays distinct from the registry's primary user.
Rejected: a second template for single-user Macs (stibnite is a parameter value, not a different shape).

Q6. Which flags are deleted?
Where importing a module is the decision, its `enable` goes: memory-pressure-guards, colima, shared-reference-tree, greptimedb, the stibnite-session pair, `custom.homebrew.enable`, `services.moshi-hook.enable`, and all of `custom.profile`.
`or false` probes of a deleted flag become presence tests (`home/development/wezterm/default.nix:24` reads `osConfig.custom.homebrew.enable or false`).
The runtime tests that set `services.greptimedb.enable` (`vm-tests/devloop-ingest.nix:1658`, `vm-tests/fleet-ingress.nix:2154`) and the one that copies `memoryPressureGuards.enable` from magnetite (`vm-tests/greptimedb-oom-order.nix:116`) are edited to import or not import, the last conditioned on whether magnetite imports the module.
Kept: mergify's default-on (`deploy-omnigent-magnetite`'s "Independently selectable workflow capabilities" requires it), dnscrypt-proxy and fleet-services-trust imported on every darwin host with `enable` as the per-host decision (`laptop.nix:28-31`), and k3s-server, whose consumers are planned and must grow additively (`docs/notes/development/kubernetes/decisions/ADR-007-nixos-vm-tests-for-k3s.md:27,190`).
Deleting an option does not change an option manual here: nothing sets `documentation.nixos.includeAllModules`, so the manuals document upstream modules only. The diff (Q13) confirms it.

Q7. How do dual-exported modules get identity?
A `flake.lib.exportAs` helper assigns one value under several names and sets `key` on it; a parameterised value's key includes its parameter (`git.nix` becomes `…#git?full=true` and `…#git?full=false`, or similar), so the two instances stay distinct.
One spelling for keys is chosen and the existing keys are migrated to it; Q14.
A `key` affects only deduplication, so drvPaths stay the same.

Q8. How is the deploy record held last?
A `flake.lib.activationOrder` names the order of each `postActivation` contributor with `mkOrder`; the record takes the largest, and the others take positions in the order the import list gives them today.
`checks.<system>.deploy-record-order` gains a clause that the record is the last `postActivation` snippet on every darwin host, and a mutant that adds a later snippet and must fail.
The record stays ahead of the relink, because `postActivation` runs before it.
The darwin activation scripts may change if the chosen positions reorder any snippet; the diff declares that change.

Q9. How is the otel-collector flake-module split?
The shared `let` moves into an `_`-prefixed file that import-tree skips, and the three units into `agent.nix`, `ingress.nix` and `service.nix` beside it, each still assigning the same `flake.modules` names the runtime tests import.
Only the `forward` connector moves into the ingress role; the agent's `!ingress` branches (`:87-91`, `:250-263`) stay, because one collector serves both roles on the ingress host.

Q10. How are the ZFS invariants generated?
A `flake.lib` attrset lists magnetite's datasets and the properties each must hold; the fourteen oneshots and the `zfs-*` entries of magnetite's `notifiedUnits` are generated from it.
`disko.nix` stays a literal, independent declaration, so `greptimedb-envelope` still compares what was declared at install time with what boot enforces.
The generated units must be byte-identical to today's; the diff decides.
Rejected: generating disko from the same table (the envelope check would compare a value with itself).

Q11. How do base and ai get named parts?
`base` becomes a named imports list of sub-aspects, one per concern (caches, nix settings, ssh, obligations, and so on); `ai` becomes one aspect per harness (claude-code, codex, opencode, pi, omp, devin, omnigent and the shared settings), with `ai` importing all of them, so every current importer gets the same set.
The obligation modules imported by base stay in base (`postgresql-backup.nix:44`, `r2-usage.nix:35`, `zpool-probe.nix:184`), because every machine must run them.

Q12. What happens to the duplicate caches?
`darwin/caches.nix` is deleted; `system/caches.nix` stays the one source for both classes.
Each darwin host's `nix.conf` lists each cache once instead of twice, so every darwin toplevel changes; that change is declared.

Q13. What shows a step changed only what it declared?
`just drv-diff <parent> <tip> openspec/changes/compose-hosts-from-cohesive-aspects/drv-delta.txt` from `establish-refactor-oracle`: it compares every NixOS and darwin toplevel, every home activation package, every attribute of `checks.{x86_64-linux,aarch64-darwin}` and of `vmTests.{x86_64-linux,aarch64-linux}` at the two commits, and fails on a difference the allow-list does not name or on a `changed` entry that did not change.
The allow-list takes exact attribute paths, no globs. `changed`: `darwin.{argentum,blackphos,rosegold,stibnite}` for the cache change (Q12) and possibly the activation order (Q8), written out as four lines; the `checks.aarch64-darwin.darwin-<host>` check of each of the four, which embeds that host's darwin system; and `checks.x86_64-linux.deploy-record-order`, which gains its clause and mutant (Q8). `may-change`: `vmTests.x86_64-linux.devloop-ingest`, `devloop-ingest-reconcile`, `fleet-ingress`, `fleet-ingress-outage` and `greptimedb-oom-order`, each as its full path, whose nodes are edited under Q6 but are meant to resolve to the same configuration.
Everything else is expected unchanged, including the `nixos-*` machine checks and the runtime tests that import the moved otel-collector, GreptimeDB and Perses modules.
Rejected: `just eval-identity`, which compares the stock and iets evaluators at one revision and says nothing about two revisions.

Q14. What stays open?
- The new keys for cinnabar features whose natural names are taken.
- Which key spelling (`vanixiets#name` or `vanixiets/name`) wins, and how a parameter is written in it.
- Whether the darwin activation scripts change at all under Q8; the diff answers it.
- Renaming stibnite's `controller` inventory tag to `deployer-workstation` is owned by `type-the-fleet-host-registry` and is not part of this change: no inventory tag is read or written here.
