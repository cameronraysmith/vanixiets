# Brainstorm: updates that fast-forward onto a shallow boundary

Linear CAM-140, its two comments of 2026-11-27, and the evidence under `logs/cam140-stuck-copy-sops-nix-20261127-183759/`, `logs/cam140-stuck-copy-nixos-hardware-20261127-183759/` and `logs/cam136-shallow-boundary-*`.
The measurements made for this plan are under `logs/cam140-plan-*` (stibnite, 2026-11-27, git 2.56.0), each named where it is used.

## Background

`ghq get -u` on a copy in the shared tree runs `git pull --ff-only`.
When the copy is shallow and the commits between its branch tip and upstream's new tip pass through a commit listed in `.git/shallow` (a boundary), the pull's fetch moves `origin/<branch>` but sends nothing below the boundary, which the copy already holds; the fast-forward then finds no merge base and exits 128 (`fatal: Not possible to fast-forward, aborting.`), ghq exits 1, the writer replies 1 and logs ` reason: ghq get exited 1`.
Every later update fails the same way, because every new upstream commit descends from the boundary.

Two sources of such a boundary, both checked against the evidence:

1. `shallow_tags` in `pkgs/by-name/ghq-shared/ghq-writer-handler.py` fetches each tag whose commit the copy lacks with `git fetch --no-tags --depth=1`; upstream's branch later fast-forwards onto that commit (`logs/cam136-shallow-boundary-ff-scratch-20261127-163055.log`: the pull fails at once and again after one more upstream commit, and succeeds after `git fetch --deepen=1`).
2. A depth-1 fetch of a commit by its id. Both failing copies on stibnite held boundaries at revisions vanixiets' `flake.lock` once pinned, fetched in July in an account's own tree before the shared tree existed: `nixos-hardware`'s `FETCH_HEAD` reads `'779c32a0…' of https://github.com/NixOS/nixos-hardware` (`FETCH_HEAD.txt`), and every `sops-nix` boundary is a pinned revision (CAM-140, first comment). The writer itself never fetches by id today; copies that arrived with such a boundary are exposed.

How common (`logs/cam136-shallow-boundary-census-20261127-163200.log`): of 679 copies on stibnite, 616 are shallow; 84 hold 8,071 boundaries that no branch or remote-tracking ref reaches; 2 failed then.
A further read-only scan for this plan (`logs/cam140-plan-at-risk-scan-20261127-185935.log`) found, among the 84, 8 copies holding a boundary newer than their upstream tip; GitHub's compare of each such boundary with the tracked branch shows that upstream's branch already contains one in `github.com/davidjo/snd_hda_macbookpro` (`89b22ff9`, `master` 6 ahead of it) and two in `github.com/withastro/astro` (`2aa8ea41` and `34c95355` on `main`). Their next `ghq-sync -u` will fail as the two healed copies did.

## The heal by hand, and what it cut

`ghq-sync --deepen 6 Mic92/sops-nix` and `ghq-sync --deepen 2 nixos/nixos-hardware`, sized to the shortest parent path from the upstream-side boundary to the local tip, let the next update fast-forward (`heal.txt`).
On `nixos-hardware` the deepen marked the old local tip `fccfa903`, and `e8b0dcdc` on another path, as boundaries though the copy held their history: `master` reached 2,930 commits where upstream's reaches 2,941, 11 hidden (`before-restore.txt`); `ghq-sync --deepen 793` restored it (`restore.txt`).
On `sops-nix` nothing was cut, because its old tip was already a boundary (a never-updated depth-1 clone).
`ghq-sync --full` would also have healed both, by unshallowing and then refetching every blob: it turns a blobless copy into a full one, which the tree's design avoids.

The cut is not peculiar to that copy. `logs/cam140-plan-heal-scratch-20261127-190204.log` (script `logs/cam140-plan-heal-scratch.sh`) rehearses both sources in scratch repositories:

- a blobless copy with complete history whose upstream fast-forwards past a commit fetched by id at depth 1: `git fetch --deepen=3` (exactly the distance to the local tip) leaves `master` reaching 1 commit of its 34, and `origin/side`, a branch the fetch never needed, 5 of its 23;
- a depth-1 copy updated twice, whose upstream merges a branch forked below the clone's boundary: a doubling `--deepen` leaves `master` reaching 2 of its 3.

So any deepen that reaches the local tip's held history cuts it: git records the commits at the new depth as boundaries whether or not it holds their parents (A380).

## Correction to a premise

"Commits fetched by a failing update are not hydrated" does not hold for the writer as deployed. The history walk runs after `ghq get -u` whatever its exit status: the failing update of `nixos-hardware` logged `history=hydrated:190` (`reproduce-writer-log.txt`).
The 34 unreadable commits of `sops-nix` arrived with an update of 2026-11-24, before the writer had a history fetch; the first request after the writer that keeps `.git/ghq-writer-hydrated` was deployed wrote the record from the refs as it found them, so the walk counts those commits as held.
That is the residue the archived history change already names (commits fetched before the record), not a property of failing updates, and is outside this change.

## Questions and answers

**Q1. When does the writer act: before every update, or after an update fails?**
After `ghq get -u` exits non-zero and the copy's state shows the cause: the copy is shallow, `HEAD` is a branch with an upstream, `HEAD` is not an ancestor of the upstream, and the commits the upstream reaches and `HEAD` does not include a boundary. These are local reads; the pull's own fetch has already moved the upstream.
Acting before every update needs a fetch first, a network round trip on every update of every copy, to find a condition 2 copies in 679 had.

**Q2. How is the gap filled?**
Candidates, compared:

- `git fetch --deepen=N`, doubling N: deepens from every boundary the fetched branch reaches, the clone's floor included. In merge-dense history that is expensive: from nixpkgs' tip, 16 generations reach 1,253 commits, 32 reach 64,034 and 64 reach 589,653 (`logs/cam140-plan-depth-measurements-20261127-185935.log`). It also cut held history in both rehearsals.
- `git fetch --depth=K origin <branch>` from upstream's tip, doubling K from one more than the commits the upstream reaches above the boundary: covers the gap without moving the floor, since depth counts from the tip. It too marks held commits at depth K as boundaries (the rehearsal's first case: 2 such), which the repair below removes. Rehearsed: both cases heal at K = 6 with every ref keeping every commit it reached, the filter `blob:none` kept, `git fsck --connectivity-only` clean and the pull exiting 0.
- `--shallow-exclude=<local tip>`: upload-pack refuses an object id (`deepen-not is not a ref`, rehearsal log); the local tip rarely has a remote ref.
- Fetching the boundary's parents with no depth and removing the boundary: the server sends their whole ancestry the local refs do not reach, including a side branch forked below the clone's floor down to its root (the rehearsal's third case: `origin/master` then reaches 21 commits of upstream's 48, against 10 after the depth fetch below); unbounded.
- `git fetch --unshallow` (or `promote`): fetches everything below every boundary, for a depth-1 copy its whole history (nixpkgs: 1,131,790 commits, 547 MB as commits alone in a treeless clone, trees besides for a blobless copy; the stibnite copy, which holds nearly all of it, has 1.73 GiB of packs); promote also refetches every blob.

Chosen: the depth fetch from the tip, doubling, then the repair.

**Q3. How is held history kept?**
After the fetch, every boundary that was not present when the heal began and whose every parent the copy holds is removed from `.git/shallow`, repeated until none is left, the file written as git writes it (`.git/shallow.lock`, renamed over; removed when empty) (A382).
Then a commit walk of every ref the copy had before the heal, with lazy fetching off, must succeed and must list no boundary the heal added: the graph only gained parent links, so every ref reaches at least what it reached before. If that check fails, the shallow file the fetch wrote is put back (a cut, but a consistent repository) and the heal reports failure.
Cost of the check on the largest copy: `git --no-lazy-fetch rev-list --count master` of the stibnite nixpkgs copy takes 7.4 s (1,131,621 commits); it runs only when a heal runs.

**Q4. How far may a heal go?**
The rounds stop when the local tip is an ancestor of the upstream (healed); when a merge base exists but the local tip is not an ancestor (upstream rewrote its branch, so a fast-forward is impossible anyway); when no boundary is left between them (the upstream's history reached its roots without meeting the local tip); or when the commits the heal has brought in pass a bound.
Measured: linear histories (home-manager 7,645 commits, BAML 4,413, dfinity/ic 37,548 in scratch treeless clones) bring in one commit per generation, and a deepen to their roots needs depth 7,237, 3,903 and 10,240; nixpkgs (1,131,790 commits, 547 MB treeless, cloned in 24 s) needs 7,667 to its roots but 13, 16, 25 and 30 generations to reach `master` as it was 1, 7, 30 and 90 days earlier.
The bound counts commits, not depth, because depth means a thousand commits in one repository and a million in another: proposed 100,000 commits the heal brought in (the scale of the history limit), counted before each round, so one round can overshoot it (nixpkgs from 32 to 64 generations), under the command timeout of 3,600 s.

**Q5. What does the caller see?**
The first attempt's output stays in the reply (it is what happened), then one status line, then the second attempt's output; the exit status is the second attempt's.
Status lines: `healed shallow boundary: <path> (depth <K>; <n> boundaries on held history removed)`, `shallow boundary not healed: <path> (<reason>)`, `shallow boundary heal failed: <path> (<phase>: <reason>)`.
Exit log line token, after the duration and before `history=`: `heal=healed:<K>`, `heal=not-healed` or `heal=failed`; none when no heal was attempted.

**Q6. What happens to the history walk and its record?**
The walk runs once, after the second attempt.
It already takes the commits a moved ref gained above what the record's refs reached, and the commits below each removed boundary down to the boundaries now present.
After a repair, "the boundaries now present" no longer stop the walk at the old history, so the removed-boundary range would run through the copy's whole held history: on a copy whose older history was never hydrated that passes the history limit and leaves even the gained commits unhydrated.
So the walk also excludes the boundaries the repair removed; it then lists exactly the commits the heal and the update gained. The record names the refs and the boundaries after the repair.
A heal that does not complete leaves the walk as today: the upstream's move onto a boundary present at the request's start walks nothing.

**Q7. Does `deepen` get the same repair?**
`ghq-sync --deepen N` is how the copies were healed by hand, and it cut `nixos-hardware`. Applying the repair after the deepen verb's fetch keeps its promise ("deepen history in place") and is the same function. Recommended; it is a scope decision.

**Q8. Prevention (fetch tags with history, or never fetch a tag's commit ahead of a branch)?**
Fetching a tag with no depth brings its whole ancestry not reachable from the copy's refs: for a tag on a release branch forked below the copy's floor, its history to the root (BAML: 832 boundaries in its copy, 4,413 commits upstream; dfinity/ic: 434 and 37,548), and with trees, since copies are blobless.
Whether a tag's commit lies ahead of a tracked branch is unknowable before fetching it.
Neither covers the second source (a commit fetched by id). With the heal in place a boundary ahead of a branch is harmless to updates; prevention is not part of this change.

**Q9. Existing copies?**
The 84 copies' unreached boundaries are healed lazily, by the update that needs it; nothing can be done ahead, because no ref leads past them yet.
A separate class exists: `logs/cam140-plan-hidden-history-census-20261127-185935.log` finds 70 copies holding 1,894 boundaries whose every parent the copy holds (e.g. `k3s-io/k3s` 180, `tursodatabase/turso` 139, `golemcloud/golem` 116): history present but hidden. They do not block updates. Removing them is the same repair applied to a whole copy, a writer verb run once over the tree; the pending removal of stale `tmp_pack_*` and `objects/maintenance.lock` files, and CAM-138's housekeeping items, may want the same verb. Not designed here.

**Q10. CAM-138?**
Its three items (no ssh-remote test; runtime mutants run only on demand; no writer note during a consolidation) are about tests and messages, not this failure. None belongs here. A heal is a long step inside a request like a consolidation is, so CAM-138's third item, if built, should cover a heal too.

## Agreed direction

Heal inside the update that fails (Q1), with a doubling depth fetch from the upstream's tip (Q2), the repair and its check (Q3), a commit bound (Q4), reported as in Q5, the walk excluding what the repair restored (Q6), the deepen verb repaired too (Q7, to confirm); no prevention (Q8); the hidden-history sweep left to a writer housekeeping verb (Q9); CAM-138 unchanged (Q10).
