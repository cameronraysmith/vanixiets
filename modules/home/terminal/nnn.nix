{ ... }:
{
  flake.modules.homeManager.terminal =
    { pkgs, ... }:
    {
      programs.nnn = {
        enable = true;
        package = pkgs.nnn.override { withNerdIcons = true; };
        plugins = {
          mappings = {
            K = "preview-tui";
          };
          src = pkgs.nnn + "/plugins";
        };
      };
    };
}
