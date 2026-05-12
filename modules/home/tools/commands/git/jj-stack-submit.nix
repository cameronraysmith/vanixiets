{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "jj-stack-submit";
          runtimeInputs = with pkgs; [
            jujutsu
            coreutils
            gh
            gitea
          ];
          text = builtins.readFile ./jj-stack-submit.sh;
          meta.description = "Push linearized chain bookmarks and open N+1 PRs (stacked-base chain PRs + aggregate targeting main) via gh or tea";
        })
      ];
    };
}
