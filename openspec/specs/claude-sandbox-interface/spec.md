# claude-sandbox-interface Specification

## Purpose

The machine-side contract between this repository and a Claude Code cloud environment's setup step: which Nix store path the setup step names, where it fetches it from, and the platform limits the generated script stays within.
Trust boundary: these properties guarantee only that the setup step fetches the named store path from the two binary caches, accepting it only under their signing keys, and runs that path's activation.
They do not guarantee that the caches still hold the path, that the platform runs the setup step, or that the activation succeeds; the `claude-sandbox-bootstrap` capability states the behaviour, and the world assumptions it rests on state the platform facts.

## Requirements

### Requirement: An environment can be pinned by an argument

(R2) Given a store path as the argument after `--` in the setup box, the setup app SHALL realise that path from the two caches under their keys and activate it, without evaluating a flake or walking `main`.
The pin SHALL be an argument, not an environment variable, because the setup step cannot read the environment's variables (A172).
Relies on: A172, A177; S: the app's argument handling.

#### Scenario: A pinned bootstrap runs

- **WHEN** the setup box's flake reference is followed by `-- /nix/store/…-home-manager-generation`
- **THEN** the app realises and activates that path with no `git clone` or walk evaluation, and its marker records `mode=pinned`

### Requirement: The setup box holds a fixed bootstrap

(R3) The setup box SHALL hold a fixed bootstrap generated from `lib/caches.nix`: `#!/bin/bash`; one `nix run` command, split by `\` continuations into lines of at most 200 columns, with the two caches, their keys and `accept-flake-config false`, on `git+https://github.com/cameronraysmith/vanixiets?ref=main&shallow=1#claude-sandbox-setup`; and `exit 0`.
Relies on: A170, A175, A184, A187, T5; S: the `claude-sandbox-setup-script` check.

#### Scenario: The documented bootstrap drifts

- **WHEN** `lib/caches.nix` changes, a bootstrap line exceeds 200 columns with a tab counting 8, or the bootstrap in the app module's comment or the profile's README differs from the lines the check generates
- **THEN** the `claude-sandbox-setup-script` check fails evaluation, naming the wide line or the file

#### Scenario: A commit changes the setup app

- **WHEN** a commit on `main` changes `modules/apps/claude-sandbox-setup.sh`
- **THEN** the setup box is unchanged, and the next environment snapshot runs the changed app

### Requirement: Cloud sessions run main's newest published closure

(R1) Without a pin, each environment snapshot SHALL hold the `claude-sandbox@x86_64-linux` closure of the newest of `main`'s 5 newest first-parent commits that `cache.scientistexperience.net` serves, with no operator action per update.
Relies on: A175, A184, A185, T1, T2, T4; S: the app's walk, the fixed bootstrap (R3), substitution (R7).

#### Scenario: A profile change lands on main

- **WHEN** a commit on `main` changes the profile and nixbot has published its closure
- **THEN** the next environment snapshot holds that closure, with no change to the setup box

### Requirement: Track mode walks back main's first-parent history

Without a pin, the setup app SHALL list `main`'s 5 newest first-parent commits and, from the tip, evaluate each one's activation package path with the two caches and keys passed as bash arrays.
It SHALL accept the first path whose narinfo `cache.scientistexperience.net` answers with 200, treating a failed evaluation as a miss, and stop after 5 commits or about 300 s.

#### Scenario: The tip is unpublished

- **WHEN** the tip's narinfo answers 404 and its parent's answers 200
- **THEN** the setup app accepts the parent's path without evaluating further commits

#### Scenario: The budget runs out

- **WHEN** 5 commits are missed or about 300 s pass
- **THEN** the setup app activates nothing, records the misses, and exits 0

### Requirement: The setup logic is the claude-sandbox-setup app

(R4) The setup logic SHALL be the flake app `claude-sandbox-setup`, declared as `modules/apps/claude-sandbox-setup.nix` with its text in the co-located `claude-sandbox-setup.sh`, built by `writeShellApplication` so that its build shellchecks it.
Relies on: A177; S: the app's build, which the `claude-sandbox-setup-script` check depends on.

#### Scenario: The script has a shellcheck finding

- **WHEN** `modules/apps/claude-sandbox-setup.sh` holds a construct shellcheck reports
- **THEN** the app's build fails, and with it the `claude-sandbox-setup-script` check

### Requirement: Every command the setup logic calls comes from the flake

(R5) Every external command the setup app runs SHALL come from its `runtimeInputs`, Nix included; only bash and the image's Nix come from the image, and only to start the app.
Relies on: A177; S: the app's `runtimeInputs`, the bootstrap's options.

#### Scenario: The image lacks a tool

- **WHEN** the image has no `git` or `awk` on its `PATH`
- **THEN** the app still lists, evaluates, realises and activates, since its wrapper's `PATH` names them from the store

### Requirement: Setup never fails the session

(R6) The setup box and the setup app SHALL both end in `exit 0`, and every run of the app SHALL append one marker line to `/var/log/claude-sandbox-bootstrap/setup.log`.
Relies on: A170; S: the app's final `exit 0` and its one marker write, the `claude-sandbox-setup-script` check.

#### Scenario: Nothing can be activated

- **WHEN** none of the 5 newest commits is published, or the realise or activation fails
- **THEN** the app writes its marker and exits 0, and the session starts without the profile

### Requirement: The profile's closure is substituted, never built

(R7) The setup app SHALL realise the profile's closure with `--max-jobs 0 --option builders ''` from the two caches, so a missing path fails instead of building; small local builds outside the profile, such as the app's wrapper, are allowed.
Relies on: A175, T4; S: the realise options, the walk (R1), the `claude-sandbox-setup-script` check.

#### Scenario: Part of the closure is missing from the caches

- **WHEN** the realise needs a path neither cache serves
- **THEN** it fails without building, activation is skipped, and the app exits 0

### Requirement: The marker records the walk

Each run's marker SHALL name the outcome (`mode=pinned`, `tracked` or `none`), `main`'s tip when the walk ran, the commit used and its distance from that tip, each skipped commit with its reason, and the walk's seconds and the realise and activate codes and seconds.

#### Scenario: A run that walked back

- **WHEN** the setup app accepted `main~1` after the tip's evaluation failed
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
