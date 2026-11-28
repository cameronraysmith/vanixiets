## ADDED Requirements

### Requirement: A380 — A depth fetch marks the commits at its new depth as boundaries, held or not

It is true of git at the version the fleet installs (2.56.0), independent of what this fleet builds, that a `--depth` or `--deepen` fetch into a shallow repository lists in `.git/shallow` exactly the commits at the new depth, even those whose parents the repository holds, hiding the history below them, and no commit at a smaller depth.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Evidence**: git-fetch(1) at 2.56.0: `--depth` deepens or shortens "to the specified number of commits", from the tip of each fetched ref; `--deepen` counts "from the current shallow boundary". Observed on stibnite on 2026-11-27: `logs/cam140-plan-heal-scratch-20261127-190204.log` (`--deepen=3` leaves `master` reaching 1 of its 34 commits and another remote-tracking branch 5 of its 23; `--depth=6` marks two held commits) and the copy of `github.com/nixos/nixos-hardware` (`logs/cam140-stuck-copy-nixos-hardware-20261127-183759/before-restore.txt`, 11 of 2,941 commits hidden after `--deepen 2`); a depth fetch whose depth equals a root commit's distance from the tip marks the root (`verify.md`, the fourth verification).

#### Scenario: Observed by the boundary handler cases

- **WHEN** the boundary script deepens by 2 a clone holding `master`'s whole history below a commit fetched by id
- **THEN** `master`'s commit reaches fewer commits than before

#### Scenario: git stops marking held commits

- **WHEN** a git release leaves a commit whose parents the repository holds out of `.git/shallow` after a depth fetch
- **THEN** this assumption is void; the warning in the `shared-reference-tree-interface` requirement `The writer's reply names a shallow boundary between a failed update's branch and its upstream`, `ghq-sync`'s usage text and the skill `dependency-source-acquisition` are re-examined, a sized deepen then being safe

### Requirement: A381 — A shallow boundary hides a commit's parents from a fast-forward

It is true of git, independent of what this fleet builds, that a commit listed in `.git/shallow` is read as having no parents by every history walk, merge bases included, so `git pull --ff-only` refuses to fast-forward a branch its upstream reaches only through a boundary, and a fetch with no depth leaves that boundary in place.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Evidence**: gitrepository-layout(5) at 2.56.0, `shallow` ("similar to info/grafts but is internally used and maintained by shallow clone mechanism"); observed on stibnite on 2026-11-27 in `logs/cam136-shallow-boundary-ff-scratch-20261127-163055.log` (`fatal: Not possible to fast-forward, aborting.`, exit 128, again after one more upstream commit) and in the writer's replies for `github.com/Mic92/sops-nix` and `github.com/nixos/nixos-hardware` (`logs/cam140-stuck-copy-{sops-nix,nixos-hardware}-20261127-183759/reproduce-ghq-sync-u.txt`).

#### Scenario: Observed by the failing-first handler cases

- **WHEN** the boundary script's blocked updates run against the handler without the report
- **THEN** each update exits 1 with git's fast-forward refusal

#### Scenario: git fetches through a boundary

- **WHEN** a git release, fetching a branch with no depth into a shallow repository, removes a boundary the fetched history reaches or fetches its parents
- **THEN** this assumption is void; the `shared-reference-tree-interface` requirement `The writer's reply names a shallow boundary between a failed update's branch and its upstream` stops being reached, and its condition is re-examined

### Requirement: A382 — No reference repository's history runs 1,000,000 commits below a boundary

It is true of the repositories the shared tree holds, independent of what this fleet builds, that from any commit no path of parents to a root commit is as long as 1,000,000 commits, so a deepen of 1,000,000 below the boundaries of the branches it fetches reaches their roots and leaves no boundary on them.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Evidence**: measured on stibnite on 2026-11-27 in scratch treeless clones (`logs/agent-reports-20261126/Cam140Plan.md`, "Depth to the roots"): a deepen to the roots needs depth 7,237 for home-manager, 3,903 for BAML, 10,240 for dfinity/ic and 7,667 for nixpkgs, whose 1,131,790 commits are the most of any copy measured; `ghq-sync --deepen 793` reached the roots of `nixos-hardware`.

#### Scenario: Observed by the boundary handler cases

- **WHEN** the boundary script runs the named deepen on a clone holding a root commit
- **THEN** the clone has no boundary left

#### Scenario: A copy deeper than the named depth

- **WHEN** a reference repository's history from a boundary to a root is found to run 1,000,000 commits or more, as an update whose reply still names a shallow boundary after the named deepen shows
- **THEN** this assumption is void; the repair the `shared-reference-tree-interface` requirement `The writer's reply names a shallow boundary between a failed update's branch and its upstream` names may leave a boundary on held history, that copy is repaired with `ghq-sync --full`, as `ghq-sync`'s usage text tells the reader, and the named depth is re-examined
