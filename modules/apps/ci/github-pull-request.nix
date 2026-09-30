# Report whether a pull request is still open at a given head.
#
#   github-pull-request state --repo <owner/name> --number <N> --head-sha <sha>
#
# Why: nixbot delivers pull_request effects in no guaranteed order (a merge's
# pull_request_closed can precede the head's pull_request), so the docs preview
# and release plan effects share this one program to check the PR is currently
# open at the event's head before acting.
{ ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      apps.github-pull-request = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "github-pull-request";
            runtimeInputs = [
              pkgs.curl
              pkgs.jq
            ];
            text = builtins.readFile ./github-pull-request.sh;
          }
        );
      };
    };
}
