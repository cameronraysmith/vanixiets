{ inputs, ... }:
let
  inherit (inputs) landrun-nix;
in
{
  imports = [ landrun-nix.flakeModule ];

  perSystem =
    { pkgs, config, ... }:
    let
      claude-code = inputs.nix-ai-tools.packages.${pkgs.system}.claude-code;
    in
    {
      # Sandboxed claude-code variants
      landrunApps = {
        # Sandboxed claude with full features (normal permissions mode)
        claude-sandboxed = {
          program = "${claude-code}/bin/claude";
          imports = [
            landrun-nix.landrunModules.gh
            landrun-nix.landrunModules.git
          ];
          features = {
            tty = true;
            nix = true;
            network = true;
          };
          cli = {
            rw = [
              "$HOME/.claude"
              "$HOME/.claude.json"
            ];
            rwx = [ "." ];
            env = [ "HOME" ];
          };
        };

        # Sandboxed variant with dangerously-skip-permissions
        ccds-sandboxed = {
          program = "${pkgs.writeShellScript "ccds-wrapped" ''
            exec ${claude-code}/bin/claude --dangerously-skip-permissions "$@"
          ''}";
          imports = [
            landrun-nix.landrunModules.gh
            landrun-nix.landrunModules.git
          ];
          features = {
            tty = true;
            nix = true;
            network = true;
          };
          cli = {
            rw = [
              "$HOME/.claude"
              "$HOME/.claude.json"
            ];
            rwx = [ "." ];
            env = [ "HOME" ];
          };
        };
      };
    };
}
