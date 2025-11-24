{ ... }:
{
  flake.modules.homeManager.terminal =
    { ... }:
    {
      programs.htop.enable = true;
    };
}
