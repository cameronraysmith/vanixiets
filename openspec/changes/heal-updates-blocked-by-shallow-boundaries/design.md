## Context

Copies in the shared reference tree are shallow blobless clones that the writer (`pkgs/by-name/ghq-shared/ghq-writer-handler.py`) updates with `ghq get -u`, which runs `git pull --ff-only`.
A commit listed in a copy's `.git/shallow` (a boundary) is read as having no parents (A381).
When the commits between the copy's branch tip and its upstream's new tip pass through a boundary, the pull's fetch moves `origin/<branch>` but sends nothing below the boundary, the fast-forward finds no merge base, git exits 128, ghq exits 1 and the writer replies 1 with ` reason: ghq get exited 1`; every later update fails the same way.

Two sources are known: `shallow_tags` fetches a tag whose commit the copy lacks at depth 1, and upstream's branch later fast-forwards onto it; and a depth-1 fetch of a commit by id, as both failing copies on stibnite received in July in an account's own tree before the shared tree existed (CAM-140 and its comments; `logs/cam140-stuck-copy-{sops-nix,nixos-hardware}-20261127-183759/`).
On stibnite on 2026-11-27, 616 of 679 copies were shallow, 84 held 8,071 boundaries no branch or remote-tracking ref reaches (`logs/cam136-shallow-boundary-census-20261127-163200.log`), 2 failed, and upstream's branch already contained such a boundary of 2 more, `github.com/davidjo/snd_hda_macbookpro` and `github.com/withastro/astro` (`logs/cam140-plan-at-risk-scan-20261127-185935.log`).

The two failing copies were healed by hand with `ghq-sync --deepen N`, N sized to the gap. On `nixos-hardware` the deepen marked the old local tip and a commit on another path as boundaries though the copy held their history, hiding 11 of the 2,941 commits upstream's `master` reaches, until `ghq-sync --deepen 793` reached the roots.
A deepen marks the commits at its new depth as boundaries whether or not the copy holds their parents (A380); the scratch rehearsal (`logs/cam140-plan-heal-scratch-20261127-190204.log`) shows it on a copy with complete history (`master` 34 commits to 1, another remote-tracking branch 23 to 5) and on an updated depth-1 copy (3 to 2).

Boundaries: every file this change edits is first-party (the handler, its tests, `ghq-sync`'s usage text, the skill under `modules/home/ai/plugins/`); git is vendored and only invoked; the report reaches a host by its deploy.

## Goals / Non-Goals

**Goals:**
- An update that fails with a commit held without its history between the local branch and upstream's keeps git's refusal and exit status, and its reply names that commit and a repair that hides no history the copy holds, stating no cause the clone cannot show.
- The writer's log tells such an update from one that failed for another reason.
- Finding the boundary writes nothing, fetches nothing, costs an update that succeeds nothing, and cannot change an update's outcome.
- Accounts learn, from `ghq-sync`'s usage text and the skill, that a sized `--deepen` can hide held history, and which form does not.

**Non-Goals:**
- Healing the update, repairing `.git/shallow`, or changing what a request does to a repository (D4).
- Preventing boundaries: fetching tags with their history, or refusing a tag ahead of a branch.
- Removing the boundaries that already hide held history in existing copies.
- Telling a branch upstream rewrote from one that moved on: where the rewritten history passes a commit held without its history, the clone shows both alike, so the reply names that commit and the repair, and says that an update still failing after the repair without the line means upstream rewrote its branch. Where no such commit lies between them, the update fails as before, with no boundary line.

## Decisions

### D1: Find the boundary after a failed fast-forward, reading only

- **Choice**: after `ghq get -u` of an existing clone exits non-zero, with lazy fetching off: read `.git/shallow`; if it lists a boundary, resolve `@{upstream}` of `HEAD`, require `git merge-base --is-ancestor HEAD <upstream>` to exit 1, and list `git rev-list <upstream> ^HEAD`; the first listed commit that is a boundary is named. Any exception while finding it, a git that cannot start or a time-out included, names none.
- **Rationale**: the same test the heal ran before it fetched, without the fetch: a boundary among the commits upstream's branch gained is what stops the walk from reaching `HEAD` (A381). The update's own fetch has already moved `origin/<branch>`, so nothing more is fetched. The test cannot tell a branch that moved past the boundary from one upstream rewrote onto history passing it: in both the boundary hides where the two histories meet, so the reply states only that the commit lies between them. A rewritten branch whose only boundary is `HEAD`'s commit has `HEAD` outside the listing and gets no line. Finding the commit is an addition to the reply, so no failure in it may change the update's outcome.
- **Alternatives considered**: running it before the update (every update would pay for it); reporting any failed update of a shallow copy (a rewritten branch would get a wrong repair).

### D2: What the reply and the log carry

- **Choice**: the reply keeps the update's output and exit status, git's `fatal:` line among them, and ends its standard error with two lines:
  `shallow boundary between the local branch and upstream's: <path> (the copy holds <commit> without its history, and it lies between the local branch and upstream's <remote>/<branch>)` and
  `to repair it: ghq-sync --deepen 1000000 <path> then ghq-sync -u <path> (that deepen hides none of the history the copy holds, where a smaller one can; if the update still fails with git's fast-forward refusal and without this line, upstream rewrote its branch and this boundary was not the cause; ghq-sync --help, under --deepen, says what the deepen costs and names the other repair)`.
  The exit log line adds ` boundary=blocked` after the history token.
- **Rationale**: the caller sees what the clone shows beside git's refusal, a command to run, and how to read the update after it; the cost, the time limit and the other repair are in `ghq-sync --help`, which the line points to, so the reply stays two lines; the log can be counted across hosts. The exit status stays git's, so callers that act on it act as before.

### D3: The repair the reply names: a deepen of 1,000,000

- **Choice**: `ghq-sync --deepen 1000000 <path>`, the largest depth the writer's `deepen` request accepts, then `ghq-sync -u <path>`.
- **Rationale**: git marks as a boundary only a commit at exactly the requested depth below a boundary (A380), and no copy's history runs that deep (A382), so the deepen fetches everything below the boundaries the fetched branches reach and leaves none there, the root included. A boundary on a tag's commit that no fetched branch reaches can remain; it hides nothing the copy holds. It keeps the partial-clone filter and fetches the commits and trees of the whole history below those boundaries, not their blobs, which on a large copy can take long within the writer's one-hour command limit; a deepen that limit stops normally leaves the clone's history as it was and can be rerun; if git had to be killed it can leave `.git/shallow.lock`, after which each deepen of that copy prints only `failed: <path>` and a tag fetch at depth 1 fails on the lock, until the tree's administrator removes it once no git runs there. If the line still appears after the deepen, the history runs deeper than it reaches (A382), and `ghq-sync --full` repairs it. The boundary script shows it on the shapes that failed before: the tag's commit fetched at depth 1, a commit fetched by id above a branch's whole history, a root at the depth of a fetch, and a branch upstream rewrote through a commit fetched by id; each leaves every ref reaching what it reached and no boundary on held history, and the next update fast-forwards, or, on the rewritten branch, fails without the line.
- **Alternatives considered**: a deepen sized to the gap, which hid 11 commits on `nixos-hardware` and hides `master`'s held history in the boundary script (A380); `--unshallow`, which no request runs, and git's own infinite depth (2,147,483,647), which the request refuses above 1,000,000; `ghq-sync --full` (promote), which also hides nothing but refetches every blob and makes the copy a full clone, which the tree avoids.

### D4: Report, and leave the repair to an account

- **Choice**: the writer changes nothing in the repository; the account runs the named repair.
- **Rationale**: an automatic heal, with its repair of `.git/shallow` and a record that made a stopped request's repair crash-safe, was built and failed verification four times (§ "The automatic heal this change set aside"). Each remedy of the repair's crash-safety exposed another state in which held history stayed hidden or the copy stayed blocked. A report writes nothing, so it can hide nothing and block nothing; the failure it reports was 2 of 679 copies, and its repair is one command.

### D5: Where the cases run

- **Choice**: a third handler script, `test_handler_boundary.py`, with its own check `package-ghq-shared-test-handler-boundary`.
- **Rationale**: the request-half check must not grow, and the history check covers the history walk; the boundary cases need fixtures of their own (an upstream that serves a commit by id, twin clones), and a check of their own times them apart.

## The automatic heal this change set aside

The change first had the writer heal the update itself: fetch the upstream branch to a doubling depth until the local tip was in its history, remove the boundaries that fetch placed on held history, check that every ref still reached what it reached, and fast-forward; a deepen got the same repair, and a record `.git/ghq-writer-repair` let the next request finish the repair of one that was stopped.
Four verifications, recorded in `verify.md`, each failed it:

- The first: a round that failed after its pack landed made the copy unreadable and every later update fail, and a request stopped between a round's fetch and its repair hid held history for good, with no reply saying so.
- The second: a heal or deepen overwrote a pending record whose repair had failed, and the history that record named stayed hidden.
- The third: a cut made while an older record was pending stayed hidden, and the next reply said the history was repaired.
- The fourth: a heal whose depth landed on a root commit failed its own check, and the rule that no heal or deepen runs while a repair is pending then blocked the copy for good.

The commits stay out of the main line as a record; this change reports instead (D4).

## Risks / Trade-offs

- [The named repair fetches the whole history's commits and trees below the boundaries: for a depth-1 copy of nixpkgs 1,131,790 commits, 547 MB as commits alone] → it runs only when an account asks, on the copy the reply names, and `ghq-sync --help` says so; promote, the other repair that hides nothing, also fetches every blob.
- [A copy stays blocked until an account runs the repair] → every update says so and names the command, and `boundary=blocked` lets the hosts' logs be counted.
- [A copy whose history ran deeper than 1,000,000 commits below a boundary would keep a boundary there] → A382 records the deepest histories measured; the line appearing again after the deepen shows it, and `ghq-sync --full` repairs that copy.
- [An update upstream rewrote through a commit held without its history gets the line and a repair that does not make it succeed] → the line says so: an update still failing after the repair without the line was rewritten upstream, and the repair hid nothing.

## Migration Plan

Each host gets the report by its usual deploy; nothing in a copy changes.
Rollback is a revert of the handler commit.

## Open Questions

None.
