# Retrospective: stop-reading-other-hosts-configs

> Written: 2026-11-27 (after verify passed with warnings, before archive)
> Commit range: `68c045788` (planning, shared with the other Den-ready fleet changes), then `733425962` on `main`
> Worktree: merged to main (#4380); this retrospective and the archive are one further commit

---

## What the change set out to do

Every host imported `modules/system/ssh-known-hosts.nix`, which read each NixOS host's openssh public key from `flake.nixosConfigurations.<host>.config.clan.core.vars`, and stibnite read magnetite's session key the same way, so evaluating one host evaluated part of five or six others.
The change was to read host keys and public vars from the committed files through one accessor (`flake.lib.vars`) and one key map (`flake.lib.hostKeys`), keep each NixOS host's generated key equal to its pinned entry by an assertion, take magnetite's databases in the vm-tests from flake data, and prove with `just drv-diff` that no host, home or vm-test derivation changed (proposal, design D1–D8).

---

## 0. Evidence

- **Commit range**: `68c045788` (this change's artifacts among seven planned changes), `733425962` (the refactor, task evidence and verify, #4380); 2 commits
- **Diff size**: `733425962` +713 / −252 across 39 files, artifacts included; the planned artifacts +927 across 11 files in `68c045788` (with the registry entry in `openspec/linear.yaml`)
- **Tasks done**: 24/24 (`tasks.md`)
- **Active hours**: about 0.6 h of recorded task evidence, from the first log (`logs/srohc-1-parent-20261126-222318.txt`, 03:23 UTC) to verify (04:00 UTC), including the 909.4 s drv-diff run
- **Subagent dispatches**: n/a; the artifacts record none
- **New external dependencies**: none
- **Bugs encountered post-merge**: none
- **OpenSpec validate state at archive**: `openspec validate stop-reading-other-hosts-configs --strict` valid before the move; the synced specs validated with `openspec validate --specs --strict`
- **Test coverage signal**: `checks.x86_64-linux.host-key-obligations` with five fixture cases and a mutant that empties its failure list (task 4.2); a cinnabar key mutant failing its toplevel (task 4.4); seven vm-test mutants each failing with its file's message (task 6.2); `just drv-diff 390f72f0c809 bbb7c5ccc978` PASS after declaring `eval-users-lib` (task 7.1); stibnite's toplevel 3,688,926 fewer thunks (15.1 %) in alternating runs (task 7.2); after verify, the whole-stack run `14a6b01878c3..8afba9a755b7` PASS

Commit chain (chronological):

```
68c045788 docs(openspec): plan the den-ready fleet architecture changes
733425962 refactor(lib): read host keys and public vars from committed files
(this commit) docs(openspec): archive establish-refactor-oracle and stop-reading-other-hosts-configs
```

## 1. Wins

- Every host toplevel, home and vm-test derivation stayed identical, shown over the whole fleet by the oracle rather than per host (task 7.1).
- The evaluation saving was measured, not inferred: stibnite's toplevel took 3.69M fewer thunks, 421 MB less allocation and 0.87 to 0.92 s less CPU in both alternating rounds, within A323's bound (verify §8.1).
- Each guard was shown failing: the key-obligation judge on a mutant, a forced cinnabar key, a reverted stibnite read found by the source search, and each vm-test's databases assertion (tasks 4.2, 4.4, 5.4, 6.2).
- `known_hosts` entries and stibnite's session key are byte-identical, trailing whitespace included, because `hostKeys` reads the committed files untrimmed as clan does (A320, task 4.1).

## 2. Misses

- [med] [painful | evidence: design D8, task 7.1] The design predicted two changed checks; the oracle found a third, `eval-users-lib`, which imports `home/users/lib.nix` by store path. The first judgement failed until it was declared.
- [med] [painful | evidence: verify W2] D5 said each reader keeps its path-or-string kind, but its own table moved six sites from string to path; the requirement was reworded to "keeps its result value and read function", with A322 carrying the identity.
- [low] [nit | evidence: verify W1] The acceptance runs were taken before the rebase onto the oracle's final commit; the interdiff touched no module, and the whole-stack run after verify covers it.
- [low] [nit | evidence: verify W4] The source-search scenario first covered docs under `modules/home`; it was narrowed to `.nix` files.

## 3. Plan deviations

| Plan task | What changed | Why |
|-----------|--------------|-----|
| 7.1 / `drv-delta.txt` | `checks.x86_64-linux.eval-users-lib changed` declared; the seven vm-tests' `may-change` entries removed | The run showed the first and found the seven identical |
| 4.2 | `host-key-obligations` sized `medium` with `measured = false`, not `small` | The repository's form for a check no nixbot run has measured |
| D5 | Reader invariant restated as result value and read function | Six sites move from string to path with unchanged results (W2) |
| 1.1 | Both open questions answered "no" by the operator | Omnigraph graphs stay read from magnetite's settings; failing a host missing from `hostKeys` belongs to type-the-fleet-host-registry |

## 4. Skill / workflow compliance

| Skill                                            | Used |
|--------------------------------------------------|------|
| superpowers:brainstorming                        | yes (`brainstorm.md`) |
| superpowers:writing-plans                        | yes (`plan.md`) |
| superpowers:using-git-worktrees                  | no |
| superpowers:subagent-driven-development          | not evidenced |
| (transitive) superpowers:test-driven-development | yes in the mutant form: every guard was shown failing on a mutant (tasks 4.2, 4.4, 5.4, 6.2) |
| (transitive) superpowers:requesting-code-review  | no |
| superpowers:finishing-a-development-branch       | yes (#4380 merged) |

### Deliberately Skipped Skills

- **`superpowers:using-git-worktrees`**
  - **What was skipped**: the whole skill.
  - **Why this cycle**: the change landed as a chain on the shared jj development join, stacked on establish-refactor-oracle (#4380 after #4377 and #4379).
  - **How to prevent recurrence**: `schema graph fix` — the same answer and promote candidate as establish-refactor-oracle's retrospective.
- **`superpowers:requesting-code-review`**
  - **What was skipped**: a review separate from verification.
  - **Why this cycle**: on 2026-11-27 the operator waived the code and documentation review sub-gates of In Review and approved archiving on the verify record.
  - **How to prevent recurrence**: `scope-judgment rule` — record the waiver in the change's attempt log at the gate, as done here.

## 5. Surprises

- A check that imports a module file by store path (`lib.test.nix:26` importing `${./lib.nix}`) changes with any edit to that file even when every value it tests is unchanged (design D8).
- Moving a reader from `"${self}/…"` to a path changed no drvPath, because these readers consume the file during evaluation and never put its path into a derivation (A322, now observed).
- clan's `.value` keeps the committed file's trailing whitespace; magnetite's key ends in `" \n"` (task 4.1).

## 6. Promote candidates → long-term learning

- [ ] [med] **Predict a refactor's changed checks from what each check imports by store path, not only from what it evaluates.**
  → **Promote to** memory
  > **Why**: `eval-users-lib` changed although no value it tests did (D8).
  > **How to apply**: writing `drv-delta.txt` for a change that edits a file some test imports with `${./file}`.
- [ ] [low] **Read pinned keys from committed files with their exact bytes.**
  → **Promote to** one-off
  > **Why**: particular to clan's untrimmed `.value` (A320).

---

## Open items that outlive the change

| Item | Where it goes |
|------|---------------|
| A darwin host's key is still a literal a person updates, with no obligation like the NixOS one | type-the-fleet-host-registry |
| A NixOS host missing from `hostKeys` does not fail its build (operator answer to Open Question 2) | type-the-fleet-host-registry |
| `build` in the configuration sense and `SSH` have no designation rows (verify S2); the behavioral requirements use them in plain sense | a later change that adds behavioral requirements using them |
