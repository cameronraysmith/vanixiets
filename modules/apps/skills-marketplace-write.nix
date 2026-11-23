# Writes the generated .claude-plugin/marketplace.json,
# .github/plugin/marketplace.json and skills.sh.json into the tree; `just
# agents-marketplace`.
{ ... }:
{
  perSystem =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      apps.skills-marketplace-write = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "skills-marketplace-write";
            runtimeInputs = [
              pkgs.git
              pkgs.coreutils
            ];
            # Reached through config.packages: the perSystem pkgs does not
            # carry the pkgs/by-name overlay (see modules/checks/apps.nix).
            runtimeEnv.SKILLS_MARKETPLACE = config.packages.skills-marketplace;
            text = builtins.readFile ./skills-marketplace-write.sh;
          }
        );
        meta.description = "Write the generated Claude and Copilot marketplace files into the tree";
      };
    };
}
