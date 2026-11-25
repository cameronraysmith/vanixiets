<!--
Raw capture of the 2026-11-24 decision session. The questions were explored by two read-only
investigations, one of this repository's update mechanisms and one of numtide/llm-agents.nix's
per-package updater at d70dfebd, and the operator settled each decision; this file records that
log as it ran, and design.md reorganizes it. The `superpowers:brainstorming` handoff itself was not
run: the session that wrote this file worked from the operator-approved brief of that session.
-->

# Brainstorm: automate per-package version bumps for `pkgs/by-name`

## Background

Two updaters keep this repository's dependencies current, and neither touches the packages under `pkgs/by-name`.
Renovate, self-hosted on magnetite (CAM-106), updates rev- and tag-pinned flake inputs, the bun workspace, the Rust toolchain and Typst imports through `.github/renovate.json`; no manager there matches `pkgs/by-name/**`.
nixbot's scheduled `flake-update` effect (CAM-108) refreshes branch-tracking flake inputs, one `update-<input>` pull request per moved input.
Both changes name per-package updates out of scope (`stand-up-renovate-on-magnetite/proposal.md:62`, `move-flake-input-updates-to-nixbot/proposal.md:63`), and no change or ADR covers them since.

A package bump today is a person running a script by hand.
There are 23 `update.sh` scripts, one `nix-update-script` user (nix-fast-build), and 20 hand-listed `apps.update-*` entries in `modules/apps/updates.nix`; dbt-fusion, langfuse-cli and uncomment-bin have a script and no app, and quarto-bin's app is named `update-quarto`.
The procedure is `packages/docs/src/content/docs/development/operations/bump-procedure.md` with the generic recipe `just update-package` (`justfile:601-610`, ADR 0002).
About fifteen upstream-versioned packages have no updater at all, among them five `agent-plugins-*`, `pi-agent-extensions`, `pi-openai-server-compaction` and `tmux-command-palette`, which pin an upstream commit.

## Evidence gathered

This repository (full report: the `VanixietsUpdateMechanisms` investigation):
- The scripts share no library. Each rewrites `package.nix` with anchored `sed`, so a hash line must directly follow its anchor line.
- Prerelease filtering is inconsistent: quarto, linear, xsra, git-xet and dbt-fusion filter none; worktrunk, hindsight, perses and git-xet take `.[0]` of the API's order rather than the highest version.
- Some updaters leave work for a person: worktrunk and mergify print an instruction to refresh `apmDepsHash` in `pkgs/by-name/apm-skills-compose/package.nix`, and buzz resets its vendor hash to a placeholder. worktrunk, mergify and linear also rewrite a `ref:` in `modules/home/ai/plugins/*/apm.yml`, which the release-alignment structure checks require to equal the package's tag commit.
- Six packages already take their digests from a checksum file the upstream publishes with each release: ic-wasm-bin, icp-cli-bin and omnigraph (per-asset `.sha256`), mergify-cli-bin (`SHA256SUMS`), moshi-hook (`checksums.txt`), and claude-code (the vendor's `manifest.json`).
- Renovate's post-upgrade tasks must match `flake.lib.renovateSettings.allowedCommands` (`modules/lib/renovate-settings.nix:10-17`), which `checks.renovate-allowed-commands` enforces against `.github/renovate.json`. Renovate already runs `nix flake lock` and `nix run .#regenerate-bun-nix` as tasks, so nix and network are available in its unit.
- The archetype Renovate pull request is #4238: branch `renovate/argoproj-argo-cd-3.x`, title `chore(deps): update dependency argoproj/argo-cd to v3.6.3`, label `dependencies`, release notes in the body.
- The archetype flake-update pull request is #4272, `update-nixpkgs`, titled `Update nixpkgs`. The split between the two updaters is recorded at `packages/docs/src/content/docs/about/contributing/ci-cd-setup.md:296-298`.
- Neither updater enqueues; the operator enqueues every update pull request into gitea-mq.

numtide/llm-agents.nix at `d70dfebd` (full report: the `LlmAgentsUpdater` investigation):
- GitHub Actions discovers packages and fans out a matrix, one `update/<name>` branch and pull request per package.
- A typed, stdlib-only Python library in `scripts/updater/` does the work, with injectable fetchers for offline unit tests that run in `nix flake check`.
- Each package keeps its version and per-platform hashes in a `hashes.json` beside `package.nix`, and `platformSource` gives the build and the updater one URL template and one platform map, so the two cannot drift.
- `lib/mk-updater.nix` validates a package's updater configuration at evaluation time, so a bad one fails `nix flake check`.
- The updater refuses downgrades, confines writes to the package's own directory plus declared companions, and computes dependency hashes with a dummy-hash build that it rolls back on failure.
- Weaknesses: nothing builds before the pull request, discovery runs only for x86_64-linux, the runtime configuration is an untyped dictionary, and nothing closes a stale pull request.

## Decision chain

**Q1. Who discovers a new upstream release, and who rewrites the pins?**
Options:
- O1: Renovate discovers through a custom manager over a per-package data file, and a typed realizer, run as a post-upgrade task, rewrites the pins.
- O2: a nixbot scheduled effect that both discovers and realizes, after CAM-108's model.
- O3: port llm-agents.nix's GitHub Actions matrix.
- O4: keep the scripts and schedule them.

Operator decision (D-a): O1.
Renovate already owns release lookup, version ordering, prerelease handling, branch and pull-request lifecycle, the dependency dashboard and stale-branch cleanup, and it already runs on magnetite with a task allowlist.
What it cannot do is compute a Nix hash, which the realizer does.
O2 would rebuild Renovate's lookup and pull-request lifecycle inside an effect. O3 puts a hosted runner back on the update path, which CAM-108 removed. O4 keeps the inconsistencies listed above.

**Q2. Are commit-pinned packages in scope?**
Operator decision (D-b): yes, in a later stage than the tag-pinned packages, through Renovate's `git-refs` datasource digest updates of the tracked branch.

**Q3. Does automation enqueue?**
Operator decision (D-c): no. The operator enqueues into gitea-mq, as for CAM-106's Renovate pull requests and CAM-108's flake-update pull requests.

**Q4. What is the first delivery, and what does design.md have to record?**
Operator decision (D-d): an OpenSpec change bound to a new Linear story.
design.md records the "Renovate owns discovery, the package owns realization" boundary and two tagged unions, one over where a release comes from and one over what a release pins.
The first delivery is the schema, the realizer and the six platform-binary packages with upstream checksum files: ic-wasm-bin, icp-cli-bin, omnigraph, mergify-cli-bin, moshi-hook and claude-code.

**Q5. How does a package migrate?**
Settled with Q4: a clean cutover per package. A migrated package loses its `update.sh` and its `apps.update-*` entry in the same commit that adds its data file, and `just update-package` and `bump-procedure.md` shrink to "realize a version".

## Design sketch agreed in the session

- A per-package data contract, `pkgs/by-name/<p>/pin.json`, holds the upstream source as data, the version and the per-platform hashes. `package.nix` reads it with `builtins.fromJSON` and validates it against a Nix type, so a malformed pin fails `nix flake check`. The build and the realizer share one URL template and one platform map.
- Two tagged unions, as module-system `lib.types.attrTag`:
  - `source = githubRelease {owner, repo, tagTemplate} | npm {package} | pypi {package} | vendorJson {url, pointer} | vendorText {url, regex} | gitCommit {owner, repo, branch}`;
  - `artifacts = platformBinaries {urlTemplate, platforms, checksum = upstreamFile {...} | prefetch} | sourceBuild {fetcher, depsHash = npm | cargo | go | none}`;
  - and `companions = [ paths ]`, which makes cross-file edits explicit and confined.
- One realizer, `nix run .#realize-pin -- <pkg> <version>`, total over both unions, written in Python with basedpyright, beartype and Expression `Result` at its I/O boundaries, with network and nix calls behind injectable capabilities, and offline unit tests as a small check. Dependency hashes come from the fake-hash build with rollback. Every pushed commit is complete, with no manual follow-up.
- Renovate gets one custom manager over `pkgs/by-name/**/pin.json` (the `jsonata` custom manager if the deployed Renovate supports it, otherwise `regex`), `customDatasources` for vendor endpoints, and one post-upgrade task added to the allowlist. Packages are discovered through the existing pkgs-by-name wiring, with no hand-maintained list. Renovate's `renovate/<p>` branches cannot collide with the effect's `update-<input>` branches.

## Risks named in the session

- R1 [INFERENCE at the time]: the deployed Renovate's support for `customType: "jsonata"` was unverified.
- R2: post-upgrade prefetches and builds run on magnetite, nixbot's host, so they need timeouts and Renovate's concurrency limits.
- R3: nixbot gates only x86_64-linux before a pull request merges; aarch64-darwin is best-effort (`modules/checks/nixbot-best-effort-darwin.nix`), so a darwin breakage presents as an ignored failure. Superseded on 2026-11-25 by #4290, which deleted that file and the `ignoreFailure` on Mac checks: aarch64-darwin now gates a merge too, and every pull request needs stibnite reachable as a builder (design R3, R5).
- R4: when the realizer fails, Renovate still opens the pull request with an artifact error, and nixbot's hash mismatch fails it safely.

## Constraints from the workspace orchestrator (2026-11-24)

- The flake-update effect moves from Tuesday and Friday 22:00 UTC to an early-UTC slot on the same days; its 24-pull-request burst held nixbot on magnetite at load 113 for more than 30 minutes. The brief named 09:00 UTC; the commit carrying the move (`pzolkvnx`, in flight on the development join when this file was written) sets 10:00 UTC, after magnetite's store collection at 04:00 New York time. This design must say when per-package pull requests fire and how many open at once, and must not overlap the flake-update window.
- An `allowedVersions` rule for lazyvim-nix is being added to `.github/renovate.json` by another chain; the design must expect it.
- Every gated check declares a test size class (`testSizes.checks`, `checks.<system>.test-size-classes`).
- World-assumption codes start after A225, which `declare-test-size-classes` (CAM-123) claims.
- `gate-mutating-http` (#4253) prompts on mutating curl that is not one plain command to a trusted host; the design must say whether the realizer makes any forge API call.

## Points found while writing the design

- R1 is resolved. magnetite's Renovate unit runs `/nix/store/wazpcbgy75zxr1fw6bq7swm5s48pzdcw-renovate-44.247.1`, whose `dist/modules/manager/custom/` holds `jsonata` beside `regex`, with `fileFormat` `json` or `yaml` (`jsonata/index.js:24`), and which declares `customDatasources` with formats `json`, `plain`, `yaml`, `html` and `toml`. `nix eval --inputs-from . nixpkgs#renovate.version` on the locked nixpkgs prints `44.247.1`. Read 2026-11-24 over SSH.
- In 44.247.1, `schedule`, `updateNotScheduled`, `prHourlyLimit`, `prConcurrentLimit` and `branchConcurrentLimit` are all valid inside a `packageRules` entry (`sharedScopes` in `config/options/scopes.js`), but the counts they are compared against are repository-wide: open pull requests and branches over every Renovate branch, and pull requests created this hour under the branch prefix (`workers/repository/process/limits.js`, `write.js:93-100`). A limit set on the pin rule is therefore a ceiling that other Renovate pull requests also consume, not a reservation.
- `updateNotScheduled` defaults to true, so without setting it the window would govern only branch creation, and Renovate would still rebase and re-run the realizer on an open pin branch outside the window.
- Renovate compiles every post-upgrade command as a template before matching it against `allowedCommands` (`execute-post-upgrade-commands.js:77-86`); 44.247.1 has no `allowCommandTemplating` switch. The current `checks.renovate-allowed-commands` matches the uncompiled strings in `.github/renovate.json`, so a templated command needs the check to render it first.
- omnigraph pins a second fetch besides its platform binaries (`passthru.skillSrc`, a `fetchFromGitHub` tree at the release tag), and mergify-cli-bin pins the tag's commit (`sourceRev`), a `ref:` in `modules/home/ai/plugins/version-control-and-forge/apm.yml`, and, through that ref, `apmDepsHash` in `pkgs/by-name/apm-skills-compose/package.nix`. A single `artifacts` value cannot describe either, and a bare path list does not tell the realizer what to write into a companion file.
- Post-upgrade tasks see only `PATH` and `HOME` (CAM-106's A111), so the realizer runs without a forge token. It reads release assets and vendor endpoints only and calls no GitHub API: release download URLs are not counted against the API's rate limit, and `git ls-remote` resolves a tag's commit. Nothing it sends is a mutating HTTP request.

## Decisions taken on those points (operator, 2026-11-24)

**Q6. How does the pin describe a package with more than one fetch, or with files outside its own directory?**
Operator decision (D-e): `artifacts` becomes a named set of artifact entries, each one the `platformBinaries | sourceBuild` union, so omnigraph's pin holds `binaries` and `skillSrc`.
The pin records the release tag's commit whenever an entry or a companion needs it.
`companions` stays a list, but each entry is typed, `{ path, kind = apmRef { git } | fixedOutputHash { package, attr } }`, so the realizer knows what to write into each file.
A file outside `pkgs/by-name/<p>/` (an `apm.yml`, apm-skills-compose's `apmDepsHash`) may change only through such an entry, and the realizer's write confinement is computed from the entries.

**Q7. When do per-package pull requests fire, and how many at once?**
Operator decision (D-f): Renovate's pin rule sets `schedule: ["* 14-17 * * 1,4"]` (Monday and Thursday, 14:00 to 17:59 UTC), `updateNotScheduled: false`, `prHourlyLimit: 2`, `prConcurrentLimit: 6` and `branchConcurrentLimit: 6`.
Renovate's timer fires every two hours at :17 with up to ten minutes' random delay, so two runs fall in each window, at about 14:17 and 16:17.
The bound is at most 2 pull requests per run, 2 runs per window, so at most 4 per window and 8 per week, and never more than 6 per-package pull requests open.
The flake-update schedule in the in-flight commit `pzolkvnx` (Tuesday and Friday 10:00 UTC) is the source of truth, not the brief's 09:00.
The window was picked to stay clear of both the flake-update effect, whichever of its schedules is live, and magnetite's harmonia-gc at 04:00 New York time (09:00 UTC in winter, 08:00 in summer).

**R1.** Resolved by the read recorded above: the deployed Renovate is 44.247.1 at `/nix/store/wazpcbgy75zxr1fw6bq7swm5s48pzdcw-renovate-44.247.1`, and it ships the `jsonata` custom manager.
