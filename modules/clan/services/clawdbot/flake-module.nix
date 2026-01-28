{ ... }:
{
  clan.modules.clawdbot =
    { ... }:
    {
      _class = "clan.service";
      # TODO: rename to "clan-core/clawdbot" when upstreamed
      manifest.name = "clawdbot";
      manifest.description = "Clawdbot Matrix gateway service with plugin architecture";
      manifest.categories = [ "Communication" ];
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

              serviceUser = lib.mkOption {
                type = lib.types.str;
                description = "Unix user to run the clawdbot gateway as";
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
                    gateway = {
                      port = settings.port;
                      mode = "local";
                    };
                    channels.matrix = {
                      enabled = true;
                      homeserver = settings.homeserver;
                    };
                  }
                );

                passwordVarPath = config.clan.core.vars.generators.matrix-password-clawd.files."password".path;
                oauthTokenPath = config.clan.core.vars.generators.clawdbot-claude-oauth.files."token".path;

                stateDir = "${config.users.users.${settings.serviceUser}.home}/.clawdbot";

                wrapper = pkgs.writeShellScript "clawdbot-gateway-wrapper" ''
                  mkdir -p ${stateDir}
                  cp /etc/clawdbot/clawdbot.json ${stateDir}/clawdbot.json
                  export CLAWDBOT_CONFIG_PATH="${stateDir}/clawdbot.json"
                  export CLAWDBOT_NIX_MODE=1
                  export MATRIX_USER_ID="${settings.botUserId}"
                  export MATRIX_PASSWORD="$(cat ${passwordVarPath})"
                  export ANTHROPIC_OAUTH_TOKEN="$(cat ${oauthTokenPath})"
                  exec ${lib.getExe' pkgs.clawdbot-gateway "clawdbot"} gateway run --bind ${settings.bindMode}
                '';
              in
              {
                environment.etc."clawdbot/clawdbot.json".source = configFile;
                environment.systemPackages = [ pkgs.clawdbot-gateway ];

                users.users.clawdbot = {
                  isSystemUser = true;
                  group = "clawdbot";
                  home = "/var/lib/clawdbot";
                  shell = pkgs.bashInteractive;
                };
                users.groups.clawdbot = { };

                clan.core.vars.generators."clawdbot-gateway-token" = {
                  files."token" = { };
                  runtimeInputs = [ pkgs.pwgen ];
                  script = ''
                    pwgen -s 64 1 > "$out"/token
                  '';
                };

                clan.core.vars.generators."clawdbot-claude-oauth" = {
                  prompts.token = {
                    description = "Claude Code OAuth token (from 'claude setup-token')";
                    type = "hidden";
                  };
                  files."token" = {
                    neededFor = "services";
                    owner = settings.serviceUser;
                  };
                  script = ''
                    cat "$prompts"/token > "$out"/token
                  '';
                };

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
                    User = settings.serviceUser;
                    Group = "users";
                  };
                };
              };
          };
      };
    };
}
