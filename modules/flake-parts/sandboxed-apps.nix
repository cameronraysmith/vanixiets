{ inputs, ... }:
let
  inherit (inputs) landrun-nix;
in
{
  imports = [ landrun-nix.flakeModule ];

  perSystem =
    { pkgs, config, ... }:
    {
      # Sandboxed claude-code variants
      landrunApps = {
        # Sandboxed claude with full features (normal permissions mode)
        claude-sandboxed = {
          program = "${pkgs.claude-code-bin}/bin/claude";
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
              "$HOME/.config/gcloud"
            ];
            rwx = [ "." ];
            env = [
              "HOME"
              "CLAUDE_CODE_USE_VERTEX"
              "ANTHROPIC_MODEL"
            ];
          };
        };

        # Sandboxed variant with dangerously-skip-permissions
        ccds-sandboxed = {
          program = "${pkgs.writeShellScript "ccds-wrapped" ''
            exec ${pkgs.claude-code-bin}/bin/claude --dangerously-skip-permissions "$@"
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
              "$HOME/.config/gcloud"
            ];
            rwx = [ "." ];
            env = [
              "HOME"
              "CLAUDE_CODE_USE_VERTEX"
              "ANTHROPIC_MODEL"
            ];
          };
        };
      };
    };
}
