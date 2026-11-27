{ config, ... }:
{
  flake.modules.homeManager = config.flake.lib.exportAs {
    key = "jq";
    names = [
      "terminal"
      "jq"
    ];
    module =
      { ... }:
      {
        programs.jq.enable = true;
      };
  };
}
