---
title: Semantic Release Preview
sidebar:
  order: 8
---

Find out what a pull request will release before it merges: every pull request gets a `release-plan` check run that forecasts, per monorepo package, the version semantic-release would publish if the pull request landed on `main`.
The forecast uses the same program, configuration, and plugins as the production release.

## How releases run

Releases happen only on `main`.
The `release-packages` effect runs on each push to `main` as `release-packages --rev <commit>`.
That program clones the repository, checks out the commit as `main`, discovers every package with `list-packages-json`, and runs the `release` program (`nix run .#release -- <package-path>`) for each one.
It runs under `lock = "release-packages"`, exits 0 without releasing when `main` has moved past the commit it was built for, and fails for a commit outside `main`'s history.
The effect itself is a data entry in `vanixiets.effects` with no behaviour of its own; the release logic lives entirely in `release-packages` and `release`.
There is no separate preview implementation: the pull request forecast is `release-packages plan`, a mode of the same program, and a local preview is the same `release` program with semantic-release's own `--dry-run`.

Tags follow semantic-release-monorepo's `<package-name>-v<version>` format, for example `@vanixiets/docs-v0.7.0`.
The `semantic-release-major-tag` plugin additionally maintains floating major and minor tags, as ADR-0006 requires.

## The release-plan check run

### When it runs

The `release-packages` effect's `pullRequest` trigger runs `release-packages plan` as a nixbot onEvent `pull_request` effect.
nixbot delivers that event once a pull request's head has built green, so every pull request gets a forecast after a successful build, including fork pull requests once CI has been approved for them.
Each new green head produces a new forecast on that head commit, under `lock = "release-plan-{pr}"`.
`release-plan` is not a required context: a failed forecast never blocks a merge.

nixbot does not guarantee the order in which it delivers pull request events, so a `pull_request` event can arrive after the pull request has merged or after a newer head was pushed.
Before forecasting, `release-packages plan` asks the shared `github-pull-request` program whether the pull request is still open at the event's head commit.
When it is `closed` (closed or merged) or `superseded` (open at a newer head), the check run completes as `neutral`, titled "Release plan skipped" with the summary "pull request #<number> is <state>; no forecast", the log prints `RELEASE-PLAN: skipped (<state>)`, and the program exits 0 without cloning anything; a superseded head gets its forecast from the newer head's own run.

### What it shows

On success the check run is titled "Release plan" and its summary is a table with one row per package:

| Column | Meaning |
|--------|---------|
| package | The package, as discovered by `list-packages-json` on `main` |
| last | The package's latest release version, or `none` when no `<package-name>-v*` tag exists |
| next | The version semantic-release would publish, or `no release` |
| bump | The kind of version change the pull request's commits cause |

The nixbot log of the `release-packages` effect run prints the same forecast as one line per package:

```text
RELEASE-PLAN: @vanixiets/docs 0.7.0 -> 0.8.0
RELEASE-PLAN: <package> <last|none> -> <next|no release>
```

The check run completes as `failure`, with the reason in its summary, when the pull request conflicts with `main`, when the fetched `refs/pull/<number>/head` is not the head commit nixbot reported, or when semantic-release fails for a package (the summary then carries that package's output tail).
A failed pull request state lookup also fails the run.

The effect log also carries semantic-release's own output, which includes `Published release <version> on <channel> channel` even under `--dry-run` (semantic-release 25.0.9 `index.js`, line 221).
The forecast publishes nothing: the `RELEASE-PLAN` lines and the `release-plan` check run are its authoritative output.

### How it forecasts, and what it trusts

The pull request contributes commits only; every file the forecast executes or reads comes from `main`.

1. `release-packages plan` creates the `in_progress` check run on the pull request's head commit, and an exit trap completes it; reporting never masks the program's exit status.
2. It confirms with `github-pull-request state` that the pull request is still open at the event's head commit, and otherwise completes the check run as `neutral` without cloning.
3. It clones the public repository without a token, with tags, fetches `refs/pull/<number>/head`, and requires it to equal the head commit in nixbot's event.
4. It simulates the merge with `git merge-tree --write-tree origin/main <head>` and records a merge commit whose parents are `main` and the pull request head.
5. It checks that merge commit out as `main`, then resets the index and working tree to `main`'s tree, and fails closed if the working tree then differs from `main`'s.
   semantic-release therefore analyses the pull request's history, but loads its configuration, including any `extends`, and its plugins from `main`'s files.
   A pull request that edits a package's release configuration cannot change what the forecast runs.
6. It runs the `release` program for each package with `--dry-run --no-ci`.

Credentials and writes:

- The only credential is nixbot's per-run forge token, a GitHub App installation token scoped to this repository (contents read, checks write), passed as `GITHUB_FORGE_TOKEN`; `@semantic-release/github` accepts an installation token in its verification step, and the token cannot push or create releases.
- The release PAT (`GITHUB_TOKEN` in the effect secrets) is never given to the `pullRequest` trigger, and plan mode never reads it: the program exits 1 if it would need it.
- The forecast never pushes. semantic-release checks push access with `git push --dry-run` even in a dry run, so plan mode points git at a local bare clone of the repository (`url.<bare clone>.insteadOf` for the GitHub URLs, in a temporary git config), and every git network operation reaches that clone instead of GitHub.

## Preview a release locally

```bash
just release-package docs true
```

This expands to:

```bash
nix run .#release -- packages/docs -- --dry-run
```

Arguments after the second `--` pass straight through to semantic-release.
The dry run loads the production plugin list, including `@semantic-release/github`, whose `verifyConditions` step checks the token even in dry-run mode.
`GITHUB_TOKEN` is therefore required:

```bash
GITHUB_TOKEN="$(gh auth token)" just release-package docs true
```

The dry run analyzes commits and prints the next version and its release notes.
It creates no tags, no GitHub release, and no commits.

semantic-release only computes a release on a configured release branch (`main`, or `beta` as a prerelease channel).
On any other branch it reports that no version would be published, so preview from a checkout of `main` or `beta`; for a pull request, read its `release-plan` check run instead.

## Hermetic rehearsal

`checks.<system>.release-rehearsal` proves the release machinery on a fixture; the `release-plan` check run forecasts one real pull request.
The rehearsal runs the `release-packages` program with the production plugin list inside a derivation, against a local git fixture it clones as the repository and a stub GitHub API, without a token or network access.

In `--rev` mode it cuts a full, non-dry-run release, including the floating `docs-v<major>` and `docs-v<major>.<minor>` tags from `semantic-release-major-tag`, and covers a missing `GITHUB_TOKEN`, a superseded rev that `main` has moved past, a diverged rev outside `main`'s history, and a second run with nothing new to release.

In `plan` mode it runs fixture pull requests through the installation-token path: a `feat:` pull request forecasts a minor bump and completes the check run with the table while leaving the fixture remote's tags and refs untouched and creating no release; a `feat!:` pull request forecasts a major bump, proving the production conventional-commits preset is in force; a docs-only or chore pull request forecasts no release; a pull request that edits the release configuration to add a plugin still gets the forecast from `main`'s configuration, and its plugin never runs.
It also covers a merge conflict, a head mismatch, a missing forge token, and a release PAT present in the environment, which the stub API never sees.

The `release-packages` effect lists the rehearsal among its inputs, so every pull request and merge-queue batch builds it as part of the required `nixbot/effects` check.
Build the same check CI builds with:

```bash
nix build .#checks.x86_64-linux.release-rehearsal
```

## Troubleshooting

### `release-plan` reports a conflict with main

Rebase the pull request onto `main`; the forecast needs a merge it can simulate.

### `release-plan` forecasts no release

The forecast is computed from `main`'s release configuration, so a pull request that changes that configuration is forecast under the old one until it lands.
Otherwise see [No release computed](#no-release-computed).

### `GITHUB_TOKEN is required`

Export a token that can read the repository, for example `gh auth token`.

### `node_modules exists and is not a symlink`

The release program links the nix-built dependency tree into the package's `node_modules` for the duration of the run and refuses to overwrite a real `bun install`.
Remove or move the package's `node_modules` directory, then rerun.

### No release computed

Check that:

1. the commits since the last `<package-name>-v*` tag follow conventional commit format (`feat:`, `fix:`, and so on) and touch the package's directory;
2. the checkout is on `main` or `beta`;
3. tags are fetched locally (`git fetch --tags`).

## See also

- [CI/CD Setup](/about/contributing/ci-cd-setup/) - Effects, triggers, and per-trigger secrets
- [Semantic Release Documentation](https://semantic-release.gitbook.io/)
- [Conventional Commits Specification](https://www.conventionalcommits.org/)
- [semantic-release-monorepo Plugin](https://github.com/pmowrer/semantic-release-monorepo)
