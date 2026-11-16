# Verification Report

**Change**: `shared-tree-lfs-pointer-policy`
**Verified at**: `2026-11-16`, after the change was archived in the same chain; written from the evidence logs below, with no new builds
**Verifier**: the implementing agent, from `tasks.md`, `design.md`, `proposal.md`, `specs/` and the evidence logs; the commands of §1 were run read-only against a copy of the chain's tree

Evidence names are files under `logs/`, which is git-ignored, named `ghq-lfs-*-<timestamp>.log`.
Every build evaluated the chain's pinned commit as `git+file://$PWD?rev=<commit>`, never the working copy.

---

## 1. Structural Validation

- [x] The change validated before archive
- [x] Archive synced its deltas without error
- [x] No spec newly fails strict validation

`openspec validate shared-tree-lfs-pointer-policy --strict` printed `Change 'shared-tree-lfs-pointer-policy' is valid` (`ghq-lfs-openspec-validate-20261116-131855.log`, and again before archive in `ghq-lfs-openspec-archive-20261116-132729.log`).
The first validation failed because the MODIFIED behavioral requirement dropped the scenario `An acquisition request asks for more than adding, refreshing or deepening` and an ADDED interface requirement exceeded 500 characters; the scenario was kept under its name and the requirement split in two (`ghq-lfs-openspec-validate-20261116-131837.log`).
`openspec archive -y` applied `shared-reference-tree` +1 ~1 and `shared-reference-tree-interface` +2 ~3 and printed `Specs updated successfully` (`ghq-lfs-openspec-archive-20261116-132729.log`).
After the sync, the MODIFIED statement of `A missing reference repository can be requested without a person` was 568 characters; it was shortened to 483 in both the synced main spec and this change's delta, with its obligation unchanged.

`openspec validate --specs --strict` fails on the same 18 specs on `origin/main` `f3e1e337f` and on this chain's tree, `shared-reference-tree` and `shared-reference-tree-interface` among them before as well: `Moving per-account copies into the reference tree loses nothing and is reversible` (1001 characters) and eight interface statements over 500 characters predate this change. Three of those eight, `Acquisition is delegated…`, `The writer accepts only constrained requests` and `Migration moves only administrators' trees…`, grew here; the two ADDED interface requirements are 474 and 446 characters and the ADDED behavioral one 433 (`origin/main` in `ghq-lfs-verify-validate-20261116-132954.log`, the chain's tree in `ghq-lfs-verify-archived-20261116-133133.log`).
`openspec validate --archived` on the chain's tree reports this change valid with no issues; its 5 failures are other archived changes (`ghq-lfs-verify-archived-20261116-133133.log`).
`openspec validate --all` fails only on the active changes `stand-up-gitea-mq-on-magnetite` and `stand-up-nixbot-on-magnetite`, which this change does not touch (`ghq-lfs-verify-validate-20261116-132954.log`).

| Item | Type | Issues |
|---|---|---|
| `stand-up-gitea-mq-on-magnetite`, `stand-up-nixbot-on-magnetite` | change | pre-existing, not touched here |

---

## 2. Task Completion (`tasks.md`)

- [x] All `- [ ]` have been changed to `- [x]`

All eight items in `tasks.md` are ticked, each with the evidence of §8b.
`plan.md` is absent: this change had no separate micro-task plan, and `tasks.md`, whose eight items carry their verification commands, served as the plan. No plan was written after the work.

| Task | Reason incomplete | Blocks archive? |
|---|---|---|
| — | — | — |

---

## 3. Delta Spec Sync State

| Capability | Sync status | Notes |
|---|---|---|
| `shared-reference-tree` | synced | +1 `Every participating account reads a reference repository as committed`; ~1 `A missing reference repository can be requested without a person` |
| `shared-reference-tree-interface` | synced | +2 `The shared tree holds LFS pointer files, and the writer runs no LFS filter`, `Participating accounts' git runs no LFS filter beneath the shared root`; ~3 `Acquisition is delegated…`, `The writer accepts only constrained requests`, `Migration moves only administrators' trees…` |

`packages/docs/src/content/docs/development/traceability/satisfaction.md` was rebuilt wholesale from the synced corpus in the same chain: 302 requirements, 155 of 249 requirement-side rows discharged; no row outside the seven of this change changed (`ghq-lfs-sat-rebuild-20261116-132734.log`).

---

## 4. Design / Specs Coherence Spot Check

| Sampled item | design description | specs correspondence | Gap |
|---|---|---|---|
| D1 | four `filter.lfs.*` keys at command scope in the handler and the migration tool | interface `The shared tree holds LFS pointer files, and the writer runs no LFS filter` names the same keys and scope | none |
| D2 | one `gitdir:` include per root form, asserted per participant | interface `Participating accounts' git runs no LFS filter beneath the shared root` names both darwin forms and the evaluation failure | none |
| D3 | set back only content whose SHA-256 and size match the pointer, keep content and index, undo on rollback | MODIFIED migration requirement and its scenario `An administrator's tree holds smudged LFS content` | none |
| D4 | hydrate fetches one revision's missing objects, revision checked by the handler | MODIFIED `The writer accepts only constrained requests` (revision syntax, skip of an absent commit) and the hydrate scenarios | none |

**Drift warnings** (non-blocking):

- The designation `acquisition request` in `world-assumptions` still reads "added to, refreshed in, or deepened within"; the MODIFIED behavioral requirement adds making a reference repository readable at a revision (§8a).

---

## 5. Implementation Signal

- [x] No unstaged files in the worktree for this change's paths: every path was routed into the chain change `nolsknov` with `jj squash` and the working copy holds none of them
- [ ] All related commits have been pushed: not pushed; publishing is the orchestrator's step

**Commit range**: `9d614d92517f` (`main@origin` when the chain was created)..`nolsknov`.

---

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

- [x] No files: `ls docs/superpowers/specs/*.md` lists nothing

---

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

`plan.md` is absent, so there are no `[~]` rows. Three runtime observations are explicitly pending after deployment; none is claimed here:

| Pending observation | Nearest automated evidence | Coverage assessment | Real gap? |
|---|---|---|---|
| hydrate through the writer on a sharing host | VM hydrate subtest through the socket-activated writer; handler test hydrate cases | NixOS writer, socket, client, wrapper and fetch over an allowed and a disallowed protocol; not darwin's launchd writer, not a GitHub remote | yes until observed on stibnite and a NixOS host |
| the one-time repair of stibnite's ten migrated LFS repositories (4390 paths) | `logs/ghq-lfs-repair.sh` rehearsed read-only as crs58 (`ghq-lfs-repair-rehearsal-stibnite-20261116-131948.log`); VM migration case | selection of the paths only; no path was changed; the writer's checkout is exercised only in the VM | yes until the operator runs it with `--apply` |
| the darwin migration path (`restore_lfs_pointers` under launchd's `_ghq`) | VM migration case on NixOS; local helper rehearsal as one account | same code, NixOS only; darwin's `/private/var` root and `_ghq` not exercised | yes; stibnite was migrated before this change and is repaired by the script instead |

---

## 8. Designation Lint and Discharge Coherence

These are agent-executed checks; `openspec validate` checks structure only.

### 8a. Designation lint (behavioral delta `shared-reference-tree`)

Resolved against `openspec/specs/world-assumptions/spec.md`: `participating account`, `acquisition request`, `reference repository`, `reference tree`, `writer` (sense: reference tree), `history`, `host`.

| Unresolved noun | Requirement | Finding |
|---|---|---|
| `revision` | both requirements | belongs in the designation table as a world term (a recorded state of a repository's history) |
| `file` | `Every participating account reads a reference repository as committed` | belongs in the designation table |
| `content` | `Every participating account reads a reference repository as committed` | belongs in the designation table, or the requirement restated with `file` alone |
| `upstream` | `Every participating account reads a reference repository as committed` | used, not designated; `reference repository`'s own entry says "upstream project" |
| `acquisition request` (sense drift) | `A missing reference repository can be requested without a person` | the designation lists add, refresh and deepen only; it should gain "made readable at a revision" |

Follow-up: the next change that owns the designation table adds these rows; this change did not modify `world-assumptions`.

### 8b. Discharge coherence

| Requirement | Discharged by (S) | Under (W) | Status |
|---|---|---|---|
| interface `The shared tree holds LFS pointer files, and the writer runs no LFS filter` | handler package test: an update of a clone that requires git-lfs fast-forwards to the new pointer, a control clone without the policy fails, and with `LFS_POLICY` removed the test fails (local run); VM LFS subtest: pointer checkout and the same update through `ghq-sync -u`, failing on a throwaway commit that removes `LFS_POLICY` | — | discharged at package-test and VM interfaces (`ghq-lfs-build-pkgtests-20261116-131530.log`, `ghq-lfs-vmtest-pyrite-20261116-132449.log`, `ghq-lfs-vmtest-pyrite-negctl-20261116-132612.log`) |
| interface `Participating accounts' git runs no LFS filter beneath the shared root` | evaluated includes for crs58 on stibnite (both forms), cameron, omnigent-cameron and omnigent-janettesmith on pyrite and cameron on magnetite, with no failing assertion on the three hosts; mutations (cameron's includes emptied on pyrite, crs58 with the `/var` form only on stibnite) fail evaluation with the new message; the rendered stibnite `git/config` places both `includeIf` sections after `[filter "lfs"]`; VM readers with git-lfs configured at system scope report nothing and write nothing to `.git/lfs`, while a control re-enabling git-lfs as a required filter above the include fails with `permission denied` | — | discharged at evaluation and VM interfaces (`ghq-lfs-eval-stibnite-includes-20261116-130600.log`, `ghq-lfs-eval-stibnite-gitconfig-20261116-130613.log`, `ghq-lfs-eval-includes-20261116-130633.log`, `ghq-lfs-eval-mutations-20261116-130734.log`, `ghq-lfs-vmtest-pyrite-20261116-132449.log`); darwin by evaluation and a read-only check against stibnite's `bastani-inc/atomic`, where only the `/private/var/lib/ghq/` form matches |
| interface `Acquisition is delegated to the writer through a socket-activated entry point` (MODIFIED) | earlier evidence of CAM-77 for delegation; for `--hydrate`, the VM hydrate subtest (a reader cannot show `HEAD~2:f` before, can after, every entry still the writer's) and the wrapper test's delegation cases | — | discharged at package-test and VM interfaces; hydrate after deployment pending (§7) |
| interface `The writer accepts only constrained requests` (MODIFIED) | handler package test: eight hydrate refusal classes (range, option, reflog, tree path, empty, non-string, path outside the root, unknown field), hydrate over a disallowed protocol fails, an absent revision is skipped; VM: `ghq-writer-client hydrate HEAD..main` refused | — | discharged at package-test and VM interfaces |
| interface `Migration moves only administrators' trees in place…` (MODIFIED) | VM migration case: cameron's clone holds smudged LFS content; apply reports `set 1 LFS paths back`, the path equals its pointer, the writer's status omits it, every entry is the writer's, and rollback restores the tree byte for byte | — | discharged at the VM interface; darwin path pending (§7) |
| behavioral `A missing reference repository can be requested without a person` (MODIFIED) | `Acquisition is delegated…`; `The writer accepts only constrained requests` | — | discharged |
| behavioral `Every participating account reads a reference repository as committed` | `The shared tree holds LFS pointer files, and the writer runs no LFS filter`; `Participating accounts' git runs no LFS filter beneath the shared root` | — | discharged at the specification side; stibnite's ten migrated LFS repositories violate it until the repair of §7 runs |

No world assumption is named: git's configuration precedence (command scope over repository over global over system, and `includeIf gitdir:` matching the resolved directory) is relied on but not designated. It was observed in the VM and on stibnite, not stated as an assumption.

### 8c. Alphabet check

- The behavioral requirements name no machine artifact: no `ghq-sync`, no `filter.lfs`, no path. "a file the upstream stores outside the repository's history" stands for an LFS object without naming LFS.
- The interface requirements name only phenomena the machine observes: configuration keys, `gitdir:` conditions, request fields, working-tree files and evaluation failures. None references world state.

---

## Other evidence

- `prek run --files` on every changed path passed: `ghq-lfs-prek-20261116-131422.log` (code and guidance, after treefmt reformatted two Nix files in `…-131220.log`), `ghq-lfs-prek-wrapper-20261116-131529.log`, `ghq-lfs-prek-vmtest-20261116-132448.log`, `ghq-lfs-prek-openspec-20261116-132810.log`.
- Affected-repository census, read-only in the writer's environment: stibnite 10 repositories with changed LFS paths; magnetite and pyrite none (`ghq-lfs-census-*.log`, `ghq-lfs-census2-20261116-131632.log`).

---

## Overall Decision

- [ ] (pass) PASS — may proceed to finishing-a-development-branch and archive
- [x] (warn) PASS WITH WARNINGS — may proceed to subsequent steps but note: `plan.md` is absent and `tasks.md` carried the plan; §7's three runtime observations are pending after deployment; §8a's five designation findings await the designation table's owner; three already-long interface statements grew
- [ ] (fail) FAIL — return to the failed artifact, correct it, then re-run verify

**Next step**:

Publish the chain; after deployment, run `logs/ghq-lfs-repair.sh stibnite` and then with `--apply`, and observe `ghq-sync --hydrate` through the writer on stibnite and one NixOS host.
