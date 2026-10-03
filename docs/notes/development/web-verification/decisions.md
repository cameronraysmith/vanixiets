# Decisions

## D1: keep interaction and verification separate

Use Playwright CLI for portable exploration and committed Playwright Test scenarios for the verdict.
Do not add another browser framework merely to demonstrate tool diversity.
This preserves the existing browser/version work and an independent assertion oracle.

## D2: make APM the skill source of truth

Declare the upstream Git skill dependency in the existing planning-and-development plugin.
Reuse the packaged release source in offline composition with a full-revision drift guard.
Remove the direct Home Manager extraSkillDirs route for this skill.
The existing Linear CLI integration is the local precedent.

## D3: separate completed reports from passing verdicts

A conventional failing derivation cannot export normal successful output artifacts.
Produce a valid completed execution report independently of its result, then enforce that result with a mandatory dependent check.
Missing or invalid reports fail closed.
Do not replace the verdict check with an always-green artifact producer.

## D4: use nixbot events for failed-build evidence

Extend the existing registry for build_finished rather than importing GitHub Actions artifact jobs.
Reuse the recorded-build-output lookup and writeShellApplication sidecar pattern.
Publication uses trusted default-branch code and requires no execution of PR code under credentials.

## D5: demonstrate integrity with a controlled defect

A passing baseline alone cannot show that the harness detects regressions.
Use an isolated broken fixture and require the intended assertion to fail while its evidence survives.
Do not break or deploy the real documentation site for the demonstration.

## D6: retain human control over changed expectations

An agent may repair implementation or propose test changes.
It may not silently weaken assertions, accept visual baselines, skip tests, or redefine the journey.
Ambiguity between an intended behavior change and a regression requires review.

## Unresolved operational choices

D9 settles report destination, serving-origin isolation, access policy, and retention.
D10 settles association of a landed revision with existing evidence when nixbot reuses an entire build and does not emit build_finished.
These remain open:

- Whether publication failures should add a separate required gate.
- Scope of successful-run recordings beyond the focused demonstration.

Neither blocks live publication; until decided, a publication failure is visible only as a failed effect run, and only the screenshots and metadata named in D9 are published.

## D7: preserve observations and refresh through an explicit evidence epoch

Review R2 identified that a completed negative report remains a valid cached output.
Pinned nixbot restarts use ordinary realization; Nix 2.35.2 `--rebuild` compares output hashes and does not replace a valid report.
Changing only cache availability would not prevent local reuse.

Use a source-controlled decimal evidence epoch outside the application's source fileset.
Increment it deliberately to collect another required observation without rebuilding unchanged application or browser inputs.
Record the epoch in the report and preserve the old observation.
Do not reuse an epoch or interpret a fresh pass as proof that an earlier failure was harmless.
This provides a defined refresh mechanism; it does not make live or inherently time-dependent tests hermetic.

## D8: bound report load and let retries recover infrastructure attempts

nixbot build 951 failed correct docs changes with navigation timeouts while three PRs built on magnetite.
The builders run `cores = 0`, so every concurrent report build received `NIX_BUILD_CORES=16` and started 16 workers against its own single-process `astro preview`.
The validator then rejected the run even where retries recovered, because it required every failed attempt, not only the terminal one, to be a product failure.

Bound each report build at four workers, since `NIX_BUILD_CORES` cannot see concurrent builds.
Drop the separate navigation deadline: navigation failures are never product evidence, so the test deadline is the only bound that matters.
Accept an infrastructure-class attempt, including a whole-test deadline, only when a later attempt of the same test completed; count it as `infrastructureRetries`.
A terminal infrastructure attempt still prevents a valid report, and product attempts still require a trace and screenshot.
Let the negative controls inherit the suite's retries and require every attempt to fail with a product-class terminal attempt, so host noise cannot mask the deliberate defect and a retry cannot pass it.
This tolerates bounded host noise; it does not make the suite correct on an arbitrarily overloaded builder.

## D9: publish to the adopted `sciexp` bucket under a confined prefix

Evidence goes to the existing R2 bucket `sciexp` under `projects/vanixiets/browser-evidence/<tier>/v1/<obs>/<path>`.
Terraform (`modules/terranix/cloudflare.nix`) adopts the bucket with an import block and `prevent_destroy`, and owns its whole lifecycle configuration; it manages nothing else for evidence.
`<obs>` is the first 32 hex of the SHA-256 of the compact JSON `[attribute, outPath]`, so it names the report's content, not the build that produced it; every build carrying the same report output writes the same keys.
The receipt, schema version 3, is a pure function of that content: it records `identity` (`attribute` and `outPath`), `obs`, system, config, report provenance, verdict, and each file's path, SHA-256, and size, and no build number, revision, build URL, build status, `cached` flag, event kind, or pull request number.
With `--upload` it adds `destination` (bucket, prefix, tier, and URL), which is stable because the tier is part of the key.
A tier therefore receives each report at most once: the receipt is uploaded last with `If-None-Match: *`, an identical existing receipt is reported `unchanged`, and a different one is a conflict, which only a schema change or corruption can now cause.

The tier is part of the key, and a lifecycle rule per tier prefix deletes objects by age:

- `ttl-30d` for a pull request build whose report `main` has not published ([D10](#d10-publish-main-from-onpush-and-pull-requests-from-build_finished));
- `ttl-90d` for `main` and other builds without a pull request;
- `ttl-365d` for a later curation step; the rule exists, but nothing writes to it.

R2 lifecycle rules are bucket-wide, so `cloudflare_r2_bucket_lifecycle.sciexp` holds every rule for the bucket, including the existing multipart-abort rule.
Other writers to `sciexp` add their rules there; a second lifecycle resource would replace this one's rules.

The effect holds an R2 token limited to Object Read & Write on `sciexp` and never uploads with it.
Each run signs temporary credentials locally from it, following Cloudflare's temporary-credential example, each with a 15-minute lifetime:

- `rw`: scope `object-read-write`, prefix `projects/vanixiets/browser-evidence/<tier>/`, the run's own tier only; for a pull request run that is `ttl-30d/`, which also holds the pull request marker;
- `ro`, for pull request runs only: scope `object-read-only`, prefix `projects/vanixiets/browser-evidence/ttl-90d/`, used only to probe for `main`'s receipt.

A pull request run therefore cannot write into `ttl-90d/`, where `main`'s evidence lives.
The parent secret is unset immediately after signing, never appears in argv or a child's environment, and every request uses only a temporary credential.
A credential minted the same way with the earlier whole-evidence prefix `projects/vanixiets/browser-evidence/` was checked live: it wrote, read, and deleted an object inside the prefix and was refused for `projects/vanixiets/x` and `omnigraph/x`.
The per-tier prefixes and the read-only scope have not been checked against R2.

A Worker, `sciexp-evidence`, serves evidence read-only through its R2 binding `EVIDENCE` on `evidence.vanixiets.net`.
It is the TypeScript workspace package `packages/evidence-worker/` (`@vanixiets/evidence-worker`, `src/index.ts`, `wrangler.jsonc`), deployed with wrangler rather than Terraform.
URL path `/<project>/<kind>/<tier>/v1/<obs>/<path>` equals the R2 key suffix after `projects/`; this repository's evidence is under `/vanixiets/browser-evidence/<tier>/v1/<obs>/`.
It answers GET and HEAD only and 405 for other methods; it accepts only allowlisted (project, kind) pairs, the three tiers, a 32-hex `<obs>`, and path segments of `[A-Za-z0-9._-]` with no `..` or empty segment.
Its path grammar rejects the pull request markers under `ttl-30d/pr/`, so they are never served.
It serves `.png` as `image/png` and `.json` as `application/json`, 404s any other extension or missing object, and never lists.
Content type comes from the extension, never from object metadata.
Every response carries `X-Content-Type-Options: nosniff`, `Content-Security-Policy: default-src 'none'; sandbox`, `Referrer-Policy: no-referrer`, and `Cross-Origin-Resource-Policy: same-origin`.
Objects add `Content-Disposition: inline` and `Cache-Control: public, max-age=86400, immutable`; 404 and 405 responses carry `Cache-Control: no-store`.
Evidence is public to anyone holding a URL; the publisher selects only metadata and raster screenshots, and HTML reports and traces stay unpublished.

The hostname choice rests on three points:

- `vanixiets.net` is a registrable domain dedicated to untrusted CI content. It never hosts authentication, sessions, or cookies, so nothing served there can reach a credential.
- A subdomain of a session-bearing domain is insufficient for active content. A page on any subdomain can set cookies for the whole registrable domain (cookie tossing), SameSite treats requests between its subdomains as same-site and so first-party, and the subdomain shares the trust users and policies extend to the parent domain. Today's content is inert, PNG and JSON under a sandboxing content security policy, so serving it on this host is acceptable now; the dedicated domain keeps that true once active content exists.
- Future active content, such as the HTML report, a trace viewer, or video, goes on another `vanixiets.net` subdomain, such as `reports.vanixiets.net`, never on a domain carrying sessions. It remains out of scope.

## D10: publish `main` from onPush and pull requests from build_finished

gitea-mq lands a batch by fast-forwarding `main` to the tested commit, so the push to `main` reuses the batch's build.
Pinned nixbot delivers build_finished only for a build that newly finished (`nixbot/nixbot/after_build.py:74-79`), so a landing sends none.
build_finished alone would therefore never publish evidence for `main`.

The `browser-evidence` effect has two triggers sharing the `browser-evidence` lock:

- `main`: an onPush effect running `publish-evidence main --upload --rev <commit>`; it finds the build for that commit through nixbot's builds API, takes the highest build number, and publishes its report to `ttl-90d` unless that report is already there. It never comments.
- `buildFinished`: an onEvent effect running `publish-evidence build-finished --upload` for succeeded and failed builds, with `when.permission = "write"`; for a pull request build it applies the affected rule below, and for a build without a pull request it publishes to `ttl-90d` as `main` does, without a probe or comment.

onPush runs only after a successful build, so a failed report reaches publication only through build_finished.
The receipt names no build, so a report reused by a later build or by a landing push is the same publication; the pull request comment names the build it describes.

nixbot runs event effects from the default branch only (nixbot@2626aa2 `nixbot/nixbot/event_effects.py:1-4`): the effect code comes from a worktree of the default branch, and a pull request contributes only an untrusted clone of its head.
A pull request that introduces or changes the `browser-evidence` effect or the publisher is therefore not exercised by its own build; it is exercised by builds after it lands, and before then only the rehearsal check covers it.

A pull request is unaffected when `main` has already published this exact report, that is, when `ttl-90d/v1/<obs>/receipt.json` exists.
The publisher probes for that receipt with the read-only credential.
When it exists, the run uploads nothing, posts no comment, and logs `PUBLISH-EVIDENCE: unaffected (report <obs> already published from main)`.
Otherwise the pull request is affected: the run uploads to `ttl-30d/v1/<obs>/` and upserts the pull request comment.
Any probe status other than 200 or 404 fails the run, naming the key, before any upload or comment.

Nix's report output path is the change detector.
It is derived from every input of the report derivation, including the site build, test sources, fixtures, Playwright configuration, browsers, runner, and evidence epoch, so two revisions share it exactly when nothing that the report depends on differs.
Path globs over the diff would approximate that input set by hand, miss changes that reach the report indirectly, such as a lock file or flake input update, and drift as the build changes; the output path cannot drift, because it is the build's own identity.
The rule carries to future applications unchanged: each (project, kind) has one report derivation, and that derivation's output path is its detector.

The rule compares against what `main` has published, not against `main`'s source.
A report that differs from every report published from `main` in the last 90 days is treated as affected, for example when `main`'s evidence for the same report has expired or `main`'s publish run failed.
The comment says so: no report identical to this one has been published from `main` in the last 90 days, so it is shown in the pull request.

For an affected pull request, the publisher posts through nixbot's `POST /api/v1/pr-comment` with the run's API token and the marker `vanixiets-browser-evidence`.
nixbot only upserts: it edits the newest comment carrying that marker or posts a new one (`nixbot/nixbot/forge_pr.py:163-178`, `web/task_routes.py` `PrCommentRequest`), and it can neither delete a comment nor update one only if it exists.
Once a pull request has a comment, a later unaffected build can neither remove it nor stay silent without leaving it describing a change the pull request no longer makes.
The publisher therefore records its comment state in R2 at `projects/vanixiets/browser-evidence/ttl-30d/pr/<number>.json`: schema version 1, the pull request number, `state` `current` or `superseded`, and the report, build, and revision it was written for.
The marker lies inside the pull request run's read-write prefix, the 30-day lifecycle deletes it, and the Worker never serves it.
An affected run writes `current` after a successful comment.
An unaffected run reads the marker: if it is absent, no comment was ever posted and the run stays silent; if it is `current`, the run upserts the comment with a superseded body, which names the report shared with `main`, the build, and the revision and carries no links, writes `superseded`, and logs `PUBLISH-EVIDENCE: superseded #<number>`; if it is `superseded`, the run does nothing.
Two builds of one pull request that finish out of order race on the comment and the marker, and the run that finishes last wins even when it is not the newest build.
This race is accepted: the shared `browser-evidence` lock serialises the runs but does not order them.
The publisher holds no GitHub token for the comment; a failed post fails the effect after the upload, and a rerun is idempotent.

## Source grounding

The research inspected nixbot at `2626aa2ca80b76ef894f4558635a3fdda1edd8b4` and hercules-ci-effects at `6c58de7236d1cd634deea07bd15d52c7ce470bd3`, matching the inputs at the start of this implementation.
Kandev at `9f8e98e56a023de985ee03c78a30d9e33ea7dd1f` informed the separation between exploration, executable tests, selected PR media, and expiring CI diagnostics.
Its media-ref publication mechanism is a reference, not a selected storage design.
The Playwright CLI release source is to remain coupled to its package; upstream HEAD is not a substitute for inspecting that release.
