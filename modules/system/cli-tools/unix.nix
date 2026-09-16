{ config, lib, ... }:
let
  packages = config.flake.lib.cliUnixPackages;
in
{
  flake.lib.cliUnixPackages =
    pkgs:
    [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.gawk
      pkgs.diffutils
      pkgs.gnupatch
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.hostname ];

  flake.modules = {
    nixos.cli-unix = { pkgs, ... }: { environment.systemPackages = packages pkgs; };
    darwin.cli-unix = { pkgs, ... }: { environment.systemPackages = packages pkgs; };
    homeManager.cli-unix = { pkgs, ... }: { home.packages = packages pkgs; };
  };
}
