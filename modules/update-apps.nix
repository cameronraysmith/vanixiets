# Package update apps
#
# nix run .#update-beads-next
# nix run .#update-claude-code
# nix run .#update-dolt
{ ... }:
{
  perSystem =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      # nix-update-script returns a list [ executable args... ];
      # flake apps require a single program path.
      mkUpdateApp =
        pkg:
        let
          script = pkg.updateScript;
        in
        if builtins.isList script then
          {
            type = "app";
            program = lib.getExe (
              pkgs.writeShellApplication {
                name = "update-${pkg.pname}";
                text = lib.escapeShellArgs script;
              }
            );
          }
        else
          {
            type = "app";
            program = "${script}";
          };
    in
    {
      apps.update-beads-next = mkUpdateApp config.packages.beads-next;
      apps.update-claude-code = mkUpdateApp config.packages.claude-code;
      apps.update-dolt = mkUpdateApp config.packages.dolt;
    };
}
