# Retrospective: declare-host-user-relations-once

> Written: 2026-11-27 (after verify passed with warnings and the operator tasks 6.5 and 9.6 were recorded, before archive)
> Commit range: `68c045788` and `db0beed0d` (planning), then `302236090f91` on `main` (#4403, parented on `4b546df1f47f`); `6c362f02b` recorded 9.6 in `tasks.md`
> Worktree: merged to main (#4403); this retrospective and the archive are one further commit

---

## 0. Evidence

- **Commit range**: `68c045788` (Den-ready fleet plan), `db0beed0d` (design), `302236090f91` (the change, task evidence and verify, #4403), `6c362f02b` (task 9.6's record); 4 commits
- **Diff size**: `4b546df1f47f..302236090f91` +1104 / −891 across 61 files, artifacts included
- **Tasks done**: 48/48 (`grep -cE '^\s*- \[x\]' tasks.md`), operator tasks 6.5 and 9.6 included
- **Active hours**: about 2.5 h of recorded evidence, from the parent record (`logs/dhuro-1-parent-20261127T082123Z.txt`, 08:21 UTC) through the merged-head diff (`logs/drv-diff-4b546df1f47f-302236090f91-20261127T100040Z`, 1024.9 s) to the darwin builds on stibnite (`logs/dhuro-6-darwin-20261127-104432.log`)
- **Subagent dispatches**: the verify subagent (`verify.md`, Verifier line); the implementing agents are not recorded in the artifacts
- **New external dependencies**: none
- **Bugs encountered post-merge**: none; no toplevel changed, so no deploy was needed (task 9.5)
- **OpenSpec validate state at archive**: `openspec validate declare-host-user-relations-once --strict` valid (verify §1); the synced specs validated with `openspec validate --specs`
- **Test coverage signal**: seven attachment-constraint mutants (`logs/dhuro-3-mutants-20261127T090540Z.log`), the cinnabar attachment mutant (`dhuro-4-mutants-…`), the `extraSpecialArgs.flake` mutant (`dhuro-5-mutants-…`), the `reachUsers` mutant of `omnigent-worker-scope` (`dhuro-6-scope-…`); `just check-fast auto off x86_64-linux` exit 0 over every `checks.x86_64-linux` attribute (`logs/checks-linux-20261127-044502.log`); `just drv-diff 4b546df1f47f 302236090f91` PASS on the first judgement (6 NixOS and 4 darwin toplevels, 20 homes, 24 runtime tests identical; task 9.6)

Commit chain (chronological):

```
68c045788 docs(openspec): plan the den-ready fleet architecture changes
db0beed0d docs(openspec): design declare-host-user-relations-once and seam-secrets-away-from-clan-vars
302236090 refactor: declare each host's users once on the host record
6c362f02b docs(openspec): design compose-hosts-from-cohesive-aspects (carries task 9.6's record)
(this commit) docs(openspec): archive declare-host-user-relations-once
```

---

## 1. Wins

- Fifteen host-account attachments replaced four to seven hand-written copies per fact (clan user instances, host bodies, the secret bridge, darwin admin and uids, `checkedUsers`, requesters, participants) with every host and home derivation identical, shown twice by the drvPath diff (tasks 9.1, 9.6).
- The ambient `flake` argument is gone: one `homeFlake` per home, one `workerFlake` for worker homes, and an assertion with a mutant that fails if `extraSpecialArgs.flake` returns (task 5.5).
- Every derived value was compared with an isolated baseline projection, the working copy with this change's files restored to their parent, so other chains' uncommitted edits in the shared join could not pass for this change's effect (`logs/dhuro-9-projection-diff-20261127T091051Z.txt`).
- Each constrained attachment field fails at evaluation naming the host and account, with `tryEval` false (task 3.5).

## 2. Misses

- [med] [painful | evidence: session record; `logs/dhuro-9-projection-diff-20261127T091051Z.txt`] stibnite's crs58 home first showed a different `nviminit.lua` (main's LazyVim spec list held `LazyVim`, `snacks.nvim` and `blink.cmp` twice, the working copy once). Time went to looking for a module this change applied twice. The difference came from another chain's edits in the join: main's own `init.lua` already lists those entries twice from one definition, and against the isolated baseline stibnite's home and toplevel are identical.
- [med] [painful | evidence: design Risks "Known gap", A346] A wrong darwin `uid` in an attachment is detected by nothing. nix-darwin's activation warns, skips the account and succeeds. The source read for task 1.4 contradicted A346's first wording, which was corrected. The follow-up is the planned change fail-darwin-activation-on-uid-mismatch (CAM-139).
- [low] [nit | evidence: verify §4, design D9] The scenario "checkedUsers is generated from static data" says "cost no more"; that holds on CPU and wall time only. The thunk count rises by a deterministic 0.5% (x86_64-linux) and 1.0% (aarch64-darwin).
- [low] [nit | evidence: task 5.5] The literal `{ }` mutant for the `extraSpecialArgs.flake` assertion fails earlier, on a home module's `flake.inputs` read, before assertions are checked. Only the full-value mutant reaches the assertion.
- [med] [painful | evidence: A344 Evidence line, design D4] A344 was stated wrongly twice. Its first wording had the order reversed; the one verified and merged said, as a general rule, that a module's own list definitions merge after its imports', and cited the lock node named `nixpkgs` (`2074cc67`), which is another input's, not the root flake's nixpkgs (`bd5b7d01`) that hosts and homes evaluate with. Measured again at archive: `genericClosure` collects modules breadth-first (`lib/modules.nix:600-614` at `bd5b7d01`) and `:278` reverses that list, so a definition's place depends on its import depth; "own after imports" holds only between a module and its direct imports. A344, design D4 and its Risk line were corrected before the specs were synced; the comment at `modules/lib/host-users.nix:152` still states the old rule and is left to a code commit.

## 3. Plan deviations

| Plan task | What changed | Why |
|-----------|--------------|-----|
| 4.6 / D4 | The aspect's per-attachment assertion that `users.users.<a>` exists was dropped; the interface requirement "One home-manager integration aspect per class" was reworded after verify | It could not fail: home-manager's NixOS module defines `users.users.<name>` for every home, and the darwin aspect sets each attachment's uid. The mutant attaching christophersmith to cinnabar fails on NixOS's own user assertions instead |
| 4.4 / D1 | `extraImports` is `listOf raw`, not a `deferredModule` list | A `deferredModule` list re-keyed each module, so a module the person's aggregates also import applied twice and reordered pyrite's `home.packages` |
| 4.7 / A344 | stibnite's crs58 adds its three packages with `lib.mkAfter` | The inline host-body definition was a top-level module of the home and came last of 168 `home.packages` definitions. In `overrides`, one import level deeper, it came 101st, because modules are collected breadth-first and merged in reverse (A344 as corrected at archive); `mkAfter` puts it last again. The import position is not what keeps the drvPath |
| 4.9 / D9 | Generated `checkedUsers` accepted on CPU and wall time, the thunk increase taken on | Thunk and allocation counts are deterministic, so their increase is real; CPU and wall stayed within the parent's run-to-run spread |
| 1.4 / A346 | A346 reworded to warn-and-skip | nix-darwin's users activation warns and skips a uid mismatch (`modules/users/default.nix:285-288`, `:197-198`) |

## 4. Skill / workflow compliance

| Skill                                            | Used |
|--------------------------------------------------|------|
| superpowers:brainstorming                        | yes (`brainstorm.md`) |
| superpowers:writing-plans                        | yes (`plan.md`) |
| superpowers:using-git-worktrees                  | no |
| superpowers:subagent-driven-development          | not evidenced beyond the verify subagent |
| (transitive) superpowers:test-driven-development | yes in the mutant form: each guard shown failing (tasks 3.5, 4.6, 5.5, 6.4) |
| (transitive) superpowers:requesting-code-review  | no |
| superpowers:finishing-a-development-branch       | yes (#4403 merged) |

### Deliberately Skipped Skills

- **`superpowers:using-git-worktrees`**
  - **What was skipped**: the whole skill.
  - **Why this cycle**: the change landed as one commit on the shared jj development join, parented on `4b546df1f47f`.
  - **How to prevent recurrence**: `schema graph fix`. The previous Den-ready retrospectives gave the same answer; see §6.
- **`superpowers:requesting-code-review`**
  - **What was skipped**: a review separate from verification.
  - **Why this cycle**: on 2026-11-27 the operator waived the code and documentation review sub-gates of In Review and approved archiving on the verify record and the operator tasks 6.5 and 9.6.
  - **How to prevent recurrence**: `scope-judgment rule`: record the waiver in the change's attempt log at the gate, as done here.

## 5. Surprises

- A difference in a home's derivation, seen in the shared working copy, can belong to another chain's uncommitted edit. Only a baseline that restores this change's files to their parent isolates it (§2).
- nix-darwin does not fail activation on a uid mismatch; it warns and leaves the account unmanaged (A346).
- An assertion that a generated attachment's account exists cannot fail, because the same generation defines the account (task 4.6).
- Moving an inline host-body home definition into an imported module moves it one import level deeper, and that alone changes its place in every list it defines: modules are collected breadth-first and merged in reverse, so deeper definitions come first whatever their ancestry (A344 as corrected at archive).
- Thunk and allocation counts from `just eval-cost` have no run-to-run spread, so any increase in them is real. A spread-based acceptance only applies to CPU and wall time (D9).

## 6. Promote candidates → long-term learning

- [ ] [med] **In a shared jj join, compare against a baseline that restores only this change's files to their parent, never against the join or main.**
  → **Promote to** memory
  > **Why**: stibnite's `nviminit.lua` difference was investigated as this change's double import, but it came from another chain's edits in the join.
  > **How to apply**: any drvPath or projection comparison taken from a working copy other sessions also edit.
- [ ] [med] **An assertion over a value the same code generates is not a check; prove it can fail with a mutant before adding it.**
  → **Promote to** memory
  > **Why**: the `users.users.<a>` existence assertion was planned, then dropped because no mutant could make it fail (task 4.6).
  > **How to apply**: designing an evaluation-time assertion in a generator aspect.
- [ ] [med] **A definition's place in a merged list depends on its import depth; pin list order that reaches a derivation with an order priority, not with import position.**
  → **Promote to** memory
  > **Why**: stibnite's `home.packages` reordered (101st of 168) until `lib.mkAfter` restored it; the rule "own definitions after imports" was stated as general twice and was false across depths (A344, task 4.7).
  > **How to apply**: refactoring host-body definitions into aspects where a list option reaches a derivation; cite nixpkgs from the root flake's input (`jq '.nodes[.nodes.root.inputs.nixpkgs]' flake.lock`), not the lock node named `nixpkgs`.
- [ ] [low] **Accept evaluation-cost changes on CPU and wall time against a spread, and state deterministic thunk and allocation increases as costs taken on.**
  → **Promote to** one-off
  > **Why**: D9's "within the spread" criterion does not apply to counts with no spread.
- [ ] [med] **Shared-join changes skip `using-git-worktrees` every cycle.** (carried from type-the-fleet-host-registry)
  → **Promote to** schema
  > **Why**: four consecutive Den-ready changes recorded the same skip and the same prevention answer.
  > **How to apply**: the apply phase of `superpowers-bridge-wrspm` should accept a jj development-join chain as the isolation step.

---

## Open items that outlive the change

| Item | Where it goes |
|------|---------------|
| A wrong darwin `uid` in an attachment is not detected; nix-darwin warns and skips the account (A346) | fail-darwin-activation-on-uid-mismatch (CAM-139) |
| Scenario "A person is given an account on a new host" has no witness (no attachment added) | the first change that adds an attachment |
| Scenario "A recorded uid differs from the account on disk" has no witness (verify §8.0) | fail-darwin-activation-on-uid-mismatch (CAM-139) |
