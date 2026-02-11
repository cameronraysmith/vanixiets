{ ... }:
{
  clan.modules.kanban =
    { ... }:
    {
      _class = "clan.service";
      manifest.name = "kanban";
      manifest.description = "Beads kanban board UI with embedded SQLite persistence";
      manifest.categories = [ "Development" ];
      manifest.readme = builtins.readFile ./README.md;

      roles.default = {
        description = "Runs the beads-kanban-ui server serving the kanban board frontend";

        interface =
          { lib, ... }:
          {
            options = {
              port = lib.mkOption {
                type = lib.types.port;
                default = 3008;
                description = "HTTP listen port for the kanban board UI";
              };

              serviceUser = lib.mkOption {
                type = lib.types.str;
                default = "cameron";
                description = "Unix user to run the kanban board server as";
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
                package = config.services.kanban.package;
                userHome = config.users.users.${settings.serviceUser}.home;
              in
              {
                options.services.kanban.package = lib.mkOption {
                  type = lib.types.package;
                  default = pkgs.beads-kanban-ui;
                  defaultText = lib.literalExpression "pkgs.beads-kanban-ui";
                  description = "The beads-kanban-ui package";
                };

                config = {
                  systemd.services."beads-kanban-ui" = {
                    description = "Beads Kanban Board UI";
                    after = [ "network-online.target" ];
                    wants = [ "network-online.target" ];
                    wantedBy = [ "multi-user.target" ];

                    environment = {
                      PORT = toString settings.port;
                      HOME = userHome;
                    };

                    serviceConfig = {
                      Type = "simple";
                      ExecStart = lib.getExe package;
                      Restart = "always";
                      RestartSec = 5;
                      User = settings.serviceUser;
                      Group = "users";

                      # Filesystem protection
                      ProtectSystem = "strict";
                      ReadWritePaths = [ "${userHome}/.local/share/beads" ];

                      # Privilege escalation prevention
                      NoNewPrivileges = true;
                      RestrictSUIDSGID = true;
                      SystemCallArchitectures = "native";

                      # Kernel and device isolation
                      PrivateDevices = true;
                      ProtectKernelTunables = true;
                      ProtectKernelModules = true;
                      ProtectControlGroups = true;

                      # Misc hardening
                      PrivateTmp = true;
                      RestrictRealtime = true;
                      RestrictNamespaces = true;
                    };
                  };
                };
              };
          };
      };
    };
}
