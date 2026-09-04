{ ... }:
{
  flake.modules.homeManager.terminal =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        zstd
        # snzip
      ];
    };
}
