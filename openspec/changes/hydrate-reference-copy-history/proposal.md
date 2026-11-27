---
linear_story_id: CAM-136
linear_story_identifier: CAM-136
linear_story_title: "Make the commits a reference copy brings in readable as diffs"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-136/make-the-commits-a-reference-copy-brings-in-readable-as-diffs
linear_story_state: In Progress
linear_team: CAM
last_synced_state: In Progress
last_synced_at: "2026-11-27T05:05:13Z"
review_round: 3
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-26T23:56:11Z", transition: "Backlog->Todo", outcome: "posted", note: "Issue CAM-136 created in Todo on team CAM with no project, description seeded from proposal.md; state confirmed by read-only view" }
  - { at: "2026-11-27T05:05:13Z", transition: "Todo->In Progress", outcome: "posted", note: "First tasks.md checkbox ticked (1.1); state set by name and confirmed by read-only view; milestone comment added" }
---

## Why

Readers cannot diff most commits a reference copy holds: copies are shallow blobless clones, and an update brings in the new commits and trees but only the blobs of the new tip.
In `github.com/vidhanio/hypertext` on stibnite 92 objects of its 39 commits' history were missing on 2026-11-26, and `git show` of the second newest commit, like lazygit's Patch pane, failed with `Permission denied` from an on-demand fetch into the read-only tree; lazygit's start-up fetch fails the same way.
The skill's remedy, hydrating `<rev>` before `git show <rev>`, is not enough, because a diff needs the parents' blobs too.

## What Changes

Decisions tagged `D<n>` are developed in `design.md`; items 1 to 3 of the outline were approved on 2026-11-26.

**History of an update or deepen**
- From: an update or deepen fetches commits and trees, and only the blobs its checkout needs.
- To: before releasing the repository's lock, the writer fetches the blobs each commit brought into the copy's branches and remote-tracking branches needs for its diff, as `git show` and lazygit read it with rename detection, merges included (D1 to D3), leaving a tag commit fetched at depth 1 for `ghq-sync --hydrate <tag>`, unless more than 100,000 are missing, when it fetches none and says so, naming `ghq-sync --hydrate` (D4); a failed fetch leaves the request's outcome unchanged (D5), and what a failed or stopped request fetched and left unhydrated is hydrated at the copy's next update or deepen, from a record of what its last complete walk saw (D2).
- Reason: every commit a reader sees in a copy should be readable as a diff.
- Impact: non-breaking; updates take longer and copies grow by their window's blobs; a first acquisition is unchanged.

**Readers' git beneath the shared root**
- From: a read needing an absent blob starts an on-demand fetch that fails with a permission error.
- To: participating accounts' git refuses every transport beneath the shared root (`protocol.allow = never` under the existing `gitdir:` includes), so such a read fails at once with `could not fetch <oid> from promisor remote` (D6).
- Reason: a clear, immediate failure that names the missing object.
- Impact: readers' `git ls-remote origin`, `git remote show origin` and `git fetch --no-write-fetch-head` inside a copy are refused before any transport; a plain `git fetch` is still refused first by the operating system, at `.git/FETCH_HEAD`.

**lazygit**
- From: lazygit fetches at start-up in a copy and shows the failure.
- To: `<root>/.lazygit.yml`, owned by the writer, sets `git.autoFetch: false` for every copy (D7).
- Impact: non-breaking; migration keeps the file.

**Guidance**
- From: the skill says to hydrate `<rev>` before `git show <rev>` or `git diff`.
- To: the skill, `ghq-sync --hydrate`'s usage text and the spec say `git show <rev>` needs `<rev>` and its parents hydrated and `git diff A B` both endpoints (D8).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `shared-reference-tree` (stratum: `behavioral`): adds `A refreshed or deepened reference repository shows what each commit it gained changed`, `A refresh that stopped after fetching is made readable by the next`, `A tag's commit fetched without its history is readable once requested` and `A read that needs content the reference tree lacks fails at once`.
- `shared-reference-tree-interface` (stratum: `interface`): adds `An update makes every commit it brought in readable as a diff`, `An update makes the merges it brought in readable with rename detection`, `Tag commits fetched at depth 1 stay unhydrated`, `The history fetch keeps the clone's partial-clone filter`, `A deepen makes every commit it brought in readable as a diff`, `The writer bounds the history it makes readable`, `The writer keeps a record of what its last complete history walk saw`, `The writer hydrates what an earlier request fetched and left unhydrated`, `A failed history fetch leaves the request's outcome as it was`, `The history walk gives git its lists on standard input`, `The writer's exit log line names what the history fetch did`, `A first acquisition fetches nothing more than before`, `Participating accounts' git refuses every transport beneath the shared root`, `The shared root is declared as a path a gitdir: include can match`, `Evaluation rejects an include that reopens a transport beneath the shared root`, `lazygit fetches nothing at start-up beneath the shared root`, `Migration keeps the provisioned .lazygit.yml over an administrator's own` and `A revision's diff is readable once the revision and its parents are hydrated`; every new scenario names its witness. Trust boundary: these hold at the hosts' declared configuration, the writer's handler and Unix permissions; they do not cover an account's own `-c` or environment overrides, programs that read no git configuration, lazygit versions other than the one inspected, or history fetched before the change.
  `Acquisition is delegated to the writer through a socket-activated entry point` keeps its text, and its scenario "A participating account bypasses the wrapper" stays true: a plain `git fetch` opens `.git/FETCH_HEAD` before it connects, so the operating system still refuses it with a permission error (design, decisions of 2026-11-27, item 5).

`world-assumptions` is unchanged: the behavioral requirements use its existing designations (reference repository, reference tree, participating account, writer, acquisition request, commit, history).

## Impact

- Code: `pkgs/by-name/ghq-shared/ghq-writer-handler.py`, `handler_fixtures.py`, `test_handler.py`, `test_handler_history.py`, `test-handler.nix` and `package.nix`; `modules/checks/package-tests.nix`; `modules/darwin/omnigent-host.nix`; `pkgs/by-name/ghq-shared/ghq-shared-migrate.py`; `pkgs/by-name/ghq-sync/ghq-sync.sh` (usage text); `modules/home/development/repository-acquisition.nix`; `modules/system/shared-reference-tree.nix`, `modules/nixos/shared-reference-tree.nix`, `modules/darwin/shared-reference-tree.nix`; `modules/system/shared-reference-tree.test.nix`; `modules/vm-tests/shared-reference-tree.nix`; `modules/home/ai/plugins/version-control-and-forge/.apm/skills/dependency-source-acquisition/SKILL.md`; `modules/home/ai/plugins/agent-context-vanixiets/.apm/instructions/30-reference-repositories.instructions.md`.
- Tests: the handler's test splits into `checks.*.package-ghq-shared-test-handler` (requests, locks, time limits, failure logging, maintenance) and `checks.*.package-ghq-shared-test-handler-history` (the history fetch's cases, seventeen of them new), sharing `handler_fixtures.py`; `checks.x86_64-linux.eval-shared-reference-tree` is new; `vmTests.x86_64-linux.shared-reference-tree-migration` gains two subtests (about 2 to 3 s of its 33 to 35 s), `shared-reference-tree` one assertion and a reworked hydrate subtest.
- Hosts: magnetite, pyrite and stibnite, by their usual deploys.
