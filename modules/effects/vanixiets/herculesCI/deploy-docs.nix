# herculesCI effect: deploy the docs to production on a push to main.
#
# The effect holds Cloudflare credentials, so it runs only code from main: the
# run-context guard refuses every other event. Runs share a lock so landings in
# quick succession deploy in order, and deploy.sh skips a run whose commit main
# has already moved past.
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
      shortRev = herculesCI.config.repo.shortRev;
      rev = herculesCI.config.repo.rev;

      runContext = config.flake.lib.effectRunContext;
    in
    {
      onPush.default.outputs.effects.deploy-docs = withSystem "x86_64-linux" (
        { config, pkgs, ... }:
        let
          hci-effects = inputs.hercules-ci-effects.lib.withPkgs pkgs;

          deployDocsProgram = config.apps.deploy-docs.program;
        in
        hci-effects.mkEffect {
          name = "deploy-docs";
          lock = "deploy-docs";

          # Declaring an audience is what makes nixbot expose its identity
          # endpoint to this effect; the token's claims are the only way the
          # script can tell a push to main from any other event.
          # Must be a JSON-array string: a bare nix list serialises
          # space-separated and nixbot rejects it before the sandbox starts.
          # buildbot-nix has no such endpoint and ignores this attribute.
          idTokenAudiences = builtins.toJSON [ runContext.audience ];

          # Why: the run-context guard needs curl, jq and coreutils; mkEffect's
          # defaultInputs are not relied on for any of them.
          inputs = [
            pkgs.curl
            pkgs.coreutils
            pkgs.jq
            # Why: building it is part of the pre-merge nixbot/effects gate.
            config.checks.deploy-docs-rehearsal
          ];

          # nixbot enforces hercules-ci secretsMap semantics: only the
          # destinations named here are written into
          # $HERCULES_CI_SECRETS_JSON, and mkEffect declares an empty map when
          # the caller omits one, which grants nothing at all. buildbot-nix
          # ignores the map and passes the whole file, so this narrows what
          # the script can read under nixbot and changes nothing under
          # buildbot-nix. Left-hand names are what the script reads;
          # right-hand names are keys in the composed secrets file.
          secretsMap = {
            CLOUDFLARE_API_TOKEN = "CLOUDFLARE_API_TOKEN";
            CLOUDFLARE_ACCOUNT_ID = "CLOUDFLARE_ACCOUNT_ID";
          };

          effectScript = ''
            set -euo pipefail

            ${runContext.mainOnlyGuard}

            echo "=== effects.deploy-docs (docs production deploy) ==="
            echo "rev:      ${lib.escapeShellArg (toString rev)}"
            echo "shortRev: ${lib.escapeShellArg (toString shortRev)}"

            export CLOUDFLARE_API_TOKEN="$(jq -r '.CLOUDFLARE_API_TOKEN.data.value' "$HERCULES_CI_SECRETS_JSON")"
            export CLOUDFLARE_ACCOUNT_ID="$(jq -r '.CLOUDFLARE_ACCOUNT_ID.data.value' "$HERCULES_CI_SECRETS_JSON")"

            export GIT_REV=${lib.escapeShellArg (toString rev)}
            export GIT_REV_SHORT=${lib.escapeShellArg (toString shortRev)}
            export GIT_REV_SHORT12=${lib.escapeShellArg (builtins.substring 0 12 (toString rev))}
            export GIT_BRANCH="$CI_BRANCH"
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

            deploy_log="$(mktemp -t deploy-docs-prod.XXXXXX.log)"
            set +e
            # Why: bwrap sandbox does not bind working tree; .# cannot resolve. Use eval-time /nix/store path.
            ${deployDocsProgram} production 2>&1 | tee "$deploy_log"
            deploy_rc=''${PIPESTATUS[0]}
            set -e
            if [ "$deploy_rc" -ne 0 ]; then
              echo "error: deploy-docs production exited $deploy_rc" >&2
              exit "$deploy_rc"
            fi
            # deploy.sh reports a superseded run itself and deploys nothing.
            if ! grep -q '^DEPLOY-DOCS-ACTION: superseded' "$deploy_log"; then
              echo "DEPLOY-DOCS-ACTION: deploy"
            fi

            echo "=== deploy-docs effect complete (exit 0) ==="
          '';
        }
      );
    };
}
