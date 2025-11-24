{ ... }:
{
  flake.modules.homeManager.tools =
    { ... }:
    {
      programs.k9s = {
        enable = true;
      };
    };
}
