# Nix CI/CD architecture pattern

This working note documents the CI/CD architecture pattern converged upon across the vanixiets and ironstar projects as of 2026-04-09.
The pattern separates CI/CD into three layers with distinct execution models and composes them through nix flake outputs.

## Three-layer architecture

### Layer 1: local development feedback loop

The developer's primary validation mechanism before pushing is `nix flake check` and `nix-fast-build`.
In ironstar, the `just check-fast` recipe wraps `nix-fast-build --no-nom --skip-cached` to provide parallel evaluation and build of all flake checks with a single command.
This layer operates entirely on the developer's machine with no network dependencies beyond the binary cache substituter.
The tight feedback loop catches evaluation errors, type mismatches, test failures, and formatting violations before code reaches any CI system.

### Layer 2: CI via buildbot-nix

buildbot-nix provides centralized CI by using `nix-eval-jobs` to fan out flake check evaluation across workers.
It evaluates all `checks.*` outputs from a flake and builds them with full parallelism, applying several caching optimizations: niks3 binary cache on Cloudflare R2 for persistent cross-build caching, per-derivation deduplication, and Hydra-style separation of evaluation from building.

The `build-with-buildbot` topic filter controls which repositories are CI-eligible.
buildbot-nix supports dual-forge operation, discovering repos, creating webhooks, and reporting commit status on both GitHub and Gitea independently.
This dual-forge capability means the same CI infrastructure serves both public GitHub repositories and private Gitea-hosted ones without configuration duplication.

### Layer 3: CD via flake apps

Deployment operations are encapsulated as `nix run .#<app>` flake apps using `writeShellApplication` with explicit `runtimeInputs`.
CI platforms (GitHub Actions, Gitea Actions) become thin triggers that provide timing (on push to main, on PR merge) and secrets (via environment variables), while the deployment logic is entirely owned by the flake.
This makes CD operations portable across CI platforms, locally testable via `nix run .#deploy-docs -- --dry-run`, and hermetically reproducible because the flake pins every dependency.

## Why flake apps instead of buildbot-nix effects

buildbot-nix supports a Hercules CI-style effects system where post-build deployment steps run as part of the CI pipeline.
The architectural decision (ironstar-ohy.14, 2026-04-08) concluded that effects are not suitable for most CD operations for several reasons.

Effects have zero caching: they always re-execute on every build with no derivation-hash-based skip logic, so a deploy whose inputs have not changed still runs.
semantic-release, the primary versioning tool in ironstar, is inherently forge-coupled because it uses GITHUB_TOKEN or Gitea API tokens to create releases, tags, and changelogs.
Embedding this in buildbot effects adds an indirection layer without benefit.
Effects run in buildbot's execution model (concurrent, worker-dispatched), which conflicts with semantic-release's requirement for sequential, ordered execution across monorepo packages.
In practice, only 2 of 11 CD jobs in the ironstar pipeline were even viable effect candidates; the others are platform-coupled operations like tagging, releasing, and PR management.

Flake apps solve all of these constraints: they execute only when triggered by the CI platform rather than on every build, they receive platform credentials via environment variables as is natural for Actions workflows, they can be tested locally, and their dependencies are hermetically declared in the nix store.

buildbot-nix effects remain valuable for operations that are truly build-adjacent.
Cache warming is already handled by niks3 integration.
Artifact publishing to registries where the build output is the artifact fits naturally into the effects model.
Infrastructure-as-code applies where the deployment is itself a nix derivation.
The choice is not exclusive: effects and flake apps coexist, each serving the class of operations it is suited for.

## The writeShellApplication pattern for CD

Each deployment operation becomes a flake app built with `writeShellApplication`.
The following example illustrates the pattern:

```nix
apps.deploy-docs.program = lib.getExe (pkgs.writeShellApplication {
  name = "deploy-docs";
  runtimeInputs = with pkgs; [ bun sops git jq coreutils openssh ];
  text = ''
    # Decrypt Cloudflare credentials
    eval "$(sops exec-env vars/shared.yaml 'env')"
    
    # Build and deploy
    bun run --cwd packages/docs build
    bunx wrangler versions upload --tag "$(git rev-parse --short HEAD)"
  '';
});
```

The `runtimeInputs` attribute declares every dependency explicitly, and the script's PATH contains exactly these tools and nothing else.
`writeShellApplication` runs `shellcheck` at build time, catching shell scripting errors before execution.
`set -euo pipefail` is set by default.
The resulting app is a nix store path that can be cached, shared, and reproduced.

The corresponding CI workflow becomes minimal:

```yaml
- run: nix run .#deploy-docs
  env:
    SOPS_AGE_KEY: ${{ secrets.SOPS_AGE_KEY }}
```

The CI platform provides timing and secrets.
The flake owns everything else.

This pattern was observed in clan-website's `.#deploy` app, which uses the less idiomatic `writeShellScript` with manual `lib.makeBinPath` instead of `writeShellApplication` with `runtimeInputs`.
It is already used in vanixiets' `modules/home/tools/commands/default.nix` for developer tooling via the `makeShellApp` helper.

## Infrastructure that enables this pattern

The pattern depends on three infrastructure services deployed on magnetite as part of the vanixiets nix-7v7 epic.

*niks3 binary cache* (`cache.scientistexperience.net` for reads, `niks3.scientistexperience.net` for writes) provides persistent caching across all builds.
It uses a Cloudflare R2 backend with CDN edge caching for reads.
buildbot-nix pushes built paths automatically after successful builds.
Developers pull cached builds via nix substituters configuration.

*buildbot-nix* (`buildbot.scientistexperience.net`) evaluates flake checks with nix-eval-jobs, builds with worker parallelism, and pushes results to niks3.
It operates in dual-forge mode, discovering and building repos from both GitHub and Gitea simultaneously.
fullyPrivate mode with oauth2-proxy provides authenticated UI access.

*Gitea* (`git.scientistexperience.net`) is the self-hosted git forge with GitHub OAuth2 authentication.
Two Podman-based Actions runners are colocated on magnetite with nix store mounts.
These runners provide the CD execution environment for Gitea Actions workflows.
Actions runners have hermetic nix access inside containers via bind-mounted `/nix` store.

## Migration path

For projects currently using GitHub Actions for both CI and CD, such as ironstar, the migration proceeds in phases.

Phase 1 consolidates CI into `nix flake check`.
All validation concerns become flake check derivations.
buildbot-nix takes over CI evaluation and caching.
This phase is completed for ironstar.

Phase 2 creates `writeShellApplication` flake apps for each deployment operation.
Each app is tested locally with `nix run .#<app>`.
Existing GitHub Actions CD workflows continue running in parallel during this phase.

Phase 3 creates minimal Gitea Actions workflows that call `nix run .#<app>` with secrets injected via environment variables.
These are validated on magnetite's Podman-based runners.
semantic-release stays platform-native (GitHub Actions or Gitea Actions depending on the primary forge for a given project).

Phase 4 deprecates GitHub Actions CD workflows once their Gitea Actions equivalents are validated.
GitHub remains available for public-facing releases if desired.
Gitea becomes the primary CI/CD platform for private repositories.

## References

- vanixiets `modules/nixos/buildbot.nix` — buildbot-nix dual-forge configuration
- vanixiets `modules/nixos/gitea.nix` — Gitea service with GitHub OAuth
- vanixiets `modules/nixos/gitea-actions-runner.nix` — Podman-based Actions runners
- vanixiets `modules/home/tools/commands/default.nix` — writeShellApplication pattern for developer tools
- ironstar `.github/workflows/cd.yaml` — current GHA CD pipeline (target for nixification)
- ironstar `justfile` (`check-fast` recipe) — local nix-fast-build invocation
- clan-website `nix/apps/flake-module.nix` — clan's deploy flake app reference
- clan-infra `modules/web01/gitea/actions-runner.nix` — Podman runner reference implementation
- buildbot-nix `examples/fully-private-github.nix` — dual-forge configuration example
