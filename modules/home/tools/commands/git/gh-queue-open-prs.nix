{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "gh-queue-open-prs";
          runtimeInputs = with pkgs; [
            gh
            jq
          ];
          text = builtins.readFile ./gh-queue-open-prs.sh;
          meta.description = "Report required-check status for open PRs and authorize the merge queue";
        })
      ];
    };
}
