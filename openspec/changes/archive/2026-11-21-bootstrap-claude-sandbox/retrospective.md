# Retrospective: bootstrap-claude-sandbox (CAM-118)

Written 2026-11-21 (UTC) at archive time, by subagent `SandboxChangeAuthor`, from this change's artifacts and the commit range below.
The author wrote the planning and verification artifacts; the implementation commits were made by the orchestrating agent, so claims about how they were produced rest on the artifacts and commits, not on first-hand observation.

## 0. Evidence

| Measure | Value | Source |
|---|---|---|
| Commits | 10 on `origin/main`: 1 proposal (`c22ee4b02`), 7 implementation (`090fca026` … `7c2a300ba`), 2 artifact rounds (`df278d5ea`, `1dbb4425c`); this archive round is the 11th, unpublished | `git log --oneline 090fca026^..origin/main` |
| Diff size, implementation range | 29 files, +1534 −338; excluding `openspec/`, 22 files, +1056 −220 | `git diff --shortstat 090fca026^ origin/main` |
| Tasks done | 33 of 33 | `openspec list --json` |
| Active span | 2026-11-21, about 17:29 UTC (first cloud session, record V1) to about 23:45 UTC (this archive), roughly 6 h | session record, commit times |
| Cloud sessions run | 6 rounds: the original cloud session, probe sessions 1 and 2 (5 children), session 3 (2 children), session 4 (4 children), the task 7.2 round (1 child) | tasks.md §0, 3.4, 3.6, 7.2, 8.x |
| Subagent dispatch count | not recorded in the change artifacts | — |
| New external dependencies | none in the flake; one new external service relied on, the Claude Code cloud platform, whose behaviour is recorded as A167–A183 | `specs/world-assumptions` |
| Post-merge bugs | 1: the revision-baking setup script tripped nixbot's `tree-meta-in-drv` warning, fixed in `63bcb45ef` | tasks.md 3.3 |
| OpenSpec validate at archive | change valid; `--strict` fails on one known structural warning (the designation table requirement over 500 characters) | verify.md §1 |
| Test signal | evaluation checks with mutants (`flake-shape`, `claude-sandbox-setup-script`, `claude-sandbox-session-secrets`, the hooks assertion), container tests on magnetite (tasks 4.1, 5.1, 6.5), and cloud integration rounds (8.1–8.4, 7.2) | tasks.md |
| Commit chain | propose → profile and sandbox aggregate → CI check and setup script → run-time revision fix → repository-context hook → scoped Linear secrets → session-time rendering → record integration → ghq under `/home/user` → workspace directory → record Default switch and verify → archive | `git log` |

## 1. Wins

- Measuring the platform before designing paid off: the probes overturned three documented or assumed facts before any code depended on them (a 360 s setup is snapshotted, a failed setup is fatal, setup runs twice), and each became a world assumption with a violation scenario (A169–A171).
- The controller-session loop made the cloud testable end to end for the price of one prompt and one approval card per setup change (A179, task 8.4), and every integration claim cites a measured line rather than an inference.
- Q91 dropped the bootstrap sub-flake for a generated setup script that names the CI-built closure; a cold start takes about 31 s of the 360 s window (design.md, session 4), and no flake is evaluated in the sandbox.
- Secrets stayed scoped: one recipient, one file with only the Linear keys, decrypted into `/dev/shm` at session start and never at activation, with a check and a mutant holding that (task 6.5).

## 2. Misses

- [med] Three task clauses were written for measurements that were not then made as written (3.4's hook `PATH` and `CLAUDE_ENV_FILE`, 5.2's whole-`/root` scan, 8.3's baseline with no setup step); each had to be reworded after the fact with a dated note.
- [med] The first verification's designation lint found machine terms in a behavioral requirement and five nouns without rows; fixing them (Q96) cost a round that a lint at specs time would have avoided.
- [low] The probe evidence lived on scratch branches, so every round had to quote it into the artifacts before the branches could be deleted.
- [low] `ghq.root` set by the profile is not visible to `git config --global` in a cloud session (design.md §Open Questions); unexplained at archive.

## 3. Plan deviations

- D2 was revised by Q91 the same day: the planned bootstrap sub-flake, its pointer file, its check and assumption S4 were replaced by a generated setup script and a template check (tasks.md group 3 preface); plan.md Task 4–5 describe the replacement.
- The bootstrap report became configuration (`vanixiets.sandbox.bootstrapReport`) rather than a sub-flake app (task 3.2).
- A workspace-directory option (`vanixiets.sandbox.workspaceDirectory`) and ghq clones under `/home/user` were added after the cloud showed `/home/user` is no account's home (A183, commits `0891c29cb`, `7c2a300ba`).
- An interface capability, `claude-sandbox-interface`, was added at archive time (Q96, task 7.4).
- Tracking `main` instead of a pinned closure was deferred to a separate change (Q97); this change archives as delivered (Q98).

## 4. Skill / workflow compliance

| Apply-phase skill | Used? | Evidence |
|---|---|---|
| superpowers:using-git-worktrees | no | the work ran in this repository's jj development join, not a git worktree |
| superpowers:subagent-driven-development | partly | an orchestrator dispatched subagents for artifacts and probes; whether each plan task had its own implementer is not recorded |
| superpowers:test-driven-development | partly | failing-first checks with mutants for 1.3, 2.1, 3.3 and 6.5; the cloud behaviour could only be tested after deploy |
| superpowers:requesting-code-review | not evidenced | no review artifact in the change directory |
| superpowers:finishing-a-development-branch | yes | the implementation landed on `main` through pull requests (#4121 among them) |

### Deliberately Skipped Skills

- **What was skipped**: superpowers:using-git-worktrees.
  **Why this cycle**: the repository is jj-colocated and its workflow keeps one development join on `main` with a chain per change (the chains `ozzrzsul`, `tnxtmwtr` and `ylpwwwkz` of this change), which isolates work without a git worktree.
  **How to prevent recurrence**: schema graph fix: name the jj chain as an accepted isolation mechanism in the apply instruction for jj repositories, so this row reads yes.
- **What was skipped**: superpowers:requesting-code-review, as a recorded artifact.
  **Why this cycle**: no `review.md` exists in the change directory and no review is cited in tasks.md; the integration evidence was cloud measurement, which a code review would not have replaced.
  **How to prevent recurrence**: scope-judgment rule: for a change whose code lands across several pull requests, record each pull request's review outcome in tasks.md next to the task it closes.

## 5. Surprises

- The platform's documented five-minute caching bound was wrong for 360 s (A169), and its documented ~30 GB disk was about 64 GB (A174).
- A failed setup step is fatal and unrecoverable, and `CCR_SETUP_SCRIPT_FAILURE_CONTINUES` did not change that (A170).
- Setup runs when a pre-warmed container is claimed, not when it boots, and a snapshot can come from a sibling container (A181, A182).
- Packages activated as root land in the image's default Nix profile, already on the agent's `PATH`, so no `CLAUDE_ENV_FILE` route was needed (A180).
- `/home/user` belongs to no account (A183).

## 6. Promote candidates → long-term learning

- [ ] [med] Lint designation nouns when writing specs, not only at verify.
  → **Promote to** schema
  > **Why**: Q96 found machine terms and five unresolved nouns only at verification, costing an extra round before archive.
  > **How to apply**: when a change adds behavioral requirements, run the §8a lexer pass on the specs artifact before tasks are written.
- [ ] [med] Write a task's verify clause as the exact command and observable the session will run.
  → **Promote to** skill (writing-plans / openspec task authoring)
  > **Why**: 3.4, 5.2 and 8.3 named measurements no session printed, and had to be reworded after the fact.
  > **How to apply**: for any task verified in a remote or hosted session, put the probe command in the clause and in the controller prompt together.
- [ ] [low] Quote probe evidence into the change artifacts in the same round that reads it.
  → **Promote to** memory
  > **Why**: scratch report branches are deleted after landing; anything not quoted is lost.
  > **How to apply**: whenever a probe pushes a report branch, quote the lines a task relies on before ticking it.
- [ ] [low] Explain the cloud `ghq.root` shadowing at the next 30-day renewal.
  → **Promote to** one-off
  > **Why**: the same shadowing could hide the profile's commit author identity.
  > **How to apply**: at the next renewal, run `env | grep -E '^(GIT_CONFIG|GHQ_ROOT|XDG_CONFIG)'` and `git config --show-origin --get-all ghq.root` in a child session.
