# Retrospective: hydrate-reference-copy-history

> Written: 2026-11-27 (after verify passed with warnings and both In Review gates were accepted, before archive)
> Commit range: `98ab5a010..0f98c236f` on `main`, 19 commits touching the change's files (PRs #4375 to #4465)
> Worktree: merged to main; this retrospective and the archive are one further commit

---

## What the change set out to do

Copies in the shared reference tree are shallow blobless clones, and an update brought in the new commits and trees but only the blobs of the new tip.
On stibnite on 2026-11-26, `github.com/vidhanio/hypertext` held 39 commits with 92 objects of their history missing; a reader's `git show` of the second newest commit, like lazygit's Patch pane, failed with `Permission denied` from an on-demand fetch into the read-only tree, and lazygit's start-up fetch failed the same way (proposal Why, `brainstorm.md` Background).
The change was to make every commit an update or deepen brings in readable as a diff up to a bound, refuse readers' git every transport beneath the root so a read needing absent content fails at once, turn lazygit's start-up fetch off through `<root>/.lazygit.yml`, and tell readers what a diff needs (design D1 to D11).

## The measured result

On stibnite after activation at `main` `3fea6f9b` (`verify.md` §9) and again at `1d9c9dd5` (§11), as a participating account, with git 2.56.0 and lazygit 0.66.3:

| Copy (check) | Old → new | Commits (merges) | Packs | Wall time | Writer's exit line | Readable |
|---|---|---|---|---|---|---|
| `jj-vcs/jj` (§9) | `a1f34c05` → `10231189` | 157 (0) | 182 → 3 | 3.93 s | `history=hydrated:370` | 157 of 157 |
| `numtide/iets` (§9) | `81d2d4aa` → `1a1c28bd` | 242 (119) | 11 → 14 | 2.48 s | `history=hydrated:195` | 242 of 242 |
| `nixos/nixpkgs`, first (§9) | `2a21d231` → `a2138be0` | 450 (202) | 1,688 → 4 | 55.59 s | `history=hydrated:74` | all single-parent; see below |
| `nixos/nixpkgs`, second (§9) | `a2138be0` → `aa08d423` | 16 (8) | 4 → 6 | 3.11 s | `history=hydrated:0` | all single-parent; see below |
| `nixos/nixpkgs` (§11) | `aa08d423` → `c7a754b3` | 77 (36) | 6 → 9 | 4.47 s | `history=hydrated:26` | 77 of 77 |
| `numtide/iets` (§11) | `1a1c28bd` → `d016486e` | 4 (2) | 14 → 16 | 1.18 s | `history=hydrated:0` | 4 of 4 |
| `nix-community/home-manager` (§11) | `361da94f` → `54f903fd` | 3 (0) | 65 → 2 | 1.36 s | `history=hydrated:0` | 3 of 3 |
| `cachix/git-hooks.nix` (§11) | `1ba1dbfe` → `26f3f17f` | 11 (4) | 7 → 10 | 1.40 s | `history=hydrated:15` | 11 of 11 |
| `DeterminateSystems/nix-src` (§11) | `ea7e9be2` → `7e38738b` | 452 (146) | 12 → 15 | 2.71 s | `history=hydrated:435` | 452 of 452 |

- At §11 every commit the five updates brought in, 547 with 188 merges, read with default rename detection and under lazygit's two commands, each in under 0.2 s (the slowest, nixpkgs' merge `c3a65b02`, in 0.159 s).
- lazygit ran 112 s in the nixpkgs copy, moved over 80 commits and ran 81 `git show`, all exiting 0, with no `fetch`, `fetch-pack` or `remote-https` in its traces (§11); in §9 it ran 110 s in the jj copy, and a scratch configuration setting `git.autoFetch: true` still fetched nothing there.
- A read outside the hydrated range failed within a second with `transport 'https' not allowed` and `could not fetch <oid> from promisor remote`, without `Permission denied` (§9).
- The first update of nixpkgs repacked once inside the request, 1,688 packs to 4 and 2,589,088 KiB to 1,806,252 KiB, in 55.6 s; the second, 12 minutes later, took 3.1 s and did not (§9).
- Each copy's record `.git/ghq-writer-hydrated` is `_ghq:_ghq` `0640`, readable and not writable by readers (§11).
- magnetite, deployed at `6c362f02` (the handler of `df8c75572`, before the merge listing and the record), answered one `ghq-sync -u` of `jj-vcs/jj` with `history=hydrated:0`, refused `git ls-remote origin` with `transport 'https' not allowed`, and holds `/var/lib/ghq/.lazygit.yml` `ghq:ghq` `0640` (`logs/agent-reports-20261126/DeployMagnetite17.md`).

---

## 0. Evidence

- **Commit range**: `98ab5a010` (plan, #4375); delivery `aab117563` (#4382), `3ff10f600` (#4394), `6c53ca380` (#4395), `d901fd6ba` (#4396); remedies `ce9e492df` (#4405), `df8c75572` (#4429), `9952b92c7` (#4439), `3ebf59000` (#4456), `d2b222d1e` (#4457), `1d9c9dd54` (#4460); records `c21a2dc87` (#4399), `3a8bfba48` (#4428), `300eabc35` (#4430), `1afa13ef4` (#4440), `0f5219d7f` (#4451), `4cb8988f3` (#4458), `99050232b` (#4459), `0f98c236f` (#4465); 19 commits
- **Diff size**: +4,680 / −1,378 lines across 27 files, artifacts included; `pkgs/by-name/ghq-shared` +1,960 / −707
- **Tasks done**: 36/36 (`tasks.md`)
- **Active hours**: about 21.7 h, from `98ab5a010` (2026-11-26 23:21 UTC) to the end of §11's checks (2026-11-27 21:04 UTC)
- **Subagent dispatches**: 12 distinct saved reports under `logs/agent-reports-20261126/` (`Cam136*.md`, `DeployMagnetite17.md`); the first delivery commit has none
- **New external dependencies**: none
- **Bugs encountered post-merge**: the first delivery (`aab117563`, `3ff10f600`, `6c53ca380`, `d901fd6ba`) was on `main` before its first verification; verification then found six failures, five, one and none in turn (§4), and the deployed host two more (§9): each is listed under §2 and "What each verification found"
- **OpenSpec validate state at archive**: `openspec validate hydrate-reference-copy-history --strict` valid
- **Test coverage signal**: `test_handler_history.py` holds the history cases, split from `test_handler.py` (`package-ghq-shared-test-handler-history` and `package-ghq-shared-test-handler`, both `measured = false`); `checks.x86_64-linux.eval-shared-reference-tree` holds 39 nix-unit cases at `d2b222d1e` and 45 at `1d9c9dd54`; two runtime subtests added to `shared-reference-tree-migration` and the hydrate subtest of `shared-reference-tree` reworked; every remedy's cases shown failing against the code before it (tasks 5 to 9); on magnetite the request half ran 47.4 s and the history half 21.0 to 21.7 s of their 60 s class (§10), and on pyrite the runtime tests 37.20 to 41.73 s and 35.92 to 39.63 s (§2)

Commit chain (chronological):

```
98ab5a010 docs(openspec): plan hydrating reference copy history
aab117563 feat(ghq-shared): make the commits an update or deepen brings in readable as diffs
3ff10f600 feat(shared-reference-tree): refuse readers every transport beneath the root and turn off lazygit start-up fetch
6c53ca380 docs(dependency-source-acquisition): say what a reference copy makes readable and what readers' git refuses
d901fd6ba fix(shared-reference-tree): make the darwin writer log 0640 from activation
c21a2dc87 docs(openspec): verify hydrating reference copy history
ce9e492df fix(ghq-shared): hydrate what every moved branch ref gained, and harden the history fetch
3a8bfba48 docs(openspec): re-verify hydrating reference copy history
df8c75572 fix(ghq-shared): walk only what a request gained, and guard every history phase
300eabc35 docs(openspec): verify hydrating reference copy history a third time
9952b92c7 fix(shared-reference-tree): fold letter case when judging whether an include reaches the root
1afa13ef4 docs(openspec): verify the case rule of hydrating reference copy history
0f5219d7f docs(openspec): record the deployed-host checks of hydrating reference copy history
3ebf59000 fix(ghq-shared): hydrate merges as rename detection reads them, and what a failed request left behind
d2b222d1e fix(shared-reference-tree): refuse a root git's gitdir: include cannot match
4cb8988f3 docs(hydrate-reference-copy-history): record the deployed-host checks and their remedies
99050232b docs(openspec): verify the merge and left-behind remedies of hydrating reference copy history
1d9c9dd54 test(ghq-shared): pin the record's start boundaries and its advance past the limit; refuse glob characters in the shared root
0f98c236f docs(openspec): record the repeated deployed-host checks of hydrating reference copy history
(this commit) docs(openspec): archive hydrating reference copy history
```

## What each verification found

Each verification read every requirement the change adds or amends against the code paths able to break it and tried them in scratch repositories (§4, §10; design, the three verification sections).

1. **First run, against `d901fd6b`**: six failures. The range walked was `HEAD`'s `OLD..NEW` alone, so the commits a deepen or a tag fetch moves `origin/<branch>` to, and tag commits fetched at depth 1, stayed unreadable while the requirement promised every commit; a timeout after the walk dropped its log token and status line; the evaluation check read `protocol.<name>.allow` in settings only, and three includes defeated it; the history fetch passed a fixed `--filter=blob:none`, writing that filter into a promisor clone recording none; an `OSError` starting git, or 20,000 boundaries on darwin's argv, failed the request; migration kept an administrator's own `.lazygit.yml` at the root. Remedy `ce9e492df`: the range from every moved branch and remote-tracking ref, the tag exception stated, the clone's own filter, the revisions on standard input.
2. **Second run, against `ce9e492d`**: five failures. A ref moved to a commit the copy already held started a walk; a ref name that is not UTF-8, or any exception outside three classes, failed the request with status 70; the evaluation check missed includes through the account's `~/ghq` link, sections in another letter case and settings written as a list; the tag requirement contradicted a branch that later merges the tag's branch; and the handler check, declared `small`, ran 75 to 151 s on nixbot. Remedy `df8c75572`: a walk only when the moved refs reach a commit nothing old reached; every exception in the history phases caught and named by type; includes judged against the root's forms and the link in every shape and case; the handler check split into its request and history halves, each within its class.
3. **Third run, against `cd4dd583`**: one failure. On darwin an include whose `gitdir:` path differed from the link or the root only in letter case reopened the transport, and evaluation passed it. Remedy `9952b92c7`: `includeReachesRoot` folds ASCII letter case on every platform, so an include reaching the root in any shape and any letter case fails evaluation.
4. **Fourth run, against `c6aeb3cb`**: no failure; one warning that a root declared with a trailing slash would make the include `gitdir:<root>//`, which git never applies, and the assertions would not see it.
5. **Fifth verification (§10), against the deployed-host remedies**: no failure. The merge listing was tried on 1,691 commits in 6 built and 60 random histories: with the blobs the handler lists fetched, every commit read under `git show`, lazygit's command and its commit-files listing, while the earlier handler left 41 unreadable. Nine single-line mutants of the handler ran against the history test: seven failed it, and two passed, an untested start-boundary clause (W1) and the record's advance past the limit (W2); the root type admitted glob characters (W3). Remedy `1d9c9dd54`: a case for each clause and the glob characters refused.

The darwin `.lazygit.yml` step, after the first two runs, writes the file under a new name in the root and renames it over whatever stands there, through the root opened as a directory (`df8c75572`, design D7).

## What only a deployed host showed

- **96 of 210 nixpkgs merges unreadable under rename detection** (§9). D1's listings ran with `--no-renames` and named the first parent's side and the combined diff; rename detection on a merge diffs it against each parent and reads the blobs of paths added or deleted there, such as `pkgs/by-name/cl/cleanuparr/qbittorrent-net-client-deps.json` in `a2138be0`'s second parent, a pull-request branch that still held a file `master` had deleted. No handler or runtime fixture had a merge whose branch side holds a file the mainline deleted, and the first run's scratch probe, which covered an octopus merge resolved differently from every parent, had none either. Remedy `3ebf59000`: for each merge, `git diff-tree --stdin --diff-filter=AD --no-renames` against each parent after the first names both sides' blobs, under the same count (design D1, deployed-host item 1; task 8.1). A read-only rehearsal on the nixpkgs copy named 11,653 blob ids, 1,427 missing, in 3.4 s against 1.6 s (task 8.4).
- **A range a failed request left behind** (§9). nixpkgs' `origin/master` was 3 commits ahead of `master`, left by an earlier `ghq get -u` that exited 1; the walk's old side came from the refs as the request found them, so those commits were never walked. Remedy `3ebf59000`: the record `.git/ghq-writer-hydrated`, naming the refs and boundaries the last walk that did not fail saw, written before the first fetch when absent and replaced in one rename after such a walk (design D2, deployed-host item 2; task 8.2). §11 found it in all five copies updated, `_ghq:_ghq` `0640`, unchanged by an update that brought nothing in and by `--hydrate`.

## 1. Wins

- After the remedies every commit five updates brought in read on the host, 547 with 188 merges, each in under 0.2 s, and lazygit fetched nothing in 112 s (§11).
- A read the writer did not prepare fails within a second with the missing object's name, never `Permission denied` (§9).
- Each remedy's cases were shown failing against the code before it, on both systems where they run (tasks 5 to 9), and §10's mutants showed which clauses no case pinned.
- The merge listing's remedy was rehearsed read-only on the copy that showed the fault before it was merged, and every one of the 466 commits read in a scratch repository borrowing the copy's objects (task 8.4).
- The follow-up `serialise-shared-reference-tree-writes` left to this change, the writer's waiting note and log line in the reference-repository guidance, is done (`6c53ca380`).

## 2. Misses

- [high] [blocking | evidence: §9, `3ebf59000`] The hydrate as merged left 96 of 210 nixpkgs merges unreadable under `git show`'s default rename detection; the fixtures held no merge of the shape that needed it, and D1's rejection of `git log -m` rested on "whose modified paths `git show` never reads", which is true for modified paths and not for added or deleted ones under rename detection (`brainstorm.md` measurement 5).
- [high] [blocking | evidence: §4 first run, `ce9e492df`] The first delivery hydrated `HEAD`'s range only, while its requirement promised every commit a deepen or tag fetch brings in.
- [med] [painful | evidence: §4, `ce9e492df`, `df8c75572`, `9952b92c7`] The evaluation check of readers' includes took three rounds to reach every shape: settings only, then includes, then the link, list settings and section case, then letter case in paths.
- [med] [painful | evidence: §4 second run, `df8c75572`] The handler check outgrew `small` (75 to 151 s on nixbot) and was split; its request half runs 47.4 s of 60 s on magnetite (§10).
- [med] [painful | evidence: §9, `3ebf59000`] A range a failed request left behind was found only on the host.
- [low] [nit | evidence: `Cam136HostTasks.md`] The first nixpkgs update was estimated at 5 to 15 min, ten times the 42.9 to 48.6 s that `serialise-shared-reference-tree-writes` (design D9) had measured for consolidating copies of that copy's 1,688 packs; it took 55.6 s.
- [low] [nit | evidence: §11, `Cam136HostRepeat.md`] The objects the recovery recipe would fetch for `400c87b5^2` were first estimated with `git rev-list --objects --missing=print` without `--no-walk`, which walks the parent's whole history: 1,188,150 against the 11,055 its tree lacks and `--hydrate` fetched. An estimate of 724 objects for `e3c7a9df^2` came to 459, as `a2138be0^2`'s hydrate had brought some in.
- [low] [nit | evidence: `99050232b`] A verification record's commit message reached `main` with the verifier's warning codes (W1, W2, W3) in its body.
- [low] [nit | evidence: `Cam136Verify.md`] task 2.3 expected the migration runtime test to grow 2 to 3 s; it grew 5 to 8 s.
- [low] [nit | evidence: `Cam136HydrateHistory-commits2-4.md`] The migration subtest's new assertions were never run red, as the red run failed at an earlier subtest; task 3.1 was ticked by a one-character `perl` substitution rather than the edit tool.
- [low] [nit | evidence: `Cam136Verify.md`] `gh repo sync` was run once by mistake in stibnite's real `vidhanio/hypertext` copy; it failed with `transport 'https' not allowed`, and nothing in the copy changed.
- [low] [nit | evidence: §9, §11] stibnite's `darwin-version` named `663d8b96` and `663d8b9`, neither a commit here; the deployed handler was matched to `1d9c9dd5`'s source instead.

What the misses say about the practice: every behavioural fault was found by reading a requirement's promise against what git does on real histories, in scratch or on a host, not by the cases the author wrote; the one the scratch probes missed needed a history shape (a branch holding a file the mainline deleted) that only a large, active upstream supplied.

## 3. Plan deviations

| Plan task | What changed | Why |
|-----------|--------------|-----|
| (none planned) 5.1–5.8 | Range from every moved ref, tag exception, clone's filter, standard input, transport gaps, migration of an administrator's `.lazygit.yml`, darwin descriptor steps | First run's six failures |
| (none planned) 6.1–6.7 | Walk gate, bytes and catch-all in the history phases, includes in every shape, tag wording, the handler check split, `.lazygit.yml` by rename | Second run's five failures and a warning |
| (none planned) 7.1 | Letter case folded in `includeReachesRoot` | Third run's failure |
| 4.1 | Run twice; open after §9, done after §11 | §9's merges |
| (none planned) 8.1–8.5 | Merge sides, the record, the root option's type, the rehearsal | §9's two faults and the fourth run's warning |
| (none planned) 9.1–9.3 | Cases for the start boundaries and the record's advance; glob characters refused | §10's W1 to W3 |
| Decision 4 of 2026-11-27: no retry record | Reversed: the record makes the next request hydrate what a failed one left | §9's left-behind range |
| Non-goal "Hydrating history fetched before this change reaches a host" | Narrowed: what a later request finds unhydrated is hydrated then; history before the record still needs `ghq-sync --hydrate` | The record |
| The planned rewording of "A participating account bypasses the wrapper" | Dropped | A plain `git fetch` opens `.git/FETCH_HEAD` before it connects, so the scenario stays true (design, decision 5) |
| Proposal's requirement list | 4 behavioural and 21 interface requirements added, the handler check in two | The remedies, each split to stay within the length rule |

## 4. Skill / workflow compliance

| Skill                                            | Used |
|--------------------------------------------------|------|
| superpowers:brainstorming                        | yes (`brainstorm.md`, from an approved outline; no interactive session) |
| superpowers:writing-plans                        | no (`plan.md` absent) |
| superpowers:using-git-worktrees                  | no |
| superpowers:subagent-driven-development          | yes (the saved reports) |
| (transitive) superpowers:test-driven-development | yes for groups 5 to 9, each case shown failing first; partly for groups 1 to 3 (the migration subtest's new assertions never ran red) |
| (transitive) superpowers:requesting-code-review  | no |
| superpowers:finishing-a-development-branch       | yes (#4375 to #4465 merged) |

### Deliberately Skipped Skills

- **`superpowers:writing-plans`**
  - **What was skipped**: `plan.md`.
  - **Why this cycle**: `tasks.md` names each task's files, commands and verify step, and its header names the commit each group becomes; `openspec status` shows `plan` ready, never written.
  - **How to prevent recurrence**: `schema graph fix` — let a `tasks.md` whose every task carries a verify step stand for `plan.md`, or require the plan before apply.
- **`superpowers:using-git-worktrees`**
  - **What was skipped**: the whole skill.
  - **Why this cycle**: the repository is jj-colocated; each piece landed as its own chain on the development join.
  - **How to prevent recurrence**: `schema graph fix` — accept a jj chain as the isolation mechanism, the same answer as `serialise-shared-reference-tree-writes`.
- **`superpowers:requesting-code-review`**
  - **What was skipped**: a review separate from verification.
  - **Why this cycle**: on 2026-11-27 the code-review gate accepted the five verifications and the deployed-host checks as the review (verify.md, In Review gates).
  - **How to prevent recurrence**: `scope-judgment rule` — a verification that reads every requirement against the code paths able to break it counts as the review only when verify.md's gate says so, as here and in `serialise-shared-reference-tree-writes`.

## 5. Surprises

- `git show` of a merge with rename detection reads the blobs of paths added or deleted against every parent, not only the first parent's diff and the combined diff (§9).
- `git rev-list --objects --missing=print OLD..NEW` does not count a blob reachable from the old tip, so the missing count of §9 was 0 while 96 merges were unreadable.
- A plain `git fetch` opens `.git/FETCH_HEAD` before it connects, so the operating system refuses it before `protocol.allow` is read (design, decision 5).
- On darwin the `gitdir:/var/lib/ghq/` form applies only when the working directory is spelled that way; the `/private/var/lib/ghq/` form applies to every spelling (design D6).
- lazygit 0.66.3 reads `.lazygit.yml` in every ancestor after the account's own configuration, and `disableStartupPopups: true` keeps it from fetching at all, so it cannot stand in for a seen intro in a trace (design D7).
- darwin refused 20,000 boundaries as arguments and accepted 15,000 (§4 first run).
- git's gc keeps every object of a promisor pack, so a force-push and a gc do not remove a recorded commit (design, deployed-host item 2).
- lazygit's `--find-renames=50%` overrides a reader's `diff.renames = copies` (§10).
- nixpkgs gained 77 commits in the five hours between §9 and §11.
- A fast-forward onto a commit that a depth-1 tag fetch left as a shallow boundary fails with `Not possible to fast-forward`, with this change's handler and the one before it (§10).

## 6. Promote candidates → long-term learning

- [ ] [high] **A fixture of git history must include the shapes a large active upstream produces, not only the ones the author can name.**
  → **Promote to** skill (`openspec-verify-change`, section 4)
  > **Why**: 1,691 generated commits and the author's cases all read, and nixpkgs still left 96 merges unreadable until a branch holding a file the mainline deleted was added (§9, §10).
  > **How to apply**: any requirement over "every commit"; rehearse read-only on the largest real copy available before merging.
- [ ] [med] **Estimate an object count for one commit's tree with `--no-walk`.**
  → **Promote to** memory
  > **Why**: without it `rev-list --objects --missing=print <rev>` walks the whole history: 1,188,150 against 11,055 (§11).
  > **How to apply**: any estimate of what `ghq-sync --hydrate <rev>` will fetch.
- [ ] [med] **Commit bodies that reach `main` carry no verifier codes.**
  → **Promote to** skill (`openspec-verify-change`, commit message)
  > **Why**: `99050232b` carries W1 to W3, which mean nothing outside its `verify.md`.
  > **How to apply**: when committing a verification record, name each warning by what it says.

---

## Open items that outlive the change

| Item | Where it goes |
|------|---------------|
| 29 merges of 2026-11-27 in stibnite's nixpkgs copy (of `2a21d231..aa08d423`, fetched before the record existed) stay unreadable under rename detection; their second parents' trees lack 3,935 distinct objects, 58 requests of one to three seconds (§11) | `ghq-sync --hydrate <rev>` and `--hydrate <rev>^<n>` for each, as the skill says; no change or issue holds it |
| Copy and break detection (`-C`, `--find-copies-harder`, `diff.renames = copies`, `-B`) and, on a merge, `-m`, `--diff-merges=separate` and `--remerge-diff` read blobs no listing names (§10) | excepted by "An update makes the merges it brought in readable with rename detection"; carried in the CAM-136 qualifications of `satisfaction.md` |
| An update exits 1 when its fast-forward lands on a commit a depth-1 tag fetch left as a shallow boundary, a writer defect older than this change (§10) | no change or issue holds it yet; carried in the CAM-136 qualifications of `satisfaction.md` |
| The request half of the handler check ran 47.4 s of its 60 s class on magnetite; both halves are `measured = false` until nixbot's first uncached runs (§10, `modules/checks/package-tests.nix`) | the classes, from those runs |
| A darwin activation killed between writing `.lazygit.yml.<hex>` and the rename leaves that file in the root, after which `ghq-shared-migrate` no longer counts the root as empty (§4 drift warnings) | no change or issue holds it yet |
| A home directory declared with a trailing slash would double the link's slash in the include; `modules/home/users/lib.nix` declares none (§4 drift warnings) | no change or issue holds it yet |
| "Brings in" is defined by refs: a branch moved onto a commit only a tag reached in a copy holding full history starts a walk that hydrates it (§4 drift warnings) | accepted as the requirements word it |
| Stale `objects/pack/tmp_pack_*` in `NousResearch/hermes-agent`, `cameronraysmith/atomic`, `can1357/oh-my-pi` and `schpet/linear-cli`, and an empty `objects/maintenance.lock` in `block/buzz`, on stibnite (§9) | a writer-side cleanup change, not yet opened, as `serialise-shared-reference-tree-writes` left it |
| magnetite runs the handler of `df8c75572` (deployed at `6c362f02`) and pyrite is not checked: neither runs the merge listing or the record (§11; `DeployMagnetite17.md`) | each host's next deploy |
| `ghq-sync --hydrate <rev>` fetching the parent side of `<rev>`'s diff, and the first update of a depth-1 copy of a repository with merges, which brings in most of its history (design, decisions 3 and 6) | a later change, not yet opened |
| The fragment's and the usage text's "next update or deepen" is narrower than the code, which also walks at a `get` with tags (§10) | a later edit of either text |
| No test of the writer uses an ssh remote; the runtime tests' mutation variants run only on demand; a consolidation inside a request gives the caller no note from the writer, met again here when nixpkgs' first update repacked for 55.6 s and home-manager's printed `Auto packing the repository` (§9, §11) | CAM-138, items 1 to 3 |
