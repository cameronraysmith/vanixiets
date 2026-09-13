{ lib, ... }:
{
  flake.lib.mkLinearCredentialsTemplate =
    config:
    if config ? workspaces then
      {
        mode = "0400";
        path = config.destination;
        content = ''
          default = ${builtins.toJSON config.defaultWorkspace}

          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (
              workspace: placeholder: "${builtins.toJSON workspace} = ${builtins.toJSON placeholder}"
            ) config.workspaces
          )}
        '';
      }
    else
      {
        mode = "0400";
        path = "${config.xdg.configHome}/linear/credentials.toml";
        content = ''
          default = "${config.sops.placeholder."linear-workspace-personal"}"

          ${config.sops.placeholder."linear-workspace-personal"} = "${
            config.sops.placeholder."linear-api-key-personal"
          }"
          ${config.sops.placeholder."linear-workspace-work"} = "${
            config.sops.placeholder."linear-api-key-work"
          }"
        '';
      };
}
