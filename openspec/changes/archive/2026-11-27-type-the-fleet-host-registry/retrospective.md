# Retrospective: type-the-fleet-host-registry

> Written: 2026-11-27 (after verify passed with warnings and the post-merge tasks 6.1–8.3 were recorded, before archive)
> Commit range: `68c045788` (planning, shared with the other Den-ready fleet changes), then `9055ae0f1333` on `main`
> Worktree: merged to main (#4386); this retrospective and the archive are one further commit

---

## 0. Evidence

- **Commit range**: `68c045788` (this change's artifacts among the planned Den-ready fleet changes), `9055ae0f1333` (the typed record, task evidence and verify, #4386, parented on `07e3f1affe2d`); 2 commits
- **Diff size**: `9055ae0f1333` +976 / −471 across 43 files, artifacts included
- **Tasks done**: 32/32 (`tasks.md`)
- **Active hours**: about 1.5 h of recorded evidence, from the baseline (`logs/thr-1-baseline-20261127-053803.json`, 05:38 UTC) to the controller read (`logs/thr-7-controller-20261127-020351.log`, 07:04 UTC), including two drvPath diffs of 978.0 s and 934.8 s and the cinnabar deploy (07:00:25–07:03:31 UTC)
- **Subagent dispatches**: one recorded, the verify subagent (`verify.md`, Verifier line); the others are not recorded in the artifacts
- **New external dependencies**: none
- **Bugs encountered post-merge**: none; the deploy left cinnabar `running` with no failed units and the controller admitting all twelve members (tasks 7.1, 7.2)
- **OpenSpec validate state at archive**: `openspec validate type-the-fleet-host-registry --strict` valid; the synced specs validated with `openspec validate --specs`
- **Test coverage signal**: four record mutants (`thr-2-mutants-…`), three composition mutants m5–m7 (`thr-3-mutants-…`), the cx99 cloud-type mutant (`thr-4-mutants-…`), the resolver mutant failing `eval-inventory-members` (`thr-5-mutants-…`); `just drv-diff 07e3f1affe2d 9055ae0f1333` PASS (nixos 5 identical + cinnabar changed, darwin 4, home 20, vmTests 24 identical; task 8.1); the 1.2 projections equal at the merged head except the expected three differences (task 8.2)

Commit chain (chronological):

```
68c045788 docs(openspec): plan the den-ready fleet architecture changes
9055ae0f1 feat(lib): record each fleet host once as a typed record
(this commit) docs(openspec): archive type-the-fleet-host-registry
```

---

## 1. Wins

- Six hand-kept host tables collapsed into one typed record with no drvPath change outside cinnabar and the checks that read the docs package or the size table; the oracle showed it fleet-wide twice (tasks 5.5, 8.1).
- Every derived value was compared with its pre-change baseline by one projection expression, run at the commit (verify §5) and again at the merged head (task 8.2): equal except `allowedIps` order, stibnite's tag and the one added check, each a declared outcome.
- The deploy exercised the one intended runtime change: cinnabar's controller now admits the six external members from a class-derived list, read on the machine (task 7.2).
- Each class-contradicting field fails naming the host, shown by mutants with `tryEval` returning `success = false` (task 2.4).
- The resolver unified four readers, and a mutant ignoring `all` fails its own check (task 5.1).

## 2. Misses

- [med] [painful | evidence: task 5.5, verify §4 D10] D10 predicted four changed checks; the first judgement found 29 more (24 docs-package checks, `agent-skills-index`, `deploy-docs-rehearsal`, `apps-build` on both systems, `fleet-alert`), each traced with `nix derivation show` and then declared. The same miss as the previous change's `eval-users-lib`: a check changes through what it imports or renders, not through what it tests.
- [med] [painful | evidence: verify WARNING 2] The behavioral scenario `A host disappears from the registry` has no mutant, and m5–m7 show the directory assert fires before `structure-fleet` compares, so its THEN (the fleet pin names the host) is unobserved and may name the wrong guard. Left open at archive.
- [low] [nit | evidence: verify §8a, §8c] Several behavioral nouns (record, fully qualified name, overlay address, deploy account, evaluator bound, controller) have no designation row, and three behavioral scenarios state interface or machine phenomena. Not reworded at sync.
- [low] [nit | evidence: verify WARNING 3] A301's first citation (`lib/modules.nix:1240,1249`) was from another nixpkgs revision; corrected to `:1434,1443` at `bd5b7d01` before merge.
- [low] [nit | evidence: task 7.1] cinnabar had not been deployed since 2026-11-24, so this change's deploy also applied unrelated merged work (zpool-probe timer, collector and exporter restarts, hermes-agent and package updates); the deploy cannot isolate this change's runtime effect from theirs, though the controller read is specific to it.

## 3. Plan deviations

| Plan task | What changed | Why |
|-----------|--------------|-----|
| 5.5 / D10 / `drv-delta.txt` | 29 further checks declared `changed`; D10, the Goals bullet, plan Global Constraints, proposal Impact and the oracle scenario reworded to name `fleet-alert` and the docs-package checks | The first judgement showed them; each was traced to `fleet.json` as docs source, the size-rule table, or `deploy-docs` |
| 5.5 | Run against `66c5a7768fc5`, whose tree differs from the published commit only in `drv-delta.txt` | The declarations were added after the dump; 8.1 at the merged head closed the gap |
| 6.1 | No ADR amendment | ADR-0019 and ADR-0020's `clan.machines` example is what `modules/clan/machines.nix` now generates |
| 8.2 | Projections taken with `getFlake` at a pinned revision rather than the working copy | The shared working copy carries other chains' work |

## 4. Skill / workflow compliance

| Skill                                            | Used |
|--------------------------------------------------|------|
| superpowers:brainstorming                        | yes (`brainstorm.md`) |
| superpowers:writing-plans                        | yes (`plan.md`) |
| superpowers:using-git-worktrees                  | no |
| superpowers:subagent-driven-development          | not evidenced beyond the verify subagent |
| (transitive) superpowers:test-driven-development | yes in the mutant form: each guard shown failing (tasks 2.4, 3.8, 4.2, 5.1) |
| (transitive) superpowers:requesting-code-review  | no |
| superpowers:finishing-a-development-branch       | yes (#4386 merged) |

### Deliberately Skipped Skills

- **`superpowers:using-git-worktrees`**
  - **What was skipped**: the whole skill.
  - **Why this cycle**: the change landed as one commit on the shared jj development join, parented on `07e3f1affe2d`, the archive of the two previous Den-ready changes.
  - **How to prevent recurrence**: `schema graph fix` — the same answer as establish-refactor-oracle's and stop-reading-other-hosts-configs' retrospectives; see §6.
- **`superpowers:requesting-code-review`**
  - **What was skipped**: a review separate from verification.
  - **Why this cycle**: on 2026-11-27 the operator waived the code and documentation review sub-gates of In Review and approved archiving on the verify record and the post-merge tasks.
  - **How to prevent recurrence**: `scope-judgment rule` — record the waiver in the change's attempt log at the gate, as done here.

## 5. Surprises

- The docs package takes `fleet.json` as source, so renaming one inventory tag changes every docs-package check on both systems (task 5.5).
- `fleet-alert` renders every `testSizes.checks` entry into its size-rule clause, so adding any sized check changes it (task 5.5).
- clan-core adds every `flake.clan.machines` name to the inventory, so a record without an inventory entry passes the name asserts and only the directory assert catches it (task 3.8).
- The machine-check asserts guard the whole `checks` set, so a kind flip fails before `structure-fleet` compares (task 3.8, D4).

## 6. Promote candidates → long-term learning

- [ ] [med] **Predict a refactor's changed checks from what each check imports, renders or takes as source, not from what it tests.**
  → **Promote to** memory
  > **Why**: two consecutive changes under-declared `drv-delta.txt` (`eval-users-lib` in stop-reading-other-hosts-configs; 29 checks here via `fleet.json` and `testSizes`).
  > **How to apply**: writing `drv-delta.txt` for a change that edits `fleet.json`, `testSizes`, or a file some test imports with `${./file}`; trace reverse dependencies with `nix derivation show` before the first run.
- [ ] [med] **Shared-join changes skip `using-git-worktrees` every cycle.**
  → **Promote to** schema
  > **Why**: three consecutive Den-ready changes recorded the same skip and the same prevention answer.
  > **How to apply**: the apply phase of `superpowers-bridge-wrspm` should accept a jj development-join chain as the isolation step.
- [ ] [low] **Deploy the target host right after the previous merged change, so a change's deploy carries only its own closure delta.**
  → **Promote to** one-off
  > **Why**: here a three-day gap folded unrelated work into the deploy; whether it recurs depends on deploy cadence, not on this change.

---

## Open items that outlive the change

| Item | Where it goes |
|------|---------------|
| No mutant removes a host record; whether `A host disappears from the registry` names the fleet pin or the directory assert is unobserved (verify WARNING 2) | a later change touching `checks/machines.nix` or `structure-fleet` |
| Behavioral nouns without designation rows and three alphabet findings (verify §8a, §8c) | a later change that adds behavioral requirements using them |
| A darwin host's key is still a literal a person updates (carried from stop-reading-other-hosts-configs) | not addressed here; D11 derives only the NixOS key-host list, so a new NixOS record is always in `hostKeys` |
