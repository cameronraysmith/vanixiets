# Resumably restore a path from the archival Time Machine source drive to its
# equivalent location on this disk. The snapshot data root is provisioned as a
# sops secret (crs58's per-user secrets file); the decrypted file's path is
# injected here at eval time and read by the script at runtime, overridable with
# --from or $TM_DATA_ROOT.
{ ... }:
{
  flake.modules.homeManager.tools =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "tm-restore";
          runtimeInputs = with pkgs; [
            rsync
            coreutils
          ];
          text = ''
            export TM_DATA_ROOT_FILE=${
              lib.escapeShellArg (
                lib.attrByPath [ "sops" "secrets" "tm-source-drive-data-root" "path" ] "" config
              )
            }
          ''
          + builtins.readFile ./tm-restore.sh;
          meta.description = "Resumably restore a path from the archival Time Machine source drive (sops-pinned data root; override with --from or $TM_DATA_ROOT)";
        })
      ];
    };
}
