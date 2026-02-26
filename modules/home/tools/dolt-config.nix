# Declarative seed for ~/.dolt/config_global.json
#
# Seeds the dolt CLI config with the beads connection profile and user identity
# on first activation. The file is mutable so dolt can add runtime keys
# (server_uuid, user.creds) without conflict. Delete the file and re-activate
# to reset from nix config.
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
                  port = "3307";
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
      doltConfigFile = pkgs.writeText "dolt-config-global.json" doltConfig;
    in
    {
      home.activation.dolt-config = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -f "$HOME/.dolt/config_global.json" ]; then
          mkdir -p "$HOME/.dolt"
          cp ${doltConfigFile} "$HOME/.dolt/config_global.json"
        fi
      '';
    };
}
