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

An effect contains no behaviour of its own.
Each effect is a data entry naming a program, and every behaviour lives in that program, which a hermetic rehearsal check runs against stubs.
There is no separate preview or dry-run implementation of an effect; pre-merge confidence comes from those rehearsals.

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

Each effect lists the rehearsal checks for its program among its inputs, so every pull request and batch builds them as part of the required `nixbot/effects` gate:

- `checks.<system>.deploy-docs-rehearsal` runs `deploy-docs production` and `deploy-docs preview` through their flag interface against a stub wrangler, including the superseded production run and the untrusted `--payload` hardening;
- `checks.<system>.release-rehearsal` runs `release-packages --rev` with the production semantic-release plugin list against a local git fixture and a stub GitHub API, including the floating major and minor tags from `semantic-release-major-tag`, a superseded rev that main has moved past, and a diverged rev outside main's history;
- `checks.<system>.docs-preview-rehearsal` runs `docs-preview` against a stub nixbot API, a stub GitHub check-runs API, and a stub `deploy-docs`, covering succeeded and `skipped_local` docs attributes, failed and missing attributes, a build that did not succeed, a malformed event, and a failed deploy.

`deploy-docs` and `docs-preview` list `deploy-docs-rehearsal`, `release-packages` lists `release-rehearsal`, and `docs-preview` also lists `docs-preview-rehearsal`.
The rehearsals run the real programs without a token or network access, so a change that breaks the release, deploy, or preview path fails before it reaches `main`.

`checks.<system>.effects-interpreter` covers the one piece of code between nixbot and a program: the script the interpreter generates for each effect.

### Docs previews

The `docs-preview` onEvent effect uploads a docs preview for each pull request; see [docs-preview](#docs-preview) below.
It reports as the `docs-preview` check run, which is not a required context and never blocks a merge.

### Fork pull requests

nixbot's `prApproval` (configured in `modules/nixos/nixbot.nix`) is enabled and holds pull requests from authors outside the `OWNER`, `MEMBER`, and `COLLABORATOR` associations until a maintainer approves CI for them.
Pull requests whose head branch lives in this repository are always trusted, bots included, since pushing that branch already required write access.
A held pull request is approved with its check run's button.

## Landing

gitea-mq tests batches of queued pull requests and lands a batch by fast-forwarding `main` to the exact tested commit.
The resulting push to `main` reuses the batch's build, and nixbot then runs the effects for that commit.

Batches can land in quick succession, so an effect may start after `main` has already moved past the commit it was built for.
Both onPush effects handle this the same way: a `lock` orders runs across builds, and the program exits 0 without acting when its `--rev` is no longer `main`'s head, leaving the work to the run for the newer commit.

## Effects

Effects are data.
`modules/effects/vanixiets/effects.nix` declares them as entries of the flake option `vanixiets.effects.<name>`, each naming its trigger (`push-main` or `pull-request`), its program, literal arguments, the secrets it reads, its rehearsals, its lock, and, for pull-request entries, the permission nixbot requires.

One interpreter, `modules/effects/vanixiets/registry.nix`, turns the entries into `herculesCI.onPush.default.outputs.effects.<name>` and `herculesCI.onEvent.pull_request.<name>`.
The script it generates for each effect does three things, in order:

1. for `push-main` entries, runs the fail-closed guard (`mainOnlyGuard` from `modules/lib/effect-run-context.nix`), which asks nixbot for an identity token and refuses to run unless the token says the event is a push to `refs/heads/main`: any other run is skipped with exit 0 before a secret is read, and a missing or unreadable token fails the effect;
2. exports each declared secret, failing with a specific error on the first one that is absent, null, or empty;
3. execs the program with the entry's arguments, followed by `--rev <commit>` for `push-main` entries.

`checks.<system>.effects-interpreter` renders synthetic entries through the same function and runs the generated script against stubs, asserting the guard's skip on a non-main run, the exported secrets, the failure on a missing secret, the forge token, and the exact argv the program receives, including `--rev`.

### deploy-docs

Runs `deploy-docs production --rev <commit>`, which deploys the nix-built `vanixiets-docs` payload with `wrangler deploy` to 100% of production traffic.
It runs under `lock = "deploy-docs"` and skips with exit 0, logging `DEPLOY-DOCS-ACTION: superseded`, when `main`'s head is no longer its commit.

`deploy-docs` owns its interface: `production --rev <sha>` or `preview --rev <sha> --alias <name> [--payload <dir>]`, with an optional `--deployed-by <name>`.
It derives short SHAs, the version message, and the sanitized alias from its flags and reads only `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` from the environment; `deploy-docs --help` prints the usage.

### release-packages

Runs `release-packages --rev <commit>`, which clones the repository, checks out the commit as `main`, discovers packages with `list-packages-json`, and runs the `release` program for each, which runs semantic-release with the production plugins.
It runs under `lock = "release-packages"`, skips with exit 0 and logs `RELEASE-PACKAGES-ACTION: superseded` when `main` has moved past its commit, and refuses a commit outside `main`'s history.
See [Semantic Release Preview](/about/contributing/semantic-release-preview/) for previewing a release.

### docs-preview

`herculesCI.onEvent.pull_request.docs-preview` is an event effect: nixbot evaluates it from `main`, never from the pull request, so pull-request code never holds its secret.
It runs the `docs-preview` program, which on a pull request event:

1. runs only when the pull request's author or pusher has write permission on the repository (`permission = "write"`, which the interpreter emits as `passthru.when.permission`);
2. creates an `in_progress` GitHub check run named `docs-preview` on the pull request's head commit, using nixbot's forge token;
3. fetches the pull request's nixbot build from nixbot's API, without evaluating any pull-request code, and requires the build to have succeeded and its `checks.x86_64-linux.package-vanixiets-docs` attribute to be `succeeded` or `skipped_local` (nixbot reports a cached output as `skipped_local`);
4. runs `deploy-docs preview --rev <head> --alias pr-<number> --payload <store path>`, which uploads that payload as a preview version aliased at `b-pr-<number>` (`https://b-pr-<number>-infra-docs.sciexp.workers.dev`) using a synthesized assets-only wrangler config;
5. completes the check run as `success` with the preview URL as its details link, or as `failure` with the error in its summary.

Runs for the same pull request are ordered by `lock = "deploy-docs-preview-{pr}"`.
The effect is informational: a failed or skipped preview never blocks a merge.

## Secrets

Effect secrets are declared once, in `flake.lib.vanixietsEffectSecrets` (`modules/effects/vanixiets/secrets.nix`).
The `vanixiets-effects-secrets` clan vars generator's prompts and the secrets JSON it composes are generated from that schema; the generator runs on magnetite and nixbot receives the result as a systemd credential.
An effect entry's `secrets` is typed as an enum of the schema's names, and the interpreter derives each effect's `secretsMap` from it, so an effect can read exactly the secrets it declares.
`checks.x86_64-linux.nixbot-wiring` asserts that the union of the entries' `secrets` equals the schema, so no secret is prompted for without being used and none is used without being prompted for.

| Secret | Used by |
|--------|---------|
| `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` | `deploy-docs`, `docs-preview` |
| `GITHUB_TOKEN` (fine-grained PAT, read and write) | `release-packages` |

`docs-preview` also sets `forgeToken = true`, which gives it nixbot's per-run GitHub token as `GITHUB_FORGE_TOKEN` for the check run; that token is not an entry of the schema.

To rotate a value, regenerate the generator's prompts with `clan vars generate --regenerate` and redeploy magnetite.

## Running the same programs locally

Local runs use `secrets/shared.yaml` through `sops exec-env` for Cloudflare credentials:

# Upload a preview version of HEAD aliased at b-<branch>
just docs-deploy-preview

# Deploy HEAD to production (normally done by the deploy-docs effect);
# exits 0 without deploying unless HEAD is main's head on GitHub
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
