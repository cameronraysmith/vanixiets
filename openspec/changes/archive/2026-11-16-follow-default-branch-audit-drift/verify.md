# Verification Report

**Change**: `follow-default-branch-audit-drift`
**Verified at**: `2026-11-16`, before archive, on the chain's pinned commit `bf3f5d0309517a8976cbb7a7e1fcf4596e51648c`
**Verifier**: the implementing agent, from `tasks.md`, `design.md`, `proposal.md`, `specs/` and the evidence logs

Evidence names are files under `logs/`, which is git-ignored.
Every build evaluated the pinned commit as `git+file://$PWD?rev=<commit>`, never the working copy.

---

## 1. Structural Validation

- [x] The change validates under `--strict`
- [x] Both full check sets evaluate from the pinned commit

`openspec validate follow-default-branch-audit-drift --strict` prints `Change 'follow-default-branch-audit-drift' is valid` (`ghq-d28-openspec-validate-20261116-*.log`; again before archive in `ghq-d28-openspec-archive-*.log`).
The three ADDED requirement statements are each under 500 characters; the MODIFIED `This capability states its own trust boundary` was over 500 before and grows by one sentence, and `shared-reference-tree-interface` already failed `--specs --strict` on `origin/main` for eight long statements.
`checks.x86_64-linux` (166 checks) and `checks.aarch64-darwin` (110 checks) evaluate every `drvPath` from the pinned commit (`ghq-d28-eval-checks-20261116-200111.log`).

---

## 2. Task Completion (`tasks.md`)

- [x] All `- [ ]` have been changed to `- [x]`

All eight items are ticked. `plan.md` is absent: `tasks.md`, whose items carry their verification commands, served as the plan; no plan was written after the work.

| Task | Reason incomplete | Blocks archive? |
|---|---|---|
| — | — | — |

---

## 3. Delta Spec Sync State

| Capability | Sync status | Notes |
|---|---|---|
| `shared-reference-tree-interface` | synced at archive | +3 `An update follows the remote's default branch`, `The writer's request handler sets its own umask`, `A participating account audits the tree against GitHub without changing it`; ~1 `This capability states its own trust boundary` |

`shared-reference-tree` has no delta: following the default branch is part of refreshing, and the audit only reads.

---

## 4. Design / Specs Coherence Spot Check

| Sampled item | design description | specs correspondence | Gap |
|---|---|---|---|
| D28 | `ls-remote --symref`; single-branch clones switch at their depth; full clones move `origin/HEAD` and switch only from a clean previous default | `An update follows the remote's default branch` and its scenario | none |
| D29 | GraphQL through the account's `gh`; findings with commands; read-only; graceful without a token | `A participating account audits the tree…` and its two scenarios | none |
| D30 | no writer-side deletion or relocation | the sentence added to the trust boundary and its scenario `An upstream repository is renamed` | none |
| D32 | handler sets umask `0027` in `main()` | `The writer's request handler sets its own umask` | none |

**Drift warnings** (non-blocking): none.

---

## 5. Implementation Signal

- [x] Every path of this change is routed into the chain change `zpvrspvu`; the working copy holds none of them
- [ ] All related commits have been pushed: not pushed; publishing is the orchestrator's step

**Commit range**: `main@origin` `4105f209f3b7`..`zpvrspvu`.

---

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

- [x] No files: `ls docs/superpowers/specs/*.md` lists nothing

---

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

`plan.md` is absent, so there are no `[~]` rows. Four runtime steps are explicitly pending after deployment; none is claimed here:

| Pending observation | Nearest automated evidence | Coverage assessment | Real gap? |
|---|---|---|---|
| an update following a renamed default branch through the writer on stibnite and on a NixOS host | VM subtest through the socket-activated writer on NixOS; handler package test with lazy and full clones | NixOS writer, socket and wrapper; not darwin's launchd writer, not a GitHub remote | yes until observed |
| the darwin handler creating entries without permission for others | handler package test starting the handler with umask 022, as launchd does | the handler's own umask; not launchd itself | yes until a clone on stibnite is checked after deployment |
| the operator's correction of entries the writer created open to others (stibnite: 105,754 entries; magnetite and pyrite: none) | dry run of `logs/ghq-umask-repair.sh` on stibnite (`ghq-umask-repair-dryrun-stibnite-20261116-195827.log`) | the selection only; nothing was changed | yes until run with `--apply` after deployment |
| an audit of the shared tree by each participating account after deployment | wrapper package test with a fake `gh`; a read-only run over stibnite's tree with crs58's token (`ghq-d29-audit-stibnite-20261116-*.log`: 557 checked, 22 with findings, nothing changed) | the script's logic and one live run; not the delivered package | no for the logic; the delivered binary is unobserved |

---

## 8. Designation Lint and Discharge Coherence

These are agent-executed checks; `openspec validate` checks structure only.

### 8a. Designation lint

No `behavioral` capability has a delta in this change; the lint has nothing to check.

### 8b. Discharge coherence

| Requirement | Discharged by (S) | Under (W) | Status |
|---|---|---|---|
| ADDED `An update follows the remote's default branch` | handler package test: lazy clones of an upstream whose default moved from `master` to `main` with `master` deleted and kept follow it at depth 1 with the filter kept; a clean full clone on `master` switches; a full clone on a feature branch and one with a local change keep their branch while `origin/HEAD` moves; the test failed against the handler before the change (`ghq-d28-handler-red-20261116-195140.log`) and passes with it (`ghq-d28-handler-green-20261116-195236.log`, `ghq-d28-pkgtests-magnetite-20261116-200111.log`); VM subtest through the writer, failing on a throwaway commit that drops `follow_default_branch` | — | discharged at package-test and VM interfaces (`ghq-d28-vmtest-pyrite-20261116-200158.log`, `ghq-d28-vmtest-pyrite-negctl-20261116-200327.log`) |
| ADDED `The writer's request handler sets its own umask` | handler package test starting every handler with umask 022 and failing on any entry open to others or group-writable: 72 such entries against the handler before the change, none after | — | discharged at the package-test interface; darwin after deployment pending (§7) |
| ADDED `A participating account audits the tree against GitHub without changing it` | wrapper package test with a fake `gh`: a rename with relocate commands, a rename beside the new clone with retire commands, a deleted, an archived, a case-only and a drifted repository, the count line, the tree unchanged by path, mode and mtime, and the no-token message with exit 0; a read-only run over stibnite's tree | — | discharged at the package-test interface |
| MODIFIED `This capability states its own trust boundary` | the requirement's own statement | — | undischarged — boundary statement, not a property; the writer's request set has no delete, rename or relocate action (handler `FIELDS`) |

### 8c. Alphabet check

The ADDED and MODIFIED interface requirements name configuration, commands, request outcomes and file modes the machine observes; none references world state.

---

## Other evidence

- `prek run --files` on every changed path passed (`ghq-d28-prek-20261116-200043.log`, and again on the archive and projection files).
- D32 cause: `launchctl print system/org.vanixiets.ghq-writer` reports `umask = 27`, yet a clone the writer made on stibnite on 2026-11-16 was `0755`, and launchd's own `StandardErrorPath` file is `0644`; magnetite and pyrite have no directory open to others under their roots.
- The probe clone `octocat/Spoon-Knife` was retired as the writer (mv, then rm) the same day.

---

## Overall Decision

- [ ] (pass) PASS — may proceed to finishing-a-development-branch and archive
- [x] (warn) PASS WITH WARNINGS — may proceed to subsequent steps but note: `plan.md` is absent and `tasks.md` carried the plan; §7's four runtime steps are pending after deployment; the trust-boundary statement grew
- [ ] (fail) FAIL — return to the failed artifact, correct it, then re-run verify

**Next step**:

Publish the chain; after deployment run `logs/ghq-umask-repair.sh` on stibnite (dry run, then `--apply`), and observe an update following a renamed default branch and a new clone's modes on stibnite.
