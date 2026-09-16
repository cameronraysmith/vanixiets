{ config, ... }:
let
  packages = config.flake.lib.cliArchivePackages;
in
{
  flake.lib.cliArchivePackages = pkgs: [
    pkgs.gnutar
    pkgs.gzip
    pkgs.xz
    pkgs.zstd
    pkgs.unzip
    pkgs.zip
  ];

  flake.modules = {
    nixos.cli-archives = { pkgs, ... }: { environment.systemPackages = packages pkgs; };
    darwin.cli-archives = { pkgs, ... }: { environment.systemPackages = packages pkgs; };
    homeManager.cli-archives = { pkgs, ... }: { home.packages = packages pkgs; };
  };
}
