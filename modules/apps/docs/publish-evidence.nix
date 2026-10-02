# Publish the docs browser report nixbot built for a build.
#
#   nix run .#publish-evidence -- build-finished [--out <dir>] [--upload]
#   nix run .#publish-evidence -- main --rev <commit> [--out <dir>] [--upload]
#
# The browser-evidence effect (modules/effects/vanixiets/effects.nix) runs
# `build-finished --upload` on nixbot's build_finished event and
# `main --upload --rev <rev>` on default-branch pushes. Evidence is keyed by
# the report's content (attribute and store path), so a report is uploaded
# once per tier. --upload writes the bundle into the R2 evidence bucket,
# served at https://evidence.vanixiets.net, with temporary credentials the
# program signs from the parent R2 token: read-write on the run's own tier
# only, and for a pull request read-only on main's ttl-90d. A pull request
# whose report main already published is unaffected (no upload, no
# comment, and a stale comment of its own is marked superseded); otherwise
# it uploads to ttl-30d and comments on the pull request.
#
# Why: the report and its metadata are untrusted build output, so the
# validator that judges them is this program's own copy of
# packages/docs/tests/report, interpolated as the non-exported shell variable
# `validator` so neither the environment nor the report can substitute it.
{ ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      apps.publish-evidence = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "publish-evidence";
            # The effect sandbox PATH is runtimeInputs only: curl reaches
            # nixbot's build API and R2's S3 API, nix provides nix-store to
            # realise the recorded report, node runs the validator and signs
            # the temporary R2 credential.
            runtimeInputs = [
              pkgs.nodejs_24
              pkgs.curl
              pkgs.jq
              pkgs.nix
              pkgs.coreutils
              pkgs.diffutils
              pkgs.findutils
            ];
            text = ''
              validator=${lib.escapeShellArg "${../../../packages/docs/tests/report}/validate-report.ts"}
              ${builtins.readFile ./publish-evidence.sh}
            '';
          }
        );
      };
    };
}
