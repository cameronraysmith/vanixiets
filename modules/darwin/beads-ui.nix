# Darwin launchd user agent for beads-ui web interface
# Localhost-only service for laptop use (per-user, runs when logged in)
{ lib, ... }:
{
  flake.modules.darwin.beads-ui =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      cfg = config.services.beads-ui;
      package = cfg.package;
      serverEntry = "${package}/lib/node_modules/beads-ui/server/index.js";
      userHome = config.users.users.${config.system.primaryUser}.home;
    in
    {
      options.services.beads-ui = {
        enable = lib.mkEnableOption "beads-ui web interface";
        package = lib.mkPackageOption pkgs "beads-ui" { };
        host = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "Address to bind the beads-ui server to.";
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = 3009;
          description = "HTTP listen port for the beads-ui server.";
        };
      };

      config = lib.mkIf cfg.enable {
        launchd.user.agents.beads-ui = {
          serviceConfig = {
            ProgramArguments = [
              "${pkgs.nodejs_22}/bin/node"
              serverEntry
              "--host"
              cfg.host
              "--port"
              (toString cfg.port)
            ];
            RunAtLoad = true;
            KeepAlive = true;
            ThrottleInterval = 5;
            WorkingDirectory = userHome;
            StandardErrorPath = "/tmp/beads-ui.err.log";
            StandardOutPath = "/tmp/beads-ui.out.log";
            EnvironmentVariables =
              {
                HOME = userHome;
                PATH = lib.makeBinPath [
                  pkgs.beads
                  pkgs.git
                  pkgs.nodejs_22
                ];
              }
              // lib.optionalAttrs config.services.dolt-sql-server.enable {
                BEADS_DOLT_SERVER_PORT = toString config.services.dolt-sql-server.port;
              };
          };
        };
      };
    };
}
