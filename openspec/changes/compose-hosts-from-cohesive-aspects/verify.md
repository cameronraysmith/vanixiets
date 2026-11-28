# Verification Report

**Change**: `compose-hosts-from-cohesive-aspects` (Linear CAM-132)
**Verified at**: `2026-11-28 07:33` (UTC), on stibnite

Implementation: ten pull requests on `main`. The design planned seven; commit 6b, stibnite's move into the workstation aspect and the shared-reference-tree flag deletion each landed separately.

| Pull request | Commit on main | What it carries | Compared (parent → commit) | Allow-list |
|---|---|---|---|---|
| 4443 | `a7028532a` | cinnabar's features under their own keys | `7018377df648 → 90b6d55bc555` | `drv-delta-cinnabar-feature-keys.txt` |
| 4448 | `b36b9b2a8` | otel-collector split by unit | `7018377df648 → 58fc0befa60a` | `drv-delta-otel-split.txt` |
| 4449 | `7aaff0b5d` | `exportAs`, key spelling, `activationOrder` | `58fc0befa60a → 24ee039d1247` | `drv-delta-module-identity.txt` |
| 4452 | `103a0427d` | one copy of each darwin cache | `3fea6f9b152e → f8501ab8302e` | `drv-delta-darwin-caches.txt` |
| 4453 | `1bc9415a6` | provider aspects, state versions, host facts, `darwin-workstation` for three Macs | `3fea6f9b152e → 77e4c7ca1118` | `drv-delta-provider-aspects.txt` |
| 4454 | `4c90592e9` | deploy record last, `darwinSnippetAfterRecord` | `3fea6f9b152e → 64daf36be12d` | `drv-delta-record-last.txt` |
| 4461 | `33f23d7c1` | magnetite's `<svc>-server` aspects, ZFS table | `ccc1a8db1932 → 7cf5441341be` | `drv-delta-magnetite-server-aspects.txt` |
| 4462 | `3ee7345ed` | seven `enable` flags and `custom.profile` deleted | `63172ebbd3db → 476ae0e097a5` | `drv-delta-flag-deletions.txt` |
| 4468 | `b728eddae` | stibnite imports `darwin-workstation` | `0f98c236fefd → 2455db80bf21` | `drv-delta-stibnite-workstation.txt` |
| 4470 | `e6c915824` | `services.shared-reference-tree.enable` deleted | `d1df742d0c2b → 60d5b489a064` | `drv-delta-reference-tree-flag.txt` |

Code was read from main's tree: `git archive origin/main` (`31d1365a10c3`) into `/tmp/chca-verify`, a fresh git repository. Line numbers below are at that revision. Since this change, main has taken in the secrets seam, name-the-parts-of-base-and-ai and shape-the-repository-for-its-readers. Each requirement is judged against main as it is now, and every place a later change superseded what this change specified is noted. Evaluations used `nix-stock` 2.35.6 in that tree. No `nix-eval-jobs` process was running at any evaluation.

---

## 1. Structural Validation (`openspec validate`)

- [x] Valid under `--strict`

```text
openspec validate compose-hosts-from-cohesive-aspects --strict -> Change 'compose-hosts-from-cohesive-aspects' is valid
```

---

## 2. Task Completion (`tasks.md`)

- [ ] All tasks closed: no, 49 of 56. Each open task carries its reason in `tasks.md`:

| Task | Why it stays open |
|---|---|
| 1.2 | the single baseline JSON was not written; each projection was recorded at its own commit's parent instead (the task lists where) |
| 7.5 | named parts were not done in this change. name-the-parts-of-base-and-ai did them (F6) |
| 7b.5, 8.6 | argentum, rosegold and blackphos are offline and not deployed since pull requests 4452 and 4454 and `ccc1a8db1`. stibnite also lacks a failure-topic read and a `chca-8-deploy-stibnite-*` log. The tasks say exactly what each Mac still needs |
| 9.1, 9.5 | not runnable as written: 23 other commits, several of them changing hosts, are interleaved with the ten, so one diff cannot isolate this change. The ten per-pull-request comparisons stand in its place (F7) |
| 9.4 | `docs/notes/development/architectural-principles.md` has stale lines outside this change directory (Leftovers 1-2) |

Closed or corrected at verify, with evidence:

| Task | Evidence |
|---|---|
| 0.1 | `logs/chca-0-reread-20261128T073009Z.md`. The design.md Context ranges and A357's range hold at their parents. proposal.md's `536-1058` was `527-1050` at `ccc1a8db1932` and is corrected there |
| 7.3, 7.4 | moved to group 7b and done there (7b.1-7b.4, pull request 4454) |
| 8.6 (stibnite, correction) | the daemon reload is evidenced: generation 259 (`p1k14mmd…`) is the first with an 11-entry `substituters` line (generation 258 had 21), and its activation log `logs/activate-stibnite-20261127-153640.log:49` reads `reloading nix-daemon...`. Generations 260-262 leave `nix.conf` unchanged, so the line is correctly absent from their logs |

Every comparison's report ends `result: PASS` with an empty `entries that did not occur:`:

```text
logs/drv-diff-7018377df648-90b6d55bc555-20261127T155245Z  PASS  (4443)
logs/drv-diff-7018377df648-58fc0befa60a-20261127T160955Z  PASS  (4448)
logs/drv-diff-58fc0befa60a-24ee039d1247-20261127T162658Z  PASS  (4449)
logs/drv-diff-3fea6f9b152e-f8501ab8302e-20261127T175933Z  PASS  (4452)
logs/drv-diff-3fea6f9b152e-77e4c7ca1118-20261127T181844Z  PASS  (4453)
logs/drv-diff-3fea6f9b152e-64daf36be12d-20261127T183428Z  PASS  (4454)
logs/drv-diff-ccc1a8db1932-7cf5441341be-20261127T193426Z  PASS  (4461)
logs/drv-diff-63172ebbd3db-476ae0e097a5-20261127T200140Z  PASS  (4462)
logs/drv-diff-0f98c236fefd-2455db80bf21-20261127T211630Z  PASS  (4468)
logs/drv-diff-d1df742d0c2b-60d5b489a064-20261127T215127Z  PASS  (4470)
```

---

## 3. Delta Spec Sync State

| Capability | Sync status | Notes |
|---|---|---|
| host-composition | pending sync | new capability; no main spec |
| host-composition-interface | pending sync | new capability; no main spec. Restate F2 and F4 before sync |
| devloop-collection-interface | pending sync | MODIFIED `Each activation appends one deploy record`: against main's text it changes only the darwin clause ("added last … at `flake.lib.activationOrder.deployRecord`"), the Discharged-by line, and adds two scenarios. No later change edited the requirement |
| telemetry-store-interface | pending sync | MODIFIED: one scenario line, `greptimedbDataset` → `flake.lib.zfsBootInvariants.magnetite`. The rest equals main's text |
| world-assumptions | pending sync | A350-A359 are not in `openspec/specs/world-assumptions/spec.md` and no other open change uses those ids. Correct A357-A359's Evidence lines at sync (World assumptions below) |

---

## 4. Requirement Trace

### Interface requirements (`host-composition-interface`)

| Requirement / scenario | Code on main | Evidence | Status |
|---|---|---|---|
| The server aspects and cinnabar feature keys | `nixos/{omnigraph,greptimedb,perses,fleet-alert}-server.nix`, imported at `machines/nixos/magnetite/default.nix:68-71`; none imports a `flake.modules` value (`rg imports` finds none in the four) | — | met. **Superseded**: the aspects declare `vanixiets.secrets.<name>` (`omnigraph-server.nix:81,121,138,152`, `greptimedb-server.nix:48,84`, `perses-server.nix:16`), not clan generators, after the secrets seam (`archive/2026-11-27-seam-secrets-away-from-clan-vars`). The site-neutral `{omnigraph,greptimedb,perses,fleet-alert,devloop-collection}.nix` read neither `clan.core.vars` nor `vanixiets.secrets` (`rg`: no match) |
| — The store's assertions stay with the host | `machines/nixos/magnetite/default.nix:307` onward (credential holders, `:333-342`; unit relations, `:397`, `:417`) | — | met |
| — The host keys are searched for | `rg -ln 'flake.modules.nixos."machines/nixos/cinnabar"'` → `default.nix`, `disko.nix` | run at verify | met |
| — The keys are listed | the four `<svc>-server` keys, the eight cinnabar keys and the site-neutral `greptimedb`, `perses`, `fleet-alert`, `omnigraph`, `devloop-collection` and `otel-collector-{agent,ingress}` are all present in `modules.nixos` | evaluated at verify | met |
| — magnetite's credentials are unchanged | — | `logs/chca-5-drvpaths-20261127T193305Z.log` (task 5.1); comparison 4461 shows magnetite identical | met at landing |
| — perses-server without greptimedb-server | — | `logs/chca-verify-mutant-perses-without-greptimedb-20261128T072755Z.log`: pyrite plus `fleet-alert-server` fails `attribute 'greptimedb-users' missing`; pyrite plus `perses-server` fails first on `attribute 'kanidm-oauth2-perses' missing` | met in part (F5) |
| The provider aspects | `nixos/hetzner-cloud.nix:87-130` (srvos import `:95`, assertion `:99-106`, `devNodes` `:117`, `10-uplink` `en*` `:121-129`); `nixos/gcp-cloud.nix:15-45` (assertion `:24-31`, `devNodes` `:34`, `en* eth*` `:36-44`, no srvos import); `MaxAuthTries` in `system/sshd-max-auth-tries.nix:5-7`, listed at `nixos/base.nix:37`, in no host module (`rg`) | — | met. **Extended later**: both aspects import `initrd-networking` (`hetzner-cloud.nix:96`, `gcp-cloud.nix:22`), and `hetzner-cloud.nix:23-30,108-114` sets the boot loader from the server type, by shape-the-repository-for-its-readers |
| — The provider aspects are read | hetzner-cloud imported at `cinnabar/default.nix:35`, `electrum/default.nix:24`, `magnetite/default.nix:36`; gcp-cloud at `galena/default.nix:23`, `scheelite/default.nix:26`; pyrite imports neither (`rg`: no match) | — | met |
| — A Hetzner host imports the GCP aspect | — | `logs/chca-verify-mutant-electrum-gcp-20261128T072720Z.log`, electrum's import swapped in a throwaway tree: `electrum imports flake.modules.nixos.gcp-cloud, but flake.fleet.hosts.electrum.cloud.provider is "hetzner", not "gcp"`; the control evaluates | met |
| — The NixOS hosts keep their values | evaluated at verify: `devNodes` by-path on the five cloud hosts and by-id on pyrite; `10-uplink` `en*` (Hetzner), `en* eth*` (GCP), none on pyrite; `MaxAuthTries` 20 on all six; `grub.enable` true on cinnabar and magnetite, false elsewhere | `logs/chca-4-drvpaths-20261127T180826Z.log` at landing | met. **Superseded for electrum**: this change wrote `grub.enable = false` in electrum's body. shape-the-repository-for-its-readers removed that line, and the value now comes from `hetzner-cloud.nix:109-114` (`ccx23` → systemd-boot) |
| The darwin-workstation aspect | `darwin/darwin-workstation.nix:17-92`: imports `:36-51`, documentation options written once and plainly `:56-62`, `computerName` `:64`, `targetHost` `:68`, `declaredSshd.serving` `:75`, human `users.users` per attachment with shell and keys skipped where `shellAndKeysFromUserService` `:77-87`, `knownUsers` in uid order `:30,90`; imported by `argentum/default.nix:4`, `blackphos/default.nix:7`, `rosegold/default.nix:4`, `stibnite/default.nix:19` | `lib/host-users.nix:69-72` (the attachment field), `:226-234` (the per-account agreement throw; mutant in `logs/chca-4-mutants-20261127T180131Z.log`) | met |
| — The Macs keep their values | evaluated at verify: on all four, the six documentation options are true, `computerName` is the host name and `serving` is true | three Macs equal at 4453; stibnite's `knownUsers` order and packages order changed, as `drv-delta-stibnite-workstation.txt` declares | met (stibnite as declared) |
| Hosts read their state version from the registry | `darwin/base-essentials.nix:56-59` (a part of `darwin.base`, `darwin/base.nix:9`); `system/nix-settings.nix:24-27` for NixOS; the registry description at `lib/hosts.nix:150` names the setters; no `system.stateVersion` in `machines/darwin` | — | met. **Location superseded**: name-the-parts moved the setting from `darwin/base.nix` into the `base-essentials` part |
| — The state versions are evaluated | — | evaluated at verify: `stateVersion` 4 equals the registry on all four Macs; `ids.gids.nixbld` 350 | met |
| Importing a module is the decision | the eight flags are gone (`rg` over `modules`: no match, exit 1); `custom.profile` and `darwin/profile.nix` are gone; presence tests at `clan/services/otel-collector/agent.nix:308,662-663`, `ingress.nix:56,326`, `darwin/omnigent-host.nix:157,451`, `lib/omnigent-fleet-obligations.nix:127`, `home/development/wezterm/default.nix:24`. Kept: `programs.mergify.enable` defaulting on (`home/development/mergify.nix:18,24`), `services.dnscrypt-proxy.enable` (`system/dnscrypt-proxy.nix:128`), `services.fleet-services-trust.enable` (`darwin/fleet-services-trust.nix:20`), `nixos/k3s-server/` | — | met. Why each was kept (`brainstorm.md:74`): mergify's default-on because `deploy-omnigent-magnetite` requires independently selectable capabilities; dnscrypt-proxy and fleet-services-trust because `darwin-workstation` imports them on every Mac (`darwin-workstation.nix:33-35`), so `enable` is the per-host decision (fleet-services-trust is set at `machines/darwin/blackphos/default.nix:65` and `stibnite/default.nix:179`; dnscrypt-proxy in each Mac's `services.dnscrypt-proxy` block); k3s-server because its consumers are planned (ADR-007) |
| — A deleted flag is searched for | — | `rg` at verify: no match | met |
| — A runtime test diverges from magnetite | `vm-tests/greptimedb-oom-order.nix:59-67` (the guards' own rules evaluated alone) and `:91-92` (the assertion naming the module) | — | met |
| exportAs and the key spelling | `lib/export-as.nix:29-43` (`key = "vanixiets/${key}"`, set on the module itself); used in the seven files of 7.1 and since in `system/secrets.nix:298`, `system/hm-sops-bridge.nix:175` | `rg 'key = "vanixiets#'`: no match | met in part: `home/development/gh-dash.nix:23` sets `key = "vanixiets:gh-dash-prs-keyed"` (F1) |
| — A home imports an aggregate and one of its parts | `home/terminal/fd.nix:3-4` | home drvPaths equal at 4449 (`logs/chca-7-drvpaths-20261127-160716.log`) | met at landing. That `fd` is applied once is inferred from its key, not evaluated |
| — The two git instances | `home/development/git.nix:171-177`: keys `git?full=true` and `git?full=false`, prefixed to `vanixiets/…` | — | met |
| The activation order and the record-last judge | `system/deploy-record.nix:205-218` (`deployRecord = 1900`, the largest `postActivation` priority); users `darwin/resolver-reload.nix:99`, `darwin/casks.nix:36`, `system/dnscrypt-proxy.nix:307`, `darwin/fleet-services-trust.nix:25`, `machines/darwin/stibnite/default.nix:165`, `system/deploy-record.nix:261`; judge `:120-134,160-165`; case `checks/deploy-record-order.nix:54` with `problems = 1` (`:36-40`) | — | met. **Extended later** by pull request 4511: `localDevelopmentCa = 999` and the `launchd.*` slots 400-403 |
| — The order is unchanged on the Macs | — | 4449: the four texts equal byte for byte (task 7.2); 4454 then moved the record last, as declared | met at landing |
| — A snippet is placed after the record | `checks/machines.nix:61-84` prefixes each message with the obligation's name (`:69`) | `logs/chca-verify-mutant-record-last-20261128T072821Z.log`: a `mkOrder 2000` snippet on argentum yields `argentum: postActivation runs \`echo mutant-after-record\` after the deploy record, before the relink`; the four unmutated Macs yield none | met |
| The ZFS dataset table | `lib/zfs-boot-invariants.nix:20` onward (14 entries, evaluated at verify); units generated at `machines/nixos/magnetite/default.nix:152-184`; notified units at `lib/observability-hosts.nix:107`; `disko.nix` remains a literal | `logs/chca-5-drvpaths-20261127T193305Z.log` | met |
| — The generated units are compared | — | all fourteen identical at 4461 | met, except that "absent when `r2`" is false both before and after (F4) |
| One cache writer per class | `system/caches.nix:8-16` (`base-caches` for both classes), listed at `darwin/base.nix:26` and `nixos/base.nix:20`; `darwin/caches.nix` deleted | — | met |
| — A darwin host's caches are evaluated | — | evaluated at verify: 11 substituters, all unique, the ten of `lib/caches.nix` once each, last `https://cache.nixos.org/`, on all four Macs | met |
| Named parts of base and ai, and the otel-collector split | `clan/services/otel-collector/{_shared,agent,ingress,service}.nix`, `_shared.nix` imported at `agent.nix:16`, `ingress.nix:5`, `service.nix:26`; `clan.modules ? otel-collector` is true. Named parts at `nixos/base.nix:8-44`, `darwin/base.nix:8-42`, `home/ai/default.nix:9-28` | — | otel split: met. Named parts: not done by this change (design Resolved Question 10). **Superseded** by `archive/2026-11-28-name-the-parts-of-base-and-ai/` (pull request 4509), which made the lists explicit and accepted the reordering as a declared difference. This change's decision to leave the parts implicit no longer describes main (F6) |
| — The key-set cost is measured | — | `logs/chca-1-keyset-cost-20261127-171420.log`, for 4449 only | met for the commit that changed keys |
| Only the declared derivations change | ten allow-lists in this directory | the ten reports above, all PASS | met per pull request. The text is not met as written: three pull requests (4452, 4454, 4468) name darwin toplevels, not one (F2) |
| — A commit's diff runs | — | each run exits 0 on its first judgement; no `may-change` entry remains | met |
| Trust boundary | — | — | met as a statement. Stibnite's `nix.conf` changed only at its deploy (generation 259) and no other Mac's has, which shows the stated boundary |

### Behavioral requirements (`host-composition`)

| Requirement / scenario | Discharged by | Status |
|---|---|---|
| Each host's deployed system is unchanged apart from declared differences | the ten comparisons | met. Four were run on a base or a compared commit other than the landed one (F7) |
| — A restructuring step is compared with its base commit | the reports | met |
| — A step changes a host it did not declare | — | not exercised: no comparison found one |
| A capability several hosts run is declared once | the aspects; task 9.2's `rg` (no match at verify) | met in part: `networking.useNetworkd = true; networking.useDHCP = false;` is written in both GCP hosts (`galena/default.nix:54-55`, `scheelite/default.nix:65-66`), which design D3 "As applied" leaves for later (F3) |
| A cloud server takes its provider's shape from one declaration | `hetzner-cloud`, `gcp-cloud` | met |
| — A host names the wrong provider's shape | the electrum mutant | met: it names electrum, `"hetzner"` and `gcp-cloud` |
| — A host that is not a cloud server | pyrite imports neither; `devNodes` by-id; no `10-uplink` | met |
| A Mac's state version is declared once | `lib/hosts.nix:396,416,436,456` | met |
| A darwin host's deploy record is the last thing its activation writes | `activationOrder.deployRecord`, the judge, the machine checks | met in evaluation on all four Macs (the last `postActivation` line is the record). On a running Mac: stibnite only, `activate:4589` then the relink comment at `:4591`, re-read at verify. The uid comparison is at `:36-47`, ahead of every step that changes the Mac |
| — A step is added after the record | the mutant above | met |
| Each darwin host consults each binary cache once | `base-caches` | met in evaluation on all four. Deployed only on stibnite (`/etc/nix/nix.conf`: 11 and 11; task 8.6). In `trusted-public-keys`, `cache.nixos.org-1` still appears twice (nix-darwin's own and `lib/caches.nix`'s, design D10), so the key list holds a duplicate the cache list does not (F9) |
| — The caches are read after the change is deployed | operator read | stibnite only; argentum, rosegold and blackphos open (7b.5, 8.6) |
| magnetite's boot-enforced dataset properties are stated once | the table; `greptimedb-envelope`'s `diskoMatchesDataset` | met (mutant `logs/chca-5-mutants-20261127T193254Z.log`) |

### MODIFIED requirements

| Requirement | Code on main | Status |
|---|---|---|
| `devloop-collection-interface`: Each activation appends one deploy record | `system/deploy-record.nix:227-240` (NixOS), `:246-265` (darwin, `preActivation` read `:255-260`, record at `activationOrder.deployRecord` `:261-263`) | met. Stibnite's last record line (`2026-11-28T06:31:05Z`) names `/run/current-system` (`p5a53lm7…`), read at verify |
| `telemetry-store-interface`: the dataset properties scenario | `nixos/greptimedb-server.nix:13-35` reads the dataset, quota and reservation from the table's greptimedb entries | met |

### World assumptions (A350-A359)

The lock has moved three times since these were written (`1dbea3712` delta, `cd05d7357` and `806079d6b` llm-agents). None of those moves touches a cited input, so every cited revision is still the locked one: nix-darwin `663d8b962a11`, nixpkgs `bd5b7d01ccc4` (nix-darwin follows harmonia's nixpkgs, which follows the root's), flake-parts `ea2630b74709`, srvos `e151e24ac800`, clan-core `78d5de23bd56`, import-tree `eb1b52eaecc5`. The cited files were re-opened at `nix-stock eval --raw .#inputs.<name>.outPath`:

| Id | Citation | Holds today |
|---|---|---|
| A350 | `activation-scripts.nix:114-151` (`postActivation` `:140`, last other `:138`, relink `:146`); `write-text.nix:25-31`; `types.nix:794-813`; `modules.nix:1417-1422,1652-1668` | yes, line for line |
| A351 | `modules.nix:543-546` (fallback key at `:546`), `:765,783`, `:463-468`, `:594-614`; flake-parts `extras/modules.nix:12-28` (`# TODO: set key?` at `:24`), `:72`; `types.nix:1992-1998` | yes |
| A352 | `modules.nix:594-614`; `types.nix:1992-1998` | yes. Its measured consequence for package lists no longer applies: shape-the-repository-for-its-readers sorts package lists and the Brewfile (`system/package-order.nix`). The assumption still governs every other list option, for example stibnite's `users.knownUsers` order |
| A353 | `nix/default.nix:38-50`, `:622-657` (`substituters` `:622-623`, `trusted-public-keys` `:656-657`), `:947-949` | yes |
| A354 | `nix/default.nix:935`, `:937` (inside `:928-943`) | yes. Observed on stibnite at generation 259 (`logs/activate-stibnite-20261127-153640.log:49`) |
| A355 | srvos `shared/server.nix:26-29`, `darwin/server/default.nix:14-15`, `nixos/hardware/hetzner-cloud/default.nix:16`, `shared/common/well-known-hosts.nix` (only `programs.ssh.knownHosts`); clan-core `nixosModules/clanCore/defaults.nix:38-45` | yes. The srvos modules imported are unchanged: `nixosModules.server` (9 sites), `darwinModules.server`, `mixins-nginx`, `hardware-hetzner-cloud` and pyrite's `well-known-hosts.nix` |
| A356 | import-tree `default.nix:64-68` (`nixFilter` at `:64`), `:83-87` | yes. `modules/_disabled/` still exists; `_shared.nix` is read only by its three importers |
| A357 | `machines/nixos/magnetite/default.nix:222-228` "at the time of writing" | the claim holds and the cited range was right at `ccc1a8db1932`. On main the comment is at `machines/nixos/magnetite/default.nix:152-161` and `lib/zfs-boot-invariants.nix:9-12` |
| A358 | `lib/hosts.nix:328-367`; `darwin/base.nix:43-52` | no longer at those lines. The Mac records' `stateVersion = 4` is at `lib/hosts.nix:396,416,436,456`; the nixbld note is at `darwin/base-essentials.nix:44-54` (name-the-parts moved it). The three `mkForce 4` lines are gone, as this change intended |
| A359 | `flake.lib.cloudMachines`; derived `cloud.provider`; "the comments at galena's and scheelite's imports" | in part. `cloudMachines` is at `lib/cloud-machines.nix:19` and the derived provider at `lib/hosts.nix:28-38`. Neither import (`galena/default.nix:23`, `scheelite/default.nix:26`) carries a comment; the nearest, `galena:53` and `scheelite:64`, says only "the uplink is gcp-cloud's" |

No violation of any assumption was observed.

### Findings

- **F1, one first-party key breaks the spelling.** `home/development/gh-dash.nix:23` has `key = "vanixiets:gh-dash-prs-keyed"`, added by `709ada4e3` (pull request 4511, after this change). The requirement says every first-party `key` uses `vanixiets/`.
  - Correction (2026-11-28, after verify): the key is now `vanixiets/gh-dash-prs-keyed`, written as a literal as the repository's other inner modules write theirs (`otel-collector/_shared.nix:66`); `exportAs` builds `flake.modules` attribute sets, not an inner import. Measured on `31d1365a10c3` and that tree with the one line changed: the twenty standalone homes' activation drvPaths, the ten toplevels and the nineteen integrated homes' activation drvPaths are identical. Not yet landed.
- **F2, "Only the declared derivations change" describes a plan, not what landed.** It says seven commits, of which only the seventh names a toplevel. As landed: ten pull requests. 4452, 4454 and 4468 each change darwin toplevels; 4462 and 4470 change checks only. Restate it as: "Each of the change's pull requests SHALL pass `just drv-diff` against its own `drv-delta-*.txt`; only `drv-delta-darwin-caches.txt`, `drv-delta-record-last.txt` and `drv-delta-stibnite-workstation.txt` name a host toplevel, and only darwin ones."
  - Correction (2026-11-28, after verify): `host-composition-interface`'s requirement is restated as ten pull requests, each against its own `drv-delta-*.txt`, of which 4452, 4454 and 4468 name darwin toplevels by declaration; design.md's goal carries an "As landed" line.
- **F3, GCP hosts repeat their networkd lines.** `galena/default.nix:54-55` and `scheelite/default.nix:65-66` both set `useNetworkd`/`useDHCP`. Design D3 "As applied" defers moving them into `gcp-cloud`. The scenario "A shared statement is copied into a host" holds for them.
  - Correction (2026-11-28, after verify): recorded as a follow-up in design.md, not done.
- **F4, the r2 scenario claims more than the code does.** Task 5.2 found that with `omnigraphRootStore = "r2"`, `zfs-set-root-omnigraph-quota` is an empty unit (`enable = true`, no `ExecStart`, no `wantedBy`), not absent, both before and after. The scenario should say "has no `ExecStart` and no `wantedBy` when the root store is `r2`, as before".
  - Correction (2026-11-28, after verify): the scenario now says the unit is empty (no `ExecStart`, no `wantedBy`) when the root store is `r2`, as before.
- **F5, the dependency scenario's wording predates the secrets seam.** A server aspect without greptimedb-server fails on a missing `vanixiets.secrets` attribute, not on a named generator. `fleet-alert-server` names `greptimedb-users`. On pyrite, `perses-server` fails first on `kanidm-oauth2-perses`, because it also reads kanidm's secret. The scenario should say "fails naming the missing `vanixiets.secrets` entry (`greptimedb-users`, or for perses-server first `kanidm-oauth2-perses` where kanidm is absent)".
  - Correction (2026-11-28, after verify): the scenario now names the missing `vanixiets.secrets` entry, `greptimedb-users`, or for `perses-server` on pyrite first `kanidm-oauth2-perses`.
- **F6, superseded by later changes.**
  - The secrets seam: every clan vars read is behind `vanixiets.secrets`, including in the four server aspects.
  - `nixos.base`, `darwin.base` and `homeManager.ai` are explicit lists of named parts. This change's Resolved Question 10 and D11, which leave them implicit, are superseded by `openspec/changes/archive/2026-11-28-name-the-parts-of-base-and-ai/`.
  - Package lists are sorted, so A352's measured consequence holds only for other list options.
  - `activationOrder` gained `localDevelopmentCa` and four `launchd` slots.
  - The `initrd-networking` part moved into the two provider aspects.
  - Electrum's boot loader comes from `hetzner-cloud`'s server-type mapping.
  - The registry carries `tags` and `description` (`lib/hosts.nix:72-92`).

  None of these breaks a requirement here except as F1 and the Named-parts row note.
- **F7, four comparisons ran on other ids than landed.**
  - 4461 and 4462 were compared on `ccc1a8db1932` and `63172ebbd3db`. Those bases lack `d2b222d1e` and `1d9c9dd54` (shared-reference-tree and ghq-shared), which the landed parents carry; the patches are equal (task 1.1).
  - 4468 was compared on `0f98c236fefd` and landed on `ae13fcfa1`. Outside `openspec/`, the compared and landed trees differ only in `packages/docs/…/traceability/satisfaction.md`.
  - 4470's compared commit differs from `e6c915824` only in one line of `docs/notes/development/architectural-principles.md`.

  No comparison covers the landed pairs. Nixbot built every check at the heads of 4461 and 4462 (tasks 5.3, 6.4).
- **F8, nothing enforces `flake.nix`'s `nixConfig` equal to `lib/caches.nix`.** Only comments link them (`lib/caches.nix:1`, `system/caches.nix:2`). Today they agree as sets (`flake.nix:224-250`); the key order differs (catppuccin, cuda, scientistexperience, cameronraysmith versus thalheim's position).
  - Correction (2026-11-28, after verify): recorded as a follow-up in design.md, not done. The two still match as sets.
- **F9, the `cache.nixos.org-1` key appears twice on every Mac.** Once from nix-darwin (`nix/default.nix:947`) and once from `lib/caches.nix`. Design D10 notes it as outside this change.
- **F10, task 8.6's "daemon reload not evidenced" was wrong for stibnite.** It was evidenced at generation 259 (task 8.6 correction).
  - Correction (2026-11-28, after verify): stibnite's failure topic was read. `logs/fdp-alerts-read-20261128T0659Z.log` read `fleet-alerts`, which is also the failure notifier's topic (`lib/observability-notify-run.nix:98`; stibnite's notifiers at `darwin/otel-collector-agent.nix:316,480` pass no other), from 06:15Z to 06:59:37Z with no message. Task 8.6 carries a bullet saying so.
- **F11, tasks 9.1 and 9.5 cannot run as written** (task 9.1's note).

### Leftovers

1. `docs/notes/development/architectural-principles.md:192` (O02 status) says stibnite does not import `darwin-workstation` and keeps seven `lib.mkForce true` lines, and that electrum writes `grub.enable = false`. It should say: resolved. stibnite imports the aspect since pull request 4468 (`b728eddae`), and no Mac writes the documentation options; electrum's loader comes from `nixos/hetzner-cloud.nix`'s server-type mapping (shape-the-repository-for-its-readers).
2. The same file, `:340` (O19 template status), should say the template is resolved, with all four Macs importing it (4453, 4468). `:587` should say: O02, O05 (with the shared-reference-tree flag deleted by pull request 4470, `e6c915824`) and the template half of O19 are closed by this change; O44 is closed by name-the-parts-of-base-and-ai (pull request 4509).
   - Addressed (2026-11-28, after verify): lines 192, 340 and 587 are restated as above, each checked against main's code first. Not yet landed.
3. `modules/home/development/gh-dash.nix:23`: the key should be `vanixiets/gh-dash-prs-keyed` (F1).
4. `modules/machines/nixos/{galena,scheelite}/default.nix`: `networking.useNetworkd`/`useDHCP` belong in `modules/nixos/gcp-cloud.nix` (F3), in a later change accepted on its own comparison.
5. Either a check comparing `flake.nix`'s `nixConfig` with `lib/caches.nix`, or comments at both saying the two are kept equal by hand and nothing checks it (F8).
6. In this directory, before sync: restate `host-composition-interface` for F2, F4 and F5, and correct A357's, A358's and A359's Evidence lines to the locations above. These are text edits to this change's specs, not made at verify.
   - Addressed (2026-11-28, after verify): F2, F4 and F5 are restated, and A357's, A358's and A359's Evidence lines cite main's lines at `31d1365a10c3`; A359 cites the registry and the provider assertion, and says `1bc9415a6` removed the import comments.

---

## 5. Implementation Signal

**Commits**: `a7028532a`, `b36b9b2a8`, `7aaff0b5d`, `103a0427d`, `1bc9415a6`, `4c90592e9`, `33f23d7c1`, `3ee7345ed`, `b728eddae`, `e6c915824`. They are interleaved with 23 other commits between `7018377df648` and `e6c915824`.

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

- [x] No files under `docs/superpowers/specs/` (the directory does not exist)

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

`plan.md` has no `[~]` rows. Deploy-time verification is open for three Macs:

- stibnite: deployed at main `d705c39bd6c6` (`logs/fdp-stibnite-*-20261128T06*.log`). `/etc/nix/nix.conf` lists each cache once, the record is the last `postActivation` step, the daemon reload is observed at generation 259, and `fleet-alerts` was read empty from 06:15Z to 06:59Z. The failure topic was not read.
- argentum and rosegold: offline; their `nix.conf` still lists the ten caches twice, and their record is not yet last.
- blackphos: not online.
- cinnabar, magnetite and pyrite: deployed at `d705c39bd6c6` (`logs/fdp-*`). No requirement here asks for evidence from them, and their toplevels were identical across all ten comparisons.

## 8. Designation Lint and Discharge Coherence

**8a.** The content nouns of `host-composition` resolve to rows of the world-assumptions delta table or to existing rows: host, capability, cloud provider, provider shape, fleet description, state version, deploy record, activation, binary cache, boot-enforced dataset property, install-time declaration, operator.

**8b.**

| Requirement | Discharged by (S) | Under (W) | Status |
|---|---|---|---|
| Deployed system unchanged apart from declared | the ten comparisons | A351, A352 | met (F7) |
| Capability declared once | the aspects, task 9.2 | A355 | met in part (F3) |
| Provider shape from one declaration | the provider assertion | A359 | met |
| Mac state version once | `base-essentials`, the registry | A358 | met |
| Deploy record last | `activationOrder`, `deployRecordObligations` | A350 | met; deployed on stibnite only |
| Each cache once | `base-caches` | A353, A354 | met in evaluation; deployed on stibnite only |
| Dataset properties once | the table, `greptimedb-envelope` | A357 | met |

**8c.** Machine phenomena named here (the deploy record, `nix.conf`, ZFS properties) are designated shared in the world-assumptions table; A354 and A357 carry the observation each rests on.

---

## Overall Decision

- [ ] (pass) PASS
- [x] (warn) PASS WITH WARNINGS, NOT READY FOR ARCHIVE. The code on main meets every requirement this change implements. The exceptions: one first-party key breaks the spelling (F1, a later change), the GCP hosts repeat two networkd lines (F3), and three interface statements describe a plan or a pre-seam wording rather than the code (F2, F4, F5). The named-parts decision is superseded, and main now has the named lists. Before archive:
  - deploy argentum and rosegold, then blackphos, as tasks 7b.5 and 8.6 state, and read stibnite's failure topic;
  - restate F2, F4 and F5 and correct A357-A359's Evidence lines in this directory (Leftover 6);
  - land Leftovers 1-3 outside this directory, or record them as follow-ups.

Tasks 1.2, 7.5, 9.1, 9.4 and 9.5 stay open with their reasons and do not block archive unless the operator decides otherwise.
