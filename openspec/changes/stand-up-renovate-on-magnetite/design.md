## Context

Dependency updates for `cameronraysmith/vanixiets` come from the Mend-hosted Renovate app, driven by `.github/renovate.json`.
Three of its update kinds push commits that are incomplete for this repository.
A `custom.regex` bump of a `flake.nix` ref leaves `flake.lock` locking the old ref; a `bun` update rewrites `bun.lock` and leaves `bun.nix`, its nix projection, stale; and the cross-manager Playwright group co-schedules the npm and flake bumps without making the npm pins equal the flake driver that `pkgs/by-name/vanixiets-docs/package.nix:334-350` checks.
`.github/workflows/regenerate-lock-files.yaml` repairs the first two on GitHub Actions after the fact, as `github-actions[bot]`, which `.github/renovate.json::gitIgnoredAuthors` exists to tolerate; nixbot has by then evaluated and failed the first push.

Renovate can make these commits complete itself through `postUpgradeTasks`, but only an instance whose global `allowedCommands` admits the commands runs them; the hosted app sets none for this repository.
nixpkgs ships `services.renovate` (M) and a NixOS test (T, `nixos/tests/all-tests.nix:1616`); M and T are byte-identical at the local flake.lock pin `6dadaf4375be` and at magnetite's running revision `82566dfe91ca`, and both ship Renovate 44.236.2 (R).
Magnetite already runs the forge, nixbot, gitea-mq and the binary cache, and composes services through the repository's deferred-module pattern: aspects in `flake.modules.nixos.<name>`, named in `modules/machines/nixos/magnetite/default.nix`, deployed by `clan machines update magnetite`.

The design source is a design session of 2026-11-16, whose module, source and probe evidence is summarized in brainstorm.md; the operator then settled its open questions.
Stakeholders: the operator, who creates the App, populates its key, disables the Mend app and decides when Renovate pull requests are enqueued; nixbot, which evaluates every pushed Renovate commit; gitea-mq, which lands them once enqueued.

## Goals / Non-Goals

**Goals:**

- Renovate runs on magnetite from the nixpkgs module under a dedicated, vanixiets-only GitHub App with a per-run one-hour token, and the App's private key never enters the sandbox where repository code runs.
- Every commit Renovate pushes is self-consistent: `flake.lock` locks `flake.nix`, `bun.nix` matches `bun.lock`, and npm Playwright equals the flake driver, so nixbot is green on the first push with no follow-up commit.
- The repository's task commands and the instance's allowlist cannot drift apart unnoticed.
- One updater at a time; the hosted app's state is closed, not adopted.
- `regenerate-lock-files.yaml` and `gitIgnoredAuthors` are deleted.

**Non-Goals:**

- `.github/workflows/update-flake-inputs.yaml`, which stays on GitHub Actions until a separate change decides it.
- Auto-enqueueing Renovate pull requests into gitea-mq; enqueueing remains an operator act.
- Any change to nixbot, gitea-mq, buildbot, their Apps or the default-branch rulesets.
- A second repository, webhook-driven runs, Merge Confidence API rules.

## Decisions

### D1: Self-host with the nixpkgs `services.renovate` module on magnetite

- **Choice**: enable `services.renovate` in a new first-party aspect `flake.modules.nixos.renovate` at `modules/nixos/renovate.nix`, named in magnetite's aspect list after `gitea-mq`.
- **Rationale**: the module provides a `DynamicUser` unit with a full hardening set (M:138-168), a timer from `schedule` (M:129), `runtimePackages`, `credentials`, and build-time validation of the global settings (M:17-37, 91-95), and is tested upstream by T.
- **Alternatives considered**: the Mend-hosted app, which cannot run `postUpgradeTasks`; `renovatebot/github-action`, which spends GitHub Actions minutes and depends on private-repository minutes once the repository goes private; a nixbot scheduled effect, which would put a long network-bound job on the build service's scheduler; a custom module, which duplicates a maintained and tested one.
- **Boundary**: vendored-versus-first-party. M is consumed from nixpkgs and never edited; site configuration, the token minting and the assertions live only in the aspect. A nixpkgs bump that changes M changes the unit, which is why the aspect's assumptions about M (the `script` composition, `RuntimeDirectory` availability) are proved against the rendered unit (task 4.4), not the source.

### D2: Dedicated GitHub App with a per-run installation token minted outside the sandbox

- **Choice**: App `vanixiets-renovate`, owner the personal account, "Only on this account", installed on vanixiets only, webhook off. `ExecStartPre = [ "+…" ]` runs `gh-token generate --key <pem> --app-id … --installation-id …` as root, writes `.token` into `/run/renovate/token` (`RuntimeDirectory=renovate`, mode 0700) owned by the dynamic user; a `lib.mkBefore` prefix on M's `script` reads it into `RENOVATE_TOKEN`, exports it, and deletes the file before M's `exec renovate`. App id and installation id are non-secret constants in the aspect. Leave `gitAuthor`, `username` and `platformCommit` unset.
- **Rationale**: an installation token (`ghs_…`) is repository-scoped and expires after an hour; Renovate normalizes it and sets `isGHApp` (R `platform/github/index.ts:232-233`), discovers its author as `<name> <<id>+<slug>[bot]@users.noreply.github.com>` (R index.ts:261-294), and `platformCommit: auto` (R `lib/config/options/index.ts:3874`) resolves to `enabled` for App tokens (R `platform/github/scm.ts:17-20`), so commits go through the REST API and GitHub signs them. `script` is `types.lines` (`nixos/lib/systemd-unit-options.nix:419-423`), so the prefix lands ahead of M's lines.
- **Alternatives considered**: a bot user with a fine-grained PAT — a second GitHub user, a long-lived account-wide credential, no `platformCommit`, unsigned commits without a managed `gitPrivateKey`. The module's `credentials` option carrying the PEM — `LoadCredential` is read at unit start before any `ExecStartPre` (M:54-64,141,172-177) and would expose the PEM to every task child, which runs repository code under Renovate's uid. `credentials` carrying a token minted by a separate unit — a second unit and a token file that outlives the run.
- **Permissions (operator Q16)**: Contents rw, Pull requests rw, Issues rw, Workflows rw (`helpers:pinGitHubActionDigests` edits `.github/workflows/*`), Commit statuses rw, Checks rw, Administration r, Dependabot alerts r, Metadata r; Merge queues omitted because landing is gitea-mq and no ruleset has a native merge queue. Trim after Phase 1 by reading which calls the debug journal shows.
- **Identity interactions**: the App is not a bypass actor on either ruleset; it pushes only `renovate/*` branches, which no ruleset targets. nixbot trusts pull requests whose head branch lives in the base repository regardless of author (`modules/nixos/nixbot.nix:170-185`), so the new bot's pull requests build without approval; effects already handle bots that report no permission (`modules/effects/vanixiets/effects.nix:4-11,31-35`). Nothing in the flake keys on the login `renovate[bot]` except test fixture data (`modules/checks/deploy-docs-rehearsal.nix:875`).
- **Not yet proven**: that the `+` pre-start and the `mkBefore` prefix compose in the rendered unit; task 4.4 renders and reads it.

### D3: The App key is a manual clan vars generator

- **Choice**: `clan.core.vars.generators.renovate-github-app-secret-key` with file `key.pem` at the default owner `root`, whose script exits non-zero with a "populate via clan vars set" message, after `modules/nixos/gitea-mq.nix:48-53`. No `restartUnits`, because each timer run reads the key afresh and a running run must not be killed by a rotation.
- **Rationale**: the fleet's one answer for service secrets; the value never reaches the repository or the store.
- **Boundary**: source-versus-delivered. The generator declaration is source; the decrypted file exists only on magnetite at activation, which is what the minting step reads.

### D4: Global settings in the module, repository behaviour in `.github/renovate.json`

- **Choice**: `services.renovate.settings`: `platform = "github"`, `repositories = [ "cameronraysmith/vanixiets" ]`, `autodiscover = false`, `onboarding = false`, `requireConfig = "required"`, `binarySource = "global"`, `repositoryCache = "enabled"`, `prCommitsPerRunLimit = 4`, `allowedCommands` (D6). `allowScripts`, `allowShellExecutorForPostUpgradeCommands` and `exposeAllEnv` stay at their false defaults, so Renovate's own `bun install` passes `--ignore-scripts` (R `manager/bun/artifacts.ts:56-59`) and tasks run without a shell. Repository rules stay in `.github/renovate.json`, which `checks.renovate-config` already validates with `--strict`.
- **Rationale**: settings are serialized into the store (M:96-110), so they hold nothing secret; M's `validateSettings` validates them as global config at build time (R `lib/config-validator.ts:142,168-192`). Keeping rules in the repository keeps them reviewable with the code they govern.
- **Schedule (operator Q14)**: `schedule = "*-*-* 00/2:17:00"` and `systemd.timers.renovate.timerConfig.RandomizedDelaySec = "10min"`. Because the unit stays active through a run, a timer firing mid-run starts no second instance.

### D5: Post-upgrade tasks per manager, and the Playwright derivation (operator D7)

- **Choice**: after the existing rules in `.github/renovate.json` (later rules win), add:
  - `matchManagers: ["custom.regex"]` → `postUpgradeTasks { commands: ["nix flake lock"], fileFilters: ["flake.lock"], executionMode: "branch" }`;
  - `matchManagers: ["bun"]` → `{ commands: ["nix run .#regenerate-bun-nix"], fileFilters: ["bun.nix"], executionMode: "branch" }`;
  - Playwright (operator D7): `matchManagers: ["bun"], matchPackageNames: ["playwright", "@playwright/test"], enabled: false`;
  - Playwright (operator D7): `matchManagers: ["custom.regex"], matchPackageNames: ["cameronraysmith/playwright-web-flake", "pietdevries94/playwright-web-flake"], groupName: "playwright"` → `{ commands: ["nix flake lock", "just bun-repin-playwright", "bun install --ignore-scripts", "nix run .#regenerate-bun-nix"], fileFilters: ["flake.lock", "packages/docs/package.json", "bun.lock", "bun.nix"], executionMode: "branch" }`, placed after the generic `custom.regex` rule.
  The current "Group playwright across npm and flake.nix" and "Pin playwright npm packages" rules are deleted; "Disable nix manager for playwright-web-flake" stays.
- **Rationale**: tasks run after the managers' own artifact updates and before commit (R `update/branch/index.ts:400,467,548`) in the clone root (R `execute-post-upgrade-commands.ts:155-175`). `fileFilters` choose which changed files enter the commit, not which updates trigger a task; `matchManagers` does the triggering. `postUpgradeTasks` is not mergeable (R `config/utils.ts:30-45`), so a later rule's object replaces an earlier one's and each rule spells out all three fields; that is why the Playwright rule must follow the generic regex rule. `executionMode: "branch"` runs once per branch (R :395-410), which suits groups such as `bun workspace non-major`. `just bun-repin-playwright` (`justfile:595`) evaluates the driver version through `nix eval --inputs-from .`, so it must follow the re-lock. Renovate splits commands without a shell (R `lib/util/exec/common.ts:119-131`); the probe confirmed `nix run .#regenerate-bun-nix` keeps its `#`.
- **Alternatives considered**: keep the cross-manager Playwright group (co-schedules the bumps without making them agree; #3856 is the live failure); keep the repair workflow (two evaluations and a red check per update, and a foreign-author commit on every Renovate branch).
- **Constraint recorded for later rules**: never group bun-manager and `custom.regex` updates into one branch unless that rule's task object is the union of both chains.

### D6: Allowlist in the module, tied to the repository by a flake check (operator Q18, risk R7)

- **Choice**: `allowedCommands = [ "^nix flake lock$" "^nix run \\.#regenerate-bun-nix$" "^just bun-repin-playwright$" "^bun install --ignore-scripts$" ]`, all anchored, kept as static flake data `flake.lib.renovateSettings.allowedCommands` in `modules/lib/renovate-settings.nix`, which also holds the Phase 1 global `packageRules` while they exist; the aspect passes both to `services.renovate.settings`. A new flake check `checks.<system>.renovate-allowed-commands` beside `modules/checks/renovate.nix` reads `.github/renovate.json` with `builtins.fromJSON` and the patterns and global rules from `flake.lib.renovateSettings`, collects every `postUpgradeTasks.commands` entry, and fails if any command matches no pattern or if the collected command set is empty. It evaluates no host configuration, so it adds no NixOS evaluation to the build service's runs. It lands in the same commit as the first task commands (task 5.1), so it is green from its first evaluation. Matching uses `jq`'s `test`, an Oniguruma engine, against the same anchored patterns Renovate tests with JavaScript regexes; the four patterns use only anchors, literals and an escaped dot, on which the two engines agree.
- **Rationale**: a disallowed or failing command becomes an `artifactErrors` entry (R `execute-post-upgrade-commands.ts:222-229`) and the branch is still committed and pushed with a "lock file problem" comment (R `update/branch/index.ts:480-500`), so the failure arrives as exactly the incomplete commit this change exists to remove. The module and the check read the one definition in `flake.lib.renovateSettings`, so the check tests the value the instance runs with, without paying for a NixOS evaluation of magnetite on every build-service run. The emptiness guard keeps the check from passing vacuously if the rules are deleted.
- **Boundary**: source-versus-delivered. The check proves source agreement at evaluation; the deployed unit's settings file is the delivered form, checked on the host in task 8.2.

### D7: Tool versions on the unit's path (operator Q17)

- **Choice**: `runtimePackages = [ config.nix.package bun just jq bash ]`, where `bun` is the repository's toolchain bun — the derivation the default dev shell carries (`modules/devshells/default.nix:167`) — taken through flake-parts `withSystem` for magnetite's system, as `modules/containers/default.nix:148` does for packages. An assertion in the aspect fails evaluation unless `bun.version` equals the version in `package.json::packageManager` (`bun@1.4.4`). `config.nix.package` matches the 2.35.6 daemon. The nix manager shells out to `nix flake update` with `--extra-access-tokens` (R `manager/nix/artifacts.ts:36-53`), so `nix` is required on the path.
- **Rationale**: Renovate passes only `PATH` and `HOME` to children (R `lib/util/exec/env.ts:5-30`), so every task tool must come through `runtimePackages`; a bun other than the repository's could reformat `bun.lock`.
- **Boundary**: vendored-versus-first-party. `pkgs.bun` comes from nixpkgs; the assertion is the first-party guard that the vendored version matches the repository's declared toolchain.

### D8: Load controls

- **Choice**: `prCommitsPerRunLimit = 4` (global-only, R options:1454), `prHourlyLimit` and `prConcurrentLimit` at their defaults (2 and 10), `rebaseWhen` at `auto`, which resolves to `conflicted` because the rulesets' required checks are non-strict; unit `Nice=10`, `CPUWeight=20`, `IOWeight=20`, `MemoryHigh=4G`, `MemoryMax=8G`, `RuntimeMaxSec=55min`.
- **Rationale**: each push is a full nixbot evaluation (peak about 31 GiB, `modules/machines/nixos/magnetite/default.nix:824`); Renovate's own nix work never runs `nix-eval-jobs`, so `modules/nixos/nix-eval-lock.nix` does not apply. `RuntimeMaxSec` stops a run before its token expires.
- **Alternatives considered**: wrapping tasks in `flock /etc/nix/eval.lock`, which would widen the allowlist and couple to the lock's owner protocol (`modules/lib/nix-eval-lock.sh`); deferred until load shows a need.

### D9: Staged cutover with a clean slate

- **Choice**: Phase 1 deploys the aspect with `dryRun = "full"`, `branchPrefix = "renovate-selfhost/"`, `branchPrefixOld = "renovate-selfhost/"`, `LOG_LEVEL=trace`, and the D5 rules as global `packageRules`; the hosted app keeps running and sees no change, because global rules are concatenated before the repository's (R options:1747-1758) and the repository file is untouched. The operator then disables the Mend app for vanixiets; the open `renovate[bot]` pull requests are closed with a pointer comment and their branches deleted; Dependency Dashboard #832 is closed. Phase 2 is one pull request: D5 rules in `.github/renovate.json`, `gitIgnoredAuthors` deleted, the two old Playwright rules deleted, `.github/workflows/regenerate-lock-files.yaml` deleted, and the aspect's `dryRun`, `branchPrefix`, `branchPrefixOld`, global `packageRules` and `LOG_LEVEL` removed. It lands through nixbot and gitea-mq; then magnetite is deployed and a run started by hand.
- **Rationale**: `dryRun: "full"` still runs artifact updates and tasks and logs only commits, pushes and forge writes (R `update/branch/index.ts:400,467`; `commit.ts:65-80`), which is the evidence wanted before anything is pushed. A branch under a new prefix is new only if the old-prefix lookup is off as well: the existing `renovate/*` branches, authored by `renovate[bot]`, count as modified by a foreign author and are skipped (R `util/git/index.ts` isBranchModified), and Renovate looks them up by `branchPrefixOld`, not only by `branchPrefix`. The new instance only finds dashboard issues it created (R `platform/github/graphql.ts:27,90`; index.ts:1416-1428), so #832 would otherwise linger beside the new one. Disabling the hosted app and closing its branches before Phase 2 lands keeps the hosted app from meeting tasks it cannot run and the new instance from meeting foreign-authored branches.
- **Correction, 2026-11-17**: the original choice set only `branchPrefix`, on the assumption that a temporary prefix makes every branch new. That was wrong: `branchPrefixOld` defaults to `renovate/` (R `lib/config/options/index.ts:2248-2254`), and when a branch under `branchPrefix` does not exist Renovate adopts the same-named branch under `branchPrefixOld` (R `lib/workers/repository/update/branch/index.ts:88-97`; for pull requests `check-existing.ts:30`). The first Phase 1 run (2026-11-17 06:54Z) therefore found the hosted app's five `renovate/*` branches, judged them edited and skipped all of them, so no update task ran. Setting `branchPrefixOld` equal to `branchPrefix` disables the lookup, since both sites guard it with `branchPrefix !== branchPrefixOld`.
- **Trace logging in Phase 1**: `LOG_LEVEL=trace` logs each HTTP request (R `lib/util/http/http.ts:232`, `got.ts:37`), which the permission trim (task 5.4, operator Q16) needs; debug logged only three GitHub API URLs, through the HTTP cache. Trace does not log credentials: the logger masks the value of any `authorization` or `token` field (R `lib/util/sanitize.ts:7-23`, applied by `lib/logger/utils.ts::sanitizeValue`) and replaces the platform token's value anywhere in a message, because platform initialisation registers it as a host rule (R `lib/modules/platform/index.ts:74-94`), host rules register their token for sanitizing (R `lib/util/host-rules.ts:268-281`), the per-repository reset re-adds them (R `lib/workers/global/index.ts:225-232`), and an App token is registered with and without its `x-access-token:` prefix (R `lib/util/sanitize.ts:47-64`). The App key never reaches Renovate's process. The journal is still scanned for token and key patterns before any excerpt is kept.
- **Alternatives considered**: adopting the old pull requests with `ignorePrAuthor: true` and a transitional `gitIgnoredAuthors` for `renovate[bot]`, which keeps foreign-authored commits the new bot would rewrite and stale dashboard state, to save a few hours of re-creation at `prHourlyLimit` 2.

## Risks / Trade-offs

- [Risk] A run longer than the token's hour fails mid-run → Mitigation: `RuntimeMaxSec=55min`, `prCommitsPerRunLimit = 4`, a fresh token every run.
- [Risk] R7: a task that is disallowed or fails still produces a pushed, incomplete commit → Mitigation: D6's flake check for allowlist drift; a task that fails for other reasons leaves nixbot red as today, now with Renovate's "lock file problem" comment on the pull request.
- [Risk] Tasks run repository-controlled code (a justfile recipe, a flake app) as Renovate's uid, and the token in Renovate's environment is readable by same-uid children through `/proc/<pid>/environ` → Mitigation: the exposure is a ≤1 h, vanixiets-only token; the PEM is unreachable; only `renovate/*` branches built from the default branch are processed, never fork pull requests; npm lifecycle scripts never run.
- [Risk] Tool drift: a nixpkgs bun differing from `packageManager` → Mitigation: D7's assertion fails evaluation; nix comes from `config.nix.package`.
- [Risk] Daemon policy: narrowing magnetite's `allowed-users` from `*` would lock the dynamic user out → Mitigation: recorded as a world assumption with its violation condition; the dynamic user must then be admitted.
- [Risk] The `+` pre-start and `mkBefore` composition, unproven → Mitigation: task 4.4 renders the unit and reads `ExecStartPre` and the script before deploy; Phase 1's journal shows the token minted.
- [Trade-off] No webhooks: dashboard checkboxes and rebase requests wait up to about 2 h 10 min → accepted; `systemctl start renovate.service` is the manual nudge.
- [Trade-off] Up to four nixbot evaluations per run → accepted, bounded by D8.
- [Trade-off] Open Renovate pull requests are recreated rather than adopted → accepted for a clean identity and dashboard.

## Migration Plan

1. [wizard] Create the App `vanixiets-renovate` with D2's permissions, webhook off, "Only on this account"; record the App id. Install on vanixiets only; record the installation id. No private key yet.
2. Declare the key generator in a generator-only aspect named in magnetite's aspect list (the service stays disabled), then at once [wizard] generate a private key and, in the operator's terminal, `(set +x; CLAN_NO_COMMIT=1 clan vars set magnetite renovate-github-app-secret-key/key.pem < <downloaded pem>)`, delete the download, and route the ciphertext. These steps run back to back because `clan machines update` runs every missing generator for every machine before deploying, so a tree carrying the declaration without the key cannot deploy any host.
3. Phase 1 pull request (aspect with dry-run settings, host aspect list, allowlist check); land through nixbot and gitea-mq; `clan machines update magnetite`. Magnetite is the only host whose closure changes.
4. Start a run; accept when the journal shows the token minted, every task executed with no "not been added to the allowed list" message, and "DRY-RUN: Would commit files" sets containing `flake.lock` for regex bumps, `bun.nix` for bun branches, and the four-file Playwright set for a pending Playwright bump.
5. [wizard] Disable the Mend app for vanixiets.
6. Close the open `renovate[bot]` pull requests with a pointer comment, delete their `renovate/*` branches, close #832.
7. Phase 2 pull request; land; deploy magnetite; start a run by hand.
8. First live run: recreated pull requests carry "Verified" commits authored by `…+vanixiets-renovate[bot]`, contain `flake.lock` or `bun.nix` as appropriate, and pass nixbot on the first push with no follow-up commit; a new Dependency Dashboard exists.
9. Trim the App's permissions per Q16 from what the Phase 1 debug journal showed.

Rollback: before step 5, removing `renovate` from magnetite's aspect list and redeploying stops the instance with no forge-side effect. After step 5, re-enable the Mend app and revert the Phase 2 pull request, which restores `regenerate-lock-files.yaml` and `gitIgnoredAuthors`; the App can be uninstalled independently.

## Gate 1 modality verdicts

This table is the pre-apply spec-and-feature alignment record.
It carries one row per requirement in this change's three delta specs, with the capability's stratum tag from the proposal and the modality that witnesses the requirement.

No row routes to a Gherkin scenario, so this change lays out no `.feature` file.
The repository has no BDD runner (no pytest-bdd, cucumber or behave dependency, and no `.feature` file in the tree), so a laid-out scenario would be an unbound surface nothing executes.
Every observable this change asserts is either a property of the evaluated NixOS configuration or of `.github/renovate.json`, which `nix eval` and the flake checks witness, or an observation against magnetite, the updater's journal or the forge, which the dry run and the integration verification witness as smoke tests.
Where a scenario has no task that observes it, the row says so rather than naming a witness.

| Requirement | Capability | Stratum | Modality | Witness |
|---|---|---|---|---|
| The dependency updater proposes updates on a fixed schedule | `dependency-update-service` | behavioral | build gate (`nix eval`) and smoke (deployment, forge) | tasks 4.1, 4.5, 5.2, 9.1; the scenario "A run approaches the hour" is witnessed only as the evaluated `RuntimeMaxSec` (4.5): no task observes a run being stopped |
| The updater acts under its own forge identity with expiring credentials | `dependency-update-service` | behavioral | smoke (forge, host), build gate (`nix eval`) and content search | tasks 1.2, 1.4, 2.1, 2.3, 4.2, 4.4, 9.1; the scenario "An update task tries to read the application key" by task 5.5, which reads the key as the unit's dynamic user on magnetite and expects a refusal |
| Every pushed update commit is a consistent commit | `dependency-update-service` | behavioral | build gate (flake checks, negative control), dry run and smoke (forge) | tasks 3.1, 3.2, 4.3, 5.3, 9.1, 9.2 |
| The npm Playwright pin is derived from the Playwright flake input | `dependency-update-service` | behavioral | dry run and smoke (forge) | tasks 5.3, 7.1, 9.3; both observations depend on an upstream Playwright release occurring, and 9.3 records "pending" otherwise |
| Merge authorization stays with people | `dependency-update-service` | behavioral | smoke (forge) | tasks 1.5, 9.5 |
| Exactly one dependency updater writes to the repository | `dependency-update-service` | behavioral | operator procedure and smoke (forge) | tasks 6.1, 6.2, 6.3, 9.4 |
| The fleet's updater is observed in a dry run before it first writes | `dependency-update-service` | behavioral | dry run (journal) | tasks 5.1, 5.3 |
| The updater runs on a fixed schedule within a bounded envelope | `dependency-update-interface` | interface | build gate (`nix eval`), smoke (deployment) and world assumption | tasks 4.1, 4.5, 5.2; the scenario "The timer fires during a run" by world assumption A115, not by a task |
| The application key is read only by a privileged pre-start step | `dependency-update-interface` | interface | build gate (`nix eval`, rendered unit), content search and smoke (host, negative control) | tasks 2.1, 2.3, 4.2, 4.4; the scenario "The sandboxed process looks for the key" by task 5.5 |
| The forge application holds a fixed permission set over this repository alone | `dependency-update-interface` | interface | smoke (forge) | tasks 1.2, 1.4, 1.5, 8.3 |
| Update tasks are attached per dependency kind in the repository's configuration | `dependency-update-interface` | interface | build gate (flake checks) and `jq` order and grouping checks | tasks 7.1 (rule order and the ban on grouping bun and flake-reference updates into one branch), 7.2 |
| Update task commands are admitted by the allowlist, and a check ties the repository's commands to it | `dependency-update-interface` | interface | build gate (flake check, negative controls) | tasks 3.1, 3.2, 4.1 |
| The tools on the updater's path match the repository's declarations | `dependency-update-interface` | interface | build gate (`nix eval`, negative control) | task 4.3 |
| The updater neither labels for the queue nor enables auto-merge | `dependency-update-interface` | interface | smoke (forge) | task 9.5 |
| A full dry run writes nothing to the forge and records each would-be commit | `dependency-update-interface` | interface | dry run (journal and forge) | task 5.3 |
| This capability states its own trust boundary | `dependency-update-interface` | interface | capability text and documentation | specs text, task 7.5 |
| A107 — A GitHub App installation token expires an hour after issue and reaches only the installation's repositories | `world-assumptions` | world | violation-condition witness | its own scenario |
| A108 — Renovate commits through the forge's API under an App identity, and the forge signs those commits | `world-assumptions` | world | violation-condition witness | its own scenario |
| A109 — Renovate runs post-upgrade tasks between its own artifact updates and the commit, runs only allowlisted commands, and still commits when a task fails | `world-assumptions` | world | violation-condition witness | its own scenario |
| A110 — Renovate replaces rather than merges a rule's post-upgrade tasks, and applies global rules before the repository's | `world-assumptions` | world | violation-condition witness | its own scenario |
| A111 — Renovate runs a task command without a shell and passes it only PATH and HOME | `world-assumptions` | world | violation-condition witness | its own scenario |
| A112 — Renovate leaves a branch another author wrote, and recognizes only dashboard issues it created | `world-assumptions` | world | violation-condition witness | its own scenario |
| A113 — A full dry run performs artifact updates and tasks and writes nothing to the forge | `world-assumptions` | world | violation-condition witness | its own scenario |
| A114 — magnetite's nix daemon serves every local account and trusts only root and wheel | `world-assumptions` | world | violation-condition witness | its own scenario |
| A115 — systemd does not start an already-active service when its timer elapses | `world-assumptions` | world | violation-condition witness | its own scenario |
| Grounded vocabulary for behavioral requirements | `world-assumptions` | world | designation table and its lint | the table itself |

No row carries an `est-property`, `est-contract`, or `est-symbolic` modality, so this change carries no executable-specification-testing obligation.

## Open Questions

- None blocking. The App permission trim (Q16) is decided as "after Phase 1" and is task 8.3; whether `flock` serialization with nixbot evaluation is ever needed is left to observed load (D8).
