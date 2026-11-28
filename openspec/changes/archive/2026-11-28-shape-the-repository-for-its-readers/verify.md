# Verification Report

**Change**: `shape-the-repository-for-its-readers` (Linear CAM-142)
**Verified at**: `2026-11-28 05:55` (UTC), on stibnite

Implementation, three commits on `main`:

- Pull request 4497, commit `963e6ac6b15b`: host lists from the registry, `just composition` and the route obligation, the Hetzner boot mapping, the placement rules, the people constructors (design D5 steps 1-4, 2b and 7).
- Pull request 4509, commit `c69bbcac5565`: the package and Brewfile sort, the darwin `base` and `ai` parts lists, the two darwin halves moved to `system/` (steps 5b and 6).
- Pull request 4510, commit `d705c39bd6c6`: `initrd-networking` only through the two cloud aspects, `r2-usage` and `postgresql-backup` imported by magnetite (steps 6b and 6c). This is `origin/main`.

`git range-diff` shows `963e6ac6b` and the compared `c63a450f800e` carry the same patch, and `c69bbcac5` and the compared `de1600cb6e74` the same patch. The second comparison ran on parent `fb7b981f1e74`; the landed parent is `1c2b60fc1`, six commits later (the cognee removal, a relock, a `nix-build-locked` fix), so its result is for the same patch on an earlier base. The third comparison ran on the landed parent and commit.

Code was read from main's tree: `git archive origin/main` (`d705c39bd6c6`) into `/tmp/srr-verify`; line numbers below are at that revision. The working copy differs from main in `modules/README.md`, `modules/home/README.md` and the host-onboarding guide (text corrections made after the re-measure, not landed; see Leftovers), so it was not used for code. The re-measure was read from the working copy's `docs/notes/development/reader-measure/` and `tasks.md`.

---

## 1. Structural Validation (`openspec validate`)

- [x] This change reports valid under `--strict`

```text
openspec validate shape-the-repository-for-its-readers --strict -> Change 'shape-the-repository-for-its-readers' is valid
```

---

## 2. Task Completion (`tasks.md`)

- [ ] All tasks closed: no, 44 of 60. The 16 open tasks each carry their reason in `tasks.md`:

| Task | Why it stays open |
|---|---|
| 2.6 | `structure-fleet` holds no phantom; the interface requirement is not met (F3) |
| 5.5, 5.6, 5.7 | gh-dash bindings keyed by key, one overlay list, activation slots: not done; design D2(f) records each as open after the order step |
| 5.8 | `drv-order-trace.py` exits 1 on the ten toplevels and seven homes at the two home-delivered texts (F4) |
| 6.2 | the four files assigning into two aggregates were not split; no evidence recorded |
| 6.4 | the parts lists landed in the order step's commit; no comparison isolates them (F5) |
| 6b.2 | pyrite's orphaned `vars/per-machine/pyrite/initrd-ssh/` is kept for a separate removal; `sops-correspondence` does not flag it |
| 8.1-8.5 | the fleet deploy of cinnabar, magnetite, pyrite and stibnite is being prepared and has not run; argentum and rosegold are offline; no standalone home has been activated; the record of the undeployed hosts follows the deploy |
| 9.2 | `docs/notes/development/architectural-principles.md` carries no resolving commits and two stale lines (Leftovers 3-4); outside this change directory |
| 10.1b | the commands arm needs measuring agents with a shell; none has run |
| 10.2 | the `basalt` throwaway tree needs `clan vars generate` with the operator's keys and a full evaluation of a new host |

Closed at verify, with evidence:

| Task | Evidence |
|---|---|
| 2b.5, 3.5, 7.4 | the first-pass comparison (`logs/drv-diff-96a3c1ef8a8d-c63a450f800e-20261128T031645Z/report`, `result: PASS`) covers steps 2b, 3 and 7, which `963e6ac6b` carries |
| 3.3 | `logs/srr-corr-cost-20261127-220233.log`: three runs each of `checks.x86_64-linux.nixos-magnetite` with and without the judge, thunks 24,057,169 and 24,301,210, allocation 2,538 and 2,551 MB, CPU within the runs' spread. Measured by direct evaluation, since `just eval-cost` takes jj revisions |
| 5.9 | `logs/srr-5b-profiles-20261127-233804.log`: 54 profiles replayed with the locked `builder.pl` at parent and commit; every link has the same target. Not compared: scheelite's `nvidia-persistenced` (scheelite is not enabled) and the home members that were not substitutable. A home's profile aborts on differing files at one path (design D2(f)), so order cannot choose content there |
| 5.10 | `logs/drv-diff-fb7b981f1e74-de1600cb6e74-20261128T044712Z/report`, `result: PASS`, every entry of `drv-delta-order.txt` occurred |
| 6b.3, 6c.3 | `logs/drv-diff-c69bbcac5565-d705c39bd6c6-20261128T051525Z/report`, `result: PASS`, every entry of `drv-delta-host-content.txt` occurred |
| 6c.1 | `logs/srr-verify-hostfacts-20261128T054551Z.json`: only magnetite's `options.vanixiets` has `r2Usage` and `postgresqlBackup`. Every NixOS and darwin machine check's output at main is in `https://cache.scientistexperience.net` (`logs/srr-verify-machine-checks-cache-20261128T054953Z.log`) |
| 9.1 | `rg -n 'mkAfter' modules/lib/host-users.nix` on main finds nothing |
| 10.3 | `checks/machines.nix:61-84` folds every obligation, `compositionRoutes` among them, into an evaluation-time assertion. The third comparison evaluated all 277 and 118 checks at `d705c39bd6c6` with `0 failing-at-one, 0 failing-at-both`, and every machine check's output is in the cache (log above) |
| 10.4 | the three reports pass, and each lists no entry under `entries that did not occur:`, so each changed set equals its allow-list plus the base allow-list |

Corrections recorded under tasks already ticked: 1.1 (the grading script was not run on the baseline or the re-measure), 2.7 (the `basalt` mutant was not run; the check's own mutant shows the failure), 10.1 (E1's count).

Summary lines of the three comparisons:

```text
drv-diff 96a3c1ef8a8d -> c63a450f800e
nixos: 6 attributes; 6 identical, 0 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
darwin: 4 attributes; 4 identical, 0 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
home: 20 attributes; 20 identical, 0 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
checks.x86_64-linux: 274 attributes; 248 identical, 23 changed, 3 added, 0 removed, 0 failing-at-one, 0 failing-at-both
checks.aarch64-darwin: 118 attributes; 103 identical, 15 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
vmTests.x86_64-linux: 21 attributes; 21 identical, 0 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
vmTests.aarch64-linux: 3 attributes; 3 identical, 0 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
result: PASS

drv-diff fb7b981f1e74 -> de1600cb6e74
nixos: 6 attributes; 0 identical, 6 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
darwin: 4 attributes; 0 identical, 4 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
home: 20 attributes; 0 identical, 20 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
checks.x86_64-linux: 277 attributes; 236 identical, 41 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
checks.aarch64-darwin: 118 attributes; 93 identical, 25 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
vmTests.x86_64-linux: 21 attributes; 20 identical, 1 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
vmTests.aarch64-linux: 3 attributes; 2 identical, 1 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
result: PASS

drv-diff c69bbcac5565 -> d705c39bd6c6
nixos: 6 attributes; 5 identical, 1 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
darwin: 4 attributes; 4 identical, 0 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
home: 20 attributes; 20 identical, 0 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
checks.x86_64-linux: 277 attributes; 272 identical, 5 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
checks.aarch64-darwin: 118 attributes; 116 identical, 2 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
vmTests.x86_64-linux: 21 attributes; 21 identical, 0 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
vmTests.aarch64-linux: 3 attributes; 3 identical, 0 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
result: PASS
```

What the claims about each pass rest on:

- **First pass, "no host or home changes"** (commit message of `963e6ac6b`): met. All 6 NixOS, 4 darwin and 20 home attributes and all 24 runtime tests are identical. The 36 differing checks are the 3 added and 33 changed checks `drv-delta-first-pass.txt` declares, plus `gitleaks`, `treefmt` and `ntfy-tls-verification` under the base allow-list.
- **Second pass, "order only"**: met in part. Every toplevel and home changed, as declared. `drv-delta-order.txt:21-26` and `logs/srr-5b-trace-20261127-233754.log` show three leaves that are content, not order: the checks skill's ladder, `40-fleet-and-user-conventions.instructions.md` (both delivered into homes through `apm-deps` and `apm-skills-compose`), and `nixos-deployment.md`'s moved path. The other differences are `chosenOutputs` order, the gh-dash bindings' order and the Brewfile's in-section order (F4).
- **Third pass**: pyrite's toplevel changes in content: `virtio_net` and `virtio_pci` leave its initrd (`drv-delta-host-content.txt:20-26`). magnetite, the four other NixOS hosts, the Macs and every home are identical, as design Resolved Questions 3-4 expected.

---

## 3. Delta Spec Sync State

| Capability | Sync status | Notes |
|---|---|---|
| repository-shape | pending sync | new capability; no main spec |
| repository-shape-interface | pending sync | new capability; no main spec |
| world-assumptions | pending sync | A383-A386 are not in `openspec/specs/world-assumptions/spec.md`, and no other open change uses those ids. The designation table must be merged by hand with rows other changes added |
| apple-laptop-hardware-support | pending sync | MODIFIED: two requirements restated for initrd networking off by default plus pyrite's assertion |

---

## 4. Requirement Trace

### Interface requirements (`repository-shape-interface`)

| Requirement / scenario | Code on main | Evidence | Status |
|---|---|---|---|
| Each host list is derived from the registry or checked against it | `lib/hosts.nix:72-93` (`tags`, `description`), `clan/inventory/machines.nix:9-18`, `checks/sops-correspondence.nix:55-57`; the assert at the old `checks/machines.nix:78-79` is gone; ssh `logins` kept literal (`home/core/ssh.nix:15`) and exported as `flake.lib.sshLogins` (`:60`) | `logs/srr-int-clan-{main,work}-20261127-211625.json` | met. The ssh logins take the requirement's "where their values equal today's" exit: the admin attachment does not give today's logins (task 2.4) |
| — The derived lists are evaluated | no host literal in `clan/inventory/machines.nix` or in `machineAnchors` | first-pass comparison: `sops-correspondence` changes only in its anchors' order | met |
| — A list left by design is read | `justfile:50-63` reads `.#lib.hosts`, with no host list; the guide's `ztRecords` row | `logs/srr-corr-verify-20261127-215333.log` (`unknown hostname: nosuchhost …`, exit 1) | met |
| Hand-written host lists are checked, with controls | `checks/host-list-keys.nix:32-55` (three lists, three phantoms) | `logs/srr-verify-mutant-cloud-row-20261128T054734Z.log` | met for `host-list-keys`; not met for `structure-fleet` (F3) |
| — A cloud row names no host | — | mutant row `hetzner.basalt`: `actualJson` has `"basalt":false`, `expectedJson` `"basalt":true`. The check's builder is `diff -u` of the two (`lib/mk-structural-check.nix:33-38`), so it fails naming basalt | met |
| — The fleet pin's control | `checks/structure/flake-shape.nix:31` has no phantom | — | not met (F3) |
| The onboarding guide lists every generated step with its check | `host-onboarding.md:61-68` (key and vars, bridge files, `fleet-deployers` link, topology), each naming its check | `logs/srr-verify-sops-correspondence-20261128T054718Z.log` | met |
| — A new enabled host lacks its deployer group link | `sops-correspondence.nix:200-203`, its mutant `deployer-group-missing` at `:258-259` | `mutant 'deployer-group-missing' failed as expected: FAIL: argentum-age.key does not name the fleet-deployers group`. The output of main's drvPath is in the cache. The `basalt` tree was not run (task 10.2) | met for an existing target; a new host not run |
| A new Hetzner host's boot loader follows its server type | `nixos/hetzner-cloud.nix:23-30` (`loaderFor`), `:108-114` (set for `ccx*`, `cax*`), `:73-85` (`hetznerBootLoader`), registered at `checks/machines.nix:44`; `lib/hosts.nix:36-38` (`cloud.type` throws naming the host) | fixtures `checks/hetzner-boot-loader.nix:18-54` (seven cases) | met |
| — A host forces the other loader | — | `logs/srr-int-builds-mutants-20261127-212820.log` m3: `hetznerBootLoader: electrum boots with both grub and systemd-boot, but its Hetzner server type ccx23 boots with systemd-boot`; a missing type: `flake.fleet.hosts.electrum.cloud.type: … sets neither serverType nor machineType` | met |
| — electrum's lines removed | `machines/nixos/electrum/default.nix` has no boot-loader lines | first pass: `nixos.electrum` identical | met |
| A command prints any configuration's composition | `lib/composition.nix:131-167`, `justfile:84-87` | `logs/srr-verify-composition-20261128T054559Z.log` | met in part (F6) |
| — magnetite's composition | — | 83 names at main (81 at `c63a450f800e`; `base-package-order`, `nix-build-lock` and the renamed `initrd-networking` since); 3 names print with more than one route (`node-exporter-textfile` `base,include`, `ntfy-alerter` `clan,host`, `secrets` `clan,include,base`) | met in part: the scenario's "each with one route kind" does not hold for a name reached by several routes (F6) |
| — A home's systems | — | `crs58: home built for aarch64-darwin, aarch64-linux, x86_64-linux` | met |
| A named module arriving by an unknown route kind fails the machine check | `lib/composition.nix:118-129,174-183`; `checks/machines.nix:61-84` passes `configuration.graph` | fixtures `checks/composition-routes.nix`; mutant m2: `compositionRoutes: zt-dns reaches electrum from modules/clan/machines.nix by no known route` | met, within what it sees (F2) |
| — Its cost is measured first | — | `logs/srr-corr-cost-20261127-220233.log` (+1.0% thunks, +0.5% allocation) | met in part: measured directly, not by `just eval-cost`, and recorded in `tasks.md`, not beside the registration |
| Equal-priority collisions settled by priority | — | `logs/srr-5-profiles-20261127-223604.log`, `equal_prio_collisions` empty on all ten hosts | met: none to settle (scheelite's `nvidia-persistenced` not realised) |
| Package list order is irrelevant | `system/package-order.nix:13-33` | — | met for the five lists; not met for gh-dash and overlays (F1) |
| — The sorted lists' keys are read | `:16`, `:19`, `:26-28`, `:32`: only `apply`, packages by `lib.getName` or string, Homebrew by `name`; `builtins.sort` is stable | — | met |
| — The home sort reaches every home | `system/home-manager-integration.nix:63`, `home/mk-home.nix:32`, `darwin/omnigent-host.nix:110` | — | met |
| — A darwin part moves | — | `logs/srr-verify-mutant-darwin-order-20261128T055245Z.log`: `base-homebrew` moved after `base-mosh`; stibnite's and argentum's toplevel drvPaths unchanged | met |
| — The sort changes a file's content | — | `logs/srr-5b-profiles-20261127-233804.log` | met for the members compared (task 5.9) |
| Ordered-on-purpose lists take their order from one table | `system/deploy-record.nix:206-213` | four `launchd` `mkBefore` snippets (`darwin/omnigent-host.nix:479`, `darwin/otel-collector-agent.nix:229,426`, `darwin/shared-reference-tree.nix:279`) and stibnite's plain `postActivation` (`machines/darwin/stibnite/default.nix:164`) have no slot | not met (F1) |
| One check placement rule is documented | `checks/README.md:9-23`, the skill's ladder (`c69bbcac5`), `modules/README.md:75` | — | met: the README defers to `checks/README.md`; the skill states the same rungs and exception |
| One shape for a hand-entered secret | `system/secrets.nix:43-47`, `modules/README.md:73,136` | both cite `greptimedb-r2` in `nixos/greptimedb-server.nix` | met |
| The reader measure is committed, targets per-run | `docs/notes/development/reader-measure/` | `grade.py` takes a flat list of graded runs; neither the baseline nor `after.json` was run through it | met in part: the re-measure is hand-graded (F7) |

### Behavioral requirements (`repository-shape`)

| Requirement / scenario | Discharged by | Status |
|---|---|---|
| No host list kept by convention alone | derived lists; `host-list-keys`; the guide's table | met in part: `ztRecords` is named; the evaluator table in `modules/README.md` is a host list written by hand that no check reads and the count omits (F8) |
| — The operator adds a server | the guide's "Adding a host" section | met as text; the `basalt` trial was not run (10.2) |
| — A checked host list disagrees | `host-list-keys` | met (mutants: cloud row, pyrite tagged `cloud`, galena's login removed) |
| — A generated step is skipped | `sops-correspondence`, `fleet-topology-fresh`, the host-key obligation | met for the deployer link, shown on an existing target; the others not exercised here |
| Composition on request; routes known | `just composition`, `compositionRoutes` | met within F2 and F6 |
| — A reader lists what a host consists of | — | not measured: the commands arm did not run (10.1b) |
| One placement rule per kind of addition | `modules/README.md:63-75` | met in part: lines 69-70 are stale or misleading on main (Leftover 1) |
| — Three contributors | re-measure PL1, PL3, PL5 | PL1 and PL3 3 of 3; PL5 3 of 3 against the stated rule, 2 of 3 against the key |
| Restructuring delivers nothing but declared priority and order | the three comparisons | met in part (F4, F9) |
| Restructuring is accepted on what readers can do | the re-measure | not met: four of the measured targets miss (below) |

Measure targets of design D1, as the re-measure at `d705c39bd6c6` records them (`tasks.md` 10.1, `reader-measure/README.md`, "Re-measure"), tree arm, three runs per hard task, one per lookup:

| # | Target | Result | Status |
|---|---|---|---|
| 1 | Lookup right answers 20 of 20 | 20 of 20 | met |
| 2 | Lookup files and searches no higher, median and maximum | files 2 and 6 (baseline 2 and 4); searches 1.5 and 8 (2 and 8) | not met (files maximum) |
| 3 | None of the five baseline misleads recurs | Q17 recurs; Q1, Q6, Q18 and Q19's are gone; a new one from `modules/README.md:70` | not met |
| 4 | PL1, PL3, PL5: every run chooses and cites the stated rule | PL1 3 of 3, PL3 3 of 3; PL5 3 of 3 against `checks/README.md`, 2 of 3 against the key | met for PL1 and PL3; PL5 met against the rule, not the key |
| 5 | PL2 host lists 8 / 6 / 1 | as the guide counts: 8, 6 checked, 1 (`ztRecords`) | met as counted; F8 |
| 6 | PL2 every run lists every generated step | 3 of 3 (baseline 0 of 3) | met |
| 7 | E1, E2 complete in every run, commands arm | not run | not measured |
| 8 | I1 names the 20 homes in every run, commands arm | not run; tree arm 0 of 3 | not measured |
| 9 | E1, E2, I1 no worse in completeness and files, tree arm | E2 files median 22 to 27; I1 0 of 3, files 16 to 16; E1 files 29.5 to 30 | not met. E1's completeness: see F10 |
| 10 | I2 reported | 90 files under `modules/` (baseline 91) | reported |

### World assumptions

A383-A386 are read at the source as their scenarios state; `lib/composition.nix:18-30` parses A383's string, `:76-113` walks A386's `graph`, `:44` matches A385's clan labels. A384 holds at main: evaluation succeeds with the re-declarations. No violation observed.

### `apple-laptop-hardware-support` (MODIFIED)

| Requirement | Evidence | Status |
|---|---|---|
| Stage-1 SPI/SMC modules from the profile | pyrite `boot.initrd.kernelModules` = `["applesmc","applespi","dm_mod","i915","intel_lpss_pci","spi_pxa2xx_platform","zfs"]`; cinnabar's equals the spec's list (`logs/srr-verify-hostfacts-20261128T054551Z.json`) | met |
| Initrd networking off on pyrite by default, asserted | `machines/nixos/pyrite/default.nix:127`; `boot.initrd.network.enable` false; no `initrd-ssh` in `vanixiets.secrets` | met |

### Findings

- **F1, three order items are not done.** gh-dash `keybindings.prs` is still a list merged in import order (`home/development/gh-dash.nix:37,72`); overlays apply in `nixpkgsOverlays` merge order (`nixpkgs/compose.nix:27,43`); four launchd snippets and stibnite's `postActivation` (`:164`, no `mkOrder`) have no `activationOrder` slot. The interface requirements "Package list order is irrelevant" (gh-dash, overlays) and "Ordered-on-purpose lists take their order from one table" are not met. Tasks 5.5-5.7 stay open, as design D2(f) records.
  - Correction (2026-11-28): the three items are written in the working copy and recorded as tasks 5.5-5.7: the bindings keyed by key and rendered in `prsOrder` (`C`, `m`, `M`, the order main rendered, not `m`, `M`, `C`); the overlays named in `nixpkgsOverlaysByName` and ordered by `overlayOrder`; the five snippets slotted in `activationOrder`. Their derivation comparison is still to run.
- **F2, what the route obligation cannot see.** Checked: `compositionRoutes` (`lib/composition.nix:76-129`) against the interface requirement. It judges route *kinds* only, so it sees:
  - a named module whose nearest named or host ancestor is none of the known kinds, that is, one reached from an unnamed root that is neither the host module nor a clan-service label;
  - a graph in which the host's own module is missing (`:124-125`).

  It cannot see:
  - anything below a named ancestor, which is `include` whatever alias form imports it, so E1's `flakeConfig.flake.modules.nixos` miss is invisible to it;
  - unnamed modules (inline modules, srvos, nixos-hardware);
  - disabled nodes;
  - hosts with `checked = false` (scheelite), integrated homes and standalone homes (classes `nixos` and `darwin` only, `:175-178`);
  - a new clan mechanism whose label matches `isClanService` (`:44`).

  The known kinds are written in code (`routeBelow`, `rootRoute`), not read from `modules/README.md`. The README lists five kinds (`:88-92`); the code also emits `home` for standalone homes. A kind added in code without the README passes. Result: consistent with the spec's trust boundary, which excludes `checked = false` hosts and integrated homes; the alias-form and README-linkage limits are not stated there.

  Correction (2026-11-28): the interface requirement's trust boundary, design D2(g) ("What the check judges") and `modules/README.md`'s route section now state this scope, including the alias-form limit, and the README lists the `home` kind.
- **F3, `structure-fleet` has no phantom.** The interface requirement says `structure-fleet` SHALL hold one. `checks/structure/flake-shape.nix` has none (task 2.6; principles O12 says "open for these two pins"). Meanwhile `checks/README.md:34` says every structural check carries a phantom. Either add the phantom or restate the requirement.
  - Correction (2026-11-28): the requirement is restated to the control written in the working copy: `structure-fleet` builds its pin over the fleet and over two mutants (a machine dropped, its class flipped) and fails unless the pin fails on each (task 2.6).
- **F4, the order step changes content.** `repository-shape`'s requirement allows the order step "only the order of installed packages and of three review bindings", and its third scenario rejects a declared difference beyond order. `drv-delta-order.txt` declares three content leaves (two home-delivered texts, one docs path), and the trace exits 1 on 17 configurations at them (task 5.8). Design D5 row 5b planned the texts in this step. Spec and design disagree; restate the requirement to admit the two texts, or record them as the scenario says.
  - Correction (2026-11-28): `repository-shape`'s requirement is restated as "Restructuring delivers nothing but its declared differences", admitting the two texts in the order step; design D5 ("Comparisons as run") gives each comparison's summary lines.
- **F5, the parts lists cannot be shown derivation-free.** They landed in the order step's commit. The structure check's drvPath is unchanged (`logs/srr-5-structure-20261127-223916.log`). Moving a darwin part after the sort changes no toplevel (`logs/srr-verify-mutant-darwin-order-20261128T055245Z.log`). The gh-dash bindings' order did change in that commit, and with the bindings still a list (F1) a reordered `ai` list can cause it; no comparison separates the two. Task 6.4 stays open.
- **F6, one name can print several routes.** The spec scenario says "each with one route kind"; `render` (`lib/composition.nix:131-145`) joins all of a name's routes with commas. Three names on magnetite and one on stibnite do so. The behaviour is informative; the scenario should say "each with its route kinds".
  - Correction (2026-11-28): the scenario now reads "each with its route kinds".
- **F7, the grading script graded nothing.** `grade.py` expects a flat list of per-run records; neither `baseline.json` nor `after.json` is in that form, and both sets were graded by hand. The interface scenario "The re-measure is graded" is met by hand grading only.
  - Correction (2026-11-28): recorded in design D1 ("Re-measure") and the measure README's `grade.py` entry.
- **F8, a ninth hand-written host list.** The guide's table lists "the evaluator table in `modules/README.md`" as left, with no check, and its count of 8 leaves it out. By design D1's definition (a file outside `lib/hosts.nix` and the host directory where a host's name is written by hand), the counts are 9 / 6 / 2. Every PL2 run edited it. Design D2(d) classes it "left", so the target was set without it.
  - Correction (2026-11-28): the counts read 9 / 6 / 2 in design D2(d) and D3, tasks 10.1 and 10.2, the onboarding guide and the measure README. The evaluator table states per-host readings of the bound rules that no registry field names, so it stays a list written by hand.
- **F9, the third pass changes a host beyond order.** pyrite's initrd loses two modules. `repository-shape` names only the priority and order steps as carrying declared differences. Design Resolved Question 3 accepts the change, and the `apple-laptop-hardware-support` delta restates pyrite's side, but the `repository-shape` requirement was not amended for steps 6b and 6c.
  - Correction (2026-11-28): covered by the restated requirement under F4 (the step importing parts only where used changes only pyrite, by one part).
- **F10, E1's count was graded against a stale number.** The re-measure graded E1 against "composition's 81". At the measured commit `d705c39bd6c6`, `just composition magnetite` prints 83 names (`logs/srr-verify-e1-names-20261128T054844Z.log`): `base-package-order` and `nix-build-lock` are new since `c63a450f800e`, and `base-initrd-networking` is renamed `initrd-networking`. By token search, runs E1-1 and E1-3 (83 names each) contain all 83. E1-2 lacks `omnigent-worker-options`, `shared-reference-tree-options` and the host module. So the tree arm's E1 completeness is 2 of 3 (baseline 1 of 2); its files median is 30 against 29.5. Target 9 stays not met on E2's files.
  - Correction (2026-11-28): recorded in design D1 ("Re-measure") and the measure README.
- **F11, the second comparison's parent is not the landed parent.** The patch is identical. Commits `fb7b981f1..1c2b60fc1` remove the cognee skill and relock `apm.lock.yaml`, which reach the same apm derivations. No comparison ran on `1c2b60fc1 -> c69bbcac5`. The order trace and profile replay also ran against `fb7b981f1e74`.
  - Correction (2026-11-28): recorded in design D5 ("Comparisons as run").

### Leftovers

1. `modules/README.md:69` (main) says the darwin half "still assigns into darwin `base` until that list exists". It should name `flake.lib.nixosBaseParts` and `flake.lib.darwinBaseParts` and say the part is listed in both. `:70` lists `nixos/postgresql-backup.nix` as a feature example, which misled lookup 1; it should say that no module is a PostgreSQL host role. `:75` lacks the `checked = false` exception. The working copy holds these three corrections, uncommitted.
2. `modules/home/README.md` (main) does not state the systems a standalone home is built for or the count of 20. The working copy adds both, uncommitted. The host-onboarding guide's `testSizes` row (`host-onboarding.md:46` on main) says only "a size class"; it should say `class = "medium"; measured = false;` (working copy, uncommitted).
3. `docs/notes/development/architectural-principles.md:371` (O22) says "The `aggregates` option defaults to the shared list; the four secondary users omit it". On main the default is `[ ]` (`home/users/lib.nix:252-254`), and the four users set `config.flake.lib.defaultAggregates` (`*/meta.nix:4`). It should say so.
4. The same file, `:590`: "O03, O06, O11, O12, O17 and O22 are outside the project and stay open." O03, O11 and O22 are resolved by `963e6ac6b`; it should list O06, O12 and O17 only. `:196` says "commit recorded at merge" and records none. O03, O04, O09, O11 and O22 should name `963e6ac6b` (pull request 4497), and L5 should say "open: overlays still apply in merge order".
5. `nixpkgs/compose.nix` and `modules/README.md:82` describe the overlay order truthfully as import order; no stale text. No added comment in `modules/**` or the justfile carries a design, task or assumption id, date or log path (search of the three commits' added lines; the only date is the `created:` front matter of `modules/checks/README.md`).
   - Correction (2026-11-28): import order was not the order the overlays applied: nixpkgs applied them reverse-alphabetically by file name (`zed-delta` first, `aeneas` last), so both texts were stale. In the working copy `overlayOrder` in `nixpkgs/compose.nix` writes that order, and `modules/README.md`'s "Where order is written" names that list.

---

## 5. Implementation Signal

**Commit range**: `96a3c1ef8..963e6ac6b`, `1c2b60fc1..c69bbcac5`, `c69bbcac5..d705c39bd`.

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

- [x] No files under `docs/superpowers/specs/` (the directory does not exist)

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

`plan.md` has no `[~]` rows. Deploy-time verification is open (tasks 8.1-8.5):

- cinnabar, magnetite, pyrite and stibnite wait on the fleet deploy being prepared.
- argentum and rosegold are offline.
- electrum, galena and scheelite are disabled, and blackphos has no machine.

Until the deploy runs, nothing is observed on any host: no `/run/current-system` comparison, no read of the alert logs, and no check on any Mac that the deploy deletes no account.

Note (2026-11-28): the deploy has since run on cinnabar, magnetite, pyrite and stibnite, to main `d705c39bd6c6` (tasks 8.2, 8.3; `logs/fdp-*-20261128T06*.log`). On each, `/run/current-system` is the system built from that commit and the deploy record names it; stibnite's activation deleted no account or group. No alert or notice was posted to `fleet-alerts` from 06:15Z to 06:33Z (`logs/fdp-alerts-read-20261128T0633Z.log`); a second read is due before the archive. pyrite's new initrd takes effect at its next boot. argentum and rosegold were offline.

Note (2026-11-28, before archive): a second read of `fleet-alerts` at 06:59Z, 28 minutes after the last switch, returned no message since 06:15Z, and `/v1/health` answered 200 (`logs/fdp-alerts-read-20261128T0659Z.log`). No standalone home is known to be activated on a real host; the five aarch64-linux standalone homes were built from main `709ada4e324b` and activated in a throwaway virtual machine, each making generation 1 the evaluated `activationPackage` and each exiting 1 at the sops-nix step for want of an age key (design Resolved Question 14; tasks 8.1, 8.4).

## 8. Designation Lint and Discharge Coherence

**8a.** The content nouns of `repository-shape` resolve to rows of the world-assumptions delta table: part, route, composition, composition statement, host list, entry-point document, placement rule, fleet-wide setting, hand-entered secret, Mac application, installed packages, review binding, reader measure, lookup, placement, enumeration and impact task, priority step and order step. "operator", "check" and "host" resolve to existing rows.

**8b.**

| Requirement | Discharged by (S) | Under (W) | Status |
|---|---|---|---|
| No host list kept by convention alone | derived lists, `host-list-keys`, the guide | — | met in part (F8) |
| Composition on request; routes known | `just composition`, `compositionRoutes` | A383, A385, A386 | met within F2 |
| One placement rule per kind | `modules/README.md` | — | met in part (Leftover 1) |
| Nothing but declared priority and order | the comparisons, the trace, the replay | A376, A377, A384 | met in part (F4, F9, F11) |
| Accepted on what readers can do | the re-measure | — | not met; commands arm not run |

**8c.** No behavioral requirement names a machine phenomenon beyond installed packages and review bindings, both designated shared.

---

## Overall Decision

- [ ] (pass) PASS
- [ ] (warn) PASS WITH WARNINGS
- [x] (fail) NOT READY FOR ARCHIVE. The code meets the requirements it implements, except the three order items (F1) and the `structure-fleet` phantom (F3). The measure's acceptance requirement is not met: targets 2, 3 and 9 miss, and targets 7 and 8 are unmeasured. Before archive:
  - run the deploy (8.1-8.5) and the commands arm (10.1b);
  - decide F1 and F3 by doing the work or restating the interface requirement;
  - restate `repository-shape` for F4 and F9;
  - land the working copy's text corrections and edit the principles document (Leftovers 1-4).

**Next step**: deploy cinnabar, magnetite, pyrite and stibnite, then argentum and rosegold when online. Then run the commands arm.

Archive (2026-11-28): the change is archived with this decision unchanged and 8 of 60 tasks open, each with its reason under it in `tasks.md`. Where each condition above stands:
- the deploy: run on cinnabar, magnetite, pyrite and stibnite, with a second alert read; 8.1 and 8.4 closed on the test-machine activation; 8.3 open, argentum and rosegold offline;
- the commands arm (10.1b): not run;
- F1 and F3: done by pull request 4511 (`709ada4e324b`), compared against `drv-delta-order-items.txt` (`logs/drv-diff-d705c39bd6c6-709ada4e324b-20261128T062913Z`, `result: PASS`), tasks 2.6 and 5.5-5.7;
- F4 and F9: `repository-shape` restated (pull request 4512);
- Leftovers 1-4: the text corrections landed in pull request 4512; the principles document still lacks its resolving commits (task 9.2, open).

The requirement "Restructuring is accepted on what readers can do" is not met and is recorded as undischarged in the satisfaction table, with the other requirements this report finds met in part recorded as partly discharged.
