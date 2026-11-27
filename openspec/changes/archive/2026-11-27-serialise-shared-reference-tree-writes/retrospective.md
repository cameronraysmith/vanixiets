# Retrospective: serialise-shared-reference-tree-writes

> Written: 2026-11-27 (after verify passed with warnings, before archive)
> Commit range: `ebd5daae2`, then `1d65ad802..096de303b` on `main`
> Worktree: merged to main; this retrospective and the archive are one further commit

---

## What the change set out to do

On 2026-11-26 two `get -u` requests for one clone ran together on stibnite, and the second failed with "cannot lock ref", leaving the remote-tracking ref ahead of the branch.
`ebd5daae2` serialised the writer's requests per repository and was merged (#4363) and deployed before the interface spec said anything of it.
The change was to record that behaviour in `shared-reference-tree-interface` (the lock, its bounded wait, the note to a caller that asks, the refused `get`, the log line, the disconnected caller) and to split `vmTests.x86_64-linux.shared-reference-tree`, which had reached 50.04 to 51.76 s of its 60 s limit, without raising its class (proposal, design D1, D3).

---

## 0. Evidence

- **Commit range**: `ebd5daae2` (the behaviour, #4363), `1d65ad802` and `3bf86e17a` (proposal and split, #4366), `b718b62ec` (#4369), `35aae997c` (#4370), `096de303b` (verify); 6 commits
- **Diff size**: +2110 / −573 lines across 14 files, artifacts included; the writer and its test (`pkgs/by-name/ghq-shared`) +797 / −46 across `ebd5daae2..35aae997c`
- **Tasks done**: 17/17 (`tasks.md`)
- **Active hours**: about 3.2 h, from `ebd5daae2` (2026-11-26 22:13 UTC) to the third verify run (2026-11-27 01:24 UTC)
- **Subagent dispatches**: n/a; the artifacts record none
- **New external dependencies**: none
- **Bugs encountered post-merge**: 3, all in the behaviour merged in `ebd5daae2` and found by verification, not by a test or a host:
  1. A command past its 3600 s limit raised `subprocess.TimeoutExpired`, which nothing caught; the traceback, holding the `ghq get` arguments and so the request's target with any credentials, went to the writer's log, with no exit line and no reply (fixed in `b718b62ec`).
  2. The lock requirement said requests for different repositories never wait for each other, while the lock name case-folds the path (spec corrected in `b718b62ec`, design D7).
  3. Git's automatic maintenance ran detached (`maintenance.autoDetach=true` by default), left the command's process group and wrote the repository after the lock was released; with the geometric strategy it never repacked promisor packs, so stibnite's blobless clones held up to 2,533 packs (fixed in `35aae997c`, design D9).
- **OpenSpec validate state at archive**: `openspec validate serialise-shared-reference-tree-writes --strict` valid
- **Test coverage signal**: `ghq-shared`'s handler test gained cases in each of `ebd5daae2`, `b718b62ec` and `35aae997c`, each new case of the last two seen failing against the earlier handler (tasks 4.1, 5.2); two mutants of the stop (tasks 4.2); `shared-reference-tree` 35.40 to 37.36 s and `shared-reference-tree-migration` 32.86 to 35.10 s of 60 s on pyrite (tasks 3.1, 4.4, 5.5)

Commit chain (chronological):

```
ebd5daae2 fix(ghq-shared): serialise writer requests per repository
1d65ad802 docs(openspec): propose serialising shared reference tree writes
3bf86e17a test(shared-reference-tree): move migration and tags to a second test
b718b62ec fix(ghq-shared): stop and log timed-out writer commands without their target
35aae997c fix(ghq-shared): run git maintenance in the foreground, consolidating promisor packs
096de303b docs(openspec): verify serialising shared reference tree writes
(this commit) docs(openspec): archive serialise-shared-reference-tree-writes
```

## 1. Wins

- The split met its target: both tests run 15 s or more under the limit, `shared-reference-tree` keeps its name and history, and both mutants still fail at their subtests (tasks 1.3, 3.1).
- Each fix after merge was shown failing first: every new handler case failed against the handler on `main` before `b718b62ec` and `35aae997c` (tasks 4.1, 5.2), and the kill-only and SIGKILL-first mutants fail the stop's cases (task 4.2).
- The pack accumulation was traced to its cause in git 2.56.0's source (`builtin/gc.c`, `odb/source-files.c`, `repack-geometry.c`) and its cost measured on copies before the fix: 2,533 packs to 1 in 12.9 s, 1,688 to 2 in 42.9 to 48.6 s, and `SIGTERM` and `SIGKILL` mid-repack leaving each copy intact (design D9).

## 2. Misses

- [high] [blocking | evidence: `b718b62ec`, verify §4 finding 1] The behaviour as merged wrote a request's target, credentials included, into the writer's log when a command timed out, and left that request without a reply.
- [high] [blocking | evidence: `35aae997c`, verify §4 finding 3, design D9] As merged, the lock did not cover git's automatic maintenance, which outlived it, and a timed-out command's stop could not reach that maintenance.
- [med] [painful | evidence: verify §4 finding 2, design D7] The first delta stated two rules about the lock that contradicted each other on paths differing only in letter case.
- [med] [painful | evidence: verify §4 drift warnings] Five drift warnings remain: no case of a one-line caller that waits and then succeeds; only an `https` URL with credentials is tested; `describe` replaces the target only verbatim and a `://…@` userinfo; a fetch's `.promisor` file is mode `0600` between consolidations; a consolidation runs inside a caller's request with no note.
- [low] [nit | evidence: verify Overall Decision] Tasks 1.1, 3.3 and 5.1 rest partly on narrated evidence without a log name.

What the misses say about the practice: `ebd5daae2` carried 240 lines of package test and a VM subtest, passed its checks, and was merged as #4363 and deployed (no review is recorded on that pull request); its tests passed and the three defects were still in it.
Each was found by reading a statement of the spec (no target in the log; requests for different repositories never wait; the lock covers the request's operation) against the code paths that could break it (the uncaught `TimeoutExpired` and its traceback; `casefold()` in the lock name; git's detached maintenance), not by reading the tests.
The tests exercised what their author expected to happen; none drove a command past its limit, two paths differing only in case on a case-sensitive host, or an update past `gc.autoPackLimit`.

## 3. Plan deviations

| Plan task | What changed | Why |
|-----------|--------------|-----|
| (none planned) 4.1–4.4 | Group 4 added: process-group stop, exit 124, reasons on every exit line, the outer guard, the case rule in the spec | Findings 1 and 2 of the first verify run |
| (none planned) 5.1–5.5 | Group 5 added: maintenance in the foreground with the gc strategy | Finding 3 of the second verify run |
| Non-goal "changing the writer" | Narrowed to "beyond how it ends a failed or timed-out request and how git's automatic maintenance runs" | The fixes above changed the writer |
| D1's six added requirements | Eight added: "A command that outlasts its limit is stopped with all it started" and "Git's automatic maintenance is part of the request that starts it" joined | Groups 4 and 5 |

## 4. Skill / workflow compliance

| Skill                                            | Used |
|--------------------------------------------------|------|
| superpowers:brainstorming                        | yes (`brainstorm.md`) |
| superpowers:writing-plans                        | yes (`plan.md`) |
| superpowers:using-git-worktrees                  | no |
| superpowers:subagent-driven-development          | not evidenced |
| (transitive) superpowers:test-driven-development | yes for groups 4 and 5 (tasks 4.1, 5.2); no for `ebd5daae2`, which predates the change |
| (transitive) superpowers:requesting-code-review  | no |
| superpowers:finishing-a-development-branch       | yes (#4363, #4366, #4369, #4370 merged) |

### Deliberately Skipped Skills

- **`superpowers:using-git-worktrees`**
  - **What was skipped**: the whole skill.
  - **Why this cycle**: the repository is jj-colocated; each piece landed as its own chain on the development join (#4366, #4369, #4370).
  - **How to prevent recurrence**: `schema graph fix` — accept a jj chain as the isolation mechanism in a jj repository; the same answer as the archived `bootstrap-claude-sandbox` and `track-main-in-claude-sandbox` retrospectives.
- **`superpowers:requesting-code-review`**
  - **What was skipped**: a review separate from verification.
  - **Why this cycle**: on 2026-11-27 the code-review gate accepted the three verification runs as the review (verify.md §In Review gates); no review is recorded on #4363, #4369 or #4370.
  - **How to prevent recurrence**: `scope-judgment rule` — a verification run that reads every spec statement against the code paths able to break it counts as the review only when verify.md names it so; record that acceptance at the gate, as done here.

## 5. Surprises

- git's `maintenance.autoDetach` defaults to true, so `git fetch` returns while `git maintenance run --auto --detach` keeps writing the repository in a process group of its own (verify §4 finding 3).
- Without `maintenance.strategy`, git 2.56.0's unscheduled maintenance uses the geometric strategy, which sets promisor packs aside, so automatic maintenance never repacks a blobless clone (design D9).
- `git clone` ignores `remote.origin.uploadpack`, so a hanging remote for the test had to be a FIFO in place of `packed-refs` (task 4.1).
- A fetch writes a pack's `.promisor` file with mode `0600` under umask `0027`; readers only test that it exists (task 5.2).
- The group-writable mutant's `UMask=0007` no longer reaches the handler, which sets its own umask; the mutant still fails through the root's mode `2770` (task 1.3).

## 6. Promote candidates → long-term learning

- [ ] [high] **Check each spec statement against the code paths that can break it, not only against the tests that witness it.**
  → **Promote to** skill (`openspec-verify-change`, section 4)
  > **Why**: all three defects in `ebd5daae2` survived its package test and VM subtest and were found this way (verify §4 findings 1–3).
  > **How to apply**: for each requirement, list the exceptions, platform differences and child processes the code can produce, and look for each in the requirement's text.
- [ ] [med] **A lock held by a process that runs git must account for git's detached maintenance.**
  → **Promote to** memory
  > **Why**: `git fetch` returned while its maintenance kept writing after the lock was released (design D8 boundary).
  > **How to apply**: any wrapper that holds a lock or a timeout around git commands; set `maintenance.autoDetach=false` and `gc.autoDetach=false` in its command-scope configuration.
- [ ] [med] **Blobless clones need `maintenance.strategy=gc` for automatic maintenance to repack them.**
  → **Promote to** memory
  > **Why**: the geometric strategy sets promisor packs aside; stibnite's clones held up to 2,533 packs (design D9).
  > **How to apply**: any automation keeping partial clones up to date.

---

## Open items that outlive the change

| Item | Where it goes |
|------|---------------|
| Pyrite runs the handler before the lock (`/nix/store/rrlira2i…-ghq-shared-0.1.0`, no `/var/lib/ghq-writer`); stibnite runs it without the process-group stop and the maintenance settings; magnetite without the maintenance settings (verify §5) | each host's next deploy or activation |
| A stale `objects/maintenance.lock` in stibnite's `github.com/block/buzz` (2026-08-20, 366 packs), after which automatic maintenance of that copy does nothing; stale `tmp_pack_*` files in `NousResearch/hermes-agent`, `cameronraysmith/atomic`, `can1357/oh-my-pi`, `nixos/nixpkgs` and `schpet/linear-cli`; `/var/log/ghq-writer/writer.log` on stibnite at mode `0644` until rotated (design Risks, verify §5) | a writer-side cleanup change, not yet opened |
| No test exercises a transport over ssh (design D8 boundary, verify §5) | no change or issue holds it yet; carried in the CAM-128 qualifications of `satisfaction.md` |
| The mutation variants `group-writable` and `broken-control` run only on demand (design D6 and its non-goal, verify §5) | no change or issue holds it yet; carried in the CAM-128 qualifications of `satisfaction.md` |
| Consolidating a large copy (45.8 s for `nixpkgs`) runs inside a caller's request with no note (design D9, verify §4) | no change or issue holds it yet; carried in the CAM-128 qualifications of `satisfaction.md` |
| The reference-repository guidance does not describe the writer's waiting note or its log line format (verify §In Review gates) | `hydrate-reference-copy-history`, when its task 3.1 edits `dependency-source-acquisition/SKILL.md` |

