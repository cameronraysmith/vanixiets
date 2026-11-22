## MODIFIED Requirements

### Requirement: The setup step names the activation package by store path

When the setup step sets `PIN=` to a store path, it SHALL fetch that path with `nix-store --realise` from `cache.scientistexperience.net` and `cache.nixos.org`, trusting only their public keys, and run the path's `activate` as root, and SHALL NOT evaluate a flake.
`nix run .#claude-sandbox-setup-script` in its pinned mode SHALL print that `PIN=` line for a revision.

#### Scenario: The generated script is read

- **WHEN** `nix run .#claude-sandbox-setup-script` prints the pinned setup script for a revision
- **THEN** it sets `PIN` to the store path of that revision's activation package, realises it with only those two substituters and their keys, and runs its `activate`, with no `nix eval`, `nix build` or flake reference on that path

### Requirement: The named store path is the CI check's output

A `PIN=` store path the pinned mode prints SHALL be the output of `checks.x86_64-linux.home-manager-claude-sandbox` at the revision its comment records, so that the build service builds it and publishes it to `cache.scientistexperience.net`.

#### Scenario: The script's store path is checked

- **WHEN** the `claude-sandbox-setup-script` check is built for a revision
- **THEN** it fails unless the pinned script's `PIN` equals that revision's `home-manager-claude-sandbox` output path

### Requirement: The setup script stays within the platform's limits

Each generated setup script, pinned or track mode, SHALL have at most 100 lines of at most 200 bytes each once filled in, and its last line SHALL be `exit 0`.

#### Scenario: A script over the limits

- **WHEN** either template would produce a line over 200 bytes once filled, more than 100 lines, or a last line other than `exit 0`
- **THEN** the `claude-sandbox-setup-script` check fails evaluation with its own message

## ADDED Requirements

### Requirement: The track-mode text is the same for every revision

The track-mode setup script SHALL contain no revision, store path or date that depends on a commit, so that a new commit on `main` leaves the cloud environment's setup step unchanged.

#### Scenario: Two revisions print the track-mode script

- **WHEN** `nix run .#claude-sandbox-setup-script` prints the track-mode script at two different revisions
- **THEN** the two outputs are byte-identical, and the check fails on a template holding a 40-hex revision or a store path

### Requirement: Track mode walks back main's first-parent history

Without `PIN`, the setup step SHALL fetch `main`'s first-parent history to depth 5 and, from the tip, evaluate each commit's `claude-sandbox@x86_64-linux` activation package path with the two caches and keys passed as a bash array.
It SHALL accept the first path whose narinfo `cache.scientistexperience.net` answers with 200, treating a failed evaluation as a miss, and stop after 5 commits or about 300 s.

#### Scenario: The tip is unpublished

- **WHEN** the tip's narinfo answers 404 and its parent's answers 200
- **THEN** the setup step accepts the parent's path without evaluating further commits

#### Scenario: The budget runs out

- **WHEN** 5 commits are missed or about 300 s pass
- **THEN** the setup step activates nothing, records the misses, and exits 0

### Requirement: Track mode substitutes and never builds

The track-mode setup step SHALL realise the accepted path with `--max-jobs 0` and `--option builders ''` from the two caches, run its `activate` as root unless it is already the current home-manager generation, and SHALL NOT build any derivation.

#### Scenario: Part of the closure is missing from the caches

- **WHEN** the realise needs a path neither cache serves
- **THEN** it fails without building, activation is skipped, and the script exits 0

### Requirement: The marker records the walk

Each setup run SHALL append one line to `/var/log/claude-sandbox-bootstrap/setup.log` naming the mode, the commit used and its distance from `main`'s tip, the evaluation, realise and activate exit codes and seconds, and each skipped commit with its reason, and SHALL then exit 0.

#### Scenario: A run that walked back

- **WHEN** the setup step accepted `main~1` after the tip's evaluation failed
- **THEN** its marker names that commit, distance 1, and the tip with reason `eval` and its exit code

### Requirement: The staleness hook only reads

A SessionStart hook SHALL compare the commit the snapshot's marker records with `main`'s tip from `git ls-remote`, and append one `staleness` line to `run.log` with that commit, the distance the marker recorded, and whether the tip differs; it SHALL print nothing and exit 0.
It SHALL NOT fetch history, evaluate, realise or activate anything.

#### Scenario: The hook runs in a stale session

- **WHEN** a session starts from a snapshot whose marker records `main~2`, and `main`'s tip has moved since
- **THEN** `run.log` gains one `staleness` line naming the commit, distance 2 and a moved tip, the hook's stdout is empty, and the current home-manager generation is unchanged

### Requirement: Every lock source is in the cache

`checks.x86_64-linux.flake-input-sources` SHALL refer to the source of every non-`path` node of `flake.lock`, so that nixbot's upload of its output puts each in `cache.scientistexperience.net`, and the cache-completeness timer covers that output on `main`.

#### Scenario: A lock change adds an input

- **WHEN** a commit adds a flake input and its build lands on `main`
- **THEN** the check's output refers to the new input's source, so the upload of the output's closure carries it, and cache-completeness fails if the check's output is not served
