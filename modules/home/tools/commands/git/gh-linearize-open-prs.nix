{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "gh-linearize-open-prs";
          runtimeInputs = with pkgs; [
            gh
            jujutsu
            jq
            coreutils
          ];
          text = builtins.readFile ./gh-linearize-open-prs.sh;
          meta.description = "Linearize commits from open PR branches onto a new jj bookmark";
        })
      ];
    };
}
