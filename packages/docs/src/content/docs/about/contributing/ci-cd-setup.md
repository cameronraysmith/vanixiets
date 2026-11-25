---
title: CI/CD Setup
description: How nixbot builds, checks, and deploys vanixiets, and why deploy secrets are held only by code from main
sidebar:
  order: 6
---

vanixiets builds on [nixbot](https://github.com/Mic92/nixbot) running on magnetite, lands changes through the gitea-mq merge queue, and deploys through hercules-ci-style effects.
The GitHub Actions release and docs-deploy workflows are archived under `.github/deprecated/`.

## The rule: secrets are only held by code from main

Effects are the only CI programs that receive deploy secrets (the Cloudflare API token, the GitHub release token, the R2 token for browser evidence, and the flake updater App's key).
onPush effects run only for pushes to `main`, onEvent effects, including `build_finished`, are always evaluated from `main`, and onSchedule effects are evaluated and run from `main`'s tip, so the code that holds a secret has always already been reviewed and landed.
Secrets are declared per trigger, so a pull request trigger receives only the secrets it declares: the `release-packages` pull request trigger declares none.

An effect contains no behaviour of its own.
Each effect is a data entry naming a program, and every behaviour lives in that program, which a hermetic rehearsal check runs against stubs.
There is no separate dry-run implementation of an effect; pre-merge confidence comes from those rehearsals.

## Gating

`nixbot.toml` at the repository root sets:

```toml
attribute = "checks"
effects_on_pull_requests = false
```

nixbot reads the effects gating keys from the default branch, never from the ref being built, so a pull request cannot grant itself effects.
With `effects_on_pull_requests = false` and `effects_branches` left at its empty default:

- a push to `main` runs the onPush effects;
- no pull request runs its own onPush effects, whether it comes from a fork or from a branch in this repository;
- a push to any other branch, including a merge-queue batch branch, runs no effects.

The comments in `nixbot.toml` cite the nixbot functions that implement each rule.

## What pull requests and merge-queue batches run

A pull request or batch build evaluates and builds `checks`, scoped by `evalSystems` in `modules/nixos/nixbot.nix` to `checks.x86_64-linux` and `checks.aarch64-darwin`; aarch64-linux is never evaluated.
The darwin checks, the `darwin-<host>` machine checks included, are required like every other check: magnetite dispatches them to stibnite, which builds them on battery or AC at Background QoS.
A failed darwin attribute fails the build, and so does a darwin attribute no Mac could build, so with stibnite asleep or unreachable nothing lands.
In an emergency, `attribute = "checks.x86_64-linux"` in `nixbot.toml` restricts nixbot to the Linux checks from the first commit that carries it, with no deploy.

For each onPush effect gated off on that ref, nixbot builds the effect's dependencies as a check and still posts the `nixbot/effects` status.
A required `nixbot/effects` context is therefore satisfied without running anything that reads a secret.

The required contexts are `nixbot/nix-eval`, `nixbot/nix-build`, and `nixbot/effects`.

### Rehearsals

Each effect lists the rehearsal checks for its program among its inputs, so every pull request and batch builds them as part of the required `nixbot/effects` gate:

- `checks.<system>.deploy-docs-rehearsal` runs every `deploy-docs` mode (`production`, `preview`, `pull-request`, `pull-request-closed`, `versions`, and `deployments`) against a stub wrangler that also executes each invocation with the real pinned wrangler and the identical argv: `deploy` with `--dry-run`, and `preview`, `preview delete`, `versions list`, and `deployments list` against a loopback fake Cloudflare API, so an argv wrangler would reject fails the check. It covers the superseded production run; the untrusted `--payload` hardening, including symlink refusal and a payload build command that never runs; the pull request trust rule (a same-repository bot pull request and fork pull requests with a writer as actor or author preview, an untrusted fork is skipped as `neutral`, and a missing `isFork` fails); `succeeded`, `skipped_local`, failed, and missing docs attributes, a malformed event, a failed deploy, and the `docs-preview` check-run lifecycle; a pull request found closed or superseded before the upload, which is skipped without any Cloudflare or nixbot API request, one closed during the upload, whose Preview is withdrawn, and a failed pull request state lookup; teardown of an existing Preview, of one that never existed, and a failed delete; `--limit` truncation of the listings; and missing secrets failing before any network call;
- `checks.<system>.release-rehearsal` runs `release-packages --rev` with the production semantic-release plugin list against a local git fixture and a stub GitHub API, including the floating major and minor tags from `semantic-release-major-tag`, a superseded rev that main has moved past, and a diverged rev outside main's history; it also runs `release-packages plan` on fixture pull requests through the installation-token path, covering a minor, a major, and no bump, a pull request that edits the release configuration (forecast from main's configuration, its plugin never run), a closed or superseded pull request, which is skipped without cloning, a failed pull request state lookup, a merge conflict, a head mismatch, a missing forge token, and a release PAT in the environment that is never used, and it asserts that a forecast leaves the fixture remote's tags and refs untouched and creates no release;
- `checks.<system>.publish-evidence-rehearsal` runs `publish-evidence event` and `publish-evidence main` against a loopback nixbot API, a chroot store, a stub comment endpoint, and a stub S3 endpoint that verifies the temporary credentials' JWT claims and SigV4 signature, refuses writes under a read-only credential, and refuses keys outside each credential's prefix. It covers report selection and validation; a `main` upload to `ttl-90d` with the receipt last and create-only, and a later `main` build with the same report that uploads nothing; `main` mode's lookup failures (a commit with no build, a missing `NIXBOT_API_URL`, and a missing or non-`main` `--rev`); an unaffected pull request whose report `main` already published, which uploads and comments nothing; an affected pull request uploaded to `ttl-30d` with a comment and marker, its retry, and a second build with the same report; the same affected run delivered as a `pull_request` event; a reused build whose comment names the head it was reused for and whose marker records it, and a reused build that returns to `main`'s report and supersedes the comment; a rejected event kind such as `pull_request_closed`; a refused comment, a corrupted remote receipt, and a failed upload; a pull request that returns to `main`'s report and supersedes its comment, also without an API token and with a malformed marker; credential confinement, including that no pull request run writes into `ttl-90d`; a build without a pull request; a failing baseline probe; missing R2 secrets; and the parent secret's absence from every request.
- `checks.<system>.flake-update-rehearsal` runs the `flake-update` program, built by the same function as production with only a stand-in `nix`, against a fake GitHub on loopback (its API and git's smart HTTP protocol through `git http-backend`) with a test App key generated in the build. Two runs over a lock with `nixpkgs`, `utils` and `playwright-web-flake` must each sign a JWT the fake forge verifies against the test key and App id, mint a token restricted to the repository and to `contents` and `pull_requests` write, make every later API and git request with that token and never with the checkout's, and revoke it at exit; the first must leave `update-nixpkgs` and `update-utils` one commit ahead of `main`, authored and committed by the App's bot user, with a pull request each and no `update-playwright-web-flake`, and the second must change no branch head. An installation lookup answering 404 must fail the run with no push and no pull request call. After every run no file in the checkout, its git objects, the forge or `$HOME` may hold a line of the key, the program's private directory must be gone, and while nixbot's script runs no `FLAKE_UPDATER_*` variable or file may hold the key.

The `docs` effect lists `deploy-docs-rehearsal`, `release-packages` lists `release-rehearsal`, `browser-evidence` lists `publish-evidence-rehearsal`, and `flake-update` lists `flake-update-rehearsal`.
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

A batch forms once the queue has settled: 15 seconds with no new enqueue (`GITEA_MQ_BATCH_SETTLE`, a local patch in `modules/nixos/gitea-mq-batch-settle.patch`), at once when 20 pull requests are queued (`batchMax`), and at most 2 minutes after the oldest queued pull request (`GITEA_MQ_BATCH_SETTLE_MAX`).
So pull requests enqueued together, such as one `gh-queue-open-prs` run, share one build instead of the first one forming a batch of its own.
A pull request that does not merge cleanly onto the batch is ejected while the batch is built, and gitea-mq removes its auto-merge; it re-enters the queue only when enqueued again.

Batches can land in quick succession, so an effect may start after `main` has already moved past the commit it was built for.
The production deploy and the release handle this the same way: a `lock` orders runs across builds, and the program exits 0 without acting when its `--rev` is no longer `main`'s head, leaving the work to the run for the newer commit.
The `browser-evidence` effect does not skip a superseded commit: evidence for each landed commit is kept under its own build's keys, and its lock only serialises runs.

## Effects

Effects are data.
`modules/effects/vanixiets/effects.nix` declares them as entries of the flake option `vanixiets.effects.<name>`, each naming its program, its rehearsals, and its `triggers`.
An entry has at least one of the triggers `main`, `pullRequest`, `pullRequestClosed`, `buildFinished`, and `schedule`, and each trigger sets the program's literal arguments, the secrets it reads, its lock, and whether it receives nixbot's forge token.

One interpreter, `modules/effects/vanixiets/registry.nix`, turns each trigger into a nixbot effect: `main` into `herculesCI.onPush.default.outputs.effects.<name>`, `pullRequest` into `herculesCI.onEvent.pull_request.<name>`, `pullRequestClosed` into `herculesCI.onEvent.pull_request_closed.<name>`, `buildFinished` into `herculesCI.onEvent.build_finished.<name>`, and `schedule` into the schedule `herculesCI.onSchedule.<name>` with the one effect `outputs.effects.<name>`.
A `schedule` trigger carries its UTC `when` (`minute`, `hour`, `dayOfWeek`, `dayOfMonth`) and whether the run gets nixbot's pushable checkout of `main` (`checkout`); nixbot registers schedules after a green non-pull-request build of `main` and runs each occurrence from `main`'s tip, and `nbo schedule run <name> <name> -f` starts one by hand.
A `buildFinished` trigger also carries nixbot's delivery conditions (`when`), such as the build statuses it is delivered for; these select builds rather than authorize anyone, and the trust gate for pull request builds is nixbot's CI approval (`prApproval` in `modules/nixos/nixbot.nix`), which holds a pull request from outside the repository until a maintainer approves it.
The script it generates for each trigger does three things, in order:

1. for `main` triggers, runs the fail-closed guard (`mainOnlyGuard` from `modules/lib/effect-run-context.nix`), which asks nixbot for an identity token and refuses to run unless the token says the event is a push to `refs/heads/main`: any other run is skipped with exit 0 before a secret is read, and a missing or unreadable token fails the effect;
2. exports each secret the trigger declares, failing with a specific error on the first one that is absent, null, or empty;
3. execs the program with the trigger's arguments, followed by `--rev <commit>` for `main` triggers.

`checks.<system>.effects-interpreter` renders synthetic entries with every trigger kind through the same function and runs the generated scripts against stubs, asserting the guard's skip on a non-main run, the exported secrets, that a trigger never receives another trigger's secrets, the failure on a missing secret, the forge token of each trigger, and the exact argv the program receives, including `--rev` for `main` only; it also pins the `onSchedule` output, an entry's `when`, checkout request and absence of an identity-token audience.

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
5. deploys that payload with `wrangler preview --name pr-<number> --worker-name infra-docs --ignore-base-config` as the Cloudflare Preview `pr-<number>` of the `infra-docs` Worker, from a synthesized assets-only wrangler config with an empty `previews` block, `upload_source_maps: false`, and no build command, bindings, or routes, so neither the payload nor the dashboard's Preview base config adds anything to it;
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
| `pullRequest` | `herculesCI.onEvent.pull_request.browser-evidence` | `publish-evidence event --upload` | `browser-evidence` |
| `buildFinished` | `herculesCI.onEvent.build_finished.browser-evidence` | `publish-evidence event --upload` | `browser-evidence` |

All three triggers share the `browser-evidence` lock, so no two runs overlap on a pull request's comment and marker.
A per-pull-request `{pr}` lock is not usable here: nixbot also delivers `build_finished` for builds without a pull request, and it skips an event whose lock names `{pr}` when the event has no pull request.

nixbot delivers `pull_request` after every pull request build that settles succeeded, whether it built afresh or reused an earlier build of an identical tree, and it delivers `build_finished` only for a newly finished build; the `buildFinished` trigger is restricted to failed builds (`when.status = [ "failed" ]`), since a failing suite still leaves a report.
Each settled pull request build therefore gets exactly one run:

| Pull request build | Succeeded | Failed |
|--------------------|-----------|--------|
| fresh | `pullRequest` | `buildFinished` |
| reused | `pullRequest` | none |

A reused failed build gets no run, so its head has no comment of its own; the earlier build's comment remains.
For a reused build the comment names the build's revision and adds `(reused for head <head>, same tree)`.
A label event also delivers `pull_request` for the pull request's latest build, and that repeat run finds its upload and comment already in place.

Neither onEvent trigger sets `when.permission`, which nixbot satisfies with the actor's or pull request author's permission: bots such as Renovate report none, so the condition skipped their pull requests.
The trust gate is nixbot's CI approval instead, and the program never evaluates or executes pull request code.
A landing on `main` reuses the merge-queue build and nixbot sends no `build_finished` for a reused build, so the `main` trigger looks the landed commit up in nixbot's builds API instead.

Neither mode evaluates or builds anything: both realise the recorded report output, validate it with the program's own validator, and upload only `run.json`, `completion.json`, the referenced PNG screenshots, and a `receipt.json` (schema version 3) that identifies the report by attribute and output path and names no build.
Objects go to the R2 bucket `sciexp` under `projects/vanixiets/browser-evidence/<tier>/v1/<obs>/`, where `<obs>` is derived from the report's attribute and Nix output path only; every build with the same report writes the same keys, each tier receives a report at most once, and an identical existing receipt logs `PUBLISH-EVIDENCE: unchanged`.
`main` and failed builds without a pull request use the `ttl-90d` tier; bucket lifecycle rules in `modules/terranix/cloudflare.nix` delete each tier's objects by age.

A pull request build first checks whether `main` has already published this exact report, by probing for its receipt under `ttl-90d`.
If so, the pull request is unaffected: the program uploads nothing, posts no comment, and logs `PUBLISH-EVIDENCE: unaffected (report <obs> already published from main)`.
Otherwise it uploads to `ttl-30d` and posts one comment through nixbot's `pr-comment` API with the verdict, the build, links to the screenshots and receipt, the retention, and a note that no identical report has been published from `main` in the last 90 days; it edits that same comment on later builds.
A report that differs from every report published from `main` in the last 90 days is treated as affected, for example when `main`'s evidence has expired or its publish run failed.
The report's output path is input-addressed, so a dependency bump in the site's closure is affected even when its screenshots are pixel-identical to `main`'s.
`vanixiets-docs-deps` is built from the whole workspace `bun.lock`, so a dependency change in another workspace package, such as `@vanixiets/evidence-worker`, currently counts as affecting the docs report too; per-application dependency derivations would remove that.
Another application would add its own report derivation, one per (project, kind), judged independently; the program's single report attribute is the point to extend.
Because `pr-comment` can only upsert, the program records its comment in a marker object under `ttl-30d/pr/`; a later unaffected build that finds a current marker replaces the comment with a superseded note and logs `PUBLISH-EVIDENCE: superseded #<number>`.
When two builds of one pull request finish out of order, the one that finishes last decides the comment.

The program never uses the R2 token for requests: each run signs temporary credentials valid for 15 minutes, read-write on its own tier's prefix and, for a pull request, read-only on `projects/vanixiets/browser-evidence/ttl-90d/`, then unsets the token, so a pull request run cannot write into `main`'s tier.
The Worker `sciexp-evidence` (`packages/evidence-worker/`, deployed with wrangler) serves the evidence read-only at `https://evidence.vanixiets.net/vanixiets/browser-evidence/<tier>/v1/<obs>/<file>`, the object key after `projects/`: GET and HEAD only, `.png` and `.json` only, no directory listing, with `nosniff` and a sandboxing content security policy.
`vanixiets.net` is dedicated to untrusted CI content and hosts no authentication, sessions, or cookies.

A failed upload or comment fails the effect run.
nixbot runs event effects from the default branch and posts no forge status for them (`nixbot/nixbot/event_effects.py`), so a pull request that changes this effect or its program is first exercised after it lands, and a failed `pullRequest` or `buildFinished` run never blocks a merge; a failed `main` run fails `nixbot/effects` on the `main` push.
Posting the comment requires nixbot's GitHub App to have the repository permission `Pull requests: Read and write`.
nixbot caches installation tokens for 48 minutes (`nixbot/nixbot/forge/github.py:153-154`), so a permission change on the App takes effect once the cached token expires or after nixbot restarts.
See [Docs browser evidence](https://github.com/cameronraysmith/vanixiets/blob/main/packages/docs/tests/report/README.md#publication) for reading the evidence.

### flake-update

The `flake-update` effect refreshes the flake inputs that track a branch, each on its own branch and pull request:

| Trigger | nixbot effect | Program | Lock |
|---------|---------------|---------|------|
| `schedule` (Tuesday and Friday, 10:00 UTC, with a checkout) | `herculesCI.onSchedule.flake-update.outputs.effects.flake-update` | `flake-update` | `flake-update` |

The program (`modules/effects/vanixiets/flake-update.{nix,sh}`) runs nixbot's own `flakeUpdate` script from the locked `nixbot` input with `perInput = true`: for every root input of `main`'s `flake.lock` except `playwright-web-flake`, it rebuilds the branch `update-<input>` from `main`, runs `nix flake update <input> --commit-lock-file`, force-pushes only when the result differs from the branch on GitHub, and opens a pull request titled `Update <input>` whose body is the lock change, treating GitHub's "already exists" answer as success.
When `main` already has an input's update, the branch is deleted; one failing input does not stop the others, and the run fails naming them.
Pull requests are not auto-merged: a person enqueues them into gitea-mq, as Renovate's.
nixbot reads the schedule in UTC with no time zone, so the run starts at 05:00 New York time in winter and 06:00 in summer, before the working day and at least an hour after magnetite's daily store collection (`harmonia-gc`, at 04:00 New York time).

It writes as the GitHub App `vanixiets-flake-updater`, whose commits carry the author and committer `vanixiets-flake-updater[bot] <246545483+vanixiets-flake-updater[bot]@users.noreply.github.com>`.
Each run reads the App id and key (`FLAKE_UPDATER_APP_ID`, `FLAKE_UPDATER_PRIVATE_KEY`), signs a nine-minute JWT with `gh-token`, looks up the App's installation on the repository named by the checkout's `origin`, and mints a one-hour installation token restricted to that repository with `contents` and `pull_requests` write.
It deletes its copy of the key and unsets both variables before nixbot's script starts, hands the token to the script in a private secrets file, and revokes it on exit; nixbot's own App, which may only read contents, never writes these branches.

To run it now, `nbo schedule run flake-update flake-update -f`.
nixbot does not catch up an occurrence it missed while down, and it registers a change to the schedule only after a green non-pull-request build of `main`.

What the repository guarantees here is limited to what it controls: the declared schedule, checkout request and secrets, the generated entry point, the program's credential handling, arguments and commit identity, and the rehearsal.
When nixbot fires the schedule, how its sandbox isolates a run, GitHub's token semantics, the App's installation and permissions, and whether a refreshed input builds are not.
In particular the key is in the run's sandbox for the whole run, in nixbot's read-only secrets file even after the program drops its own copies, and nixbot scopes secrets per repository rather than per effect, so any effect declared on `main` could name them; the per-trigger `secrets` list is a convention that review enforces.

## Dependency updates

[Renovate](https://docs.renovatebot.com/) runs on magnetite as the NixOS `services.renovate` unit, configured by the `renovate` aspect (`modules/nixos/renovate.nix`), and reads its repository configuration from `.github/renovate.json`.
It acts as its own GitHub App, `vanixiets-renovate`, installed on this repository only.
Each run's privileged `ExecStartPre` mints a one-hour installation token from the App's private key, the `renovate-github-app-secret-key` clan vars generator on magnetite, and the key itself never reaches Renovate's process; `RuntimeMaxSec` stops a run at 55 minutes, before the token expires.
To replace the key, generate a new one on the App's settings page, store it with `clan vars set magnetite renovate-github-app-secret-key/key.pem`, delete the old one on GitHub, and redeploy magnetite.

The timer starts a run every hour at 17 minutes past, plus up to ten minutes of random delay, and systemd starts no second run while one is active.
To run it now, `systemctl start renovate.service` on magnetite; `journalctl -u renovate.service` shows the run.
Renovate pull requests go through nixbot like any other and are not enqueued automatically: a person enqueues each one into gitea-mq.

Every commit Renovate pushes is complete, so nixbot passes it without a fix-up commit: post-upgrade tasks in `.github/renovate.json` run in the same branch before the commit.

| Update | Tasks in the same commit |
|--------|--------------------------|
| A `flake.nix` reference bumped by a custom regex manager (an input pinned to a version tag) | `nix flake lock` |
| A `package.json` dependency (bun manager) | `nix run .#regenerate-bun-nix` |
| A `pkgs/by-name/<package>/pin.json` version (`custom.jsonata` manager; see [Package pins](#package-pins)) | `nix run .#realize-pin -- <package> <version>` |
| The `playwright-web-flake` tag | `nix flake lock`, `just bun-repin-playwright`, `bun install --ignore-scripts`, `nix run .#regenerate-bun-nix`, so npm `playwright` equals the flake's driver version |

npm `playwright` and `@playwright/test` are never updated on their own; they follow the flake input.
Renovate may run only the commands in its `allowedCommands` (`flake.lib.renovateSettings`, `modules/lib/renovate-settings.nix`), and a command it refuses still yields a pushed, incomplete commit, so `checks.x86_64-linux.renovate-allowed-commands` fails when any task command in `.github/renovate.json` is not on that list.

Flake inputs are split between two updaters, so no input has two.
Renovate updates the inputs pinned to a revision (its `nix` manager, which re-locks the input itself) or to a version tag (the regex managers above); lock file maintenance is off, so it never refreshes the rest.
Inputs that track a branch are refreshed one pull request per input by the scheduled [`flake-update` effect](#flake-update), which excludes `playwright-web-flake`.

### Package pins

A package with `pkgs/by-name/<package>/pin.json` declares in that file its version, its upstream (a GitHub release, an npm or PyPI package, or a vendor's release manifest read through one of the custom datasources in `.github/renovate.json`), the hash of every artifact it fetches, and the companion files that move with the version; `lib/pins.nix` evaluates the pin into the fetches the package builds from.
Renovate's `custom.jsonata` manager matches `pkgs/by-name/**/pin.json`, so adding a pin is all it takes for Renovate to track a package; there is no list to maintain.
Packages without a pin keep their `update.sh` updater, or have none, and Renovate never touches them; [Bumping a package](/development/operations/bump-procedure/) covers both routes.

The pin rule in `.github/renovate.json` gives each package one branch, `renovate/<package>`, and one pull request titled `chore(deps): update <package> to <version>`, straight to its newest stable version, whose version must contain a dot.
A rule after it labels an update that crosses a major version `major`.
The rule's one post-upgrade task, `nix run .#realize-pin -- <package> <version>`, runs in the branch before the commit, and Renovate commits only the task's writes that match its `fileFilters`: `pin.json`, `hashes.json`, `pkgs/by-name/apm-skills-compose/skills.json` and the `apm.yml` files under `modules/home/ai/plugins`.
realize-pin derives each hash from the upstream's checksum file or by prefetching, writes `version` first, then each hash and companion file, and `realizedVersion` last, and stops after ten minutes.
When it fails, Renovate still commits its own edit of `version` and reports an artifact error on the pull request; `checks.<system>.pin-realized`, required on x86_64-linux and aarch64-darwin, then fails because that pin's `realizedVersion` differs from its `version`, naming the pin, so an unrealized version cannot land.
The allowlist admits the task through one anchored pattern, `^nix run \.#realize-pin -- [a-z0-9][a-z0-9-]* [0-9A-Za-z][0-9A-Za-z.+_-]*$`, and `checks.x86_64-linux.renovate-allowed-commands` renders the templated command with the name and version of every pin in the tree before matching it, and requires the pattern to reject the version `1.0.0;id`.

Pin pull requests open at any hour of any day, at most 4 per hour.
Two limits hold that bound: the instance's `prCommitsPerRunLimit = 4` with one run per hour, and the pin rule's `prHourlyLimit: 4`, which counts every pull request Renovate created on a `renovate/` branch in the current clock hour, so Renovate's other pull requests share those 4.
The number of pin pull requests open at once is not limited (`prConcurrentLimit` and `branchConcurrentLimit` are 0).
Since pin branches have no schedule, they can open and rebase during the flake-update effect's burst on Tuesday and Friday at 10:00 UTC.
realize-pin's prefetches and hash builds run on magnetite inside the Renovate unit, under its `Nice = 10`, `CPUWeight = 20`, `MemoryHigh = 4G` and `MemoryMax = 8G`.
Every pin pull request needs stibnite, the aarch64-darwin builder, reachable to go green, and none is merged automatically: a person enqueues each into gitea-mq.
The first decision, a Monday and Thursday window from 14:00 to 17:59 UTC with at most 2 pull requests per hour and 6 open, was superseded on 2026-11-25 by the hourly cadence above (design D7 of the `automate-package-version-bumps` change).

greptimedb-bin, which runs as `services.greptimedb.package` on magnetite, gets no branch until its update is approved on Renovate's Dependency Dashboard; the review it needs before approval and before enqueueing is in [Bumping a package](/development/operations/bump-procedure/#2-realize-a-version).
Any pinned package can also be realized by hand at any time with `just update-package <package> <version>`.

What the repository guarantees here is limited to what it controls: the pin contract and its type, the fetch plan the build and realize-pin share, what realize-pin reads and writes, the Renovate configuration and allowlist entry it declares, and the checks that guard them.
When Renovate runs, which releases it finds and how it orders them, what an upstream publishes and whether its checksum file matches its artifacts, whether the deployed Renovate honours the configuration, and whether a release builds on a platform are not; the last is recorded by nixbot's required checks on x86_64-linux and aarch64-darwin, and only while a builder for that platform is reachable.

## Secrets

Effect secrets are declared once, in `flake.lib.vanixietsEffectSecrets` (`modules/effects/vanixiets/secrets.nix`).
The `vanixiets-effects-secrets` clan vars generator's prompts and the secrets JSON it composes are generated from that schema; the generator runs on magnetite and nixbot receives the result as a systemd credential.
Each trigger's `secrets` is typed as an enum of the schema's names, and the interpreter derives each trigger's `secretsMap` from it, so a trigger can read exactly the secrets it declares and no other trigger's.
`checks.x86_64-linux.nixbot-wiring` asserts that the union of every trigger's `secrets` across all entries equals the schema, so no secret is prompted for without being used and none is used without being prompted for.

| Secret | Used by |
|--------|---------|
| `CLOUDFLARE_API_TOKEN` | `docs`: `main`, `pullRequest`, and `pullRequestClosed` |
| `CLOUDFLARE_ACCOUNT_ID` | `docs`: `main`, `pullRequest`, and `pullRequestClosed`; `browser-evidence`: `main`, `pullRequest`, and `buildFinished` |
| `GITHUB_TOKEN` (fine-grained PAT, read and write) | `release-packages`: `main` only |
| `R2_EVIDENCE_ACCESS_KEY_ID`, `R2_EVIDENCE_SECRET_ACCESS_KEY` (R2 token, Object Read & Write on `sciexp` only) | `browser-evidence`: `main`, `pullRequest`, and `buildFinished` |
| `FLAKE_UPDATER_APP_ID`, `FLAKE_UPDATER_PRIVATE_KEY` (GitHub App `vanixiets-flake-updater`, `contents` and `pull_requests` write) | `flake-update`: `schedule` |

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
- Renovate: https://docs.renovatebot.com/
- Cloudflare Workers: https://developers.cloudflare.com/workers/
- Wrangler CLI: https://developers.cloudflare.com/workers/wrangler/
- semantic-release: https://semantic-release.gitbook.io/
