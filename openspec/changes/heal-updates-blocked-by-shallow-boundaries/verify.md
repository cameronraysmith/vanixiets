This record verified the automatic heal of the first design of this change, set aside for a report; `design.md`, § "The automatic heal this change set aside", says what each verification found.

# Verification Report

> This file is produced by the `openspec-verify-change` skill after apply completes, to confirm that the
> implementation is consistent with the specs / design / tasks. Any failed check must be returned to its
> corresponding artifact for correction before re-running verify.

**Change**: `heal-updates-blocked-by-shallow-boundaries` (CAM-140)
**Verified at**: `2026-11-28 03:55` UTC, against `xkmoyvll` (`1a6e212f`, `docs(openspec): resolve the heal change's questions and plan its build`) and `lqmntpmv` (`d12c86b5`, `feat(ghq-shared): heal updates a shallow boundary blocks, and keep held history`), on `trunk()` `636a27d7`
**Verifier**: `openspec-verify-change` (omp)

**Verdict**: FAIL.
Two paths leave a copy worse than the failed update left it, and neither says so: a heal round whose fetch fails after its pack has landed (F1), and a request stopped between a round's fetch and the repair (F2).
Everything else the delta specs ask for holds, with the warnings in §4.

## Scope

The handler `pkgs/by-name/ghq-shared/ghq-writer-handler.py`, `handler_fixtures.py`, `test_handler_history.py` and the comment in `test-handler.nix` at `d12c86b5`; the change's documents at `d12c86b5` (brainstorm, proposal, design, `plan.md`, tasks and the three delta specs); the main specs `openspec/specs/shared-reference-tree{,-interface}/spec.md`; `ghq-sync`'s usage text, the skill `dependency-source-acquisition` and the fragment `30-reference-repositories.instructions.md`, which the change leaves as they were; the builder's report `logs/agent-reports-20261126/Cam140Plan.md` and logs `logs/cam140-build-*`, each read as a claim.
The builder's check and mutant runs were made at `bdebe055`; `d12c86b5` holds the same handler and `handler_fixtures.py`, and differs only in the test script's docstring and the comment in `test-handler.nix`.
Line numbers below are of the files at `d12c86b5`.

## Method

Every requirement and scenario the delta specs add or amend was read against the code path that implements it, then tried in scratch repositories under `/tmp` on stibnite with git 2.56.0, lazy fetching off.

- Handler functions called directly (`heal`, `repair`, `check_reach`, `walk_history`), the module loaded from `d12c86b5`'s source: history shapes (a merge in the gap of a branch forked below a depth-5 clone's floor with a tag below a boundary; an octopus in the gap whose legs fork from held history with a second branch sharing that history; an unrelated root merged in the gap; a replace ref on held history), the limit at 1, 2, 3, 4, 23, 24 and 25 commits, a round whose pack lands without its `.git/shallow` update, and a round's fetch completed with the repair skipped (`logs/cam140-verify-scratch-shapes-20261127-225204.log`).
  Each shape compares, for every ref including tags and `HEAD`, the set of commits reachable before the heal with the set after, not counts.
- The whole handler over a socket pair, with the test suite's fixtures: a heal whose second round's remote stalls after sending its pack (`logs/cam140-verify-stalled-round-20261127-224646.log`, script `logs/cam140-verify-stalled-round.py`, wrapper `logs/cam140-verify-stall-tail-upload-pack.py`; the run at `224637` failed setting up, its wrapper naming an interpreter the handler's `PATH` lacks), and a heal whose handler is killed where the repair would run (`logs/cam140-verify-killed-before-repair-20261127-224708.log`).
- `test_handler_history.py` of `d12c86b5` run directly against `d12c86b5`'s handler with the store paths of the `trunk()` build substituted, against `trunk()`'s built handler (`/nix/store/ghxrsv0s…-ghq-shared-0.1.0`, the same handler source as `636a27d7`), against two of the builder's mutants (no repair; the upstream-side range without `^held`) and against one of mine (a failed check restores the boundaries the repair removed) (`logs/cam140-verify-history-{new,trunk,mut-*}-20261127-224318.log`).
- The case "a timeout after the history fetch" four times at `trunk()` (its handler and its tests) and four times at the change (`logs/cam140-verify-timeout-case-repeats-20261127-224718.log`).
- The check's walk timed read-only on copies in the reference tree, on a copy of `.git/shallow` in `/tmp` (`logs/cam140-verify-check-cost-20261127-225213.log`).

Read only, not run: the builder's mutants "deepen heal" and "after-view check", the `aarch64-darwin` and magnetite check timings, the writer configuration evaluation, and the rehearsal logs `logs/cam140-plan-*`.

## 1. Structural validation

```text
openspec validate heal-updates-blocked-by-shallow-boundaries --strict: Change 'heal-updates-blocked-by-shallow-boundaries' is valid
```

## 2. Task completion

16 of 19 tasks in `tasks.md` are `- [x]`; 6.1, 6.2 and 6.3 wait on the deploys (§6); every step of `plan.md` is ticked.
The ticked tasks' evidence was checked against the logs they name; each new case fails against `trunk()`'s handler and 1.5 passes there, as the tasks say (`cam140-verify-history-trunk-…`: 1.1, 1.2, 1.3, all four clones of 1.4, 1.6 and 3.1 fail).

## 3. Findings

### F1 (FAIL): a round that fails after its pack landed makes the copy unreadable, and every later update fails

`repair` (`ghq-writer-handler.py:973-992`) counts a parent as held when its object is present (`absent`, `:989`).
A382, on which the repair rests, makes the stronger claim: an entry can go when its commit's parents *and their history* are present.
A depth fetch that fails after git has stored its pack, and before git renames `shallow.lock` over `.git/shallow`, leaves exactly that gap: the round's commits are present, the deepest with absent parents, and none of them is a boundary.
`heal` then repairs (`:1104-1108`) the boundaries the previous round placed, whose parents that pack supplies, and the check (`:995-1025`) cannot see the hole, because it walks under the boundaries of the heal's start, which stop it above the exposed chain.

Reproduction (`logs/cam140-verify-stalled-round-20261127-224646.log`): upstream holds `c1`..`c40`; a blobless clone holds `c1`..`c20` and `c40` fetched by id at depth 1; upstream adds `c41`; the clone's `upload-pack` withholds the final flush of the reply to a request deepening to 6; an update runs under a `commandTimeout` of 6 s.
The first round heals nothing, the second times out after its pack landed, and the repair removes the first round's boundary.
The reply is `exit 124` with only `ghq-writer: timed out after 6 s running git fetch`; the log line is `heal=failed reason: timed out after 6 s running git fetch`.
`.git/shallow` is gone, and `git --no-lazy-fetch log origin/master` exits 128 with `error: Could not read <oid>`.
The next two updates, with the remote healthy, exit 1 with `Could not read <oid>` and `revision walk setup failed`, and attempt no heal, because `heal` returns at an empty `.git/shallow` (`:1075-1078`); the copy stays so until someone repairs it by hand.
Before the heal, `origin/master` read and the copy was a valid shallow clone; at `trunk()` the same update fails with git's refusal and leaves it so.
The trigger reproduced is a remote that stalls after a pack's last byte, which the command timeout then stops; a connection dropped there, or the handler killed there, should leave the same objects, since git commits `.git/shallow` only after the pack is stored (inference from that order, not run); so should a heal whose round meets commits an earlier killed fetch left in the object store (the shapes log simulates the state directly).
It violates "A heal that cannot complete leaves the update's outcome as it was" (interface delta, line 103: every ref reaching what it reached) and "A refresh that cannot move past history held in part leaves the reference repository as it was" (behavioral delta, line 37).

Smallest remedy: count a boundary as on held history only when every parent is a commit the walk of the heal's start refs under the start's boundaries lists, which is the history those refs reached; run that walk before the repair, which then needs no separate check for this purpose.
A case with the wrapper above, asserting that `origin/master` stays walkable and the next update heals, fails against `d12c86b5`.

### F2 (FAIL): a request stopped between a round's fetch and the repair hides held history for good, and no answer says so

The repair's start is held in memory only (`heal`, `:1075`; `run_deepen`, `:1175`).
A handler stopped after a round's `git fetch --depth` committed its boundaries and before `write_shallow` (`:951`) leaves boundaries on held history, which no later request removes: a later heal treats them as present at its start, and the next update usually fast-forwards with no heal at all.
Reproduction (`logs/cam140-verify-killed-before-repair-20261127-224708.log`, the repair replaced by `SIGKILL`): the killed request sends no reply; the next two updates exit 0 with no heal or repair line; the old `master` commit reaches 3 of its 23 commits from then on.
Other paths into the same state, by reading, not run: `ghq-sync --deepen` timing out after its fetch committed the new boundaries (`:1178` raises before `keep_reach`); the repair raising for any reason (`FileExistsError` on a `shallow.lock` a `SIGKILL`ed git left, a timed-out `cat-file`, `.git/shallow changed while it was rewritten`), which the reply reports as `heal failed: … (repair: …)` or `repair failed: …`.
The stated hole, a failed repair write, is the reported member of this class; the stop is not stated anywhere in the change, and the behavioral requirement "Moving past history held in part never hides history a reference repository held" (behavioral delta, line 23) allows hiding only when "the writer's answer says" so, and a stopped request gives none.
Smallest remedy: before a heal's first fetch, and before a deepen's, write the start's boundaries beside the copy's record (`.git/ghq-writer-hydrated` is written the same way, `:695-704`), and have every request under the lock repair against a start it finds there before anything else, removing it after a check; F2's reproduction, and a failed repair write, would then be repaired at the next request, which a case killing the handler at the repair can assert.

### The three departures from the design

| Departure | Reasoning | Documents now | Test that fails when reverted | A shape where it is wrong |
|---|---|---|---|---|
| (1) The check walks under the boundaries of the start and after the repair together (`check_reach`, `:1014-1020`) | Right. A ref's walk under `start ∪ now` lists exactly what it reached at the start, cut by the new boundaries; an added boundary in that listing is a commit whose parents the ref reached, and no added boundary listed means each ref reaches at least what it did. Under `now` alone the ref the first attempt moved walks through the gap to boundaries on history never held. | D3 (`design.md:52`), the interface requirement at line 52 and tasks 2.2 say the same as the code | The builder's "after-view check" fails 1.3 and 1.6 (`logs/cam140-build-mutant-after-view-check-20261127-220656.log`, read) | None among the shapes built: merges below the floor, an octopus, a shared side branch, an unrelated root, tags below boundaries, a replace ref; each kept every ref's set. It does not see F1's hole, which lies past a start boundary. |
| (2) A failed check leaves the repaired `.git/shallow` (`keep_reach`, `:1047-1049`) | Right for what the check can catch: putting the fetch's file back re-hides held history, which is the cut the change exists to undo. | D3, D6 and the requirement at line 52 | My mutant restoring the removed boundaries fails 1.4's check clone (`master` 6 → 3, a held boundary) (`cam140-verify-history-mut-restore-on-check-failure-…`) | F1's state is a failed round, not a failed check; leaving the repair there is wrong, but the cause is the repair's test of "held", not this choice. |
| (3) Below an upstream-side removed boundary the walk also excludes what the recorded refs reach (`walk_history`, `:776-781`) | Right: those commits were walked when the record was written; without the exclusion the range below the gap runs through the whole held history and passes `historyLimit`. | D7 and the interface requirement at line 114 | The builder's "walk-repaired-stops-only" mutant, re-run here: 1.3 lists 1 old commit (`cam140-verify-history-mut-walk-repaired-stops-only-…`) | A boundary the heal's fetch removed on the recorded refs' side (a floor deepened through) is not upstream-side and keeps its range without `^held`, so what lies below it is walked. |

## 4. Requirements

| Requirement | Evidence | Result |
|---|---|---|
| An update heals a fast-forward a shallow boundary blocks (interface, line 3) | entry test `heal`, `:1068-1085`; second `ghq get` only when healed, `run_get`, `:1137-1147`; cases 1.1 and 1.5; every scratch shape healed and its second pull exited 0 | PASS |
| A heal fetches the upstream branch to a doubling depth (line 23) | `:1090-1103`; K = gap + 1, doubled; stops on ancestor, merge base, or no boundary in the gap; the clone's remote and filter kept (case 1.3) | PASS |
| A heal removes the boundaries its fetch placed on held history (line 41) | `repair`, `write_shallow`, `:951-992`; `shallow.lock` with `O_EXCL`, renamed, removed when empty; the test of "held" is object presence (F1) | FAIL (F1) |
| A heal checks that every ref still reaches what it reached (line 52) | `check_reach`, `:995-1025`; exact for refs under `refs/heads` and `refs/remotes`; tags and a detached `HEAD` are not walked, which the repair covers when its test of "held" is right (W3) | PASS WITH WARNING |
| A heal is bounded by the commits it brings in (line 70) | `:1093`, `> limit`, counted before each round: counts `[2, 3, 6, 12]` before the rounds of a 23-commit gap; limits 1 to 4 stop with `more than <limit> commits`, 23 to 25 heal at depth 24; `HEAD`, `origin/master` and every ref unchanged when stopped | PASS |
| The writer's reply says what a heal did (line 81) | `Heal`, `:1050-1066`; order after the first attempt, `:1140-1147`; a heal that times out drops the line and the first attempt's output (W1) | PASS WITH WARNING |
| The writer's exit log line names what a heal did (line 92) | `main`, `:1336-1341`; observed `heal=failed` before `reason:` in F1's run, and `heal=healed:<K>` before `history=` in case 1.1 | PASS |
| A heal that cannot complete leaves the update's outcome as it was (line 103) | status kept, no second attempt, phase by type (case 1.4, four clones); fails for a round that fails after its pack landed | FAIL (F1) |
| The history walk of a healed update stops at what the clone held before (line 114) | `walk_history`, `:740-787`; 1.3's walk lists no old commit; the tag commit in 1.1 is hydrated against its parent | PASS |
| A deepen removes the boundaries it placed on held history (line 125) | `run_deepen`, `:1165-1194`; case 3.1; a deepen on a full clone or to the roots adds no boundary, so the repair and check do nothing; a deepen that times out skips the repair (F2) | PASS WITH WARNING |
| A request that brings in no commit runs no history walk, as amended (line 138) | case 1.2 under `healLimit` 0 walks nothing | PASS |
| A refresh succeeds when upstream's branch has moved past history held in part (behavioral, line 3) | the interface requirements above; cases 1.1 and 1.3 | PASS |
| Moving past history held in part never hides history a reference repository held (behavioral, line 23) | holds for every completed request in the shapes; a stopped request hides held history with no answer | FAIL (F2) |
| A refresh that cannot move past history held in part leaves the reference repository as it was (behavioral, line 37) | case 1.4; not for F1's failed round | FAIL (F1) |
| A380, A381, A382 (world assumptions) | A380 and A381 observed in the cases' red runs; A382's read of `shallow.c` is the builder's; A382 says parents *and their history*, the repair tests parents alone (F1) | PASS as assumptions |

Warnings:

- W1: `serve` turns a `TimedOut` the heal re-raises into `Session.fail` (`:1303-1304`, `:1232-1238`), which keeps a history status line but not the heal's, nor the first attempt's output: F1's reply is the timeout line alone, against the interface requirement at line 81 ("SHALL carry … one status line"). Remedy: `Session.fail` appends `session.heal`'s standard error as it does the history's, or the requirement names the exception.
- W2: readers are told nothing of the heal or of what to do after `shallow boundary heal failed: … (repair: …)` or `shallow boundary repair failed: …`, though the behavioral requirement at line 23 makes such an answer the one admitted case of hidden history; the skill and the fragment are silent, and `ghq-sync`'s usage text says fetch mode preserves "ghq's own output and exit status" (`ghq-sync.sh:87-88`), which a healed update on a host-shared tree does not (ghq's first exit 1 becomes 0, with a line ghq did not print). Remedy: one sentence in the skill and the usage text saying a blocked update heals, and that after a repair failure the copy's branches may hide commits until the writer's sweep or a re-clone.
- W3: the check walks `refs/heads` and `refs/remotes` only; tags and a detached `HEAD` keep their history only through the repair's test, so F1's remedy covers them too. In the shapes, tag `t-low` below a boundary and `HEAD` kept their sets.
- W4: a round can overshoot the limit by the depth's growth (D4 states it: nixpkgs from 32 to 64 generations goes from 64,034 to 589,653 commits within reach); the command timeout bounds that round, and no heal of that size was run.

## 5. Tests, mutants and cost

- `d12c86b5`'s handler with its tests: `every history case behaved`, 36.2 s outside Nix; four more runs 35 to 41 s, against 25 to 27 s for `trunk()`'s handler with `trunk()`'s tests on the same Mac.
- Mutants re-run: "no repair" fails 7 assertions (1.3, 1.6, 3.1, 1.4); "walk-repaired-stops-only" fails 1.3's walk; mine, a failed check restoring the removed boundaries, fails 1.4's check clone.
- No case fails against the F1 or F2 state: the suite has no failed or stopped round after a fetch landed.
- "A timeout after the history fetch": failed 1 of 4 runs at `trunk()` with `trunk()`'s tests and 0 of 4 at the change, and the builder's red run at `trunk()` failed it on `git ls-remote` timing out. It is timing-sensitive independent of this change: every command of that request runs through a Python `upload-pack` wrapper under a 2 s limit; the change adds no command to that request, whose first `ghq get -u` succeeds.
- Size classes: the builder's magnetite timings, read, are 31.1 and 32.5 s for the history check and 48.3 and 48.0 s for the request check, under the 60 s class; the history check grew by about 10 s, as it did here outside Nix.
- The check's walk: 7.1 to 8.9 s on stibnite's nixpkgs copy (1,131,622 commits, 398,333 merges held), under 0.6 s on hermes-agent (69,600), llm-agents.nix (25,262, 11,825 merges) and nix (24,993); nixpkgs is the largest held history in the tree. It runs once per heal or deepen that adds a boundary, inside a 3,600 s command limit. An update that needs no heal runs nothing new: a full clone's failed update reads `.git/shallow` and returns; a shallow clone's runs `symbolic-ref`, `for-each-ref`, `merge-base` and one `rev-list` of the gap.

## 6. What remains for deployed hosts

- 6.1 to 6.3 as `tasks.md` states them, after F1 and F2 are remedied: the at-risk scans on stibnite, magnetite and pyrite, the deploys with their alerts, and `ghq-sync -u` of `github.com/davidjo/snd_hda_macbookpro` and `github.com/withastro/astro` healing, each ref's count no smaller, `fsck --connectivity-only` passing and the filter kept.
- On stibnite: `git --no-lazy-fetch log` of each healed copy's remote-tracking branch exiting 0, which F1 shows `fsck --connectivity-only` alone does not establish in a blobless copy.
- The first heal of nixpkgs, if one occurs: its duration and the commits it brought in against the limit.

---

## 7. Re-verification of the remedies, 2026-11-28

**Verified at**: `2026-11-28 04:55` UTC, against `lunpnpuv` (`53ee9a30`, `fix(ghq-shared): count a parent as held only when the starting refs reached it, and repair a stopped heal at the next request`), `msmzovvs` (`0bc9bd9f`, `docs(ghq-sync): say what a healed update's reply holds and what follows a repair failure`) and `uxmtxuyk` (`19011827`, `docs(openspec): record the verification's remedies for healing updates`).
Only what these three commits change is checked; §1 to §6 are not repeated.

**Verdict**: FAIL.
F1, F2 and W1 to W3 are closed, each by experiment.
One new path hides held history for good after an answer that promised otherwise (F3): a pending repair file is overwritten by the next heal or deepen when the repair it records fails in that same request.

### Method

The handler of `53ee9a30`, its three store paths substituted from the `trunk()` build (`ghq-sync` and `ghq-writer-client` are unchanged since that build; `msmzovvs` changes `ghq-sync`'s usage text only), driven over a socket pair with the change's own `handler_fixtures.py`, on stibnite with git 2.56.0:

- My first round's scripts, re-run unchanged but for the fixtures' path: `logs/cam140-reverify-stalled-round-20261127-233012.log`, and `logs/cam140-reverify-killed-before-repair-20261127-233208.log` (its line filter widened to match `repaired shallow boundaries`; the run at `233012` used the narrower filter).
- New: a `deepen` whose client times out after its fetch committed boundaries, an exception in a heal's repair, and the handler killed during a stalled round (`logs/cam140-reverify-variants-20261127-233208.log`, script `logs/cam140-reverify-variants.py`); git itself killed while it holds `shallow.lock`, the restore after unrelated failures and after a lost commit, and the repair file as a directory, a symbolic link to garbage, truncated, naming absent commits, failing on every request, met by `hydrate` and `promote`, and its mode (`logs/cam140-reverify-attacks-20261127-233320.log`, scripts `logs/cam140-reverify-attacks.py` and `logs/cam140-reverify-helpers.py`); a repair file whose repair fails in a deepen (`logs/cam140-reverify-overwrite-20261127-233438.log`).
- The three test scripts against the handler, and the boundary script against two of the builder's mutants rebuilt here (`logs/cam140-reverify-suite-*-20261127-233717.log`, and `logs/cam140-reverify-suite-v2-handler-with-client-*.log` for `test_handler.py`). The suite logs at `233544`, and the `test_handler.py` runs at `233717` and `234717`, are void: the first ran with `GIT_NO_LAZY_FETCH` left set in the shell, the others without `ghq-writer-client` beside the handler, which the script's client case needs.
- Read-only on stibnite's nixpkgs copy, the restore's and the repair's walks timed (`logs/cam140-reverify-restore-cost-20261127-234500.log`).

Read only, not run: the builder's mutants "no journal" and "no restore", the darwin and magnetite check timings, and the red run of the boundary script.

### F3 (FAIL): a heal or deepen overwrites a pending repair file whose repair failed, and the history it recorded stays hidden

`recover` (`ghq-writer-handler.py:1103-1133`) leaves `.git/ghq-writer-repair` when its repair fails and says "the next request tries again"; the same request then goes on, and a deepen (`run_deepen`, `:1317`) or a heal's first round (`:1231`) calls `keep_start`, which writes the file afresh from the refs and boundaries as they are now (`:1086-1090`).
The boundaries the stopped request left on held history are then part of the new start, so no later repair removes them, and no later answer mentions them.
Reproduction (`logs/cam140-reverify-overwrite-20261127-233438.log`): a stopped heal's state (repair file naming the start, a depth-24 fetch leaving the old `master` reaching 3 of its 23 commits); a deepen whose request has `reached_among` raising `OSError` replies twice `shallow boundary repair failed: … (repair: OSError; …)`; the next two updates exit 0 with no line, the repair file gone, and the old `master` reaching 4 of 23 from then on.
A real trigger needs a repair that fails in the request after a stopped one: for one, a `shallow.lock` a killed git left (staged below), on which `write_shallow` raises `FileExistsError`, and the next request being a deepen or a heal.
It contradicts the behavioral requirement "Moving past history held in part never hides history a reference repository held" (`specs/shared-reference-tree/spec.md`, line 25: hidden history repaired "by the end of the next request … whose answer says it repaired the history") and the interface requirement "A heal or deepen stopped before its repair is repaired by the next request" ("leaving the file when that repair fails").
Smallest remedy: `keep_start` leaves a repair file that is already there, or merges into it (the refs of both, the older boundaries); the case is the overwrite script above, failing now.

### The findings of the first run

| Finding | Now | Evidence |
|---|---|---|
| F1: a round failing after its pack landed | Closed. A parent counts as held only when the starting refs reached it under the starting boundaries (`reached_among`, `:1002-1027`; `repair`, `:1030-1053`). My stalled round: exit 124, the reply holds git's refusal and `shallow boundary heal failed: … (fetch: timed out after 6 s running git fetch)`, `.git/shallow` stays, `origin/master` walks, and the next update heals at depth 32. The builder's "held by presence" mutant, rebuilt here, fails both of the boundary script's stall and hang-up cases | stalled-round log; `cam140-reverify-suite-mut-held-by-presence-boundary-…` |
| F2: a request stopped before its repair | Closed but for F3. My kill: the next update says `repaired shallow boundaries: … (1 boundaries an interrupted request left on held history removed)`, the old `master` reaches 23 of 23, the file is gone. A deepen whose client times out after its fetch committed (`:1320` raises before the repair): the old `master` 38 → 1, the next update repairs it to 38. A heal whose repair raises: `heal failed: … (repair: OSError)`, old `master` 3 of 23, the next update repairs it to 23. The handler killed during a stalled round: the file stays, `origin/master` walks, no boundary on held history, the next update heals | killed-before-repair and variants logs |
| W1: a timed-out heal's reply | Closed: `Session.fail` (`:1376-1385`) carries `session.kept`, which `run_get` fills before re-raising (`:1284`) | stalled-round log |
| W2: readers' words | Closed: `ghq-sync.sh` (the `-u` option and the fetch-mode paragraph) and the skill (`SKILL.md`, line 47) say what a healed update's reply holds and that the next request repairs after a repair failure; each sentence matches the code, except that a time-out ending a deepen says nothing of a cut until the next request (W8) | read against the code |
| W3: tags and a detached `HEAD` | Closed: `held_refs` (`:659-676`) peels tags fully (a tag of a tag peels to its commit, checked with git 2.56.0) and adds `HEAD`; the builder's "branch refs only" mutant, rebuilt here, fails "a deepen must keep the history of a tag and a detached HEAD" | `cam140-reverify-suite-mut-branch-refs-only-boundary-…` |

### The restore after a failed update

`restore` (`:1169-1181`) runs after every failed update of a promisor copy, before the heal, under the copy's lock (`serve` takes the lock at `:1436` before anything else); a full copy gets none (a full clone with a commit lost from its pack: no line, no `.git/shallow`).
An update failing for an unrelated reason (the remote gone) on a shallow blobless copy runs one `rev-list --missing=print`, writes nothing and prints nothing; on stibnite's nixpkgs copy that walk takes 6.8 to 8.6 s, on every failed update of it.
A blobless copy that is not shallow, with one commit lost from its pack: the failed update marks its child, `.git/shallow` appears, `master` reaches 5 of its 10 commits, and fetching the lost commit back by id afterwards restores nothing, the boundary staying (W6).

### The repair file

- Mode `-rw-r-----` and the writer's owner, as `.git/ghq-writer-hydrated`; `.git` on the deployed tree is `drwxr-x---` `_ghq:_ghq`, so no reader writes it.
- A request with no repair file opens nothing more than the file's absence; with a file whose repair removes nothing, one walk of the start's refs.
- Garbage, a truncated line, or a link to garbage: `shallow boundary repair skipped: … (ghq-writer-repair is unreadable; removed)`, then the request as without it. Naming only absent commits: no line, removed. A repair failing on every request: `shallow boundary repair failed: … (repair: OSError; the next request tries again)` on each, exit 0 each.
- `hydrate` and `promote` meeting a pending file: each repairs first and says so (old `master` 3 → 23), then hydrates or promotes.
- A directory in its place: the update that needs a heal exits 70 with `unexpected PermissionError`, because `drop_start` (`:1093-1095`) suppresses only `FileNotFoundError` and the heal calls it outside its `PhaseFailed` handler (W5).
- Two requests for one copy: `recover` runs after `hold`, so the second waits for the first; read, and covered by `test_handler.py`'s concurrent-update cases, which pass.

### Warnings

- W5: a directory, or anything `unlink` refuses, at `.git/ghq-writer-repair` ends a heal or deepen with status 70, against "never 70 for the heal's own failure"; only the writer can make that state. Remedy: `drop_start` suppresses `OSError` and the line says so.
- W6: the restore hides a lost commit's present ancestors and keeps them hidden after the commit returns; design.md's "Marking hides nothing: nothing below those commits could be read" (line 122) is false there, and the line names no recovery. Remedy: fetch the absent commits by id from the promisor remote first and mark only what stays absent, or correct the sentence and the line.
- W7: git killed with `SIGKILL` while it holds `shallow.lock` leaves the lock; every later update of the copy then fails with git's "lock file may be stale" and `shallow boundary heal failed: … (fetch: git fetch exited 128)`, and nothing removes it (attacks log, V4). git's own behaviour, now met by more depth fetches; the reply quotes git's message.
- W8: a deepen that a time-out ends after its fetch committed answers only `timed out`, though the history it cut stays hidden until the next request repairs it.
- W9: the new reliance on `git rev-list --missing=print` naming absent commits with lazy fetching off, and on a `--shallow-file` walk failing at an absent commit, is witnessed by the cases but named in no assumption; A382 could carry it.

### Tests, cases and classes

- The boundary, history and request scripts pass against `53ee9a30` (35.9 s, 28.4 s and 49.4 s outside Nix).
- No case was lost in the split: every assertion message of `d12c86b5`'s `test_handler_history.py` is in `53ee9a30`'s history or boundary script, which add 12 more; `test_handler.py` is unchanged.
- `package-ghq-shared-test-handler-boundary` is declared as its neighbours are (`modules/checks/package-tests.nix`): `small` with `measured = false` on `x86_64-linux`, `medium` with `measured = false` on `aarch64-darwin`, and listed in `ghq-shared`'s tests and `package.nix`.
- The builder's magnetite timings, read: boundary 23.5 and 30.5 s, history 21.6 and 33.4 s, request 49.2 and 49.8 s, against 48.3 and 48.0 s for the request check in the first round; this round added about 1.3 s there, now at 82 to 83 % of its 60 s class, the second run under memory pressure.
- No case covers F3, W5 or W6.

### What remains

- F3's remedy and its case, then a run of this section's scripts.
- §6's host checks, and on stibnite the first `restored shallow boundaries` or `repaired shallow boundaries` line the writer's log shows, with the copy's refs walkable afterwards.

---

## 8. Verification of the repair-file and removal remedies, 2026-11-28

**Verified at**: `2026-11-28 05:20` UTC, against `kunxsoxr` (`db18e9ba`, `fix(ghq-shared): keep a pending repair file, and drop the restore of boundaries after a failed update`) and `quumvvry` (`e44b1d92`, `docs(openspec): record the second verification's remedies for healing updates`).
Only what these two commits change is checked; §1 to §7 are not repeated.

**Verdict**: FAIL.
F3 is closed, the restore is gone without a trace in code, cases, specs or readers' text, and W5, W8 and W9 are closed.
Keeping the older repair file leaves one path that hides held history for good, and then answers that it repaired the history (F4).

### Method

The handler of `db18e9ba`, its three store paths substituted from the `trunk()` build, with `ghq-writer-client` of that build beside it, driven over a socket pair with the change's fixtures, on stibnite with git 2.56.0:

- My F3 script, unchanged (`logs/cam140-reverify2-overwrite-20261128-001606.log`).
- New: a heal stopped at its repair, then an update and a deepen stopped at its repair, then ordinary updates, once with every request's recovery passing and once with the pending file's repair failing in the update and the deepen (`logs/cam140-reverify2-nested-20261128-001348.log`, script `logs/cam140-reverify2-nested.py`); my W6 copy after a failed update (`logs/cam140-reverify2-w6-20261128-001546.log`); a directory, a FIFO and a dangling symbolic link at the repair file's path, each also with a heal stopped at its repair; a deepen a time-out ends after its fetch; a leftover `shallow.lock` (`logs/cam140-reverify2-attacks-20261128-001437.log`, scripts `logs/cam140-reverify2-attacks.py` and `logs/cam140-reverify2-nested-helpers.py`).
- The boundary, history and request scripts against `db18e9ba`, and the boundary script against `lunpnpuv`'s handler (`logs/cam140-reverify2-suite-*-20261128-001557.log`).
- git 2.56.0's `promisor-remote.c` and `revision.c` from the source tarball the fleet builds (`/nix/store/454fdxl1…-git-2.56.0.tar.xz`), `launchd.plist(5)` on stibnite, and the writer's launchd plist and systemd units in `modules/{darwin,nixos}/shared-reference-tree.nix`.

Read only: the builder's red log (`logs/cam140-reverify-fix-red-boundary-20261127-235439.log`) and magnetite timings (`logs/cam140-reverify-fix-magnetite-*.log`).

### F4 (FAIL): a cut on history only newer refs reached, made while an older repair file is pending, stays hidden, and the next answer says the history was repaired

Whether a request wrote the repair file is decided in memory: `keep_start` (`ghq-writer-handler.py:1085-1104`) returns whether it wrote it, and the heal (`:1201-1216`) and the deepen (`:1288-1303`) remove it only then.
A heal or deepen that meets a pending file repairs its own cut in the same request against its own start, held in memory; when that request is stopped before its repair, or its repair fails, nothing records its start, and the next request repairs against the older file alone, which covers only what the older refs reached.
Reproduction, the faulted run of the nested script: a heal stopped at its repair leaves the file (the old `master` at 3 of 23 commits); an update whose recovery fails moves `master` to a commit reaching 28; a tag-like depth-1 fetch adds a boundary five commits above it; a deepen by 5 whose recovery fails is stopped at its repair, leaving that `master` commit reaching 1 of 28.
The next update says `repaired shallow boundaries: … (1 boundaries an interrupted request left on held history removed)`, the old `master` is back to 23 of 23, the file is gone, and the `master` commit the deepen cut reaches 1 of 28 then and after two more updates, which say nothing.
With every request's recovery passing (the ordinary run), each stopped request is repaired by the next: no history stays hidden.
The trigger therefore needs the pending file's repair to fail in two consecutive requests while their fetches succeed, the second being a stopped or failed heal or deepen; I found no fault that does this without injection (a stale `shallow.lock`, the one real cause staged in §7, also fails the fetches), so this path is narrow, but it hides history and then answers that the history was repaired, which the standard of §3 counts as a FAIL.
It contradicts the behavioral requirement that hidden history be repaired "by the end of the next request … whose answer says it repaired the history" (`specs/shared-reference-tree/spec.md`, line 25).
Smallest remedy: a request whose recovery failed starts no heal or deepen, saying so (`shallow boundary repair pending: …`); the alternative, a second record kept beside the first and repaired against in turn, is larger.

### The first-round and second-round items

| Item | Now | Evidence |
|---|---|---|
| F3 | Closed: my script, unchanged, now ends with the next update saying `repaired shallow boundaries` and the old `master` at 23 of 23, the file gone | overwrite log |
| A file written by one request, that request killed, the next repairing | Clean: the next request's recovery removes the file whoever wrote it (`recover`, `:1123`), and the ordinary nested run shows each stopped request's file repaired and removed by the next, with no file left | nested log |
| The restore | Gone: no `restore`, `restored shallow boundaries` or its requirement remains in the handler, the boundary script, the interface delta, `ghq-sync`'s usage text or the skill; the design records its removal. My W6 copy after a failed update: exit 128, no status line, no `.git/shallow`, no history walk among the commands the handler ran; `.git` gains only `ghq-writer-hydrated`, which the history snapshot writes when absent, as at `trunk()`. A failed update now runs no history walk: on failure `run_get` calls only `heal` (`:1248`), which returns at an empty `.git/shallow` or after `upstream_of`, one `merge-base --is-ancestor` and one listing of the gap above `HEAD` (read; the recorded commands of the W6 run show no `rev-list` or `log`) | w6 log |
| W5, a non-file at the repair file's path | Closed for a directory: `shallow boundary repair skipped: … (… unreadable and cannot be removed; the tree's writer removes it)` and exit 0. Open for two others (W10) | attacks log |
| W7, a leftover `shallow.lock` | Named, not removed: each request says `shallow boundary lock present: …` and the heal fails at its fetch as git refuses; the file stays (W11) | attacks log |
| W8, a deepen a time-out ends | Closed: exit 124 with `shallow boundary repair pending: … (the deepen was stopped before its repair; the next request for this repository repairs it)`; the next update repairs it (old `master` 6 → 23 of 23) | attacks log |
| W9, the assumption | Closed: in git 2.56.0, `fetch_objects` (`promisor-remote.c:24`) returns -1 at once when `GIT_NO_LAZY_FETCH` is set, and `get_revision_1` (`revision.c:4436`) dies with `Failed to traverse parents of commit` when `process_parents` fails in a streaming walk (`:4488-4491`), unless `ignore_missing_links` is set, which a plain `rev-list` does not; the topological walk dies the same way (`:3973-3976`). The scenario's citation holds; the observed exit 128 with that message is in §7's stalled-round runs | read |

### The `shallow.lock` reasoning

`run` starts every command in a process group of its own (`process_group=0`).
On darwin the writer is an inetd-style launchd job (`modules/darwin/shared-reference-tree.nix`, no `AbandonProcessGroup`), and `launchd.plist(5)` says that when a job dies launchd kills the remaining processes "with the same process group ID as the job": a git the handler started is in another group, so it outlives a killed handler, and the per-repository lock, an `flock` on the handler's descriptor, is released while that git may still be writing.
On NixOS each request is an instance of `ghq-writer@`, with systemd's default `KillMode=control-group`, under which the instance's whole control group is stopped with it (systemd's documented default, not run here), so there no git outlives its handler.
Naming the file without removing it is right: on darwin the writer cannot tell a stale lock from one a live git holds, and removing a live one would let two gits write `.git/shallow`.

### Warnings

- W10: a FIFO at `.git/ghq-writer-repair` hangs the request in `read_record`'s `open` (`:705`) with the per-repository lock held: no reply within 30 s, and every later request for the copy waits for the lock until it gives up; a dangling symbolic link there reads as no file, yet `keep_start` treats it as present (`os.path.lexists`), so no request writes a repair file, and a heal stopped at its repair then hides the old `master` (3 of 23) with every later reply silent, as does a directory, whose replies say only that the file was skipped. Only the writer can make these states. Remedy: `read_record` opens the repair file with `O_NOFOLLOW | O_NONBLOCK` and requires a regular file, and `keep_start` treats anything but a regular file as unreadable and says that the repair cannot be recorded.
- W11: the lock line ends "once no git runs in it, the tree's writer removes it", but nothing in the writer removes it, and a reader cannot; the line can say that an administrator of the tree removes it after checking that no git runs in the copy (on darwin, `pgrep -f <path>`).

### Tests and sizes

- The four new cases fail against `lunpnpuv`'s handler (re-run here: "a deepen a time-out ends after its fetch must say the next request repairs it", "a directory in the repair file's place must fail no request", "a shallow.lock present when a request begins must be named in its reply", "the update after a failed repair and a deepen must repair against the earlier start") and pass against `db18e9ba`, as the builder's red log says; the boundary, history and request scripts pass (30.3 s, 24.5 s, 48.5 s outside Nix).
- No case covers F4, W10 or W11.
- `kunxsoxr` changes only the handler and `test_handler_boundary.py`; `test_handler.py` and the fixtures are untouched. The handler's change on the request path is one `lexists` per request and the restore's removal, so this round adds nothing to the request check.
- The request check ran 48.9, 59.4, 48.1 and 47.9 s on magnetite (builder's logs, read), the 59.4 s run under memory pressure (`some avg60` 6.30) and the next two under a load average near 17 and 9. The 59.4 s run comes from the request half's own size under load, which the second round's 1.3 s brought closer to its 60 s class; it is not this round's, and belongs in a separate report on that check's class.

### What remains

- F4's remedy and its case (the faulted nested run, failing now), then a run of this section's scripts.
- §6's host checks, with the first `repaired shallow boundaries` or `shallow boundary lock present` line the writer's log shows on a host.

---

## 9. Verification that no heal starts while a repair is pending, 2026-11-28

**Verified at**: `2026-11-28 07:30` UTC, against `rqmslntz` (`f428aca3`, `fix(ghq-shared): start no heal or deepen while a shallow boundary repair is pending`) and `qvuklkpn` (`c3167b04`, `docs(openspec): start no heal or deepen while a shallow boundary repair is pending`).
Only what these two commits change is checked; §1 to §8 are not repeated.

**Verdict**: FAIL.
F4 is closed, and no state with an uncovered cut and a silent reply is reachable without a fault nothing real causes.
The pending rule turns a false check failure, which an ordinary history makes, into a permanent block: every later heal and deepen of the copy is refused, and every reply says "the next request tries again" (F5).

### Method

The handler of `f428aca3`, its three store paths substituted from the `trunk()` build, with that build's `ghq-writer-client` beside it, driven over a socket pair with the change's fixtures, on stibnite with git 2.56.0:

- §8's nested script, unchanged (`logs/cam140-reverify3-nested-20261128-022047.log`).
- New: the first heal and the first deepen of a clean copy each stopped with `SIGKILL` before the record, between the record and the fetch, after the fetch, during the repair, between the repair and the record's removal, and after the fetch with the record's write failing, then two updates; a record that is empty or unparseable over a stopped heal (`logs/cam140-reverify3-stops-20261128-022129.log`, script `logs/cam140-reverify3-stops.py`); a FIFO, a socket, a link to a file outside the repository, a link to a directory, a dangling link, an empty and a non-empty directory at the record's path, then an update and a deepen (`logs/cam140-reverify3-nonfile-20261128-022238.log`, and against `quumvvry`'s handler `…-nonfile-v3-20261128-022313.log`; scripts `logs/cam140-reverify3-nonfile.py` and `logs/cam140-reverify3-stops-helpers.py`); a heal whose doubling depth lands on a root commit (`logs/cam140-reverify3-root-20261128-022031.log`, script `logs/cam140-reverify3-root.py`).
- The boundary script against `f428aca3` and against `quumvvry`'s handler (`kunxsoxr`, `db18e9ba`), and the history and request scripts against `f428aca3` (`logs/cam140-reverify3-suite-*-20261128-022313.log`).

Read only: the builder's red logs (`logs/cam140-pending-red-boundary-*.log`) and magnetite timings (`logs/cam140-pending-magnetite-*.log`); nothing was run on magnetite or pyrite.

### F5 (FAIL): a heal whose depth lands on a root commit the clone holds fails its check, and the copy then stays pending for good

git marks a root commit as a boundary when a depth fetch's depth equals its distance from the tip (in scratch, `--depth=6` over six commits wrote the root to `.git/shallow`).
The repair removes only added boundaries that have parents (`repair`, `ghq-writer-handler.py:1052`), and the check fails on any added boundary the starting refs reached (`check_reach`, `:1062`), so a root the clone's branch reaches fails the heal, although a boundary on a commit with no parents hides nothing.
The record then stays, and every later recovery repeats the same check failure.
Reproduction: six commits upstream, a blobless clone holding the first three whole, the fifth fetched by id at depth 1, upstream at the sixth.
The update ends `shallow boundary heal failed: … (check: 1 boundaries the fetch added hide history a ref reached)`, exit 1, though the depth-6 round had made `HEAD` an ancestor of the upstream.
The next updates fast-forward (exit 0, the root boundary hiding nothing) but each says `shallow boundary repair failed: … (check: …; the next request tries again)` and `shallow boundary repair pending: … (no heal or deepen runs until a request repairs it; the next request tries again)`, ` repair=pending`; a deepen is refused with exit 75.
No request ever repairs it: an update whose fast-forward a boundary later blocks can never heal, and the copy can never be deepened.
Only a promote (`ghq-sync --full`) clears it, by removing `.git/shallow`; it ran normally while pending, and the update after it carried no repair line and left no record. Neither the skill, the usage text nor any reply names that way out, or the record's removal by an administrator.
The shape needs a clone holding its history down to a root, as the spec's own fixtures do, and a round whose depth equals the root's distance from the tip; no fault is involved.
Smallest remedy: count an added boundary with no parents as hiding nothing, in the repair (remove it) or in the check (ignore it); and let the pending line, when the same failure repeats, name the way out.
The check's false failure on such a root has stood since §3's build; until this round it cost one failed update, after which the copy updated normally.

### The stop points and the record

| Stopped at | Heal (old `master`, then the next update) | Deepen |
|---|---|---|
| before the record is written | no cut; the next update heals | no cut; the next update heals |
| between the record and the fetch | no cut; the next update's recovery passes silently and it heals | the same |
| after the fetch | the first round cut nothing; the next update heals | 38 → 1; the next update says `repaired shallow boundaries`, 38 |
| during the repair | 23 → 3; the next update says `repaired shallow boundaries`, 23 | 38 → 1; repaired the same way |
| between the repair and the record's removal | nothing hidden; the next recovery passes silently and removes the record | the same |
| after the fetch, the record's write failing | no cut by the first round; the next update heals | 38 → 1, no record; both later updates silent, 1 for good |

- The record is written whole or not at all: `write_record` writes `ghq-writer-repair.new`, flushes, `fsync`s and renames it (`:726-736`), before the first fetch; a stop before the rename leaves no record and no cut. The directory is not `fsync`ed after the rename, so a power loss could still lose a renamed record (read, not staged).
- A failing write is swallowed (`keep_start`, `:1089-1098`), and the request goes on to fetch; stopped after its fetch, its cut stays hidden with no reply saying so (the last row). I found no real cause of that write failing while the fetch then succeeds: a full disk should fail the fetch too (inference, not staged), and only the writer can put something at `.git/ghq-writer-repair.new` (W12).
- An empty record is read as a start with no refs and no boundaries: the recovery passes, removes it and says nothing, and the cut it should have covered stays (old `master` 3 of 23 after two updates). An unparseable one is removed with `shallow boundary repair skipped: … (ghq-writer-repair is unreadable; removed)`, which does not say history may stay hidden; the cut stays too. Both need the file damaged, which the `fsync`ed rename does not do (W13).
- Two requests racing: `recover` and `repair_state` run after `hold`, the per-repository `flock`, so the second sees the first's record or its removal, never a half state (read).

### Non-files at the record's path

- `recover` reads the path with `lstat` first (`:1117-1131`) and removes anything not a regular file unopened: a FIFO, a socket, a link to a file outside the repository, a link to a directory and a dangling link each gave `shallow boundary repair skipped: … (ghq-writer-repair is not a regular file; removed)` and a healed update within a second; each link's target, file or directory, was left intact (`unlink` removes the link). Against `quumvvry`'s handler the FIFO hung the request for the full 30 s.
- Removing is right: the handler never makes anything but a regular file there, so nothing else carries a record.
- An empty and a non-empty directory each stay and block: the update keeps git's refusal (exit 1) and says `… (ghq-writer-repair is not a regular file and cannot be removed; no heal or deepen runs until the tree's writer account removes it)`, naming the path, ` repair=blocked`; a deepen is refused with 75. No `rmdir` is tried; an empty directory could be removed as safely as a FIFO.
- A regular file swapped for a link between `lstat` and `open` is opened with `O_NOFOLLOW | O_NONBLOCK` (`read_record`, `:705`), which fails; the recovery then removes the link and says it was unreadable (read).

### Exit 75, tokens and requests in either state

- No caller retries on 75: `ghq-writer-client` exits with the reply's status, and `ghq.sh` and `ghq-sync.sh` hold no retry around the writer (read).
- An update needing a heal while pending keeps its first attempt's output and status (`run_get`, `:1263`: no heal, the first result untouched), as the boundary script's case asserts; fast-forwarding updates and a promote ran normally while pending (root log), each reply carrying the pending lines and token.
- Dead code: the "keep an older record" branch and the ownership bookkeeping are gone from the handler, the cases, the spec and the design, except the module docstring, which still says a heal or deepen "keeps a file an earlier request left there" (`:63`) and does not state the pending rule (W14).
- The quoted replies in the interface delta match the handler's strings word for word.

### Warnings

- W12: `keep_start` swallows a failed write and lets the heal or deepen fetch without a record. Remedy: refuse the heal or deepen, saying so, when the record cannot be written.
- W13: an empty record passes recovery silently, and an unparseable one is dropped with a line that does not say history may be hidden. Remedy: treat an empty record as unreadable, and say in that line that history the stopped request cut may stay hidden until a sweep.
- W14: the handler's module docstring (`:58-64`) describes the removed keep-older rule and omits the pending rule.

### Tests and sizes

- The boundary script fails against `quumvvry`'s handler on five assertions ("a FIFO in the repair file's place must be removed without opening it", "a deepen while a repair is pending must be refused and cut nothing", "a directory in the repair file's place must block the heal and fail nothing else", "an update that needs a heal while a repair is pending must keep git's refusal", "the request after a pending repair must repair it, every ref keeping its history"), as the builder's red log does, and passes against `f428aca3` (28.1 s); the history and request scripts pass (22.5 s, 47.8 s).
- The case's socket entry is skipped wherever `bind` fails, which it does on darwin for the fixture's path length, so it has run only on Linux; I did not run it there. My socket run above, bound through a relative path on darwin, shows the behaviour; against `quumvvry`'s handler a socket gave the older `unreadable; removed` line, so the case's text would be red there, which no log records.
- No case covers F5, W12 or W13.
- `rqmslntz` changes only the handler and `test_handler_boundary.py`; no request-half case changed, and the builder's request-check timings of 48 to 50 s on magnetite are as before.

### What remains

- F5's remedy and its case (the root script, failing now), then a run of this section's scripts.
- §6's host checks.
