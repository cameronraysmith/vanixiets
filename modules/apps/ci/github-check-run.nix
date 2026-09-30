# Create and complete GitHub check runs with nixbot's forge token.
#
#   github-check-run create --repo <owner/name> --name <check> --head-sha <sha>
#   github-check-run complete --repo <owner/name> --id <id> --conclusion <c> \
#     --title <t> --summary <s> [--details-url <u>]
#
# Why: event effects post no commit status, so each reports its outcome as a
# check run on the head commit; the docs and release-packages effects share
# this one program so their requests cannot drift apart.
{ ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      apps.github-check-run = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "github-check-run";
            runtimeInputs = [
              pkgs.curl
              pkgs.jq
            ];
            text = builtins.readFile ./github-check-run.sh;
          }
        );
      };
    };
}
