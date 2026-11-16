## ADDED Requirements

### Requirement: The updater runs on a fixed schedule within a bounded envelope

magnetite's evaluated configuration SHALL enable the nixpkgs `services.renovate` module for `cameronraysmith/vanixiets` alone, on the schedule `*-*-* 00/2:17:00` with up to ten minutes of timer jitter, with at most four commits per run, and with a unit run-time ceiling of fifty-five minutes, shorter than the forge credential's lifetime.

#### Scenario: The evaluated settings and timer are read

- **WHEN** `services.renovate.settings`, `systemd.services.renovate.serviceConfig` and `systemd.timers.renovate.timerConfig` are read from magnetite's evaluated configuration
- **THEN** the settings carry `platform` `github`, `repositories` exactly `["cameronraysmith/vanixiets"]`, `autodiscover` false, `onboarding` false, `requireConfig` `required`, `binarySource` `global`, `repositoryCache` `enabled` and `prCommitsPerRunLimit` `4`; the timer carries `OnCalendar` `*-*-* 00/2:17:00` and `RandomizedDelaySec` `10min`; and the unit carries `Nice=10`, `CPUWeight=20`, `IOWeight=20`, `MemoryHigh=4G`, `MemoryMax=8G` and `RuntimeMaxSec=55min`

#### Scenario: The timer fires during a run

- **WHEN** `renovate.timer` elapses while `renovate.service` is still active
- **THEN** no second instance starts, because the unit is still active

### Requirement: The application key is read only by a privileged pre-start step

The App's private key SHALL be readable on magnetite only by root and SHALL be read only by a `+`-prefixed pre-start step of `renovate.service`, which mints a per-run installation token that reaches the Renovate process through a file the main script removes before Renovate starts; the key SHALL appear in no unit credential, settings file or store path.

#### Scenario: The rendered unit is read

- **WHEN** the rendered `renovate.service` unit and the generator `renovate-github-app-secret-key` are read from magnetite's evaluated configuration
- **THEN** the unit has exactly one `+`-prefixed `ExecStartPre`, no `LoadCredential`, `services.renovate.credentials` is empty, `RuntimeDirectory=renovate` has mode `0700`, the script assigns `RENOVATE_TOKEN` from `/run/renovate/token` and removes the file before `exec renovate`, and the generator's `key.pem` is owned by root with no `restartUnits`

#### Scenario: The sandboxed process looks for the key

- **WHEN** a process running as the unit's dynamic user, under the unit's sandbox, tries to open the key file's path
- **THEN** the open is refused, because the file is root-owned with mode `0400` and the dynamic user is neither root nor in a group with access

#### Scenario: A run starts after the token file was left behind

- **WHEN** `renovate.service` starts
- **THEN** the pre-start step overwrites the token file with a freshly minted token, and the main process has removed the file before Renovate begins its first forge request

### Requirement: The forge application holds a fixed permission set over this repository alone

The GitHub App `vanixiets-renovate` SHALL hold no permission outside a fixed list, SHALL have its webhook inactive, SHALL have exactly one installation whose repository selection is exactly `cameronraysmith/vanixiets`, and SHALL NOT be a bypass actor on any ruleset of that repository; a permission MAY be dropped from the list once a full dry run and a live run show no forge request needing it.

#### Scenario: The App and its installation are read from the forge

- **WHEN** the App, its installations, and the repository's rulesets are read through the forge's API
- **THEN** the permissions are within Contents write, Pull requests write, Issues write, Workflows write, Commit statuses write, Checks write, Administration read, Dependabot alerts read and Metadata read, with no Merge queues permission; the webhook is inactive; the single installation lists only `cameronraysmith/vanixiets`; and no ruleset's bypass actors include the App

### Requirement: Update tasks are attached per dependency kind in the repository's configuration

`.github/renovate.json` SHALL attach a complete post-upgrade task chain to each dependency kind whose update leaves a lock file or derived pin behind, as rules placed after every other rule in a fixed order, SHALL disable bun-manager updates of the npm Playwright packages, and SHALL carry no `gitIgnoredAuthors`.

#### Scenario: The repository configuration is read

- **WHEN** `.github/renovate.json` is read
- **THEN** after every other rule it carries, in order: manager `custom.regex` running `nix flake lock` with file filter `flake.lock`; manager `bun` running `nix run .#regenerate-bun-nix` with file filter `bun.nix`; manager `bun` with packages `playwright` and `@playwright/test` and `enabled` false; and manager `custom.regex` with packages `cameronraysmith/playwright-web-flake` and `pietdevries94/playwright-web-flake` running `nix flake lock`, `just bun-repin-playwright`, `bun install --ignore-scripts` and `nix run .#regenerate-bun-nix` in that order with file filters `flake.lock`, `packages/docs/package.json`, `bun.lock` and `bun.nix`; every task rule spells out `commands`, `fileFilters` and `executionMode` `branch`; there is no `gitIgnoredAuthors`; and `checks.x86_64-linux.renovate-config` passes with `--strict`

#### Scenario: A rule groups bun and flake-reference updates into one branch

- **WHEN** a rule groups bun-manager and `custom.regex` updates into one branch without its task object being the union of both chains
- **THEN** under A110 that branch runs only one chain, and this requirement is violated

#### Scenario: The Playwright chain is reordered before the generic rule

- **WHEN** the Playwright `custom.regex` rule is placed before the generic `custom.regex` rule
- **THEN** under A110 a Playwright flake bump runs only `nix flake lock`, which is why the order above is part of this requirement

### Requirement: Update task commands are admitted by the allowlist, and a check ties the repository's commands to it

magnetite's evaluated Renovate settings SHALL admit exactly four anchored task commands and no shell execution, and the flake check `renovate-allowed-commands` SHALL fail whenever the repository's or the module's rules ask for a task command those patterns do not admit, or ask for none at all.

#### Scenario: The evaluated allowlist is read

- **WHEN** `services.renovate.settings` is read from magnetite's evaluated configuration
- **THEN** `allowedCommands` is exactly `^nix flake lock$`, `^nix run \.#regenerate-bun-nix$`, `^just bun-repin-playwright$` and `^bun install --ignore-scripts$`, and `allowShellExecutorForPostUpgradeCommands`, `allowScripts` and `exposeAllEnv` are unset

#### Scenario: The repository adds a command the instance does not allow

- **WHEN** a rule in `.github/renovate.json` gains a task command that no `allowedCommands` pattern matches
- **THEN** `checks.<system>.renovate-allowed-commands` fails and names the command, before the change can land

#### Scenario: Every task rule is removed

- **WHEN** neither `.github/renovate.json` nor the module's global rules carry any task command
- **THEN** the check fails rather than passing vacuously

### Requirement: The tools on the updater's path match the repository's declarations

`systemd.services.renovate.path` SHALL include `config.nix.package`, the bun derivation the repository's default development shell carries, `just`, `jq`, and `bash`, and magnetite's evaluation SHALL fail with an assertion message when that bun's version differs from the version in `package.json`'s `packageManager` field.

#### Scenario: The repository moves to a new bun

- **WHEN** `package.json`'s `packageManager` names a bun version different from the bun on the updater's path
- **THEN** evaluation of magnetite's configuration fails with the assertion's message, so no host is deployed with a bun that could rewrite `bun.lock` differently

#### Scenario: The unit's path is read

- **WHEN** the unit's path is read from magnetite's evaluated configuration
- **THEN** it contains nix at the daemon's version, bun at `packageManager`'s version, `just`, `jq`, and `bash`

### Requirement: The updater neither labels for the queue nor enables auto-merge

Neither the module's global settings nor `.github/renovate.json` SHALL set `automerge` to true, or any `addLabels` or `labels` value naming the merge queue's label `merge-queue`.

#### Scenario: Update pull requests are read after a run

- **WHEN** the update pull requests opened by a run are read through the forge's API
- **THEN** none carries the `merge-queue` label or a native auto-merge request that the updater set

### Requirement: A full dry run writes nothing to the forge and records each would-be commit

While magnetite's evaluated `services.renovate.settings.dryRun` is `full`, a run SHALL create no branch, commit, pull request, comment or issue on `cameronraysmith/vanixiets`, and its journal SHALL record, for each branch it would write, a `DRY-RUN: Would commit files` line naming the file set, together with each task command it ran and any refusal by the allowlist.
While a temporary `branchPrefix` is set for such a run, every branch it would write SHALL be named under that prefix.

#### Scenario: A dry run is started by hand

- **WHEN** the operator starts `renovate.service` with `dryRun` `full`
- **THEN** the forge shows no new branch, pull request, comment or issue from the App, and `journalctl -u renovate.service` shows the minted-token step, each task command executed, and each would-be commit's file set

### Requirement: This capability states its own trust boundary

This capability SHALL state what its properties guarantee and what they do not, and SHALL NOT be described, by itself or in any downstream report, as an end-to-end guarantee that every update commit is consistent or that update pull requests are safe to merge.

#### Scenario: The properties above are read as a set

- **WHEN** the properties of this capability are read as a set
- **THEN** what they establish is that the updater on magnetite is configured for one repository on a fixed schedule within a bounded envelope, that its application key is reachable only from a privileged pre-start step and its token only from its own process tree for at most one run, that the App holds a bounded permission set over one repository with no bypass, that the repository asks for task chains per dependency kind which the allowlist admits, that the tools on its path match the repository's declarations, that it sets no merge authorization, and that a full dry run writes nothing

#### Scenario: What lies outside the boundary is read

- **WHEN** a reader asks what these properties do not establish
- **THEN** they do not establish GitHub's token lifetime, scoping or commit signing (A107, A108), Renovate's task ordering, admission, rule merging or commit-despite-failure behaviour (A109–A111), its treatment of foreign branches and dashboards or its dry-run behaviour (A112, A113), that magnetite's daemon admits the updater's account (A114), that a task command succeeds on a given upstream release, that upstream releases are themselves correct, or that the hosted updater has been stopped, which is an operator act on the forge
