{ ... }:
{
  flake.modules.homeManager.terminal =
    { ... }:
    {
      programs.nix-index = {
        enable = true;
        enableZshIntegration = true;
      };
      programs.nix-index-database.comma.enable = true;
    };
}
