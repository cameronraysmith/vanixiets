---
linear_story_id: CAM-128
linear_story_identifier: CAM-128
linear_story_title: "Serialise shared reference tree writes in the spec and split its runtime test"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-128/serialise-shared-reference-tree-writes-in-the-spec-and-split-its
linear_story_state: Done
linear_team: CAM
last_synced_state: Done
last_synced_at: "2026-11-27T04:54:08Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-26T22:35:53Z", transition: "Backlog->Todo", outcome: "posted", note: "Issue CAM-128 created in Todo on team CAM with no project, description seeded from proposal.md; state, project and labels confirmed by read-only view" }
  - { at: "2026-11-26T22:43:20Z", transition: "Todo->In Progress", outcome: "posted", note: "First tasks.md checkbox checked; state confirmed In Progress by read-only view" }
  - { at: "2026-11-27T01:25:37Z", transition: "In Progress->In Review", outcome: "posted", note: "verify.md written with PASS WITH WARNINGS after two earlier FAIL runs closed by the writer fixes; state confirmed In Review by read-only view" }
  - { at: "2026-11-27", transition: "In Review gates", outcome: "posted", note: "Code review accepted on the three verification runs; documentation accepted with one follow-up (verify.md, In Review gates); review_round stays 0" }
  - { at: "2026-11-27T04:54:08Z", transition: "archive->mirror", outcome: "dropped", note: "no linear_project bound; spec mirror skipped" }
  - { at: "2026-11-27T04:54:08Z", transition: "In Review->Done", outcome: "posted", note: "Archived after syncing shared-reference-tree-interface; state confirmed Done by read-only view, closing comment posted" }
---

## Why

On 2026-11-26 two updates of one clone in the shared reference tree ran together on stibnite: one moved the remote-tracking ref while the other's pull was transferring, which then failed with "cannot lock ref" and left the ref ahead of the branch.
The fix on `main` serialises the writer's requests per repository, but the interface spec does not state the lock, its wait, the note a waiting caller receives, the refused `get`, the log line or a disconnected caller.
The runtime test that witnesses the writer reached 50 to 52 s of its 60 s limit with the lock's case, so the next case would exceed it.

## What Changes

**Writer concurrency**
- From: the spec says the service starts one handler per connection and is silent on two requests for one repository.
- To: requests for one repository run one at a time under a lock outside the tree, requests for repositories whose paths differ by more than letter case overlap, and a request waits at most 3600 s before failing with exit status 75.
- Reason: the collision above.
- Impact: non-breaking; records behaviour already on `main`.

**Request protocol**
- From: one request line per connection.
- To: an optional second line `{"accept": ["note"]}` lets the writer tell a waiting caller so; a `get` whose target names no directory under the root is refused; each request leaves log lines with a UTC timestamp, the caller, the verb, the repository, the status, the duration and a failure's reason, never the target; a command that outlasts its limit is stopped with every process it started, and its request ends with a reply; a caller that disconnects does not stop its operation.
- Reason: a caller that waits must know why; the log must say who wrote what without recording credentials a target may carry.
- Impact: non-breaking; older clients send no second line and get their reply alone.

**Runtime test**
- From: `vmTests.x86_64-linux.shared-reference-tree` holds every case, 50.04 to 51.76 s of a 60 s limit.
- To: migration and tags move to `vmTests.x86_64-linux.shared-reference-tree-migration`, built from the same node definition; both are `small` with at least 15 s of margin.
- Reason: a class is not raised to make room; a test larger than its purpose is split.
- Impact: one more runtime test in the weekly run; `shared-reference-tree` keeps its name and its recorded history.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `shared-reference-tree-interface` (stratum: `interface`): adds `The writer acts on one repository at a time` (the lock, its directory and its name), `A request waits a bounded time for its repository, and only a caller that asks is told` (3600 s, exit status 75, the note line), `The writer refuses a get that names no directory under the shared root`, `The writer logs each request without its target`, `A command that outlasts its limit is stopped with all it started`, `Git's automatic maintenance is part of the request that starts it`, `A caller that disconnects does not stop its request` and `Each runtime test of the shared tree fits its size class`; modifies `Each property is backed by evidence that can fail` to speak of runtime tests in the plural. Every new scenario names its witness. `Acquisition is delegated to the writer through a socket-activated entry point` and `The writer accepts only constrained requests` keep their text, which stays true: one handler still starts per connection, and the note line is an option, not a second request. Trust boundary: the lock orders the writer's own handlers on one host and nothing else that writes a clone, such as root or an administrator acting as the writer; a wait is bounded by the holder's own git timeouts, not by the lock.

The behavioral capability `shared-reference-tree` is unchanged: the lock orders the writer's own work and gives no other account a write, and "A missing reference repository can be requested without a person" already demands that each well-formed request is carried out.
`world-assumptions` is unchanged: no assumption names the writer's concurrency or the runtime test.

## Impact

- Specs: `openspec/specs/shared-reference-tree-interface/spec.md`, eight requirements added and one modified.
- Test: `modules/vm-tests/shared-reference-tree.nix` defines `shared-reference-tree` and `shared-reference-tree-migration` from one `mkTest` and declares both in `testSizes.vmTests`; `checks.x86_64-linux.test-size-classes` reads the new name.
- Writer: `pkgs/by-name/ghq-shared/ghq-writer-handler.py` stops a timed-out command with its process group, ends every failure with a reply and a logged reason, and runs git's automatic maintenance in the foreground with the gc strategy, so a clone's packs are consolidated under its lock; `test_handler.py` covers each.
- Unchanged: the NixOS and darwin modules, and the weekly runner, which evaluates every `vmTests.x86_64-linux` attribute by itself.
- Evidence logs are under `logs/` (git-ignored), named `srt-split-<test>-pyrite-<timestamp>-run<n>.log`.
