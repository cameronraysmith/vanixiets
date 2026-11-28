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

A reference copy can silently stop updating: once upstream's branch moves past a commit the copy holds without its history, every refresh fails, and agents go on reading stale source.
On stibnite on 2026-11-27, 2 of 679 copies failed every refresh, 84 held 8,071 such commits that no branch reaches yet, and upstream's branch already contains one in 2 more, whose next refresh will fail.
Healing by hand, by deepening a sized number of commits, hid 11 commits of history the copy had held; only a second deepen to the roots brought them back.

## What Changes

Decisions tagged `D<n>` are developed in `design.md`.

**A refresh that meets a shallow boundary**
- From: `ghq get -u` fails with `fatal: Not possible to fast-forward, aborting.`, the writer replies 1, and every later refresh fails the same way until someone deepens the copy by hand.
- To: when the fast-forward fails because a shallow boundary lies between the local branch and its upstream, the writer fetches the upstream branch to a doubling depth until the local tip is in its history (D1, D2), removes the boundaries that fetch placed on history the copy already held (D3), and fast-forwards; within a bound on the commits a heal may bring in (D4). The reply and the exit log line say whether it healed (D5); a heal that cannot complete leaves the refresh's failure as it was and the copy's history whole (D6).
- Reason: the copy keeps updating, and no heal hides history it held.
- Impact: non-breaking; a refresh that heals takes longer and fetches the missing commits and trees; one that does not need a heal costs nothing more.

**The history a healed refresh brings in**
- From: n/a.
- To: the history fetch makes the commits a healed refresh brought in readable, and does not walk the history the copy held before (D7).

**Deepen**
- From: `ghq-sync --deepen N` can mark commits whose history the copy holds as boundaries, hiding that history.
- To: a deepen removes those boundaries as a heal does (D8), so it never hides history a branch reached.
- Impact: non-breaking; this is a scope choice for review (design, Open Questions 1).

Not in this change: fetching tags with their history or refusing to fetch a tag ahead of a branch (D9); a pass over existing copies to remove boundaries that hide held history, of which stibnite has 1,894 in 70 copies (D10); hydrating the commits a copy fetched before the writer kept its history record; the items of CAM-138.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `shared-reference-tree` (stratum: `behavioral`): adds `A refresh succeeds when upstream's branch has moved past history the reference repository holds only in part`, `Moving past history held in part never hides history a reference repository held` and `A refresh that cannot move past history held in part leaves the reference repository as it was`.
- `shared-reference-tree-interface` (stratum: `interface`): adds `An update heals a fast-forward a shallow boundary blocks`, `A heal fetches the upstream branch to a doubling depth`, `A heal removes the boundaries its fetch placed on held history`, `A heal checks that every ref still reaches what it reached`, `A heal is bounded by the commits it brings in`, `The writer's reply says what a heal did`, `The writer's exit log line names what a heal did`, `A heal that cannot complete leaves the update's outcome as it was`, `The history walk of a healed update stops at what the clone held before` and `A deepen removes the boundaries it placed on held history`; modifies `A request that brings in no commit runs no history walk`, whose scenario of a branch moving onto a boundary now holds for an update that does not heal. Trust boundary: the properties hold at the writer's handler and the clone it acts on, for upstreams that serve a depth fetch of a branch; they do not make a branch upstream rewrote fast-forward, and say nothing of the content an upstream serves.
- `world-assumptions` (stratum: `world`): adds A380 to A382, git's shallow-history facts the design relies on.

## Impact

- Code: `pkgs/by-name/ghq-shared/ghq-writer-handler.py` (the heal, the repair, the walk's exclusion, the status line and token, `healLimit`); `pkgs/by-name/ghq-shared/test_handler_history.py`, and a third handler test script with its own check only if the history check's time on magnetite calls for one; `pkgs/by-name/ghq-sync/ghq-sync.sh` (usage text of `-u` and `--deepen`); `modules/home/ai/plugins/version-control-and-forge/.apm/skills/dependency-source-acquisition/SKILL.md`; `modules/checks/package-tests.nix` only for a new check.
- Tests: the existing handler case "A boundary present when a request begins counts as held" changes: the update it describes now heals; its point, that a boundary present when a request begins counts as held, moves to an update whose heal is not allowed to run.
- Hosts: magnetite, pyrite and stibnite, by their usual deploys; a copy heals at its first refresh that needs it after its host's deploy.
