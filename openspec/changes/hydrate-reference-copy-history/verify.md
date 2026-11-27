# Verification Report

> This file is produced by the `openspec-verify-change` skill after apply completes, to confirm that the
> implementation is consistent with the specs / design / tasks. Any failed check must be returned to its
> corresponding artifact for correction before re-running verify.

**Change**: `hydrate-reference-copy-history` (CAM-136)
**Verified at**: `2026-11-27 15:45` UTC, a fourth run, narrowed to the case rule of `uutwvwxq` (`c6aeb3cb`, `fix(shared-reference-tree): fold letter case when judging whether an include reaches the root`); the third run, `2026-11-27 10:45` UTC against `cd4dd583` (`skwtzotn`), checked everything else, and the first (`08:50` UTC, `d901fd6b`) and second (`10:10` UTC, `ce9e492d`) are recorded in §4
**Verifier**: `openspec-verify-change` (omp)

Prechecks: `tasks.md` holds 26 `- [x]` lines and 2 `- [ ]` (4.1 and 4.2); `cd4dd583` is on `main`, `c6aeb3cb` is not.
The third run read the code at `cd4dd583`: `pkgs/by-name/ghq-shared/ghq-writer-handler.py`, `test_handler.py`, `test_handler_history.py`, `handler_fixtures.py`, `test-handler.nix`, `package.nix`, `modules/checks/package-tests.nix`, `modules/system/shared-reference-tree.nix` and `.test.nix`, `modules/{nixos,darwin}/shared-reference-tree.nix`, `modules/darwin/omnigent-host.nix`, `modules/home/development/repository-acquisition.nix`, the skill, the agent-context fragment and `ghq-sync`'s usage text; line numbers in §4's third-run text are of those files there.
`c6aeb3cb` changes only `modules/system/shared-reference-tree.nix` and its `.test.nix` in code, and the interface delta spec, `design.md`, `tasks.md` and `proposal.md` in text; the fourth run read those at `c6aeb3cb`.
Nothing of this change is deployed to any host, and no test was re-run.
The evidence is the remedies' logs (`logs/cam136-r3-*`, `logs/cam136-casefold-*`), the systemd 262 source the pinned nixpkgs builds, and scratch experiments under `/tmp` with git 2.56.0, recorded as `logs/cam136-r3verify-*` and `logs/cam136-r4verify-*` with their scripts.

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

26 of 28 at this run; 4.1 and 4.2 waited on a deploy (§5). After the deploy, 4.2 is done and 4.1 stays open (§9).
Task 7.1, the case rule, is checked against `logs/cam136-casefold-magnetite-red-green-20261127-103853.log` (the nix-unit check 24 of 31 against `cd4dd583`'s function, 31 of 31 at `c6aeb3cb`), `logs/cam136-casefold-host-assertions-20261127-103627.log` (no assertion fails for magnetite, pyrite or stibnite), `logs/cam136-casefold-magnetite-changed-set-20261127-103623.log` (243 attributes evaluated at both commits, the four changed checks built) and `logs/cam136-casefold-stibnite-case-include-20261127-103713.log` (stibnite with an include under `gitdir:<home>/GHQ/` evaluates clean before the fix and fails naming `crs58` after it).
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

### Third run, 2026-11-27 10:45 UTC, against `cd4dd583`, and what closed its finding

| Third-run finding | Now |
|---|---|
| R1: on darwin, evaluation passed an include whose `gitdir:` path differed from the account's link or the root only in letter case, which git applies when a copy is reached by that spelling (`logs/cam136-r3verify-gitdir-case-scratch-20261127-053931.log`) | Closed. `includeReachesRoot` lower-cases the pattern, after `~/` expansion, and each root form and link before comparing them, on every platform (`modules/system/shared-reference-tree.nix` at `c6aeb3cb`, lines 97-125). |
| Note: a participant with no `programs.git` stopped evaluation with `attribute 'git' missing` | Closed: `transportGaps` reads `home.programs.git or { }`, so the assertion reports each root form missing its include, naming the account. |

### Fourth run, 2026-11-27 15:45 UTC, against `c6aeb3cb`

No checked finding.
The case rule, evaluated directly (`logs/cam136-r4verify-case-rule-eval-20261127-104220.log`): `gitdir:/Users/CrS58/gHq/`, `gitdir:/pRiVaTe/var/LIB/ghq/github.com/` (mixed case inside a path), `gitdir:/USERS/crs58/`, `gitdir:/Users/crs58/GHQ/`, `gitdir:~/GHQ/`, `gitdir:/private/VAR/lib/ghq/`, and `gitdir:/users/crs58/ghq/` for a home declared `/Users/CRS58`, each count as reaching; `gitdir:/USERS/crs58/Projects/` and `gitdir:/VAR/LIB/GHQ-other/`, which differ in case and are otherwise disjoint, still do not; every shape and condition the third run probed gives the same result as then.
A configuration with no `programs.git`, and one with no `programs` at all, now return the two missing-include findings, which the NixOS and darwin assertions print with the account's name.
The 31 nix-unit cases assert what their names say: each case's expression sets the include, home or link its name gives, and its expected list names exactly that include, or is empty for `testDeclared`, `testSettingsAllowAlways`, `testUnrelatedGitdir`, `testUnrelatedTildeGitdir`, `testCaseUnrelatedGitdir` and `testPathInclude`.
Every root form, link and home directory the hosts declare is ASCII: the root is the option's default `/var/lib/ghq` on stibnite, magnetite and pyrite (none sets `root`), its darwin form `/private/var/lib/ghq`, and the homes are `/Users/<user>` or `/home/<user>` from `modules/home/users/lib.nix` for `crs58`, `cameron` and the `omnigent-*` worker accounts; `lib.toLower` folds ASCII letters only, which the design states.
Between `cd4dd583` and `c6aeb3cb` the delta specs changed only in the interface spec: the scenario "A participant lacks the setting" adds a configuration with no `programs.git` and the witness `testNoGit`, the requirement "Evaluation rejects an include that reopens a transport beneath the shared root" adds "letter case ignored" to its disjointness clause, and the scenario "An include under a path differing only in letter case reaches the tree" is new; the behavioral delta is unchanged, and no other requirement's text moved.

### Requirements

| Requirement | Result |
|---|---|
| A refreshed or deepened reference repository shows what each commit it gained changed (behavioral) | PASS |
| A tag's commit fetched without its history is readable once requested (behavioral) | PASS |
| A read that needs content the reference tree lacks fails at once (behavioral) | PASS at the declared configuration |
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
| Evaluation rejects an include that reopens a transport beneath the shared root | PASS |
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
A participant whose configuration has no `programs.git` at all is reported by the assertion's own message at `c6aeb3cb`; at `cd4dd583` it stopped evaluation with `attribute 'git' missing`.
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
- `services.shared-reference-tree.root` is a plain string, so a module can declare it with a trailing slash, though none does. The includes are then written under `gitdir:<root>//`, which git never applies: in a scratch copy, an include under `gitdir:<root>//` left `protocol.allow` unset and `git show` ran the transport (`logs/cam136-r4verify-trailing-slash-gitdir-scratch-20261127-104220.log`). The assertions still pass, since they compare against the same doubled form, and `transportGaps` misses an include under a path beneath such a root (`rootTrailingSlashBeneath` in the case-rule log). The option's type could refuse a trailing slash. A home directory with a trailing slash would double the link's slash the same way; `modules/home/users/lib.nix` declares none.

---

## 5. Implementation Signal

- [ ] No unstaged files in the worktree for this change: the remedies are `cd4dd583` and `c6aeb3cb`; this report is on its own commit, a child of `c6aeb3cb`
- [ ] All related commits have been pushed: `c6aeb3cb` is not yet on `main`

**Commit range**: `aab117563`, `3ff10f60`, `6c53ca38`, `d901fd6b`, the first run's report, `ce9e492d`, the second run's report, `cd4dd583`, the third run's report, then `c6aeb3cb`

Open items, which only a deployed host or later runs can show:

- 4.1 on stibnite: run on 2026-11-27 (§9). Every part held except one: in nixpkgs, 96 of the 210 merges two updates brought in are not readable as `git show` shows them (rename detection on), so 4.1 stays open.
- 4.2: `prek run --files` on this report and `tasks.md` passed (§9).
- On magnetite and pyrite after their deploys: the `history=` tokens for real updates, and the lock-hold time of large copies' first updates; stibnite's are in §9.
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
| A read that needs content the reference tree lacks fails at once | `Participating accounts' git refuses every transport beneath the shared root`; `Evaluation rejects an include that reopens a transport beneath the shared root`; `Evaluation reads a participant's git settings in every shape and case` | none named | discharged at the declared configuration |

8c: the interface delta names only what the hosts' configuration, the writer and git expose; the behavioral delta names no git command, file or setting.

---

## 9. Deployed-host checks on stibnite, 2026-11-27

Run as `crs58` on stibnite after activation at `main` `3fea6f9b` (system profile 258, `/run/current-system` linked at 17:44:29 UTC), from 17:46 to 18:11 UTC, with git 2.56.0 and lazygit 0.66.3.
The logs are `logs/cam136-host41-jj-20261127-174751.log`, `logs/cam136-host41-iets-20261127-175318.log`, `logs/cam136-nixpkgs-first-update-20261127-174847.log`, `logs/cam136-host41-nixpkgs-reads-20261127-180417.log` and `logs/cam136-host41-lazygit-20261127-174929.log`, with its scratch configuration `logs/cam136-host41-lazygit-scratch-config.yml`; validation and hooks are in `logs/cam136-host41-prek-20261127-181200.log`.

### What is deployed

- `ghq-sync --help` describes the writer hydrating the commits an update, deepen or tag fetch brings into a clone's branches, and the `transport '<scheme>' not allowed` refusal.
- `/private/var/lib/ghq/.lazygit.yml` holds `git:` / `  autoFetch: false`, owned `_ghq:_ghq`, mode `0640`, written at activation (12:44 local time).
- `git -C /private/var/lib/ghq/github.com/jj-vcs/jj config --show-origin --get protocol.allow` prints `file:/nix/store/bki0727m3969ibxy10f01ip7n5wvn61c-hm_gitconfig never`, the file `includeIf.gitdir:/var/lib/ghq/.path` and `includeIf.gitdir:/private/var/lib/ghq/.path` name in `~/.config/git/config`.
- The writer logs to `/var/log/ghq-writer/writer.log` (`StandardErrorPath` in `modules/darwin/shared-reference-tree.nix`), `_ghq:_ghq` `0640`, readable by `crs58` through the `_ghq` group.

### The updates

Each copy was chosen from `ghq list -p`, blobless (`remote.origin.promisor` true, `partialclonefilter` `blob:none`), and behind `git ls-remote <url> HEAD` run from `/tmp`.
Readable means `git -C <path> --no-lazy-fetch show --stat -p <c>` exits 0; missing is `git --no-lazy-fetch rev-list --objects --missing=print OLD..NEW | grep -c '^?'`.

| Copy | Old tip → new tip | Commits (merges) | Packs before → after | Wall time | Writer's exit line | Readable | Missing |
|---|---|---|---|---|---|---|---|
| `github.com/jj-vcs/jj` | `a1f34c05` → `10231189` | 157 (0) | 182 → 3 | 3.93 s | `exit status=0 duration=3.325s history=hydrated:370` | 157 of 157 | 0 |
| `github.com/numtide/iets` | `81d2d4aa` → `1a1c28bd` | 242 (119) | 11 → 14 | 2.48 s | `exit status=0 duration=2.205s history=hydrated:195` | 242 of 242 | 0 |
| `github.com/nixos/nixpkgs`, first | `2a21d231` → `a2138be0` | 450 (202) | 1,688 → 4; 2,589,088 KiB → 1,806,252 KiB | 55.59 s | `exit status=0 duration=55.414s history=hydrated:74` | see below | 0 |
| `github.com/nixos/nixpkgs`, second | `a2138be0` → `aa08d423` | 16 (8) | 4 → 6; 1,807,080 KiB | 3.11 s | `exit status=0 duration=2.878s history=hydrated:0` | see below | 0 |

The jj and nixpkgs replies each printed `Auto packing the repository for optimum performance.` before the fast-forward: the first update of a copy holding more than `gc.autoPackLimit` packs repacked once inside the request, and nixpkgs' second update, 12 minutes later, took 3 s and did not repack.
The nixpkgs pack directory held `tmp_pack_cVPbJa` (415 MiB, 27 August) before its first update and not after it.
Before that update nixpkgs' `origin/master` (`e3c7a9df`) was 3 commits ahead of its `master`, left by an earlier `ghq get -u` that exited 1 after its fetch (the older log format's `exit=1` line after a `BrokenPipeError`); the update's walk started from the commits no old ref reached, so those 3 commits, which reached `master` by this fast-forward, were outside its walk.

Of the 466 commits nixpkgs' two updates brought in (`2a21d231..aa08d423`), read with a 20 s limit per command: all 256 single-parent commits are readable; of the 210 merges, 114 are readable and 96 exceeded the limit; all 466 are readable with `--no-renames`.
An earlier pass without the limit, stopped after 27 commits, read 8 merges to the end, among them `3422cb69`, `57bcedef`, `7826914b` and `a2138be0`, and each failed with `could not fetch <oid> from promisor remote`.
A plain `git show a2138be0` (a merge in the hydrated range) ran 103 s of processor time and exited 128 with `fatal: transport 'https' not allowed` and `fatal: could not fetch 9970522f282aff7b7b815d7f5f5527fd51a4a46a from promisor remote`; `git show --no-renames a2138be0` exits 0.
The blob is `pkgs/by-name/cl/cleanuparr/qbittorrent-net-client-deps.json` in the merge's second parent `c9237336`, a pull-request branch commit inside the range whose tree still holds a file `master` had since deleted: its diff against the merge deletes that file, and rename detection on that side reads the blob, which the hydrate's listings, `--diff-merges=first-parent` and `--merges --cc` with `--no-renames`, never name, because the merge and its first parent agree on the path and the blob is reachable from the old tip, so `--missing=print` over `OLD..NEW` does not count it.
iets' 119 merges all read; jj's range holds none, so lazygit, whose `git show` passes `--find-renames=50%`, was not shown such a merge.

### Outside the hydrated range

`git -C /private/var/lib/ghq/github.com/jj-vcs/jj show a1f34c05` (the old tip, whose parent's blobs were absent: 1,210 objects reachable from it are missing) exited 128 within a second with:

```text
fatal: transport 'https' not allowed
fatal: could not fetch 0b383152c907ba2c6b329e809ddcbe76c418e0f0 from promisor remote
```

No line held `Permission denied`, and the copy's pack list and refs were unchanged.

### lazygit

lazygit ran in a tmux pseudo-terminal of 200 by 50 in the jj copy with `GIT_TRACE` and `GIT_TRACE2_EVENT` set, from 17:49:29 to 17:51:19 UTC (110 s, past the default `refresher.fetchInterval` of 60 s), with the account's own configuration (`LG_CONFIG_FILE` naming the catppuccin theme and `~/.config/lazygit/config.yml`, neither setting `autoFetch`).
The commits panel was focused and moved down 13 commits; lazygit ran `git show … --find-renames=50% … --stat --decorate -p <c>` for 14 commits of the update's range, each exiting 0, and the Patch pane showed their diffs.
The traces hold no `fetch`, `fetch-pack` or `remote-https` invocation.
lazygit's documentation (`docs/Config.md`, line 19, in the tree's copy of `jesseduffield/lazygit`) says files called `.lazygit.yml` in any parent directory of a repository are loaded; `getPerRepoConfigFiles` in `pkg/gui/gui.go` lists them outermost first, after the account's files.

The contrast, with a scratch configuration setting `git.autoFetch: true` and `refresher.fetchInterval: 10` through `LG_CONFIG_FILE`, both from 17:52:12 to 17:53:51 UTC:

- In the copy, lazygit ran no `git fetch`: `<root>/.lazygit.yml` overrides the account's files, so a scratch file cannot neutralise it there.
- With `lazygit -g <copy>/.git -w /tmp/cam136/wt`, whose top level lies outside the root and so reads no `<root>/.lazygit.yml`, lazygit ran `git fetch --all --no-write-fetch-head` every 10 s, 10 times, each exiting 128 with `transport 'https' not allowed`.

After both runs the copy's pack list, refs and `.git` listing were the same as before.

### Alerts, notices and the writer's log

`fleet-alerts` on `ntfy.zt`, polled with `since` 17:00 UTC at 17:47 and 18:10 UTC, held no message; its last was at 12:00:04 UTC, and `fleet-heartbeat` posted through 18:10:04 UTC.
The writer's log holds no line after activation other than the start and exit lines of the four requests above, with no warning; the last before it, at 17:43:30 UTC, is an update of `github.com/can1357/oh-my-pi` exiting 1.
Stale files met in copies, left in place: `objects/pack/tmp_pack_*` in `NousResearch/hermes-agent` (1 August), `cameronraysmith/atomic` (7 September), `can1357/oh-my-pi` (6 October) and `schpet/linear-cli` (31 August), and an empty `objects/maintenance.lock` of 20 August in `block/buzz`.

### Result

4.1 holds for jj and iets and for every single-parent commit of nixpkgs, and fails for nixpkgs merges whose second parent's side of the diff, as git shows it with rename detection, needs blobs no listing names; lazygit's start-up and interval fetch are off beneath the root and refused outside the setting.
4.2: `prek run --files` on `tasks.md` and this report passed.

---

## Overall Decision

- [ ] (pass) PASS — may proceed to finishing-a-development-branch and archive
- [x] (warn) PASS WITH WARNINGS — may proceed to subsequent steps but note: "brings in" is defined by refs; the request-half handler check ran 46.9 s of its 60 s limit; a darwin activation killed mid-write leaves `.lazygit.yml.<hex>` in the root; a root or home declared with a trailing slash would defeat the include, though none is; tasks 4.1 and 4.2 stay open until the deploy
- [ ] (fail) FAIL — return to the failed artifact, correct it, then re-run verify

Every finding of the first, second and third runs is closed, and every requirement holds against `c6aeb3cb`.
No checked FAIL remains.
Tasks 4.1 and 4.2 remain open.

**Next step**:

Deploy, then tasks 4.1 and 4.2; CAM-136 stays In Progress until its deployed-host tasks are done.
