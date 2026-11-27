{ config, ... }:
{
  flake.modules.homeManager = config.flake.lib.exportAs {
    key = "ripgrep";
    names = [
      "terminal"
      "ripgrep"
    ];
    module =
      { ... }:
      {
        programs.ripgrep.enable = true;
      };
  };
}
