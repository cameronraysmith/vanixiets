{ ... }:
{
  flake.modules.homeManager.terminal =
    { ... }:
    {
      programs.lsd = {
        enable = true;
        enableBashIntegration = true;
        enableZshIntegration = true;
      };
    };
}
