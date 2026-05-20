# Restore a hermes-agent tar.zst snapshot back to a hermes-import-compatible zip
{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "hermes-restore";
          runtimeInputs = with pkgs; [
            libarchive
            zstd
            coreutils
          ];
          text = builtins.readFile ./hermes-restore.sh;
          meta.description = "Convert a hermes-backup tar.zst back to a hermes-import-compatible zip via libarchive";
        })
      ];
    };
}
