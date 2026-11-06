# Retrospective: deliver-omp-browser-relay

> Written: 2026-11-05 (after verify passed with warnings and the person answered Q1 and Q2)
> Commit range: `4d893e705..00aeab3f0662`, plus the archive commit
> Worktree: merged to main (implementation PR #3729); archive written in `vanixiets-worktrees/omnigent-0-21`

---

## 0. Evidence

- **Commit range**: `4d893e705..00aeab3f0662` (2 commits on `main`): the implementation `b325407984e6` (PR #3729, merged 2026-11-05T23:02:41Z) and the verification `00aeab3f0662`; the archive commit follows
- **Diff size**: +1013 / -0 lines across 12 files in `b325407984e6`; +267 / -5 across 3 files in `00aeab3f0662`
- **Tasks done**: 12/13 (`grep -cE '^\s*- \[x\]' tasks.md` → 12); 5.4 is undischarged at archive and carried by CAM-80; 5.2 and 6.1 were rescoped to the Helium profile `sciexp` by the person's decision Q1 (verify.md, Addendum)
- **Active hours**: one day of wall clock, 2026-11-05: proposal at 22:48 UTC (proposal.md `attempt_log`), merge at 23:02 UTC, stibnite activation at 23:26 UTC, verify at 23:43 UTC
- **Subagent dispatches**: at least one recorded: `RelayVerifyRecord`, which wrote verify.md (verify.md header); others not recorded
- **New external dependencies**: none; the package is built by the omp the fleet already deploys from `inputs.llm-agents` (no fetched zip, no second hash)
- **Bugs encountered post-merge**: none
- **OpenSpec validate state at archive**: this change valid; `openspec validate --all` fails on two unrelated changes (`stand-up-gitea-mq-on-magnetite`, `stand-up-nixbot-on-magnetite`), verify.md §1
- **Test coverage signal**: `checks.{aarch64-darwin,x86_64-linux}.package-omp-browser-relay-extension`, `darwin-stibnite`, `home-manager-crs58` in nixbot build 2104; the stamp-mismatch mutant (task 1.2) and the symlinked-folder activation refusal (verify.md §9.1)

Commit chain (chronological):

```
4d893e705 Merge 22cc5283 into gitea-mq/batch/255
b325407984e6 feat(omp): deliver the browser relay extension declaratively
00aeab3f0662 openspec: verify deliver-omp-browser-relay on stibnite
<archive> openspec: archive deliver-omp-browser-relay
```

---

## 1. Wins

- [evidence: verify.md §9.1] The package is byte-identical to upstream's v18.16.0 `omp-browser-relay-extension.zip` (`diff -r` empty) and reproducible under `nix build --rebuild`, with no fetched source beyond omp itself.
- [evidence: verify.md §9.3] The extension ID Helium recorded in `sciexp`, `oijoeegnoohbebikmcjkffchcokmdndn`, equals the one predicted from the sha256 of the fixed folder path, which is the observation A67 rests on.
- [evidence: verify.md §9.3] The per-request opt-in held both ways on first use: `app.relay: true` drove a Helium tab through a Kanidm sign-in filled from Bitwarden, and a call without it opened on omp's headless browser.
- [evidence: tasks.md 1.2, verify.md §9.1] Both negative controls failed as designed: the `0.0.0` stamp mutant and the symlinked-folder activation.

## 2. Misses

- [med]  [painful  | evidence: verify.md §2, §9.4 Q1] Tasks 5.2 and 6.1 were written for "each Helium profile" although the person loads the relay only where they accept omp's control; the acceptance had to be rescoped after verification.
- [med]  [painful  | evidence: world-assumptions delta, verify.md Addendum] The change numbered its assumptions A61–A63 while the active `stand-up-darwin-collection` already used A61–A66; the collision surfaced only at archive and cost a renumbering to A67–A69.
- [low]  [nit      | evidence: verify.md §9.3] The badge reading "on" was not recorded at the load; it rests on the person's later report.
- [low]  [nit      | evidence: tasks.md 5.4] Task 5.4 depends on an external event, the next `llm-agents` omp bump, so the change could not discharge BRD `The loaded relay extension follows the agent release without being reloaded by hand` before archive.

## 3. Plan deviations

| Plan task | What changed | Why |
|-----------|--------------|-----|
| Task 5 Step 3 / tasks 5.2, 6.1 | load in `sciexp` only, instead of each Helium profile | person's decision Q1: loading the relay hands omp control of that profile |
| Task 5 Step 5 / task 5.4 | left undischarged at archive, carried by CAM-80 | person's decision Q2: archive without waiting for the next omp bump |
| world assumptions | A61–A63 renumbered A67–A69 | `stand-up-darwin-collection` holds A61–A66; this change archives first |

## 4. Skill / workflow compliance

| Skill                                            | Used |
|--------------------------------------------------|------|
| superpowers:brainstorming                        | yes (brainstorm.md) |
| superpowers:writing-plans                        | no   |
| superpowers:using-git-worktrees                  | not recorded |
| superpowers:subagent-driven-development          | not recorded |
| (transitive) superpowers:test-driven-development | partly: the stamp mutant and the symlink refusal were run as must-fail controls |
| (transitive) superpowers:requesting-code-review  | not recorded |
| superpowers:finishing-a-development-branch       | yes (PR #3729 merged through the queue) |

### Deliberately Skipped Skills

- **`superpowers:writing-plans`**
  - **What was skipped**: the interactive planning session; plan.md was written by the delegated authoring session following the skill's structure (plan.md header comment).
  - **Why this cycle**: the change was proposed, planned and implemented in one delegated session on 2026-11-05, with no interactive plan step between tasks.md and implementation.
  - **How to prevent recurrence**: `scope-judgment rule` — a delegated authoring session that writes plan.md should say so in the plan header, as this one did, and the orchestrator decides whether an interactive pass is owed before implementation.
- **`using-git-worktrees`, `subagent-driven-development`, `requesting-code-review`**: the artifacts this retrospective was written from (git history, tasks.md, plan.md, verify.md) do not record whether these ran, so they are marked not recorded rather than yes or no.

## 5. Surprises

- Assumption numbers are allocated per change, not reserved against other active changes, so two concurrent changes can claim the same numbers without either failing validation.
- Bitwarden's inline autofill frame detached omp from the relay tab, and omp reattached without reload (verify.md §9.3).

## 6. Promote candidates → long-term learning

- [ ] [med] **Allocate new world-assumption numbers above every active change's, not only above main's** → **Promote to schema** (specs or archive guidance)
  > **Why**: this change and `stand-up-darwin-collection` both claimed A61–A63, found only at archive.
  > **How to apply**: when a delta adds a world assumption, scan `openspec/changes/*/specs/world-assumptions/spec.md` for the highest number in use.
- [ ] [low] **Scope per-profile acceptance to the profiles the person chooses to expose to an agent** → **One-off**
  > **Why**: loading the relay hands omp control of a profile, so "each profile" was never the intended scope.
  > **How to apply**: any task whose acceptance spans a person's browser profiles.
