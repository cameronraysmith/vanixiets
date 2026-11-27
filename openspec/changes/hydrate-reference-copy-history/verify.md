# Verification Report

> This file is produced by the `openspec-verify-change` skill after apply completes, to confirm that the
> implementation is consistent with the specs / design / tasks. Any failed check must be returned to its
> corresponding artifact for correction before re-running verify.

**Change**: `hydrate-reference-copy-history` (CAM-136)
**Verified at**: `2026-11-27 10:10` UTC, the second run (the first, `2026-11-27 08:50` UTC against `d901fd6b`, is recorded in §4)
**Verifier**: `openspec-verify-change` (omp), against `ce9e492d` (`nzvnkwwu`, `fix(ghq-shared): hydrate what every moved branch ref gained, and harden the history fetch`)

Prechecks: `tasks.md` holds 18 `- [x]` lines and 2 `- [ ]` (4.1 and 4.2); the change's commits are on `main` up to the first run's report, and `ce9e492d` is its remedy, not yet on `main`.
The code was read at `ce9e492d`: `pkgs/by-name/ghq-shared/ghq-writer-handler.py`, `test_handler.py`, `ghq-shared-migrate.py`, `pkgs/by-name/ghq-sync/ghq-sync.sh`, `modules/system/shared-reference-tree.nix` and `.test.nix`, `modules/{nixos,darwin}/shared-reference-tree.nix`, `modules/vm-tests/shared-reference-tree.nix`, the skill and the agent-context fragment; line numbers below are of those files there.
Nothing of this change is deployed to any host.
No test was re-run.
The evidence is the logs the remedy recorded (`logs/cam136-fix-*`, `logs/cam136-trim-*`), nixbot's records in the telemetry store, read-only counts over stibnite's tree, and scratch experiments under `/tmp/cam136v2` with git 2.56.0, recorded as `logs/cam136-reverify-*-20261127-050626.log` with their scripts.

---

## 1. Structural Validation (`openspec validate --all --json`)

- [ ] All items report `"valid": true`

**Result**:

```text
totals: 84 items, 81 passed, 3 failed
openspec validate hydrate-reference-copy-history --strict: Change 'hydrate-reference-copy-history' is valid
```

None of the three failures is this change: `compose-hosts-from-cohesive-aspects`, `stand-up-gitea-mq-on-magnetite` and `stand-up-nixbot-on-magnetite`.

---

## 2. Task Completion (`tasks.md`)

- [ ] All `- [ ]` have been changed to `- [x]`

18 of 20; 4.1 and 4.2 wait on a deploy (§5).
Tasks 1.1 to 3.1 are as the first run found them (§4, first run).

| Task | Evidence checked | Missing |
|---|---|---|
| 5.1 ref snapshot, walk of moved refs | `logs/cam136-fix-handler-red-darwin-20261127-041419.log`, `logs/cam136-fix-handler-red-x86-magnetite-20261127-042419.log` (fail before the remedy); `logs/cam136-fix-handler-green-darwin-20261127-041638.log`, `logs/cam136-fix-handler-green-x86-magnetite-20261127-042711.log` ("all request classes behaved", `build-exit 0`) | a ref moving to a commit already present, and a ref name that is not UTF-8 (findings N1, N2) |
| 5.2 outcome on the session | same builds, case "A command after the history fetch that outlasts the command timeout" | none |
| 5.3 recorded filter | same builds, case "The history fetch passes the filter the clone records" | none |
| 5.4 `OSError`, standard input | same builds | other exception classes (finding N2) |
| 5.5 `sharedReferenceTreeTransportGaps` | `logs/cam136-fix-refuses-transport-eval-20261127-042852.log`, `logs/cam136-fix-assertions-20261127-042901.log`, `logs/cam136-fix-changed-checks-magnetite-20261127-042950.log` | the link and case gaps of finding N3 |
| 5.6 migration of an administrator's own file | `logs/cam136-fix-red-pyrite-shared-reference-tree-migration-20261127-042603.log` (fails before), green runs below; `logs/cam136-fix-mutant-pyrite-shared-reference-tree-migration-20261127-043341.log` | none |
| 5.7 darwin log step and directory refusal | `logs/cam136-fix-darwin-log-mode-scratch-20261127-042054.log`, `logs/cam136-fix-darwin-activation-scratch-20261127-041530.log` | the race of the absent-log branch and of the directory test (§4 warnings) |
| 5.8 text | `logs/cam136-fix-openspec-validate-20261127-043726.log`, `logs/cam136-fix-prek-final-20261127-043726.log` | `tasks.md`'s header still gives the handler check's nixbot median as 39 s (finding N5) |

Runtime tests at the remedy, class `small` (60 s): `shared-reference-tree` 38.58, 38.50, 42.20 s; `shared-reference-tree-migration` 37.37, 43.34, 36.58 s (`logs/cam136-fix-green-run{1,2,3}-pyrite-*.log`).
Margins under the limit, 17.8 and 16.7 s, are wider than the ranges, 3.7 and 6.8 s, so both keep the margin their class needs.

---

## 3. Delta Spec Sync State

| Capability | Sync status | Notes |
|---|---|---|
| `shared-reference-tree` | needs sync | 3 ADDED |
| `shared-reference-tree-interface` | needs sync | 14 ADDED |

---

## 4. Design / Specs Coherence Spot Check

### First run, 2026-11-27 08:50 UTC, against `d901fd6b`, and what closed each finding

| First-run finding | Now |
|---|---|
| 1. The behavioral requirement claimed commits no walk reached: tags at depth 1, and the commits a deepen moved `origin/<branch>` to | Closed. The walk covers every moved ref under `refs/heads` and `refs/remotes` (`ghq-writer-handler.py:616-640`); a `get` with tags fetches the tracked branches before the walk (`:750-764`); the requirement now covers the branches' history and states the tag exception, as do the skill, the fragment and the usage text. The scratch deepen of a copy three commits behind now leaves none of the three unreadable (`logs/cam136-reverify-deepen-tip-scratch-20261127-050626.log`). |
| 2. A timeout after the walk dropped the `history=` token and the status line | Closed: the outcome is on the session as the walk returns (`:760`, `:777`), and `fail` carries its line (`:818-824`) |
| 3. The transport assertion accepted includes that reopen a transport | Partly closed: unconditional, same-condition and broader-`gitdir:` includes are rejected (`modules/system/shared-reference-tree.nix:94-150`); finding N3 lists what still passes |
| 4. The history fetch used a constant filter and wrote one into a promisor copy recording none | Closed: the fetch passes the recorded filter (`:701`); a copy recording none gets no listing or fetch (`:720-724`) |
| 5. An `OSError` starting git in the walk failed the request; revisions went on argv | Closed for `OSError` (`HISTORY_ERRORS`, `:602`) and for argv (`git log --stdin`, `:682`; the 300-ref scratch walk passed at most 12 arguments and 12,383 bytes on standard input); not for other exception classes (finding N2) |
| 6. A migrated tree's own `.lazygit.yml` replaced the provisioned one until activation | Closed: it goes to `~/ghq.pre-shared-<date>` (`ghq-shared-migrate.py:703-705`), the provisioned file comes back, and rollback reverses both; the migration subtest compares the root after each refused apply, migration and rollback |
| Warning: the darwin log step's `chown` and `chmod` followed a link | Closed: one descriptor opened with `O_NOFOLLOW`, then `fstat`, `fchown`, `fchmod` (`modules/darwin/shared-reference-tree.nix:43-59`) |
| Warning: `install` onto a directory at `.lazygit.yml` exited 0 | Closed for a directory standing there at activation (`:278-281`); a race remains (warnings below) |
| Warning: the skill's history and failure-line wording | Closed |

### Findings of this run

- [x] **FAIL N1, scenarios "An update of a full clone" and "A request runs no history walk"**: a request that brings in no commit must run no walk and log no `history=` token.
  `walk_history` counts a ref as having gained its new commit whenever its value changed and that value was no old ref's (`ghq-writer-handler.py:630-631`), so a ref moved to a commit already present starts a walk.
  Scenario: upstream force-resets `main` to an ancestor the copy holds, and `ghq-sync -u` (whose `git pull --ff-only` then has nothing to do) answers `hydrated history: <path> (0 objects fetched)` and logs `history=hydrated:0`; shown in a scratch copy holding the whole branch (`logs/cam136-reverify-ref-snapshot-scratch-20261127-050626.log`).
  A new upstream branch at an existing commit, in a copy fetching every branch, does the same.
  Harmless in effect, but the two scenarios say otherwise.

- [x] **FAIL N2, `A failed history fetch leaves the request's outcome as it was`** ("When reading the clone's refs or shallow boundaries … fails …"), and the behavioral scenario "Making the changes readable fails".
  `branch_refs` decodes `for-each-ref`'s output as UTF-8 (`:598`), and `history_before` catches only `HISTORY_ERRORS` (`:602-613`); a ref name that is not UTF-8, which git allows, raises `UnicodeDecodeError` from `run_get` (`:743`) before any command runs, so the request ends with 70 and the update never happens.
  Shown with a packed ref `refs/remotes/origin/caf\xe9` in a scratch blobless copy (same log); darwin's file system refuses the name as a loose ref, the Linux hosts' do not; whether the forges serve such a branch was not determined.
  The same applies to any exception outside `HISTORY_ERRORS` raised while reading refs or walking.

- [x] **FAIL N3, `Participating accounts' git refuses every transport beneath the shared root` and `Evaluation rejects an include that reopens a transport beneath the shared root`**.
  `includeReachesRoot` (`modules/system/shared-reference-tree.nix:94-116`) judges a literal `gitdir:` path by text against the root's forms, but git matches the path a repository is reached by as well as its resolved one, so a literal path through a link into the tree applies beneath the root.
  `~/ghq` is such a link, made by the module itself: in a scratch tree, an include under `gitdir:<home>/ghq/`, or under `gitdir:<home>/`, setting `protocol.file.allow = always` reopened the transport for `git show` run from `~/ghq/…` (`Unable to create temporary file …/tmp_pack_*`), while `transportGaps` returned `[]` for both (`logs/cam136-reverify-gitdir-link-and-case-scratch-20261127-050626.log`, `logs/cam136-reverify-transport-gaps-eval-20261127-050626.log`); the test case `testUnrelatedGitdir` (`gitdir:/Users/someone/projects/`) is the same shape.
  Git's section names are case-insensitive: `contents.Protocol.https.allow` in an include, or `settings.Protocol.https.allow`, reopens the transport (scratch, `[Protocol "file"]`) and returns `[]` (`:125`, `:147` read only `protocol`).
  Home Manager's `programs.git.settings` may be a list of fragments (`either gitIniType (listOf gitIniType)`); `git.settings.protocol or { }` is then `{ }` (`:147`), and a fragment setting `protocol.https.allow` returns `[]`.
  No participant has any of these today.

- [x] **FAIL N4, `Tag commits fetched at depth 1 stay unhydrated`** ("The writer SHALL NOT walk or hydrate a tag's commit").
  A tag's commit fetched at depth 1 that upstream later merges into the branch is reached by the branch's gained range, which excludes only the old branch refs (`:630-635`), and is walked as a shallow root: its whole tree's missing blobs are fetched.
  Shown in scratch: tag `t` on an unmerged branch fetched at depth 1, upstream merges that branch, and the walk's range included `t` and fetched its missing blob; `git --no-lazy-fetch show t` then succeeded (`logs/cam136-reverify-tag-merged-scratch-20261127-050626.log`).
  The commit is by then a branch commit, so this is more hydration than promised, bounded by the limit; the requirement's wording, or the exclusion, needs to say which holds.

- [x] **FAIL N5, repository rule: `checks.x86_64-linux.package-ghq-shared-test-handler` is declared `small` (`modules/checks/package-tests.nix:88`, "median 39 s, slowest 75 s, all 6 runs 2026-10-21..2026-11-11")**.
  nixbot's uncached runs (`devloop.ci_attribute`, `logs/cam136-reverify-handler-check-runs-20261127-050626.log`) within the last 30 days are 39 s (11-07), 75 s (11-11), 151 s (11-24), 3 s and 3 s (11-25).
  By the rule's letter (runs of at least 1 s, median over 30 days) the median is 39 s; the two 3 s records cannot be runs of a script that took 80 to 95 s on magnetite (`logs/cam136-fix-handler-timing-x86-magnetite-20261127-04*.log`, `logs/cam136-trim-handler-red-green-timing-x86-magnetite-20261127-044936.log`: 80.3 to 81.2 s at `trunk()`, 85.2 to 95.2 s with the remedy), and without them the median of the three real runs is 75 s, past the 60 s limit.
  Whether the 3 s records built anything was not determined.
  Either way the check's slowest recent run is 151 s and every local run since 2026-11-24 exceeds 60 s; the class needs re-reading from fresh nixbot runs once the remedy lands, and either `medium` with a reason or a split, as `references/test-sizes.md` says for a check that outgrows its class; the darwin check is already `medium`.

### Requirements

| Requirement | Result |
|---|---|
| A refreshed or deepened reference repository shows what each commit it gained changed (behavioral) | FAIL (N2) |
| A tag's commit fetched without its history is readable once requested (behavioral) | PASS (VM subtest: `ghq-sync --hydrate t-unmerged`, then `git show`) |
| A read that needs content the reference tree lacks fails at once (behavioral) | PASS at the declared configuration; N3 is where evaluation would not catch one that defeats it |
| An update makes every commit it brought in readable as a diff | FAIL (N1) |
| Tag commits fetched at depth 1 stay unhydrated | FAIL (N4) |
| The history fetch keeps the clone's partial-clone filter | PASS |
| A deepen makes every commit it brought in readable as a diff | PASS |
| The writer bounds the history it makes readable | PASS |
| A failed history fetch leaves the request's outcome as it was | FAIL (N2) |
| The history walk gives git its lists on standard input | PASS |
| The writer's exit log line names what the history fetch did | FAIL (N1) |
| A first acquisition fetches nothing more than before | PASS |
| Participating accounts' git refuses every transport beneath the shared root | FAIL (N3) |
| Evaluation rejects an include that reopens a transport beneath the shared root | FAIL (N3) |
| lazygit fetches nothing at start-up beneath the shared root | PASS |
| Migration keeps the provisioned .lazygit.yml over an administrator's own | PASS |
| A revision's diff is readable once the revision and its parents are hydrated | PASS |

### The remedy, probed

The ref snapshot (`branch_refs`, `:592-598`) reads `refs/heads` and `refs/remotes` once before the request's first fetch and once after its last branch-moving command; `refs/remotes/origin/HEAD` appears with its target's commit and adds nothing of its own.
A ref deleted during a request drops out of the second snapshot and gains nothing; a force-moved ref's new commits are walked from its new tip, excluding every commit any old ref reached; a ref moved backwards is N1.
A tags-only `get` of a shallow copy now fetches the tracked branches with `git fetch --no-tags origin` before the walk (`:751-754`), so what `origin/<branch>` gained is hydrated and the depth-1 tag commits are not.
An update that moves nothing returns `None` from `walk_history` and logs no token.
With 300 branches each gaining a commit in a copy fetching every branch, the snapshot and the walk grew with the ref count only on standard input (at most 12 arguments, 12,383 bytes), the walk took 0.1 s, and the limit applied to the request as a whole: at `historyLimit` 50 nothing was fetched for any branch, the checked-out one included.
Of stibnite's 603 promisor copies, 4 fetch every branch, the most with 65 remote-tracking refs (`github.com/openzfs/zfs`).
Every path after the walk now carries its outcome: a later timeout through `fail` (`:818-824`), an unexpected exception through `main`'s `fail`, and the normal reply through the results.
The filter rule reads `remote.origin.partialclonefilter` with `git config --get` (`:720`): exit 1 means none and skips listing and fetch, any other failure raises `HistoryFailed`.
The read side's other probes of the first run (`gitdir:` forms, the overrides the trust boundary covers, what readers can still do) are unchanged by the remedy, whose trust boundary now names a hand-written `~/.gitconfig` and path includes.
Every text that describes the hydrated range states the tag exception: the handler's docstring, `ghq-sync`'s usage, the skill, the agent-context fragment and both delta specs.

**Drift warnings** (non-blocking):

- The absent-log branch is unchanged: between `[ ! -e ]` and `install` (`darwin/shared-reference-tree.nix:258-260`), a log launchd creates is unlinked by `install`, and the lines a handler writes to it are lost (the first run's `logs/cam136-verify-bsd-install-scratch-20261127-034842.log`); whether `install` creates its file with `O_EXCL` after unlinking, which decides whether a link put there in between is followed, was not determined.
  The descriptor step itself refuses a link to a file or a directory (`ELOOP`), a directory, a hard link, a FIFO and an absent path, exiting 0 with a message each time (`logs/cam136-reverify-log-mode-script-scratch-20261127-050626.log`; run as a non-root account, so the change of owner was not exercised).
- The `.lazygit.yml` test and the `install` after it (`:278-282`) are two steps on a path in a directory the writer owns: a link to a directory put there between them makes root write `<store name>-lazygit.yml`, owned by the writer, into the directory it names. Which directories would make that an escalation was not determined; `/etc/paths.d`, every file of which `path_helper` reads for login shells, is one candidate.
- `transportGaps` reads neither `programs.git.iniContent`, an internal Home Manager option a participant can still set, nor an include's nested `include.path`; the trust boundary names path includes.
- `tasks.md`'s header still gives the handler check as "class `small`, nixbot median 39 s".

---

## 5. Implementation Signal

- [ ] No unstaged files in the worktree for this change: the remedy is `ce9e492d`; this report is on its own commit, a child of it
- [ ] All related commits have been pushed: `ce9e492d` is not yet on `main`

**Commit range**: `aab117563`, `3ff10f60`, `6c53ca38`, `d901fd6b`, the first run's report, then `ce9e492d`

Open items, which only a deployed host can show:

- 4.1 on stibnite: the update of a blobless copy behind its upstream, `--no-lazy-fetch show` of each commit it brought in, lazygit under a terminal with `GIT_TRACE` and no `git fetch`, `git show` outside the range printing `transport 'https' not allowed` and no `Permission denied`, and every alert since the deploy.
- 4.2: `prek run --files` on the changed files.
- On each host after its deploy: the `history=` tokens for real updates, and the lock-hold time of the first updates of large copies and of the four copies fetching every branch.
- On stibnite after activation: `writer.log` `0640 _ghq:_ghq` set by the descriptor step, `.lazygit.yml` present `0640`, and the Omnigent worker's git configuration carrying both includes.
- On magnetite and pyrite: `.lazygit.yml` from the tmpfiles rule, and each participant's include with `protocol.allow = never`.
- The handler check's class, from nixbot's first uncached runs of the remedy (N5).

---

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

- [x] No files, or any existing files are legitimate residue from before schema installation

`ls docs/superpowers/specs/*.md` printed nothing.

---

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

There is no `plan.md`, so no row is marked `[~]`.
The deferred checks are tasks 4.1 and 4.2 (§5); the runtime tests cover what 4.1 checks at the interface on NixOS, but not lazygit's start-up on a host, which only the design's scratch run and 4.1 show.

---

## 8. Designation Lint and Discharge Coherence

8a: the behavioral delta uses reference repository, reference tree, participating account, writer, acquisition request, commit and history, each a row of `openspec/specs/world-assumptions/spec.md`; "file contents", "branch" and "tag" resolve to no row.

8b:

| Requirement | Discharged by (S) | Under (W) | Status |
|---|---|---|---|
| A refreshed or deepened reference repository shows what each commit it gained changed | the update, deepen, bound, filter, failure, stdin, log-line and first-acquisition requirements of the interface delta | none named | discharged but for N2 |
| A tag's commit fetched without its history is readable once requested | `Tag commits fetched at depth 1 stay unhydrated`; `A revision's diff is readable once the revision and its parents are hydrated` | none named | discharged (N4 makes more readable, not less) |
| A read that needs content the reference tree lacks fails at once | `Participating accounts' git refuses every transport beneath the shared root`; `Evaluation rejects an include that reopens a transport beneath the shared root` | none named | discharged at the declared configuration; N3 is where evaluation would pass one that defeats it |

8c: the interface delta names only what the hosts' configuration, the writer and git expose; the behavioral delta names no git command, file or setting.

---

## Overall Decision

- [ ] (pass) PASS — may proceed to finishing-a-development-branch and archive
- [ ] (warn) PASS WITH WARNINGS — may proceed to subsequent steps but note: …
- [x] (fail) FAIL — return to the failed artifact, correct it, then re-run verify

Five of the first run's six findings are closed and the sixth partly; this run's findings hold against `ce9e492d`: a ref moved to a commit already present starts a walk (N1), a ref name that is not UTF-8 fails the request before its update (N2), evaluation passes includes through a link into the tree, with a differently cased section, or in list-form settings (N3), a depth-1 tag commit later merged is hydrated (N4), and the handler check outgrows `small` on every real run since 2026-11-24 (N5).
Tasks 4.1 and 4.2 remain open.

**Next step**:

Correct the code or the spec for each finding, then re-run verify; CAM-136 stays In Progress.
