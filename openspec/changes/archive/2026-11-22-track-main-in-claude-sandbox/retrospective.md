# Retrospective: track-main-in-claude-sandbox (CAM-119)

Written 2026-11-22 (UTC) at archive time, by subagent `TrackMainImpl`, which implemented groups 1, 2, 5 and 6 and recorded the evidence of groups 3 to 6; the orchestrator ran the controller and cloud sessions, so claims about those rest on their reports, quoted in tasks.md.

## 0. Evidence

| Measure | Value | Source |
|---|---|---|
| Commits | 14 on `origin/main`, `b374a85f9` (propose) … `0cd1be05b`; this record-and-archive round is the 15th, unpublished | `git log --oneline b374a85f9~1..0cd1be05b` |
| Diff size | 38 files, +2294 −209, artifacts included | `git diff --shortstat b374a85f9~1 0cd1be05b` |
| Tasks done | 20 of 20 (3.3 closed unmeasured, 4.1 by its fallback, 4.2 dropped) | tasks.md |
| Active span | 2026-11-22, about 01:10 UTC (propose) to 08:10 UTC (archive), roughly 7 h | commit times |
| Cloud sessions run | 3.1 and 3.2 children, the Q97 and id probes, 5.3's controller and child, the refresh and end-to-end session of 6.5 | tasks.md |
| Design restatements | D2 changed four times in one day: pasted track-mode text → curl of a raw file → raw file without runtimeInputs → the flake app run by a fixed `nix run` bootstrap | design.md D2 |
| New external dependencies | none in the flake; gitleaks added to the profile's hook closure | `modules/home/users/claude-sandbox/default.nix` |
| Post-merge defects | 2: the bootstrap's 402-column line refused by the platform (fixed in `6687876da`, A187); `checks.gitleaks` failing on the transcript check's literal fixtures (fixed in `0cd1be05b`) | tasks.md 5.3, 6.4 |
| Pre-existing defect found | `.gitleaks.toml` loaded no rules, so the repository scan found nothing (#4138, `c0e8ddda6`) | tasks.md 6.4 |
| OpenSpec validate at archive | `--strict` valid | verify.md §1 |
| Test signal | evaluation checks with mutants (`claude-sandbox-setup-script`, `claude-sandbox-transcripts`, the hooks assertion), shellcheck mutants, container tests on magnetite (1.3, 2.1, 5.2, the hook, the app stubs), and cloud runs (3.1, 3.2, 5.3, 6.5) | tasks.md, verify.md |
| Commit chain | propose → track mode → record 3.1, 3.2 → setup app → split bootstrap → CLI default environment → transcript hook → session app → skill → gitleaks defaults → end-to-end fixes → assembled fixtures → record and archive | `git log` |

## 1. Wins

- The setup step's text no longer changes per commit: Default holds a 7-line bootstrap generated from `lib/caches.nix`, and every profile change since 5.3 reached it through `main` and one refresh line, not a new script (tasks 5.3, 6.5).
- Every regulator was seen failing on a mutant before it was trusted, and the mutants found real gaps: an equivalent C mutant (`lib.last`), a canary hidden by a gitleaks match overlap, and a line-target allowlist that only an over-broad mutant exposes (verify.md §4).
- One probe session settled two unknowns at once: the cloud session id lives in the transcript's `remote_session_change` record, not in any environment variable, and the session's own origin and credential helper carry the hook's push (README §Observing a session).
- The loop ran end to end on its first real attempt after the fixes: two rounds of create or send, wait and fetch in 108 s and a fast-forward (task 6.5).

## 2. Misses

- [high] The first bootstrap was written without the platform's line limit, which the archived change had recorded as 200 bytes and this change dropped as applying only to pasted scripts; the operator's card was refused and the stored text diverged from the README until `6687876da` (A187).
- [med] D2 was restated four times in one session, each time after code had been written for the previous form; two container test rounds were thrown away (tasks 5.1, 5.2).
- [med] `checks.gitleaks` was not run when the transcript check added token-shaped fixtures, so a pushed commit failed CI (`ff7bc717b`, fixed in `0cd1be05b`).
- [low] The first transcript hook used gitleaks' default rules, which flag three kinds of harness metadata in every cloud transcript, so the first live turn pushed nothing (task 6.4).
- [low] A `HOME` override in a persistent shell left three commits with an empty committer, repaired with `jj metaedit` (tasks 3.1 round).

## 3. Plan deviations

- Group 1's generator (`--track`) and its check were replaced in group 5 by the flake app; plan.md now says so at its top.
- Groups 5 and 6 were added mid-change: the bootstrap-and-app design (operator Q1–Q3) and the CLI cloud-session loop, split into three stacked chains for review.
- Tasks 3.3, 4.1 and 4.2 were closed by operator decision rather than measured (tasks.md).
- The walk's 300 s budget path was left untested by decision (verify.md §4).

## 4. Skill / workflow compliance

| Apply-phase skill | Used? | Evidence |
|---|---|---|
| superpowers:using-git-worktrees | no | jj development join with one chain per piece of work |
| superpowers:subagent-driven-development | yes | the orchestrator dispatched this implementer, scouts for the skill's baseline and green runs, and controller sessions |
| superpowers:test-driven-development | yes | each check assertion and the skill were seen failing first (verify.md §4, tasks 5.1, 6.3, 6.4) |
| superpowers:requesting-code-review | not evidenced | no review artifact; pull requests #4135–#4139 merged through the queue |
| superpowers:finishing-a-development-branch | yes | every chain landed on `main` through pull requests |

### Deliberately Skipped Skills

- **What was skipped**: superpowers:using-git-worktrees.
  **Why this cycle**: the repository is jj-colocated and the work ran as path-scoped squashes into chains (`luzwmoou`, `uwpvyyzq`, `omnxlryo`, `nunsrxwt`, `lwzkutwk`, `kprrmnmv`, `ozrlqqrm`, `ruspxnzt`) on the development join.
  **How to prevent recurrence**: schema graph fix, as `bootstrap-claude-sandbox` already proposed: accept a jj chain as the isolation mechanism for jj repositories. This is the second cycle with the same answer.
- **What was skipped**: superpowers:requesting-code-review, as a recorded artifact.
  **Why this cycle**: reviews happened as orchestrator round-trips on each chain, not as recorded review outcomes.
  **How to prevent recurrence**: scope-judgment rule: record each pull request's review outcome in tasks.md next to the task it closes.

## 5. Surprises

- The platform refuses setup-script lines wider than 200 columns, a tab counting 8, before any card is shown (A187).
- `/rename` sent with `-p --cloud` renames the session internally and shows in its chat, but the claude.ai title set by `-n` stays.
- Without `remote.defaultEnvironmentId`, `claude --cloud` takes the newest environment, not the first.
- A gitleaks config holding only an allowlist loads no rules at all, so the repository scan had been passing vacuously (#4138).
- The marker's `nix` is the app's own Nix (2.35.6) while the session's `PATH` keeps the image's (2.34.6), as designed (R5).
- A pooled, pre-provisioned container ran the setup step at claim time, after the script change (task 3.2).

## 6. Promote candidates → long-term learning

- [ ] [high] A platform limit recorded in an archived change still binds its successor; carry world assumptions forward explicitly instead of re-deriving which still apply.
  → **Promote to** memory
  > **Why**: the 200-byte line limit was dropped as obsolete and the operator's card was refused (A187).
  > **How to apply**: when replacing a design, list the archived change's world assumptions and mark each kept or void before writing code.
- [ ] [med] Run `checks.gitleaks` whenever a change adds anything token-shaped, including test fixtures and canaries.
  → **Promote to** CLAUDE.md
  > **Why**: the transcript check's literal fixtures failed CI after push (`ff7bc717b`).
  > **How to apply**: any diff adding secrets, canaries, or strings a secret scanner could match.
- [ ] [med] Settle the delivery mechanism (text, raw file, app) with the operator before implementing it.
  → **Promote to** skill (brainstorming)
  > **Why**: D2 was rebuilt four times in one session.
  > **How to apply**: when a design choice trades trust boundary against convenience, ask before writing code.
- [ ] [low] Never change `HOME` in a persistent shell; pass it per command.
  → **Promote to** memory
  > **Why**: jj lost its user config and wrote commits with an empty committer.
  > **How to apply**: any test that needs an isolated home directory.
