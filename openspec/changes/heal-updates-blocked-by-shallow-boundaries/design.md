## Context

Copies in the shared reference tree are shallow blobless clones that the writer (`pkgs/by-name/ghq-shared/ghq-writer-handler.py`) updates with `ghq get -u`, which runs `git pull --ff-only`.
A commit listed in a copy's `.git/shallow` (a boundary) is read as having no parents (A381).
When the commits between the copy's branch tip and its upstream's new tip pass through a boundary, the pull's fetch moves `origin/<branch>` but sends nothing below the boundary, the fast-forward finds no merge base, git exits 128, ghq exits 1 and the writer replies 1 with ` reason: ghq get exited 1`; every later update fails the same way.

Two sources are known: `shallow_tags` fetches a tag whose commit the copy lacks at depth 1, and upstream's branch later fast-forwards onto it; and a depth-1 fetch of a commit by id, as both failing copies on stibnite received in July in an account's own tree before the shared tree existed (CAM-140 and its comments; `logs/cam140-stuck-copy-{sops-nix,nixos-hardware}-20261127-183759/`).
On stibnite on 2026-11-27, 616 of 679 copies were shallow, 84 held 8,071 boundaries no branch or remote-tracking ref reaches (`logs/cam136-shallow-boundary-census-20261127-163200.log`), 2 failed, and upstream's branch already contained such a boundary of 2 more, `github.com/davidjo/snd_hda_macbookpro` and `github.com/withastro/astro` (`logs/cam140-plan-at-risk-scan-20261127-185935.log`).

The two failing copies were healed by hand with `ghq-sync --deepen N`, N sized to the gap. On `nixos-hardware` the deepen marked the old local tip and a commit on another path as boundaries though the copy held their history, hiding 11 of the 2,941 commits upstream's `master` reaches, until `ghq-sync --deepen 793` reached the roots.
A deepen marks the commits at its new depth as boundaries whether or not the copy holds their parents (A380); the scratch rehearsal (`logs/cam140-plan-heal-scratch-20261127-190204.log`) shows it on a copy with complete history (`master` 34 commits to 1, another remote-tracking branch 23 to 5) and on an updated depth-1 copy (3 to 2).

The history fetch (archived change `hydrate-reference-copy-history`) walks, after `ghq get -u` whatever its exit status, what the copy's refs gained since the record `.git/ghq-writer-hydrated` and what lies below each boundary a request removed.
The failing update of `nixos-hardware` was walked (`history=hydrated:190`); the 34 unreadable commits of `sops-nix` predate the record, which its first request wrote from the refs as it found them (brainstorm, "Correction to a premise").

Boundaries: every file this change edits is first-party (the handler, its tests, `ghq-sync`'s usage text, the skill under `modules/home/ai/plugins/`); git is vendored and only invoked; the heal reaches a host by its deploy.
The measurements and the comparison of remedies are in `brainstorm.md`.

## Goals / Non-Goals

**Goals:**
- An update of a shallow copy whose fast-forward a boundary blocks succeeds, the branch at upstream's tip, whenever upstream's branch still contains the local tip and the gap lies within the bound.
- No heal, and no deepen, leaves any branch or remote-tracking ref reaching fewer commits than before; the copy keeps its partial-clone filter.
- An update that needs no heal runs nothing more than today.
- The commits a healed update brings in are readable as diffs, as for any update, and the history the copy held before is not walked.
- The caller and the writer's log can tell a heal from an ordinary update, and a heal that could not complete from one that failed.

**Non-Goals:**
- Preventing boundaries (D9).
- Removing the boundaries that already hide held history in existing copies (D10).
- Hydrating commits a copy fetched before the writer kept its record.
- Updates of a branch upstream rewrote: the fast-forward stays impossible and fails as today.
- Promoting a copy to a full clone.

## Decisions

### D1: Heal after a failed fast-forward, inside the same request

- **Choice**: after `ghq get -u` of an existing clone exits non-zero, the handler checks, with lazy fetching off and on local state only: `.git/shallow` exists; `HEAD` is a branch with an upstream; `HEAD` is not an ancestor of the upstream; and `git rev-list <upstream> ^HEAD` lists a commit that `.git/shallow` names. When all hold, it heals (D2, D3) and runs `ghq get -u` once more, under the same lock.
- **Rationale**: the pull's fetch has already moved the upstream, so the cause is decidable without the network; an update that succeeds pays nothing.
- **Alternatives considered**: checking before every update: needs its own fetch, a round trip on every update of every copy for a condition two copies in 679 had. Running the fast-forward with `git merge --ff-only @{u}` after the heal instead of `ghq get -u`: one fetch fewer, but a second path for what ghq does; ghq's second fetch finds nothing new and costs one round trip.
- **Boundary**: first-party handler; ghq and git vendored, invoked as today.

### D2: Fill the gap with a depth fetch from the upstream's tip, doubling

- **Choice**: `git fetch --no-tags --depth=<K> origin <upstream branch>` with K starting at one more than the number of commits `rev-list <upstream> ^HEAD` lists, doubling each round, until `HEAD` is an ancestor of the upstream (healed); or a merge base exists without it (upstream rewrote its branch: not healed); or `rev-list <upstream> ^HEAD` lists no boundary while `HEAD` is still not an ancestor (the history reached its roots without the local tip: not healed); or the bound of D4 is passed (not healed). Each fetch uses the clone's configured remote and so its recorded partial-clone filter.
- **Rationale**: depth counts from the fetched tip, so the fetch covers the gap without deepening the copy's other boundaries, the clone's floor among them, which in merge-dense history is costly (nixpkgs: 16 generations from a tip reach 1,253 commits, 32 reach 64,034, 64 reach 589,653; `logs/cam140-plan-depth-measurements-20261127-185935.log`). Doubling costs at most twice the needed depth and a logarithmic number of round trips. Rehearsed on both sources: healed at K = 6, filter kept, connectivity clean.
- **Alternatives considered**: `git fetch --deepen=N` (what the hand heal used): deepens every boundary the branch reaches, the floor included, and cut held history in every rehearsal. `--shallow-exclude=<local tip>`: upload-pack accepts only a ref name (`deepen-not is not a ref`). Fetching the boundary's parents with no depth: brings their whole ancestry not reachable from the local refs, a side branch forked below the floor down to its root (rehearsal: 21 commits against 10). `--unshallow` or `promote`: the whole history, and promote every blob too. Measuring the gap exactly: impossible locally, its commits are what is missing.

### D3: Remove the boundaries the fetch placed on held history, and prove it

- **Choice**: after the last round, the handler removes from `.git/shallow` every boundary not present when the heal began whose every parent the clone holds, repeating until none is left, writing the file as git does: `.git/shallow.lock` created exclusively, renamed over `.git/shallow`, the file removed when empty (A382). It then walks, lazy fetching off, every commit the refs held before the heal reach; the walk must succeed and list no boundary the heal added. If it fails, the handler puts back the shallow file the fetch wrote and reports the heal failed (D6).
- **Rationale**: a boundary on a held commit is a graft over parents the clone has, so removing it only restores parent links git already holds; a boundary whose parents are absent stays, so the result is a valid shallow clone. If no boundary the heal added lies in the old refs' ancestry, every old ref reaches at least what it reached before (the graph only gained parent links), which is the invariant "no ref's reachable count decreases", checked in one walk. The walk costs 7.4 s on the largest copy (stibnite's nixpkgs, 1,131,621 commits) and runs only for a heal.
- **Alternatives considered**: deepening further until no held commit is a boundary: the hand restore needed depth 793 for nixos-hardware, and the depth to the roots is 7,237 for home-manager, 10,240 for dfinity/ic and 7,667 for nixpkgs, each also moving the floor (brainstorm, Q4). Counting each ref's commits before and after: exact too, but one walk per ref; the per-ref counts are what the handler cases assert.
- **Boundary**: the handler writes a file inside `.git` that git owns, under the writer's per-repository lock, so no other git runs in that clone meanwhile; the format and its lock are git's (A382).

### D4: A heal is bounded by the commits it brings in

- **Choice**: before each round, the first included, the handler counts with lazy fetching off the commits the upstream reaches that the refs held before the heal do not (the first count holds what the failed attempt's fetch brought); past `healLimit` (default 100,000, from the handler's configuration like `historyLimit`), it stops: not healed. The command timeout bounds each fetch as it bounds every command.
- **Rationale**: depth is not a cost measure: 1,024 generations are 1,024 commits in home-manager, BAML or dfinity/ic, and nearly all of nixpkgs. The commits brought in are what the fetch transfers (with their trees, in a blobless clone) and what the walk lists. 100,000 matches the history limit's scale and covers nixpkgs gaps of 90 days (30 generations, at most 64,034 commits within reach, most of them held by a copy that is updated). A round's fetch is counted before the next, so one round can overshoot (nixpkgs: 32 to 64 generations). A limit of 0 stops every heal before its first fetch, which the handler case for an update that does not heal uses.
- **Alternatives considered**: a depth limit (meaningless across repositories, above); no bound but the command timeout (a copy whose branch upstream replaced with unrelated history would fetch to the roots for up to an hour).

### D5: What the caller and the log see

- **Choice**: the reply holds the first attempt's output, then one status line, then the second attempt's; the exit status is the second attempt's. Status lines: `healed shallow boundary: <path> (depth <K>; <n> boundaries on held history removed)`, `shallow boundary not healed: <path> (<reason>)` where the reason is `upstream's branch does not contain the local branch`, `upstream's history ends before the local branch` or `more than <limit> commits`, and `shallow boundary heal failed: <path> (<phase>: <reason>)`, the phase `fetch`, `repair` or `check`. The exit log line adds, after the duration and before any `history=` token, `heal=healed:<K>`, `heal=not-healed` or `heal=failed`; a request that attempts no heal adds none. Neither names the target or a command's arguments.
- **Rationale**: the first attempt's `fatal:` line is what happened; the status line explains it and the exit status says the update succeeded. The token lets the writer's log show which copies healed, as `history=` shows which were hydrated.
- **Alternatives considered**: dropping the first attempt's output when the heal succeeds: hides a real failure and its cause from a reader who later finds the copy deeper than expected.

### D6: A heal that cannot complete

- **Choice**: not healed or failed, the request's exit status is the first attempt's; the handler runs no second attempt; the clone keeps whatever commits the rounds fetched, with D3's repair applied, so every ref reaches at least what it did; a failure of the repair's check restores the fetch's shallow file. Any exception in the heal is the heal's failure, reported by its phase and the exception's type, never ending the request with status 70, as the history phases do (`A failed history fetch leaves the request's outcome as it was`). A heal that times out ends the request like any command that outlasts its limit, its token on the exit line.
- **Rationale**: a reader then has what it had, plus a reason; a later update retries, at no cost when nothing changed.

### D7: The history walk of a healed update

- **Choice**: the walk runs once, after the second attempt, as for any update, and additionally excludes the boundaries D3 removed: its range below a removed boundary stops at the boundaries now present and at those. The record names the refs and the boundaries after the repair. When no heal completes, the walk is as today.
- **Rationale**: without the exclusion, the range below the upstream-side boundary the fetch removed runs through the copy's whole held history once D3 has removed the boundaries that stopped it; on a copy whose older history was never hydrated that passes `historyLimit` and leaves even the gained commits unhydrated. With it, the walk lists exactly the commits the heal and the update gained: the gap, through the moved refs' range, and the old boundary's diff against its newly present parent.
- **Effect on the existing case**: "A boundary present when a request begins counts as held" asserts that an update whose `master` moves onto a tag's depth-1 commit walks nothing; with the heal, that update succeeds and walks one commit, the tag's, against its parent, fetching one blob, not its whole tree as a root commit's. The case becomes the failing-first case of the first source, and its point moves to an update with `healLimit` 0, which does not heal and walks nothing.

### D8: A deepen applies the same repair

- **Choice**: after `ghq-sync --deepen N` returns, the handler applies D3 to the boundaries that were not present before the deepen, then walks as today, excluding the boundaries it removed. `ghq-sync.sh`'s `deepen_one` is unchanged; its usage text says a deepen never hides history a branch reached.
- **Rationale**: `--deepen` is the hand heal readers know and the one that cut `nixos-hardware`; one function serves both.
- **Alternatives considered**: leaving `deepen` as is and documenting the cut: readers would still hide history with the writer's own verb. This is a scope choice (Open Questions 1).

### D9: No prevention in this change

- **Choice**: `shallow_tags` keeps fetching a tag whose commit the copy lacks at depth 1, and the writer still accepts copies that arrive with boundaries.
- **Rationale**: fetching a tag with its history brings its whole ancestry the copy's refs do not reach, with trees (a release branch forked below the floor: down to its root); whether a tag's commit lies ahead of a tracked branch is unknowable before fetching it; and neither covers a commit fetched by id. With D1 to D3 a boundary ahead of a branch costs the one update that meets it a heal.

### D10: Existing copies

- **Choice**: no pass over existing copies. A copy whose upstream reaches one of its boundaries heals at its next update after its host's deploy. The 1,894 boundaries in 70 stibnite copies whose every parent the copy holds (`logs/cam140-plan-hidden-history-census-20261127-185935.log`) block no update; removing them is D3 applied to a whole copy, which belongs in a writer housekeeping verb run once per host. The removal of stale `tmp_pack_*` and `objects/maintenance.lock` files, and CAM-138's housekeeping items, may want the same verb; it is not designed here.
- **Rationale**: an unreached boundary cannot be healed ahead of time: no ref leads past it yet. A verb that rewrites `.git/shallow` across every copy of a host is a larger act than a fix of one request, with its own review.

### D11: Where the new cases run

- **Choice**: the new handler cases join `test_handler_history.py`, whose check ran 21.0 to 21.7 s on magnetite and 25 s on stibnite of its 60 s class, against 47.3 to 47.4 s for `test_handler.py`'s. If the history check then runs more than 45 s on magnetite under the build lock, the heal's cases move to a third script, `test_handler_boundary.py`, sharing `handler_fixtures.py`, declared as its own check in the same class; no check is declared in a larger class.

## Risks / Trade-offs

- [Risk] The handler writes `.git/shallow`, a file git owns. → Mitigation: under the writer's lock, through git's own lock-file name and an atomic rename (A382), only removing entries whose parents the clone holds, followed by a connectivity walk that must pass or the fetch's file is restored; handler cases assert `git fsck --connectivity-only` with lazy fetching off after every heal.
- [Risk] A heal of a merge-dense repository fetches many commits and trees under the lock. → Mitigation: D4's bound and the command timeout; a queued request waits up to 3,600 s for the lock already.
- [Trade-off] A heal fetches, besides the gap, the commits of side branches merged into it down to the depth it reaches: in the rehearsal's depth-1 copy `origin/master` reached 2 commits before the heal and 10 after, of which the branch's own path holds 3 new ones. → Accepted: they are upstream's history of the branch, bounded by the depth, and the copy keeps them.
- [Trade-off] The reply of a healed update carries the first attempt's `fatal:` line. → Accepted (D5).
- [Risk] A git release changes how a depth fetch marks boundaries or how `.git/shallow` is written. → Mitigation: A380 to A382 name the facts with their observation; the handler cases fail if a fetch stops reaching the local tip or a ref loses a commit.

## Migration Plan

Deploy order: magnetite, pyrite, stibnite, each by its usual deploy; nothing changes in a copy until an update needs a heal, or a deepen runs.
On stibnite, `github.com/davidjo/snd_hda_macbookpro` and `github.com/withastro/astro` are the copies to observe: their upstream branches contained one of their boundaries on 2026-11-27; whether that still holds is re-read before the deploy, read-only.
Rollback: revert the commits and deploy; healed copies stay valid shallow clones with more history, and the record stays readable by the earlier handler.

## Open Questions

1. Does the deepen verb get the repair in this change (D8)? Recommended: yes; one function, and it is the verb that cut `nixos-hardware`.
2. The bound (D4): 100,000 commits brought in, counted before each round? Recommended: yes; the alternative is a depth limit, which is meaningless across repositories.
3. Should the reply of a healed update drop the first attempt's output (D5)? Recommended: keep it.
4. The sweep of boundaries that hide held history (1,894 in 70 copies on stibnite) as a writer housekeeping verb, with the `tmp_pack_*` and `objects/maintenance.lock` cleanup: a new change and Linear issue (D10)? Recommended: yes, after this change lands, reusing D3's function.
