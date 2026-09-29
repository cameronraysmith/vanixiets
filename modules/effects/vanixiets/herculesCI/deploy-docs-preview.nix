# herculesCI onEvent effect: upload a docs preview for each pull request.
#
# nixbot evaluates onEvent from the default branch whatever pull request the
# event is about, so this script and everything it runs come from main. The
# pull request contributes data only: its number, head rev, and the docs
# payload nixbot already built for it, located through nixbot's build API and
# realised by store path without evaluating anything. No pull request code is
# evaluated or executed while the Cloudflare token is readable; the payload's
# bytes are untrusted, which deploy-docs' preview path accounts for.
#
# The run-context guard is not used: an event effect's identity token is
# pull_request-shaped whatever the event, so the guard would always refuse,
# and the code already comes from main.
#
# Event effects post no commit status and do not count towards nixbot/effects,
# so a failed preview never blocks a merge; the outcome is reported as a pull
# request comment instead. Pull request builds still build this effect's
# dependencies as a check.
{
  inputs,
  lib,
  withSystem,
  ...
}:
{
  herculesCI.onEvent.pull_request.deploy-docs-preview = withSystem "x86_64-linux" (
    { config, pkgs, ... }:
    let
      hci-effects = inputs.hercules-ci-effects.lib.withPkgs pkgs;

      deployDocsProgram = config.apps.deploy-docs.program;

      # nixbot builds nixbot.toml's `attribute` (checks.x86_64-linux), where
      # modules/checks/packages.nix exposes the docs package; reported
      # attribute names carry that prefix.
      docsAttr = "checks.x86_64-linux.package-vanixiets-docs";
      buildsApi = "api/repos/github/cameronraysmith/vanixiets/builds";
    in
    hci-effects.mkEffect {
      name = "deploy-docs-preview";

      # nixbot extension: {pr} expands to the pull request number, so runs for
      # one pull request are ordered and different pull requests run in
      # parallel.
      lock = "deploy-docs-preview-{pr}";

      # nixbot reads `when` off the effect value; passthru keeps the attrset
      # out of the derivation environment. The pusher or the author must be
      # able to write to the repository: approval of an outside pull request
      # is sticky across its later pushes, and a preview publishes its content
      # with our token. A writer labelling such a pull request previews it.
      passthru.when.permission = "write";

      inputs = [
        pkgs.coreutils
        pkgs.curl
        pkgs.gnugrep
        pkgs.jq
        pkgs.nix
        # Why: building it is part of the pre-merge nixbot/effects gate.
        config.checks.deploy-docs-rehearsal
      ];

      # See deploy-docs.nix for why this map is required under nixbot.
      secretsMap = {
        CLOUDFLARE_API_TOKEN = "CLOUDFLARE_API_TOKEN";
        CLOUDFLARE_ACCOUNT_ID = "CLOUDFLARE_ACCOUNT_ID";
      };

      effectScript = ''
        set -euo pipefail

        : "''${NIXBOT_API_URL:?}" "''${NIXBOT_API_TOKEN:?}" "''${NIXBOT_EVENT_JSON:?}"
        if [ "''${NIXBOT_EVENT_KIND:-}" != pull_request ]; then
          echo "error: expected a pull_request event, got ''${NIXBOT_EVENT_KIND:-none}" >&2
          exit 1
        fi
        pr="''${NIXBOT_PR_NUMBER:-}"
        head_rev="''${NIXBOT_PR_HEAD:-}"
        build_number="$(jq -r '.build.number // empty' "$NIXBOT_EVENT_JSON")"
        if ! [[ "$pr" =~ ^[0-9]+$ && "$head_rev" =~ ^[0-9a-f]{40}$ && "$build_number" =~ ^[0-9]+$ ]]; then
          echo "error: malformed event (pr=$pr head=$head_rev build=$build_number)" >&2
          exit 1
        fi

        comment() {
          jq -n --arg body "$1" '{body: $body, marker: "deploy-docs-preview"}' \
            | curl -fsS --retry 3 -X POST "$NIXBOT_API_URL/api/v1/pr-comment" \
                -H "Authorization: Bearer $NIXBOT_API_TOKEN" \
                -H 'Content-Type: application/json' \
                --data @-
        }
        report_failure() {
          local rc=$?
          if [ "$rc" -ne 0 ]; then
            comment "Docs preview failed for ''${head_rev:0:12}: ''${NIXBOT_BUILD_URL:-see nixbot}" || true
          fi
        }
        trap report_failure EXIT

        echo "=== effects.deploy-docs-preview (pull request #$pr at ''${head_rev:0:12}) ==="

        # The store path nixbot built for this pull request, by build number
        # from the event: no evaluation of the pull request's flake.
        build_json="$(curl -fsS --retry 3 "$NIXBOT_API_URL/${buildsApi}/$build_number")"
        payload="$(jq -er --arg attr ${lib.escapeShellArg docsAttr} '
          select(.build.status == "succeeded")
          | .attributes[]
          | select(.attr == $attr and .status == "succeeded")
          | .outputs.out' <<<"$build_json")"
        if ! [[ "$payload" =~ ^/nix/store/[0-9a-z]{32}-[^/]+$ ]]; then
          echo "error: build $build_number has no store path for ${docsAttr}: $payload" >&2
          exit 1
        fi
        nix-store --realise "$payload" >/dev/null

        export CLOUDFLARE_API_TOKEN="$(jq -r '.CLOUDFLARE_API_TOKEN.data.value' "$HERCULES_CI_SECRETS_JSON")"
        export CLOUDFLARE_ACCOUNT_ID="$(jq -r '.CLOUDFLARE_ACCOUNT_ID.data.value' "$HERCULES_CI_SECRETS_JSON")"
        for var in CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID; do
          if [ -z "''${!var}" ] || [ "''${!var}" = null ]; then
            echo "error: $var missing from \$HERCULES_CI_SECRETS_JSON" >&2
            exit 1
          fi
        done

        export DOCS_PAYLOAD="$payload"
        export GIT_REV="$head_rev"
        export GIT_REV_SHORT="''${head_rev:0:7}"
        export GIT_REV_SHORT12="''${head_rev:0:12}"
        export GIT_BRANCH="pr-$pr"
        export GIT_COMMIT_MSG="pull request #$pr"
        export GIT_WORKTREE_STATUS=clean
        # Why: whoami/hostname not on bwrap PATH; supply hard-coded values.
        export DEPLOY_DEPLOYER=nixbot
        export DEPLOY_HOST=magnetite

        preview_log="$(mktemp -t deploy-docs-preview.XXXXXX.log)"
        ${deployDocsProgram} preview "pr-$pr" 2>&1 | tee "$preview_log"
        preview_url="$(grep -oE 'Preview URL: https://[^[:space:]]+' "$preview_log" | head -n1 | cut -d' ' -f3)"
        if [ -z "$preview_url" ]; then
          echo "error: deploy-docs preview printed no Preview URL" >&2
          exit 1
        fi
        echo "DEPLOY-DOCS-PREVIEW-URL: $preview_url"
        comment "Docs preview for ''${head_rev:0:12}: $preview_url"
      '';
    }
  );
}
