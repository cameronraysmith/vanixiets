# Upload a docs preview for a pull request from nixbot's pull_request event.
#
#   docs-preview      (no arguments; reads the nixbot event environment)
#
# Runs from the default branch whatever pull request the event is about. The
# pull request contributes data only: its number, head rev, and the docs
# payload nixbot already built for it, located through nixbot's build API and
# realised by store path. Nothing from the pull request is evaluated or run
# while the Cloudflare token is readable; the payload's bytes are untrusted,
# which `deploy-docs preview` accounts for.
#
# Event effects post no commit status, so the outcome is reported as the
# `docs-preview` check run on the head commit through the forge token.
#
# Environment: NIXBOT_EVENT_KIND, NIXBOT_EVENT_JSON, NIXBOT_PR_NUMBER,
# NIXBOT_PR_HEAD, NIXBOT_API_URL, GITHUB_FORGE_TOKEN, and CLOUDFLARE_API_TOKEN
# / CLOUDFLARE_ACCOUNT_ID for deploy-docs. Test seams: GITHUB_API_URL,
# DOCS_PREVIEW_DEPLOY_DOCS.
#
# Interpolation form: `text` injects deploy-docs' store path as the default.
{ ... }:
{
  perSystem =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      apps.docs-preview = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "docs-preview";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.curl
              pkgs.gnugrep
              pkgs.jq
              pkgs.nix
            ];
            text = ''
              deploy_docs="''${DOCS_PREVIEW_DEPLOY_DOCS:-${config.apps.deploy-docs.program}}"
              ${builtins.readFile ./docs-preview.sh}
            '';
          }
        );
      };
    };
}
