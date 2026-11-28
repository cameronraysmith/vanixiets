{ config, lib, ... }:
let
  modules = config.flake.modules;
  packages = config.flake.lib.cliHostInspectionPackages;
in
{
  flake.lib.cliHostInspectionPackages =
    pkgs:
    [
      # The wrapped `fastfetch` adds apple-sdk (about 440 MiB) on darwin and ddcutil and xfconf on Linux for desktop modules.
      pkgs.fastfetch-unwrapped
      pkgs.nix-info
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      pkgs.pciutils
      pkgs.usbutils
    ];

  flake.modules = {
    nixos.cli-host-inspection = { pkgs, ... }: { environment.systemPackages = packages pkgs; };
    darwin.cli-host-inspection = { pkgs, ... }: { environment.systemPackages = packages pkgs; };
    homeManager.cli-host-inspection =
      { pkgs, ... }:
      {
        key = "vanixiets/cli-host-inspection-home-module";
        home.packages = packages pkgs;
      };

    darwin.base.imports = [ modules.darwin.cli-host-inspection ];
    homeManager.engineering-tools.imports = [ modules.homeManager.cli-host-inspection ];
  };
}
