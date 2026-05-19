# Re-wrap a hermes-agent backup into a prefix-directory tar.zst for archival
{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "hermes-backup";
          runtimeInputs = with pkgs; [
            libarchive
            zstd
            coreutils
          ];
          text = builtins.readFile ./hermes-backup.sh;
          meta.description = "Snapshot hermes-agent state to prefix-directory tar.zst via libarchive + zstd";
        })
      ];
    };
}
