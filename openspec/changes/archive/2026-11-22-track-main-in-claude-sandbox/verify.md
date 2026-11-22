# Verification Report

> This file is produced by the `openspec-verify-change` skill after apply completes, to confirm that the
> implementation is consistent with the specs / design / tasks. Any failed check must be returned to its
> corresponding artifact for correction before re-running verify.

**Change**: `track-main-in-claude-sandbox` (CAM-119)
**Verified at**: `2026-11-22 08:05` UTC
**Verifier**: subagent `TrackMainImpl` (omp), running `openspec-verify-change` and this schema's checks 1–7

Prechecks: the change's commits on `main` run from `b374a85f9` (`openspec: propose track-main-in-claude-sandbox`) to `0cd1be05b` (`fix(checks): assemble transcript-gitleaks fixtures at build time`), 14 commits, and `tasks.md` holds 20 `- [x]` lines, so both are positive.

---

## 1. Structural Validation (`openspec validate --all --json`)

- [x] All items report `"valid": true`, for this change and the main specs

**Result**:

```text
totals: 66 items, 64 passed, 2 failed (changes 33/31, specs 33/33)
openspec validate track-main-in-claude-sandbox --strict: Change 'track-main-in-claude-sandbox' is valid
```

The two failures are other changes, unchanged since `bootstrap-claude-sandbox`'s verify: `stand-up-gitea-mq-on-magnetite` and `stand-up-nixbot-on-magnetite`, whose MODIFIED "Grounded vocabulary for behavioral requirements" omits a scenario the main spec has.
This change's own designation-table warning was fixed on 2026-11-22 by moving the table under a scenario, so `--strict` passes.

## 2. Task Completion (`tasks.md`)

- [x] All `- [ ]` have been changed to `- [x]`

20 of 20. Task 3.3 is closed without measurement by the operator (A185 stays documented, not measured), 4.1 by its fallback, and 4.2 is dropped because `checks.x86_64-linux.flake-input-sources` enforces it per lock change; each records its reason in `tasks.md`.

## 3. Delta Spec Sync State

| Delta spec | State before archive |
|---|---|
| `specs/claude-sandbox-bootstrap/spec.md` | Needs sync: 1 MODIFIED (`One closure defines the environment`), 2 ADDED |
| `specs/claude-sandbox-interface/spec.md` | Needs sync: 11 ADDED, 3 REMOVED |
| `specs/world-assumptions/spec.md` | Needs sync: 4 ADDED (A184–A187), 1 MODIFIED (the designation table) |

The archive step syncs them.

## 4. Design / Specs Coherence Spot Check

| Requirement | Discharged by | Evidence |
|---|---|---|
| R1 Cloud sessions run main's newest published closure | the app's walk (`modules/apps/claude-sandbox-setup.sh` `choose`) | tasks 3.1, 3.2, 5.3, 6.5: `mode=tracked dist=0` |
| R2 Pinned by an argument | `choose`'s `pinned` outcome | task 5.2: `mode=pinned`, no clone or evaluation |
| R3 The setup box holds a fixed bootstrap | the `claude-sandbox-setup-script` check, its 200-column assertion (A187) | 13 mutants and the width mutants fail; Default stores the generated 7 lines (`cmp`) |
| R4 The logic is the flake app | `modules/apps/claude-sandbox-setup.{nix,sh}`, shellchecked by its build | the SC2070 mutant fails the build |
| R5 Every command from the flake | `runtimeInputs` | task 5.2: each command resolves to a store path with the image's `git` and `awk` removed |
| R6 Setup never fails the session | final `exit 0` in box and app, one marker per run | every container and cloud run exited 0 with a marker |
| R7 Substituted, never built | `--max-jobs 0 --option builders ''` on the realise only | check assertion; all-miss run activates nothing |
| The marker records the walk | the marker line | `skip=<rev>:narinfo`, `skip=<rev>:eval/102` in task 1.3 |
| The staleness hook only reads | `claude-sandbox-staleness` | task 2.1 container cases; `moved=no`/`moved=yes` in the cloud |
| Every lock source is in the cache | `checks.x86_64-linux.flake-input-sources` (#4127) | D7 |
| Sessions report how far behind | the staleness hook, `session.json`'s marker | tasks 3.1, 6.5 |

Removed requirements: no `flake.lib.claudeSandboxSetupScript`, `trackTemplate`, `claude-sandbox-setup-script` app or `P=/nix/store` setup text remains in `modules/` or `lib/`; the x86_64-linux apps matching `claude` are `claude-cloud-session`, `claude-sandbox-setup` and `update-claude-code`.

**Warning (accepted)**: the scenario "The budget runs out" is covered only by its 5-miss half (task 1.3's all-miss run, done in 176 s); the 300 s path, marker `skip=<rev>:budget`, has never run.
Accepted by the orchestrator on 2026-11-22: every walk evaluation runs under `timeout "$left"` and the loop breaks once `left` reaches 0, so a stall fails safe, with `skip=<rev>:budget` in the marker and exit 0, and a stalled-remote container test would cost more to maintain than the risk warrants.

**Suggestions and their dispositions**:

- `verify.md` itself was the next artifact before archive: written here.
- `packages/docs/src/content/docs/development/traceability/satisfaction.md` still named the removed generator: regenerated at archive.
- `plan.md` describes the superseded generator design: a line at its top now points to design.md D2 (final); kept otherwise as the historical execution record.

## 5. Implementation Signal

- [x] No unstaged files in the worktree (the jj working copy `@` is empty; this report is squashed into its chain)
- [x] All related commits have been pushed: `b374a85f9..0cd1be05b` is on `origin/main`

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

- [x] No files, or any existing files are legitimate residue from before schema installation

`ls docs/superpowers/specs/*.md` printed nothing.

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

`plan.md` has no `[~]` rows, so this section is blank (PASS).

---

## Overall Decision

- [ ] (pass) PASS — may proceed to finishing-a-development-branch and archive
- [x] (warn) PASS WITH WARNINGS — may proceed to subsequent steps but note: the 300 s budget path of the walk is untested, accepted by the orchestrator on 2026-11-22 (§4)
- [ ] (fail) FAIL — return to the failed artifact, correct it, then re-run verify

**Next step**:

Write the retrospective, then archive: sync the three delta specs into `openspec/specs`, move the change to `openspec/changes/archive/2026-11-22-track-main-in-claude-sandbox`, and regenerate the satisfaction projection.
