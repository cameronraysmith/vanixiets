---
name: preferences-nix-ci-cd-integration
description: >
  Integrate nix flake checks into CI/CD pipelines via nix-eval-jobs, nix-fast-build,
  and buildbot-nix. Use when designing CI pipelines for nix-based repositories,
  migrating from hand-crafted CI matrices to nix-native check fanout, configuring
  buildbot-nix project registration, or planning binary cache strategy. Also load
  when the two-phase migration pattern (GHA+nix-fast-build to buildbot-nix delegation)
  or the effect execution strategy decision (platform-native vs nix-native effects)
  is relevant.
---

# Nix CI/CD integration

This skill covers the integration of nix flake checks into continuous integration and continuous delivery pipelines.
The companion skill `preferences-nix-checks-architecture` covers what to build (check taxonomy, derivation patterns, source filtering).
This skill covers where and how to run those checks: the tools, the migration path, the effect execution model, and the caching strategy.

The content is organized around the lifecycle of a CI pipeline for a nix-based repository.
The nix-native CI principle establishes the architectural foundation.
nix-eval-jobs and nix-fast-build provide the execution machinery.
buildbot-nix provides the self-hosted runner.
The two-phase migration pattern provides the transition path from existing CI to the nix-native model.
The effect execution strategies cover continuous delivery.
The binary cache strategy covers build artifact management.
Pipeline observability covers operational visibility.


## The nix-native CI principle

The foundational insight is that `nix flake check` defines the entire validation surface of a repository as a set of pure derivations.
Once checks are expressed as flake attributes, the question of *where* they run becomes a deployment-time decision independent of the check definitions themselves.

The same checks run under `nix flake check` on a developer's laptop, under nix-fast-build in a GitHub Actions workflow, and under buildbot-nix on a self-hosted server.
No check logic lives in CI workflow YAML.
No build matrix duplicates what the flake already declares.
The CI runner is a thin shell that invokes nix tooling against the flake's check surface.

This decoupling means runner selection (GitHub Actions, buildbot-nix, Hercules CI, Garnix) does not affect check design.
A repository can migrate from one runner to another without modifying any nix code.
The migration affects only the CI configuration layer, not the validation layer.

The principle has a corollary for local development: if a check passes under `nix flake check` on the developer's machine, it will pass in CI.
There is no "works on my machine" gap because the check derivation is hermetic.
The only variable is the builder's system architecture (a `checks.aarch64-darwin` derivation cannot build on an `x86_64-linux` worker), which is a deployment constraint, not a design decision.

The anti-pattern this principle replaces is CI workflows that embed build logic in YAML: matrix strategies that enumerate packages, conditional steps that select which checks to run, and shell scripts that partition the flake output space into categories for parallel dispatch.
All of that logic already exists in the flake's attribute structure and should be consumed, not reimplemented, by the CI system.
When build logic lives in YAML, changes to the flake's output structure (adding a new check, renaming a package) require corresponding changes to the CI workflow.
When the CI runner simply evaluates the flake, new checks are picked up automatically on the next push.


## nix-eval-jobs and nix-fast-build

nix-eval-jobs is the evaluation engine that makes parallel CI execution possible.
Standard `nix flake check` evaluates the flake and builds every check derivation sequentially in a single process.
nix-eval-jobs replaces this with parallel evaluation: multiple worker processes evaluate flake outputs concurrently and produce a stream of derivation metadata (store path, system, attribute path, derivation hash) as JSON objects on stdout.
Each output can be independently scheduled for building, which decouples evaluation from building and enables per-derivation parallelism.

The JSON stream format is designed for machine consumption.
Each line is a self-contained JSON object describing one derivation, including its attribute path (e.g., `checks.x86_64-linux.clippy`), store path, and whether it is cached.
Downstream tools consume this stream to make scheduling decisions without re-evaluating the flake.

nix-fast-build wraps nix-eval-jobs for cache-aware distributed building.
It evaluates the flake, checks each derivation against configured binary caches, builds only what is missing, and optionally pushes results to a cache.
The tool handles failure isolation: when one derivation fails to build, other derivations continue building, and the exit code reflects the aggregate result.
This is a substantial improvement over `nix flake check`, which aborts on the first failure.
The key flags for CI integration:

- `--eval-workers N` controls the number of parallel evaluation workers. Setting this to 4 rather than the default reduces SQLite eval-cache contention, which manifests as lock timeout errors under high parallelism.
- `--niks3-server URL` uploads built paths to a self-hosted niks3 cache. Cache lookups use nix's `substituters` configuration, which is separate.
- `--result-format junit` produces JUnit XML output that CI platforms parse for per-check reporting in their dashboards.
- `--skip-cached` avoids rebuilding derivations that already exist in the configured binary cache.
- `--no-nom` disables the nix output monitor (nom) interactive display, producing plain log output suitable for CI log capture.

The `--eval-workers` flag deserves elaboration because the default behavior can cause CI failures that are difficult to diagnose.
nix-eval-jobs evaluates flake outputs by forking multiple worker processes, each of which accesses the nix eval cache (a SQLite database).
Under high parallelism, SQLite write locks cause contention that manifests as "database is locked" errors or evaluation timeouts.
Setting `--eval-workers 4` bounds the contention to a manageable level.
The optimal value depends on the flake's evaluation complexity and the system's I/O performance, but 4 is a reliable default for CI.

Two execution modes serve different contexts in the justfile convention.
`just check` runs sequential `nix flake check`, which is appropriate for local development where the developer watches output interactively and benefits from nom's progress display.
The sequential mode also provides simpler error output: when a single check fails, the error is immediately visible without interleaving from parallel builds.
`just check-fast` runs parallel `nix-fast-build` with failure isolation and JUnit output, which is appropriate for CI where parallelism, structured reporting, and total wall time matter more than interactive display.
Both modes validate the same set of derivations; the difference is execution strategy, not validation scope.

The universal structural anti-pattern that nix-fast-build replaces deserves explicit description because it appears in many nix CI configurations developed before nix-fast-build existed.
A `flake-validation` GitHub Actions job runs `nix flake check`, which builds all checks sequentially in a single derivation graph.
Then a separate `nix` matrix job uses a `ci-build-category.sh` script to partition flake outputs into categories (packages, checks, devshells, home configurations, NixOS configurations) and rebuilds the *same* checks individually for per-category visibility.
The motivation for the matrix job is reasonable: per-category build status provides better failure isolation than a monolithic `nix flake check` that reports only "something failed."
But the implementation duplicates all builds.
nix-fast-build eliminates this duplication entirely: it evaluates once, builds in parallel with per-attribute failure isolation, and reports per-attribute results in JUnit format that CI dashboards render natively.

The transition from the categorized pattern to nix-fast-build also eliminates a maintenance burden.
The `ci-build-category.sh` script must be updated whenever the flake's output structure changes (new check categories, renamed packages, new machine configurations).
nix-fast-build discovers the output structure dynamically from the flake, so structural changes require no CI workflow updates.


## buildbot-nix integration

buildbot-nix is a NixOS module that runs a Buildbot instance configured specifically for nix flake evaluation and building.
It discovers repositories via forge integration (GitHub, Gitea, or both in dual-forge mode) and evaluates their flake outputs on push and pull request events.

`buildbot-nix.toml` is the per-repo configuration file that lives in the repository root.
The `attribute` field scopes which flake outputs nix-eval-jobs evaluates.
It defaults to `"checks"`, which restricts nix-eval-jobs to the `checks` flake output.
Setting `attribute = "checks.x86_64-linux"` further restricts evaluation to linux checks, avoiding cross-system eval failures on repos that define outputs for systems the buildbot workers cannot build.
To evaluate additional outputs like packages, set `attribute` explicitly (e.g. a custom path covering the desired output tree).

Project registration uses the `build-with-buildbot` GitHub topic (or Gitea topic) as the discovery mechanism.
Adding this topic to a repository causes buildbot-nix to pick it up on its next scan and begin evaluating pushes.
No manual registration or API call is required.
Removing the topic deregisters the project.
This topic-based discovery allows repository owners to opt in and opt out of buildbot-nix CI without requiring access to the buildbot server configuration.

In dual-forge mode, buildbot-nix monitors both a GitHub organization and a Gitea instance simultaneously.
A repository can exist on both forges (mirrored) or exclusively on one.
The `herculesCI` context provides repository metadata (branch, ref, tag, rev, remoteHttpUrl) that effects can use for forge-specific behavior (e.g., posting status to GitHub but not Gitea, or vice versa).

The dual-scheduler architecture separates evaluation from building, which is one of buildbot-nix's most practically important design decisions.
The first scheduler runs nix-eval-jobs to evaluate the flake.
On evaluation success, it triggers per-attribute build schedulers.
This separation produces distinct status checks: `buildbot/nix-eval` reports whether the flake evaluates cleanly, and `buildbot/nix-build` reports individual build results.
Evaluation failures (syntax errors, infinite recursion, missing inputs) are immediately visible without waiting for builds.

The practical consequence is faster feedback on common errors.
A typo in a nix expression, a missing input, or an infinite recursion in module evaluation are all caught during the evaluation phase, which typically completes in seconds.
Without the dual-scheduler separation, these errors would only surface after the build scheduler attempts (and fails) to build the derivation, which can take minutes to reach depending on scheduling latency.

`fullyPrivate` mode adds oauth2-proxy in front of the buildbot web UI, requiring OAuth2 authentication for all web access.
It forces `authBackend` to `httpbasicauth`, which makes `github.enable` default to `false`.
To retain GitHub commit status posting under `fullyPrivate`, set `github.enable = true` explicitly.

Mergify or similar merge automation gates on the buildbot status checks.
The typical configuration requires both `buildbot/nix-eval` and `buildbot/nix-build` to succeed, along with any remaining GitHub Actions checks (fast-forward verification, bootstrap checks) before allowing a merge.
This gating ensures that no PR merges with broken nix evaluation or failing builds, regardless of which runner performs the validation.

Cross-reference `references/buildbot-nix-configuration.md` for the full `buildbot-nix.toml` schema, GitHub App permissions, worker configuration, and effect pipeline details.


## The two-phase migration pattern

Migrating a repository from hand-crafted CI workflows to nix-native CI proceeds in two phases.
The phases are designed so that each one independently delivers value and the repository remains fully functional between them.

Phase 1 replaces categorized CI dispatch with nix-fast-build while still running on GitHub Actions.
The transformation has three steps: refactor all validation logic into nix flake check attributes (if not already there), replace the `ci-build-category.sh` matrix dispatch with a single nix-fast-build invocation, and archive deprecated CI artifacts to `.github/deprecated/`.
After phase 1, GitHub Actions is a thin shell invoking nix-fast-build, and checks run identically under `nix flake check` locally and under nix-fast-build in CI.
The deliverable is runner-agnostic validation: the nix layer is complete, and the CI layer is minimal.

Phase 1 is independently valuable even if phase 2 never happens.
The repository benefits from simplified CI maintenance, per-check failure isolation, JUnit reporting, and the elimination of duplicated builds.
Projects that do not have access to a self-hosted buildbot-nix instance can remain in phase 1 indefinitely.

Phase 2 delegates nix check execution to a self-hosted buildbot-nix instance.
The repository adds a `buildbot-nix.toml` configuration, registers as a buildbot project via the `build-with-buildbot` topic, and configures merge gating on buildbot status checks.
GitHub Actions nix-check jobs are either converted to passthrough (forwarding to buildbot results) or removed entirely.
Only CD workflows (deploy, release, publish) and platform-specific checks remain in GitHub Actions.

The readiness gate for phase 2 is that the repository must be registered as a buildbot-nix project, confirmed by its appearance in the buildbot project list and successful evaluation of a test push.
Phase 2 adds value beyond phase 1 in three ways: it moves nix builds off GitHub-hosted runners (which have limited nix store persistence and time limits), it provides a persistent binary cache warm from prior builds (the buildbot worker's nix store is persistent), and it enables nix-native effects (which require the buildbot-nix effect runner).

The boundary between phase 1 and phase 2 is a natural checkpoint for validating the migration.
Before proceeding to phase 2, verify that the phase 1 CI runs produce identical validation results to the pre-migration CI.
Any discrepancy indicates a check that was present in the categorized dispatch but missing from the flake's check attributes, or a check that was redundantly defined in both places.
Resolving these discrepancies during phase 1 ensures that phase 2 delegates a complete and correct check surface.

Cross-reference `references/migration-pattern.md` for the detailed recipe including canonical commits from the ironstar migration and per-repo variation guidance.


## Effect execution strategies

Effects are operations with side effects: deploying services, publishing artifacts, sending notifications, updating lock files, running scheduled maintenance.
Two strategies exist for executing effects, and the choice depends on where the effect's target lives and whether the "verify even when gated off" property adds value.

### Platform-native effects

Platform-native effects execute as CI workflow steps (GitHub Actions steps, Gitea Actions steps) that invoke nix-built tools.
The typical pattern is a `writeShellApplication` derivation exposed as a flake app, called via `nix run .#deploy-thing` in a workflow step.
Secrets are managed by the CI platform (GitHub repository secrets, Gitea secrets) and injected as environment variables.
The nix derivation provides hermetic tooling (the deploy script is built with all its dependencies in the nix store), but the orchestration (when to run, with what secrets, on what trigger) lives in the CI platform.

This strategy is appropriate when the CI platform is the *target* of the effect (GitHub releases, GitHub Pages deployment via `gh-pages`, marketplace publishing) or for simple effects where the hercules-ci interface adds no value over a shell script.
Effect logic lives in workflow YAML, which makes it visible to developers familiar with the CI platform but couples the effect to a specific runner.
Migrating a platform-native effect from GitHub Actions to Gitea Actions requires rewriting the workflow YAML, though the underlying nix app remains unchanged.

### Nix-native effects

Nix-native effects are defined as derivations with `isEffect = true` in a `herculesCI` or `effects` flake output.
buildbot-nix discovers effects after all checks pass, following a sequential pipeline: evaluate the flake, build all checks, discover effects, run effects.
Effects execute in a bubblewrap sandbox with network access and nix daemon access, mimicking the hercules-ci-agent execution environment.
The sequential ordering is deliberate: effects should not run if checks fail, because a deployment of broken code is worse than no deployment.

The `runIf` gating pattern is the key design feature that distinguishes nix-native effects from platform-native effects.
`runIf condition effect` behaves as follows: when the condition is true, the effect executes normally.
When the condition is false, the effect's `inputDerivation` is still exposed with `isEffect = false` and `buildDependenciesOnly = true`.
This means all build dependencies of the effect are built and cached, verifying that the deployment *would* succeed, without actually executing the side-effecting operation.
A deployment gated on `branch == "main"` still has its closure built on every pull request, catching build failures before merge.
This property is not achievable with platform-native effects, where the deployment either runs or does not, with no intermediate "build but do not execute" state.

The `onSchedule` interface enables recurring effects.
A `flakeUpdate` effect scheduled via `onSchedule` with `when = { hour = [ 4 ]; dayOfWeek = [ "Mon" ]; }` produces a Buildbot Nightly scheduler that evaluates the flake on the specified schedule, builds any effects, and runs them.
Changing the schedule in the flake and pushing to the default branch triggers a buildbot reconfig that updates the Nightly scheduler's timing without manual intervention.

Nix-native effects are appropriate for system deployments (`runNixOS`, `runNixDarwin` over SSH), scheduled operations (flake.lock updates, cache garbage collection), and any effect whose build dependencies benefit from the "verify even when gated off" property.

Cross-reference `references/nix-native-effects.md` for the `mkEffect` and `modularEffect` APIs, bubblewrap execution details, secret injection patterns, common effect types, the `herculesCI` flake output interface, flake-parts integration, and local testing.

### Decision guidance

Use nix-native effects when the build dependencies are substantial and verifying them on every PR catches real failures.
NixOS deployments, Darwin deployments, and any operation that builds a system closure are strong candidates.
The system closure for a NixOS configuration is typically hundreds of megabytes and takes minutes to build.
Discovering that it fails to build *after* merging to main is substantially more disruptive than discovering it on the PR.
The `runIf` pattern provides this pre-merge verification automatically.

Scheduled operations that should produce buildbot-visible results (flake.lock update PRs, cache GC reports) also benefit from the nix-native model.
The `onSchedule` interface provides cron-like timing with full buildbot visibility: each scheduled run appears in the buildbot UI with build logs, status, and duration.

Use platform-native effects when the CI platform itself is the target.
GitHub release creation, npm publishing, Docker Hub push, and GitHub Pages deployment via platform APIs are naturally expressed as workflow steps.
There is no benefit to wrapping `gh release create` in a bubblewrap sandbox.
The platform-native model is also appropriate for effects that are trivially fast and have no meaningful build dependencies to verify.
A notification webhook that sends a JSON payload to a Slack endpoint does not benefit from the `runIf` closure-building property.

When uncertain, consider whether a pull request would benefit from building the effect's closure without executing it.
If yes, the nix-native model with `runIf` provides that property automatically.
If not, the platform-native model is simpler.
A repository can use both strategies simultaneously: nix-native effects for deployments and scheduled operations, platform-native effects for GitHub-specific integrations.
The two models are complementary, not mutually exclusive.


## Binary cache strategy

Binary caching operates at three tiers, each with distinct invalidation characteristics and storage costs.

The *nix store* on the local builder is the first tier.
It is populated by every `nix build` and `nix flake check` invocation.
Cache hits are instant (no network) but limited to the machine that performed the build.
On CI, the nix store's persistence depends on the runner infrastructure.
GitHub-hosted runners have ephemeral storage, so the nix store is empty at the start of each job.
Self-hosted runners (including buildbot-nix workers) have persistent storage, so the nix store accumulates builds across jobs and acts as a warm local cache.
This persistence difference is one of the practical motivations for phase 2 of the migration pattern.

The *binary cache* is the second tier.
A binary cache stores pre-built derivations indexed by store path hash, served over HTTP.
niks3 on Cloudflare R2 provides self-hosted storage with no free-tier eviction and cost proportional to usage.
Cachix provides managed convenience with integrated GitHub Actions support via `cachix/cachix-action`, at the cost of storage limits on free plans and eviction under sustained CI load.
Substituter ordering in `nix.conf` determines lookup priority: local store, then self-hosted cache, then cachix, then cache.nixos.org.
The order matters because nix tries each substituter in sequence and uses the first hit.
Placing the self-hosted cache first ensures project-specific derivations (which cache.nixos.org does not have) are served from the fast, project-local cache.
`nixConfig.extra-substituters` in `flake.nix` makes project-specific caches available to anyone who builds the flake without requiring manual `nix.conf` configuration.

The *CI job-result cache* is the third tier, operating above the nix layer entirely.
The `cached-ci-job` composite action computes SHA256 hashes of glob-matched source files to produce a cache key.
When the key matches a prior run, the entire GitHub Actions job skips without invoking nix at all.
This is orthogonal to nix store caching: it prevents job *execution*, not just derivation *building*.
Even if every nix derivation would be a cache hit, the CI job still spends time on checkout, nix daemon startup, nix-fast-build invocation, and cache synchronization.
The job-result cache eliminates all of that overhead for unchanged source sets.

Source filtering (described in the companion `preferences-nix-checks-architecture` skill) drives cache efficiency at the nix layer.
Content-addressed source paths (`builtins.path` with fixed `name`), language-specific filters (`crane.filterCargoSources`, `lib.fileset.toSource`), and lockfile-based dependency fetchers all minimize cache invalidation from unrelated changes.
The relationship between source filtering and cache efficiency is direct: every file included in a derivation's source input contributes to the derivation hash.
A change to any included file invalidates the cache entry.
Excluding irrelevant files (documentation, CI configuration, unrelated source directories) prevents cascading invalidation.

The `cache-overlay-packages` anti-pattern is a dedicated GitHub Actions job that builds overlay packages to warm the cache before other jobs run.
Under nix-fast-build, this is unnecessary because `--skip-cached` and binary cache integration handle caching as part of the normal build pipeline.
The dedicated job adds CI wall time without providing benefit when nix-fast-build is the build driver.

Cross-reference `references/caching-strategies.md` for detailed content-addressed source patterns, shared artifact patterns, and niks3 vs cachix tradeoff analysis.


## Justfile CI conventions

The justfile serves as the developer-facing interface to both local and CI execution.
CI workflows invoke justfile recipes rather than calling nix tooling directly, which keeps the CI YAML minimal and ensures developers can reproduce CI behavior locally.

The `check` recipe runs `nix flake check` with nom for interactive output.
This is the developer's primary feedback loop during local development.
It evaluates and builds all checks sequentially, providing clear per-check error output without interleaving.

The `check-fast` recipe runs nix-fast-build with the flags appropriate for CI: `--skip-cached`, `--no-nom`, `--eval-workers 4`, and `--result-format junit`.
CI workflows invoke `just check-fast` and upload the JUnit artifact.
Developers can also run `just check-fast` locally to validate cache behavior or reproduce CI-specific issues.

The `build` recipe builds a specific package or the default package.
The `fmt` recipe runs treefmt.
The `lint` recipe runs language-specific linters.
These recipes may invoke nix derivations or run tools directly, depending on whether the tool is available in the devshell or needs a nix build.

The convention of routing CI through justfile recipes means that CI workflow changes are rare.
Adding a new check to the flake requires no CI workflow update because the check is discovered automatically by nix-fast-build.
The only CI workflow changes needed are for structural changes: adding or removing CI jobs, changing the runner, or modifying the trigger conditions.

This indirection also simplifies debugging.
When a CI job fails, the developer can reproduce the failure locally by running the same justfile recipe.
There is no need to decipher GitHub Actions YAML to understand what the CI job actually does.
The justfile recipe is the single source of truth for how a validation or build operation is invoked, used identically by developers and CI runners.


## Pipeline architecture for multi-system repositories

Repositories that target multiple systems (e.g., `x86_64-linux` and `aarch64-darwin` for a cross-platform tool) face a challenge: a single buildbot worker typically supports only one system.
Three approaches address this.

The *split-attribute* approach uses separate `buildbot-nix.toml` attribute scoping per forge.
A GitHub-hosted runner evaluates `checks.aarch64-darwin` via nix-fast-build in a GHA workflow, while the buildbot worker evaluates `checks.x86_64-linux`.
This hybrid retains GHA for systems that buildbot cannot build while delegating the primary system to buildbot.

The *multi-worker* approach provisions buildbot workers for each target system.
An `aarch64-linux` worker on a Hetzner ARM server and an `x86_64-linux` worker on a standard server together cover both linux architectures.
Darwin systems require a macOS worker, which is feasible with persistent macOS CI runners (e.g., a Mac Mini connected to the buildbot master).

The *cross-compilation* approach builds non-native system outputs via cross-compilation on the available worker.
This works for simple derivations but fails for checks that require native execution (test suites, linters, type checkers).
Cross-compilation is appropriate for package builds but not for the full check surface.

The choice depends on the repository's system coverage and available infrastructure.
Most repositories target a single primary system and do not need multi-system CI.
Repositories that do should prefer the split-attribute approach initially and consider multi-worker as their infrastructure matures.

For nix-darwin repositories in the vanixiets fleet, the split-attribute approach is the current practice.
Darwin checks run locally on the developer's machine via `just check`, while linux checks are delegated to buildbot-nix on the Hetzner worker.
This division reflects the reality that darwin builders are developer workstations, not CI infrastructure, and should not be burdened with CI workloads.


## Pipeline observability

CI/CD observability bridges to the CI/CD/CV (continuous validation) trichotomy described in `preferences-production-readiness`.
Three categories of signal provide visibility into pipeline health.

Cache hit rate is a leading indicator of CI efficiency.
Declining hit rates signal source filtering regressions (a change to the filter function that broadened the input set), cache eviction (free-tier storage limits, retention policy changes), or infrastructure issues (cache endpoint unreachable, authentication failures).
Tracking hit rate per check category identifies which categories are most affected.
nix-fast-build's output includes cache lookup results for each derivation, making it possible to compute hit rates from CI logs without additional instrumentation.

JUnit output from nix-fast-build (`--result-format junit`) provides per-check visibility in CI dashboards.
Each check appears as a test case with pass/fail status, duration, and output.
CI platforms (GitHub Actions, Gitea Actions, buildbot's web UI) render JUnit XML natively, so no additional tooling is needed to surface per-check results.
The JUnit format also enables trend analysis across runs: a check that takes 30 seconds in one run and 5 minutes in the next is immediately visible in the CI platform's test duration charts.

Build time tracking per check category identifies performance regressions.
When a check that previously completed in 30 seconds starts taking 5 minutes, the cause is typically a cache miss (dependency change, source filter regression) or a genuine build complexity increase.
Distinguishing these two causes requires correlating build time with cache hit rate.
A build time increase accompanied by a cache hit rate decrease points to a caching problem.
A build time increase with stable cache hit rates points to genuine complexity growth or a dependency update that increased build time.

The dogfooding loop is a particularly valuable observability signal for infrastructure repositories.
When buildbot-nix builds the repository that defines the buildbot-nix configuration (vanixiets building vanixiets), the pipeline validates itself end-to-end.
A failing build on the buildbot-nix configuration repo means the next deployment of that configuration would break CI for all registered projects.
This self-referential validation closes the loop between infrastructure changes and their operational impact.
It also provides early warning for upstream breakage: when a nixpkgs update breaks the buildbot-nix configuration, the dogfooding build fails before the broken configuration is deployed.

The bridge to continuous validation (CV) from `preferences-production-readiness` is through the effect system.
Nix-native effects can implement CV checks: scheduled health probes, deployment verification tests, and post-deploy smoke tests.
The `onSchedule` interface provides the timing, the effect sandbox provides the execution environment, and the `runIf` gating pattern provides conditional execution based on deployment state.
A health probe scheduled every hour that verifies all deployed services are responding is a CV check implemented as a nix-native effect.
Its build dependencies (the probe script, the HTTP client, the expected-response definitions) are verified on every push, while the probe itself executes only on schedule.

The three observability categories (cache hit rate, per-check timing, dogfooding results) together provide sufficient signal to identify most CI health problems without requiring dedicated monitoring infrastructure.
CI platforms already provide the dashboards; the nix-native CI approach ensures the data feeding those dashboards is structured and per-attribute rather than monolithic.


## Cross-references

This skill sits at the intersection of several other preference skills, each covering a complementary aspect of the nix-based development workflow.

`preferences-nix-checks-architecture` covers check taxonomy, derivation patterns, source filtering, and flake-parts module organization.
It answers *what* to build; this skill answers *where* and *how* to run it.
The two skills are designed to be loaded together when working on CI pipeline design, as the check architecture directly determines the CI pipeline's structure.

`preferences-nix-development` covers flake conventions, module structure, and derivation best practices that underpin both check derivation design and the flake outputs that CI tools consume.
The `perSystem` convention from flake-parts determines the attribute paths that `buildbot-nix.toml`'s `attribute` field references.

`preferences-production-readiness` defines the CI/CD/CV trichotomy, pipeline observability foundations, and progressive delivery patterns.
The effect execution strategies in this skill implement the CD layer of that trichotomy.
The pipeline observability section bridges to the CV layer through scheduled effects and health probes.

`preferences-observability-engineering` provides instrumentation patterns applicable to build pipeline telemetry: structured events for build completion, traces spanning evaluation through building, and SLO-based alerting on cache hit rates and build times.
When build pipeline telemetry is integrated with application observability, the full deployment lifecycle is visible from commit through build through deploy through production health.

`preferences-secrets` covers CI key strategies, sops-nix integration, and secret rotation patterns relevant to both platform-native and nix-native effect secret management.
The `secretsMap` pattern in nix-native effects and the `perRepoSecretFiles` configuration in buildbot-nix are the CI-specific instantiations of the general secrets management patterns.

`preferences-web-application-deployment` covers deployment patterns that may be implemented as either platform-native or nix-native effects, depending on the decision guidance in this skill's effect execution strategies section.
