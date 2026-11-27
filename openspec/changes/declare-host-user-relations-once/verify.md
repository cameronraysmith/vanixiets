# Verification Report

> This file is produced by the `openspec-verify-change` skill after apply completes, to confirm that the
> implementation is consistent with the specs / design / tasks. Any failed check must be returned to its
> corresponding artifact for correction before re-running verify.

**Change**: `declare-host-user-relations-once`
**Verified at**: `2026-11-27 09:47` (UTC)
**Verifier**: verification subagent (Claude), working copy whose files for this change equal jj change `oywttoqwttlt` (commit `5aca00cd664f`, `refactor: declare each host's users once on the host record`)

Evidence is cited from `logs/`. The drvPath diff ran on the commit before its rebase (`1be931444c18`); the rebase moved it onto a main that changed by OpenSpec and docs files and one unrelated code commit (two runtime tests, the collector option type, one assert message). Task 9.6 repeats the diff at the merged head.

---

## 1. Structural Validation (`openspec validate --all --json`)

- [x] This change reports `"valid": true` (`openspec validate declare-host-user-relations-once --strict`: valid)
- [ ] All items report `"valid": true`

**Result**:

```text
84 items; 81 valid. Invalid: compose-hosts-from-cohesive-aspects,
stand-up-gitea-mq-on-magnetite, stand-up-nixbot-on-magnetite — other
changes, not touched here.
```

| Item | Type | Issues |
|---|---|---|
| compose-hosts-from-cohesive-aspects | change | not this change; not examined |
| stand-up-gitea-mq-on-magnetite | change | not this change; not examined |
| stand-up-nixbot-on-magnetite | change | not this change; not examined |

---

## 2. Task Completion (`tasks.md`)

- [ ] All `- [ ]` have been changed to `- [x]`

**Incomplete tasks**:

| Task | Reason incomplete | Blocks archive? |
|---|---|---|
| 6.5 | darwin builds of `omnigent-worker-{capabilities,darwin}`: operator | yes |
| 9.6 | drvPath diff at the merged head: operator, after merge | no (post-merge) |

---

## 3. Delta Spec Sync State

| Capability | Sync status | Notes |
|---|---|---|
| host-user-attachment | pending sync | new capability; no main spec yet |
| host-user-attachment-interface | pending sync | new capability; no main spec yet |
| world-assumptions | pending sync | ADDED A340-A348; MODIFIED grounded vocabulary (rows appended; rows other changes add since 2026-11-27 are merged by hand at archive, design Risks) |

---

## 4. Design / Specs Coherence Spot Check

| Sampled item | design description | specs correspondence | Gap |
|---|---|---|---|
| D1 attachment | `flake.fleet.hosts.<h>.users.<a>` with `primary`, `admin`, `sopsBridge`, `uid`, `extraImports`, `overrides` | interface "The attachment field on the host entity" | none (`extraImports : listOf raw` in code, D1, D4, plan and the interface scenario) |
| D2 constraints | `apply`-time `assertMsg` per field | "Attachment constraints fail when read" | none |
| D4 aspect | homes, bridge, darwin admin and uids; no `users.users ? a` assertion | "One home-manager integration aspect per class", scenario "A darwin attachment declares its account" | none |
| D5/D6 flake value | `homeFlake` per home; worker gets `workerFlake` | "No ambient flake argument", "The worker aspect closes over a restricted value" | none |
| D9 checkedUsers | generated; accepted on CPU and wall | "checkedUsers is generated from static data" ("cost no more") | thunk count rises 0.5% / 1.0%; the scenario's "cost no more" is met only on CPU and wall time, as D9's outcome records |
| D12 oracle | one `just drv-diff`; may-change resolved | "Only the declared derivations change" | none |

**Drift warnings** (non-blocking): none. Corrected after this report was first written: design.md D1, plan.md's interface table and the interface scenario "The fields have their types" now say `extraImports : listOf raw`, as `modules/lib/host-users.nix:70` does; proposal.md's What Changes and Capabilities state the two flags (primary, admin) and that `custom.laptop.primaryUser` is removed, with `darwin/laptop.nix` reading the host record's `primaryUser`; the Linear description of CAM-130 is re-synced. brainstorm.md keeps its first-proposed `role` enum and generated `custom.laptop.primaryUser` as the record of that exploration; design D1 states why both were dropped.

Requirement text corrected after verification to match the verified code (no code changed): the interface requirement "One home-manager integration aspect per class" no longer says the aspect asserts that each attached account exists in `users.users` (that assertion was dropped because it cannot fail; on NixOS an undeclared account fails NixOS's own user assertions, task 4.6, and on darwin the attachment declares the account), and its scenario "What the aspect generates" gives the code's import order, `modules ++ extraImports ++ [ overrides ]` (`modules/system/home-manager-integration.nix:57`), as do plan.md and the home-manager onboarding guide. Also aligned: `uid` is required on darwin and forbidden on NixOS (spec and design D1, D2); "nine host modules" now says they cover ten hosts; the runtime-test homes of `vm-tests/shared-reference-tree.nix` receive no `flake` (spec, design D5); D7 says the worker-scope literal fails on any change of names, not only growth.

---

## 5. Implementation Signal

- [x] The change's files are committed: the working copy equals `oywttoqwttlt` for every path this change touches; other uncommitted edits in the shared working copy belong to other chains
- [ ] All related commits have been pushed

**Commit range**: parent `4b546df1f47f` .. `5aca00cd664f` (one commit; drv-diff measured at `ec2c878bf4bc..1be931444c18`, before the rebase). This verification adds edits to `tasks.md`, `design.md`, `proposal.md`, `plan.md`, `specs/host-user-attachment-interface/spec.md`, `drv-delta.txt` and this file, not yet folded into the commit.

---

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

- [x] No files: `ls docs/superpowers/specs/*.md` finds none

---

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

plan.md has no `[~]` rows; not applicable. No dogfood is deferred: no host or home derivation changes, so nothing reaches a running host (task 9.5).

---

## 8. Requirement trace, designation lint and discharge coherence

### 8.0 Requirements and scenarios traced to code and evidence

| Requirement | Code | Evidence | Status |
|---|---|---|---|
| Each account a person holds on a host is declared once | `modules/lib/host-users.nix:109` (table from `:120`); `clan/inventory/services/users/{cameron:17,crs58:18,tara:17}.nix` | narrowed 9.3 searches find nothing (`logs/dhuro-9-searches-20261127T094600Z.log`); instance machine lists equal main's (`logs/dhuro-9-projection-diff-20261127T091051Z.txt`) | verified; scenario "A person is given an account on a new host" has no witness (no attachment added) |
| A host provides exactly its declared accounts, home configurations and secret access | `modules/system/home-manager-integration.nix:58,70,76-77` | every host's `home-manager.users`, NixOS `hm-sops-bridge.users`, home drvPaths equal main's (projection diff); 4.6 mutant fails on NixOS's own user assertions (`logs/dhuro-4-mutants-20261127T090540Z.log`); toplevels identical (drv-diff); every `checks.x86_64-linux` attribute built (`logs/checks-linux-20261127-044502.log`) | verified; darwin builds with the operator (6.5) |
| A darwin host's admin account is declared separately from its primary user | `host-users.nix:37-45,101`; `hosts.nix:83,196`; aspect `:76` | `system.primaryUser`, uids and `primaryUser` equal main's on all four darwin hosts (projection); seven constraint mutants fail naming host and account, `tryEval` false (`logs/dhuro-3-mutants-20261127T090540Z.log`) | verified |
| Which hosts run a person's Omnigent workers is declared once | `modules/lib/fleet-workers.nix:16,79`; `clan/inventory/services/omnigent.nix:50`; `lib/fleet-deployer.nix:49`; participants `magnetite:137`, `pyrite:89`, `stibnite:42` | `roles.host.machines`, requesters, participants equal main's (projection); literal oracles untouched (7.4); `omnigent-worker-inventory` and `fleet-deployer-obligations` built (`logs/checks-linux-20261127-044502.log`) | verified |
| A worker's home cannot read a person's private settings or whole home configuration | `modules/home/ai/omnigent/worker.nix:16-24,124`; `checks/omnigent-workers.nix:1006-1083`; `darwin/omnigent-host.nix` passes only `osConfig` | `omnigent-worker-scope` built, so `positive`, `reachUsers`, `reachContentPrivate`, `allowedNames`, `noShadow` pass (`logs/checks-linux-20261127-044502.log`, `logs/dhuro-6-scope-eval-20261127T094609Z.log`); binding `users = config.flake.users` fails naming `reachUsers` (`logs/dhuro-6-scope-20261127T090540Z.log`) | verified on Linux; darwin builds with the operator |
| The person-account correspondence is stated once | `modules/home/users/aliases.nix:34,40-52` | all eight keys both directions, `personOf "nobody"` throws (`logs/dhuro-2-vocabulary-deployer-20261127T090407Z.log`); `signingPerson` gone (9.4); `eval-users-lib`, `agent-telemetry-emitters` built (`logs/checks-linux-20261127-044502.log`) | verified |
| Every home configuration is checked without a hand-kept list | `modules/checks/home.nix:53` | check names equal main's except the added scope check; cost in `logs/dhuro-4-keyset-cost-20261127T092547Z.log` (design D9 outcome) | verified, with the thunk increase accepted |
| A person's home does not depend on the order a host's settings are read | `home-manager-integration.nix:58,64,83`; `home/mk-home.nix:31` | no `extraSpecialArgs.flake` or host `_module.args.flake` remains: only the aspect's comment and assertion, `mk-home.nix:31`, `worker.nix:124` and `modules/home/README.md` prose match (`logs/dhuro-9-searches-20261127T094600Z.log`); 5.5 full-value mutant fails with the assertion (`logs/dhuro-5-mutants-20261127T090540Z.log`); every toplevel and home identical (drv-diff) | verified |
| Interface requirements (fifteen) | as above, plus `jj-pr-tags.nix:302`, `system/stibnite-session.nix` | tasks 2.1-7.4 logs; drv-diff PASS with all eight `may-change` entries identical and removed, re-judged PASS (`logs/drv-diff-ec2c878bf4bc-1be931444c18-20261127T092819Z/report.20261127T094539Z`); Linux check builds (`logs/checks-linux-20261127-044502.log`) | verified by evaluation, drv-diff and Linux builds |
| Trust boundary | capability text | scenario "A recorded uid differs from the account on disk": no witness after this change (A346) | stated, unwitnessed by design |

### 8a. Designation lint (behavioral: `host-user-attachment`)

Content nouns resolved against the delta's designation rows (`specs/world-assumptions/spec.md`): person, account, host, home configuration, Omnigent worker, private settings, admin, primary user, fleet description, personal key each have a row. "secret access" has no row of its own; it is used as the access a personal key grants, which the "personal key" row covers. No unresolved noun names a machine phenomenon.

### 8b. Discharge coherence

| Requirement | Discharged by (S) | Under (W) | Status |
|---|---|---|---|
| R1 declared once | D1, D3, D4 | A343 | `observed` at apply (instances name the same machines) |
| R2 exactly the declared accounts | D3, D4 | A343, A344 | `observed` (projections, drv-diff) |
| R3 admin separate from primary | D2, D4 | A345, A346 | A345 `configured` (source read); A346 `configured` only: a uid mismatch is not detected |
| R4 workers declared once | D8 | — | `observed` (projections) |
| R5 worker scope | D6, D7 | A341, A347 | `observed` at evaluation (scope cases, mutant) |
| R6 correspondence once | D10 | — | `observed` (evaluation over every key) |
| R7 checked without a list | D9 | — | `observed` (check names) |
| R8 order independence | D5 | A340, A342, A348 | A342, A348 `not violated` over this commit's drv-diff window |

### 8c. Alphabet check

No behavioral requirement names an option or file; the interface capability names only evaluable values. No violation found.

---

## Overall Decision

- [ ] (pass) PASS — may proceed to finishing-a-development-branch and archive
- [x] (warn) PASS WITH WARNINGS — may proceed to subsequent steps but note: every requirement is traced to code and to evaluation, drv-diff or build evidence; the drv-diff passed with every host, home and runtime test identical; `just check-fast auto off x86_64-linux` built every `checks.x86_64-linux` attribute (exit 0, 264 s, `logs/checks-linux-20261127-044502.log`), and prek's gitleaks and treefmt hooks passed on every file of the commit (tasks 2.3-8.3 ticked); only the darwin builds (6.5) remain before archive, and 9.6 after merge
- [ ] (fail) FAIL — return to the failed artifact, correct it, then re-run verify

**Next step**:

The operator runs task 6.5's darwin builds; then the pull request, and task 9.6 at the merged head.
