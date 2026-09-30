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
onPush effects run only for pushes to `main`, and onEvent effects are always evaluated from `main`, so the code that holds a secret has always already been reviewed and landed.

An effect contains no behaviour of its own.
Each effect is a data entry naming a program, and every behaviour lives in that program, which a hermetic rehearsal check runs against stubs.
There is no separate dry-run implementation of an effect; pre-merge confidence comes from those rehearsals.

## Gating

`nixbot.toml` at the repository root sets:

```toml
attribute = "checks.x86_64-linux"
effects_on_pull_requests = false
```

nixbot reads the effects gating keys from the default branch, never from the ref being built, so a pull request cannot grant itself effects.
With `effects_on_pull_requests = false` and `effects_branches` left at its empty default:

- a push to `main` runs the onPush effects;
- no pull request runs its own onPush effects, whether it comes from a fork or from a branch in this repository;
- a push to any other branch, including a merge-queue batch branch, runs no effects.

The comments in `nixbot.toml` cite the nixbot functions that implement each rule.

## What pull requests and merge-queue batches run

A pull request or batch build evaluates and builds `checks.x86_64-linux`.
For each onPush effect gated off on that ref, nixbot builds the effect's dependencies as a check and still posts the `nixbot/effects` status.
A required `nixbot/effects` context is therefore satisfied without running anything that reads a secret.

The required contexts are `nixbot/nix-eval`, `nixbot/nix-build`, and `nixbot/effects`.

### Rehearsals

Each effect lists the rehearsal checks for its program among its inputs, so every pull request and batch builds them as part of the required `nixbot/effects` gate:

- `checks.<system>.deploy-docs-rehearsal` runs every `deploy-docs` mode (`production`, `preview`, `pull-request`, `pull-request-closed`, `versions`, and `deployments`) against a stub wrangler that also executes each invocation with the real pinned wrangler and the identical argv: `deploy` with `--dry-run`, and `preview`, `preview delete`, `versions list`, and `deployments list` against a loopback fake Cloudflare API, so an argv wrangler would reject fails the check. It covers the superseded production run; the untrusted `--payload` hardening, including symlink refusal and a payload build command that never runs; the pull request trust rule (a same-repository bot pull request and fork pull requests with a writer as actor or author preview, an untrusted fork is skipped as `neutral`, and a missing `isFork` fails); `succeeded`, `skipped_local`, failed, and missing docs attributes, a malformed event, a failed deploy, and the `docs-preview` check-run lifecycle; teardown of an existing Preview, of one that never existed, and a failed delete; `--limit` truncation of the listings; and missing secrets failing before any network call;
- `checks.<system>.release-rehearsal` runs `release-packages --rev` with the production semantic-release plugin list against a local git fixture and a stub GitHub API, including the floating major and minor tags from `semantic-release-major-tag`, a superseded rev that main has moved past, and a diverged rev outside main's history.

The `docs` effect lists `deploy-docs-rehearsal` and `release-packages` lists `release-rehearsal`.
The rehearsals run the real programs without a token or network access, so a change that breaks the release, deploy, preview, or teardown path fails before it reaches `main`.

`checks.<system>.effects-interpreter` covers the one piece of code between nixbot and a program: the script the interpreter generates for each effect trigger.

### Docs previews

The `docs` effect's pull request trigger deploys each pull request's docs as a Cloudflare Preview, and its pull-request-closed trigger deletes that Preview; see [docs](#docs) below.
The preview reports as the `docs-preview` check run, which is not a required context and never blocks a merge.

### Fork pull requests

nixbot's `prApproval` (configured in `modules/nixos/nixbot.nix`) is enabled and holds pull requests from authors outside the `OWNER`, `MEMBER`, and `COLLABORATOR` associations until a maintainer approves CI for them.
Pull requests whose head branch lives in this repository are always trusted, bots included, since pushing that branch already required write access.
A held pull request is approved with its check run's button.

## Landing

gitea-mq tests batches of queued pull requests and lands a batch by fast-forwarding `main` to the exact tested commit.
The resulting push to `main` reuses the batch's build, and nixbot then runs the effects for that commit.

Batches can land in quick succession, so an effect may start after `main` has already moved past the commit it was built for.
The production deploy and the release handle this the same way: a `lock` orders runs across builds, and the program exits 0 without acting when its `--rev` is no longer `main`'s head, leaving the work to the run for the newer commit.

## Effects

Effects are data.
`modules/effects/vanixiets/effects.nix` declares them as entries of the flake option `vanixiets.effects.<name>`, each naming its program, the secrets it reads, its rehearsals, and its `triggers`.
An entry has at least one of the triggers `main`, `pullRequest`, and `pullRequestClosed`, and each trigger sets the program's literal arguments, its lock, and whether it receives nixbot's forge token.

One interpreter, `modules/effects/vanixiets/registry.nix`, turns each trigger into a nixbot effect: `main` into `herculesCI.onPush.default.outputs.effects.<name>`, `pullRequest` into `herculesCI.onEvent.pull_request.<name>`, and `pullRequestClosed` into `herculesCI.onEvent.pull_request_closed.<name>`.
The script it generates for each trigger does three things, in order:

1. for `main` triggers, runs the fail-closed guard (`mainOnlyGuard` from `modules/lib/effect-run-context.nix`), which asks nixbot for an identity token and refuses to run unless the token says the event is a push to `refs/heads/main`: any other run is skipped with exit 0 before a secret is read, and a missing or unreadable token fails the effect;
2. exports each declared secret, failing with a specific error on the first one that is absent, null, or empty;
3. execs the program with the trigger's arguments, followed by `--rev <commit>` for `main` triggers.

`checks.<system>.effects-interpreter` renders synthetic entries with all three trigger kinds through the same function and runs the generated scripts against stubs, asserting the guard's skip on a non-main run, the exported secrets, the failure on a missing secret, the forge token of each trigger, and the exact argv the program receives, including `--rev`.

### docs

The `docs` effect runs the `deploy-docs` program on all three triggers:

| Trigger | nixbot effect | Program | Lock |
|---------|---------------|---------|------|
| `main` | `herculesCI.onPush.default.outputs.effects.docs` | `deploy-docs production --rev <commit>` | `deploy-docs` |
| `pullRequest` | `herculesCI.onEvent.pull_request.docs` | `deploy-docs pull-request` | `docs-preview-{pr}` |
| `pullRequestClosed` | `herculesCI.onEvent.pull_request_closed.docs` | `deploy-docs pull-request-closed` | `docs-preview-{pr}` |

`deploy-docs production` deploys the nix-built `vanixiets-docs` payload with `wrangler deploy` to 100% of production traffic.
It skips with exit 0, logging `DEPLOY-DOCS-ACTION: superseded`, when `main`'s head is no longer its commit.

The two pull request triggers are onEvent effects: nixbot evaluates them from `main`, never from the pull request, so pull-request code never holds their secrets.
On a pull request event, `deploy-docs pull-request`:

1. creates an `in_progress` GitHub check run named `docs-preview` on the pull request's head commit, using nixbot's forge token;
2. decides whether to trust the pull request from the event's `pullRequest.isFork`, `actor.permission`, and `pullRequest.author.permission`: a pull request whose head branch is in this repository is trusted, bots included, since pushing that branch already required write access; a fork is trusted only when the actor or the author has `write` or `admin`, so a maintainer previews a fork by adding any label to it; an untrusted fork completes the check run as `neutral` ("Docs preview skipped", naming the reason and that remedy) and exits 0 without fetching or deploying anything, and an event without a boolean `isFork` fails;
3. fetches the pull request's nixbot build from nixbot's API, without evaluating any pull-request code, and requires the build to have succeeded and its `checks.x86_64-linux.package-vanixiets-docs` attribute to be `succeeded` or `skipped_local` (nixbot reports a cached output as `skipped_local`);
4. deploys that payload with `wrangler preview --name pr-<number> --worker-name infra-docs --ignore-base-config` as the Cloudflare Preview `pr-<number>` of the `infra-docs` Worker, from a synthesized assets-only wrangler config with an empty `previews` block and no build command, bindings, or routes, so neither the payload nor the dashboard's Preview base config adds anything to it;
5. completes the check run as `success` with the Preview URL, `https://pr-<number>-infra-docs.sciexp.workers.dev`, as its details link, or as `failure` with the error in its summary.

The program applies the trust rule itself because bots report no permission even when their head branch is in this repository, and a nixbot condition cannot express "same repository or a writer".
Each run for a pull request updates the same Preview, whose URL always serves its latest deployment.

When the pull request is closed or merged, `deploy-docs pull-request-closed` deletes the Preview with `wrangler preview delete --name pr-<number> --skip-confirmation --worker-name infra-docs` and logs `DEPLOY-DOCS-PREVIEW: deleted (pr-<number>)`.
A pull request that never got a Preview, such as a skipped fork or a failed build, logs `DEPLOY-DOCS-PREVIEW: absent (pr-<number>)` and exits 0.
Both pull request triggers share `lock = "docs-preview-{pr}"`, so teardown waits for an upload still in flight for the same pull request.

Cloudflare applies these properties to [Previews](https://developers.cloudflare.com/workers/previews/):

- a Worker holds at most 100 Previews on the Free plan and 500 on paid plans, and a Preview holds at most 100 deployments; at either limit Cloudflare deletes the least recently deployed Preview or the oldest deployment to make room;
- Preview URLs are public, and their `workers.dev` URLs send `X-Robots-Tag: noindex`;
- deletion can lag: a Preview's URL has been observed to keep serving for hours after `wrangler preview delete` reported success ([cloudflare/developer-platform#73](https://github.com/cloudflare/developer-platform/issues/73)).

The previews are informational: a failed, skipped, or undeleted preview never blocks a merge.

`deploy-docs` owns its interface: `production --rev <sha>`, `preview --rev <sha> --name <name> [--payload <dir>]` (both with an optional `--deployed-by <name>`), `pull-request`, `pull-request-closed`, `versions [--limit <n>]`, `deployments [--limit <n>]`, and `tail`.
It sanitizes a Preview name to at most 40 lowercase letters, digits, and hyphens, reads only `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` from the environment (plus nixbot's event variables and forge token in the pull request modes), and fails before any network call when a secret is missing; `deploy-docs --help` prints the usage.

### release-packages

Runs `release-packages --rev <commit>`, which clones the repository, checks out the commit as `main`, discovers packages with `list-packages-json`, and runs the `release` program for each, which runs semantic-release with the production plugins.
It runs under `lock = "release-packages"`, skips with exit 0 and logs `RELEASE-PACKAGES-ACTION: superseded` when `main` has moved past its commit, and refuses a commit outside `main`'s history.
See [Semantic Release Preview](/about/contributing/semantic-release-preview/) for previewing a release.

## Secrets

Effect secrets are declared once, in `flake.lib.vanixietsEffectSecrets` (`modules/effects/vanixiets/secrets.nix`).
The `vanixiets-effects-secrets` clan vars generator's prompts and the secrets JSON it composes are generated from that schema; the generator runs on magnetite and nixbot receives the result as a systemd credential.
An effect entry's `secrets` is typed as an enum of the schema's names, and the interpreter derives each effect's `secretsMap` from it, so an effect can read exactly the secrets it declares.
`checks.x86_64-linux.nixbot-wiring` asserts that the union of the entries' `secrets` equals the schema, so no secret is prompted for without being used and none is used without being prompted for.

| Secret | Used by |
|--------|---------|
| `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` | `docs` |
| `GITHUB_TOKEN` (fine-grained PAT, read and write) | `release-packages` |

The `docs` effect's `pullRequest` trigger also sets `forgeToken = true`, which gives it nixbot's per-run GitHub token as `GITHUB_FORGE_TOKEN` for the `docs-preview` check run; that token is not an entry of the schema.

To rotate a value, regenerate the generator's prompts with `clan vars generate --regenerate` and redeploy magnetite.

## Running the same programs locally

Local runs use `secrets/shared.yaml` through `sops exec-env` for Cloudflare credentials, and every docs recipe runs `deploy-docs` rather than wrangler directly, so local runs share the wrangler invocation the rehearsal checks:

```bash
# Deploy HEAD as the Cloudflare Preview named after the current branch (or: just docs-deploy-preview <name>)
just docs-deploy-preview

# Deploy HEAD to production (normally done by the docs effect);
# exits 0 without deploying unless HEAD is main's head on GitHub
just docs-deploy-production

# Inspect Cloudflare state (newest first, default limit 10)
just docs-deployments
just docs-versions
just docs-tail

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
