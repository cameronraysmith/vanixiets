{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "rerun-pr-checks";
          runtimeInputs = with pkgs; [ gh ];
          text = builtins.readFile ./rerun-pr-checks.sh;
          meta.description = "Re-run GitHub Actions workflow checks for a PR";
        })
      ];
    };
}
