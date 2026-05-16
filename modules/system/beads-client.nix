# Cross-platform beads CLI wrapper enabling shared-server mode
# Installs a wrapped `bd` binary that sets BEADS_DOLT_SERVER_MODE=1 so the
# CLI talks to a running dolt SQL server instead of using embedded storage.
# Conditional per-machine: defaults on when services.dolt-sql-server.enable.
{ lib, ... }:
let
  mkPackage =
    pkgs:
    pkgs.symlinkJoin {
      name = "bd-shared-server";
      paths = [ pkgs.beads ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/bd \
          --set BEADS_DOLT_SERVER_MODE 1
      '';
    };

  mkConfig =
    { config, pkgs, ... }:
    let
      cfg = config.services.beads-client;
    in
    {
      options.services.beads-client = {
        shared-server =
          lib.mkEnableOption "wrapped bd CLI that forces shared-server mode via BEADS_DOLT_SERVER_MODE=1"
          // {
            default = config.services.dolt-sql-server.enable;
          };
        package = lib.mkOption {
          type = lib.types.package;
          default = mkPackage pkgs;
          defaultText = lib.literalExpression "pkgs.beads wrapped with BEADS_DOLT_SERVER_MODE=1";
          description = "The wrapped beads CLI package to install when shared-server mode is enabled.";
        };
      };

      config = lib.mkIf cfg.shared-server {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.modules.darwin.beads-client = mkConfig;
  flake.modules.nixos.beads-client = mkConfig;
}
