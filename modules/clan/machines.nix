{ config, ... }:
{
  clan.machines = {
    cinnabar = {
      imports = [ config.flake.modules.nixos."machines/nixos/cinnabar" ];
    };

    electrum = {
      imports = [ config.flake.modules.nixos."machines/nixos/electrum" ];
    };

    galena = {
      imports = [ config.flake.modules.nixos."machines/nixos/galena" ];
    };

    scheelite = {
      imports = [ config.flake.modules.nixos."machines/nixos/scheelite" ];
    };

    blackphos = {
      imports = [ config.flake.modules.darwin."machines/darwin/blackphos" ];
    };

    stibnite = {
      imports = [ config.flake.modules.darwin."machines/darwin/stibnite" ];
    };

    rosegold = {
      imports = [ config.flake.modules.darwin."machines/darwin/rosegold" ];
    };

    argentum = {
      imports = [ config.flake.modules.darwin."machines/darwin/argentum" ];
    };
  };
}
