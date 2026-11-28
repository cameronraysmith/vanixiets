## ADDED Requirements

### Requirement: A380 — A depth fetch marks the commits at its new depth as boundaries, held or not

It is true of git at the version the fleet installs (2.56.0), independent of what this fleet builds, that a `--depth` or `--deepen` fetch into a shallow repository lists in `.git/shallow` the commits at the new depth, even those whose parents the repository holds, hiding the history below them.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Evidence**: git-fetch(1) at 2.56.0: `--depth` deepens or shortens "to the specified number of commits", from the tip of each fetched ref; `--deepen` counts "from the current shallow boundary". Observed on stibnite on 2026-11-27: `logs/cam140-plan-heal-scratch-20261127-190204.log` (`--deepen=3` leaves `master` reaching 1 of its 34 commits and another remote-tracking branch 5 of its 23; `--depth=6` marks two held commits) and the copy of `github.com/nixos/nixos-hardware` (`logs/cam140-stuck-copy-nixos-hardware-20261127-183759/before-restore.txt`, 11 of 2,941 commits hidden after `--deepen 2`).

#### Scenario: Observed by the heal's handler cases

- **WHEN** the handler cases that heal a fast-forward, or deepen a clone holding history below an upstream-side boundary, run
- **THEN** before the repair, the depth fetch has marked a held commit as a boundary

#### Scenario: git stops marking held commits

- **WHEN** a git release leaves a commit whose parents the repository holds out of `.git/shallow` after a depth fetch
- **THEN** this assumption is void; the `shared-reference-tree-interface` requirements `A heal removes the boundaries its fetch placed on held history` and `A deepen removes the boundaries it placed on held history` lose their discharge until their handler cases, whose repair then finds nothing to remove, are re-examined for what still witnesses them

### Requirement: A381 — A shallow boundary hides a commit's parents from a fast-forward

It is true of git, independent of what this fleet builds, that a commit listed in `.git/shallow` is read as having no parents by every history walk, merge bases included, so `git pull --ff-only` refuses to fast-forward a branch its upstream reaches only through a boundary, and a fetch with no depth leaves that boundary in place.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Evidence**: gitrepository-layout(5) at 2.56.0, `shallow` ("similar to info/grafts but is internally used and maintained by shallow clone mechanism"); observed on stibnite on 2026-11-27 in `logs/cam136-shallow-boundary-ff-scratch-20261127-163055.log` (`fatal: Not possible to fast-forward, aborting.`, exit 128, again after one more upstream commit) and in the writer's replies for `github.com/Mic92/sops-nix` and `github.com/nixos/nixos-hardware` (`logs/cam140-stuck-copy-{sops-nix,nixos-hardware}-20261127-183759/reproduce-ghq-sync-u.txt`).

#### Scenario: Observed by the failing-first handler cases

- **WHEN** the heal's handler cases run against the handler without the heal
- **THEN** the update exits non-zero with git's fast-forward refusal

#### Scenario: git fetches through a boundary

- **WHEN** a git release, fetching a branch with no depth into a shallow repository, removes a boundary the fetched history reaches or fetches its parents
- **THEN** this assumption is void; the `shared-reference-tree-interface` requirement `An update heals a fast-forward a shallow boundary blocks` stops being reached, and its condition is re-examined

### Requirement: A382 — .git/shallow lists one commit per line, and an entry whose parents are held can go

It is true of git, independent of what this fleet builds, that `.git/shallow` holds one commit id per line, which git replaces through `.git/shallow.lock`, and that removing an entry whose commit's parents and their history are present leaves a repository every walk reads whole.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Evidence**: gitrepository-layout(5) at 2.56.0 (`shallow`); observed on stibnite on 2026-11-27 in `logs/cam140-plan-heal-scratch-20261127-190204.log`: after the removal `git --no-lazy-fetch fsck --connectivity-only` passes, every ref reaches its earlier count, `git pull --ff-only` succeeds, and the clone keeps `remote.origin.partialclonefilter = blob:none`. The lock file's name and the removal of an empty file are read from git's source at apply.

#### Scenario: Read at the source at apply

- **WHEN** git's shallow-file writing is read at the version the fleet installs
- **THEN** it writes `shallow.lock` beside `shallow`, one id per line, renames it over, and removes the file when the list is empty

#### Scenario: git changes the file's form

- **WHEN** a git release stores shallow boundaries elsewhere or in another form, or validates `.git/shallow` against a checksum
- **THEN** this assumption is void; the `shared-reference-tree-interface` requirements `A heal removes the boundaries its fetch placed on held history` and `A deepen removes the boundaries it placed on held history` lose their discharge until the repair is rewritten for that form
