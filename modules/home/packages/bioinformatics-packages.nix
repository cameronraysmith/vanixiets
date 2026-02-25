{ ... }:
{
  flake.modules.homeManager.packages =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        # bioinformatics
        minimap2
        star
        xsra
      ];
    };
}
