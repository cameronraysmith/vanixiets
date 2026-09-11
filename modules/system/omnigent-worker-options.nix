{ lib, ... }:
let
  workerOptions =
    { config, ... }:
    let
      osConfig = config;
    in
    {
      options.services.omnigent-host.workers = lib.mkOption {
        default = { };
        description = "Dedicated worker accounts prepared independently of host execution.";
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, config, ... }:
            {
              options = {
                enable = lib.mkEnableOption "foreground execution for this enrolled worker";
                owner = lib.mkOption {
                  type = lib.types.nonEmptyStr;
                  description = "Intended human association; enrollment must verify application ownership separately.";
                };
                user = lib.mkOption {
                  type = lib.types.strMatching "[a-z_][a-z0-9_-]*";
                  description = "Declared non-administrative Unix account; never inferred from a privileged user.";
                };
                hostName = lib.mkOption {
                  type = lib.types.nonEmptyStr;
                  default = "${osConfig.networking.hostName}-${name}";
                  description = "Distinct registration name for this machine and worker.";
                };
                workspaceRoot = lib.mkOption {
                  type = lib.types.strMatching "/.*";
                  default = "${osConfig.users.users.${config.user}.home}/projects";
                  description = "Project directory inside the declared account home.";
                };
                autoApproveDirenv = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                  description = "Trust direnv files under workspaceRoot without individual approval.";
                };
                environment = lib.mkOption {
                  type = lib.types.attrsOf lib.types.str;
                  default = { };
                  description = "Non-secret additions; identity, state, PATH and credential selectors are adapter-owned.";
                };
                extraPackages = lib.mkOption {
                  type = lib.types.listOf lib.types.package;
                  default = [ ];
                  description = "Executable providers appended after required runtime packages and the worker profile.";
                };
                extraHomeModules = lib.mkOption {
                  type = lib.types.listOf lib.types.deferredModule;
                  default = [ ];
                  description = "Additional credential-free Home Manager modules; not clan-serializable settings.";
                };
              };
            }
          )
        );
      };
    };
in
{
  flake.modules.nixos.omnigent-worker-options = workerOptions;
  flake.modules.darwin.omnigent-worker-options = workerOptions;
}
