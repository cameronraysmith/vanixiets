---
linear_story_id: 857edfc7-ce19-4090-82c8-e37e281463f4
linear_story_identifier: CAM-106
linear_story_title: "Stand up Renovate on magnetite as the dependency updater"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-106/stand-up-renovate-on-magnetite-as-the-dependency-updater
linear_story_state: In Progress
linear_team: CAM
linear_project: nixbot-herculesci-cicd
last_synced_state: In Progress
last_synced_at: 2026-11-17T04:56:58Z
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-16T18:59:21Z", transition: "Backlog->Todo", outcome: "posted", note: "T1 bind; issue created in project nixbot-herculesci-cicd at Todo, description seeded from this proposal, one comment posted" }
  - { at: "2026-11-17T04:56:58Z", transition: "Todo->In Progress", outcome: "posted", note: "T2 on first checked tasks.md box (1.1, 1.3, 1.5); state set by name, one comment posted" }
---

## Why

Renovate's pull requests to vanixiets arrive incomplete: a flake ref bump leaves `flake.lock` stale, a bun update leaves `bun.nix` stale, and npm Playwright can drift from the flake's driver.
A GitHub Actions workflow repairs them with fix-up commits after nixbot has already failed the first push, so every update costs two evaluations and a red check.
The hosted Mend app cannot run the commands that would make its own commits complete.
Magnetite already runs the forge, nixbot, gitea-mq and the cache, and nixpkgs ships a tested Renovate module, so self-hosting there makes every Renovate commit self-consistent at push time and retires the repair workflow.

## What Changes

**A self-hosted dependency updater on magnetite**
- From: the Mend-hosted Renovate app runs on Mend's schedule against `cameronraysmith/vanixiets` as `renovate[bot]`.
- To: the nixpkgs `services.renovate` module runs on magnetite as a dynamic-user unit every 2 hours at minute 17, in a first-party aspect `flake.modules.nixos.renovate` named in the host's aspect list, with nix, the repository's own bun, `just`, `jq` and `bash` on its path and resource ceilings that keep it from competing with nixbot evaluation.
- Reason: only a self-hosted instance can run post-upgrade commands, and the module plus its NixOS test is maintained upstream.
- Impact: one timer and one unit on magnetite; up to four pushes per run, each a nixbot evaluation.

**Its own forge identity, with a short-lived token**
- From: Mend's shared app identity.
- To: a dedicated GitHub App `vanixiets-renovate`, installed on vanixiets only; a privileged pre-start step mints a one-hour installation token per run from the App's private key, which lives in a clan vars generator and never enters the sandbox where repository code runs. Commits are made through GitHub's API and are signed by GitHub.
- Reason: repository-scoped, expiring credentials with no long-lived token on disk or in the store.
- Impact: one more App to hold and rotate; registration and key population are operator browser and terminal steps.

**Every update commit is complete when pushed**
- From: `regenerate-lock-files.yaml` pushes `github-actions[bot]` fix-up commits after nixbot fails the first push; `gitIgnoredAuthors` tolerates them.
- To: post-upgrade tasks per manager re-lock the flake after a `flake.nix` ref bump and regenerate `bun.nix` after a bun update, in the same commit; a Playwright flake bump re-pins npm Playwright to the new driver, reconciles `bun.lock` and regenerates `bun.nix` in one commit, and the bun manager no longer proposes Playwright on its own. A flake check fails when a task command in `.github/renovate.json` is not admitted by the instance's command allowlist.
- Reason: nixbot should be green on the first push with no follow-up commit.
- Impact: `regenerate-lock-files.yaml` and `gitIgnoredAuthors` are deleted; the two Playwright rules are replaced.

**A staged cutover with one updater at a time**
- From: nothing to migrate from beyond the hosted app's open pull requests and Dependency Dashboard #832.
- To: Phase 1 runs a full dry run under a temporary branch prefix with the candidate rules supplied globally; the operator then disables the Mend app; the old `renovate[bot]` pull requests and branches and #832 are closed; Phase 2 lands the repository changes in one pull request, magnetite is deployed, and the first live run is verified.
- Reason: two updaters writing the same branches would fight; the dry run proves tasks run and commit the right files before anything is pushed.
- Impact: open Renovate pull requests are recreated by the new identity; Renovate pull requests are not auto-enqueued into gitea-mq.

## Capabilities

### New Capabilities
- `dependency-update-service` (stratum: `behavioral`): what the fleet's dependency updater must do for the repository — propose updates on a fixed cadence under its own forge identity with expiring credentials, push only commits whose lock files and derived pins already agree with what they declare so the build service passes without a follow-up commit, keep npm Playwright derived from the flake's driver, leave merge authorization to people, and be the only updater writing to the repository.
- `dependency-update-interface` (stratum: `interface`): the properties at the machine's interface that discharge those requirements — the evaluated unit and timer settings on magnetite, the private key held only by a privileged pre-start step and the token reaching only the updater's environment, the command allowlist and the flake check that ties the repository's task commands to it, the tool versions on the unit's path with the bun assertion, and the App's permission set with no ruleset bypass. Its trust boundary: the machine controls what the updater is configured and allowed to run and with which credential; it does not control the App's installation selection, GitHub's token semantics, Renovate's commit-despite-failure behaviour, or the correctness of upstream releases.

### Modified Capabilities
- `world-assumptions` (stratum: `world`): adds assumptions on GitHub App installation tokens, Renovate 44.236.2's App-identity commits, post-upgrade task execution and its commit-despite-failure behaviour, rule merging, full dry runs, its treatment of foreign-authored branches and dashboards, and magnetite's daemon admitting an untrusted dynamic user; the designation table gains the terms the new behavioral requirements use.

## Impact

Implementation touches: a new aspect `modules/nixos/renovate.nix` (service settings, privileged token minting, the key generator, resource controls, the bun assertion); `modules/machines/nixos/magnetite/default.nix` to name `renovate` in the aspect list; one entry under `vars/per-machine/magnetite/`; `.github/renovate.json` (task rules, Playwright rules, `gitIgnoredAuthors` removed); deletion of `.github/workflows/regenerate-lock-files.yaml`; a flake check beside `modules/checks/renovate.nix`; documentation of the updater in the CI/CD docs.
Outside the repository: the GitHub App and its installation, disabling the Mend app for vanixiets, closing the old Renovate pull requests and #832.

Nothing in nixbot, gitea-mq, buildbot or their Apps and rulesets is edited.
Out of scope: auto-enqueueing Renovate pull requests, any second repository, and branch-tracking flake inputs. Those stay one pull request per input from `.github/workflows/update-flake-inputs.yaml` until the separate change `move-flake-input-updates-to-nixbot` (CAM-108) moves them to nixbot's `flakeUpdate` effect; that change deletes the workflow and keeps the flake-updater GitHub App, whose credentials the effect uses (its D7 and D8). Renovate updates every other dependency, including the flake inputs pinned by revision or by tag.
