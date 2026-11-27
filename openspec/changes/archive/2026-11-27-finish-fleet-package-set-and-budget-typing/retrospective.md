# Retrospective: finish-fleet-package-set-and-budget-typing

> Written: 2026-11-27 (after verify passed with warnings, before archive)
> Commit range: `209d6a2ea` (planning, the split from register-fleet-obligations), then `330c77fa7` on `main`, parented on `ec2c878bf`
> Worktree: merged to main (#4401, 09:33 UTC); this retrospective and the archive are one further commit

---

## 0. Evidence

- **Commit range**: `209d6a2ea` (the split of the blocked tasks out of register-fleet-obligations, with this change's artifacts); `330c77fa7` (the two runtime tests on `fleetPkgs`, the typed `envelopeBudget`, the registry assert's message, #4401); 2 commits
- **Diff size**: `330c77fa7` +211 / −41 across 10 files, of which 4 are code (+26 / −14: `modules/checks/machines.nix`, `modules/clan/services/otel-collector/flake-module.nix`, `modules/vm-tests/perses-greptimedb.nix`, `modules/vm-tests/shared-reference-tree.nix`) and 6 are this change's artifacts
- **Tasks done**: 9/9 (`tasks.md`)
- **Active hours**: about 0.5 h of recorded evidence, from task 1.1 (09:00 UTC, the first checked box in the Linear attempt log) to the oracle run (`logs/drv-diff-c21a2dc87701-ccf786c25f99-20261127T090914Z`, 963.6 s) and the merge at 09:33 UTC; planning at 08:16 UTC is not counted
- **Subagent dispatches**: one recorded, the verify subagent (`verify.md`, Verifier line)
- **New external dependencies**: none
- **Bugs encountered post-merge**: none
- **OpenSpec validate state at archive**: `openspec validate finish-fleet-package-set-and-budget-typing --strict` valid (verify §1); the synced specs validated with `openspec validate --specs`
- **Test coverage signal**: per-attribute drvPath comparisons (`logs/ffp-{base,head}-drvpaths-*.json`, `logs/ffp-{base,head}-hosts-20261127T0902Z.json`, `logs/ffp-assertmsg-drvpaths-20261127T0906Z.log`); three mutants (`logs/ffp-mutants-20261127T0904Z.log`: `storeURL`, the removed `electrum` record twice, the uncovered `ffpmutant` database); `just drv-diff c21a2dc87701 ccf786c25f99` PASS on the first judgement (nixos 6, darwin 4, home 20, vmTests 21 + 3 identical; five checks changed, all on the base allow-list)

Commit chain (chronological):

```
209d6a2ea docs(openspec): split the blocked tasks out of register-fleet-obligations and record the secrets-seam decisions
330c77fa7 refactor(vm-tests): move the last two runtime tests to the fleet package set and type the envelope budget
(this commit) docs(openspec): archive finish-fleet-package-set-and-budget-typing
```

---

## 1. Wins

- No runtime test under `modules/vm-tests` instantiates nixpkgs for its nodes any more; the two moved tests and their mutations keep their drvPaths (tasks 2.1, 2.2).
- `envelopeBudget` rejects a field it does not have at the option, with nixpkgs' "Did you mean `storeUrl`" hint, and both writers keep their derivations (tasks 3.1, 3.2).
- The host-registry mutant found a real gap: removing a host failed evaluation without naming it. A five-line change to the assert's message closed it without moving any check's drvPath (task 4.1).
- The oracle passed on its first judgement with an empty `drv-delta.txt`, as D4 predicted (task 5.1).
- Splitting the held work out let register-fleet-obligations archive with every requirement it kept met on `main` (`209d6a2ea`).

## 2. Misses

- [med] [painful | evidence: task 4.1 first run] The registry scenario "A host disappears from the registry" had been stated as discharged-in-principle while evaluation actually failed at `modules/checks/machines.nix:78-80` with a message that named no host. A spec scenario stated but never run gave false comfort until a mutant ran it.
- [low] [nit | evidence: verify §4 first warning] The trust-boundary comment of "Runtime tests evaluate against the fleet package set" read wider than the requirement: seven runtime tests set no node package set. Narrowed before sync to name the five `pkgs.testers.runNixOSTest` tests and the two `tincr` tests.
- [low] [nit | evidence: verify §4 second warning] The working copy's `shared-reference-tree.nix` carried two other changes' edits beside this change's hunk, so the change was evaluated in an isolated `/tmp/ffp/head` tree built from `git archive` plus only its hunks (task 1.2 method).

## 3. Plan deviations

| Plan task | What changed | Why |
|-----------|--------------|-----|
| 4.1 | Code changed: the assert's message in `modules/checks/machines.nix` now lists the names on only one side (design D3 amendment); the mutant ran twice | The first run failed without naming the host |
| 4.2 | The failing line names the dump unit as missing from the host's `notifiedUnits`, not from the backup set | The backup module puts every `ensureDatabases` entry into the backup set, so the uncovered part is the notified units, which the scenario's WHEN also names |
| 1.2–3.1 head side | Evaluated in `/tmp/ffp/head` rather than the working copy | The working copy held another session's unlanded edits |
| 5.1 | The oracle ran on `c21a2dc87701 -> ccf786c25f99`; the commit was then rebased onto `ec2c878bf4bc` | `main` moved by OpenSpec text files only; `jj interdiff` against the post-rebase commit is empty (verify preamble) |

## 4. Skill / workflow compliance

| Skill                                            | Used |
|--------------------------------------------------|------|
| superpowers:brainstorming                        | yes (`brainstorm.md`, recorded as a decision chain without an interactive session) |
| superpowers:writing-plans                        | yes (`plan.md`) |
| superpowers:using-git-worktrees                  | no |
| superpowers:subagent-driven-development          | not evidenced beyond the verify subagent |
| (transitive) superpowers:test-driven-development | yes in the mutant form: each guard shown failing (tasks 3.2, 4.1, 4.2) |
| (transitive) superpowers:requesting-code-review  | no |
| superpowers:finishing-a-development-branch       | yes (#4401 merged) |

### Deliberately Skipped Skills

- **`superpowers:using-git-worktrees`**
  - **What was skipped**: the whole skill; the isolated evaluation tree under `/tmp/ffp` served evaluation, not development.
  - **Why this cycle**: the change landed as one commit on the shared jj development join, parented on `ec2c878bf`.
  - **How to prevent recurrence**: `schema graph fix`, the same answer as the four previous Den-ready changes; carried in §6.
- **`superpowers:requesting-code-review`**
  - **What was skipped**: a review separate from verification.
  - **Why this cycle**: on 2026-11-27 the operator waived the code and documentation review sub-gates and approved archiving on the verify record.
  - **How to prevent recurrence**: `scope-judgment rule`: record the waiver at the gate, as done here.

## 5. Surprises

- Evaluation never reaches the `structure-fleet` pin when a host record is removed: the inventory assert in `machines.nix` guards the whole per-system `checks` set and fires first (task 4.1).
- With that assert removed, evaluation still fails before the pin, on `attribute 'electrum' missing` (task 4.1 diagnostic), so the pin is not the guard the scenario assumed.
- Seven runtime tests set no node package set at all, which the requirement's wording ("that sets its nodes' package set") already excluded but its trust boundary did not (verify §4).

## 6. Promote candidates → long-term learning

- [ ] [med] **Run a mutant for every failure scenario a spec states before treating it as discharged.**
  → **Promote to** skill (openspec-verify-change)
  > **Why**: "A host disappears from the registry" was stated and believed, but the first mutant showed evaluation failing elsewhere with a message that named no host (task 4.1).
  > **How to apply**: at verify, any scenario whose THEN names an error message is covered only by a recorded run that shows that message.

- [ ] [med] **Shared-join changes skip `using-git-worktrees` every cycle.**
  → **Promote to** schema
  > **Why**: the fifth consecutive Den-ready change gives the same §4 answer; an isolated `/tmp` evaluation tree is what the cycle actually needs.
  > **How to apply**: make the schema's apply phase accept "isolated evaluation tree on a shared join" as satisfying the worktree step.

- [ ] [low] **A trust-boundary comment must name the population the requirement's wording excludes.**
  → **Promote to** one-off
  > **Why**: the requirement was scoped correctly but its comment claimed every runtime test; verify caught it only by reading every test module.
