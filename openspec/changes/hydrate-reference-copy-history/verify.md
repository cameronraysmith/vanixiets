# Verification Report

> This file is produced by the `openspec-verify-change` skill after apply completes, to confirm that the
> implementation is consistent with the specs / design / tasks. Any failed check must be returned to its
> corresponding artifact for correction before re-running verify.

**Change**: `hydrate-reference-copy-history` (CAM-136)
**Verified at**: `2026-11-27 10:45` UTC, the third run (the first at `08:50` UTC against `d901fd6b` and the second at `10:10` UTC against `ce9e492d` are recorded in §4)
**Verifier**: `openspec-verify-change` (omp), against `cd4dd583` (`skwtzotn`, `fix(ghq-shared): walk only what a request gained, and guard every history phase`)

Prechecks: `tasks.md` holds 25 `- [x]` lines and 2 `- [ ]` (4.1 and 4.2); `ce9e492d` is on `main`, `cd4dd583` is not.
The code was read at `cd4dd583`: `pkgs/by-name/ghq-shared/ghq-writer-handler.py`, `test_handler.py`, `test_handler_history.py`, `handler_fixtures.py`, `test-handler.nix`, `package.nix`, `modules/checks/package-tests.nix`, `modules/system/shared-reference-tree.nix` and `.test.nix`, `modules/{nixos,darwin}/shared-reference-tree.nix`, `modules/darwin/omnigent-host.nix`, `modules/home/development/repository-acquisition.nix`, the skill, the agent-context fragment and `ghq-sync`'s usage text; line numbers below are of those files there.
Nothing of this change is deployed to any host, and no test was re-run.
The evidence is the remedy's logs (`logs/cam136-r3-*`), the systemd 262 source the pinned nixpkgs builds, and scratch experiments under `/tmp/cam136v3` with git 2.56.0, recorded as `logs/cam136-r3verify-*` with their scripts.

---

## 1. Structural Validation (`openspec validate --all --json`)

- [ ] All items report `"valid": true`

**Result**:

```text
totals: 84 items, 82 passed, 2 failed
openspec validate hydrate-reference-copy-history --strict: Change 'hydrate-reference-copy-history' is valid
```

Neither failure is this change: `stand-up-gitea-mq-on-magnetite` and `stand-up-nixbot-on-magnetite`.

---

## 2. Task Completion (`tasks.md`)

- [ ] All `- [ ]` have been changed to `- [x]`

25 of 27; 4.1 and 4.2 wait on a deploy (§5).
Group 6, the remedies of the second run, is checked against these logs: the history check fails against `nzvnkwwu` on the snapshot, walk and non-UTF-8 cases (`logs/cam136-r3-handler-red-darwin-20261127-052552.log`) and both checks pass at the remedy (`logs/cam136-r3-handler-fix-darwin-20261127-052757.log`: 1m35s and 1m02s; `logs/cam136-r3-magnetite-red-green-timing-20261127-052541.log`: 46.9 s and 13.3 to 13.8 s); `logs/cam136-r3-magnetite-final-checks-20261127-053400.log` (`build-exit 0`); `logs/cam136-r3-darwin-descriptor-steps-scratch-20261127-052125.log`; `logs/cam136-r3-vmtests-eval-pyrite-20261127-053054.log`; `logs/cam136-r3-prek-20261127-052602.log`.
Runtime tests at the remedy: `shared-reference-tree` 37.20, 41.73, 39.19 s and `shared-reference-tree-migration` 39.07, 39.63, 35.92 s (`logs/cam136-r3-green-run{1,2,3}-pyrite-*.log`); margins under 60 s of 18.3 and 20.4 s against ranges of 4.5 and 3.7 s.

---

## 3. Delta Spec Sync State

| Capability | Sync status | Notes |
|---|---|---|
| `shared-reference-tree` | needs sync | 3 ADDED |
| `shared-reference-tree-interface` | needs sync | 17 ADDED |

---

## 4. Design / Specs Coherence Spot Check

### First run, 2026-11-27 08:50 UTC, against `d901fd6b`

Six findings: commits no walk reached (tags at depth 1, a deepen's tip commits), a timeout after the walk dropping its log token and status line, an assertion passing includes that reopen a transport, a constant filter written into a promisor copy recording none, an `OSError` or argv limit failing the request, and an administrator's own `.lazygit.yml` replacing the provisioned one.
`ce9e492d` closed five and narrowed the third.

### Second run, 2026-11-27 10:10 UTC, against `ce9e492d`, and what closed each finding

| Second-run finding | Now |
|---|---|
| N1: a ref moved to a commit already held started a walk | Closed. `walk_history` walks only when `git rev-list --max-count=1 --stdin` finds a commit the moved refs reach that no old ref and no old shallow boundary reached (`ghq-writer-handler.py:664`). In scratch (`logs/cam136-r3verify-gains-scratch-20261127-053955.log`): a move back to an ancestor runs the gate and lists nothing, logging no token; a force-push back to a commit a local branch still names never reaches the gate; two refs both gaining, one reaching its new commit only through the other, and one ref gaining while another moves back, each walk and hydrate; a branch fetched at depth 1, its only new commit a boundary, walks; a deepen moving no ref walks the deepened range without the gate. |
| N2: a ref name that is not UTF-8 failed the request | Closed. Ref names stay bytes (`:595-605`), and the snapshot and the walk each catch every `Exception` (`:621-633`, `:644-671`), reporting the handler's own failures by message and any other by type alone (`:614-618`). |
| N3: evaluation passed includes through the `~/ghq` link, with a differently cased section, or in list-form settings | Closed for those (`modules/system/shared-reference-tree.nix:97-240`); a path differing from the link or the root only in letter case still passes on darwin (FAIL R1 below). |
| N4: a depth-1 tag commit later merged was hydrated against the requirement's wording | Closed by wording: the requirement now excepts only a commit that only a tag reaches, and the skill, the fragment and the usage text say the same as the code does. |
| N5: the handler check outgrew `small` | Closed for the rule: the check is split into `package-ghq-shared-test-handler` and `package-ghq-shared-test-handler-history`, both declared `measured = false` (`modules/checks/package-tests.nix:88-98`, `:145-155`), `small` on x86_64-linux and `medium` on aarch64-darwin, which is how the rule marks a class no run backs yet. |
| Warning: the absent-log branch's race | Closed: the log is created with `O_CREAT | O_EXCL | O_NOFOLLOW` through the same descriptor step (`modules/darwin/shared-reference-tree.nix:44-63`). |
| Warning: the `.lazygit.yml` test-then-install race | Closed: the file is written under a random name in the root opened as a directory and renamed over the name (`:65-84`). |
| Warning: `iniContent` not read | Closed. |
| Warning: `tasks.md`'s header class | Closed. |

### Finding of this run

- [x] **FAIL R1, `Evaluation rejects an include that reopens a transport beneath the shared root`** ("a `gitdir:` path disjoint from all those paths cannot apply").
  On darwin the file system ignores letter case, so `/Users/crs58/GHQ/` and `/private/VAR/lib/ghq/` name the link and the root, and git matches a `gitdir:` pattern against the path a repository is reached by.
  In a scratch tree, an include under `gitdir:<home>/GHQ/`, or under the root spelled `ROOT`, setting `protocol.file.allow = always`, reopened the transport for `git show` run from a working directory spelled that way (`Unable to create temporary file …`), while the root's own include still refused it from every other spelling (`logs/cam136-r3verify-gitdir-case-scratch-20261127-053931.log`).
  `includeReachesRoot` compares a `gitdir:` pattern with the forms and the link case-sensitively (`:117`), and `transportGaps` returned `[]` for `gitdir:/Users/crs58/GHQ/`, `gitdir:/USERS/crs58/` and `gitdir:/private/VAR/lib/ghq/` (`logs/cam136-r3verify-transport-gaps-eval-20261127-053955.log`).
  No participant has such an include; the remedy is to fold case for that comparison on darwin, or to count any literal path that differs only in case as reaching.

### Requirements

| Requirement | Result |
|---|---|
| A refreshed or deepened reference repository shows what each commit it gained changed (behavioral) | PASS |
| A tag's commit fetched without its history is readable once requested (behavioral) | PASS |
| A read that needs content the reference tree lacks fails at once (behavioral) | PASS at the declared configuration; R1 is where darwin's evaluation would pass one that defeats it |
| An update makes every commit it brought in readable as a diff | PASS |
| A request that brings in no commit runs no history walk | PASS |
| Tag commits fetched at depth 1 stay unhydrated | PASS |
| The history fetch keeps the clone's partial-clone filter | PASS |
| A deepen makes every commit it brought in readable as a diff | PASS |
| The writer bounds the history it makes readable | PASS |
| A failed history fetch leaves the request's outcome as it was | PASS |
| The history walk gives git its lists on standard input | PASS |
| The writer's exit log line names what the history fetch did | PASS |
| A first acquisition fetches nothing more than before | PASS |
| Participating accounts' git refuses every transport beneath the shared root | PASS |
| Evaluation rejects an include that reopens a transport beneath the shared root | FAIL (R1) |
| Evaluation reads a participant's git settings in every shape and case | PASS |
| lazygit fetches nothing at start-up beneath the shared root | PASS |
| The provisioned .lazygit.yml is never written through a link | PASS |
| Migration keeps the provisioned .lazygit.yml over an administrator's own | PASS |
| A revision's diff is readable once the revision and its parents are hydrated | PASS |

### The remedy, probed

The guards: the snapshot (`history_before`) and everything of the walk (`gains_commits`, the listings, the limit count, the filter lookup, the fetch passes) sit inside the two `except Exception` blocks; what lies outside them is the `Unread` branch, which only formats (`history_failed`), the assignment to `session.history` (`:791`, `:808`), and the reply and log formatting, none of which raises on a `History`.
Neither guard holds a command of the request proper: the update, deepen, default-branch and tag fetches run outside them, so their failures and timeouts reach `serve` as before.
`SystemExit` and `KeyboardInterrupt` pass through, as the docstring says.
A `HistoryFailed` or `TimedOut` message carries a program and subcommand only; any other exception is named by type, so a path or URL in its `str()` reaches neither the reply nor the log; the failing git's standard error still goes to the reply's standard error, as for any failed command.
`transportGaps` over a whole Home Manager configuration (`logs/cam136-r3verify-transport-gaps-eval-20261127-053955.log`): `gitdir/i:`, a trailing `/**`, `~/ghq/`, `./ghq/`, `ghq/`, a glob, `onbranch:` and `hasconfig:remote.*.url:` each count as reaching; `~/projects/` does not; settings as a list, `iniContent` with `protocol "https"`, `PROTOCOL.https.ALLOW` and an include's `"Protocol.https".Allow` are each found; a boolean `protocol.allow = true` in an include is found; an include's contents declaring `include.path` or `includeIf … .path` are not read, which the trust boundary states.
A participant whose configuration has no `programs.git` at all fails evaluation with `attribute 'git' missing` rather than with the assertion's message.
The NixOS and darwin modules pass each participant's whole Home Manager configuration (`nixos/shared-reference-tree.nix:74`, `darwin/shared-reference-tree.nix:115`), and `omnigent-host.nix:455` the darwin worker's; the NixOS Omnigent workers are among `cfg.participants`; root and the writer are not participants, and the writer's git reads no global configuration.
The split: every case header of `nzvnkwwu`'s `test_handler.py` (39) is in exactly one of `test_handler.py` and `test_handler_history.py`, which together hold 42, the three new cases added; the runtime test's mutations are unchanged.
The idle-connection case now runs the handler with `READ_TIMEOUT` 1 and asserts the refusal names it (`refused: no complete request within 1 s`); it proves the same path as before, without the 30 s wait.
The darwin `.lazygit.yml` step (`logs/cam136-r3verify-lazygit-step-scratch-20261127-054027.log`, as crs58 with its own ids standing in): nothing, a regular file, a link to a file, a link to a directory and a FIFO are each replaced by the provisioned file at 0640 with no link target touched; a directory, empty or not, stops it with a message and leaves no temporary file; an absent root or a root that is a link stops it with a traceback; activation runs under `set -e` (nix-darwin `modules/system/activation-scripts.nix:88`), so each stop stops activation.
Read for what a non-root run cannot show: `fchown(fd, writer, writer)` uses the writer's id for the group, which is the `_ghq` group's id (`users.groups.${cfg.writer}.gid = cfg.writerId`); `fchown` precedes `fchmod`, and both precede `rename`, so the file is never at the name with root's ownership or mode `0600`.
The log step creates an absent log with `O_CREAT | O_EXCL` and expects root's ownership on that path, then gives it to the writer; an entry appearing between, a link included, makes `O_EXCL` fail and is then opened without following links.
NixOS: in systemd 262, `f+` reaches `truncate_file`, which opens the parent through `chase` with `CHASE_SAFE` and the file with `O_NOFOLLOW`, then refuses anything but a regular file (`src/tmpfiles/tmpfiles.c`, `truncate_file` and `path_open_parent_safe`); the claim holds.

**Drift warnings** (non-blocking):

- "Brings in" is defined by refs: a branch moved onto a commit only a tag reached in a copy holding full history, which no `git fetch` brought in, starts a walk that hydrates it (scratch, `hydrated:2`). The requirements as written ask for exactly that; the older scenario "An update of a full clone, or one that brings in nothing" reads as if by objects.
- `package-ghq-shared-test-handler` ran 46.9 s on magnetite, 78 % of the `small` limit; the whole check ran 75 to 151 s on nixbot against 80 s locally, so its first nixbot runs may exceed 60 s.
- A darwin activation killed between creating the temporary `.lazygit.yml.<hex>` and the rename leaves it in the root, where `ghq-shared-migrate` would no longer count the root as empty.

---

## 5. Implementation Signal

- [ ] No unstaged files in the worktree for this change: the remedy is `cd4dd583`; this report is on its own commit, a child of it
- [ ] All related commits have been pushed: `cd4dd583` is not yet on `main`

**Commit range**: `aab117563`, `3ff10f60`, `6c53ca38`, `d901fd6b`, the first run's report, `ce9e492d`, the second run's report, then `cd4dd583`

Open items, which only a deployed host or later runs can show:

- 4.1 on stibnite: the update of a blobless copy behind its upstream, `--no-lazy-fetch show` of each commit it brought in, lazygit under a terminal with `GIT_TRACE` and no `git fetch`, `git show` outside the range printing `transport 'https' not allowed` and no `Permission denied`, and every alert since the deploy.
- 4.2: `prek run --files` on the changed files.
- On each host after its deploy: the `history=` tokens for real updates, and the lock-hold time of large copies' first updates.
- On stibnite after activation, as root: `writer.log` and `.lazygit.yml` owned `_ghq:_ghq` at 0640, and the Omnigent worker's git configuration carrying both includes.
- On magnetite and pyrite: `.lazygit.yml` from the tmpfiles rule, and each participant's include with `protocol.allow = never`.
- The classes of both handler checks, from their first uncached nixbot runs.

---

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

- [x] No files, or any existing files are legitimate residue from before schema installation

`ls docs/superpowers/specs/*.md` printed nothing.

---

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

There is no `plan.md`, so no row is marked `[~]`.
The deferred checks are tasks 4.1 and 4.2 (§5); the runtime tests cover what 4.1 checks at the interface on NixOS, but not lazygit's start-up on a host, and the darwin activation steps have run only as a non-root account.

---

## 8. Designation Lint and Discharge Coherence

8a: the behavioral delta uses reference repository, reference tree, participating account, writer, acquisition request, commit and history, each a row of `openspec/specs/world-assumptions/spec.md`; "file contents", "branch" and "tag" resolve to no row.

8b:

| Requirement | Discharged by (S) | Under (W) | Status |
|---|---|---|---|
| A refreshed or deepened reference repository shows what each commit it gained changed | the update, no-walk, filter, deepen, bound, failure, stdin, log-line and first-acquisition requirements of the interface delta | none named | discharged |
| A tag's commit fetched without its history is readable once requested | `Tag commits fetched at depth 1 stay unhydrated`; `A revision's diff is readable once the revision and its parents are hydrated` | none named | discharged |
| A read that needs content the reference tree lacks fails at once | `Participating accounts' git refuses every transport beneath the shared root`; `Evaluation rejects an include that reopens a transport beneath the shared root`; `Evaluation reads a participant's git settings in every shape and case` | none named | discharged at the declared configuration; R1 is where darwin's evaluation would pass one that defeats it |

8c: the interface delta names only what the hosts' configuration, the writer and git expose; the behavioral delta names no git command, file or setting.

---

## Overall Decision

- [ ] (pass) PASS — may proceed to finishing-a-development-branch and archive
- [ ] (warn) PASS WITH WARNINGS — may proceed to subsequent steps but note: …
- [x] (fail) FAIL — return to the failed artifact, correct it, then re-run verify

Every finding of the first and second runs is closed but part of one: evaluation still passes, on darwin, an include whose `gitdir:` path differs from the account's link or the root only in letter case (R1).
Every other requirement holds against `cd4dd583`.
Tasks 4.1 and 4.2 remain open.

**Next step**:

Correct R1, then re-run verify; CAM-136 stays In Progress.
