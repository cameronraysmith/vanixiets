# Declarative management of ~/.dolt/config_global.json
#
# Provides the beads connection profile and user identity for the dolt CLI.
# Managed as an immutable nix store symlink. The dolt server logs a non-fatal
# error on startup about being unable to persist runtime state (server_uuid,
# user.creds) but continues operating normally since those keys are not
# needed for localhost-only usage with git+https:// remotes.
{ ... }:
{
  flake.modules.homeManager.tools =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      doltPort = toString config.services.beads.doltServerPort;
      gitCfg = config.programs.git.settings;
      doltConfig = builtins.toJSON {
        profile = builtins.readFile (
          pkgs.runCommand "dolt-profile-base64" { } ''
            echo -n '${
              builtins.toJSON {
                beads = {
                  user = "root";
                  password = "";
                  has-password = true;
                  host = "127.0.0.1";
                  port = doltPort;
                  no-tls = true;
                  data-dir = "";
                  doltcfg-dir = "";
                  privilege-file = "";
                  branch-control-file = "";
                  use-db = "";
                };
              }
            }' | ${pkgs.coreutils}/bin/base64 -w0 > $out
          ''
        );
        "user.email" = gitCfg.user.email;
        "user.name" = gitCfg.github.user;
      };
    in
    {
      options.services.beads.doltServerPort = lib.mkOption {
        type = lib.types.port;
        default = 3307;
        description = "Port of the dolt SQL server for beads CLI connections.";
      };

      config = {
        home.file.".dolt/config_global.json".text = doltConfig;
        home.sessionVariables.BEADS_DOLT_SERVER_PORT = doltPort;
      };
    };
}
