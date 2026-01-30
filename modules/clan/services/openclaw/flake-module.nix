{ ... }:
{
  clan.modules.openclaw =
    { ... }:
    {
      _class = "clan.service";
      manifest.name = "openclaw";
      manifest.description = "OpenClaw Matrix gateway service with plugin architecture";
      manifest.categories = [ "Communication" ];
      manifest.readme = builtins.readFile ./README.md;

      roles.default = {
        description = "Runs the openclaw gateway connecting to a Matrix homeserver";

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
                description = "Unix user to run the openclaw gateway as";
              };

              gatewayMode = lib.mkOption {
                type = lib.types.enum [
                  "local"
                  "server"
                ];
                default = "local";
                description = "Gateway operation mode";
              };

              matrixBotPasswordGenerator = lib.mkOption {
                type = lib.types.str;
                description = "Name of the clan vars generator providing the Matrix bot password";
              };

              configOverrides = lib.mkOption {
                type = lib.types.attrs;
                default = { };
                description = "Additional config merged on top of the generated openclaw.json via lib.recursiveUpdate";
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
                package = config.services.openclaw.package;

                baseConfig = {
                  gateway = {
                    port = settings.port;
                    mode = settings.gatewayMode;
                    controlUi.allowInsecureAuth = true;
                    trustedProxies = [
                      "::1"
                      "127.0.0.1"
                    ];
                  };
                  channels.matrix = {
                    enabled = true;
                    homeserver = settings.homeserver;
                  };
                  plugins.entries.matrix = {
                    enabled = true;
                  };
                  models = {
                    mode = "merge";
                    providers = {
                      "zai-coding-plan" = {
                        baseUrl = "https://api.z.ai/api/coding/paas/v4";
                        apiKey = "\${ZAI_API_KEY}";
                        api = "openai-completions";
                        models = [
                          {
                            id = "glm-4.7";
                            name = "GLM 4.7 (Z.AI Coding Plan)";
                            reasoning = true;
                            input = [ "text" ];
                            cost = {
                              input = 0;
                              output = 0;
                              cacheRead = 0;
                              cacheWrite = 0;
                            };
                            contextWindow = 131072;
                            maxTokens = 131072;
                          }
                        ];
                      };
                    };
                  };
                  agents = {
                    defaults = {
                      model = {
                        primary = "zai-coding-plan/glm-4.7";
                        fallbacks = [ "anthropic/claude-opus-4-5" ];
                      };
                    };
                  };
                };

                configFile = pkgs.writeText "openclaw.json" (
                  builtins.toJSON (lib.recursiveUpdate baseConfig settings.configOverrides)
                );

                passwordVarPath =
                  config.clan.core.vars.generators.${settings.matrixBotPasswordGenerator}.files."password".path;
                gatewayTokenPath = config.clan.core.vars.generators."clawdbot-gateway-token".files."token".path;
                oauthTokenPath = config.clan.core.vars.generators.clawdbot-claude-oauth.files."token".path;
                zaiApiKeyPath = config.clan.core.vars.generators."clawdbot-zai-coding-api".files."api-key".path;

                stateDir = "${config.users.users.${settings.serviceUser}.home}/.openclaw";

                isLocalHomeserver =
                  let
                    url = settings.homeserver;
                    hasLocal = prefix: lib.hasPrefix prefix url;
                  in
                  hasLocal "http://localhost"
                  || hasLocal "https://localhost"
                  || hasLocal "http://127.0.0.1"
                  || hasLocal "https://127.0.0.1"
                  || hasLocal "http://[::1]"
                  || hasLocal "https://[::1]";
                synapseService = lib.optional isLocalHomeserver "matrix-synapse.service";

                wrapper = pkgs.writeShellScript "openclaw-gateway-wrapper" ''
                  mkdir -p ${stateDir}
                  install -m 0600 /etc/openclaw/openclaw.json ${stateDir}/openclaw.json
                  export OPENCLAW_CONFIG_PATH="${stateDir}/openclaw.json"
                  export OPENCLAW_NIX_MODE=1
                  export OPENCLAW_GATEWAY_TOKEN="$(cat ${gatewayTokenPath})"
                  export MATRIX_USER_ID="${settings.botUserId}"
                  export MATRIX_PASSWORD="$(cat ${passwordVarPath})"
                  export ANTHROPIC_OAUTH_TOKEN="$(cat ${oauthTokenPath})"
                  export ZAI_API_KEY="$(cat ${zaiApiKeyPath})"
                  exec ${lib.getExe' package "openclaw"} gateway run --bind ${settings.bindMode}
                '';
              in
              {
                options.services.openclaw.package = lib.mkOption {
                  type = lib.types.package;
                  default = pkgs.openclaw-gateway;
                  defaultText = lib.literalExpression "pkgs.openclaw-gateway";
                  description = "The openclaw gateway package with bundled plugins";
                };

                config = {
                  environment.etc."openclaw/openclaw.json".source = configFile;
                  environment.systemPackages = [ package ];

                  clan.core.vars.generators."clawdbot-gateway-token" = {
                    files."token" = {
                      neededFor = "services";
                      owner = settings.serviceUser;
                    };
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

                  clan.core.vars.generators."clawdbot-zai-coding-api" = {
                    prompts.api-key = {
                      description = "Z.AI Coding Plan API key for openclaw";
                      type = "hidden";
                    };
                    files."api-key" = {
                      neededFor = "services";
                      owner = settings.serviceUser;
                    };
                    script = ''
                      cat "$prompts"/api-key > "$out"/api-key
                    '';
                  };

                  systemd.services."openclaw-gateway" = {
                    description = "OpenClaw Matrix Gateway";
                    after = [ "network.target" ] ++ synapseService;
                    wants = synapseService;
                    wantedBy = [ "multi-user.target" ];

                    serviceConfig = {
                      Type = "simple";
                      ExecStart = wrapper;
                      Restart = "always";
                      RestartSec = 5;
                      User = settings.serviceUser;
                      Group = "users";

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

                      # Not hardened (service needs user's home for projects
                      # and Claude CLI state; Claude CLI may use namespaces):
                      # ProtectHome = "read-only";
                      # ProtectSystem = "strict";
                      # RestrictNamespaces = true;
                    };
                  };
                };
              };
          };
      };
    };
}
