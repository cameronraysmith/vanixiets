<!--
Raw capture of the brainstorming step for this change.

Procedural note, recorded rather than elided: the interactive `superpowers:brainstorming`
dialogue was not run inside this change. The exploration happened upstream on 2026-11-16:
a design session read the nixpkgs module, its NixOS test and Renovate's source at the
version nixpkgs ships, probed the module's sandbox on magnetite with a throwaway transient
unit, and wrote `logs/renovate-self-host-design.md` (gitignored) with the probe log
`logs/renovate-probe-20261116-133754.log`. The operator then answered that design's open
questions. This file is the decision log the interactive skill would have produced: each
question, the options, the answer taken, and the evidence. Answers the operator gave are
marked `[given]`; answers settled from source or probe evidence are marked `[decided]`.

Citation abbreviations used throughout this change:
- M: nixpkgs `nixos/modules/services/misc/renovate.nix`; T: `nixos/tests/renovate.nix`.
  Both are byte-identical at the local flake.lock pin `6dadaf4375be` and at magnetite's
  running revision `82566dfe91ca`, and `pkgs.renovate` is 44.236.2 at both.
- R: Renovate's source at tag `44.236.2`, the version nixpkgs ships.
-->

# Background

Dependency updates for `cameronraysmith/vanixiets` come from the Mend-hosted Renovate app, configured by `.github/renovate.json`.
Its pull requests are routinely incomplete when they arrive.
A regex-manager bump of a `flake.nix` ref leaves `flake.lock` unchanged, and a bun-manager update rewrites `bun.lock` without regenerating `bun.nix`.
`.github/workflows/regenerate-lock-files.yaml` repairs both after the fact on GitHub Actions: it runs `nix flake lock` and `nix run .#regenerate-bun-nix` on `renovate[bot]` pull requests and pushes fix-up commits as `github-actions[bot]`, which `.github/renovate.json::gitIgnoredAuthors` then tells Renovate to tolerate.
nixbot therefore evaluates the first push of every such pull request against an inconsistent tree, goes red, and runs again after the fix-up.
The Playwright pair is worse: npm `playwright` and `@playwright/test` must equal the `playwright-web-flake` driver version (`pkgs/by-name/vanixiets-docs/package.nix:334-350` guards the browsers.json revision), and the current "group playwright across npm and flake.nix" rule only co-schedules the two bumps without making them agree; pull request #3856 (npm 1.65.1, red) is the live example.

The hosted app cannot fix this from inside Renovate, because `postUpgradeTasks` only run commands a self-hosted global `allowedCommands` admits.
Magnetite already runs the fleet's forge, nixbot, gitea-mq and the binary cache, and nixpkgs ships a `services.renovate` module with a NixOS test.

# Decision chain

## Q1 [given]: where does Renovate run?

Options: keep the Mend-hosted app; `renovatebot/github-action` on a schedule; a nixbot scheduled effect; a custom module; the nixpkgs `services.renovate` module on magnetite.
Taken: the nixpkgs module on magnetite.
The hosted app cannot run `postUpgradeTasks`.
The GitHub Action spends Actions minutes and, once the repository goes private, depends on private-repository minutes.
A nixbot effect would put a long-running, network-heavy job on the build service's scheduler.
A custom module duplicates a maintained one that ships a VM test (T, registered at `nixos/tests/all-tests.nix:1616`).

## Q2 [given]: how does the self-hosted instance authenticate to GitHub?

Options: a bot user with a fine-grained PAT; a dedicated GitHub App.
Taken: a dedicated App `vanixiets-renovate`, installed on vanixiets only.
A PAT needs a second GitHub user, is long-lived, has the whole account's reach, and gets no `platformCommit`, so commits would be unsigned without a separately managed `gitPrivateKey`.
An App installation token is repository-scoped and expires within an hour; with an App token Renovate discovers its own author identity (R `platform/github/index.ts:261-294`) and `platformCommit: auto` resolves to `enabled` (R `platform/github/scm.ts:17-20`), so commits are made through the API and GitHub signs them.

## Q3 [decided]: how does a token reach Renovate without the private key entering the sandbox?

Options: the module's `credentials` option carrying the PEM; `credentials` carrying a token minted by another unit; a privileged pre-start step minting per run.
Taken: `ExecStartPre=+` runs `gh-token generate` with full privileges, reads the root-0400 clan vars PEM, writes a one-hour installation token into the unit's `RuntimeDirectory` owned by the dynamic user; a `lib.mkBefore` prefix on the module's `script` (`types.lines`, `nixos/lib/systemd-unit-options.nix:419-423`) reads it into `RENOVATE_TOKEN` and deletes the file before `exec renovate`.
`LoadCredential` (M:54-64,141,172-177) is read at unit start, before any `ExecStartPre`, so it can only carry the PEM itself or a token minted earlier by some other unit.
Loading the PEM would expose it to every `postUpgradeTasks` child, which runs repository code under Renovate's uid.
Not yet proven: that `+` ExecStartPre and the `mkBefore` prefix compose in the rendered unit.

## Q4 [given]: where does the App private key live?

Taken: clan vars generator `renovate-github-app-secret-key` with file `key.pem`, populated by `clan vars set`, whose script exits non-zero with a populate message, following `modules/nixos/gitea-mq.nix:48-53`.
No `restartUnits`: each timer run reads the key afresh.

## Q5 [decided]: does nix work inside the module's hardening?

Taken: yes, unmodified.
Probe on magnetite at 2026-11-16 18:37 UTC (`logs/renovate-probe-20261116-133754.log`): a transient unit with all of M's hardening (M:145-168) plus `DynamicUser`'s implied `ProtectSystem=strict`, `PrivateTmp`, `NoNewPrivileges` cloned vanixiets at `27a36ef7` and ran `nix flake lock` (no-op, 0.3 s), a networked `nix flake update playwright-web-flake`, a daemon build of a trivial derivation, the Playwright driver `nix eval` (`1.65.0`), `nix run .#regenerate-bun-nix` (12 s, clean tree), and nixpkgs bun 1.4.4 `install --ignore-scripts --frozen-lockfile` (rc 0, 830 packages).
The dynamic user reaches the daemon because magnetite's `nix.conf` has `allowed-users = *`; it is not trusted (`trusted-users = root @wheel`), so flake `nixConfig` is ignored with a warning.
Only stderr noise was `GC Warning: Could not open /proc/stat` from `ProcSubset=pid`.
Cleanup was verified; the only side effect was a daemon prune of three already-dangling `gcroots/auto` links.
Renovate splits task commands without a shell using its bundled `shlex@3.0.0` (R `lib/util/exec/common.ts:119-131`); `nix run .#regenerate-bun-nix` splits into three arguments with `#` intact.

## Q6 [decided]: which settings are global and which stay in the repository?

Taken: admin settings in `services.renovate.settings` (platform, repositories, autodiscover off, onboarding off, `requireConfig: required`, `binarySource: global`, `repositoryCache: enabled`, `prCommitsPerRunLimit: 4`, `allowedCommands`); repository behaviour in `.github/renovate.json`.
Leave `gitAuthor`, `username`, `platformCommit`, `exposeAllEnv`, `allowScripts` and `allowShellExecutorForPostUpgradeCommands` unset.

## Q7 [decided]: how are post-upgrade tasks attached to the right updates?

Taken: per-manager `packageRules` with `matchManagers`; `custom.regex` runs `nix flake lock` into `flake.lock`; `bun` runs `nix run .#regenerate-bun-nix` into `bun.nix`; both with `executionMode: branch`.
`fileFilters` select which changed files enter the commit, not which updates trigger a task.
`postUpgradeTasks` is not mergeable (R `config/utils.ts:30-45`), so a later rule replaces the whole object and every rule spells out all three fields.
Tasks run after managers' own artifact updates and before commit (R `update/branch/index.ts:400,467,548`), in the clone root.

## Q8 (D7) [given]: how does npm Playwright stay equal to the flake driver?

Taken: disable bun-manager updates of `playwright` and `@playwright/test`; the regex-manager update of `playwright-web-flake.url` carries one branch-level chain `nix flake lock` → `just bun-repin-playwright` → `bun install --ignore-scripts` → `nix run .#regenerate-bun-nix` with file filters `flake.lock`, `packages/docs/package.json`, `bun.lock`, `bun.nix`.
`just bun-repin-playwright` (`justfile:595`) reads the driver version through `nix eval --inputs-from .`, so it must run after the re-lock.
This rule must follow the generic `custom.regex` rule because its task object replaces that one.
Rejected: keeping the cross-manager group, which co-schedules the bumps without making them agree.

## Q9 [decided]: how is the build service protected from Renovate-driven load?

Taken: the module's timer with `RandomizedDelaySec=10min`; `prCommitsPerRunLimit = 4`; `rebaseWhen` left at `auto`, which resolves to `conflicted` because the rulesets' required checks are non-strict; unit controls `Nice=10`, `CPUWeight=20`, `IOWeight=20`, `MemoryHigh=4G`, `MemoryMax=8G`, `RuntimeMaxSec=55min`.
Renovate's own nix work never runs `nix-eval-jobs`, so `modules/nixos/nix-eval-lock.nix` does not apply.
Not taken initially: wrapping tasks in `flock /etc/nix/eval.lock`.

## Q10 [given]: cadence (operator Q14)

Every 2 hours at minute 17.

## Q11 [given]: do Renovate pull requests enqueue themselves into gitea-mq? (operator Q15)

No. Enqueueing stays an operator act; neither the repository config nor `config:recommended` sets automerge.

## Q12 [given]: App permissions (operator Q16)

Start with Renovate's documented permission list as trimmed in the design (Contents rw, Pull requests rw, Issues rw, Workflows rw, Commit statuses rw, Checks rw, Administration r, Dependabot alerts r, Metadata r; Merge queues omitted; webhook off; "Only on this account"); trim after Phase 1 shows which calls are made.
The App is not a ruleset bypass actor.

## Q13 [given]: which bun runs the tasks? (operator Q17)

The repository's toolchain bun, the same derivation the default dev shell carries (`modules/devshells/default.nix:167`), with an evaluation-time assertion that its version equals `package.json::packageManager` (`bun@1.4.4` today).
A divergent bun could reformat `bun.lock`.

## Q14 [given]: how is a disallowed task caught before it runs? (operator Q18, risk R7)

A command that no `allowedCommands` pattern admits, or that exits non-zero, becomes an `artifactErrors` entry (R `execute-post-upgrade-commands.ts:222-229`) and the branch is still committed and pushed (R `update/branch/index.ts:480-500`).
Taken: a flake check asserting every `postUpgradeTasks` command in `.github/renovate.json` matches one of the module's `allowedCommands` patterns.

## Q15 [given]: cutover

Taken: Phase 1 `dryRun: "full"` with a temporary `branchPrefix` and the candidate rules as global `packageRules` (global rules are concatenated before the repository's, R options:1747-1758); `dryRun: full` still runs artifact updates and tasks and only logs commits, pushes and forge writes (R `update/branch/index.ts:400,467`; `commit.ts:65-80`); the temporary prefix keeps the old `renovate[bot]` branches from being treated as foreign-modified (R `util/git/index.ts` isBranchModified).
Then the operator disables the Mend app; the old `renovate[bot]` pull requests are closed and their branches deleted; Dependency Dashboard #832 is closed, because the new instance only finds issues it created (R `platform/github/graphql.ts:27,90`).
Phase 2 is one pull request: the new rules in `.github/renovate.json`, `gitIgnoredAuthors` deleted, `.github/workflows/regenerate-lock-files.yaml` deleted, dry-run settings dropped; then magnetite is deployed and the first live run verified.
Rejected: adopting the old pull requests with `ignorePrAuthor` and a transitional `gitIgnoredAuthors`, which keeps foreign-authored history and stale dashboard state for a saving of a few hours.

## Q16 [given]: scope (operator Q19)

`.github/workflows/update-flake-inputs.yaml` stays on GitHub Actions; a separate later change decides it.

# Design trade-offs carried forward

- No webhooks: dashboard checkboxes and rebase requests wait for the next run (≤ about 2 h 10 min); a manual nudge is `systemctl start renovate.service`.
- The installation token sits in Renovate's environment, readable by same-uid task children through `/proc/<pid>/environ`; exposure is a ≤1 h, vanixiets-only token, and the PEM stays out of reach.
- If magnetite's `allowed-users` is ever narrowed, the dynamic user must be admitted.
- Merge Confidence badges keep rendering as static images; no `matchConfidence` rules exist to lose.
