# Retrospective: establish-refactor-oracle

> Written: 2026-11-27 (after verify passed with warnings, before archive)
> Commit range: `68c045788` (planning, shared with the other Den-ready fleet changes), then `f78b96fe5..c969642cf` on `main`
> Worktree: merged to main (#4377, #4379); this retrospective and the archive are one further commit

---

## What the change set out to do

The Den-ready fleet architecture project refactors the fleet in seven changes, each meant to leave every deployed system unchanged.
The repository had only `just eval-identity`, which compares two evaluators at one commit and cannot show that a commit left derivations unchanged.
The change was to add `just drv-diff`, which judges two commits' drvPaths over seven maps against a declared allow-list, and `just eval-cost`, which measures evaluation cost by alternating fresh runs against a recorded baseline, and to fold the fleet review's findings into the principles document with a fifth principle and amend ADR-0018/0019/0020 (proposal, design D1–D14).

---

## 0. Evidence

- **Commit range**: `68c045788` (this change's artifacts among seven planned changes), `f78b96fe5` (the two apps, #4377), `c969642cf` (principles, ADRs, READMEs, task evidence and verify, #4379); 3 commits
- **Diff size**: `f78b96fe5` +606 / −0 across 7 files (`modules/apps/drv-diff.{nix,sh}`, `drv-diff-base-allow.txt`, `eval-cost.{nix,sh}`, `justfile`, the baselines note); `c969642cf` +669 / −187 across 14 files; the planned artifacts +1118 across 9 files in `68c045788`
- **Tasks done**: 24/24 (`tasks.md`)
- **Active hours**: about 3.2 h, from the first checked task (2026-11-27 00:48 UTC) to verify (04:00 UTC); planning committed 2026-11-26 22:54 UTC
- **Subagent dispatches**: n/a; the artifacts record none
- **New external dependencies**: none (`nix-eval-jobs` and stock Nix were already in the flake)
- **Bugs encountered post-merge**: none
- **OpenSpec validate state at archive**: `openspec validate establish-refactor-oracle --strict` valid before the move; the synced specs validated with `openspec validate --specs --strict`
- **Test coverage signal**: the oracle's own run `b718b62ec596..07877c74b4e5` (857.5 s, exit 0 after re-judgement); a darwin mutant (831.1 s, exit 1 naming exactly `darwin.argentum` and its check); six allow-list cases re-judged in seconds (task 3.3); the first refactor's run `390f72f0c809..bbb7c5ccc978` (909.4 s, task 8.1); after verify, the whole stack `14a6b01878c3..8afba9a755b7` (`logs/drv-diff-14a6b01878c3-8afba9a755b7-20261127T044443Z`) PASS with every nixos, darwin and home attribute identical

Commit chain (chronological):

```
68c045788 docs(openspec): plan the den-ready fleet architecture changes
f78b96fe5 feat(apps): add drv-diff and eval-cost refactor checks
c969642cf docs: fold the fleet architecture findings into the principles and amend ADR-0018/0019/0020
(this commit) docs(openspec): archive establish-refactor-oracle and stop-reading-other-hosts-configs
```

## 1. Wins

- The oracle caught a real undeclared difference on its first use: the stop-reading-other-hosts-configs run failed on `checks.x86_64-linux.eval-users-lib`, which its design had not predicted, and that change declared and explained it before landing (task 8.1, its design D8).
- The mutant proved the report is exact, not only non-empty: one `environment.etc` line in argentum produced exactly `darwin.argentum` and `checks.aarch64-darwin.darwin-argentum` as undeclared, and nothing else (task 3.2).
- `--reuse` (D14) turned a 14-minute evaluation into a seconds-long re-judgement whenever an allow-list changed; verification ran its negative cases this way without evaluating the fleet (verify, traceability).
- The cost protocol showed stock Nix's thunk counts equal across four fresh runs in each of three baselines (A312), so later cost claims compare counts rather than noisy times (`docs/notes/development/eval-cost-baselines.md`).

## 2. Misses

- [med] [painful | evidence: design D13, `c969642cf`] The base allow-list was planned for whole-source checks only; `ntfy-tls-verification`, which scans every `.nix` and `.sh` under `modules/`, was found only when a run reported it, and the list's scope was widened to "every source file of a kind".
- [med] [painful | evidence: verify W1] The proof run was taken at commits later rebased; no run at the final pair was recorded before verify. The whole-stack run at 04:44 UTC (`14a6b01878c3..8afba9a755b7`, PASS) covers both changes after the rebase.
- [low] [nit | evidence: verify W3] Comparing a commit with itself, and the `added` and failing-at-one paths, are exercised only on synthetic dumps or by reading the code.
- [low] [nit | evidence: verify W2] iets rejects `--version`, so the header records `nix-eval-jobs` by store path; the spec was reworded to match.

## 3. Plan deviations

| Plan task | What changed | Why |
|-----------|--------------|-----|
| (none planned) 1.5 | `--reuse DIR` and `just drv-diff-rejudge` added (D14) | Allow-lists were edited after runs, and re-evaluating cost about 14 minutes each time |
| 1.4 / D13 | Base allow-list covers checks over every source file of a kind, not only the whole flake source | `ntfy-tls-verification` differed on every run |
| 3.1 | Self-identity discharged by 3.4's run, not a separate `drv-diff c c` | The 3.4 run already shows every unreached attribute identical over every map |
| 5.4 / D10 | P5 added as a fifth principle, not as a proposal awaiting the operator | The operator accepted it (design Open Questions, resolved) |
| plan Step 4, interface header requirement | `nix-eval-jobs` recorded by resolved store path | iets rejects `--version` (W2) |

## 4. Skill / workflow compliance

| Skill                                            | Used |
|--------------------------------------------------|------|
| superpowers:brainstorming                        | yes (`brainstorm.md`) |
| superpowers:writing-plans                        | yes (`plan.md`) |
| superpowers:using-git-worktrees                  | no |
| superpowers:subagent-driven-development          | not evidenced |
| (transitive) superpowers:test-driven-development | yes in the mutant-first form: the mutant and the allow-list cases were run to fail before the oracle was relied on (tasks 3.2, 3.3) |
| (transitive) superpowers:requesting-code-review  | no |
| superpowers:finishing-a-development-branch       | yes (#4377, #4379 merged) |

### Deliberately Skipped Skills

- **`superpowers:using-git-worktrees`**
  - **What was skipped**: the whole skill.
  - **Why this cycle**: the repository is jj-colocated and the change landed as a chain on the shared development join, stacked under stop-reading-other-hosts-configs (#4377, #4379, #4380).
  - **How to prevent recurrence**: `schema graph fix` — accept a jj chain as the isolation mechanism in a jj repository; the same answer as the archived `serialise-shared-reference-tree-writes`, `bootstrap-claude-sandbox` and `track-main-in-claude-sandbox` retrospectives, so it is a promote candidate below.
- **`superpowers:requesting-code-review`**
  - **What was skipped**: a review separate from verification.
  - **Why this cycle**: on 2026-11-27 the operator waived the code and documentation review sub-gates of In Review for this change and approved archiving on the verify record.
  - **How to prevent recurrence**: `scope-judgment rule` — record a waiver at the In Review gate in the change's attempt log when the operator gives it, as done here.

## 5. Surprises

- Checks that scan every file of a kind change on nearly every commit, the same as whole-source checks, so a per-change allow-list would carry them in every change (design D13).
- Four vmTests fail to evaluate at both commits under the oracle's disabled import-from-derivation (`caddy-root-from-vars`, `tincr-mesh`, `tincr-mesh-partition`, `omnigraph-seed`); after trunk `14a6b01878c3` and `c8ee415b5` only the two tincr tests still fail at both (whole-stack run).
- iets answers to `nix` on PATH, so a cost or identity claim that does not pin the evaluator measures whichever one PATH resolves (A313).

## 6. Promote candidates → long-term learning

- [ ] [med] **A jj chain on the development join is this repository's isolation mechanism; the worktree skill should accept it.**
  → **Promote to** schema
  > **Why**: four archived retrospectives skip `using-git-worktrees` for the same reason.
  > **How to apply**: the superpowers-bridge schema's apply phase in a jj-colocated repository.
- [ ] [med] **Validate an oracle with a mutant before any change relies on it, and require the report to name exactly the mutated attributes.**
  → **Promote to** memory
  > **Why**: the argentum mutant showed the report was exact, which a clean run alone cannot show (task 3.2).
  > **How to apply**: any new identity or regression check whose passing run is its only evidence.
- [ ] [low] **Keep allow-list re-judgement separate from evaluation.**
  → **Promote to** one-off
  > **Why**: it is particular to drv-diff's dump-then-judge structure (D14).

---

## Open items that outlive the change

| Item | Where it goes |
|------|---------------|
| `added` and failing-at-one report paths exercised by code reading only (W3) | the next refactor whose run adds or breaks an attribute |
| `tincr-mesh` and `tincr-mesh-partition` cannot be compared by the oracle while they need import-from-derivation | migrate-mesh-to-tincr |
| The `check` designation row is added here, word for word as declare-test-size-classes' delta has it | declare-test-size-classes' archive keeps one row |
