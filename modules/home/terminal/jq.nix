{ ... }:
{
  flake.modules.homeManager.terminal =
    { ... }:
    {
      programs.jq.enable = true;
    };
}
