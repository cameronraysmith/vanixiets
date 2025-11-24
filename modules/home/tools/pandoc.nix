{ ... }:
{
  flake.modules.homeManager.tools =
    { ... }:
    {
      programs.pandoc = {
        enable = true;
      };
    };
}
