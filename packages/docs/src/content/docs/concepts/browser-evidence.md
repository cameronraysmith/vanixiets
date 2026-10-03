---
title: Browser evidence
description: What the docs site's browser test report is, when a pull request gets an evidence comment, and how to read what it links to
sidebar:
  order: 10
---

The docs site has a browser test suite, and CI keeps its result as evidence that a reviewer or an agent can read without rebuilding anything.
This page is for those readers: it explains what the evidence is, when it appears on a pull request, and how to read it.
The report contract itself is documented beside the tests in `packages/docs/tests/report/README.md`.

## The report

The check `package-vanixiets-docs-test-e2e-report` runs the browser suite against the built site once and keeps the result as a Nix output, even when tests fail.
A successful build of that check means usable evidence exists, not that the site passed.
The separate check `package-vanixiets-docs-test-e2e` is the verdict: it reads the same report without running browsers again and fails when the suite failed.

The report's Nix output path is derived from every input of the report: the site build, test sources, fixtures, Playwright configuration, browsers, runner, and evidence epoch.
Two revisions therefore share a report path exactly when nothing the report depends on differs, and the same report is reused from cache by every build that carries it.

The `browser-evidence` effect publishes a small, inert subset of that report:

- `run.json`, the runner's exit code and the report's provenance;
- `playwright-report/completion.json`, every test's outcome and attempts;
- the PNG screenshots that test attempts reference;
- `receipt.json`, which describes the publication.

Traces, the HTML report, videos, and other attachments are not published.
To see them, build the report attribute locally.

## When a pull request gets a comment

A pull request gets a comment only when it changes the report.
The publisher detects that by the report's Nix output path, not by which files the diff touches.
A path glob over the diff would miss changes that reach the report indirectly, such as a lock file or flake input update; the output path cannot drift, because it is the build's own identity.

Because the path is derived from inputs, a dependency bump inside the site's closure changes it, and the pull request gets a comment even when every screenshot is pixel-identical to `main`'s.
The detector is also only as precise as the report's inputs.
The site's dependencies (`vanixiets-docs-deps`) are built from the whole workspace `bun.lock`, so a dependency change in another workspace package, such as `@vanixiets/evidence-worker`, currently counts as changing the docs report.
Building dependencies per application would remove that over-approximation.

Another application would get its own report derivation, one per (project, kind), and be judged by its own output path, independently of the docs report.

When a pull request build settles, the publisher checks whether `main` has already published this exact report.
If it has, the pull request does not change the browser evidence: nothing is uploaded, no comment is posted, and the effect log prints `PUBLISH-EVIDENCE: unaffected (report <obs> already published from main)`.
Otherwise the report is uploaded to the 30-day tier and the pull request gets one comment, which later builds edit instead of adding another.

The comparison is against what `main` has published, not against `main`'s source.
A report that differs from every report published from `main` in the last 90 days counts as a change, which includes the case where `main`'s evidence for it has expired or `main`'s publish run failed.

## The superseded comment

If a later build of the pull request produces the same report as `main`, the earlier comment would otherwise keep describing a change the pull request no longer makes.
The publisher replaces it once with a short note, headed `Browser evidence: superseded`, saying that the evidence previously linked no longer describes a change.
The note names the shared report, the build, and the revision, and carries no links.
A pull request that never had a comment stays silent.

When two builds of one pull request finish out of order, the comment reflects whichever finished last, even when that is not the newest build.

## What a comment contains

A comment for a pull request that changes the report shows:

- the verdict, `Browser evidence: passed` or `Browser evidence: failed`;
- the build number, linked to the build, and the first 12 hex digits of its revision, followed by `(reused for head <head>, same tree)` when the build was reused for a newer head;
- the expected, unexpected, flaky, and skipped test counts;
- a link to each screenshot, or `No screenshots.`;
- a link to `receipt.json`;
- that no report identical to this one has been published from `main` in the last 90 days, which is why it is shown;
- that the evidence is kept 30 days.

Screenshots are taken only for failed attempts, so a passing run with no screenshots is expected.
A passing run that had flaky tests is still a pass, and the `flaky` count says how many recovered on a retry.

The comment describes the build named in it.
nixbot reuses a finished build for a new head whose tree is identical, without building again, and the comment then names both the reused build's revision and the head it was reused for.
A reused build that failed sends no event, so its head gets no comment of its own; the comment keeps naming the earlier build with the same tree.

## Tiers and retention

Evidence is stored by retention tier, and objects are deleted by age; nothing renews them.

| Tier | Written for | Kept |
|---|---|---|
| `ttl-30d` | a pull request whose report `main` has not published | 30 days |
| `ttl-90d` | `main`, and failed builds without a pull request | 90 days |
| `ttl-365d` | reserved for a later curation step; nothing writes to it | 365 days |

Each tier receives a given report at most once.
A later build carrying the same report targets the same keys and is reported `unchanged`.

## URL layout

Evidence is served at

```text
https://evidence.vanixiets.net/<project>/<kind>/<tier>/v1/<obs>/<file>
```

For this repository `<project>` is `vanixiets` and `<kind>` is `browser-evidence`, so a receipt is at `https://evidence.vanixiets.net/vanixiets/browser-evidence/<tier>/v1/<obs>/receipt.json`.
`<obs>` is the first 32 hex digits of the SHA-256 of the report's attribute and output path, so it names the report's content, not the build that produced it.
`<file>` is a path from the receipt's `files`, such as `run.json` or a screenshot under `test-results/`.

The host serves only `.png` and `.json` files and never lists a directory.
Start from a link in a comment, a `PUBLISH-EVIDENCE: uploaded <url>` line in the effect log, or a receipt you already have.
Anyone holding a URL can read the evidence it names.

## Reading `receipt.json`

The receipt is a pure function of the report and its destination.
It carries no build number, revision, build URL, build status, timestamp, or pull request number, so every build carrying the same report produces it byte for byte.
Use the comment or the effect log to learn which build a report came from.

| Field | Meaning |
|---|---|
| `schemaVersion` | `3` |
| `identity` | `attribute` and `outPath`: the report's check attribute and its Nix output path; `<obs>` is computed from this pair |
| `obs` | the 32-hex observation identifier used in the URL |
| `attribute`, `outPath` | the same values as `identity` |
| `reportProvenance` | the report's provenance from `run.json`: the Nix store paths of the `site`, `source`, `dependencies`, `browsers`, and `node` it ran with, plus `system`, `config`, `projects`, `trace`, and `evidenceEpoch` |
| `verdict` | `passed`, and `counts` with `expected`, `unexpected`, `skipped`, and `flaky` |
| `files` | each published file's `path`, `sha256`, and size in `bytes` |
| `destination` | `bucket`, key `prefix`, `tier`, and the base `url` of the publication; present when the bundle was uploaded |

`verdict.passed` is `false` for a completed run whose tests failed.
Evidence that is invalid or incomplete is never published, so a receipt always describes a run that completed.
To check a file you fetched, compare its SHA-256 and size with its entry in `files`.

## Why `vanixiets.net`

Evidence comes from CI and is treated as untrusted content.
`vanixiets.net` is a registrable domain dedicated to that content: it never hosts authentication, sessions, or cookies, so nothing served there can reach a credential.

A subdomain of a domain that carries sessions would not be enough for active content.
A page on any subdomain can set cookies for the whole registrable domain, and browsers treat requests between its subdomains as same-site.

Today's content is inert: PNG and JSON only.
The serving Worker answers only GET and HEAD, takes the content type from the file extension rather than from stored metadata, and sends `X-Content-Type-Options: nosniff`, `Content-Disposition: inline`, `Referrer-Policy: no-referrer`, and a `default-src 'none'; sandbox` content security policy.
Active content such as the HTML report, a trace viewer, or video is out of scope; if it is ever published, it goes on another `vanixiets.net` subdomain, never on a domain carrying sessions.

## The publisher runs from `main`'s code

The `browser-evidence` effect is a nixbot event effect, and nixbot runs event effects from the default branch only.
The effect's code comes from `main`, and a pull request contributes only an untrusted clone of its head; the publisher never evaluates or executes pull request code.
A pull request that changes the effect or the publisher is therefore not exercised by its own build.
It is exercised by builds after it lands, and before then only the `publish-evidence-rehearsal` check covers it.

The effect has three triggers, and every run takes the same `browser-evidence` lock, so runs never overlap.
An onPush run for `main` publishes the newest build of the pushed commit to `ttl-90d` and never comments, because a fast-forward landing reuses the merge-queue build and nixbot sends no `build_finished` for it.
A `pull_request` run handles each pull request build that settles succeeded, freshly built or reused.
A `build_finished` run handles builds that failed, so a failing report reaches publication too; for a build without a pull request it publishes to `ttl-90d` without a comment.
Each pull request build therefore gets exactly one run:

| Pull request build | Succeeded | Failed |
|---|---|---|
| freshly built | `pull_request` | `build_finished` |
| reused | `pull_request` | none |

nixbot's Event Effects list therefore shows `build_finished · browser-evidence — build is succeeded, needs failed` on every succeeded build.
That is the filter working, not a failure: the `pull_request` run on the same build is the one that published.

Neither run requires the pull request's author or actor to hold a repository permission.
The trust gate is nixbot's CI approval: a pull request from outside the repository is not built until a maintainer approves it, and one whose branch lives in the repository is trusted because pushing it already needed write access.
Bots report no permission, so a permission condition would have skipped Renovate's pull requests; without it, dependency updates get evidence too.

The effect posts comments through nixbot's comment API and holds no GitHub token.
Its storage credentials are temporary, last 15 minutes, and are confined to the run's own tier, so a pull request run cannot write into `main`'s `ttl-90d` tier.

## Related

- [CI Jobs](/reference/ci-jobs/#browser-evidence): the `browser-evidence` effect's triggers, secrets, and rehearsal
- [Test Harness Reference](/development/traceability/test-harness/): CI contexts and their local equivalents
- [Build service topology](/concepts/build-service-topology/): nixbot, the CI service that builds the report and runs the effect
