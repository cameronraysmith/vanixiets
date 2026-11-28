---
linear_story_id: CAM-140
linear_story_identifier: CAM-140
linear_story_title: "ghq-sync -u fails when the update fast-forwards onto a shallow boundary a tag fetch left"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-140/ghq-sync-u-fails-when-the-update-fast-forwards-onto-a-shallow-boundary
linear_story_state: Todo
linear_team: CAM
last_synced_state: Todo
last_synced_at: "2026-11-28T00:08:38Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-28T00:08:32Z", transition: "Backlog->Todo", outcome: "posted", note: "Bound CAM-140 (team CAM, no project) on proposal.md; description seeded from proposal.md, the earlier investigation description saved under logs/; state confirmed Todo by read-only view; milestone comment added" }
---

## Why

A reference copy can silently stop updating: once upstream's branch moves past a commit the copy holds without its history, every refresh fails with git's `fatal: Not possible to fast-forward, aborting.`, and agents go on reading stale source.
On stibnite on 2026-11-27, 2 of 679 copies failed every refresh this way, and upstream's branch already contained such a commit in 2 more.
Nothing in the writer's reply says why, and the repair an account reaches for, `ghq-sync --deepen N` with N sized to the gap, hid 11 commits of history the copy had held on `nixos-hardware`; only a second deepen to the roots brought them back.
An automatic heal with a crash-safe repair was built and failed verification four times (D4), so this change reports the block and names a repair that hides nothing, and changes nothing the writer does to a repository.

## What Changes

Decisions tagged `D<n>` are developed in `design.md`.

**A refresh that fails with a shallow boundary between the branches**
- From: `ghq get -u` fails with git's fast-forward refusal, the writer replies 1, and nothing says why or how to repair it.
- To: when the fast-forward fails and a shallow boundary lies between the local branch and its upstream (D1), the reply keeps git's refusal and exit status and adds two lines: that the copy holds a commit without its history that lies between the local branch and upstream's, and the command that repairs it, `ghq-sync --deepen 1000000 <path>` followed by `ghq-sync -u <path>`, with how to read an update still failing after it (D2, D3). The lines state no cause the clone cannot show: a branch upstream rewrote through such a commit looks there like one that moved past it. The exit log line adds `boundary=blocked`; a failure while finding the commit adds nothing.
- Reason: the account learns what the clone shows and a repair that hides no history.
- Impact: non-breaking; finding the boundary reads the clone and writes nothing; an update that succeeds runs nothing more, and one that fails reads `.git/shallow` and, when it lists a boundary, runs three read-only git commands.

**What ghq-sync and the skill say of `--deepen`**
- From: `ghq-sync --deepen N` is described as deepening by N commits.
- To: the usage text and the skill `dependency-source-acquisition` say that a sized `--deepen` can hide history the copy holds, name `--deepen 1000000` as the form that hides none, and say what it costs, what a stopped one leaves, how to read the update after it, and that `ghq-sync --full` is the other repair (D3).

Not in this change: any automatic heal, repair of `.git/shallow`, record of a stopped request, or change to what `--deepen N` does (D4); fetching tags with their history; a pass over existing copies whose boundaries hide held history; the items of CAM-138.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `shared-reference-tree` (stratum: `behavioral`): adds `A refresh that fails with history held in part before upstream's says so and how to repair it`.
- `shared-reference-tree-interface` (stratum: `interface`): adds `The writer's reply names a shallow boundary between a failed update's branch and its upstream` and `The writer's exit log line marks an update the shallow boundary line names`.
- `world-assumptions` (stratum: `world`): adds A380 to A382, the git and upstream facts the report and its named repair rely on.

## Impact

- Code: `pkgs/by-name/ghq-shared/ghq-writer-handler.py` (the read-only finding, the two reply lines and the log token); `pkgs/by-name/ghq-shared/test_handler_boundary.py`, a third handler test script with its own check `package-ghq-shared-test-handler-boundary` declared in `modules/checks/package-tests.nix`, wired in `package.nix` and `test-handler.nix`; `handler_fixtures.py`'s docstring.
- Text: `pkgs/by-name/ghq-sync/ghq-sync.sh`'s usage text and `modules/home/ai/plugins/version-control-and-forge/.apm/skills/dependency-source-acquisition/SKILL.md`.
- Record: `verify.md`, the four verifications of the automatic heal this change set aside.
- Hosts: magnetite, pyrite and stibnite, by their usual deploys; a copy the reply names is repaired by hand, by the command its reply names.
