---
title: Semantic Release Preview
sidebar:
  order: 8
---

Preview what semantic-release would publish for a monorepo package, using the same program and plugins as the production release.

## How releases run

Releases happen only on `main`.
The `release-packages` effect runs on each push to `main`, discovers every package with `nix run .#list-packages-json`, and runs `nix run .#release -- <package-path>` for each one.
It runs under `lock = "release-packages"` and exits 0 without releasing when `main` has moved past the commit it was built for.
There is no separate preview implementation: a local preview is the same `release` program with semantic-release's own `--dry-run`, and the pre-merge rehearsal runs that program against stubs.

Tags follow semantic-release-monorepo's `<package-name>-v<version>` format, for example `@vanixiets/docs-v0.7.0`.
The `semantic-release-major-tag` plugin additionally maintains floating major and minor tags, as ADR-0006 requires.

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
On any other branch it reports that no version would be published, so preview from a checkout of `main` or `beta`.

## Hermetic rehearsal

`checks.<system>.release-rehearsal` runs a full, non-dry-run semantic-release with the production plugin list inside a derivation, against a local git fixture and a stub GitHub API.
It exercises the whole release path, including the floating `docs-v<major>` and `docs-v<major>.<minor>` tags from `semantic-release-major-tag`, without a token or network access.

The `release-packages` effect lists the rehearsal among its dependencies, so every pull request and merge-queue batch builds it as part of the required `nixbot/effects` check.
Build the same check CI builds with:

```bash
nix build .#checks.x86_64-linux.release-rehearsal
```

## Troubleshooting

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

- [Semantic Release Documentation](https://semantic-release.gitbook.io/)
- [Conventional Commits Specification](https://www.conventionalcommits.org/)
- [semantic-release-monorepo Plugin](https://github.com/pmowrer/semantic-release-monorepo)
