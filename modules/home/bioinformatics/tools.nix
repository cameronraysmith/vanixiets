{ ... }:
{
  flake.modules.homeManager.bioinformatics =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        minimap2
        star
        xsra
      ];
    };
}
