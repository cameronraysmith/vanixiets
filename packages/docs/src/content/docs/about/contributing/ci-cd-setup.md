---
title: CI/CD Setup
description: How nixbot builds, checks, and deploys vanixiets, and why deploy secrets are held only by code from main
sidebar:
  order: 6
---

vanixiets builds on [nixbot](https://github.com/Mic92/nixbot) running on magnetite, lands changes through the gitea-mq merge queue, and deploys through hercules-ci-style effects.
The GitHub Actions release and docs-deploy workflows are archived under `.github/deprecated/`.

## The rule: secrets are only held by code from main

Effects are the only CI programs that receive deploy secrets (the Cloudflare API token and the GitHub release token).
onPush effects run only for pushes to `main`, and the one onEvent effect is always evaluated from `main`, so the code that holds a secret has always already been reviewed and landed.

Each onPush effect has one program and one execution path.
There is no separate preview or dry-run implementation of an effect; pre-merge confidence comes from hermetic rehearsal checks that run the same programs against stubs.

## Gating

`nixbot.toml` at the repository root sets:

```toml
attribute = "checks.x86_64-linux"
effects_on_pull_requests = false
```

nixbot reads the effects gating keys from the default branch, never from the ref being built, so a pull request cannot grant itself effects.
With `effects_on_pull_requests = false` and `effects_branches` left at its empty default:

- a push to `main` runs the onPush effects;
- no pull request runs effects, whether it comes from a fork or from a branch in this repository;
- a push to any other branch, including a merge-queue batch branch, runs no effects.

The comments in `nixbot.toml` cite the nixbot functions that implement each rule.

## What pull requests and merge-queue batches run

A pull request or batch build evaluates and builds `checks.x86_64-linux`.
For each onPush effect gated off on that ref, nixbot builds the effect's dependencies as a check and still posts the `nixbot/effects` status.
A required `nixbot/effects` context is therefore satisfied without running anything that reads a secret.

The required contexts are `nixbot/nix-eval`, `nixbot/nix-build`, and `nixbot/effects`.

### Rehearsals

The effects list two hermetic rehearsal checks among their dependencies, so every pull request and batch builds them as part of `nixbot/effects`:

- `checks.<system>.release-rehearsal` runs a full semantic-release with the production plugin list against a local git fixture and a stub GitHub API, including the floating major and minor tags from `semantic-release-major-tag`;
- `checks.<system>.deploy-docs-rehearsal` runs `deploy-docs production` and `deploy-docs preview` against a stub wrangler.

Both run the real programs without a token or network access, so a change that breaks the release or deploy path fails before it reaches `main`.

### Docs previews

The `deploy-docs-preview` onEvent effect uploads a docs preview for each pull request; see [deploy-docs-preview](#deploy-docs-preview) below.
It is not a required context and never blocks a merge.

### Fork pull requests

nixbot's `prApproval` (configured in `modules/nixos/nixbot.nix`) is enabled and holds pull requests from authors outside the `OWNER`, `MEMBER`, and `COLLABORATOR` associations until a maintainer approves CI for them.
Pull requests whose head branch lives in this repository are always trusted, bots included, since pushing that branch already required write access.
A held pull request is approved with its check run's button.

## Landing

gitea-mq tests batches of queued pull requests and lands a batch by fast-forwarding `main` to the exact tested commit.
The resulting push to `main` reuses the batch's build, and nixbot then runs the effects for that commit.

Batches can land in quick succession, so an effect may start after `main` has already moved past the commit it was built for.
Both onPush effects handle this the same way: a `lock` orders runs across builds, and a run whose commit is an ancestor of the current `main` exits 0 without acting, leaving the work to the run for the newer commit.

## Effects

onPush effects are declared under `herculesCI.onPush.default.outputs.effects` in `modules/effects/vanixiets/herculesCI/`.
Each one starts with a fail-closed guard (`mainOnlyGuard` from `modules/lib/effect-run-context.nix`) that asks nixbot for an identity token and refuses to run unless the token says the event is a push to `refs/heads/main`: any other run is skipped with exit 0 before a secret is read, and a missing or unreadable token fails the effect.

### deploy-docs

Runs `nix run .#deploy-docs -- production`, which deploys the nix-built `vanixiets-docs` payload with `wrangler deploy` to 100% of production traffic.
It runs under `lock = "deploy-docs"` and skips with exit 0, logging `DEPLOY-DOCS-ACTION: superseded`, when `main` has moved past its commit.

### release-packages

Discovers packages with `nix run .#list-packages-json` and runs `nix run .#release -- <package-path>` for each, which runs semantic-release with the production plugins.
It runs under `lock = "release-packages"` and skips with exit 0 when `main` has moved past its commit.
See [Semantic Release Preview](/about/contributing/semantic-release-preview/) for previewing a release.

### deploy-docs-preview

`herculesCI.onEvent.pull_request.deploy-docs-preview` is an event effect: nixbot evaluates it from `main`, never from the pull request, so pull-request code never holds its secret.
On a pull request event it:

1. runs only when the pull request's author or pusher has write permission on the repository (`passthru.when.permission = "write"`);
2. fetches the pull request's already-built docs store path from nixbot's API, without evaluating any pull-request code;
3. uploads that payload as a preview version aliased at `b-pr-<number>` (`https://b-pr-<number>-infra-docs.sciexp.workers.dev`), using a synthesized assets-only wrangler config;
4. posts the preview URL as a comment on the pull request through nixbot's API.

Runs for the same pull request are ordered by `lock = "deploy-docs-preview-<number>"`.
The effect is informational: a failed or skipped preview never blocks a merge.

## Secrets

Effect secrets are generated on magnetite by the `vanixiets-effects-secrets` clan vars generator (`modules/effects/vanixiets/secrets.nix`) and handed to nixbot as a systemd credential.
Each effect names the entries it reads in its `secretsMap`.

| Secret | Used by |
|--------|---------|
| `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` | `deploy-docs`, `deploy-docs-preview` |
| `GITHUB_TOKEN` (fine-grained PAT, read and write) | `release-packages` |

To rotate a value, regenerate the generator's prompts with `clan vars generate --regenerate` and redeploy magnetite.

## Running the same programs locally

Local runs use `secrets/shared.yaml` through `sops exec-env` for Cloudflare credentials:

```bash
# Upload a preview version aliased at b-<branch>
just docs-deploy-preview

# Deploy to production (normally done by the deploy-docs effect)
just docs-deploy-production

# Inspect Cloudflare state
just docs-deployments
just docs-versions

# Preview a release with semantic-release's own dry run (needs GITHUB_TOKEN)
just release-package docs true
```

Build what CI builds:

```bash
nix build .#checks.x86_64-linux.some-check
just check-fast
just check
```

## References

- nixbot: https://github.com/Mic92/nixbot
- Cloudflare Workers: https://developers.cloudflare.com/workers/
- Wrangler CLI: https://developers.cloudflare.com/workers/wrangler/
- semantic-release: https://semantic-release.gitbook.io/
