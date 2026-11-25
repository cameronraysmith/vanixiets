---
linear_story_id: bff482d4-1039-40b1-946c-e39a2f8ae944
linear_story_identifier: CAM-124
linear_story_title: "Automate package version bumps"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-124/automate-package-version-bumps
linear_story_state: Todo
linear_team: CAM
linear_project: nixbot-herculesci-cicd
last_synced_state: Todo
last_synced_at: 2026-11-24T23:50:54Z
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-24T23:50:54Z", transition: "Backlog->Todo", outcome: "posted", note: "T1 bind; issue created in project nixbot-herculesci-cicd at Todo, description seeded from this proposal, one comment posted" }
---

## Why

The packages under `pkgs/by-name` are bumped only when a person runs one of 23 hand-written `update.sh` scripts, and about fifteen upstream-versioned packages have no script at all.
The scripts share no code, filter prereleases inconsistently, and some leave a hash for a person to finish.
Renovate (CAM-106) and nixbot's flake-update effect (CAM-108) now keep every other dependency current, and both leave these packages out of scope.
Renovate already finds releases and manages update pull requests on magnetite, so a typed per-package pin it can read, plus one realizer it can run, closes the gap.

## What Changes

**Who finds a package's new release**
- From: a person runs `just update-package <p>` or `nix run .#update-<p>`, whose script queries the upstream with its own copy of the lookup logic.
- To: Renovate reads each migrated package's `pkgs/by-name/<p>/pin.json` through one custom manager and looks up the next release with its own datasources, plus `customDatasources` for vendor endpoints. Packages are discovered by the file's presence, with no hand-maintained list.
- Reason: one lookup, version ordering and pull-request lifecycle for every dependency, and Renovate's handling of unstable releases and stale branches.
- Impact: non-breaking for reviewers. One pull request per package on `renovate/<p>`, titled `chore(deps): update <p> to <version>`, labelled `dependencies`, like other Renovate pull requests.

**Who rewrites the pins**
- From: each script rewrites `package.nix` with anchored `sed`.
- To: one realizer, `nix run .#realize-pin -- <p> <version>`, run by Renovate as its single new post-upgrade task, rewrites `pin.json` and the package's declared companion files. The realizer is written in typed Python, total over every source and artifact kind, and tested offline in a small check.
- Reason: every pushed commit is complete, with digests from the upstream's checksum file where one exists, and nothing is left for a person to finish.
- Impact: `package.nix` of a migrated package reads and validates `pin.json`, so a malformed pin fails evaluation before it can merge.

**When per-package pull requests fire**
- To: Monday and Thursday, 14:00 to 17:59 UTC; at most 2 per run, 4 per window and 8 per week in the expected case, and never more than 6 open. The window stays clear of the flake-update effect (Tuesday and Friday) and of magnetite's store collection.
- Reason: the flake-update burst already saturates nixbot on magnetite; per-package builds must not land on top of it.

**Cutover, staged**
- Stage 1: the pin schema, the realizer, and ic-wasm-bin, icp-cli-bin, omnigraph, mergify-cli-bin, moshi-hook and claude-code. Later stages: the remaining tag-pinned packages, then packages with no updater today, then commit-pinned packages through Renovate's `git-refs` digest updates.
- Each migrated package loses its `update.sh` and its `apps.update-*` entry in the same commit; `just update-package` and `bump-procedure.md` become "realize a version".

## Capabilities

### New Capabilities
- `package-version-refresh` (stratum: `behavioral`): what the repository needs from updates of its pinned packages. Each new stable release of a package with a package pin is proposed in an update pull request of its own, inside the update window and in bounded numbers. Every pushed commit is a consistent commit covering the pin, its digests and its companion files. A malformed pin fails a required check. Each package has exactly one updater, merge authorization stays with people, and an update that cannot be completed never lands.
- `package-version-refresh-interface` (stratum: `interface`): the properties at the machine's interface that discharge them. They cover the `pin.json` contract and its evaluation-time type (the `source` and `artifacts` unions and typed companions), the shared URL template and platform map, the realizer's command line, writes and failure behaviour, the Renovate custom manager, datasources, pin rule and allowlist entry, the realizer's offline check, and the per-package cutover. Trust boundary: the repository controls what it declares to Renovate, what the realizer writes and how a pin evaluates. It does not control when Renovate runs or how it looks up and orders releases, what an upstream publishes, whether a checksum file matches its artifacts, or whether a release builds on darwin.

### Modified Capabilities
- `world-assumptions` (stratum: `world`): adds assumptions on the deployed Renovate's jsonata custom manager and custom datasources, the scope and counting of its schedule and limits, its compiled post-upgrade commands, its exclusion of unstable releases and of older versions, and on upstream checksum files matching their release artifacts. The designation table gains `upstream`, `artifact`, `platform`, `checksum file`, `digest`, `package pin`, `companion file`, `update window` and `unstable release`.

## Impact

Implementation touches: `pkgs/by-name/<p>/` of each migrated package (`pin.json` added, `package.nix` reads it, `update.sh` deleted); a pin type and helper under `modules/lib/` or `lib/`, exposed through the flake; the realizer package and `apps.realize-pin`; a new check for the realizer's offline tests and one for the pin type, each with a declared size class; `.github/renovate.json` (custom manager, `customDatasources`, pin rule); `modules/lib/renovate-settings.nix` (one allowlist entry) and `modules/checks/renovate-allowed-commands.nix` (render templated commands before matching); `modules/apps/updates.nix`; `justfile`; `bump-procedure.md`, ADR 0002's recipe description and the CI/CD documentation.
Companion files touched through typed entries: `modules/home/ai/plugins/version-control-and-forge/apm.yml` and `pkgs/by-name/apm-skills-compose/package.nix` (mergify-cli-bin).
Deployment: none for stage 1. Renovate reads `.github/renovate.json` from `main`, and the allowlist reaches magnetite only when magnetite deploys, so the allowlist entry must be deployed before the first pin rule fires (design, Migration Plan).

Nothing in nixbot, gitea-mq or the flake-update effect is edited. Renovate's own module, schedule and GitHub App are unchanged.
Out of scope: auto-enqueueing or auto-merging update pull requests; branch-tracking flake inputs (CAM-108) and rev- or tag-pinned flake inputs (CAM-106); packages whose version comes from a flake input (playwright-cli, omp-browser-relay-extension, vanixiets-docs*); first-party packages; `pkgs/disabled/*`.
The `allowedVersions` rule for lazyvim-nix that another chain adds to `.github/renovate.json` stays as it is; this change appends its rules without reordering existing ones.
