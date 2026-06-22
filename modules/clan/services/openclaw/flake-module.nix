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
              enable = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = ''
                  Deprecation toggle for the openclaw gateway footprint on a machine.

                  Set to false to disable openclaw (gateway service, config etc
                  file, interactive wrapper, all clawdbot-* and clawd-registration
                  generators, the reverse-proxy vhost, and the .zt DNS records)
                  while retaining the inventory instance for later removal. Defaults
                  to true so an in-place rebuild does not silently disable a live
                  deployment.
                '';
              };

              homeserver = lib.mkOption {
                type = lib.types.str;
                description = "Matrix homeserver URL";
              };

              botUserName = lib.mkOption {
                type = lib.types.str;
                description = "Bot username (workspace directory name and Matrix localpart)";
              };

              matrixServerName = lib.mkOption {
                type = lib.types.str;
                description = "Matrix server name for the bot user ID (e.g., matrix.zt)";
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

              listenAddresses = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = ''
                  Mesh addresses the reverse-proxy vhost binds and that the
                  openclaw.zt DNS records resolve to. Passed explicitly by the
                  inventory so the host's VPN listen addresses are an explicit
                  coupling rather than a hidden host dependency. When empty, the
                  relocated Caddy vhost and dnsmasq records are omitted.
                '';
              };

              hostName = lib.mkOption {
                type = lib.types.str;
                default = "openclaw.zt";
                description = "Reverse-proxy virtual host and DNS name for the gateway";
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
                botUserId = "@${settings.botUserName}:${settings.matrixServerName}";
                userHome = config.users.users.${settings.serviceUser}.home;
                workspaceDir = "${userHome}/${settings.botUserName}";

                matrixHost = settings.homeserver;

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
                            id = "glm-5.1";
                            name = "GLM 5.1 (Z.AI Coding Plan)";
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
                      workspace = workspaceDir;
                      model = {
                        primary = "zai-coding-plan/glm-5.1";
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

                stateDir = "${userHome}/.openclaw";

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
                homeserverService = lib.optional isLocalHomeserver "tuwunel.service";

                wrapper = pkgs.writeShellScript "openclaw-gateway-wrapper" ''
                  mkdir -p ${stateDir}
                  install -m 0600 /etc/openclaw/openclaw.json ${stateDir}/openclaw.json
                  export OPENCLAW_CONFIG_PATH="${stateDir}/openclaw.json"
                  export OPENCLAW_GATEWAY_TOKEN="$(cat ${gatewayTokenPath})"
                  export MATRIX_USER_ID="${botUserId}"
                  export MATRIX_PASSWORD="$(cat ${passwordVarPath})"
                  export ANTHROPIC_OAUTH_TOKEN="$(cat ${oauthTokenPath})"
                  export ZAI_API_KEY="$(cat ${zaiApiKeyPath})"
                  exec ${lib.getExe' package "openclaw"} gateway run --bind ${settings.bindMode}
                '';

                interactiveWrapper = pkgs.writeShellApplication {
                  name = "openclaw";
                  text = ''
                    mkdir -p ${stateDir}
                    install -m 0600 /etc/openclaw/openclaw.json ${stateDir}/openclaw.json
                    export OPENCLAW_CONFIG_PATH="${stateDir}/openclaw.json"
                    ZAI_API_KEY="$(cat ${zaiApiKeyPath})"
                    export ZAI_API_KEY
                    ANTHROPIC_OAUTH_TOKEN="$(cat ${oauthTokenPath})"
                    export ANTHROPIC_OAUTH_TOKEN
                    exec ${lib.getExe' package "openclaw"} "$@"
                  '';
                };
              in
              {
                options.services.openclaw.package = lib.mkOption {
                  type = lib.types.package;
                  default = pkgs.openclaw-gateway;
                  defaultText = lib.literalExpression "pkgs.openclaw-gateway";
                  description = "The openclaw gateway package with bundled plugins";
                };

                config = lib.mkIf settings.enable {
                  environment.etc."openclaw/openclaw.json".source = configFile;
                  environment.systemPackages = [ interactiveWrapper ];

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

                  # TODO: Once config has stabilized, migrate from mutable copy to
                  # immutable symlink following the nix-openclaw HM module pattern:
                  #   ln -sfn /etc/openclaw/openclaw.json ${stateDir}/openclaw.json
                  # This eliminates the wrapper copy and makes config fully Nix-managed.
                  # See nix-clawdbot/nix/modules/home-manager/openclaw.nix (activation phase).
                  systemd.services."openclaw-gateway" = {
                    description = "OpenClaw Matrix Gateway";
                    after = [ "network.target" ] ++ homeserverService;
                    wants = homeserverService;
                    wantedBy = [ "multi-user.target" ];
                    restartTriggers = [ configFile ];

                    preStart = ''
                      rm -f ${stateDir}/credentials/matrix/credentials.json
                    '';

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

                  clan.core.vars.generators."matrix-password-clawd" = {
                    files."password" = {
                      neededFor = "services";
                      owner = settings.serviceUser;
                    };
                    runtimeInputs = [
                      pkgs.coreutils
                      pkgs.xkcdpass
                    ];
                    script = ''
                      xkcdpass -n 4 -d - > "$out"/password
                    '';
                  };

                  systemd.services."openclaw-register-clawd" = {
                    description = "Register the openclaw bot user on tuwunel";
                    after = [ "tuwunel.service" ];
                    requires = [ "tuwunel.service" ];
                    before = [ "openclaw-gateway.service" ];
                    wantedBy = [ "multi-user.target" ];
                    serviceConfig = {
                      Type = "oneshot";
                      RemainAfterExit = true;
                    };
                    path = [
                      pkgs.curl
                      pkgs.jq
                      pkgs.coreutils
                    ];
                    script =
                      let
                        tokenFile = config.clan.core.vars.generators."tuwunel-registration-token".files."token".path;
                        clawdPasswordFile = config.clan.core.vars.generators."matrix-password-clawd".files."password".path;
                      in
                      ''
                        set -euo pipefail

                        TOKEN=$(cat ${tokenFile})

                        for i in $(seq 1 30); do
                          if curl -fsS ${matrixHost}/_matrix/client/versions >/dev/null 2>&1; then
                            break
                          fi
                          if [ "$i" -eq 30 ]; then
                            echo "tuwunel did not become ready within 30s" >&2
                            exit 1
                          fi
                          sleep 1
                        done

                        body=$(jq -n \
                          --arg u "${settings.botUserName}" \
                          --arg p "$(cat ${clawdPasswordFile})" \
                          --arg t "$TOKEN" \
                          '{auth:{type:"m.login.registration_token",token:$t}, username:$u, password:$p, inhibit_login:true}')
                        tmpfile=$(mktemp)
                        http_code=$(curl -sS -o "$tmpfile" -w '%{http_code}' \
                          -X POST ${matrixHost}/_matrix/client/v3/register \
                          -H 'Content-Type: application/json' \
                          -d "$body")
                        case "$http_code" in
                          200)
                            echo "registered ${settings.botUserName}"
                            ;;
                          400)
                            if jq -e '.errcode == "M_USER_IN_USE"' "$tmpfile" >/dev/null 2>&1; then
                              echo "${settings.botUserName} already exists, skipping"
                            else
                              echo "registration failed for ${settings.botUserName}: HTTP 400: $(cat "$tmpfile")" >&2
                              rm -f "$tmpfile"
                              exit 1
                            fi
                            ;;
                          *)
                            echo "registration failed for ${settings.botUserName}: HTTP $http_code: $(cat "$tmpfile")" >&2
                            rm -f "$tmpfile"
                            exit 1
                            ;;
                        esac
                        rm -f "$tmpfile"
                      '';
                  };

                  services.caddy.virtualHosts.${settings.hostName} = lib.mkIf (settings.listenAddresses != [ ]) {
                    listenAddresses = lib.mkDefault settings.listenAddresses;
                    extraConfig = ''
                      tls internal
                      reverse_proxy [::1]:${toString settings.port} {
                        header_up -X-Forwarded-For
                        header_up -X-Forwarded-Proto
                        header_up -X-Forwarded-Host
                      }
                    '';
                  };

                  services.dnsmasq.settings.address = lib.mkIf (settings.listenAddresses != [ ]) (
                    map (addr: "/${settings.hostName}/${addr}") settings.listenAddresses
                  );
                };
              };
          };
      };
    };
}
