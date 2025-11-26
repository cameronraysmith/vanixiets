{ config, ... }:
{
  clan.machines = {
    cinnabar = {
      imports = [ config.flake.modules.nixos."machines/nixos/cinnabar" ];
    };

    electrum = {
      imports = [ config.flake.modules.nixos."machines/nixos/electrum" ];
    };

    test-darwin = {
      imports = [ config.flake.modules.darwin."machines/darwin/test-darwin" ];
    };

    blackphos = {
      imports = [ config.flake.modules.darwin."machines/darwin/blackphos" ];
    };

    stibnite = {
      imports = [ config.flake.modules.darwin."machines/darwin/stibnite" ];
    };
  };
}
