# Verification Report

**Change**: `omnigent-login-grant-lifetime`
**Verified at**: `2026-11-23`, before archive, nine days after pull request #3873 merged and magnetite deployed it (2026-11-14 22:12–22:13Z)
**Verifier**: subagent `GrantChangeArchive` (omp), running `openspec-verify-change` from `tasks.md`, `design.md`, `proposal.md`, `specs/` and the working copy on `main`

---

## 1. Structural Validation

- [x] `openspec validate omnigent-login-grant-lifetime --strict`: `Change 'omnigent-login-grant-lifetime' is valid`

`openspec validate --all --strict` fails 37 of 68 items, none of them this change; they fail for reasons this change does not touch (requirement text over 500 characters, or a placeholder `## Purpose`, the main `world-assumptions` spec among them).

## 2. Task Completion (`tasks.md`)

- [x] All `- [ ]` have been changed to `- [x]`

6 of 6, each with its recorded evidence of 2026-11-14.

## 3. Delta Spec Sync State

| Delta spec | State before archive |
|---|---|
| `specs/world-assumptions/spec.md` | Needs sync: 2 ADDED (A105, A106); neither number is in the main spec |

## 4. Design / Specs Coherence Spot Check

- D1: `modules/nixos/omnigent.nix:119` sets `OMNIGENT_GRANT_MAX_LIFETIME_DAYS = "90"`.
- D2: the gate's query and its result are recorded in task 2.1; A105 and A106 carry the purge-first deploy.
- D3: no `OmnigentLoginGrantExpiring` rule exists on `main`, as decided; D3's "If revisited" records the shelved commit `cc0370f3` before its abandonment.

**Drift warnings** (non-blocking): `pkgs/by-name/omnigent/package.nix` now pins omnigent 0.23.0, and A105 and A106 cite 0.22.0.
Every line they cite was re-read in the 0.23.0 package on 2026-11-23 and still says the same: `server/routes/device_auth.py:118`, `:123-156`, `:288`, `:408`, `:522-525`, `:529-545`, `:582-610`, `server/device_grant_store.py:586-640` and `db/enum_codecs.py:88-94`.

## 5. Implementation Signal

- [x] The implementation is on `main` through #3873; this archive changes only `openspec/`.

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

- [x] No files: the change wrote nothing under `docs/superpowers/specs/`.

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

Not applicable: tasks 2.1 and 3.2 were run on magnetite on 2026-11-14 and recorded, and nothing was deferred.

## 8. Designation Lint and Discharge Coherence

A105 and A106 are world assumptions: each names its evidence and a violation condition, and each is discharged by omnigent's source rather than by anything this fleet builds.

---

## Overall Decision

- [ ] (pass) PASS — may proceed to finishing-a-development-branch and archive
- [x] (warn) PASS WITH WARNINGS — may proceed to subsequent steps but note: `plan.md` is absent and `tasks.md` carried the plan; A105 and A106 cite 0.22.0, though their lines still hold in 0.23.0; no retrospective was written
- [ ] (fail) FAIL — return to the failed artifact, correct it, then re-run verify

**Next step**: archive.
