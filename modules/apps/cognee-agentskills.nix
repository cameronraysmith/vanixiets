# Refresh flake-app for the cognee SaaS `agentskills` reference-knowledge dataset.
#
# Manages ingestion, targeted removal, and full-graph rebuild of the agent-skill
# corpus (every skill `.md` under modules/home/ai/plugins/<group>/.apm/skills/,
# plus the agents-md.nix generator) in the cognee SaaS dataset `agentskills`.
#
#   nix run .#cognee-agentskills -- refresh                    # full graph-clean rebuild
#   nix run .#cognee-agentskills -- refresh --skill <group>/<skill>
#   nix run .#cognee-agentskills -- refresh --plugin <group>
#   nix run .#cognee-agentskills -- remove  --skill <group>/<skill>
#   nix run .#cognee-agentskills -- add <path...>
#   nix run .#cognee-agentskills -- list | status
#
# Mirrors the openspec-refresh-vendored-artifacts flake-app + co-located .sh
# sidecar convention. The `cognee` CLI is deliberately absent from runtimeInputs:
# it is the ambient home-manager wrapper (bakes --api-url and reads the sops key),
# and writeShellApplication prepends runtimeInputs to PATH, so the ambient wrapper
# stays reachable rather than being shadowed by a hermetic copy.
{ ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      apps.cognee-agentskills = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "cognee-agentskills";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.git
              pkgs.fd
              pkgs.gawk
              pkgs.gnugrep
              pkgs.gnused
              pkgs.jq
            ];
            text = builtins.readFile ./cognee-agentskills.sh;
          }
        );
      };
    };
}
