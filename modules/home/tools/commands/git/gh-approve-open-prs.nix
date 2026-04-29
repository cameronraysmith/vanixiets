{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "gh-approve-open-prs";
          runtimeInputs = with pkgs; [ gh ];
          text = builtins.readFile ./gh-approve-open-prs.sh;
          meta.description = "Approve all open PRs with optional exclusions";
        })
      ];
    };
}
