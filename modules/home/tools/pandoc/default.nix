{ config, ... }:
{
  flake.modules.homeManager.tools.imports = [ config.flake.modules.homeManager.pandoc ];
  flake.modules.homeManager.pandoc = {
    key = "vanixiets/pandoc-home-module";
    programs.pandoc = {
      enable = true;
    };
    xdg.dataFile."pandoc/filters/headings.lua".source = ./filters/headings.lua;
  };
}
