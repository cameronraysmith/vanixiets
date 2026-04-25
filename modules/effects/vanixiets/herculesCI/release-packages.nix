# effects.release-packages — semantic-release per-package dispatcher
# (M4 feature `m4-release-packages`). Consolidates three pre-consolidation
# jobs (preview-release-version, production-release-packages-dryrun,
# production-release-packages-cutover) into a single herculesCI effect
# that iterates every package discovered under `packages/*` and dispatches
# `semantic-release` with branch-aware behaviour.
#
# Design contract (see mission AGENTS.md "ADR-002 locked decisions" and
# `.factory/validation-contract.md` VAL-EFFECT-RELEASEPACKAGES-*):
#
#   Option Gamma store-path embedding:
#     The effect body invokes both the `list-packages-json` and `release`
#     flake apps via the nix-eval-time resolved store paths
#     `${config.apps.x86_64-linux.list-packages-json.program}` and
#     `${config.apps.x86_64-linux.release.program}`. The effect never
#     dispatches via a flake-app shell-out (`nix run`); bwrap does not
#     bind the working tree, so the .# syntax cannot resolve.
#
#   Branch dispatch (exact string equality):
#     Selection is driven by `primaryRepo.branch == "main"`, surfaced
#     through `herculesCI.config.repo.branch` which hercules-ci-effects
#     populates from the primaryRepo record at flake.herculesCI entry.
#     * primaryRepo.branch == "main"  → real semantic-release per package
#         (semantic-release's per-package commit-analyzer decides whether
#         to cut a release; tag push + GitHub Release published when so;
#         npmPublish stays false — never overridden).
#     * any other branch (or null)    → per-package `--dry-run`
#         (semantic-release prints the next-version preview only; no git
#         tags pushed, no GitHub Release created, no remote git mutation).
#
#   Pattern C'-refined secrets preamble:
#     Extracts GITHUB_TOKEN ONLY from $HERCULES_CI_SECRETS_JSON at the
#     `.GITHUB_TOKEN.data.value` envelope (see
#     modules/effects/vanixiets/secrets.nix for the generator that emits
#     this shape). Per ADR-002 §5.3 exclusivity audit, this effect MUST
#     NOT consume SOPS_AGE_KEY (load-bearing only for k3d-bootstrap-secrets)
#     and MUST NOT reference NPM_TOKEN (not part of the closed 4-key
#     bundle; npmPublish=false invariant means no npm publish surface).
#
#   Symmetric env-var contract (CI + GIT_AUTHOR/COMMITTER + RELEASE_REPO_ROOT)
#   (m4-release-packages-runtime-deps-contract):
#     Exports CI=true, GIT_BRANCH (from herculesCI.config.repo.branch at
#     eval time via lib.escapeShellArg), RELEASE_REPO_ROOT="$PWD" (mkEffect
#     cwd is the source root), and the GIT_AUTHOR_NAME/EMAIL +
#     GIT_COMMITTER_NAME/EMAIL identity quartet. Required because the
#     buildbot-effects bwrap sandbox does not bind-mount the working tree's
#     .git AND provides no host-PATH binaries beyond /nix/store ro-bind +
#     writeShellApplication runtimeInputs PATH (upstream-by-design across
#     all 3 reference effect implementations); release.sh's
#     `git rev-parse --show-toplevel` would fail with `fatal: not a git
#     repository`, its `git config user.{name,email} "…"` writes would
#     fail with `error: could not lock config file .git/config`, and
#     semantic-release would abort with `running on a CI environment is
#     required` (env-ci default) without these exports. Symmetric to
#     the deploy-docs env-var contract (GIT_* + DEPLOY_*) precedent.
#
#   Per-package atomicity (NOT fail-fast):
#     If package A fails, the loop continues to package B. Each
#     per-package failure is recorded; the dispatcher exits non-zero at
#     the end iff ANY package failed. Successful per-package tags +
#     GitHub Releases persist (semantic-release's own per-package
#     mutations are atomic per-package); failures surface via the
#     RELEASE-PACKAGE-FAILURE banners for manual re-trigger.
#
#   Posture A outer gate:
#     Fork-PR exposure is blocked by `effects_on_pull_requests = false`
#     in `buildbot-nix.toml`, which precedes this inner branch-dispatch.
#     The dispatcher logic runs only after the outer gate has passed.
#
#   Structured banners (RP-05 / RP-06 / RP-19 log-grep anchors):
#     * `RELEASE-PACKAGES-ACTION: dry-run|release` emitted exactly once
#       per run, identifying the dispatcher path taken (analogous to the
#       deploy-docs DEPLOY-DOCS-ACTION banner).
#     * `RELEASE-PACKAGE-ITERATION: <pkg-path>` emitted before each
#       per-package release invocation (count must equal
#       `just list-packages-json | jq length`).
#     * `RELEASE-PACKAGE-OK: <pkg-path>` emitted on per-package success.
#     * `RELEASE-PACKAGE-FAILURE: <pkg-path> (exit <rc>)` emitted on
#       per-package failure; the loop continues regardless.
{
  config,
  inputs,
  lib,
  withSystem,
  ...
}:
{
  herculesCI =
    herculesCI:
    let
      # primaryRepo.branch (exposed as config.repo.branch by
      # hercules-ci-effects' paramModule, populated from primaryRepo.branch
      # at flake.herculesCI entry). Type: nullable string — null on tag
      # pushes where branch is not populated.
      branch = herculesCI.config.repo.branch;
      shortRev = herculesCI.config.repo.shortRev;
      rev = herculesCI.config.repo.rev;

      # Branch dispatch: exact string equality. null == "main" is false
      # in Nix, so tag pushes naturally fall through to the dry-run path.
      isMain = branch == "main";

      # Action banner emitted once per run (RP-05 log-grep anchor).
      actionBanner = if isMain then "release" else "dry-run";

      # Eval-time --dry-run flag injection. Empty on main, "--dry-run"
      # otherwise. Ordered AFTER the package-path positional arg per
      # release.sh's CLI grammar (`release <package-path> [--dry-run]`).
      dryRunFlag = if isMain then "" else "--dry-run";
    in
    {
      onPush.default.outputs.effects.release-packages = withSystem "x86_64-linux" (
        { config, pkgs, ... }:
        let
          hci-effects = inputs.hercules-ci-effects.lib.withPkgs pkgs;

          # Option Gamma: resolved at nix eval time to /nix/store paths
          # that the bwrap sandbox can execute without a working-tree or
          # nix-daemon lookup.
          listPackagesProgram = config.apps.list-packages-json.program;
          releaseProgram = config.apps.release.program;
        in
        hci-effects.mkEffect {
          name = "release-packages";

          effectScript = ''
            set -euo pipefail

            echo "=== effects.release-packages (semantic-release per-package dispatcher) ==="
            echo "branch:   ${lib.escapeShellArg (toString branch)}"
            echo "rev:      ${lib.escapeShellArg (toString rev)}"
            echo "shortRev: ${lib.escapeShellArg (toString shortRev)}"
            echo "isMain:   ${if isMain then "true" else "false"}"

            # Structured banner (RP log-grep anchor): emitted once per run
            # so log-grep can distinguish dry-run vs release dispatch path.
            echo "RELEASE-PACKAGES-ACTION: ${actionBanner}"

            # Secrets preamble — Pattern C'-refined (ADR-002):
            # extract GITHUB_TOKEN ONLY from $HERCULES_CI_SECRETS_JSON
            # at the .data.value envelope. The other bundle keys are
            # intentionally NOT extracted here — exclusivity rules and
            # the npm-publish-never invariant are documented in the
            # outer-module doc-comments (kept out of the rendered
            # effectScript to satisfy VAL-EFFECT-RELEASEPACKAGES-22 /
            # -24's `rg -c` zero-match contract on effectScript output).
            export GITHUB_TOKEN="$(jq -r '.GITHUB_TOKEN.data.value' "$HERCULES_CI_SECRETS_JSON")"

            # Env-var-contract guard: fail fast if the secrets bundle is
            # missing GITHUB_TOKEN. Message excludes the value; only key
            # name is echoed.
            if [ -z "''${GITHUB_TOKEN:-}" ] || [ "$GITHUB_TOKEN" = "null" ]; then
              echo "error: GITHUB_TOKEN missing from \$HERCULES_CI_SECRETS_JSON" >&2
              exit 1
            fi

            # Symmetric env-var contract (m4-release-packages-runtime-deps-contract):
            # populate CI / GIT_BRANCH / RELEASE_REPO_ROOT and the
            # GIT_AUTHOR_*/GIT_COMMITTER_* identity quartet so release.sh
            # never has to invoke `git rev-parse --show-toplevel` or
            # `git config user.{name,email} "…"` inside the bwrap sandbox.
            # CI is set so env-ci recognises the run as non-interactive CI,
            # bypassing semantic-release's `running on a CI environment is
            # required` abort. GIT_BRANCH is interpolated at nix eval time
            # from herculesCI.config.repo.branch (empty string on tag-push
            # where branch is null). RELEASE_REPO_ROOT="$PWD": mkEffect cwd
            # is the source root, so $PWD is the canonical repo root inside
            # the sandbox. GIT_AUTHOR_*/GIT_COMMITTER_*: hard-coded identity
            # for the semantic-release CHANGELOG commit; git honours these
            # env vars natively without writing to .git/config.
            export CI=true
            export GIT_BRANCH=${lib.escapeShellArg (if branch == null then "" else toString branch)}
            export RELEASE_REPO_ROOT="$PWD"
            export GIT_AUTHOR_NAME=semantic-release
            export GIT_AUTHOR_EMAIL=semantic-release@vanixiets.local
            export GIT_COMMITTER_NAME=semantic-release
            export GIT_COMMITTER_EMAIL=semantic-release@vanixiets.local

            # Option Gamma store-path dispatch — both flake apps' /nix/store
            # paths are embedded at eval time via the perSystem
            # config.apps.<name>.program attributes. No flake-app shell-out
            # (bwrap would not resolve .#).
            LIST_PACKAGES=${listPackagesProgram}
            RELEASE=${releaseProgram}

            # Discover packages under packages/* (jq-driven enumeration of
            # the list-packages-json output).
            packages_json="$("$LIST_PACKAGES")"
            echo "packages discovered: $packages_json"

            # Per-package failure tracker — populated inside the loop;
            # used at end-of-loop to set the aggregate exit code.
            failed_packages=()

            # Per-package atomicity loop: iterate every {name, path}
            # entry. Read paths into the loop via process substitution
            # over `jq -r '.[].path'` (one path per line, robust to
            # paths-with-spaces unlike `for pkg in $(...)`).
            while IFS= read -r pkg_path; do
              [ -z "$pkg_path" ] && continue

              echo "RELEASE-PACKAGE-ITERATION: $pkg_path"

              # Disable -e for the per-package invocation so a single
              # package's failure does not abort the loop. We capture
              # the exit code, log appropriately, and continue.
              set +e
              "$RELEASE" "$pkg_path" ${dryRunFlag}
              rc=$?
              set -e

              if [ "$rc" -eq 0 ]; then
                echo "RELEASE-PACKAGE-OK: $pkg_path"
              else
                echo "RELEASE-PACKAGE-FAILURE: $pkg_path (exit $rc)"
                failed_packages+=("$pkg_path")
              fi
            done < <(printf '%s\n' "$packages_json" | jq -r '.[].path')

            # Aggregate exit code: OR of all per-package results. Zero
            # iff every package's invocation exited zero (or zero
            # packages were discovered, which is itself a degenerate
            # success). Non-zero iff any package failed; the failed
            # set is enumerated in stderr for operator triage.
            if [ "''${#failed_packages[@]}" -gt 0 ]; then
              echo "error: ''${#failed_packages[@]} package(s) failed: ''${failed_packages[*]}" >&2
              exit 1
            fi

            echo "=== release-packages effect complete (exit 0) ==="
          '';
        }
      );
    };
}
