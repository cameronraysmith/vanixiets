{ config, ... }:
let
  modules = config.flake.modules;
in
{
  flake.modules = {
    nixos.cli-tools = { pkgs, ... }: {
      imports = [
        modules.nixos.cli-unix
        modules.nixos.cli-archives
        modules.nixos.cli-network
      ];
      environment.systemPackages = [ pkgs.jq ];
    };
    darwin.cli-tools = { pkgs, ... }: {
      imports = [
        modules.darwin.cli-unix
        modules.darwin.cli-archives
        modules.darwin.cli-network
      ];
      environment.systemPackages = [ pkgs.jq ];
    };
    homeManager.cli-tools = {
      imports = [
        modules.homeManager.cli-unix
        modules.homeManager.cli-archives
        modules.homeManager.cli-network
        modules.homeManager.jq
      ];
    };
  };
}
