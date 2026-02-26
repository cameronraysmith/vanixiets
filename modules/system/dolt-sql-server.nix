# Cross-platform dolt SQL server for beads issue tracking
# Shared options with platform-specific service management:
#   darwin: launchd daemon
#   nixos: systemd service (DynamicUser or named user)
{ lib, ... }:
let
  mkServerArgs =
    cfg:
    [
      "${cfg.package}/bin/dolt"
      "sql-server"
      "--host"
      cfg.host
      "--port"
      (toString cfg.port)
      "--data-dir"
      cfg.dataDir
      "--loglevel"
      cfg.logLevel
    ]
    ++ lib.optionals (cfg.maxConnections != null) [
      "--max-connections"
      (toString cfg.maxConnections)
    ]
    ++ lib.optionals cfg.noAutoCommit [ "--no-auto-commit" ]
    ++ lib.optionals (cfg.remotesapiPort != null) [
      "--remotesapi-port"
      (toString cfg.remotesapiPort)
    ];

  mkOptions = pkgs: {
    services.dolt-sql-server = {
      enable = lib.mkEnableOption "dolt SQL server";
      package = lib.mkPackageOption pkgs "dolt" { };
      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Host address to bind to.";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 3307;
        description = "Port to listen on.";
      };
      dataDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/dolt";
        description = "Directory for dolt database storage.";
      };
      noAutoCommit = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Disable auto-commit (required by beads).";
      };
      logLevel = lib.mkOption {
        type = lib.types.enum [
          "trace"
          "debug"
          "info"
          "warning"
          "error"
          "fatal"
        ];
        default = "info";
        description = "Server log level.";
      };
      maxConnections = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Maximum simultaneous connections. Null uses dolt upstream default (1000).";
      };
      remotesapiPort = lib.mkOption {
        type = lib.types.nullOr lib.types.port;
        default = null;
        description = "Port for remotesapi server. Disabled when null.";
      };
      user = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "User to run the service as. NixOS uses DynamicUser when null. Darwin ignores this (uses system.primaryUser).";
      };
      group = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Group to run the service as. NixOS uses DynamicUser when null. Darwin ignores this (uses staff).";
      };
    };
  };
in
{
  flake.modules.darwin.dolt-sql-server =
    { config, pkgs, ... }:
    let
      cfg = config.services.dolt-sql-server;
    in
    {
      options = mkOptions pkgs;

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = cfg.port != 3306;
            message = "dolt-sql-server port 3306 conflicts with MySQL; default is 3307";
          }
        ];

        system.activationScripts.postActivation.text = lib.mkAfter ''
          echo "ensuring dolt data directory exists..." >&2
          mkdir -p "${cfg.dataDir}"
          chown "${config.system.primaryUser}:staff" "${cfg.dataDir}"
        '';

        launchd.daemons.dolt-sql-server = {
          serviceConfig = {
            ProgramArguments = mkServerArgs cfg;
            RunAtLoad = true;
            KeepAlive = true;
            WorkingDirectory = cfg.dataDir;
            StandardErrorPath = "/tmp/dolt-sql-server.err.log";
            StandardOutPath = "/tmp/dolt-sql-server.out.log";
            UserName = config.system.primaryUser;
            GroupName = "staff";
          };
        };
      };
    };

  flake.modules.nixos.dolt-sql-server =
    { config, pkgs, ... }:
    let
      cfg = config.services.dolt-sql-server;
    in
    {
      options = mkOptions pkgs;

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = cfg.port != 3306;
            message = "dolt-sql-server port 3306 conflicts with MySQL; default is 3307";
          }
          {
            assertion = cfg.user != null || lib.hasPrefix "/var/lib/" cfg.dataDir;
            message = "dolt-sql-server dataDir must be under /var/lib/ when using DynamicUser + StateDirectory";
          }
        ];

        systemd.services.dolt-sql-server = {
          description = "Dolt SQL Server";
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
          path = [ pkgs.git ];
          serviceConfig = {
            Type = "simple";
            ExecStart = lib.escapeShellArgs (mkServerArgs cfg);
            WorkingDirectory = cfg.dataDir;
            Restart = "on-failure";
            RestartSec = 5;
            ProtectSystem = "strict";
            PrivateTmp = true;
            NoNewPrivileges = true;
          }
          // (
            if cfg.user == null then
              {
                DynamicUser = true;
                Environment = "HOME=${cfg.dataDir}";
                StateDirectory = lib.removePrefix "/var/lib/" cfg.dataDir;
                ProtectHome = true;
              }
            else
              {
                User = cfg.user;
                Group = cfg.group;
                ProtectHome = "read-only";
              }
          );
        };
      };
    };
}
