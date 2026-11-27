# Verification Report

> This file is produced by the `openspec-verify-change` skill after apply completes, to confirm that the
> implementation is consistent with the specs / design / tasks. Any failed check must be returned to its
> corresponding artifact for correction before re-running verify.

**Change**: `hydrate-reference-copy-history` (CAM-136)
**Verified at**: `2026-11-27 08:50` UTC
**Verifier**: `openspec-verify-change` (omp), against the stack head `d901fd6b` (`moszopru`)

Prechecks: the change's delivery commits are `aab117563` (`feat(ghq-shared): make the commits an update or deepen brings in readable as diffs`) and `3ff10f60` (`feat(shared-reference-tree): refuse readers every transport beneath the root and turn off lazygit start-up fetch`, `wnutwtly`), both on `main`, then `6c53ca38` (`quyqosuo`, the skill, agent-context and `ghq-sync` usage text) and `d901fd6b` (`moszopru`, the darwin writer log mode), which are not yet on `main`.
`tasks.md` holds 10 `- [x]` lines and 2 `- [ ]`; both prechecks are positive.
`openspec status` reports the verify artifact blocked on a missing `plan.md`; this change tracks its work in `tasks.md` alone, as `serialise-shared-reference-tree-writes` did, and §7 below records what that leaves out.

The code was read at `d901fd6b`: `pkgs/by-name/ghq-shared/ghq-writer-handler.py`, `test_handler.py`, `ghq-shared-migrate.py`, `pkgs/by-name/ghq-sync/ghq-sync.sh`, `modules/system/shared-reference-tree.nix`, `modules/{nixos,darwin}/shared-reference-tree.nix`, `modules/darwin/omnigent-host.nix`, `modules/home/development/repository-acquisition.nix`, `modules/vm-tests/shared-reference-tree.nix`, the skill and the agent-context fragment.
Line numbers below are of those files at `d901fd6b`.
Nothing of this change is deployed: on 2026-11-27 stibnite's root had no `.lazygit.yml` and its `writer.log` was still `0644`, and neither magnetite nor pyrite had `/var/lib/ghq/.lazygit.yml`.
No test or runtime test was re-run.
The evidence is the recorded logs under `logs/` (git-ignored), read-only inspection of stibnite, magnetite and pyrite, and scratch experiments on stibnite under `/tmp/cam136v` with git 2.56.0, recorded as `logs/cam136-verify-*-20261127-034842.log` with their scripts beside them.

---

## 1. Structural Validation (`openspec validate --all --json`)

- [ ] All items report `"valid": true`

**Result**:

```text
totals: 85 items, 82 passed, 3 failed
openspec validate hydrate-reference-copy-history --strict: Change 'hydrate-reference-copy-history' is valid
```

None of the three failures is this change: `compose-hosts-from-cohesive-aspects`, `stand-up-gitea-mq-on-magnetite` and `stand-up-nixbot-on-magnetite`.

---

## 2. Task Completion (`tasks.md`)

- [ ] All `- [ ]` have been changed to `- [x]`

10 of 12; 4.1 and 4.2 are open, and both wait on a deploy (§5).

| Task | Evidence checked | Missing |
|---|---|---|
| 1.1 history walk and fetch | `logs/hydrate-history-handler-red-20261126-235634.log` (fails before the handler change), `logs/hydrate-history-handler-green-darwin-20261127-000118.log` and `logs/hydrate-history-c2-handler-darwin-20261127-003812.log` ("all request classes behaved"); `logs/hydrate-history-magnetite-checks-20261127-001425.log` (`build-exit 0`) | the cases cover no symlink, type change, gitlink, octopus merge or root commit; the scratch run in §4 does |
| 1.2 deepen | the deepen case in the same handler builds | none |
| 1.3 first acquisition, parents rule | the two cases in the same builds | none |
| 1.4 no `historyLimit` in either module | `logs/hydrate-history-writer-config-20261127-000713.log`: the `ghq` and `_ghq` writer configurations hold `allowedProtocols`, `group`, `lockDir` and `root` only | none |
| 1.5 reworked hydrate subtest | `logs/hydrate-history-pyrite-shared-reference-tree-20261127-001051.log` (37.10 s) | none |
| 1.6 exit log token | `history_token` assertions in the cases of 1.1 | the deepen case asserts the status line, not the token |
| 2.1 include and assertions | `logs/hydrate-history-assertions-20261127-002816.log`: `plain` is `[]` for magnetite and stibnite; emptying the include and adding `protocol.https.allow` each fail, naming `cameron` and `crs58` | the predicate passes an include that sets a `protocol.<name>.allow` key (finding 3) |
| 2.2 `.lazygit.yml` and migration | migration subtest passes in every run below | the assertions' reach is in §4 |
| 2.3 runtime subtests, three runs | `shared-reference-tree-migration`: 38.33, 39.23, 37.95 s (`logs/hydrate-history-green2-run{1,2,3}-…-migration-*.log`) and 42.28, 37.46, 40.81 s at the stack head (`logs/hydrate-history-top-run{1,2,3}-…`); `shared-reference-tree`: 43.74, 40.45, 37.86, 40.45 s | none |
| 3.1 text | the stack's checks on magnetite built 51 derivations with only `treefmt-check` failing (`logs/hydrate-history-stack-magnetite-checks-20261127-032125.log`, `build-exit 123`); `logs/hydrate-history-c4-final-fmt-magnetite-20261127-033142.log` passes `treefmt-check` (`build-exit 0`) at `fff3b7cb`, a commit not in this repository, so it cannot be matched to `d901fd6b` | the text overstates the hydrated range (finding 1) |

Margins of the runtime tests, class `small` (60 s): `shared-reference-tree-migration` ran 37.46 to 42.28 s at the stack head, 17.7 s under the limit against a 4.8 s range (9.5 s over all seven runs since the first commit); `shared-reference-tree` ran 37.10 to 43.74 s, 16.3 s under against a 6.6 s range.
Both keep a margin wider than their spread, which is the rule fleet-alert's `RuntimeTestCostDrift` applies, and the migration test stays under the 45 s task 2.3 set.
The migration test grew by 5 to 8 s over its runs at the end of `serialise-shared-reference-tree-writes` (32.86 to 35.10 s), not the 2 to 3 s task 2.3 expected: its two new subtests take 3.7 and 0.1 s (`logs/hydrate-history-top-run1-…-migration-20261127-032234.log`), and the rest is the boot before the first subtest, which varies between runs.
The new subtest bounds a refused read at 5 s, a bound that proves a refusal rather than a wait, which the class allows.

---

## 3. Delta Spec Sync State

| Capability | Sync status | Notes |
|---|---|---|
| `shared-reference-tree` | needs sync | 2 ADDED; neither is in `openspec/specs/shared-reference-tree/spec.md` |
| `shared-reference-tree-interface` | needs sync | 9 ADDED; none is in `openspec/specs/shared-reference-tree-interface/spec.md` |

---

## 4. Design / Specs Coherence Spot Check

### Findings

- [x] **FAIL 1, `A refreshed or deepened reference repository shows what each commit it gained changed`** (`specs/shared-reference-tree/spec.md:5`, scenarios at `:8` and `:20`).
  The requirement covers every commit a refresh or deepen brings into a repository's history, excepting only a deepen's deepest commits and an answer saying the commits were too many.
  The code walks only `HEAD`'s range for an update (`ghq-writer-handler.py:664-673`) and only the removed boundaries for a deepen (`:693-694`); the interface requirements say exactly that, so they do not discharge this one.
  Two code paths bring in commits no walk covers, and the answer says nothing of them:
  (a) a `get` with `update` and `tags` fetches tags whose commits are absent at depth 1 in `shallow_tags` (`:677`), after the walk; the change's own subtest shows it: `ghq-sync -u --tags` brings in `t-unmerged`, and `git show t-unmerged` is asserted to fail (`modules/vm-tests/shared-reference-tree.nix:446-452`).
  (b) `ghq-sync --deepen` runs `git fetch --deepen=N` (`ghq-sync.sh:197`), which also moves `origin/<branch>` to the commits the upstream gained since the last update; in a scratch copy three commits behind, the deepen's walk hydrated 2 blobs of the deepened range and all three new tip commits stayed unreadable with lazy fetching disabled (`logs/cam136-verify-deepen-tip-scratch-20261127-034842.log`).
  The same overstatement is in the text commit: "every commit an update or a deepen brought in" (`SKILL.md:40`, `30-reference-repositories.instructions.md:12`) and "the commits an update or deepen brought in" (`ghq-sync.sh` usage).
  Design's non-goals list "the trees of tags fetched at depth 1"; the requirement carries no such exception.

- [x] **FAIL 2, `The writer's exit log line names what the history fetch did`** (interface spec, and the status line of `An update makes every commit it brought in readable as a diff`).
  When a command after the walk outlasts `commandTimeout`, here the tag fetch of a `get` with `update` and `tags` (`shallow_tags` at `:677`), `TimedOut` leaves `run_get` and `serve` returns from its `except TimedOut` (`:801-802`) before `session.history` is set (`:805`), dropping the results.
  Scenario: `ghq-sync -u --tags owner/repo` of a blobless shallow copy behind its upstream whose tag fetch passes the limit: the walk and the history fetch ran, the exit line reads `exit status=124 duration=… reason: timed out after 3600 s running git fetch` with no `history=` token, and the reply holds no `hydrated history:` line.

- [x] **FAIL 3, `Participating accounts' git refuses every transport beneath the shared root`**, scenario "A participant lacks the setting" (interface spec `:86`, `:103-106`).
  The scenario says evaluation fails when a participant's evaluated git includes set a `protocol.<name>.allow` key.
  `refusesTransport` (`modules/system/shared-reference-tree.nix:92-102`), used by `modules/nixos/shared-reference-tree.nix:71`, `modules/darwin/shared-reference-tree.nix:65` and `modules/darwin/omnigent-host.nix:457`, looks for that key only in `git.settings` and asks only that some include per root form carry `protocol.allow = never`.
  Evaluated directly (`logs/cam136-verify-refuses-transport-eval-20261127-034842.log`), it accepts an unconditional include setting `protocol.https.allow = always`, a second include under the root's own `gitdir:` condition setting it, and an include under a broader `gitdir:` setting `protocol.allow = always`; it rejects only the key in `settings`.
  Each of those three defeats the refusal: in a read-only scratch copy, `git show` of a commit lacking a blob then ran the transport and failed with `Unable to create temporary file …/tmp_pack_XXXXXX` instead of `transport 'file' not allowed` (`logs/cam136-verify-overrides-scratch-20261127-034842.log`).
  No participant has such an include today; `crs58`'s only other include on stibnite is the catppuccin delta `path` include, whose contents evaluation cannot see.

- [x] **FAIL 4, `An update makes every commit it brought in readable as a diff`**: "with the clone's filter and depth", and the scenario's "the clone's filter … unchanged" (interface spec, first requirement).
  `fetch_blobs` passes the constant `--filter=blob:none` (`ghq-writer-handler.py:630`), not the clone's filter, and the walk's trigger is `remote.origin.promisor` alone (`:559-560`, `:664`).
  A copy with `remote.origin.promisor = true` and no `partialclonefilter` gets `remote.origin.partialclonefilter = blob:none` written by the first history fetch (`logs/cam136-verify-filter-registration-scratch-20261127-034842.log`: the key absent before the handler's fetch command, `blob:none` after).
  `ghq-sync --full` leaves a copy in that state when its `fetch --refetch` fails, since it clears the filter first and the promisor flag only after the refetch (`ghq-sync.sh:218-225`).
  No copy on stibnite is in that state today; all 603 promisor copies there have `blob:none`.

- [x] **FAIL 5, `A failed history fetch leaves the request's outcome as it was`**.
  `hydrate_history` catches only `HistoryFailed` and `TimedOut` (`:651`); an `OSError` from starting git escapes to `main`, which ends the request with status 70 and `reason: unexpected OSError …`, and the exit line gets no `history=` token.
  The deepen's walk passes every boundary on argv (`:694`), not on standard input; on darwin `Popen` raised `OSError: [Errno 7] Argument list too long` for 20,000 such arguments and not for 15,000.
  Scenario: a deepen of a copy holding about 20,000 shallow boundaries, which `shallow_tags` creates one per tag fetched at depth 1, succeeds and the request still fails with 70.
  The largest `.git/shallow` on stibnite holds 1,512 lines (`github.com/zed-industries/zed`).
  The id lists themselves go on standard input, as design D1 has them: `cat-file` (`:577-582`) and `fetch --stdin` (`:628-631`).

- [x] **FAIL 6, `lazygit fetches nothing at start-up beneath the shared root`**, scenario "A tree is migrated into a root holding the file": "`.lazygit.yml` is present afterwards with its owner, mode and content".
  When the administrator's own `~/ghq` holds a `.lazygit.yml`, the whole-tree rename brings it to the root, and `migrate` keeps it and parks the provisioned file in the record directory (`ghq-shared-migrate.py:706-710`): until the host's next activation the root's file has the administrator's content, owned by the writer with its mode masked.

### Requirements

| Requirement | Code | Witness and recorded run | Result |
|---|---|---|---|
| An update makes every commit it brought in readable as a diff | `run_get` `:656-680`, `missing_blobs` `:585-619`, `fetch_blobs` `:622-639` | case "An update of a blobless clone makes every commit it brought in readable as a diff with lazy fetching disabled" (merge, renamed default branch, filter, boundaries, one pack after gc); migration subtest "an update makes the commits it brought in readable, …" | FAIL (findings 2, 4) |
| A deepen makes every commit it brought in readable as a diff | `run_deepen` `:683-695` | case "A deepen makes every commit it brought in, but the new deepest, readable as a diff" | PASS as worded (the commits a deepen moves `origin/<branch>` to fall under finding 1) |
| The writer bounds the history it makes readable | `missing_blobs` batches `:608`, stop `:612-619`; message `:647-648` | case "An update bringing in more missing blobs than the limit fetches none and says so" (`historyLimit` 2, fewer than 7 ids checked, no merge listing, no fetch) | PASS |
| A failed history fetch leaves the request's outcome as it was | `hydrate_history` `:642-653`; `History` exit status 0 | case "A history fetch that fails leaves the update's exit status and says so" | FAIL (finding 5) |
| The writer's exit log line names what the history fetch did | `main` `:835-837`; `serve` `:805` | the three cases' `history_token`; "An update of a full clone, or one that brings in nothing, walks no history" | FAIL (finding 2) |
| A first acquisition fetches nothing more than before | `old` is `None` for an absent clone (`:662-664`) | case "A first lazy acquisition fetches no blob beyond its tip's tree" | PASS |
| Participating accounts' git refuses every transport beneath the shared root | `repository-acquisition.nix` includes; `refusesTransport` | access subtest "readers cannot write the tree" (`Permission denied`, then `not allowed`); migration subtest (`ls-remote`, `remote show`, `show` of the tag); assertion log of task 2.1 | FAIL (finding 3) |
| lazygit fetches nothing at start-up beneath the shared root | tmpfiles `f+` rule (`nixos/shared-reference-tree.nix:25-29`, asserted `:121-124`); darwin `install` (`darwin/shared-reference-tree.nix:36,256`, asserted `:134-138`); `ghq-shared-migrate.py:432,617-626,683-711,918-923` | subtest "lazygit's start-up fetch is off beneath the shared root"; `logs/hydrate-history-lazygit-stibnite-20261127-003500.log` | FAIL (finding 6) |
| A revision's diff is readable once the revision and its parents are hydrated | `ghq-sync --hydrate` unchanged (`hydrate_one`) | case "Hydrating a commit and then each of its parents makes its diff readable, and the commit alone does not" | PASS |
| A refreshed or deepened reference repository shows what each commit it gained changed (behavioral) | as the interface rows | the interface witnesses | FAIL (finding 1) |
| A read that needs content the reference tree lacks fails at once (behavioral) | the include | as the transport row | PASS at the declared configuration; finding 3 is where evaluation would not catch a configuration that defeats it |

### The history hydrate, probed

A scratch upstream (`logs/cam136-verify-hydrate-scratch-20261127-034842.log`) gave a depth-1 blobless copy 11 commits: a rename with similarity (`big.txt` to `moved.txt`, one line changed), a symlink becoming a file and a file becoming a symlink, a gitlink moved and then replaced by a file, an octopus merge of three branches amended to resolve `a` differently from every parent, and a deletion.
The handler's own `hydrate_history` then fetched 4 blobs, and with lazy fetching disabled every commit read under lazygit's `git show --find-renames=50% --submodule --stat --decorate -p`, plain `git show`, `--stat`, `-M`, `--cc`, `-m`, `-C`, `--find-copies-harder` and `--word-diff`, as did `git log -p` and `git log -p --stat` over the range, `git log --follow -p moved.txt`, `git diff OLD NEW`, `git diff NEW~5 NEW~1`, `git blame`, and `git show` of the old shallow boundary.
The octopus's combined raw lines carry four colons and five modes and ids, which `take` pairs by count (`:597-604`); a gitlink's id is skipped by its mode on each side separately, so a gitlink-to-file change lists the file's blob only.
With `--no-renames` the listing names both a renamed path's old and new blob, which is what similarity detection reads.
`-C` and `--find-copies-harder` read parents' unchanged files, which the listings do not name; they read here only because the fixture's checkout held those blobs.
A second `hydrate_history` over the same range listed, found nothing missing and ran no fetch.
Which commits form OLD and NEW: a fast-forward and a renamed default branch are walked (the handler case); a forced update upstream makes `git pull --ff-only` fail, so `HEAD` stays at OLD and nothing is walked, the update's own failure being reported (design D2, not re-run here); a detached `HEAD`, as in 2 of stibnite's 603 promisor copies (`bitwarden/clients`, `openzfs/zfs`), makes `git pull` refuse in the same way, so its update fails and nothing is walked (read from the code, not run); an update that brings nothing leaves OLD equal to NEW and walks nothing.
A default branch whose new history shares nothing with OLD makes the walk include the new branch's shallow boundaries as root commits, hydrating their whole trees under the limit (read from the code); that holds the requirement as worded.
At the limit nothing is fetched and the listing is stopped (`stream`, `:397-429`); the count can pass the limit by up to one batch, which "stopping once the count exceeds" allows.
No by-id fetch runs with an empty list: `fetch_blobs` loops only `while missing` (`:628`), an empty listing returns `[]`, a failed listing or `cat-file` raises before any fetch, and a pass that fetches nothing raises rather than repeats.
A failed or timed-out history fetch is caught, logged as `history=failed` with no ` reason:`, leaves the exit status, keeps earlier passes' packs, and the lock is released in `serve`'s `finally` (`:803-804`); a killed handler releases its `flock` with its descriptor.
The history fetch runs after `ghq get -u` and before any tag fetch, and git's automatic maintenance after it runs under `MAINTENANCE_POLICY`; the handler case with `gc.autoPackLimit` 1 and `gc.pruneExpire` now shows one pack afterwards and every commit still readable, so the fetched blobs survive the gc it starts.
LFS: the history fetch runs no filter and fetches pointer blobs as committed, under the same `LFS_POLICY`.
The caller is told on standard output; `ghq-writer-client.py:65` writes the reply's `stdout` as it is, and `ghq-sync -u` passes `ghq`'s output through.

### The read side, probed

Scratch root `/tmp/cam136v/rs/root` (on darwin `/tmp` is a link to `/private/tmp`, as `/var` is to `/private/var`), a blobless copy and a blobless bare repository in it made read-only, a scratch `HOME` whose `~/.config/git/config` holds the includes as Home Manager writes them, last and by `path` (`logs/cam136-verify-read-side-scratch-20261127-034842.log`, `logs/cam136-verify-overrides-scratch-20261127-034842.log`).
`git show` of a commit lacking a blob, by how the copy is reached:

| Include forms | `-C /tmp/…` | `-C /private/tmp/…` | cwd `/tmp/…` | cwd `/private/tmp/…` | through a link outside the root | bare, `--git-dir` |
|---|---|---|---|---|---|---|
| unresolved form only | ran the transport | ran the transport | refused | ran the transport | ran the transport | refused |
| resolved form only | refused | refused | refused | refused | refused | refused |
| both, as darwin declares | refused | refused | refused | refused | refused | refused |

This matches design D6 and `logs/hydrate-history-gitdir-forms-stibnite-20261127-003017.log`; on magnetite and pyrite `readlink -f /var/lib/ghq` is `/var/lib/ghq`, so one form covers every spelling there.
What defeats the refusal (the transport ran and failed writing `tmp_pack_*`): `-c protocol.allow=always`, `-c protocol.file.allow=always`, `GIT_CONFIG_COUNT` with that key, `GIT_ALLOW_PROTOCOL=file` (git's allow-list replaces `protocol.*` entirely), a `~/.gitconfig` setting `protocol.allow` or `protocol.<name>.allow` (read after the XDG file Home Manager writes), a `protocol.<name>.allow` in the settings before the includes, and the three includes of finding 3.
`protocol.allow = always` in the settings does not, because Home Manager writes the includes after the settings; `refusesTransport` admits that key for that reason.
The interface's trust boundary covers `-c` and environment overrides, and the capability's covers an account overriding its own configuration, which a hand-written `~/.gitconfig` is; neither `crs58` on stibnite nor `cameron` on magnetite and pyrite has one.

What readers do, with both forms included:

| Command | Result |
|---|---|
| `git -C <copy> log`, `status`, `show HEAD:f`, local `archive HEAD`, `submodule status` | works |
| `git -C <copy> ls-remote origin`, `remote show origin`, `fetch --no-write-fetch-head`, `archive --remote=origin` | refused, `not allowed` |
| `git -C <copy> fetch` | refused, permission error on `.git/FETCH_HEAD` |
| `git ls-remote <copy>`, `git ls-remote file://<copy>`, `git archive --remote=<copy>` from outside the tree | works |
| `git clone <copy> <dir>` (local) | works |
| `git clone --no-local <copy>`, `git clone file://<copy>`, a fetch from the copy into a repository outside, `jj git clone <copy>` | fail as they do without the include: the copy's `upload-pack` cannot send blobs the copy lacks (`could not fetch … from promisor remote` on the remote side) |
| `jj git init --colocate` in a copy | refused, permission (writes the tree) |
| `gh repo view`, `gh pr list` in a real stibnite copy, a scratch global configuration carrying both includes | works; `git ls-remote origin` there refused with `transport 'https' not allowed` |
| `nix eval` of `builtins.fetchGit { url = <copy>; }`, `nix flake metadata git+file://<copy>`, `nix eval git+file://<copy>#v`, `nix eval path:<copy>#v` | works |
| `builtins.fetchGit { url = file://<copy>; rev = <older>; }` | fails with and without the include alike (the revision's blob is absent) |

So a local path under the tree is not a transport git refuses for Nix, and the setting changes nothing Nix does with a copy.
Accounts beyond the Home Manager participants: the NixOS Omnigent workers are evaluated with the human participants (the task 2.1 log lists `omnigent-cameron` and `omnigent-janettesmith` on magnetite); the darwin workers through `omnigent-host.nix:457`; the writer reads no global or system configuration (`environment`, asserted by `test_handler.py`); root is no participant, and its git in a copy would fetch and write the tree, which the capability's trust boundary leaves out.

### `<root>/.lazygit.yml`

The file is `0640`, owned by the writer and its group; the root is `0750` with the same owner; participants are the group's members; neither root has an ACL (`getfacl` on magnetite and pyrite, `ls -le` on stibnite).
lazygit's lookup, read in the tree's lazygit source (`v0.66.3-196-g10f045b`, `pkg/gui/gui.go:483-504`): every ancestor of the repository path, outermost first, then `<gitdir>/lazygit.yml`; the measured run at the installed 0.66.3 is `logs/hydrate-history-lazygit-stibnite-20261127-003500.log` (one `git fetch --all --no-write-fetch-head` without the root file, none with it, with or without `git.autoFetch: true` in the account's file); its two earlier runs that day counted no fetch either way, as design D7 explains.
Migration's new assertions in the migration subtest: `outside_lazygit` (`ls -A … | grep -cvxF .lazygit.yml || true`) fails on any other entry but passes when `.lazygit.yml` is gone, and when the root is missing, as the `wc -l` it replaces did, so the three refused-apply checks cannot see a refused apply remove the file.
The after-apply and after-rollback `lazygit_file` checks fail when the file is missing or its content changed; they cannot fail on owner or mode, because the record directory and the root share one filesystem in the VM, where the rename keeps both whether or not `move_file`'s `chown` and `chmod` run.
The subtest's plan output `rename whole tree` and `rename cameron: done in` show the whole-tree path ran with the file present.

### The darwin writer log

newsyslog (`darwin/shared-reference-tree.nix:193-210`: `_ghq:_ghq`, mode 640, `N`) and activation (`:232-241`) agree on owner and mode, and the activation assertion checks both commands precede the daemon's plist.
The refusals (a link, a non-regular file, another owner, more than one link) are shown in `logs/hydrate-history-c4-log-mode-scratch-20261127-032052.log`.

**Drift warnings** (non-blocking):

- The log step tests the path, then runs `chown` and `chmod`, both of which follow a link (`:236-238`); the writer owns `/var/log/ghq-writer`, so between the test and the change it can put a link there, and root then hands the writer the file it names. The comment at `:228-230` states the step leaves such a file alone. The capability's trust boundary leaves out the writer acting against the tree, not root acting on the writer's behalf; `chown -h`, `chmod -h` or an open-and-`fstat` step would close it.
- Where the log is absent, a handler launchd starts between the test and `install` writes into a file `install` then unlinks: a write through an earlier descriptor did not reach the new file (`logs/cam136-verify-bsd-install-scratch-20261127-034842.log`).
- `/usr/bin/install` onto a directory at `<root>/.lazygit.yml` exits 0 having written a file inside it, so activation succeeds with no provisioned file; onto a link it replaces the link (same log).
- The skill ties `history hydrate failed` to the limit ("unless more than 100,000 blobs are missing, when its answer says `history not hydrated` (or `history hydrate failed`)", `SKILL.md:40`), and gives ` reason: <program> <subcommand> exited <n>` as the failure's reason (`:51`) where the handler also writes `timed out after <n> s running …`, `gave up waiting for the lock`, `refused`, `not a member of <group>`, `cannot open the lock: …` and `unexpected …`. Its waiting note, its 3600 s, exit 75, the log's locations, `sudo journalctl -u 'ghq-writer@*'` and `root:systemd-journal` 0640 (no ACL on magnetite's journal; `cameron` in `wheel` cannot read it unaided) match the code and the hosts.
- The handler cases cover no symlink, type change, gitlink, octopus merge or root commit; the scratch run above does, once, outside the build.

---

## 5. Implementation Signal

- [ ] No unstaged files in the worktree for this change: the code and artifacts are committed, `aab117563` and `3ff10f60` on `main`, `6c53ca38` and `d901fd6b` in the stack, this file on its own commit
- [ ] All related commits have been pushed: `6c53ca38` and `d901fd6b` are not on `main`

**Commit range**: `aab117563`, `3ff10f60`, then `6c53ca38` and `d901fd6b`

Hosts, read-only on 2026-11-27 at about 08:45 UTC: none runs this change; stibnite's root is `drwxr-x--- _ghq _ghq` with no `.lazygit.yml` and its `writer.log` `0644`; magnetite and pyrite have `/var/lib/ghq` `ghq ghq 750` with no ACL and no `.lazygit.yml`.

Open items, which only a deployed host can show (task group 4):

- 4.1 on stibnite: the update of a blobless copy behind its upstream, `--no-lazy-fetch show` of each commit it brought in, lazygit under a terminal with `GIT_TRACE` and no `git fetch`, `git show` outside the range printing `transport 'https' not allowed` and no `Permission denied`, and every alert since the deploy.
- 4.2: `prek run --files` on the changed files; the stack's last recorded run failed on formatting (`logs/hydrate-history-stack-prek-20261127-032331.log`).
- On each host after its deploy: the `history=` tokens in the writer's journal or log for real updates, and the lock-hold time of the first updates of large copies (design D4, D9).
- On stibnite after activation: `writer.log` `0640 _ghq:_ghq`, `.lazygit.yml` present `0640`, and the Omnigent worker's git configuration carrying both includes.
- On magnetite and pyrite after deploy: `.lazygit.yml` present from the tmpfiles rule, and each participant's generated git configuration carrying the include with `protocol.allow = never`.

---

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

- [x] No files, or any existing files are legitimate residue from before schema installation

`ls docs/superpowers/specs/*.md` printed nothing.

---

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

There is no `plan.md`, so no row is marked `[~]`.
The manual checks this change defers are tasks 4.1 and 4.2, listed in §5; the runtime tests cover what 4.1 checks at the interface on NixOS (the hydrated range, the immediate refusal, the file's owner, mode and content) but not lazygit's start-up on a host, which only the D7 scratch run and 4.1 show.

---

## 8. Designation Lint and Discharge Coherence

8a: the behavioral delta (`shared-reference-tree`) uses reference repository, reference tree, participating account, writer, acquisition request, commit and history, each a row of `openspec/specs/world-assumptions/spec.md`; "file contents" resolves to no row.

8b:

| Requirement | Discharged by (S) | Under (W) | Status |
|---|---|---|---|
| A refreshed or deepened reference repository shows what each commit it gained changed | the update, deepen, bound, failure and first-acquisition requirements of the interface delta | none named | partly discharged: commits a refresh brings in by tag fetch, and commits a deepen moves the remote branch to, are covered by no interface requirement (finding 1) |
| A read that needs content the reference tree lacks fails at once | `Participating accounts' git refuses every transport beneath the shared root`; `A revision's diff is readable once the revision and its parents are hydrated` | none named | discharged at the declared configuration; the evaluation that should reject a defeating include does not (finding 3) |

8c: the interface delta names only what the hosts' configuration, the writer and git expose; the behavioral delta names no git command, file or setting.

---

## Overall Decision

- [ ] (pass) PASS — may proceed to finishing-a-development-branch and archive
- [ ] (warn) PASS WITH WARNINGS — may proceed to subsequent steps but note: …
- [x] (fail) FAIL — return to the failed artifact, correct it, then re-run verify

Six findings in §4 hold against the code at `d901fd6b`, none yet on a host: the behavioral refresh and deepen requirement claims commits no walk covers (1); a timeout after the walk drops its token and status line (2); the transport assertion passes includes that defeat the refusal (3); the history fetch's constant filter writes a filter into a promisor copy that has none (4); an `OSError` from starting git in the walk fails the request (5); a migrated tree's own `.lazygit.yml` replaces the provisioned file until activation (6).
Tasks 4.1 and 4.2 remain open.

**Next step**:

Correct the code or the spec for each finding, then re-run verify; CAM-136 stays In Progress.
