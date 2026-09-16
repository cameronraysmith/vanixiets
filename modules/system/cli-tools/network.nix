{ config, ... }:
let
  packages = config.flake.lib.cliNetworkPackages;
in
{
  flake.lib.cliNetworkPackages = pkgs: [
    pkgs.curl
    pkgs.openssh
    pkgs.openssl
  ];

  flake.modules = {
    nixos.cli-network = { pkgs, ... }: { environment.systemPackages = packages pkgs; };
    darwin.cli-network = { pkgs, ... }: { environment.systemPackages = packages pkgs; };
    homeManager.cli-network = { pkgs, ... }: { home.packages = packages pkgs; };
  };
}
