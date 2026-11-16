# Self-hosted Renovate on magnetite implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

<!--
Procedural note: the interactive `superpowers:writing-plans` handoff was not run; this plan was
written by the session that wrote tasks.md, following that skill's structure, and stops for
operator review before any apply. It decomposes tasks.md group by group with the same numbering:
tasks.md task 4.2 is Task 4 Step 2 here where the mapping is one to one.
-->

**Goal:** Run Renovate on magnetite from the nixpkgs `services.renovate` module under a dedicated GitHub App, with post-upgrade tasks that make every pushed commit self-consistent, and cut over from the Mend-hosted app in two phases.

**Architecture:** A first-party aspect `flake.modules.nixos.renovate` at `modules/nixos/renovate.nix` enables the vendored module, declares the App key generator, mints a per-run installation token in a privileged `ExecStartPre`, puts the repository's toolchain on the unit's path with a version assertion, and bounds the unit's load. `.github/renovate.json` attaches task chains per manager. A flake check ties the repository's task commands to the module's `allowedCommands`.

**Tech Stack:** nix flakes with flake-parts and import-tree; clan-core vars and deployment; nixpkgs `services.renovate` with Renovate 44.236.2; `gh-token`; `jq`; `gh` for forge reads.

**Spec:** `openspec/changes/stand-up-renovate-on-magnetite/` — `design.md` (D1–D9), `specs/dependency-update-service`, `specs/dependency-update-interface`, `specs/world-assumptions` (A107–A114).

## Global Constraints

- Schedule `*-*-* 00/2:17:00`, `RandomizedDelaySec = "10min"` (operator Q14).
- Renovate pull requests are never auto-enqueued: no `automerge`, no `merge-queue` label (operator Q15).
- App `vanixiets-renovate`, installed on `cameronraysmith/vanixiets` only, not a ruleset bypass actor; permission trim only after Phase 1 (operator Q16).
- Task bun is the repository's toolchain bun with an assertion equal to `package.json::packageManager` (`bun@1.4.4`) (operator Q17).
- `allowedCommands` exactly `^nix flake lock$`, `^nix run \.#regenerate-bun-nix$`, `^just bun-repin-playwright$`, `^bun install --ignore-scripts$`; the flake check fails on any unmatched command or an empty command set (operator Q18).
- `.github/workflows/update-flake-inputs.yaml` is not touched (operator Q19).
- Nothing under `modules/nixos/nixbot.nix`, `modules/nixos/gitea-mq.nix`, `modules/nixos/buildbot.nix`, their Apps or the rulesets is edited.
- nix-managed outputs are verified by `nix eval`/instantiation against `.#nixosConfigurations.magnetite` and `.#checks.x86_64-linux.*`, or on the host after activation; never by reading source.
- Long or output-heavy commands: `<command> 2>&1 | tee logs/<identifier>-$(date +%Y%m%d-%H%M%S).log`.
- jj-colocated repository in a development join: route content to the owning chain with `jj squash --into`; never `jj describe @`; the orchestrator commits and opens pull requests.
- Operator-only steps (App creation, key, installation, `clan vars set`, disabling Mend, permission trim) are presented through the `wizard` skill and stopped on.

## Grounding: the consumer's exact argument lists

The vendored consumer is Renovate 44.236.2. A pre-deploy probe of any task must run the argv Renovate itself runs, not one chosen by hand:

- Task commands are split without a shell by the bundled `shlex@3.0.0` (R `lib/util/exec/common.ts:119-131`): `nix flake lock` → `["nix","flake","lock"]`; `nix run .#regenerate-bun-nix` → `["nix","run",".#regenerate-bun-nix"]`; `just bun-repin-playwright` → `["just","bun-repin-playwright"]`; `bun install --ignore-scripts` → `["bun","install","--ignore-scripts"]`. Run in the clone root, environment `PATH` and `HOME` only (R `lib/util/exec/env.ts:5-30`).
- The nix manager runs `nix flake update <inputs…> --extra-access-tokens github.com=<token>` (R `lib/modules/manager/nix/artifacts.ts:36-53`).
- The bun manager runs `bun install` with `--ignore-scripts` while `allowScripts` is false (R `lib/modules/manager/bun/artifacts.ts:56-59`).
- The 2026-11-16 probe (`logs/renovate-probe-20261116-133754.log`) ran `nix flake lock`, `nix flake update playwright-web-flake`, `nix run .#regenerate-bun-nix` and `bun install --ignore-scripts --frozen-lockfile` under M's hardening; it did not run `just bun-repin-playwright` or a plain `bun install --ignore-scripts`. Phase 1 (Task 5) is where those two run with Renovate's own argv.

---

### Task 1: Forge application (operator gate)

**Files:** none in the repository.

**Interfaces:**
- Produces: App id and installation id (non-secret integers) consumed by Task 4 Step 2; the downloaded PEM consumed by Task 2 Step 2.

- [ ] **Step 1 [operator, wizard]:** present the App creation form at `https://github.com/settings/apps/new`: name `vanixiets-renovate`; homepage `https://github.com/cameronraysmith/vanixiets`; webhook "Active" unchecked; repository permissions Contents RW, Pull requests RW, Issues RW, Workflows RW, Commit statuses RW, Checks RW, Administration R, Dependabot alerts R, Metadata R; no Merge queues; "Only on this account". Stop until the operator reports the App id.
- [ ] **Step 2:** confirm the registration.

```bash
gh api /apps/vanixiets-renovate --jq '{id, owner: .owner.login, permissions}' 2>&1 | tee logs/renovate-app-$(date +%Y%m%d-%H%M%S).log
```
Expected: the reported id, owner `cameronraysmith`, permissions exactly `{administration: read, checks: write, contents: write, issues: write, metadata: read, pull_requests: write, statuses: write, vulnerability_alerts: read, workflows: write}`.

- [ ] **Step 3 [operator, wizard]:** "Generate a private key" (downloads the PEM); "Install App" → `cameronraysmith` → "Only select repositories" → `vanixiets`. Stop until the operator reports the installation id from the URL `…/settings/installations/<id>`.
- [ ] **Step 4:** record complete installation scope. With a short-lived App JWT generated by the operator, or from the operator's installation page, record that the App has one installation and its repository list, paginated to the end, is exactly `cameronraysmith/vanixiets`.
- [ ] **Step 5:** confirm the rulesets are unchanged.

```bash
for id in $(gh api /repos/cameronraysmith/vanixiets/rulesets --jq '.[].id'); do
  gh api /repos/cameronraysmith/vanixiets/rulesets/$id --jq '{name, bypass_actors}'
done 2>&1 | tee logs/renovate-rulesets-$(date +%Y%m%d-%H%M%S).log
```
Expected: bypass actors repository-role 5 and App `4875422` only.

### Task 2: Credentials

**Files:**
- Create: `modules/nixos/renovate.nix` (generator only in this task; extended in Task 4)

**Interfaces:**
- Produces: `config.clan.core.vars.generators.renovate-github-app-secret-key.files."key.pem".path`, consumed by Task 4 Step 2.

- [ ] **Step 1:** write the aspect skeleton with the generator.

```nix
# Self-hosted Renovate for cameronraysmith/vanixiets on magnetite (nixpkgs services.renovate).
#
# Credential generator catalog:
#   - renovate-github-app-secret-key/key.pem: manual `clan vars set` (GitHub App PEM)
{ withSystem, ... }:
{
  flake.modules.nixos.renovate =
    { config, lib, pkgs, ... }:
    {
      clan.core.vars.generators.renovate-github-app-secret-key = {
        files."key.pem" = { };
        script = ''
          echo "renovate GitHub App private key: populate via clan vars set" >&2
          exit 1
        '';
      };
    };
}
```

- [ ] **Step 2 [operator, wizard]:** populate the key and shred the download.

```bash
(set +x; CLAN_NO_COMMIT=1 clan vars set magnetite renovate-github-app-secret-key/key.pem < ~/Downloads/vanixiets-renovate.*.private-key.pem)
```
Expected: `vars/per-machine/magnetite/renovate-github-app-secret-key/key.pem/secret` exists as a sops envelope; the orchestrator routes it to the chain.

- [ ] **Step 3:** verify the generator once the aspect is in the host's list (Task 4 Step 7).

```bash
nix eval .#nixosConfigurations.magnetite.config.clan.core.vars.generators.renovate-github-app-secret-key.files.\"key.pem\" \
  --apply 'f: { inherit (f) owner restartUnits; }' --json
```
Expected: `{"owner":"root","restartUnits":[]}`.

- [ ] **Step 4:** count-only, positive-controlled leak search for an interior PEM line across the working tree including ignored paths, the tracked tree, and `git log --all -S`; control string `vanixiets-renovate` must be non-zero in each layer. Record counts only.

### Task 3: Allowlist check

**Files:**
- Create: `modules/checks/renovate-allowed-commands.nix`

**Interfaces:**
- Consumes: `config.flake.nixosConfigurations.magnetite.config.services.renovate.settings.{allowedCommands,packageRules}`; `.github/renovate.json`.
- Produces: `checks.x86_64-linux.renovate-allowed-commands`.

- [ ] **Step 1:** write the check. It is defined for `x86_64-linux` only because reading magnetite's evaluated configuration is the cost `checks.x86_64-linux.nixos-magnetite` already pays.

```nix
# Every postUpgradeTasks command the repository (or, in Phase 1, the module's
# global packageRules) asks Renovate to run must match one of the module's
# allowedCommands. Renovate turns a refused command into an artifact error and
# still pushes the branch (execute-post-upgrade-commands.ts:222-229;
# update/branch/index.ts:480-500), so drift here would ship incomplete commits.
# An empty command set fails too, so the check cannot pass vacuously.
# Matching uses jq's Oniguruma `test`; the patterns use only anchors, literals
# and an escaped dot, on which Oniguruma and JavaScript regexes agree.
{ config, lib, ... }:
{
  perSystem =
    { system, pkgs, ... }:
    lib.mkIf (system == "x86_64-linux") {
      checks.renovate-allowed-commands =
        let
          settings = config.flake.nixosConfigurations.magnetite.config.services.renovate.settings;
          input = pkgs.writeText "renovate-allowed-commands-input.json" (
            builtins.toJSON {
              allowed = settings.allowedCommands or [ ];
              globalRules = settings.packageRules or [ ];
            }
          );
        in
        pkgs.runCommand "renovate-allowed-commands"
          {
            nativeBuildInputs = [ pkgs.jq ];
            passthru.meta.description = "Every Renovate postUpgradeTasks command matches the module's allowedCommands";
          }
          ''
            jq -n -r \
              --slurpfile repo ${../../.github/renovate.json} \
              --slurpfile mod ${input} '
              ($mod[0].allowed) as $allowed
              | [ (($repo[0].packageRules // []) + $mod[0].globalRules)[]
                  | .postUpgradeTasks.commands // [] | .[] ] as $cmds
              | if ($cmds | length) == 0 then
                  "renovate-allowed-commands: no postUpgradeTasks command found; the check would be vacuous" | halt_error(1)
                else
                  [ $cmds[] | select(. as $c | any($allowed[]; . as $re | $c | test($re)) | not) ]
                  | if length > 0 then
                      ("renovate-allowed-commands: not admitted by allowedCommands: " + join(", ")) | halt_error(1)
                    else "OK: \($cmds | unique | length) distinct task commands admitted" end
                end'
            touch $out
          '';
    };
}
```

- [ ] **Step 2:** build it after Task 5 Step 1 adds the global rules (before that, it fails on the empty set, which is the intended behaviour).

```bash
nix build .#checks.x86_64-linux.renovate-allowed-commands -L 2>&1 | tee logs/renovate-allowed-commands-$(date +%Y%m%d-%H%M%S).log
```
Expected: `OK: 4 distinct task commands admitted`.

- [ ] **Step 3:** mutants, in a scratch copy: append `"nix flake update"` to one rule's commands → build fails naming `nix flake update`; remove every `postUpgradeTasks` → build fails with the vacuity message. Keep both logs; revert the scratch.

### Task 4: First-party aspect

**Files:**
- Modify: `modules/nixos/renovate.nix`
- Modify: `modules/machines/nixos/magnetite/default.nix` (aspect list, after `gitea-mq`)

**Interfaces:**
- Consumes: App id and installation id (Task 1), key path (Task 2), `withSystem`.
- Produces: `systemd.services.renovate`, `systemd.timers.renovate`, `services.renovate.settings.allowedCommands` (consumed by Task 3).

The snippets below are fragments of the one aspect body begun in Task 2: merge every `let` binding into a single `let … in` around the module's attribute set, and merge the `services.renovate` and `systemd.services.renovate` fragments into one set each, because Nix rejects two `x = { … };` bindings of the same attribute in one set literal.

- [ ] **Step 1:** service settings (design D4, D6, operator Q14). Inside the aspect's attribute set:

```nix
      services.renovate = {
        enable = true;
        schedule = "*-*-* 00/2:17:00";
        settings = {
          platform = "github";
          repositories = [ "cameronraysmith/vanixiets" ];
          autodiscover = false;
          onboarding = false;
          requireConfig = "required";
          binarySource = "global";
          repositoryCache = "enabled";
          prCommitsPerRunLimit = 4;
          allowedCommands = [
            "^nix flake lock$"
            "^nix run \\.#regenerate-bun-nix$"
            "^just bun-repin-playwright$"
            "^bun install --ignore-scripts$"
          ];
        };
      };
```
Verify: `nix eval .#nixosConfigurations.magnetite.config.services.renovate.settings --json | jq .` shows exactly these keys.

- [ ] **Step 2:** token minting (design D2). Add a `let` binding and unit settings:

```nix
    let
      gen = config.clan.core.vars.generators;
      appId = <App id from Task 1 Step 1>;
      installationId = <installation id from Task 1 Step 3>;
      mintToken = pkgs.writeShellApplication {
        name = "renovate-mint-token";
        runtimeInputs = [ pkgs.gh-token pkgs.jq pkgs.coreutils ];
        text = ''
          umask 077
          gh-token generate \
            --key ${gen.renovate-github-app-secret-key.files."key.pem".path} \
            --app-id ${toString appId} --installation-id ${toString installationId} \
            | jq -jer .token > /run/renovate/token
          chown --reference=/run/renovate /run/renovate/token
        '';
      };
    in
```
```nix
      systemd.services.renovate = {
        script = lib.mkBefore ''
          RENOVATE_TOKEN="$(< /run/renovate/token)"
          export RENOVATE_TOKEN
          rm -f /run/renovate/token
        '';
        serviceConfig = {
          ExecStartPre = [ "+${lib.getExe mintToken}" ];
          RuntimeDirectory = "renovate";
          RuntimeDirectoryMode = "0700";
        };
      };
```
The two ids are the operator's reported integers, not secrets. Verify: `nix eval .#nixosConfigurations.magnetite.config.systemd.services.renovate.serviceConfig --apply 's: { inherit (s) ExecStartPre RuntimeDirectory RuntimeDirectoryMode; }' --json` and `nix eval .#nixosConfigurations.magnetite.config.services.renovate.credentials --json` → `{}`.

- [ ] **Step 3:** tool path and bun assertion (design D7, operator Q17).

```nix
    let
      repoBun = withSystem pkgs.stdenv.hostPlatform.system ({ pkgs, ... }: pkgs.bun);
      packageManagerBun = lib.removePrefix "bun@" (lib.importJSON ../../package.json).packageManager;
    in
```
```nix
      services.renovate.runtimePackages = [
        config.nix.package
        repoBun
        pkgs.just
        pkgs.jq
        pkgs.bash
      ];
      assertions = [
        {
          assertion = repoBun.version == packageManagerBun;
          message = "renovate: task bun ${repoBun.version} differs from package.json packageManager bun@${packageManagerBun}; a different bun can rewrite bun.lock";
        }
      ];
```
`repoBun` is the perSystem `pkgs.bun` the default dev shell carries (`modules/devshells/default.nix:167`). Verify: `nix eval .#nixosConfigurations.magnetite.config.systemd.services.renovate.path --apply 'map (p: p.name)' --json`; mutant in a scratch copy with `"packageManager": "bun@0.0.0"` → `nix eval .#checks.x86_64-linux.nixos-magnetite.drvPath` fails with the assertion message.

- [ ] **Step 4:** prove the pre-start and script compose.

```bash
nix eval --raw .#nixosConfigurations.magnetite.config.systemd.units.\"renovate.service\".text 2>&1 | tee logs/renovate-unit-$(date +%Y%m%d-%H%M%S).log
```
Expected: one `ExecStartPre=+/nix/store/…-renovate-mint-token/bin/renovate-mint-token`; no `LoadCredential`; `ExecStart` pointing at a script; then read that script path (`nix build` of it on magnetite, or `--eval-store` from the laptop) and confirm the three `RENOVATE_TOKEN` lines precede `exec renovate`.

- [ ] **Step 5:** load controls (design D8).

```nix
      systemd.services.renovate.serviceConfig = {
        RuntimeMaxSec = "55min";
        Nice = 10;
        CPUWeight = 20;
        IOWeight = 20;
        MemoryHigh = "4G";
        MemoryMax = "8G";
      };
      systemd.timers.renovate.timerConfig.RandomizedDelaySec = "10min";
```
Verify with `nix eval` of both attribute sets.

- [ ] **Step 6:** extend the file header: the generator; why the PEM never enters the sandbox (task children run repository code under Renovate's uid; `LoadCredential` is read before `ExecStartPre`); no `restartUnits` because each run reads the key; token life one hour versus `RuntimeMaxSec=55min`; the coupling to `checks.renovate-allowed-commands`. Verify: `direnv exec . prek run --files modules/nixos/renovate.nix`.
- [ ] **Step 7:** name `renovate` after `gitea-mq` in `modules/machines/nixos/magnetite/default.nix`'s aspect list. Verify: `nix eval .#nixosConfigurations.magnetite.config.services.renovate.enable` → `true`; `git diff --stat` touches no nixbot, gitea-mq or buildbot file.
- [ ] **Step 8:** instantiate the host.

```bash
nix eval .#checks.x86_64-linux.nixos-magnetite.drvPath 2>&1 | tee logs/nixos-magnetite-eval-renovate-$(date +%Y%m%d-%H%M%S).log
```

### Task 5: Phase 1 full dry run

**Files:**
- Modify: `modules/nixos/renovate.nix`

- [ ] **Step 1:** add the temporary settings, each commented `# Phase 1 only; removed by tasks.md 7.4`:

```nix
      services.renovate.settings = {
        dryRun = "full";
        branchPrefix = "renovate-selfhost/";
        packageRules = [
          {
            description = "Regex-manager flake.nix ref bumps never touch flake.lock; re-lock in the same commit.";
            matchManagers = [ "custom.regex" ];
            postUpgradeTasks = { commands = [ "nix flake lock" ]; fileFilters = [ "flake.lock" ]; executionMode = "branch"; };
          }
          {
            description = "bun manager updates bun.lock; regenerate bun.nix in the same commit.";
            matchManagers = [ "bun" ];
            postUpgradeTasks = { commands = [ "nix run .#regenerate-bun-nix" ]; fileFilters = [ "bun.nix" ]; executionMode = "branch"; };
          }
          {
            description = "npm playwright is derived from the playwright-web-flake driver; never proposed on its own.";
            matchManagers = [ "bun" ];
            matchPackageNames = [ "playwright" "@playwright/test" ];
            enabled = false;
          }
          {
            description = "A playwright-web-flake ref bump re-locks, re-pins npm playwright, reconciles bun.lock and regenerates bun.nix in one commit.";
            matchManagers = [ "custom.regex" ];
            matchPackageNames = [ "cameronraysmith/playwright-web-flake" "pietdevries94/playwright-web-flake" ];
            groupName = "playwright";
            postUpgradeTasks = {
              commands = [ "nix flake lock" "just bun-repin-playwright" "bun install --ignore-scripts" "nix run .#regenerate-bun-nix" ];
              fileFilters = [ "flake.lock" "packages/docs/package.json" "bun.lock" "bun.nix" ];
              executionMode = "branch";
            };
          }
        ];
      };
      systemd.services.renovate.environment.LOG_LEVEL = "debug";
```
Global rules are concatenated before the repository's (A110), and the repository file is untouched, so the hosted app sees no change. Verify: Task 3 Step 2 passes; M's `validateSettings` derivation instantiates with Task 4 Step 8.

- [ ] **Step 2:** hand the chain to the orchestrator for the Phase 1 pull request; after it lands, deploy and read every alert and failure notice posted since the deploy started, attributing each.

```bash
clan machines update magnetite 2>&1 | tee logs/clan-update-magnetite-renovate-p1-$(date +%Y%m%d-%H%M%S).log
ssh magnetite.zt systemctl list-timers renovate.timer
```

- [ ] **Step 3:** run and accept.

```bash
ssh magnetite.zt 'start=$(date -Is); sudo systemctl start renovate.service; journalctl -u renovate.service --since "$start" --no-pager' \
  2>&1 | tee logs/renovate-phase1-$(date +%Y%m%d-%H%M%S).log
```
Accept when: no `gh-token` error; no "not been added to the allowed list"; every `DRY-RUN: Would commit files` for a `custom.regex` branch lists `flake.lock`, for a bun branch lists `bun.nix`, and for a pending Playwright flake bump lists `flake.lock`, `packages/docs/package.json`, `bun.lock`, `bun.nix`; `gh pr list --author app/vanixiets-renovate` is empty.

- [ ] **Step 4:** summarize the GitHub request endpoint families from the debug journal into verify.md for the permission trim.

### Task 6: Cutover of the hosted app (operator gate plus forge writes)

- [ ] **Step 1 [operator, wizard]:** github.com → Settings → Applications → Installed GitHub Apps → Renovate → Configure → remove `vanixiets` from repository access. Stop until reported.
- [ ] **Step 2:** close the hosted app's pull requests and branches.

```bash
gh pr list --author app/renovate --state open --json number,headRefName --jq '.[] | "\(.number) \(.headRefName)"' |
while read -r n ref; do
  gh pr close "$n" --comment "Superseded by the self-hosted Renovate on magnetite (openspec change stand-up-renovate-on-magnetite); the new instance recreates this update." 
  gh api -X DELETE "/repos/cameronraysmith/vanixiets/git/refs/heads/$ref"
done 2>&1 | tee logs/renovate-cutover-close-$(date +%Y%m%d-%H%M%S).log
```
- [ ] **Step 3:** `gh issue close 832 --comment "<same pointer>"`; verify `gh issue view 832 --json state`.

### Task 7: Phase 2 repository go-live

**Files:**
- Modify: `.github/renovate.json`
- Delete: `.github/workflows/regenerate-lock-files.yaml`
- Modify: `modules/nixos/renovate.nix`
- Modify: `packages/docs/src/content/docs/about/contributing/ci-cd-setup.md`, `packages/docs/src/content/docs/reference/ci-jobs.md`

- [ ] **Step 1:** append the four Task 5 Step 1 rules, as JSON, after the last existing rule in `.github/renovate.json`, in the same order and with the same descriptions; keep "Disable nix manager for playwright-web-flake".
- [ ] **Step 2:** delete `gitIgnoredAuthors` and the "Group playwright across npm and flake.nix" and "Pin playwright npm packages" rules.
- [ ] **Step 3:** delete `.github/workflows/regenerate-lock-files.yaml`; `rg -n regenerate-lock-files --hidden -g '!openspec/changes/**'` and resolve live references.
- [ ] **Step 4:** remove every Phase 1-only item from the aspect: `dryRun`, `branchPrefix`, the global `packageRules`, `LOG_LEVEL`; `rg -n 'Phase 1|dryRun|renovate-selfhost' modules/nixos/renovate.nix` returns nothing.
- [ ] **Step 5:** run the gates.

```bash
nix build .#checks.x86_64-linux.renovate-config .#checks.x86_64-linux.renovate-allowed-commands -L 2>&1 | tee logs/renovate-p2-checks-$(date +%Y%m%d-%H%M%S).log
just bun-holds
direnv exec . prek run --files .github/renovate.json modules/nixos/renovate.nix 2>&1 | tee logs/renovate-p2-prek-$(date +%Y%m%d-%H%M%S).log
```
- [ ] **Step 6:** documentation: describe the updater (App, cadence, task chains, allowlist check, manual nudge `systemctl start renovate.service`, `journalctl -u renovate`) and remove the Mend app and `regenerate-lock-files.yaml` descriptions; `just docs-build`.

### Task 8: Go live

- [ ] **Step 1:** confirm Task 6 is complete; the orchestrator lands Phase 2 through nixbot and gitea-mq; deploy magnetite and attribute every post since the deploy started.
- [ ] **Step 2:** on magnetite, `systemctl cat renovate.service` and `jq '{dryRun, branchPrefix, allowedCommands}'` over the `RENOVATE_CONFIG_FILE` path from `systemctl show -p Environment renovate.service`; expect `null`, `null`, four patterns.
- [ ] **Step 3 [operator, wizard]:** trim the App's permissions to the endpoint families in Task 5 Step 4's summary and the first live run's journal; verify `gh api /apps/vanixiets-renovate --jq .permissions` and no 403 in the next run's journal.

### Task 9: Integration verification

- [ ] **Step 1:** `ssh magnetite.zt sudo systemctl start renovate.service`; for each new pull request, `gh api /repos/cameronraysmith/vanixiets/commits/<head> --jq '{verified: .commit.verification.verified, author: .commit.author.email, files: [.files[].filename]}'`.
- [ ] **Step 2:** for every pull request from the first two live runs, `gh pr view <n> --json commits,statusCheckRollup`: one commit, `nixbot/nix-eval`, `nixbot/nix-build`, `nixbot/effects` green on it.
- [ ] **Step 3:** on a Playwright flake bump, compare `jq -r .devDependencies.playwright packages/docs/package.json` with `nix eval --raw --inputs-from . playwright-web-flake#packages.x86_64-linux.playwright-driver.version` at the head; record "pending" if no release occurred.
- [ ] **Step 4:** no `renovate[bot]` writes after Task 6 Step 1's time; a new Dependency Dashboard by `vanixiets-renovate[bot]` exists.
- [ ] **Step 5:** `gh pr view <n> --json labels,autoMergeRequest` for each: no `merge-queue`, no auto-merge set by the bot.
- [ ] **Step 6:** rollback rehearsal in a scratch copy: drop `renovate` from the aspect list; `nix eval .#checks.x86_64-linux.nixos-magnetite.drvPath` succeeds with a different path; revert.
