{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "commit-checks";
          runtimeInputs = with pkgs; [
            gh
            tea
            jq
          ];
          text = builtins.readFile ./commit-checks.sh;
          meta.description = "Show commit-keyed checks for GitHub or Gitea remotes";
        })
      ];
    };
}
