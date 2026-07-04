# Bash shell
{ ... }:
{
  flake.modules = {
    homeManager.shell =
      {
        pkgs,
        config,
        lib,
        flake,
        ...
      }:
      {
        programs.bash = {
          enable = true;
        };
      };
  };
}
