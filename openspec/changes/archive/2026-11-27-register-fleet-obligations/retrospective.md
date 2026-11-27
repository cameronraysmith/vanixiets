# Retrospective: register-fleet-obligations

> Written: 2026-11-27 (after verify passed with warnings and the blocked tasks moved to finish-fleet-package-set-and-budget-typing, before archive)
> Commit range: `68c045788` (planning, shared with the other Den-ready fleet changes), then `db0beed0db3c..0254e8746` on `main`
> Worktree: merged to main (#4389, #4390); this retrospective and the archive are one further commit

---

## 0. Evidence

- **Commit range**: `68c045788` (this change's artifacts among the planned Den-ready fleet changes); `dfcee2e1c` (the registry, the judge-check constructor, the system-condition cleanup, the package-set move, the `patched` removal and the row validator, #4389, parented on `db0beed0db3c`); `0254e8746` (task 3.5, `host-key-obligations` through `mkJudgeCheck`, #4390); 3 commits
- **Diff size**: `dfcee2e1c` +1037 / −737 across 73 files, artifacts and docs pages included; `0254e8746` +19 / −9 across 3 files
- **Tasks done**: 22/22 (`tasks.md`); tasks 4.4, 6.1 and 6.2 moved to finish-fleet-package-set-and-budget-typing, task 7.2 dropped
- **Active hours**: about 1 h of recorded evidence, from the base drvPaths (`logs/rfo-base-drvpaths-20261127-070742.json`, 07:07 UTC) to the second oracle run (`logs/drv-diff-dfcee2e1cc6e-007995cd6f0a-20261127T075127Z`, 898.6 s), with #4390 merged at 08:13 UTC; planning on 2026-11-26 is not counted
- **Subagent dispatches**: one recorded, the verify subagent (`verify.md`, Verifier line); the others are not recorded in the artifacts
- **New external dependencies**: none
- **Bugs encountered post-merge**: none
- **OpenSpec validate state at archive**: `openspec validate register-fleet-obligations --strict` valid (verify §1); the synced specs validated with `openspec validate --specs`
- **Test coverage signal**: registry mutants A–D (`logs/rfo-mutants-20261127-070848.log`), the wrong-count mutants of tasks 3.3 and 6.3 (same log) and 3.5 (`logs/rfo-mutants-host-key-20261127T075034Z.log`); `just drv-diff db0beed0db3c f3f2849bebd0` PASS on the first judgement (942.4 s; nixos 6, darwin 4, home 20, vmTests 24 identical; 33 checks changed, all declared or base allow-listed) and `just drv-diff dfcee2e1cc6e 007995cd6f0a` PASS on the first judgement (898.6 s); three `just eval-cost` points (tasks 2.5, 4.5)

Commit chain (chronological):

```
68c045788 docs(openspec): plan the den-ready fleet architecture changes
dfcee2e1c refactor(checks): register host obligation judges
0254e8746 refactor(checks): run host-key-obligations through mkJudgeCheck
(this commit) docs(openspec): archive register-fleet-obligations
```

---

## 1. Wins

- Twelve judges wired by hand in `machines.nix` (eleven bindings, `withNetworkTargets`, one conjunction, one long message) became one registry folded per class, with every machine check's drvPath unchanged (task 2.3, oracle 7.1).
- Both oracle runs passed on the first judgement. `drv-delta.txt` declared the 28 docs-site checks before the run, which the previous change under-declared by 29 (§0; type-the-fleet-host-registry retrospective §2).
- The mutants show each guard failing with the message the spec names: A names only `harmoniaGcObligations`, B shows a darwin-only judge is never called on NixOS, C names the missing key, D adds a judge with one new module and one key-list line (task 2.4).
- Moving `devin-worker-structural` to one `fleetPkgs` per system cut its GC bytes by 39% and its thunks by 28% with an unchanged drvPath (task 4.5).

## 2. Misses

- [med] [painful | evidence: task 3.5, `0254e8746`] stop-reading-other-hosts-configs added `host-key-obligations` with the old hand-copied shape after this change was planned. The first verify pass caught it; it cost a second commit, a second PR and a second 898.6 s oracle run.
- [med] [painful | evidence: verify update note, tasks 4.4, 6.1, 6.2, 7.2] Three tasks waited on files another session held (`vm-tests/{shared-reference-tree,perses-greptimedb}.nix`, `clan/services/otel-collector/**`), so the change could not archive as planned. They moved with their requirements to finish-fleet-package-set-and-budget-typing, and the MODIFIED `database-backup-interface` delta and task 7.2 were dropped.
- [low] [nit | evidence: verify W1] The discharge clause of "The channels overlay offers no patched channel" expects `rg '\bpatched\b'` over the docs to return only the amendment. It also returns ADR-0017's Decision text, which D6 leaves as written, and English uses of the word. The requirement holds; the clause was synced as written.
- [low] [nit | evidence: verify W3, task 2.5] The registry's evaluation cost (+7,296 thunks, deterministic) is measured on `nixos-magnetite` only and is not split between the `functionTo` check and the fold.

## 3. Plan deviations

| Plan task | What changed | Why |
|-----------|--------------|-----|
| 3.5 | Added after the first verify pass; landed as its own commit and PR (#4390) with its own `drv-delta-host-key-check.txt` | A sibling change added a twelfth count-judged fixture check after planning |
| 4.4, 6.1, 6.2 | Moved to finish-fleet-package-set-and-budget-typing (its tasks 2.1, 2.2, 3.1, 3.2) with their requirements | The files they edit were held by another session |
| 7.2 | Dropped with the MODIFIED `database-backup-interface` delta | back-up-postgresql-off-host now names `fleetObligations.postgresqlBackupObligations` itself |
| 7.3 | Discharged by the operator keeping the corrected D15 sentence | The owner of delegate-fleet-deploys is the operator |
| Global Constraints, "one commit" | Two commits, two PRs | Task 3.5 above |

## 4. Skill / workflow compliance

| Skill                                            | Used |
|--------------------------------------------------|------|
| superpowers:brainstorming                        | yes (`brainstorm.md`, recorded as a decision chain without an interactive session) |
| superpowers:writing-plans                        | yes (`plan.md`) |
| superpowers:using-git-worktrees                  | no |
| superpowers:subagent-driven-development          | not evidenced beyond the verify subagent |
| (transitive) superpowers:test-driven-development | yes in the mutant form: each guard shown failing (tasks 2.4, 3.3, 3.5, 6.3) |
| (transitive) superpowers:requesting-code-review  | no |
| superpowers:finishing-a-development-branch       | yes (#4389, #4390 merged) |

### Deliberately Skipped Skills

- **`superpowers:using-git-worktrees`**
  - **What was skipped**: the whole skill.
  - **Why this cycle**: the change landed as commits on the shared jj development join, parented on `db0beed0db3c`.
  - **How to prevent recurrence**: `schema graph fix`, the same answer as the three previous Den-ready changes; carried in §6.
- **`superpowers:requesting-code-review`**
  - **What was skipped**: a review separate from verification.
  - **Why this cycle**: on 2026-11-27 the operator waived the code and documentation review sub-gates and approved archiving on the verify record.
  - **How to prevent recurrence**: `scope-judgment rule`: record the waiver at the gate, as done here.

## 5. Surprises

- A sibling change landed a new instance of the pattern this change removes between planning and verify (task 3.5).
- The registry fold's cost is deterministic: +7,296 thunks on `nixos-magnetite` in identical runs, so it is a real cost rather than noise, though CPU shows no rise (task 2.5).
- Sharing one nixpkgs instance per system saved far more on `devin-worker-structural` (−39% GC bytes) than on `greptimedb-pipeline` (−4.4%), because `probePkgs` built a new instance per home (task 4.5).

## 6. Promote candidates → long-term learning

- [ ] [med] **Predict a refactor's changed checks from what each check imports, renders or takes as source, not from what it tests.**
  → **Promote to** memory
  > **Why**: carried from type-the-fleet-host-registry. This cycle applied it and both oracle runs passed on the first judgement with the 28 docs-site checks declared in advance.
  > **How to apply**: writing `drv-delta.txt` for a change that edits `packages/docs`, `fleet.json`, `testSizes`, or a file some test imports with `${./file}`.
- [ ] [med] **Shared-join changes skip `using-git-worktrees` every cycle.**
  → **Promote to** schema
  > **Why**: four consecutive Den-ready changes recorded the same skip and the same prevention answer.
  > **How to apply**: the apply phase of `superpowers-bridge-wrspm` should accept a jj development-join chain as the isolation step.
- [ ] [med] **Before verify, re-search `main` for new instances of the pattern a change removes.**
  → **Promote to** skill (openspec-verify-change)
  > **Why**: `host-key-obligations` arrived from a sibling change after planning and needed a second commit and oracle run (task 3.5).
  > **How to apply**: a refactor change whose requirement says "every X" on a join where sibling changes land; rerun the plan's enumeration search at the parent commit before the oracle.
- [ ] [low] **A discharge clause that greps prose should name the matches it expects.**
  → **Promote to** one-off
  > **Why**: verify W1; whether it recurs depends on requirements that grep documentation, rare here.

---

## Open items that outlive the change

| Item | Where it goes |
|------|---------------|
| Tasks 4.4, 6.1, 6.2, their requirements, and the mutant for "a database is added without a backup" (verify W2) | finish-fleet-package-set-and-budget-typing (CAM-137) |
| The registry's cost on the other machine checks (verify W3) | a later change touching `checks/machines.nix` |
| The discharge clause's exceptions for `patched` (verify W1) | a later change touching `fleet-package-set-interface` |
