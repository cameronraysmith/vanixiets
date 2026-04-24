# effects.deploy-docs — docs deployment branch-dispatcher (M4 feature
# `m4-deploy-docs`). Consolidates three pre-consolidation jobs
# (preview-docs-deploy, production-docs-deploy-dryrun,
# production-docs-deploy-cutover) into a single herculesCI effect that
# dispatches on `primaryRepo.branch`.
#
# Design contract (see mission AGENTS.md "ADR-002 locked decisions" and
# `.factory/validation-contract.md` VAL-EFFECT-DEPLOYDOCS-*):
#
#   Option Gamma store-path embedding:
#     The effect body invokes the `deploy-docs` flake app via the
#     nix-eval-time resolved store path
#     `${config.apps.x86_64-linux.deploy-docs.program}`. The effect
#     never dispatches via a flake-app shell-out (bwrap does not bind
#     the working tree, so the .# syntax cannot resolve).
#
#   Branch dispatch (exact string equality):
#     Selection is driven by `primaryRepo.branch == "main"`, surfaced
#     through `herculesCI.config.repo.branch` which hercules-ci-effects
#     populates from the primaryRepo record at flake.herculesCI entry.
#     * primaryRepo.branch == "main"  → production promote path
#     * any other branch (or null)    → preview upload path
#
#   Pattern C'-refined secrets preamble:
#     Extracts CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID from
#     $HERCULES_CI_SECRETS_JSON at the `.<KEY>.data.value` envelope
#     (see modules/effects/vanixiets/secrets.nix for the generator that
#     emits this shape). Never extracts SOPS_AGE_KEY (ADR-002
#     exclusivity) and never references NPM_TOKEN.
#
#   Posture A outer gate:
#     Fork-PR exposure is blocked by `effects_on_pull_requests = false`
#     + `effects_branches` in `buildbot-nix.toml`, which precedes this
#     inner branch-dispatch. The dispatcher logic runs only after the
#     outer gate has passed.
#
#   Structured banners (DD-16 log-grep anchors):
#     * `DEPLOY-DOCS-ACTION: preview-upload|promote|fresh-deploy-and-promote`
#       emitted exactly once per run, identifying the dispatcher path
#       taken. `fresh-deploy-and-promote` is emitted post-hoc on the
#       main path only when deploy.sh reports the fallback branch.
#     * `DEPLOY-DOCS-PREVIEW-URL: <url>` emitted on the preview path
#       once the wrangler-produced preview URL is parsed from deploy.sh
#       stdout, enabling downstream `curl` verification of 200 OK.
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
      # in Nix, so tag pushes naturally fall through to the preview path.
      isMain = branch == "main";
    in
    {
      onPush.default.outputs.effects.deploy-docs = withSystem "x86_64-linux" (
        { config, pkgs, ... }:
        let
          hci-effects = inputs.hercules-ci-effects.lib.withPkgs pkgs;

          # Option Gamma: resolved at nix eval time to a /nix/store path
          # that the bwrap sandbox can execute without a working-tree or
          # nix-daemon lookup.
          deployDocsProgram = config.apps.deploy-docs.program;

          # Initial action banner — refined post-hoc on the main path if
          # deploy.sh's fresh-deploy-and-promote fallback triggers.
          actionBanner = if isMain then "promote" else "preview-upload";

          # Preview branch argument: prefer the live branch name; fall
          # back to the shortRev on detached / null-branch pushes so
          # deploy.sh preview has a non-empty argument.
          previewBranchArg = if branch != null && branch != "" then branch else shortRev;
        in
        hci-effects.mkEffect {
          name = "deploy-docs";

          effectScript = ''
            set -euo pipefail

            echo "=== effects.deploy-docs (docs deployment dispatcher) ==="
            echo "branch:   ${lib.escapeShellArg (toString branch)}"
            echo "rev:      ${lib.escapeShellArg (toString rev)}"
            echo "shortRev: ${lib.escapeShellArg (toString shortRev)}"
            echo "isMain:   ${if isMain then "true" else "false"}"

            # Structured banner (DD-16): emitted once per run so log-grep
            # can distinguish preview-upload | promote | fresh-deploy-and-promote.
            echo "DEPLOY-DOCS-ACTION: ${actionBanner}"

            # Secrets preamble — Pattern C'-refined (ADR-002):
            # extract CLOUDFLARE_API_TOKEN from $HERCULES_CI_SECRETS_JSON at .data.value envelope.
            export CLOUDFLARE_API_TOKEN="$(jq -r '.CLOUDFLARE_API_TOKEN.data.value' "$HERCULES_CI_SECRETS_JSON")"
            # Secrets preamble — Pattern C'-refined (ADR-002):
            # extract CLOUDFLARE_ACCOUNT_ID from $HERCULES_CI_SECRETS_JSON at .data.value envelope.
            export CLOUDFLARE_ACCOUNT_ID="$(jq -r '.CLOUDFLARE_ACCOUNT_ID.data.value' "$HERCULES_CI_SECRETS_JSON")"

            # Env-var-contract guard: fail fast if the secrets bundle is
            # missing either Cloudflare key. Message excludes the value;
            # only key name is echoed (VAL-EFFECT-DEPLOYDOCS-21).
            if [ -z "''${CLOUDFLARE_API_TOKEN:-}" ] || [ "$CLOUDFLARE_API_TOKEN" = "null" ]; then
              echo "error: CLOUDFLARE_API_TOKEN missing from \$HERCULES_CI_SECRETS_JSON" >&2
              exit 1
            fi
            if [ -z "''${CLOUDFLARE_ACCOUNT_ID:-}" ] || [ "$CLOUDFLARE_ACCOUNT_ID" = "null" ]; then
              echo "error: CLOUDFLARE_ACCOUNT_ID missing from \$HERCULES_CI_SECRETS_JSON" >&2
              exit 1
            fi

            # Option Gamma store-path dispatch — the `deploy-docs` flake
            # app's /nix/store path is embedded at eval time via
            # the perSystem config.apps.deploy-docs.program attribute.
            # No flake-app shell-out (bwrap would not resolve .#).
            DEPLOY_DOCS=${deployDocsProgram}

            ${
              if isMain then
                ''
                  # Main branch → promote-by-SHA path.
                  # deploy.sh's `production` subcommand looks up a Worker
                  # version whose workers/tag annotation matches the
                  # current commit short-SHA-12 (uploaded earlier on the
                  # pre-merge branch push). If found, it promotes via
                  # `wrangler versions deploy <id>@100%` (no re-upload →
                  # VAL-EFFECT-DEPLOYDOCS-16). If absent, it falls back
                  # to a fresh deploy + promote, logged with the literal
                  # substring "falling back to direct deploy". The
                  # dispatcher re-emits a DEPLOY-DOCS-ACTION banner to
                  # disambiguate the two execution paths for log-grep.
                  deploy_log="$(mktemp -t deploy-docs-prod.XXXXXX.log)"
                  set +e
                  "$DEPLOY_DOCS" production 2>&1 | tee "$deploy_log"
                  deploy_rc=''${PIPESTATUS[0]}
                  set -e
                  if grep -q "falling back to direct deploy" "$deploy_log"; then
                    echo "DEPLOY-DOCS-ACTION: fresh-deploy-and-promote"
                  fi
                  if [ "$deploy_rc" -ne 0 ]; then
                    echo "error: deploy-docs production exited $deploy_rc" >&2
                    exit "$deploy_rc"
                  fi
                ''
              else
                ''
                  # Non-main → preview upload path.
                  # deploy.sh's `preview <branch>` subcommand uploads a
                  # new Cloudflare Workers version tagged with the
                  # commit short-SHA-12, aliased at
                  # b-<sanitized-branch>-infra-docs.sciexp.workers.dev.
                  # The script emits a `Preview URL:` line on success
                  # which we parse + re-emit as a structured banner
                  # (DEPLOY-DOCS-PREVIEW-URL) for downstream 200-probes.
                  preview_log="$(mktemp -t deploy-docs-preview.XXXXXX.log)"
                  set +e
                  "$DEPLOY_DOCS" preview ${lib.escapeShellArg previewBranchArg} 2>&1 | tee "$preview_log"
                  upload_rc=''${PIPESTATUS[0]}
                  set -e
                  preview_url="$(grep -oE 'Preview URL: https://[^[:space:]]+' "$preview_log" | head -1 | awk '{print $3}' || true)"
                  if [ -n "$preview_url" ]; then
                    echo "DEPLOY-DOCS-PREVIEW-URL: $preview_url"
                  else
                    echo "warning: could not parse preview URL from deploy.sh output" >&2
                  fi
                  if [ "$upload_rc" -ne 0 ]; then
                    echo "error: deploy-docs preview exited $upload_rc" >&2
                    exit "$upload_rc"
                  fi
                ''
            }

            echo "=== deploy-docs effect complete (exit 0) ==="
          '';
        }
      );
    };
}
