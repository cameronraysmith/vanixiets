# Verification Report

> This file is produced by the `openspec-verify-change` skill after apply completes, to confirm that the
> implementation is consistent with the specs / design / tasks. Any failed check must be returned to its
> corresponding artifact for correction before re-running verify.

**Change**: `serialise-shared-reference-tree-writes` (CAM-128)
**Verified at**: `2026-11-27 01:24` UTC (earlier runs `2026-11-26 23:07` UTC against `3bf86e17a` and `2026-11-27 00:32` UTC against `b718b62ec`)
**Verifier**: `openspec-verify-change` (omp), against `main` at `35aae997c`

Prechecks: the change's commits on `main` are `1d65ad802` (`docs(openspec): propose serialising shared reference tree writes`), `3bf86e17a` (`test(shared-reference-tree): move migration and tags to a second test`), `b718b62ec` (`fix(ghq-shared): stop and log timed-out writer commands without their target`) and `35aae997c` (`fix(ghq-shared): run git maintenance in the foreground, consolidating promisor packs`); the behaviour they record landed in `ebd5daae2` (`fix(ghq-shared): serialise writer requests per repository`).
`tasks.md` holds 17 `- [x]` lines and no `- [ ]`, so both prechecks are positive.

The code was read as merged: `pkgs/by-name/ghq-shared/ghq-writer-handler.py`, `ghq-writer-client.py`, `test_handler.py`, `pkgs/by-name/ghq-sync/ghq-sync.sh`, `modules/vm-tests/shared-reference-tree.nix`, `modules/vm-tests/default.nix` and `modules/{nixos,darwin}/shared-reference-tree.nix`.
No long test was re-run; the evidence is the recorded logs under `logs/` (git-ignored), the magnetite deploy report of 2026-11-26, read-only inspection of magnetite, stibnite and pyrite, and two scratch experiments on stibnite described below.

---

## 1. Structural Validation (`openspec validate --all --json`)

- [ ] All items report `"valid": true`

**Result**:

```text
totals: 81 items, 76 passed, 5 failed
openspec validate serialise-shared-reference-tree-writes --strict: Change 'serialise-shared-reference-tree-writes' is valid
```

None of the five failures is this change:

| Item | Type | Issues |
|---|---|---|
| `compose-hosts-from-cohesive-aspects` | change | no deltas yet |
| `declare-host-user-relations-once` | change | no deltas yet |
| `seam-secrets-away-from-clan-vars` | change | no deltas yet |
| `stand-up-gitea-mq-on-magnetite` | change | requirements over 500 characters |
| `stand-up-nixbot-on-magnetite` | change | requirements over 500 characters |

---

## 2. Task Completion (`tasks.md`)

- [x] All `- [ ]` have been changed to `- [x]`

17 of 17, each with dated evidence, checked against the logs:

| Task | Evidence checked | Missing |
|---|---|---|
| 1.1 split into `accessCases` and `migrationCases` | `modules/vm-tests/shared-reference-tree.nix:638-669` defines both tests from `mkTest`; the six split runs list 30 and 6 subtest lines | the line-by-line comparison of the evaluated scripts is narrated without a log name |
| 1.2 both tests `small` | `modules/vm-tests/shared-reference-tree.nix:638-641`; `logs/srt-split-checks-magnetite-20261126-175401.log` | none |
| 1.3 mutants keep failing | `logs/srt-split-mutant-broken-control-pyrite-20261126-173936.log`, `logs/srt-split-mutant-group-writable-pyrite-20261126-174026.log` | none |
| 2.1 requirements and witnesses | `openspec validate --strict` valid; every quoted case and subtest found | none |
| 2.2 other files naming the test | the hit list in `tasks.md` | none |
| 3.1 three runs each | `logs/srt-split-shared-reference-tree-pyrite-20261126-17*-run{1,2,3}.log`: 35.79, 37.36, 36.58 s; `logs/srt-split-shared-reference-tree-migration-pyrite-20261126-17*-run{1,2,3}.log`: 33.14, 35.10, 32.86 s | none |
| 3.2 changed checks built | `logs/srt-split-checks-magnetite-20261126-175401.log` | none |
| 3.3 hooks | narrated | no log name |
| 4.1 new cases fail against the earlier handler | `logs/cam128-fixes-red-handler-test-darwin-20261126-182513.log`; the cancelled first run `…-181854.log` | none |
| 4.2 process group, 124, reasons, outer guard | `logs/cam128-fixes-green-handler-test-darwin-20261126-182905.log`, `logs/cam128-fixes-ghq-shared-tests-darwin-20261126-183143.log`; mutants `logs/cam128-fixes-mutant-kill-only-darwin-20261126-183152.log` and `logs/cam128-fixes-mutant-sigkill-first-darwin-20261126-183152.log` | none |
| 4.3 spec amended | `openspec validate --strict` valid; the quoted cases are comments in `test_handler.py` | none |
| 4.4 checks, runtime test, hooks | `logs/cam128-fixes-checks-magnetite-20261126-183702.log`, `logs/cam128-fixes-checks-final-magnetite-20261126-183908.log`; `logs/cam128-fixes-shared-reference-tree-pyrite-20261126-183212.log` (35.40 s); `logs/cam128-fixes-prek-20261126-18{3227,3858}.log` | none |
| 5.1 cause of the accumulated packs | the cause and measurements are in design D9; the leftovers it lists match read-only inspection of stibnite's tree (five `tmp_pack_*` copies, `github.com/block/buzz`'s `objects/maintenance.lock` of 2026-08-20) | the copies' measurements are narrated without log names |
| 5.2 new cases fail against the earlier handler | `logs/cam128-maint-red-handler-test-darwin-20261126-194845.log`: 5 → 6 packs with the hook never run, the fetch-written packs fail the mode check, and the slow case's hook (pid 26580) still running after the handler exited; the corrected first run is `…-194616.log` | none |
| 5.3 the three keys in `environment()` | `ghq-writer-handler.py:103-107,199`; `logs/cam128-maint-green-handler-test-darwin-20261126-195051.log` ("all request classes behaved"), `logs/cam128-maint-ghq-shared-tests-darwin-20261126-200809.log`; on x86_64-linux `logs/cam128-maint-checks-magnetite-20261126-200809.log` builds `ghq-shared-test-handler` ("all request classes behaved", `build-exit=0`) | none |
| 5.4 spec, design D8/D9, proposal | `openspec validate --strict` valid; both quoted cases are comments at `test_handler.py:793` and `:840` | none |
| 5.5 checks, runtime test, hooks | `logs/cam128-maint-checks-magnetite-20261126-200809.log`, `logs/cam128-maint-checks-final-magnetite-20261126-201421.log` (`build-exit=0`); `logs/cam128-maint-shared-reference-tree-pyrite-20261126-200827.log` (36.33 s); `logs/cam128-maint-prek-20261126-20{0753,1412}.log` | none |

---

## 3. Delta Spec Sync State

| Capability | Sync status | Notes |
|---|---|---|
| `shared-reference-tree-interface` | pending sync | 8 ADDED, 1 MODIFIED (`Each property is backed by evidence that can fail`); none of the eight is in `openspec/specs/shared-reference-tree-interface/spec.md` yet |

---

## 4. Design / Specs Coherence Spot Check

### Findings of earlier runs and what closed them

1. First run, 2026-11-26 23:07 UTC: a command that outlasted 3600 s raised `subprocess.TimeoutExpired`, which nothing caught; its traceback, holding the `ghq get` argv and so the target with any credentials, went to the writer's log, with no exit line and no reply.
   Closed on 2026-11-26 by `b718b62ec`: commands run through `run`, a timeout becomes `TimedOut` carrying only the program and subcommand, `serve` answers it with exit 124, and `main` catches any other exception and logs it with the target replaced.
2. First run: the lock requirement said requests for different repositories never wait for each other, while the lock name case-folds the path.
   Closed on 2026-11-26 by `b718b62ec`: the requirement says paths differing only in letter case share a lock (design D7), with its own scenario.
3. Second run, 2026-11-27 00:32 UTC: the writer's git ran automatic maintenance with git's default `maintenance.autoDetach=true`, so after a fetch `git maintenance run --auto --detach` left the command's process group and kept writing the repository after the lock was released, out of reach of a timed-out command's stop.
   Shown on stibnite in a scratch repository: the fetch exited in 0.04 s and its group was empty 0.3 s later while the detached maintenance, parent 1 and a group of its own, was still running.
   Closed on 2026-11-26 by `35aae997c`: `environment()` adds `maintenance.autoDetach=false`, `gc.autoDetach=false` and `maintenance.strategy=gc` (`ghq-writer-handler.py:103-107,199`), with the requirement "Git's automatic maintenance is part of the request that starts it" and two cases.

### Requirements now

| Requirement | Code | Witness and recorded run | Result |
|---|---|---|---|
| The writer acts on one repository at a time | key `hashlib.sha256(session.repo.casefold())` (`:293`); lock held from `hold` until `os.close(held)` (`:605`), with maintenance now inside the commands it covers; lock file `0o600` under umask `0027`; `/var/lib/ghq-writer` `0700` writer:writer by tmpfiles (`modules/nixos/shared-reference-tree.nix:118`) and activation (`modules/darwin/shared-reference-tree.nix:200`) | cases "Two updates of one repository…", "Updates of two repositories run side by side", "Every spelling…" (including `O/Serial-A` finding the lock held); VM subtest "a request takes its repository's lock…" passed in every recorded run up to `logs/cam128-maint-shared-reference-tree-pyrite-20261126-200827.log`; magnetite `drwx------ ghq ghq` | PASS |
| A request waits a bounded time for its repository, and only a caller that asks is told | `LOCK_TIMEOUT = 3600`, not overridden by either module; `Busy` exit 75 naming repository and holder; note only for `session.notes`; the client prints notes at once | cases "Two updates of one repository…", "A request still waiting when the lock timeout passes…"; magnetite overlapping updates of 2026-11-26 22:29:50 | PASS |
| The writer refuses a get that names no directory under the shared root | `clone_path` returns `None` for a bare name or a path resolved outside the root; `repository` raises `Refused`, exit 2 before any lock | cases "Every spelling…" and "Tag fetches act only on a clone inside the root…" | PASS |
| The writer logs each request without its target | `Session.log` (`:517-524`), `label` (`:317-325`), `describe` (`:542-551`), `TimedOut` (`:602-603`), the guard in `main` (`:627-632`); see the leak review below | cases "Log lines…", "A command that fails…", "A get whose clone outlasts…", "A git step that outlasts…", "An unexpected error whose message holds the target…" | PASS |
| A command that outlasts its limit is stopped with all it started | `run` (`:358-367`) starts each command with `process_group=0`; `stop` (`:338-355`) sends `SIGTERM` to the group, waits up to 10 s, then `SIGKILL`; maintenance now runs in the foreground, in that group | cases "A get whose clone outlasts…", "A git step that outlasts…" and "A timed-out command's stop ends the maintenance it started" (3 s limit, the hook sleeping 60 s in gc is not running afterwards, exit 124); the kill-only and SIGKILL-first mutants fail the first two; against the earlier handler the third fails with the hook still running | PASS |
| Git's automatic maintenance is part of the request that starts it | the three keys in the command-scope `GIT_CONFIG_*` of `environment()`, which outrank a repository's own configuration and are inherited by every git the request starts (below) | case "Auto maintenance after an update runs gc in the foreground, inside the request": packs from 5 to at most 2 before the handler exits, the hook ran and is not running, both hydrated blobs present with `gc.pruneExpire=now` and `gc.reflogExpireUnreachable=now`, the new pack files carry no permission for others and are group-readable, the lock is free; case "A timed-out command's stop ends the maintenance it started"; both fail against the earlier handler (task 5.2) | PASS |
| A caller that disconnects does not stop its request | `send` catches `OSError`, sets `gone`, logs once; the lock is released when the operation ends, no later than the handler's exit | case "A caller that disconnects…" | PASS |
| Each runtime test of the shared tree fits its size class | `testSizes.vmTests` both `small`; `modules/vm-tests/default.nix:47,49` | `test-size-classes` built; recorded runs 32.86 to 37.36 s of 60 s | PASS |
| Each property is backed by evidence that can fail (MODIFIED) | one node through `mkTest`; the control; module assertions | broken-control fails at the control subtest; stibnite inspected after activation | PASS |

Whether the maintenance keys reach every git a request starts, and other ways a process could outlive the lock, as of git 2.56.0:

- The keys travel as `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_n`/`GIT_CONFIG_VALUE_n` in the environment `run` passes to the command, not as argv, so every descendant inherits them unless it rewrites its environment.
- `ghq` passes its environment to git: on stibnite, `ghq get -u` (the writer's `ghq-1.12.0`) with those variables and `GIT_TRACE=1` traced `git pull` → `git fetch` → `git maintenance run --auto --no-quiet --no-detach`; without them the same fetch traces `--detach`.
- `ghq-sync` (`pkgs/by-name/ghq-sync/ghq-sync.sh`) neither sets nor clears `GIT_CONFIG_*`; its one `env -i` is in a command it prints for an operator (`:360`), not one it runs. Its explicit `git gc --quiet` after `--full` (`:219`) is not `--auto` and does not detach.
- `fetch.writeCommitGraph` writes the commit graph inside the fetch process; it starts no daemon.
- No credential helper is configured: system and global configuration are off (`GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null`), and no repository configuration in stibnite's tree names `credential`, `fsmonitor`, `autoDetach` or a `[maintenance]` section, and no clone there has a hook other than samples (read-only `rg` and `find` over `/var/lib/ghq/*/*/*/.git`).
- A process could still leave the group through repository configuration only the writer can write: a `core.fsmonitor=true` (darwin's built-in daemon detaches) or a hook that daemonizes. Neither exists, and design D8's boundary states that a process moving itself to another group escapes the signal.

Leak review, unchanged since `b718b62ec` apart from line numbers: every command goes through `run` (`:358-367`), whose output goes to the reply; the log names a failure by `label` only (`:606-608`); a timeout carries `label` only; `main` catches any other exception (`:627-632`) and logs `describe`, which replaces the exact target and `://…@` userinfo; nothing before that guard has seen the request; the lock-open failure carries `strerror`, the repository and the lock directory.

**Drift warnings** (non-blocking):

- The witness of "A waiting caller that does not accept notes" is the timeout case; no case has a one-line caller that waits and then succeeds, though the code path is the same.
- The scenario "Spellings of one repository" lists an `https` URL "with or without credentials"; the case tests one with credentials.
- `describe` replaces the target only verbatim and a `://…@` userinfo; an unexpected exception quoting a transformed target would keep it. No such exception is raised by the code today.
- Between consolidations, a fetch writes its pack's `.promisor` file with mode `0600` (task 5.2); readers test only that file's existence. The consolidation case checks only the packs gc writes.
- A maintenance that consolidates a large clone, 46 s for `nixpkgs` (design D9), runs inside the caller's request with no note.

---

## 5. Implementation Signal

- [x] No unstaged files in the worktree for this change: the code and artifacts are on `main` up to `35aae997c`, and this file is committed on its own
- [x] All related commits have been pushed: `35aae997c` is `origin/main`

**Commit range**: `ebd5daae2`, then `1d65ad802..3bf86e17a`, then `b718b62ec`, then `35aae997c`

Hosts, read-only at 01:20 UTC on 2026-11-27:

| Host | Writer |
|---|---|
| magnetite | `system-296-link`; `ghq-writer@.service` runs `/nix/store/h6zhvzzx…-ghq-shared-0.1.0`: lock and process-group stop, without the maintenance keys; `/var/lib/ghq-writer` `drwx------ ghq ghq` |
| stibnite | `org.vanixiets.ghq-writer` runs `/nix/store/dzn81a69…-ghq-shared-0.1.0`: lock, without the process-group stop and the maintenance keys; `/var/lib/ghq-writer` `drwx------ _ghq _ghq` |
| pyrite | `system-130-link`; `ghq-writer@.service` runs `/nix/store/rrlira2i…-ghq-shared-0.1.0`, the handler before the lock; no `/var/lib/ghq-writer` |

Open items, not failures:

- Each host runs this handler only after its next deploy or activation, as the table shows.
- A maintenance killed with `SIGKILL` (the 10 s grace exceeded, a host crash, a service manager's kill) leaves `objects/maintenance.lock`, after which automatic maintenance of that copy does nothing; stibnite's `github.com/block/buzz` holds one, dated 2026-08-20 (design D9, accepted risk).
- Stale `tmp_pack_*` files sit in five copies on stibnite, all under `github.com`: `NousResearch/hermes-agent`, `cameronraysmith/atomic`, `can1357/oh-my-pi`, `nixos/nixpkgs` and `schpet/linear-cli`; gc removes them in a copy it consolidates.
- `/var/log/ghq-writer/writer.log` on stibnite is mode `0644`; the newsyslog entry's mode `640` applies when the log is rotated.
- No test exercises a transport over ssh.
- The mutation variants `group-writable` and `broken-control` run only on demand.

---

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

- [x] No files, or any existing files are legitimate residue from before schema installation

`ls docs/superpowers/specs/*.md` printed nothing.

---

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

`plan.md` has no `[~]` rows, so this section is blank (PASS).

---

## 8. Designation Lint and Discharge Coherence

8a: no delta of this change is tagged `behavioral`; the lint has nothing to resolve.

8b:

| Requirement | Discharged by (S) | Under (W) | Status |
|---|---|---|---|
| The writer acts on one repository at a time | `hold`, `repository`, the lock directory in both modules, maintenance in the foreground | none named: `flock` exclusion is the operating system's documented behaviour (design D2) | discharged |
| A request waits a bounded time…, and only a caller that asks is told | `hold`, `wait_for`, the second-line option, the client | A36 bounds the trust boundary | discharged |
| The writer refuses a get that names no directory under the shared root | `clone_path`, `repository` | A35 | discharged |
| The writer logs each request without its target | `Session.log`, `label`, `describe`, `TimedOut`, the guard in `main` | none | discharged |
| A command that outlasts its limit is stopped with all it started | `run`, `stop`, `MAINTENANCE_POLICY` | none named; no process of git, `ghq` or `ghq-sync` leaves the group under the writer's configuration | discharged |
| Git's automatic maintenance is part of the request that starts it | `MAINTENANCE_POLICY` in `environment()` | none named; git's handling of promisor objects in `repack` and `prune` (design D9) | discharged |
| A caller that disconnects does not stop its request | `Session.send` | none | discharged |
| Each runtime test of the shared tree fits its size class | `testSizes.vmTests`, `modules/vm-tests/default.nix` | none | discharged |
| Each property is backed by evidence that can fail | the two VM tests, the mutants, module assertions, stibnite inspection | none | discharged |

8c: no interface requirement names world state the writer cannot observe.

---

## Overall Decision

- [ ] (pass) PASS — may proceed to finishing-a-development-branch and archive
- [x] (warn) PASS WITH WARNINGS — may proceed to subsequent steps but note: the five drift warnings in section 4 and the open items in section 5; tasks 1.1, 3.3 and 5.1 rest partly on narrated evidence without a log name
- [ ] (fail) FAIL — return to the failed artifact, correct it, then re-run verify

The three findings of the earlier runs are closed by `b718b62ec` and `35aae997c`, and every requirement and scenario holds in the code and in its recorded witness.

**Next step**:

The code-review and docs-review gates of In Review, then sync and archive.

---

## In Review gates (2026-11-27)

- **Code review: accepted.** The three verification runs above (2026-11-26 23:07, 2026-11-27 00:32 and 01:24 UTC) stand as the code review: each read the merged writer, its tests and the modules against the spec, and the findings of the first two are closed by `b718b62ec` and `35aae997c`. No separate review was run.
- **Documentation: accepted as it is**, with one follow-up: the reference-repository guidance, `modules/home/ai/plugins/version-control-and-forge/.apm/skills/dependency-source-acquisition/SKILL.md`, says nothing of the writer's waiting note (`ghq-writer: waiting up to 3600 s for <repository>, in use by another request (<holder>)`) or of the writer's log line format; a paragraph on both is to be added when the change `hydrate-reference-copy-history` edits that file (its task 3.1).

`review_round` stays 0: neither gate re-queued the change.
