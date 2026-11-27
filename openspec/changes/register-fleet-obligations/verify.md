# Verification Report

**Change**: `register-fleet-obligations`
**Verified at**: `2026-11-27 07:45 UTC`
**Verifier**: subagent of the session that applied the change (Claude, openspec-verify-change)

The commit under verification is jj change `pxpsrtynvurl`, commit `1b0b281ba64c`, parented on `main` at `db0beed0db3c`. The oracle ran against `f3f2849bebd0`, which differs from `1b0b281ba64c` only in one line of `openspec/changes/delegate-fleet-deploys/design.md`. For every file the commit touches outside this change's directory, `jj diff --from pxpsrtynvurl --to @` is empty, so the working copy holds the committed code.

**Updated 2026-11-27, after the first pass**: task 3.5 landed as its own commit (`dfcee2e1cc6e` to `007995cd6f0a`, `just drv-diff` PASS, evidence in `tasks.md`). By the operator's decision the same day, tasks 4.4, 6.1 and 6.2, their requirements, and two missing mutants moved to the change `finish-fleet-package-set-and-budget-typing` (CAM-137). The MODIFIED `database-backup-interface` delta and task 7.2 were dropped, and `back-up-postgresql-off-host` now names the registered judge itself. Task 7.3 is discharged. The sections below reflect that state.

---

## 1. Structural Validation (`openspec validate --all --json`)

- [x] All items report `"valid": true` for this change

**Result** (2026-11-27, after the split):

```text
openspec validate register-fleet-obligations --strict: "Change 'register-fleet-obligations' is valid", no INFO line
openspec validate finish-fleet-package-set-and-budget-typing --strict: valid
```

The first pass's INFO line (archive refusing the MODIFIED `database-backup-interface` delta) is gone with the delta. The three invalid items of the first pass's `--all` run (`compose-hosts-from-cohesive-aspects`, `stand-up-gitea-mq-on-magnetite`, `stand-up-nixbot-on-magnetite`) belong to other changes and were not re-run.

---

## 2. Task Completion (`tasks.md`)

- [x] All `- [ ]` have been changed to `- [x]`

22 of 22 tasks are done (`openspec instructions apply` progress). Evidence for 2.5, 4.5 and 7.1 was recorded in the first pass, and for 3.5 with its own oracle run.

**Tasks no longer in this change**:

| Task | Where it went |
|---|---|
| 4.4 move `vm-tests/{shared-reference-tree,perses-greptimedb}.nix` to `fleetPkgs` | `finish-fleet-package-set-and-budget-typing`, tasks 2.1 and 2.2 |
| 6.1 type `envelopeBudget` as a submodule | the same change, task 3.1 |
| 6.2 the `storeURL` mutant | the same change, task 3.2 |
| 7.2 archive order after `back-up-postgresql-off-host` | dropped with the MODIFIED delta; `back-up-postgresql-off-host`'s own spec delta and task 1.3 name `fleetObligations.postgresqlBackupObligations` |

**Task 7.3, message and reply (2026-11-27)**: the owner of `delegate-fleet-deploys`, the operator, was told that this commit rewrites its design D15 sentence (`design.md:154`) from `withFleetObligations` to the `fleetObligations.fleetDeployer` registration folded into every machine check by `modules/checks/machines.nix`. The operator chose to keep the corrected sentence.

---

## 3. Delta Spec Sync State

| Capability | Sync status | Notes |
|---|---|---|
| fleet-ingress-interface | pending sync | two ADDED requirements, neither present in `openspec/specs/fleet-ingress-interface/spec.md`; the envelope-budget requirement moved to `finish-fleet-package-set-and-budget-typing` |
| fleet-obligation-registry-interface | pending sync | new capability |
| fleet-package-set-interface | pending sync | new capability |
| world-assumptions | pending sync | A330–A332 are not in the main spec and are used by no other active change |

---

## 4. Design / Specs Coherence Spot Check

| Sampled item | design description | specs correspondence | Gap |
|---|---|---|---|
| D1 registry option | `fleetObligations` is a flake-parts option outside `flake`, with `classes` and `failures` | "Each host judge is registered once, beside its definition" | none |
| D2 fold | the class comes from the configuration set being mapped; message `Fleet obligations unmet on <name>:` | "Every machine check asserts…", "A failing machine check names each unmet judge" | none |
| D3 constructor | ten checks moved; host-key check converted by task 3.5 | "Every count-judged fixture check is built by one constructor" | none |
| D6 patched | ADR Decision text left as written, plus an amendment | "The channels overlay offers no patched channel": `rg` returns only the amendment's text | see warning W1 |
| D10 cost points | magnetite cost within noise; lower allocation expected for the other two | none (D10 is not a requirement) | none; measured values recorded in D10 |

**Drift warnings** (non-blocking): W1 and W2 below.

---

## 5. Implementation Signal

- [x] No unstaged files in the worktree: under jj every edit is part of a commit. The files this change touches outside its own directory are identical in the working copy and in `1b0b281ba64c`. This change's OpenSpec files were edited in this pass, so they differ from the commit until the orchestrator folds them in
- [ ] All related commits have been pushed: not yet; the commit is unpublished

**Commit range**: `db0beed0db3c..1b0b281ba64c` (jj change `pxpsrtynvurl`)

---

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

- [x] No files: `ls docs/superpowers/specs/*.md` finds nothing

---

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

`plan.md` has no `[~]` rows, so this section stays empty. Nothing here deploys a host, so the change has no dogfood step.

---

## 8. Designation lint and discharge coherence (agent-executed, not validation)

**8a. Designation lint.** The proposal tags no capability `behavioral`, so no requirement is linted. The designation table exists (`openspec/specs/world-assumptions/spec.md:102`).

**8b. Discharge coherence.**

| Requirement | Discharged by (S) | Under (W) | Status |
|---|---|---|---|
| Each host judge is registered once, beside its definition | `rg -n 'fleetObligations\.' modules`: one entry per file, each in the file that defines its judge's export. `logs/rfo-outputs-20261127-070742.json` lists no `fleetObligations` | — | discharged |
| The registry holds exactly the fleet's twelve judges | key-list assertion `modules/checks/machines.nix:102-103`, evaluated by every machine check in the oracle run. Deletion mutant C and probe mutant D (`logs/rfo-mutants-20261127-070848.log`). Classes evaluated: `resolverReloadObligations` and `sopsBootInstallObligations` are `["darwin"]`, the other ten have both (`logs/rfo-verify-registry-classes-20261127T073613Z.json`) | — | discharged |
| Every machine check asserts every judge registered for its class | `machines.nix:57-76` and the mappers at `:134-149`. Mutant B (a darwin-only throwing entry evaluates `nixos-cinnabar` and fails `darwin-stibnite`). The oracle shows nixos 6 / darwin 4 identical | A332 | discharged; A332 not violated in this oracle run |
| A failing machine check names each unmet judge | mutant A: `Fleet obligations unmet on cinnabar:` / `harmoniaGcObligations: …`, and no other line | — | discharged |
| A judge-over-fixtures check reports each wrong case | `modules/lib/judge-check.nix`; mutant 3.3 (`harmonia-gc-obligations: nixosNoTimeout: expected 0 problems, the judge gave 1: …`); 6.3's `committed` mutant | A332 | discharged |
| Every count-judged fixture check is built by one constructor | the ten migrated checks and `otel-collector-config` keep their drvPaths in the oracle run; `host-key-obligations` keeps its drvPath after conversion (`/nix/store/w6alaqpmnb4rz6pw6n9rl7asfy9v3ba8-host-key-obligations.drv`, `just drv-diff dfcee2e1cc6e 007995cd6f0a` PASS) and its wrong-count mutant fails with the per-case message (`logs/rfo-mutants-host-key-20261127T075034Z.log`) | A332 | discharged |
| A check module states its system condition once | none of the 26 modules still has an inner condition; no module with an enclosing `system ==` condition has one (`rg`, 31 modules with an outer condition). Both `test-size-classes` drvPaths are unchanged | — | discharged |
| Fixture checks evaluate against the fleet package set | `omnigent-workers` and `devin-worker` read `fleetPkgs` (`devin-worker.nix:72-73,86`); `rg 'import inputs\.nixpkgs' modules/checks` finds nothing; both checks' drvPaths are unchanged in the oracle run. The runtime-test half moved to `finish-fleet-package-set-and-budget-typing` | A330 | discharged; A330 not violated in this oracle run |
| The channels overlay offers no patched channel | `rg '\bpatched\b' modules/nixpkgs` finds nothing; `just docs-build` exit 0; the oracle shows only the 28 declared docs-site checks and the base allow-list changed | A331 | discharged, with warning W1; A331 not violated |
| (moved) A host's backup set is pinned by a fleet obligation | the MODIFIED delta was dropped; the requirement is stated by `back-up-postgresql-off-host`, and its scenario "a database is added without a backup" gets its mutant in `finish-fleet-package-set-and-budget-typing` task 4.2 | — | not this change's |
| (moved) The envelope budget has a declared shape | moved to `finish-fleet-package-set-and-budget-typing` | — | not this change's |
| Each observability host row conforms to one schema | `otel-collector-config` `judgeCases` (`modules/checks/otel-collector-config.nix:2403-2422`), drvPath unchanged. Scenario values evaluated: the committed table gives `[]`; `agentTelemtry` gives the unknown-field and missing-field messages (`logs/rfo-verify-row-scenarios-20261127T073915Z.log`) | — | discharged |
| The observability host row schema has nine typed fields | one mutant per rule in the same check. `platform = "linux"` gives one message naming `platform` (same log) | — | discharged |

World assumptions: A330, A331 and A332 are each `not violated` in one oracle window (`db0beed0db3c` to `f3f2849bebd0`). None is observed holding beyond that window.

**8c. Alphabet check.** The interface requirements name only evaluated values, options and drvPaths. The world requirements A330–A332 name language and nixpkgs facts. No violation was found.

---

## Evidence recorded in this pass

- Oracle: `just drv-diff db0beed0db3c f3f2849bebd0 …/drv-delta.txt`: PASS, exit 0, 942.4 s. 33 differences: 28 declared, plus `gitleaks` and `treefmt` on both systems and `ntfy-tls-verification` from the base allow-list. No `vmTests` difference. Re-judged after the `drv-delta.txt` header and comment edits: PASS (`logs/rfo-verify-rejudge-20261127T073846Z.log`).
- Cost points (`logs/eval-cost-rfo-*-20261127T073*`), recorded in tasks 2.5 and 4.5. `nixos-magnetite`: +7,296 thunks (+0.03%), CPU not above run-to-run spread, so `failures` stays `functionTo`. `devin-worker-structural` and `greptimedb-pipeline`: GC bytes -39% and -4.4%.
- Hand-wired block against the registry: the block at `pxpsrtynvurl-` called ten judges on both configuration sets and `networkTargetObligations` through `withNetworkTargets` on both. It called `resolverReloadObligations` and `sopsBootInstallObligations` only where `self.lib.hosts.${name}.class == "darwin"`, which is every `darwinConfigurations` host and no `nixosConfigurations` host. The evaluated registry carries the same twelve keys with the same classes. Each entry's `failures` is the same binding its `flake.lib` export carries (a shared `let` in `commit-signing.nix`, `fleet-deployer.nix`, `deploy-record.nix`, `harmonia-gc.nix` and `mesh-hosts.nix`; `config.flake.lib.<name>.failures` in the other seven). No judge was dropped from a class.

## Issues by priority

**CRITICAL** (before archive): none after the 2026-11-27 update. The first pass's open tasks are done (3.5, 7.3), moved to `finish-fleet-package-set-and-budget-typing` (4.4, 6.1, 6.2, with their requirements) or dropped (7.2, with the MODIFIED delta). Every requirement left in this change's delta specs is discharged by what is on `main` (section 8b).

**WARNING**
- W1: the discharge for "The channels overlay offers no patched channel" (`specs/fleet-package-set-interface/spec.md:28`) expects `rg '\bpatched\b' … packages/docs/src/content/docs` to return only the amendment's text. It also returns ADR-0017's Decision text at lines 48 and 67-68, which D6 leaves as written on purpose, and English uses of the word (`guides/handling-broken-packages.md:195,248`, `concepts/architecture-overview.md:73`). None of these describes `pkgs.patched` as available, so the requirement holds. The discharge clause should name those exceptions.
- W2 (first pass, now moved): the scenario "a database is added without a backup" had no mutant run. It is no longer this change's scenario; its mutant is `finish-fleet-package-set-and-budget-typing` task 4.2.
- W3: the cost of the registry is measured on one machine check only.

**SUGGESTION**: none.

---

## Overall Decision

- [ ] (pass) PASS — may proceed to finishing-a-development-branch and archive
- [x] (warn) PASS WITH WARNINGS — may proceed to subsequent steps but note: the commit `1b0b281ba64c` and the 3.5 commit `007995cd6f0a` are verified; after the 2026-11-27 update no archive blocker remains, and W1 and W3 are non-blocking
- [ ] (fail) FAIL — return to the failed artifact, correct it, then re-run verify

**Next step**: archive this change; it no longer waits on `back-up-postgresql-off-host`. `finish-fleet-package-set-and-budget-typing` archives after it.
