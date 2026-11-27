# Verification Report

> This file is produced by the `openspec-verify-change` skill after apply completes, to confirm that the
> implementation is consistent with the specs / design / tasks. Any failed check must be returned to its
> corresponding artifact for correction before re-running verify.

**Change**: `type-the-fleet-host-registry`
**Verified at**: `2026-11-27 06:18 UTC`
**Verifier**: Claude (openspec-verify-change, subagent of the implementing session)

Implementation under review: jj change `vrswyolxktsy`, commit `1b66135a6b64` ("feat(lib): record each fleet host once as a typed record"), parented on `07e3f1affe2d` (`origin/main`). Its tree equals `21876c9a4c1d`, and differs from `66c5a7768fc5`, the commit the drvPath diff dumped, only in `drv-delta.txt`. Code was read with `jj --ignore-working-copy file show -r vrswyolxktsy` and in the working copy, which matches it for every file this change touches.

### Summary

| Dimension | Status |
|---|---|
| Completeness | 26/32 tasks; 6 open (6.1 pre-merge, 7.1–8.3 post-merge); 32 requirements (31 ADDED, 1 MODIFIED) |
| Correctness | 32/32 requirements traced to code or evidence; 1 scenario without a direct run (`A host disappears from the registry`) and the deployed admission unobserved until 7.2 |
| Coherence | Design followed; D10 amended in this verify to match the acceptance run |

---

## 1. Structural Validation (`openspec validate --all --json`)

- [ ] All items report `"valid": true`

**Result**:

```text
totals: 82 items, 77 passed, 5 failed (changes 43/38/5, specs 39/39/0)
openspec validate type-the-fleet-host-registry --strict -> Change 'type-the-fleet-host-registry' is valid
```

The five failures are other active changes, none of which this change touches:

| Item | Type | Issues |
|---|---|---|
| compose-hosts-from-cohesive-aspects | change | no deltas found (planning not yet at specs) |
| declare-host-user-relations-once | change | no deltas found |
| seam-secrets-away-from-clan-vars | change | no deltas found |
| stand-up-gitea-mq-on-magnetite | change | no deltas found |
| stand-up-nixbot-on-magnetite | change | no deltas found |

---

## 2. Task Completion (`tasks.md`)

- [ ] All `- [ ]` have been changed to `- [x]`

Task 5.5 was ticked in this verify from the recorded acceptance run (see §5).

**Incomplete tasks**:

| Task | Reason incomplete | Blocks archive? |
|---|---|---|
| 6.1 README / ADR wording | The `modules/README.md` edit is in the commit (new "Host registry" section, the `memoryGiB` paragraph, scheelite's `checked = false`), but its verify step, `prek run --files` on the changed documents and the ADR-0019/0020 read, has no recorded evidence | yes |
| 7.1 Deploy cinnabar | Post-merge by design; waits on the pull request | yes |
| 7.2 Read the controller's admitted members on cinnabar | Post-merge; waits on 7.1 | yes |
| 8.1 `just drv-diff <parent> <merged head>` | Post-merge | yes |
| 8.2 Projections at the merged head | Post-merge. The same projections were taken at the commit in this verify (§5) | yes |
| 8.3 No migration flag remains | Post-merge; the search already finds nothing at the commit (§5) | yes |

---

## 3. Delta Spec Sync State

| Capability | Sync status | Notes |
|---|---|---|
| fleet-host-registry | pending sync | new capability; absent from `openspec/specs/` |
| fleet-host-registry-interface | pending sync | new capability; absent from `openspec/specs/` |
| world-assumptions | pending sync | adds A300–A305 and modifies `Grounded vocabulary for behavioral requirements` (17 rows appended: checked host, cloud machine type, cloud server, derived fact, enrolled host, externally joined member, fleet member, fleet pin, host fact, host kind, host registry, inventory tag, phone, role membership, service role, state version, system). Other active changes modify the same requirement in full; at archive, rows they added since 2026-11-26 are merged by hand (design, Risks) |

---

## 4. Design / Specs Coherence Spot Check

| Sampled item | design description | specs correspondence | Gap |
|---|---|---|---|
| D1 typed option and alias | `flake.fleet.hosts` submodule with ten declared and seven read-only fields; `flake.lib.hosts` alias | interface: `flake.fleet.hosts holds one typed entry…`, `The submodule sets the read-only fields…`, `flake.lib.hosts is a read-only alias…` | none; `modules/lib/hosts.nix:45-212,217,400` |
| D4 kept asserts | every `checks/machines.nix` assert kept; directory assert catches the record-without-inventory case | interface: `The machine-check asserts are kept`, `The golden pin stays a literal` | none; 10 `assertMsg` at parent and commit |
| D8 allowedIps from class | same six addresses, name order; cinnabar changes | interface: `The ZeroTier controller's allowedIps is derived from class`; behavioral: `The overlay network controller admits…` | none |
| D10 acceptance oracle | declared delta list | interface scenario `Only the declared derivations change` | was: four changed checks predicted, 29 more observed. Fixed in this verify: D10, the Goals bullet, task 5.5, plan Global Constraints, proposal Impact lines and the scenario now name `fleet-alert` and the docs-package checks |
| D12 tag rename | stibnite `controller` → `deployer-workstation` | interface: `An inventory tag has one meaning across hosts` | none |

**Drift warnings** (non-blocking):

- The D10 drift above, now resolved in the artifacts.

---

## 5. Implementation Signal

- [x] No unstaged files in the worktree. `git status --porcelain` is empty. The jj working copy `@` holds only other chains' work (vm-tests, ghq-shared), none of it in this change's files.
- [ ] All related commits have been pushed. `vrswyolxktsy` has no remote bookmark yet.

**Commit range**: `07e3f1affe2d..1b66135a6b64` (one commit)

**Evidence traced per requirement** (logs under `logs/`):

| Requirement (spec) | Code | Evidence |
|---|---|---|
| typed entry per member; field types (iface) | `modules/lib/hosts.nix:45-120,217` | `thr-verify-projections-20261127T061652Z.log` (twelve members; stateVersion 4 / "25.05" / "26.05" / null) |
| read-only fields (iface) | `hosts.nix:125-212` (`class` :185, `targetHost` :194, `enrolled` :211 `pathExists (self + …)`, `cloud` :212) | projections: `enrolled` false only for blackphos, pixel7 and pixel11; `cloud` for the five cloud hosts with `type` from serverType/machineType |
| class-contradicting fields throw (iface) | `hosts.nix:96-120,200-206` | `thr-2-mutants-20261127-054509.log` (memory 0, stateVersion "4", nixClassic without primaryUser, primaryUser "nobody"; `tryEval` → `success = false`) |
| alias carries prior fields (iface) | `hosts.nix:400` | projections: 11-field hosts projection equal to `thr-1-baseline-20261127-053803.json` |
| per-host values derived (iface); each fact recorded once (beh) | `hosts.nix:404`; `clan/machines.nix:3-9`; `clan/inventory/machines.nix:18,21`; `lib/observability-hosts.nix:59`; `lib/host-keys.nix:23` | projections equal: machineSystems, inventory machineClass/deploy, platforms, hostKeys; `thr-3-hostplatform-20261127-054718.log`; `rg 'nixpkgs.hostPlatform ='` and `rg 'nixosKeyHosts = \['` empty |
| host kind read from class (iface) | seven former suffix tests | `rg 'hasSuffix "-darwin"' modules` → only `lib/hosts.nix:188`, `containers/default.nix:50`; `network-target-obligations` built (`thr-3-builds-…`) |
| machine checks by `checked` (iface); lifecycle independent (beh) | `checks/machines.nix:22,27,117` | checksDarwin equal; checksX86 = baseline + `eval-inventory-members`; nixos-electrum/galena present (cloud disabled), nixos-scheelite absent |
| tincr peers by class and enrolment (iface) | `clan/inventory/services/tincr.nix` (`peers`) | tincr peer names equal baseline |
| deployer reads cloud state (iface) | `lib/fleet-deployer.nix:62` | fleetDeployer targets/problems equal; `fleet-deployer-obligations` built (`thr-4-5-builds-…`) |
| cloud memory table (iface, beh) | `lib/cloud-machines.nix:11`; `hosts.nix:200-206` | memoryGiB equal; `thr-4-mutants-20261127-055057.log` (cx99 named; `tryEval` false) |
| unclassified host reported (beh) | `hosts.nix` memoryGiB throws | `nix-eval-jobs-iets` built (`thr-4-5-builds-…`) |
| resolver (iface); one membership rule (beh) | `lib/inventory-members.nix`; readers at `fleet-topology.nix:93`, `zerotier-mss-clamp.nix:22`, `zerotierone-controller.nix:37`, `omnigent-worker-login.nix:6` | `eval-inventory-members`, `eval-fleet-topology`, `fleet-topology-fresh`, `zerotier-mss-clamp`, `zerotierone-controller-cinnabar` built; `thr-5-mutants-…` (resolver ignoring `all` fails `testAll`) |
| one meaning per tag (iface) | `clan/inventory/machines.nix:30` | projections: machines tagged `controller` = `["cinnabar"]`; inventory differs from baseline only in stibnite's tags |
| allowedIps from class (iface); controller admits external members (beh) | `clan/inventory/services/zerotier.nix` | cinnabar's `zerotier-autoaccept-zerotier` script at the commit lists the six baseline addresses, as a set, in name order argentum, blackphos, pixel11, pixel7, rosegold, stibnite |
| only declared derivations change (iface) | `drv-delta.txt` | `drv-diff-07e3f1affe2d-66c5a7768fc5-20261127T055715Z`: first judgement FAIL on 29 undeclared check differences, each traced and then declared; re-judgements `report.20261127T061438Z` and `report.20261127T061843Z` PASS (nixos 5 identical + cinnabar changed; darwin 4, home 20, vmTests 21 + 3 identical) |
| asserts kept; golden pin literal (iface); dropped or reclassified host caught (beh) | `checks/machines.nix:100-123`; `checks/structure/flake-shape.nix` | `thr-3-mutants-20261127-054718.log` (m5 flip, m6 record without inventory entry, m7 missing directory: each fails with the directory assert) |
| trust boundary (iface) | none (a statement of limits) | no machine read; 7.2 is the read that shows admission |
| A300–A305 (world) | none (assumptions) | A300 re-read in the locked clan-core: `clanServices/zerotier/default.nix:173,241,338`. A301: the locked nixpkgs `lib/modules.nix:1434,1443` throws, not `:1240,:1249` as the spec cites; `asserts.nix:53` is `pred \|\| throw msg`. A302: clan-core `lib/inventory/default.nix:15` `resolveTags`. Every inventory machine carries the tag `all` (baseline tags), which is how `all` matches. A304: `sops/machines/` lists every NixOS and darwin host except blackphos, plus `gcp-vm`. A305: drv-diff shows no NixOS or darwin drvPath change except cinnabar's (D8) |

---

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

- [x] No files, or any existing files are legitimate residue from before schema installation

`ls docs/superpowers/specs/*.md` returns nothing.

---

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

plan.md has no `[~]` rows, so this section is blank and passes. The post-merge reads of tasks 7.1 and 7.2 are open tasks, not deferrals. No automated test shows the controller's admitted set once deployed; only 7.2's read on cinnabar does.

---

## 8. Designation Lint and Discharge Coherence (agent-executed, non-blocking)

These checks are agent-executed; `openspec validate` does not perform them.

**8a. Designation lint** (`fleet-host-registry`, behavioral) against `openspec/specs/world-assumptions/spec.md` plus this change's 17 appended rows. Content nouns that resolve to no row:

| Noun | Where | Disposition needed |
|---|---|---|
| record (of a host) | `Each fact about a fleet host is recorded once` | add a row, or reword to `host registry` / `host fact` |
| fully qualified name; overlay address; deploy account | same requirement | add rows (shared), or treat as derived host facts and name them as such |
| configuration directory | `A host dropped or reclassified…`, scenario `A host's kind flips` | interface-stratum noun; redirect to the interface spec |
| evaluator bound; report of unclassified hosts | `A cloud host's memory…`, `A host whose memory cannot be read…` | add rows (machine-only today; consider moving these scenarios to the interface stratum) |
| per-host check; deployability | `A host's system is changed`, `A host is deferred from checks` | add rows, or use `checked host` |
| controller (of the overlay network) | `The overlay network controller admits…` | add a sense row; only `controller session` exists |

**8b. Discharge coherence**

| Requirement | Discharged by (S) | Under (W) | Status |
|---|---|---|---|
| Each fact about a fleet host is recorded once | iface: typed entry, read-only fields, per-host values derived, host kind read from class | A305 | discharged; A305 observed for this commit (drv-diff) |
| A member that runs no configuration is never treated as a host | iface: per-host values derived (`system != null` filters), allowedIps from class | — | discharged |
| Lifecycle facts are independent | iface: machine checks by `checked`, tincr by enrolment, deployer reads `cloud.enabled` | A304 | discharged; A304 configured (directory listing 2026-11-27) |
| A cloud host's memory follows from its type | iface: cloud memory table | A303 | discharged; A303 not violated (no machine read in window) |
| A host whose memory cannot be read is reported | iface: class-contradicting fields throw | A301 | discharged; A301 observed (mutant `tryEval` false) |
| Membership in a service role is one rule | iface: resolver; every reader uses it | A302 | discharged; A302 observed at source (`resolveTags`) |
| The controller admits exactly the external members | iface: allowedIps from class | A300 | discharged at evaluation; the deployed admission is unobserved until 7.2 |
| Dropped or reclassified host is still caught | iface: asserts kept, golden pin literal | — | partly: the reclassification is observed (m5). Removing a record has no mutant run; see Warnings |
| iface requirements (17) | the code cited in §5 | A300–A305 as above | discharged at evaluation |
| A300–A305 (world) | none (assumptions) | itself | A300, A302: observed at source; A301: observed; A303: not violated; A304: configured; A305: observed for this commit |
| Grounded vocabulary (MODIFIED) | — | — | rows appended; see 8a for nouns still unlisted |

**8c. Alphabet check**

- `fleet-host-registry`, scenario `Two places disagree about a host`, names "a search of the repository": a machine phenomenon in a behavioral scenario.
- `fleet-host-registry`, scenarios `An unknown machine type` ("evaluation … fails") and `A host's kind flips` ("the fleet's checks fail to evaluate … configuration directory"): interface phenomena in behavioral scenarios.
- `fleet-host-registry-interface`, `Trust boundary…`, names machine memory and the deployed controller only to say the interface does not observe them. Not a violation.

---

## Issues by Priority

**CRITICAL** (before archive): the open tasks 6.1, 7.1, 7.2, 8.1, 8.2 and 8.3 (§2). None blocks review of the commit. Resolved after merge (2026-11-27): all six are ticked in `tasks.md` with their evidence, on main `9055ae0f1333` (#4386).

**WARNING**:
- (resolved) Task 6.1's README edit is committed but unverified. Run `prek run --files modules/README.md`, read ADR-0019 (:70-75) and ADR-0020 (:116-121), log the result and tick it. Resolved: `prek` passed on every file of the commit before publishing, and both ADRs' `clan.machines` example is what `modules/clan/machines.nix` now generates; no amendment (task 6.1).
- (open, non-blocking) `fleet-host-registry`, scenario `A host disappears from the registry`: no mutant removes a record. m6 and m7 cover the neighbouring cases. Run one at 8.x, or cite the `structure-fleet` literal pin's failure. Still open at archive: no record-removal mutant was run, and m5–m7 show the directory assert fires before `structure-fleet` compares, so whether this scenario's THEN names the pin's failure or the directory assert's is unobserved.
- (resolved by wording) A301's evidence cites `lib/modules.nix:1240,1249`; at the locked nixpkgs the throws are at `:1434,1443`. Correct the citation in `specs/world-assumptions/spec.md`. Resolved: the delta spec's A301 Evidence now cites `:1434`, `:1443` at the locked revision `bd5b7d01`.
- (resolved) The drvPath diff dumped `66c5a7768fc5`, not the current commit. The trees differ only in `drv-delta.txt`; 8.1 at the merged head closes the gap. Resolved: task 8.1 ran `just drv-diff 07e3f1affe2d 9055ae0f1333` at the merged head, PASS.
- (open, non-blocking) 8a and 8c findings above. Not reworded at sync; the unlisted nouns stay as recorded in 8a.

**SUGGESTION**: none.

---

## Overall Decision

- [ ] (pass) PASS — may proceed to finishing-a-development-branch and archive
- [x] (warn) PASS WITH WARNINGS — may proceed to subsequent steps but note: the commit's implementation matches every requirement it can show before merge, and the acceptance drvPath diff passes. Before archive, finish task 6.1's recorded verification and the post-merge tasks 7.1–8.3, and resolve the warnings above.
- [ ] (fail) FAIL — return to the failed artifact, correct it, then re-run verify

**Next step**:

Open the pull request for `vrswyolxktsy` (In Review). After merge, deploy cinnabar (7.1), read its controller (7.2) and run 8.1–8.3. Then archive.
