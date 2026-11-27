{ config, ... }:
{
  flake.modules.homeManager = config.flake.lib.exportAs {
    key = "fd";
    names = [
      "terminal"
      "fd"
    ];
    module =
      { ... }:
      {
        programs.fd.enable = true;
      };
  };
}
