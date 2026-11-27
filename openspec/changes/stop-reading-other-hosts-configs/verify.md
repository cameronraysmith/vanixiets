# Verification Report

**Change**: `stop-reading-other-hosts-configs` (CAM-133)
**Verified at**: `2026-11-27 04:00` UTC
**Verifier**: verify agent (openspec-verify-change), read-only against jj change `vpqqmruuxkyv` (commit `53dbe6bcd4ab`, parent `yxruvwlsxllr` = `2ac5a55e96db`), the change artifacts and the recorded evidence under `logs/` (git-ignored); the only command run against the flake was `just drv-diff-rejudge` (seconds), nothing was built, deployed or activated

Evidence names are files under `logs/`. The acceptance runs were taken at `bbb7c5ccc978` on parent `390f72f0c809`; the change has since been rebased onto `2ac5a55e96db`. `jj interdiff --from bbb7c5ccc978 --to vpqqmruuxkyv` touches only `docs/notes/development/eval-cost-baselines.md` and this change's openspec artifacts, so the module patch measured is the module patch committed (see W1).

---

## 1. Structural Validation (`openspec validate --all --json`)

- [ ] All items report `"valid": true`

**Result**:

```text
openspec validate stop-reading-other-hosts-configs --json: valid, no issues
openspec validate --all --json: 81 items, 76 passed, 5 failed (all 35 specs pass)
```

The five failures are other changes, not this one:

| Item | Type | Issues |
|---|---|---|
| compose-hosts-from-cohesive-aspects | change | no deltas (outside this change) |
| declare-host-user-relations-once | change | fails validation (outside this change) |
| seam-secrets-away-from-clan-vars | change | fails validation (outside this change) |
| stand-up-gitea-mq-on-magnetite | change | fails validation (outside this change) |
| stand-up-nixbot-on-magnetite | change | fails validation (outside this change) |

---

## 2. Task Completion (`tasks.md`)

- [x] All `- [ ]` have been changed to `- [x]`

29/29 checked; `plan.md` has no `[~]` rows. Each task's recorded evidence was read:

| Task | Evidence | Observed |
|---|---|---|
| 1.1 | design.md Open Questions | both answers "no", dated 2026-11-26 |
| 1.2, 1.3 | `srohc-1-parent-20261126-222318.txt`, `srohc-1-drv-before-…json`, `srohc-1-before-values-…json` | parent `390f72f0` recorded |
| 2.1 | `srohc-2-relpath-20261126-222443.log` | `["vars/shared/langfuse/secret-key","vars/per-machine/cinnabar/caddy-root-ca/root.crt"]` |
| 2.2 | `srohc-2-deployer-20261126-222443.log` | deployer values identical; `fleet-deployer-obligations` drvPath unchanged, fixtures unedited |
| 3.1–3.3 | `srohc-3-paths-…`, `srohc-3-strings-…`, `srohc-3-mesh-{before,after}-…json` (byte-identical, `cmp` re-run here), `srohc-3-exists-…` | every listed drvPath EQUAL; per-host pg/r2/shared facts SAME |
| 3.4 | `srohc-3-search-20261126-222635.log` | every hit classified RUNTIME / EXEMPT (D7) / COMMENT / DOCUMENTATION / MESSAGE |
| 4.1 | `srohc-4-hostkeys-20261126-222749.log` | ten names; magnetite ends `" \n"`; all ten equal the parent `knownHosts` key |
| 4.2 | `srohc-4-judge-20261126-222814.log` | judge, test-size-classes, fleet-alert build; checkSizes 353→354; mutant `failures = [ ]` fails naming `oneCharacterOff trimmed` |
| 4.3 | `srohc-4-base-importers-20261126-222945.log` | no non-host importer with a `hostKeys` name and a divergent generator; guard not narrowed |
| 4.4 | `srohc-4-mutant-20261126-223000.log` | cinnabar toplevel fails: "cinnabar's generated openssh public key is not flake.lib.hostKeys.cinnabar" |
| 5.1, 5.2 | `srohc-5-values-20261126-223057.log` | knownHosts (stibnite, cinnabar), session keys, deployer, mesh, obligations raw-byte identical; `nix-builders-wiring` builds, drvPath unchanged |
| 5.3, 7.5 | `git grep` at `53dbe6bcd4ab` (this run) | `required by ssh-known-hosts` and `flake ? nixosConfigurations` absent from `modules/` |
| 5.4 | `srohc-5-search-20261126-223125.log` | tip: one comment hit; mutant: exactly the restored stibnite line |
| 6.1 | `srohc-6-drv-20261126-223315.log` | all seven drivers EQUAL |
| 6.2 | `srohc-6-mutant-20261126-223331.log` | all seven fail with their file's message |
| 7.1 | `drv-diff-390f72f0c809-bbb7c5ccc978-20261127T033555Z/` | first report FAIL on undeclared `eval-users-lib` (then declared, D8); `report.20261127T035524Z` PASS; re-judged here against the committed `drv-delta.txt` → `report.20261127T035852Z` PASS, exit 0 |
| 7.2 | `eval-cost-srohc-7-stats-{stibnite-20261127T035106Z,cinnabar-20261127T035215Z}.{log,jsonl}` | table below |
| 7.3 | `srohc-7-checks-20261126-223347.log` | three obligation checks build; nine machine checks evaluate, drvPaths identical to parent |
| 7.4 | commit diff of `docs/notes/development/architectural-principles.md` | O18 marked resolved, names `flake.lib.hostKeys` |

**Incomplete tasks**: none.

| Task | Reason incomplete | Blocks archive? |
|---|---|---|
| — | — | — |

---

## 3. Delta Spec Sync State

| Capability | Sync status | Notes |
|---|---|---|
| host-configuration-independence | pending sync | new capability; no main spec yet |
| host-configuration-independence-interface | pending sync | new capability; no main spec yet |
| world-assumptions | pending sync | A320–A323 absent from `openspec/specs/world-assumptions/spec.md` |

---

## 4. Design / Specs Coherence Spot Check

| Sampled item | design description | specs correspondence | Gap |
|---|---|---|---|
| D1 | `hostKeys` from committed files; known_hosts reads only it | interface `flake.lib.hostKeys holds every pinned host key…`; code `modules/lib/host-keys.nix:22-40`, `modules/system/ssh-known-hosts.nix:9-27` | none |
| D2 | own-host obligation in `nixos.base`, judged over fixtures | interface obligation + enforcement requirements; `host-keys.nix:42-64`, `checks/host-key-obligations.nix:31-74` | none |
| D3 | stibnite reads magnetite's committed session key | interface `No host configuration reads…`; `machines/darwin/stibnite/default.nix:172-181` | none |
| D4 | `vars.{relPath,path,public,exists,isRecipient}` | interface `flake.lib.vars reads…`; `modules/lib/vars.nix:21-83` | none |
| D5 | each reader keeps primitive and kind | interface `Every reader … keeps its read` | W2 |
| D6 | vm-tests take databases from flake data and assert magnetite | interface D6 requirement; e.g. `vm-tests/greptimedb-pipeline.nix:77,91-92` | none |
| D8 | drv-diff then A/B | interface drvPath + measurement requirements | none (D8 records the `eval-users-lib` addition) |

**Drift warnings** (non-blocking): W2.

---

## 5. Implementation Signal

- [x] No unstaged files in the worktree (the change's files are all in `vpqqmruuxkyv`; `@` holds no edits to them; the shared join's other WIP is not this change's)
- [ ] All related commits have been pushed (`vpqqmruuxkyv` is in no remote bookmark's ancestry)

**Commit range** (if known): `2ac5a55e96db..53dbe6bcd4ab` (one commit); evidence taken at `390f72f0c809..bbb7c5ccc978`

---

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

- [x] No files, or any existing files are legitimate residue from before schema installation

`ls docs/superpowers/specs/*.md` returned nothing.

| File | Content captured into change? | Recommended action |
|---|---|---|
| — | — | — |

---

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

`plan.md` has no `[~]` rows; nothing deferred.

| Deferred dogfood (plan §) | Equivalent automated test | Coverage assessment | Real gap? |
|---|---|---|---|
| — | — | — | — |

---

## 8. Requirement trace, measurement, and stratum checks

### 8.0 Requirement → code → evidence

`HCI` is `host-configuration-independence`, `HCII` its `-interface`, `WA` `world-assumptions`.

| Requirement | Code at `53dbe6bcd4ab` | Evidence | Status |
|---|---|---|---|
| HCII No host configuration reads another host's evaluated configuration | `system/ssh-known-hosts.nix:9-11` (no `flake` arg), `stibnite/default.nix:175` | `srohc-5-search-…` (tip + mutant); `git grep` here: only `nixos/devloop-collection.nix:25` (comment) plus `.md` skill docs under `home/ai/plugins/…/.apm/` (W4) | verified |
| HCII flake.lib.vars reads the committed vars layout in one place | `lib/vars.nix:21-83` | `srohc-2-relpath-…` | verified |
| HCII Every reader … uses one accessor and keeps its read | 14 call sites (`git grep 'vars\.(path\|public\|exists\|isRecipient)'`) | `srohc-3-search-…`, `srohc-2-deployer-…`, `srohc-3-*`, drv-diff PASS | verified, wording W2 |
| HCII flake.lib.hostKeys holds every pinned host key… | `lib/host-keys.nix:31-40`, `ssh-known-hosts.nix:16-27` | `srohc-4-hostkeys-…`, `srohc-5-values-…` (byte-identical) | verified |
| HCII Each NixOS host asserts … equals its pinned key | `host-keys.nix:42-49` | `srohc-4-judge-…` (five fixtures + mutant) | verified |
| HCII Every NixOS host build enforces its own obligation | `host-keys.nix:51-64` | `srohc-4-mutant-…`; `srohc-7-checks-…` | verified |
| HCII Tests take magnetite's databases from flake data… | five `vm-tests/*.nix` | `srohc-6-drv-…`, `srohc-6-mutant-…` | verified |
| HCII Every output's derivation is unchanged | — | `report.20261127T035524Z`, re-judged `report.20261127T035852Z` PASS | verified at `bbb7c5ccc978`; W1, W3 |
| HCII The evaluation saving is measured, not inferred | — | 7.2 logs; `docs/notes/development/eval-cost-baselines.md` | verified |
| HCI Building one host's configuration does not require another host's | via HCII | as above | verified |
| HCI Each host takes other hosts' keys from the pinned keys | via HCII | knownHosts byte-identical | verified |
| HCI A host … other than its pinned one fails before deploy | via HCII | cinnabar mutant | verified (NixOS only, as the spec states) |
| WA A320, A321 | — | clan-core source citations in the delta | configured/observed at the cited revision (not re-read here) |
| WA A322 | — | drv-diff PASS across string→path switches | observed (the delta's Evidence still says `[INFERENCE]`; S1) |
| WA A323 | — | parent-revision stibnite run 24,376,947 thunks vs A323's 24,376,302 | not violated (within variance) |

### 8.1 A/B measurement (task 7.2, stibnite, Nix 2.35.6, one fresh process per run)

| Host | Run | Side | cpuTime s | nrThunks | gc.totalBytes |
|---|---|---|---|---|---|
| stibnite | 1 | A | 10.43 | 24,376,947 | 3,165,612,096 |
| stibnite | 1 | B | 9.51 | 20,688,021 | 2,744,247,040 |
| stibnite | 2 | A | 10.43 | 24,376,947 | 3,165,610,176 |
| stibnite | 2 | B | 9.56 | 20,688,021 | 2,744,246,560 |
| cinnabar | 1 | A | 12.46 | 24,154,692 | 2,679,431,792 |
| cinnabar | 1 | B | 11.93 | 21,336,653 | 2,410,155,728 |
| cinnabar | 2 | A | 12.95 | 24,154,692 | 2,679,439,520 |
| cinnabar | 2 | B | 11.07 | 21,336,653 | 2,410,146,800 |

stibnite: −3,688,926 thunks (15.1 %), −421 MB (13.3 %), −0.87 to −0.92 s, against A323's upper bound of 3.7M / 423 MB / 0.98 s. Both B runs have fewer thunks than both A runs: the scenario holds.

### 8a. Designation lint (`host-configuration-independence`, behavioral)

Resolved in `openspec/specs/world-assumptions/spec.md`: host (fleet sense), configuration, host key, deploy, fleet.

| Noun | Requirement | Finding |
|---|---|---|
| build (a host's configuration is built / fails to build) | all three | no row in that sense; the `build` rows are the vendor and build-service senses |
| SSH (connects over SSH) | `Each host takes other hosts' host keys…` scenario | no row; named inside the `host key` definition only |

### 8b. Discharge coherence

| Requirement | Discharged by (S) | Under (W) | Status |
|---|---|---|---|
| HCI Building one host's configuration… | HCII source search; HCII measurement | — | discharged |
| HCI Each host takes … pinned keys | HCII `flake.lib.hostKeys…` | A320, A321 | discharged; A320/A321 configured |
| HCI A host … fails before deploy | HCII obligation | A321 | discharged (NixOS); darwin out of scope by the spec |
| HCII vars / readers / hostKeys | `nix eval`, source search, drv-diff | A320, A322 | discharged; A322 observed |
| HCII obligation, enforcement, D6, drvPath, measurement | judge check, mutants, drv-diff, A/B | A323 | discharged |

### 8c. Alphabet check

No violation found: the behavioral requirements name hosts, configurations, keys and deploys only; the interface requirements' references to a running host's presented key sit in trust-boundary disclaimers.

---

## Findings

**CRITICAL**: none.

**WARNING**
- W1: the acceptance runs (drv-diff, A/B, task logs) are at `bbb7c5ccc978` on `390f72f0c809`; the committed change is `53dbe6bcd4ab` on `2ac5a55e96db`. The interdiff touches no module, so drvPath identity at the new parent is `[INFERENCE]`. Recommendation: none required unless the parent's own patch (it edits `vm-tests/caddy-root-from-vars.nix` and omnigraph modules) is judged to interact; a re-run would be the full drv-diff.
- W2 (resolved by wording): HCII `Every reader … keeps its read` and design D5's Choice said each site keeps its path-or-string kind, but D5's own table moves `tincr.nix:40`, `checks/otel-collector-{config,darwin}.nix`, `darwin/otel-collector-agent.nix:452`, `nixos/postgresql-backup.nix:142-147` and `nixos/r2-usage.nix:250` from string to path form. Results and drvPaths are unchanged (A322 observed). Resolved: the requirement, D5, the goal and plan now state the invariant as each reader keeping its result value and read function, with the drv-diff run proving drvPaths unchanged.
- W3: four vmTests (`caddy-root-from-vars`, `omnigraph-seed`, `tincr-mesh`, `tincr-mesh-partition`) failed to evaluate at both revisions, so their identity is unobserved. They were failing before this change.
- W4 (resolved by wording): the source-search scenario's directories include `modules/home`, where `.apm` skill markdown under `home/ai/plugins/` contains `nixosConfigurations.` examples; they are docs, not imported modules, and the recorded search skipped hidden dirs. Resolved: the scenario now searches `.nix` files only.

**SUGGESTION**
- S1: update A322's Evidence from `[INFERENCE]` to the drv-diff observation at sync.
- S2: 8a's two unresolved nouns (build in the configuration sense, SSH) can gain rows or be rephrased at sync.

---

## Overall Decision

- [ ] (pass) PASS — may proceed to finishing-a-development-branch and archive
- [x] (warn) PASS WITH WARNINGS — may proceed to subsequent steps but note: `W1 and W3 are non-blocking: evidence is at the pre-rebase revision with a module-identical patch; four vmTests fail at both revisions. W2 (keep-kind wording) and W4 (search scope included docs) are resolved by wording`
- [ ] (fail) FAIL — return to the failed artifact, correct it, then re-run verify

**Next step**:

In Review: roborev and documenter review; then sync the three delta specs (applying S1 wording), push, and archive.
