{ ... }:
{
  clan.modules.beads-ui =
    { ... }:
    {
      _class = "clan.service";
      manifest.name = "beads-ui";
      manifest.description = "Local UI for Beads issue tracker with real-time WebSocket updates";
      manifest.categories = [ "Development" ];
      manifest.readme = builtins.readFile ./README.md;

      roles.default = {
        description = "Runs the beads-ui Node.js server serving the issue tracker frontend";

        interface =
          { lib, ... }:
          {
            options = {
              host = lib.mkOption {
                type = lib.types.str;
                default = "0.0.0.0";
                description = "Address to bind the beads UI server to";
              };

              port = lib.mkOption {
                type = lib.types.port;
                default = 3009;
                description = "HTTP listen port for the beads UI server";
              };

              serviceUser = lib.mkOption {
                type = lib.types.str;
                default = "cameron";
                description = "Unix user to run the beads-ui server as";
              };
            };
          };

        perInstance =
          { settings, ... }:
          {
            nixosModule =
              {
                config,
                pkgs,
                lib,
                ...
              }:
              let
                package = config.services.beads-ui.package;
                serverEntry = "${package}/lib/node_modules/beads-ui/server/index.js";
                userHome = config.users.users.${settings.serviceUser}.home;
              in
              {
                options.services.beads-ui.package = lib.mkOption {
                  type = lib.types.package;
                  default = pkgs.beads-ui;
                  defaultText = lib.literalExpression "pkgs.beads-ui";
                  description = "The beads-ui package";
                };

                config = {
                  systemd.services."beads-ui" = {
                    description = "Beads UI Server";
                    after = [ "network-online.target" ];
                    wants = [ "network-online.target" ];
                    wantedBy = [ "multi-user.target" ];

                    environment = {
                      HOME = userHome;
                    };

                    path = [
                      package.beads
                      pkgs.git
                    ];

                    serviceConfig = {
                      Type = "simple";
                      ExecStart = "${package.nodejs_22}/bin/node ${serverEntry} --host ${settings.host} --port ${toString settings.port}";
                      WorkingDirectory = userHome;
                      Restart = "always";
                      RestartSec = 5;
                      User = settings.serviceUser;
                      Group = "users";

                      # Hardening (no ProtectSystem=strict; service needs
                      # read/write access to home directory for workspace
                      # .beads/ directories and the global registry)
                      NoNewPrivileges = true;
                      RestrictSUIDSGID = true;
                      PrivateDevices = true;
                      ProtectKernelTunables = true;
                      ProtectKernelModules = true;
                      ProtectControlGroups = true;
                      PrivateTmp = true;
                    };
                  };
                };
              };
          };
      };
    };
}
