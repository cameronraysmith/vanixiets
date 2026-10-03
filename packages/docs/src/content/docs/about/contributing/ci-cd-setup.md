---
title: CI/CD Setup
description: How nixbot builds, checks, and deploys vanixiets, and why deploy secrets are held only by code from main
sidebar:
  order: 6
---

vanixiets builds on [nixbot](https://github.com/Mic92/nixbot) running on magnetite, lands changes through the gitea-mq merge queue, and deploys through hercules-ci-style effects.
The GitHub Actions release and docs-deploy workflows are archived under `.github/deprecated/`.

## The rule: secrets are only held by code from main

Effects are the only CI programs that receive deploy secrets (the Cloudflare API token, the GitHub release token, and the R2 token for browser evidence).
onPush effects run only for pushes to `main`, and onEvent effects, including `build_finished`, are always evaluated from `main`, so the code that holds a secret has always already been reviewed and landed.
Secrets are declared per trigger, so a pull request trigger receives only the secrets it declares: the `release-packages` pull request trigger declares none.

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

- `checks.<system>.deploy-docs-rehearsal` runs every `deploy-docs` mode (`production`, `preview`, `pull-request`, `pull-request-closed`, `versions`, and `deployments`) against a stub wrangler that also executes each invocation with the real pinned wrangler and the identical argv: `deploy` with `--dry-run`, and `preview`, `preview delete`, `versions list`, and `deployments list` against a loopback fake Cloudflare API, so an argv wrangler would reject fails the check. It covers the superseded production run; the untrusted `--payload` hardening, including symlink refusal and a payload build command that never runs; the pull request trust rule (a same-repository bot pull request and fork pull requests with a writer as actor or author preview, an untrusted fork is skipped as `neutral`, and a missing `isFork` fails); `succeeded`, `skipped_local`, failed, and missing docs attributes, a malformed event, a failed deploy, and the `docs-preview` check-run lifecycle; a pull request found closed or superseded before the upload, which is skipped without any Cloudflare or nixbot API request, one closed during the upload, whose Preview is withdrawn, and a failed pull request state lookup; teardown of an existing Preview, of one that never existed, and a failed delete; `--limit` truncation of the listings; and missing secrets failing before any network call;
- `checks.<system>.release-rehearsal` runs `release-packages --rev` with the production semantic-release plugin list against a local git fixture and a stub GitHub API, including the floating major and minor tags from `semantic-release-major-tag`, a superseded rev that main has moved past, and a diverged rev outside main's history; it also runs `release-packages plan` on fixture pull requests through the installation-token path, covering a minor, a major, and no bump, a pull request that edits the release configuration (forecast from main's configuration, its plugin never run), a closed or superseded pull request, which is skipped without cloning, a failed pull request state lookup, a merge conflict, a head mismatch, a missing forge token, and a release PAT in the environment that is never used, and it asserts that a forecast leaves the fixture remote's tags and refs untouched and creates no release;
- `checks.<system>.publish-evidence-rehearsal` runs `publish-evidence build-finished` and `publish-evidence main` against a loopback nixbot API, a chroot store, a stub comment endpoint, and a stub S3 endpoint that verifies the temporary credentials' JWT claims and SigV4 signature, refuses writes under a read-only credential, and refuses keys outside each credential's prefix. It covers report selection and validation; a `main` upload to `ttl-90d` with the receipt last and create-only, and a later `main` build with the same report that uploads nothing; `main` mode's lookup failures (a commit with no build, a missing `NIXBOT_API_URL`, and a missing or non-`main` `--rev`); an unaffected pull request whose report `main` already published, which uploads and comments nothing; an affected pull request uploaded to `ttl-30d` with a comment and marker, its retry, and a second build with the same report; a refused comment, a corrupted remote receipt, and a failed upload; a pull request that returns to `main`'s report and supersedes its comment, also without an API token and with a malformed marker; credential confinement, including that no pull request run writes into `ttl-90d`; a build without a pull request; a failing baseline probe; missing R2 secrets; and the parent secret's absence from every request.

The `docs` effect lists `deploy-docs-rehearsal`, `release-packages` lists `release-rehearsal`, and `browser-evidence` lists `publish-evidence-rehearsal`.
The rehearsals run the real programs without a token or network access, so a change that breaks the release, deploy, preview, or teardown path fails before it reaches `main`.

`checks.<system>.effects-interpreter` covers the one piece of code between nixbot and a program: the script the interpreter generates for each effect trigger.

### Docs previews

The `docs` effect's pull request trigger deploys each pull request's docs as a Cloudflare Preview, and its pull-request-closed trigger deletes that Preview; see [docs](#docs) below.
The preview reports as the `docs-preview` check run, which is not a required context and never blocks a merge.

### Release plan

The `release-packages` effect's pull request trigger forecasts, per package, what semantic-release would publish if the pull request landed, and reports it as the `release-plan` check run on the head commit; see [release-packages](#release-packages) below.
It is not a required context and never blocks a merge.

### Fork pull requests

nixbot's `prApproval` (configured in `modules/nixos/nixbot.nix`) is enabled and holds pull requests from authors outside the `OWNER`, `MEMBER`, and `COLLABORATOR` associations until a maintainer approves CI for them.
Pull requests whose head branch lives in this repository are always trusted, bots included, since pushing that branch already required write access.
A held pull request is approved with its check run's button.

## Landing

gitea-mq tests batches of queued pull requests and lands a batch by fast-forwarding `main` to the exact tested commit.
The resulting push to `main` reuses the batch's build, and nixbot then runs the effects for that commit.

Batches can land in quick succession, so an effect may start after `main` has already moved past the commit it was built for.
The production deploy and the release handle this the same way: a `lock` orders runs across builds, and the program exits 0 without acting when its `--rev` is no longer `main`'s head, leaving the work to the run for the newer commit.
The `browser-evidence` effect does not skip a superseded commit: evidence for each landed commit is kept under its own build's keys, and its lock only serialises runs.

## Effects

Effects are data.
`modules/effects/vanixiets/effects.nix` declares them as entries of the flake option `vanixiets.effects.<name>`, each naming its program, its rehearsals, and its `triggers`.
An entry has at least one of the triggers `main`, `pullRequest`, `pullRequestClosed`, and `buildFinished`, and each trigger sets the program's literal arguments, the secrets it reads, its lock, and whether it receives nixbot's forge token.

One interpreter, `modules/effects/vanixiets/registry.nix`, turns each trigger into a nixbot effect: `main` into `herculesCI.onPush.default.outputs.effects.<name>`, `pullRequest` into `herculesCI.onEvent.pull_request.<name>`, `pullRequestClosed` into `herculesCI.onEvent.pull_request_closed.<name>`, and `buildFinished` into `herculesCI.onEvent.build_finished.<name>`.
A `buildFinished` trigger also carries nixbot's delivery conditions (`when`); one that reads a secret must require `write` or `admin` permission, since branch and status filters select builds rather than authorize anyone.
The script it generates for each trigger does three things, in order:

1. for `main` triggers, runs the fail-closed guard (`mainOnlyGuard` from `modules/lib/effect-run-context.nix`), which asks nixbot for an identity token and refuses to run unless the token says the event is a push to `refs/heads/main`: any other run is skipped with exit 0 before a secret is read, and a missing or unreadable token fails the effect;
2. exports each secret the trigger declares, failing with a specific error on the first one that is absent, null, or empty;
3. execs the program with the trigger's arguments, followed by `--rev <commit>` for `main` triggers.

`checks.<system>.effects-interpreter` renders synthetic entries with all three trigger kinds through the same function and runs the generated scripts against stubs, asserting the guard's skip on a non-main run, the exported secrets, that a trigger never receives another trigger's secrets, the failure on a missing secret, the forge token of each trigger, and the exact argv the program receives, including `--rev`.

Programs that report a GitHub check run share one program for it, `github-check-run` (`modules/apps/ci/github-check-run.{nix,sh}`, also `apps.github-check-run`).
`github-check-run create --repo <owner/name> --name <check> --head-sha <sha>` creates an `in_progress` check run and prints its id; `github-check-run complete --repo <owner/name> --id <id> --conclusion <success|neutral|failure> --title <title> --summary <summary> [--details-url <url>]` completes it.
It authenticates with `GITHUB_FORGE_TOKEN` and fails on any non-2xx response; `deploy-docs pull-request` and `release-packages plan` both call it, and both complete their check run from an exit trap that never masks the program's exit status.

nixbot does not guarantee the order in which it delivers pull request events, and each event's payload describes the pull request as it was when the event was delivered, not when the effect runs.
A fast merge can deliver `pull_request_closed` before the `pull_request` event for the pull request's last green head, so both pull request modes check the pull request's live state before acting, with the shared `github-pull-request` program (`modules/apps/ci/github-pull-request.{nix,sh}`, also `apps.github-pull-request`).
`github-pull-request state --repo <owner/name> --number <n> --head-sha <sha>` reads the pull request from the GitHub API with `GITHUB_FORGE_TOKEN` and prints one word: `current` when it is open and its head is `<sha>`, `closed` when it is closed or merged, and `superseded` when it is open at a different head; an API or argument failure exits 1.
A mode that finds its pull request anything but `current` completes its check run as `neutral` and exits 0 without acting.

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

1. creates an `in_progress` GitHub check run named `docs-preview` on the pull request's head commit with `github-check-run`, using nixbot's forge token;
2. asks `github-pull-request state` whether the pull request is still open at the event's head commit; when it is `closed` or `superseded`, it completes the check run as `neutral` ("Docs preview skipped", "pull request #<number> is <state>; no preview"), logs `DEPLOY-DOCS-PREVIEW: skipped (<state>)`, and exits 0 without fetching or deploying anything, and a failed state lookup fails the run;
3. decides whether to trust the pull request from the event's `pullRequest.isFork`, `actor.permission`, and `pullRequest.author.permission`: a pull request whose head branch is in this repository is trusted, bots included, since pushing that branch already required write access; a fork is trusted only when the actor or the author has `write` or `admin`, so a maintainer previews a fork by adding any label to it; an untrusted fork completes the check run as `neutral` ("Docs preview skipped", naming the reason and that remedy) and exits 0 without fetching or deploying anything, and an event without a boolean `isFork` fails;
4. fetches the pull request's nixbot build from nixbot's API, without evaluating any pull-request code, and requires the build to have succeeded and its `checks.x86_64-linux.package-vanixiets-docs` attribute to be `succeeded` or `skipped_local` (nixbot reports a cached output as `skipped_local`);
5. deploys that payload with `wrangler preview --name pr-<number> --worker-name infra-docs --ignore-base-config` as the Cloudflare Preview `pr-<number>` of the `infra-docs` Worker, from a synthesized assets-only wrangler config with an empty `previews` block and no build command, bindings, or routes, so neither the payload nor the dashboard's Preview base config adds anything to it;
6. checks the pull request's state again: if it closed during the upload, it deletes the Preview `pr-<number>` exactly as `pull-request-closed` does, logs `DEPLOY-DOCS-PREVIEW: withdrawn (closed during upload)`, and completes the check run as `neutral`, failing if the delete fails; otherwise it completes the check run as `success` with the Preview URL, `https://pr-<number>-infra-docs.sciexp.workers.dev`, as its details link, keeping the Preview when a newer head has superseded this one, since that head's run updates the same Preview.

Any failure completes the check run as `failure` with the error in its summary.

The program applies the trust rule itself because bots report no permission even when their head branch is in this repository, and a nixbot condition cannot express "same repository or a writer".
Each run for a pull request updates the same Preview, whose URL always serves its latest deployment.

When the pull request is closed or merged, `deploy-docs pull-request-closed` deletes the Preview with `wrangler preview delete --name pr-<number> --skip-confirmation --worker-name infra-docs` and logs `DEPLOY-DOCS-PREVIEW: deleted (pr-<number>)`.
A pull request that never got a Preview, such as a skipped fork or a failed build, logs `DEPLOY-DOCS-PREVIEW: absent (pr-<number>)` and exits 0.
Both pull request triggers share `lock = "docs-preview-{pr}"`, so teardown waits for an upload still in flight for the same pull request.
The lock serialises the two triggers but does not order them: when teardown runs first, the later `pull-request` run finds the pull request `closed` and skips, and when the pull request closes while an upload is in flight, that run withdraws the Preview it just uploaded.

Cloudflare applies these properties to [Previews](https://developers.cloudflare.com/workers/previews/):

- a Worker holds at most 100 Previews on the Free plan and 500 on paid plans, and a Preview holds at most 100 deployments; at either limit Cloudflare deletes the least recently deployed Preview or the oldest deployment to make room;
- Preview URLs are public, and their `workers.dev` URLs send `X-Robots-Tag: noindex`;
- deletion can lag: a Preview's URL has been observed to keep serving for hours after `wrangler preview delete` reported success ([cloudflare/developer-platform#73](https://github.com/cloudflare/developer-platform/issues/73)).

The previews are informational: a failed, skipped, or undeleted preview never blocks a merge.

`deploy-docs` owns its interface: `production --rev <sha>`, `preview --rev <sha> --name <name> [--payload <dir>]` (both with an optional `--deployed-by <name>`), `pull-request`, `pull-request-closed`, `versions [--limit <n>]`, `deployments [--limit <n>]`, and `tail`.
It sanitizes a Preview name to at most 40 lowercase letters, digits, and hyphens, reads only `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` from the environment (plus nixbot's event variables and forge token in the pull request modes), and fails before any network call when a secret is missing; `deploy-docs --help` prints the usage.

### release-packages

The `release-packages` effect runs the `release-packages` program on two triggers:

| Trigger | nixbot effect | Program | Secrets | Lock |
|---------|---------------|---------|---------|------|
| `main` | `herculesCI.onPush.default.outputs.effects.release-packages` | `release-packages --rev <commit>` | `GITHUB_TOKEN` | `release-packages` |
| `pullRequest` | `herculesCI.onEvent.pull_request.release-packages` | `release-packages plan` | none (forge token only) | `release-plan-{pr}` |

`release-packages --rev <commit>` clones the repository, checks out the commit as `main`, discovers packages with `list-packages-json`, and runs the `release` program for each, which runs semantic-release with the production plugins.
It skips with exit 0 and logs `RELEASE-PACKAGES-ACTION: superseded` when `main` has moved past its commit, and refuses a commit outside `main`'s history.
`list-packages-json` lists only packages whose `package.json` declares a non-null `release` key, so a workspace package opts in to releases explicitly; a `package.json` that fails to parse fails the run, naming the file.

`release-packages plan` runs on every pull request once its head has built green, forks included once CI is approved for them, and reports the `release-plan` check run on the head commit:

1. it creates the check run with `github-check-run`, using nixbot's forge token;
2. it asks `github-pull-request state` whether the pull request is still open at the event's head commit; when it is `closed` or `superseded`, it completes the check run as `neutral` ("Release plan skipped", "pull request #<number> is <state>; no forecast"), logs `RELEASE-PLAN: skipped (<state>)`, and exits 0 without cloning, and a failed state lookup fails the run;
3. it clones the public repository without a token, fetches `refs/pull/<number>/head`, and requires it to equal the head commit in nixbot's event;
4. it simulates the merge into `main` with `git merge-tree`, failing on a conflict, and checks out the merge commit as `main` with the index and working tree reset to `main`'s tree, so semantic-release analyses the pull request's commits while its configuration and plugins come from `main`'s files;
5. it runs the `release` program for each package with semantic-release's `--dry-run`, with nixbot's installation token as `GITHUB_TOKEN`, and with git's URLs for the repository rewritten to a local bare clone, so semantic-release's push-permission check and every other git network operation reach that clone and nothing is ever pushed;
6. it logs `RELEASE-PLAN: <package> <last|none> -> <next|no release>` per package and completes the check run as `success` with a package, last, next, and bump table, or as `failure` with the reason.

semantic-release logs `Published release <version> on <channel> channel` even under `--dry-run` (semantic-release 25.0.9 `index.js`, line 221), but the forecast publishes nothing; the `RELEASE-PLAN` lines and the check run are its output.

The release PAT is never given to this trigger and plan mode never reads it.
The forecast is informational and never blocks a merge.
See [Semantic Release Preview](/about/contributing/semantic-release-preview/) for reading the forecast and previewing a release locally.

### browser-evidence

The `browser-evidence` effect runs the `publish-evidence` program, which publishes the docs browser report nixbot already built (`checks.x86_64-linux.package-vanixiets-docs-test-e2e-report`) as screenshots and JSON metadata:

| Trigger | nixbot effect | Program | Lock |
|---------|---------------|---------|------|
| `main` | `herculesCI.onPush.default.outputs.effects.browser-evidence` | `publish-evidence main --upload --rev <commit>` | `browser-evidence` |
| `buildFinished` | `herculesCI.onEvent.build_finished.browser-evidence` | `publish-evidence build-finished --upload` | `browser-evidence` |

The `buildFinished` trigger is delivered for succeeded and failed builds, since a failing suite still leaves a report, and only when the build's actor or pull request author has `write` permission or above.
A landing on `main` reuses the merge-queue build and nixbot sends no `build_finished` for a reused build, so the `main` trigger looks the landed commit up in nixbot's builds API instead.

Neither mode evaluates or builds anything: both realise the recorded report output, validate it with the program's own validator, and upload only `run.json`, `completion.json`, the referenced PNG screenshots, and a `receipt.json` (schema version 3) that identifies the report by attribute and output path and names no build.
Objects go to the R2 bucket `sciexp` under `projects/vanixiets/browser-evidence/<tier>/v1/<obs>/`, where `<obs>` is derived from the report's attribute and Nix output path only; every build with the same report writes the same keys, each tier receives a report at most once, and an identical existing receipt logs `PUBLISH-EVIDENCE: unchanged`.
`main` and other builds without a pull request use the `ttl-90d` tier; bucket lifecycle rules in `modules/terranix/cloudflare.nix` delete each tier's objects by age.

A pull request build first checks whether `main` has already published this exact report, by probing for its receipt under `ttl-90d`.
If so, the pull request is unaffected: the program uploads nothing, posts no comment, and logs `PUBLISH-EVIDENCE: unaffected (report <obs> already published from main)`.
Otherwise it uploads to `ttl-30d` and posts one comment through nixbot's `pr-comment` API with the verdict, the build, links to the screenshots and receipt, the retention, and a note that no identical report has been published from `main` in the last 90 days; it edits that same comment on later builds.
A report that differs from every report published from `main` in the last 90 days is treated as affected, for example when `main`'s evidence has expired or its publish run failed.
Because `pr-comment` can only upsert, the program records its comment in a marker object under `ttl-30d/pr/`; a later unaffected build that finds a current marker replaces the comment with a superseded note and logs `PUBLISH-EVIDENCE: superseded #<number>`.
When two builds of one pull request finish out of order, the one that finishes last decides the comment.

The program never uses the R2 token for requests: each run signs temporary credentials valid for 15 minutes, read-write on its own tier's prefix and, for a pull request, read-only on `projects/vanixiets/browser-evidence/ttl-90d/`, then unsets the token, so a pull request run cannot write into `main`'s tier.
The Worker `sciexp-evidence` (`packages/evidence-worker/`, deployed with wrangler) serves the evidence read-only at `https://evidence.vanixiets.net/vanixiets/browser-evidence/<tier>/v1/<obs>/<file>`, the object key after `projects/`: GET and HEAD only, `.png` and `.json` only, no directory listing, with `nosniff` and a sandboxing content security policy.
`vanixiets.net` is dedicated to untrusted CI content and hosts no authentication, sessions, or cookies.

A failed upload or comment fails the effect run.
nixbot runs event effects from the default branch and posts no forge status for them (`nixbot/nixbot/event_effects.py`), so a pull request that changes this effect or its program is first exercised after it lands, and a failed `buildFinished` run never blocks a merge; a failed `main` run fails `nixbot/effects` on the `main` push.
See [Docs browser evidence](https://github.com/cameronraysmith/vanixiets/blob/main/packages/docs/tests/report/README.md#publication) for reading the evidence.

## Secrets

Effect secrets are declared once, in `flake.lib.vanixietsEffectSecrets` (`modules/effects/vanixiets/secrets.nix`).
The `vanixiets-effects-secrets` clan vars generator's prompts and the secrets JSON it composes are generated from that schema; the generator runs on magnetite and nixbot receives the result as a systemd credential.
Each trigger's `secrets` is typed as an enum of the schema's names, and the interpreter derives each trigger's `secretsMap` from it, so a trigger can read exactly the secrets it declares and no other trigger's.
`checks.x86_64-linux.nixbot-wiring` asserts that the union of every trigger's `secrets` across all entries equals the schema, so no secret is prompted for without being used and none is used without being prompted for.

| Secret | Used by |
|--------|---------|
| `CLOUDFLARE_API_TOKEN` | `docs`: `main`, `pullRequest`, and `pullRequestClosed` |
| `CLOUDFLARE_ACCOUNT_ID` | `docs`: `main`, `pullRequest`, and `pullRequestClosed`; `browser-evidence`: `main` and `buildFinished` |
| `GITHUB_TOKEN` (fine-grained PAT, read and write) | `release-packages`: `main` only |
| `R2_EVIDENCE_ACCESS_KEY_ID`, `R2_EVIDENCE_SECRET_ACCESS_KEY` (R2 token, Object Read & Write on `sciexp` only) | `browser-evidence`: `main` and `buildFinished` |

The `pullRequest` triggers of `docs` and `release-packages` also set `forgeToken = true`, which gives them nixbot's per-run GitHub App installation token as `GITHUB_FORGE_TOKEN` for their `docs-preview` and `release-plan` check runs; that token is not an entry of the schema.
The `browser-evidence` program also reads `NIXBOT_API_URL` and `NIXBOT_API_TOKEN`, which nixbot sets for each effect run, to query its build API and post the pull request comment; neither is an entry of the schema.

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
