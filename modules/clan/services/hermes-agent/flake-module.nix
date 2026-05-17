{ inputs, ... }:
{
  clan.modules.hermes-agent =
    { ... }:
    {
      _class = "clan.service";
      manifest.name = "hermes-agent";
      manifest.description = "Hermes Agent (NousResearch) deployed as a clan service, importing upstream's nixosModule and adapting clan-vars secrets to environmentFiles";
      manifest.categories = [
        "AI"
        "Communication"
      ];
      manifest.readme = builtins.readFile ./README.md;

      roles.default = {
        description = "Runs the hermes-agent gateway and dashboard, importing upstream's NixOS module";

        interface =
          { lib, ... }:
          {
            options = {
              serviceUser = lib.mkOption {
                type = lib.types.str;
                default = "cameron";
                description = "Unix user to run hermes-agent as (createUser=false posture)";
              };

              stateDir = lib.mkOption {
                type = lib.types.str;
                default = "/home/cameron/.hermes";
                description = "Hermes state directory (HERMES_HOME)";
              };

              openrouterApiKeyGenerator = lib.mkOption {
                type = lib.types.str;
                default = "hermes-openrouter-api-key";
                description = "Name of the clan-vars generator producing the OPENROUTER_API_KEY env file (wired by nix-gyy.3, populated by nix-gyy.4)";
              };

              matrixBotPasswordGenerator = lib.mkOption {
                type = lib.types.str;
                default = "matrix-password-hermes";
                description = "Name of the clan-vars generator producing the MATRIX_PASSWORD env file (wired by nix-gyy.3, populated by nix-gyy.4)";
              };

              matrixServerName = lib.mkOption {
                type = lib.types.str;
                default = "matrix.zt";
                description = "Matrix homeserver hostname for the bot user_id localpart suffix";
              };

              matrixUserName = lib.mkOption {
                type = lib.types.str;
                default = "hermes";
                description = "Matrix bot username (localpart of the bot's MXID)";
              };

              port = lib.mkOption {
                type = lib.types.port;
                default = 18791;
                description = "Hermes gateway listen port (loopback bind; adjacent to openclaw 18789)";
              };

              dashboardPort = lib.mkOption {
                type = lib.types.port;
                default = 18790;
                description = "Hermes dashboard listen port (loopback bind; reverse-proxied by nginx on hermes.zt)";
              };

              channelsAllowlist = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                example = [ "@cameron:matrix.zt" ];
                description = "Matrix MXIDs allowed to DM the bot";
              };

              configOverrides = lib.mkOption {
                type = lib.types.attrs;
                default = { };
                description = "Additional config merged on top of the generated hermes-agent settings via lib.recursiveUpdate";
              };
            };
          };

        perInstance =
          { settings, ... }:
          {
            nixosModule =
              {
                config,
                lib,
                pkgs,
                ...
              }:
              {
                imports = [ inputs.hermes-agent.nixosModules.default ];

                # Issue nix-gyy.2 only scaffolds the wrapper. Issues 3, 4, 5, 6, 7 fill in:
                #   - clan-vars-to-environmentFiles adapter (nix-gyy.3)
                #   - clan-vars generators (nix-gyy.4)
                #   - mkForce hardening tuning (nix-gyy.5)
                #   - sibling hermes-agent-dashboard systemd unit (nix-gyy.6)
                #   - matrix wiring & deep settings merge (nix-gyy.7)
                # This commit lands ONLY the scaffold: settings interface, perInstance.nixosModule
                # with upstream imports, the bare-minimum services.hermes-agent.* options driven by
                # settings, and an empty environmentFiles list as a placeholder for nix-gyy.3.

                services.hermes-agent = {
                  enable = true;
                  createUser = false;
                  user = settings.serviceUser;
                  group = "users";
                  stateDir = settings.stateDir;

                  # Deep-merge into config.yaml — populated incrementally by later issues.
                  settings = lib.mkMerge [
                    {
                      channels.matrix = {
                        homeserver = "https://${settings.matrixServerName}";
                        user_id = "@${settings.matrixUserName}:${settings.matrixServerName}";
                        # Additional matrix wiring added by nix-gyy.7.
                      };
                    }
                    settings.configOverrides
                  ];

                  # environmentFiles list populated by nix-gyy.3's clan-vars adapter.
                  # Placeholder empty list keeps the option resolvable at scaffold time.
                  environmentFiles = lib.mkDefault [ ];
                };
              };
          };
      };
    };
}
