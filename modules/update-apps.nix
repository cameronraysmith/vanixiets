# Package update apps
#
# nix run .#update-claude-code
{ ... }:
{
  perSystem =
    { config, ... }:
    {
      apps.update-beads-next = {
        type = "app";
        program = "${config.packages.beads-next.updateScript}";
      };
      apps.update-dolt = {
        type = "app";
        program = "${config.packages.dolt.updateScript}";
      };
      apps.update-claude-code = {
        type = "app";
        program = "${config.packages.claude-code.updateScript}";
      };
    };
}
