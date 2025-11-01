{ inputs, lib, ... }:
let
  inherit (inputs) landrun-nix;
in
{
  imports = [ landrun-nix.flakeModule ];

  perSystem =
    {
      pkgs,
      config,
      system,
      ...
    }:
    let
      claude-code = inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
      # landrun uses Landlock LSM which is Linux-only
      isLinux = lib.hasSuffix "-linux" system;
      # landrun tests fail on aarch64-linux due to Landlock LSM compatibility issues
      # See: docs/notes/ci/landrun-aarch64-issue.md
      # TODO: Remove when upstream fixes Landlock compatibility on ARM
      canBuildLandrun = isLinux && (system != "aarch64-linux");
    in
    {
      # Sandboxed claude-code variants (x86_64-linux only - landrun broken on aarch64-linux)
      landrunApps = lib.optionalAttrs canBuildLandrun {
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
