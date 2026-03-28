{ ... }:
{
  flake.modules.homeManager.tools =
    { ... }:
    {
      programs.pandoc = {
        enable = true;
      };
      xdg.dataFile."pandoc/filters/headings.lua".source = ./filters/headings.lua;
    };
}
