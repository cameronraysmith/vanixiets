# Package update apps
#
# nix run .#update-claude-code
{ ... }:
{
  perSystem =
    { config, ... }:
    {
      apps.update-claude-code = {
        type = "app";
        program = "${config.packages.claude-code.updateScript}";
      };
    };
}
