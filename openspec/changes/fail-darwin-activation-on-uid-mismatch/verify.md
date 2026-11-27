# Verification Report

**Change**: `fail-darwin-activation-on-uid-mismatch`
**Verified at**: `2026-11-27 19:14` (UTC)
**Verifier**: verify subagent (openspec-verify-change), on stibnite

Implementation: jj change `zywkxopnokql` (commit `38e82210e6a8`; its two code files are identical to `2d5daa389571`, the commit the full drv-diff ran on). Files: `modules/system/home-manager-integration.nix`, `modules/checks/darwin-uid-preflight.nix`.

---

## 1. Structural Validation (`openspec validate --all --json`)

- [x] This change reports valid under `--strict`

**Result**:

```text
openspec validate fail-darwin-activation-on-uid-mismatch --strict  -> valid
openspec validate --all --json -> 87 items, 85 passed, 2 failed
```

| Item | Type | Issues |
|---|---|---|
| stand-up-gitea-mq-on-magnetite | change | unrelated to this change; not touched |
| stand-up-nixbot-on-magnetite | change | unrelated to this change; not touched |

---

## 2. Task Completion (`tasks.md`)

- [ ] All `- [ ]` have been changed to `- [x]` (10 of 13 done)

| Task | Reason incomplete | Blocks archive? |
|---|---|---|
| 4.2 `darwin-rebuild check` on each Mac | operator's, on the Macs | yes |
| 4.3 deploy stibnite, blackphos, argentum, rosegold | operator's, on the Macs | yes |
| 4.4 observe A374 (`id -u` against `dscl`) on each Mac | operator's, on the Macs | yes |

Evidence for the closed tasks: `logs/fdaum-1-baseline-20261127T175059Z.log`, `logs/fdaum-1-sources-20261127T175059Z.md`, `logs/fdaum-1-knownusers-20261127T175059Z.log` (every attachment is in its host's `users.knownUsers`), `logs/fdaum-2-order-20261127T175059Z.log`, `logs/fdaum-3-mutants-20261127T175059Z.log` (mutants a, b killed on the mutant-uid case, c on the absent case), `logs/fdaum-4-*`, and the full `just drv-diff 3fea6f9b152e 2d5daa389571 …/drv-delta.txt`: `result: PASS`, exit 0, 991.5 s (`logs/drv-diff-3fea6f9b152e-2d5daa389571-20261127T185003Z/report`). The `darwin-uid-preflight` drvPath at that commit (`fsmdhnmj…-darwin-uid-preflight.drv`) is the one the implementer built; its output `ll3sz3rc…-darwin-uid-preflight` is in the store.

---

## 3. Delta Spec Sync State

| Capability | Sync status | Notes |
|---|---|---|
| darwin-account-uid-agreement | pending sync | new capability; no main spec yet |
| darwin-account-uid-agreement-interface | pending sync | new capability; no main spec yet |
| world-assumptions | pending sync | A370-A374 and the designations are not in `openspec/specs/world-assumptions/spec.md` yet |

---

## 4. Design / Specs Coherence Spot Check

| Sampled item | design description | specs correspondence | Gap |
|---|---|---|---|
| D2 placement | `preActivation` at `lib.mkOrder 600` | interface requirement 1; A370, A372, A373 | interface requirement does not state the position (W1) |
| D3 comparison | `id -u` per attachment, empty passes, all mismatches then `exit 1` | interface scenarios "Matching and absent accounts", "A mismatch" | none in text; see W2 |
| D4 one source | `home-manager-integration.uidPreflight`, read-only, internal | interface requirement 1 | none |
| D5 check | three cases per host under a stub `id`; `medium`, unmeasured | interface requirement 2 | none |
| D6 delta | four toplevels, check added, `fleet-alert` | drv-delta.txt, drv-diff PASS | none |

### Requirement and scenario trace

| Requirement / scenario | Code | Evidence | Status |
|---|---|---|---|
| Behavioral: not deployed while an attached account's uid differs | `home-manager-integration.nix` darwin branch, `uidPreflight` + `preActivation.text = lib.mkOrder 600 …` | rendered order on all four Macs (below); mutant check; drv-diff | verified in evaluation; not observed on a Mac (4.3) |
| — Every account has its recorded uid | `[[ -n "$u" && "$u" != <uid> ]]` false | `matches` case, check built | verified under stub |
| — A recorded uid is wrong | `uidMismatches+=(…)`, `exit 1` before the linux-builder removal | `mismatch` case names the account; order eval | verified under stub; fails before change per A370 |
| — Two recorded uids are wrong | all attachments compared before `exit 1` | code read only; the check mismatches one account at a time | not tested (W3) |
| — A new attached account | `u=$(id -u …) \|\| u=` passes | `absent` case (all accounts absent at once) | verified under stub; creation with the recorded uid is nix-darwin's, not tested |
| — Another host | text rendered per host from that host's attachments | per-host rendering, drv-diff | verified by construction |
| Behavioral: deploy check without changing the host | same text in `preActivation`, run by `darwin-rebuild check` (A373) | source reading only | not observed (4.2); see W5 |
| Interface: comparison runs in pre-activation and fails | as above | evaluation, check | verified |
| — A host boots | `preActivation` not in the boot daemon (A372) | source reading, `fdaum-1-sources` | verified at source |
| — Only darwin hosts render it | NixOS branch sets `uidPreflight = ""` and adds nothing to activation | drv-diff: every NixOS toplevel identical | verified |
| Interface: shown to fail on a mutant uid | `modules/checks/darwin-uid-preflight.nix` | check built; mutants a, b, c killed | verified |
| — cases and size | `matches`/`absent`/`mismatch`; `testSizes` medium, `measured = false` | code read; drv-diff lists the check as added | verified |
| — removed or inverted | — | mutants a, b fail the mutant-uid case | verified |
| — fails an absent account | — | mutant c fails the absent case | verified |

Correction (2026-11-27, after stibnite's activation): the row "deploy check without changing the host" assumed `darwin-rebuild check` stops after `checks`. At nix-darwin `663d8b96` `activate`'s `#!/usr/bin/env -i` line (`modules/system/activation-scripts.nix:84`) drops the `checkActivation=1` that `darwin-rebuild.sh:230-233` exports, so no `ok` line is printed; a disagreement stops at the comparison before any step that changes the Mac, and an agreement runs the whole activation without setting the profile (`logs/stibnite-darwin-rebuild-check-20261127-171145.log`, `logs/stibnite-post-activation-supplement-20261127-171547.log`).

### World assumptions

| Assumption | Evidence | Status |
|---|---|---|
| A370 activation order, `set -e` | source lines in `fdaum-1-sources`; nix-darwin `modules/nix/linux-builder.nix:163-166`; rendered `preActivation` of all four Macs | configured (read at source and in the rendered text) |
| A371 profile set, then activate; clan uses `darwin-rebuild switch` | `fdaum-1-sources` | configured (source reading) |
| A372 boot daemon skips `preActivation` | `fdaum-1-sources` | configured (source reading) |
| A373 `darwin-rebuild check` | `fdaum-1-sources` | configured (source reading); not run on a Mac (4.2) |
| A374 `id -u` agrees with Directory Services | nix-darwin's own use of `id -u` | not observed; task 4.4 open |

Correction (2026-11-27): A373 was run on stibnite and contradicted the source reading above; it now states that `check` runs the whole activation without setting the profile (see the correction under the trace table).

### Rendered `preActivation` order (`darwinConfigurations.<host>.config.system.activationScripts.preActivation.text`, evaluated at verify from the working copy)

| Host | `/run/current-system` read | `uidMismatches=()` | `exit 1` | `rm -rf /var/lib/linux-builder` |
|---|---|---|---|---|
| stibnite | 2-3 | 7 (crs58) | 16 | 19 |
| blackphos | 2-3 | 7 (crs58, raquel) | 20 | 23 |
| argentum | 2-3 | 7 (cameron, christophersmith) | 20 | 23 |
| rosegold | 2-3 | 7 (cameron, janettesmith) | 20 | 23 |

A closure diff (`dix diff`, reads only) follows the removal on every host.

**Drift warnings** (non-blocking):

- W1: the check runs the comparison's text, not its position. Nothing fails if a later definition below order 600 that changes the Mac is added, or if the comparison is moved back to the default priority; the order above is shown only by this evaluation.
- W2: any failure of `id`, not only an absent account, empties `u` and passes (D3 accepts this; `id` failing for a present local account is outside A374).
- W3: the check mismatches one account at a time and makes all accounts absent at once; the two-mismatch scenario and a mixed absent/mismatch case are not exercised.
- W4: `brainstorm.md:33` still says "at default priority"; it records the exploration before D2 moved the comparison to order 600 and is left as history.
- W5: under `darwin-rebuild check`, `preActivation` also runs nix-darwin's `rm -rf /var/lib/linux-builder` when the comparison passes. The behavioral requirement "The operator can learn of a disagreement without changing the host" ("changing nothing on the host") and the designation `deploy check` ("changes nothing on the host") hold for a failing comparison and for the running configuration, not for that removal. A370 and A373 were corrected at verify to state the removal; the requirement and designation wording is left for a decision.
  - Correction (2026-11-27): the requirement and the designation are reworded. On the locked nix-darwin a passing `darwin-rebuild check` runs the whole activation without setting the system profile, so they now hold for a disagreement only (design.md, A373).

Corrections made at verify: `tasks.md` 2.1 ("default priority" to order 600) and 2.2 (order includes nix-darwin's own `preActivation` text, with this evaluation as evidence); `plan.md:79` (snippet now `lib.mkOrder 600`) and `plan.md:182` (the review-focus claim that a later `mkBefore` could not precede a change was false); `specs/world-assumptions/spec.md` A370 and A373 (nix-darwin's `preActivation` contains the linux-builder removal).

---

## 5. Implementation Signal

- [x] Code committed in jj change `zywkxopnokql` (working copy matches for both code files)
- [ ] All related commits have been pushed (not on any remote bookmark at verify; a publish of other commits is running)

**Commit range**: parent `3fea6f9b152e` .. `38e82210e6a8` (drv-diff ran on `2d5daa389571`, same code)

---

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

- [x] No files under `docs/superpowers/specs/`

---

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

plan.md has no `[~]` rows. The open operator tasks are listed here because no automated test stands in for them:

| Deferred dogfood (plan §) | Equivalent automated test | Coverage assessment | Real gap? |
|---|---|---|---|
| Task 4 Step 2 / tasks 4.2 `darwin-rebuild check` | `darwin-uid-preflight` | rendered text under a stub `id`; no real accounts, no `activate` | yes: operator runs it on each Mac |
| Task 4 Step 3 / tasks 4.3 deploy | drv-diff, rendered order | evaluation only | yes: operator deploys |
| Task 4 Step 4 / tasks 4.4 `id -u` vs `dscl` | none | — | yes: A374 unobserved |

---

## 8. Designation Lint and Discharge Coherence

**8a.** Behavioral content nouns resolved in the change's designation table: host (fleet), deploy, deploy check, operator, account (world), attached account, uid, recorded uid. `nix-darwin host` resolves through `host kind`. `running configuration` has no row (suggestion: add one, or reword the scenario). `deploy check` is defined as changing nothing on the host, which W5 qualifies.

**8b.**

| Requirement | Discharged by (S) | Under (W) | Status |
|---|---|---|---|
| A host is not deployed while an attached account has a uid other than its recorded uid | interface "The comparison runs in pre-activation and fails the activation" | A370, A371, A374 | A370, A371 configured; A374 not observed |
| The operator can learn of a disagreement without changing the host | same interface requirement, run by `darwin-rebuild check` | A373 | configured; W5 |
| The comparison runs in pre-activation and fails the activation | `uidPreflight` at order 600 | A370, A372 | configured |
| The comparison is shown to fail on a mutant uid | `darwin-uid-preflight` | none | built; mutants killed |

Correction (2026-11-27): "The operator can learn of a disagreement without changing the host" now holds for a disagreement only; on agreement the deploy check activates the new configuration without setting the profile (A373 as corrected). The requirement is renamed "The operator can run the comparison before a deploy, and a disagreement stops it before the host changes".

**8c.** No behavioral requirement names an interface phenomenon. The interface requirements name only machine phenomena (`id -u`, options, the check); the trust boundaries state what they do not cover.

---

## Overall Decision

- [ ] (pass) PASS — may proceed to finishing-a-development-branch and archive
- [x] (warn) PASS WITH WARNINGS — may proceed to subsequent steps but note: the change cannot archive until the operator closes tasks 4.2-4.4 on the four Macs; W1-W5 above, with W5 needing a decision on the wording of the deploy-check requirement and designation.
- [ ] (fail) FAIL — return to the failed artifact, correct it, then re-run verify

**Next step**:

Review (In Review). The operator runs `just darwin-test <host>` and then deploys each of stibnite, blackphos, argentum and rosegold, and records `id -u` against `dscl` for each attachment; then archive.

Correction (2026-11-27): `just darwin-test <host>` stops at nix-darwin's root check; the command is `sudo darwin-rebuild check --flake .#<host>` (task 4.2), and a passing run is itself an activation.
