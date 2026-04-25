# herculesCI effect: docs deployment branch-dispatcher (preview vs promote).
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
      # Nullable: null on tag pushes (no branch).
      branch = herculesCI.config.repo.branch;
      shortRev = herculesCI.config.repo.shortRev;
      rev = herculesCI.config.repo.rev;

      isMain = branch == "main";
    in
    {
      onPush.default.outputs.effects.deploy-docs = withSystem "x86_64-linux" (
        { config, pkgs, ... }:
        let
          hci-effects = inputs.hercules-ci-effects.lib.withPkgs pkgs;

          deployDocsProgram = config.apps.deploy-docs.program;

          actionBanner = if isMain then "promote" else "preview-upload";

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

            echo "DEPLOY-DOCS-ACTION: ${actionBanner}"

            export CLOUDFLARE_API_TOKEN="$(jq -r '.CLOUDFLARE_API_TOKEN.data.value' "$HERCULES_CI_SECRETS_JSON")"
            export CLOUDFLARE_ACCOUNT_ID="$(jq -r '.CLOUDFLARE_ACCOUNT_ID.data.value' "$HERCULES_CI_SECRETS_JSON")"

            export GIT_REV=${lib.escapeShellArg (toString rev)}
            export GIT_REV_SHORT=${lib.escapeShellArg (toString shortRev)}
            export GIT_REV_SHORT12=${lib.escapeShellArg (builtins.substring 0 12 (toString rev))}
            export GIT_BRANCH=${lib.escapeShellArg (if branch == null then "" else toString branch)}
            export GIT_COMMIT_MSG=${lib.escapeShellArg "effect deploy from rev ${toString shortRev}"}
            export GIT_WORKTREE_STATUS=clean

            # Why: whoami/hostname not on bwrap PATH; supply hard-coded values.
            export DEPLOY_DEPLOYER=hercules-ci-effects
            export DEPLOY_HOST=magnetite

            if [ -z "''${CLOUDFLARE_API_TOKEN:-}" ] || [ "$CLOUDFLARE_API_TOKEN" = "null" ]; then
              echo "error: CLOUDFLARE_API_TOKEN missing from \$HERCULES_CI_SECRETS_JSON" >&2
              exit 1
            fi
            if [ -z "''${CLOUDFLARE_ACCOUNT_ID:-}" ] || [ "$CLOUDFLARE_ACCOUNT_ID" = "null" ]; then
              echo "error: CLOUDFLARE_ACCOUNT_ID missing from \$HERCULES_CI_SECRETS_JSON" >&2
              exit 1
            fi

            # Why: bwrap sandbox does not bind working tree; .# cannot resolve. Use eval-time /nix/store path.
            DEPLOY_DOCS=${deployDocsProgram}

            ${
              if isMain then
                ''
                  # release.sh's production subcommand re-emits "falling back to direct deploy" on the fresh-deploy fallback; the dispatcher grep below depends on that exact substring.
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
