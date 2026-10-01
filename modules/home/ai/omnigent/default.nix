{ config, ... }:
let
  acp = config.flake.lib.omnigentACP;
  managedConfigsModule = config.flake.modules.homeManager.managedConfigs;
  content =
    legacy:
    {
      config,
      lib,
      pkgs,
      osConfig ? null,
      ...
    }:
    let
      cfg = config.programs.omnigent;
      yamlFormat = pkgs.formats.yaml { };
      hostName = if !legacy || osConfig == null then null else osConfig.networking.hostName;
      runner = if !legacy || osConfig == null then { } else osConfig.services.omnigent-host or { };
    in
    {
      imports = [ managedConfigsModule ];

      options.programs.omnigent = {
        enable = lib.mkEnableOption "Omnigent and its runner configuration";
        package = lib.mkPackageOption pkgs "omnigent" { };
        settings = lib.mkOption {
          type = yamlFormat.type;
          default = { };
          description = ''
            Content of {file}`~/.omnigent/config.yaml`, rewritten on every
            activation. host.host_id, server, and host.name when not declared
            here are kept from the existing file; every other runtime key is
            dropped. Credentials belong in runtime state, not these
            store-visible settings.
          '';
        };
      };

      config = {
        programs.omnigent = {
          enable = lib.mkDefault true;
          settings = {
            acp = acp // {
              agents = map (
                agent:
                agent
                // lib.optionalAttrs (!legacy && agent.name == "Oh My Pi") {
                  command = "omp acp --approval-mode yolo";
                }
              ) acp.agents;
            };
          }
          // lib.optionalAttrs (hostName != null && hostName != "") {
            host.name = lib.mkDefault hostName;
          };
        };

        programs.direnv.config.whitelist.prefix = lib.mkIf (
          (runner.enable or false) && runner.user == config.home.username
        ) [ "${config.home.homeDirectory}/projects" ];

        home.packages = lib.mkIf cfg.enable [ cfg.package ];
        managedConfigs.omnigent-config = lib.mkIf (cfg.enable && cfg.settings != { }) {
          target = "${config.home.homeDirectory}/.omnigent/config.yaml";
          format = "yaml";
          settings = cfg.settings;
          appOwned = [
            "host.host_id"
            "server"
          ]
          ++ lib.optional (!lib.hasAttrByPath [ "host" "name" ] cfg.settings) "host.name";
          fileMode = "0600";
        };
      };
    };
in
{
  flake.modules.homeManager.ai = content true;
  flake.modules.homeManager.omnigent = content false;
}
