{ ... }:
{
  _class = "clan.service";
  manifest.name = "clawdbot";
  manifest.description = "Clawdbot Matrix gateway service with plugin architecture";
  manifest.categories = [
    "Communication"
  ];
  manifest.readme = builtins.readFile ./README.md;

  roles.default = {
    description = "Runs the clawdbot gateway connecting to a Matrix homeserver";

    interface =
      { lib, ... }:
      {
        options = {
          homeserver = lib.mkOption {
            type = lib.types.str;
            description = "Matrix homeserver URL";
          };

          botUserId = lib.mkOption {
            type = lib.types.str;
            description = "Matrix bot user ID (e.g., @clawd:matrix.zt)";
          };

          port = lib.mkOption {
            type = lib.types.port;
            default = 18789;
            description = "Gateway listen port";
          };

          bindMode = lib.mkOption {
            type = lib.types.enum [
              "loopback"
              "lan"
              "auto"
            ];
            default = "loopback";
            description = "Network bind mode for the gateway";
          };
        };
      };

    perInstance =
      {
        settings,
        instanceName,
        ...
      }:
      {
        nixosModule =
          {
            config,
            pkgs,
            lib,
            ...
          }:
          let
            configFile = pkgs.writeText "clawdbot.json" (
              builtins.toJSON {
                gateway.port = settings.port;
                channels.matrix = {
                  enabled = true;
                  homeserver = settings.homeserver;
                };
              }
            );

            passwordVarPath = config.clan.core.vars.generators.matrix-password-clawd.files."password".path;

            wrapper = pkgs.writeShellScript "clawdbot-gateway-wrapper" ''
              export CLAWDBOT_CONFIG_PATH="/etc/clawdbot/clawdbot.json"
              export CLAWDBOT_NIX_MODE=1
              export MATRIX_USER_ID="${settings.botUserId}"
              export MATRIX_PASSWORD="$(cat ${passwordVarPath})"
              export HOME="/var/lib/clawdbot"
              exec ${lib.getExe' pkgs.clawdbot-gateway "clawdbot"} gateway run --bind ${settings.bindMode}
            '';
          in
          {
            # Deploy generated config to /etc/clawdbot/clawdbot.json
            environment.etc."clawdbot/clawdbot.json".source = configFile;

            # System user and group
            users.users.clawdbot = {
              isSystemUser = true;
              group = "clawdbot";
              home = "/var/lib/clawdbot";
            };
            users.groups.clawdbot = { };

            # Vars generator for gateway auth token
            clan.core.vars.generators."clawdbot-gateway-token" = {
              files."token" = { };
              runtimeInputs = [ pkgs.pwgen ];
              script = ''
                pwgen -s 64 1 > $out/token
              '';
            };

            # Systemd service
            systemd.services."clawdbot-gateway" = {
              description = "Clawdbot Matrix Gateway";
              after = [
                "network.target"
                "matrix-synapse.service"
              ];
              wants = [ "matrix-synapse.service" ];
              wantedBy = [ "multi-user.target" ];

              serviceConfig = {
                Type = "simple";
                ExecStart = wrapper;
                Restart = "on-failure";
                RestartSec = 10;
                User = "clawdbot";
                Group = "clawdbot";
                StateDirectory = "clawdbot";
              };
            };
          };
      };
  };
}
