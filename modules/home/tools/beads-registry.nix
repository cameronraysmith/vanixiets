# Declarative management of ~/.beads/registry.json
#
# The beads-ui server reads this file to discover registered workspaces.
# Paths are constructed relative to ${config.home.homeDirectory}/projects/
# so the same workspace list works across machines with different home directories.
{ ... }:
{
  flake.modules.homeManager.tools =
    { config, lib, ... }:
    let
      home = config.home.homeDirectory;
      workspacePaths = [
        "sciexp/planning"
        "nix-workspace/vanixiets"
        "rust-workspace/ironstar"
        "nix-workspace/python-nix-template"
        "sciexp/data"
        "hodosome-workspace/hodosome"
        "hodosome-workspace/Hodosome.jl"
      ];
      mkRegistryEntry = relPath: {
        workspace_path = "${home}/projects/${relPath}";
        socket_path = "";
        database_path = "${home}/projects/${relPath}/.beads";
        pid = 0;
        version = "0.56.1";
        started_at = "2026-02-25T00:00:00Z";
      };
    in
    {
      home.file.".beads/registry.json".text = builtins.toJSON (map mkRegistryEntry workspacePaths);
    };
}
