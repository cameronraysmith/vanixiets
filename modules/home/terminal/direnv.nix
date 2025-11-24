{ ... }:
{
  flake.modules.homeManager.terminal =
    { ... }:
    {
      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
        config.global = {
          warn_timeout = "10m";
        };
      };
    };
}
