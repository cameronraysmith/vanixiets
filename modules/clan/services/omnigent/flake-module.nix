{ config, ... }:
let
  nixosModules = config.flake.modules.nixos;
  darwinModules = config.flake.modules.darwin;
in
{
  clan.modules.omnigent =
    { lib, ... }:
    {
      _class = "clan.service";
      manifest = {
        name = "omnigent";
        description = "Omnigent server and outbound foreground hosts";
        categories = [ "AI" ];
        readme = builtins.readFile ./README.md;
      };

      perMachine.nixosModule.imports = [
        nixosModules.omnigent
        nixosModules.omnigent-host
      ];

      roles.server = {
        description = "Runs the Omnigent server behind nginx with Kanidm OIDC";
        interface = {
          options = {
            domain = lib.mkOption {
              type = lib.types.str;
              description = "Public HTTPS hostname of the server.";
            };
            port = lib.mkOption {
              type = lib.types.port;
              default = 6767;
              description = "Loopback HTTP port served behind nginx.";
            };
          };
        };
        perInstance =
          { instanceName, settings, ... }:
          {
            nixosModule =
              { config, ... }:
              {
                services.omnigent = {
                  enable = true;
                  inherit (settings) domain port;
                  cookieSecretGenerator = "omnigent-cookie-secret-${instanceName}";
                  oidc = {
                    issuer = "https://accounts.scientistexperience.net/oauth2/openid/omnigent";
                    clientId = "omnigent";
                  };
                  environmentFiles = [
                    config.clan.core.vars.generators.kanidm-oauth2-omnigent.files.env.path
                  ];
                };
              };
          };
      };

      roles.host = {
        description = "Connects a runner to the instance's single server";
        interface = {
          options = {
            legacyEnable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Retain the legacy host until explicit per-machine migration.";
            };
            workers = lib.mkOption {
              default = { };
              description = "Dedicated Linux workers; account declarations remain separate from enrollment.";
              type = lib.types.attrsOf (
                lib.types.submodule {
                  options = {
                    enable = lib.mkEnableOption "this enrolled worker's foreground host";
                    owner = lib.mkOption {
                      type = lib.types.nonEmptyStr;
                      description = "Intended human owner, verified separately during enrollment.";
                    };
                    user = lib.mkOption {
                      type = lib.types.str;
                      description = "Declared dedicated Unix account.";
                    };
                    hostName = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
                      default = null;
                      description = "Registration name; null derives machine and instance names.";
                    };
                    workspaceRoot = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
                      default = null;
                      description = "Workspace path; null derives projects below the account home.";
                    };
                    autoApproveDirenv = lib.mkOption {
                      type = lib.types.bool;
                      default = false;
                      description = "Explicit trust for direnv files under the workspace.";
                    };
                    environment = lib.mkOption {
                      type = lib.types.attrsOf lib.types.str;
                      default = { };
                      description = "Non-secret additions, excluding adapter-owned selectors.";
                    };
                    extraPackages = lib.mkOption {
                      type = lib.types.listOf lib.types.str;
                      default = [ ];
                      description = "Nixpkgs attribute names appended after the runtime and worker profile.";
                    };
                  };
                }
              );
            };
            user = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Existing runner account; null uses the platform default. May be set per machine.";
            };
            extraPackages = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Nixpkgs attribute names, including dotted paths, added to the host and runner PATH.";
            };
            environment = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              description = "Non-secret environment values for the foreground host.";
            };
          };
        };
        perInstance =
          {
            roles,
            settings,
            machine,
            ...
          }:
          assert lib.assertMsg (
            lib.length (lib.attrNames roles.server.machines) == 1
          ) "Omnigent requires exactly one server";
          {
            nixosModule =
              { pkgs, ... }:
              {
                services.omnigent-host = {
                  enable = settings.legacyEnable;
                  serverUrl = "https://${(lib.head (lib.attrValues roles.server.machines)).settings.domain}";
                  user = lib.mkIf (settings.user != null) settings.user;
                  hostName = machine.name;
                  extraPackages = map (
                    name: lib.getAttrFromPath (lib.splitString "." name) pkgs
                  ) settings.extraPackages;
                  inherit (settings) environment;
                  workers = lib.mapAttrs (_: worker: {
                    inherit (worker)
                      enable
                      owner
                      user
                      autoApproveDirenv
                      environment
                      ;
                    hostName = lib.mkIf (worker.hostName != null) worker.hostName;
                    workspaceRoot = lib.mkIf (worker.workspaceRoot != null) worker.workspaceRoot;
                    extraPackages = map (
                      name: lib.getAttrFromPath (lib.splitString "." name) pkgs
                    ) worker.extraPackages;
                  }) settings.workers;
                };
              };
            darwinModule =
              { pkgs, ... }:
              assert lib.assertMsg (settings.workers == { })
                "Dedicated Darwin workers require the Darwin adapter; this role currently supports dedicated workers only on Linux";
              {
                imports = [ darwinModules.omnigent-host ];
                services.omnigent-host = {
                  enable = settings.legacyEnable;
                  serverUrl = "https://${(lib.head (lib.attrValues roles.server.machines)).settings.domain}";
                  user = lib.mkIf (settings.user != null) settings.user;
                  hostName = machine.name;
                  extraPackages = map (
                    name: lib.getAttrFromPath (lib.splitString "." name) pkgs
                  ) settings.extraPackages;
                  inherit (settings) environment;
                };
              };
          };
      };
    };
}
