{ ... }:
{
  flake.modules.homeManager.terminal =
    { ... }:
    {
      programs.btop.enable = true;
    };
}
