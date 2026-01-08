# Landrun-sandboxed Claude Code applications (Linux-only)
#
# Uses landrun-nix to create Landlock-sandboxed versions of Claude Code CLI.
# Landlock is a Linux kernel security module (5.13+) for unprivileged sandboxing.
#
# Two variants are provided:
# - claude-sandboxed: Standard sandboxed claude (internal permission prompts active)
# - ccds-sandboxed: Sandboxed claude with --dangerously-skip-permissions
#
# The sandbox restricts filesystem access to workspace directories while allowing
# Claude to operate freely within those boundaries. This enables using
# --dangerously-skip-permissions safely by constraining the blast radius.
#
# Usage:
#   nix run .#claude-sandboxed      # Sandboxed with internal prompts
#   nix run .#ccds-sandboxed        # Sandboxed without internal prompts
#
# Home-manager aliases (Linux only):
#   claude-safe  -> nix run .#claude-sandboxed --
#   ccds-safe    -> nix run .#ccds-sandboxed --
{ inputs, ... }:
let
  inherit (inputs) landrun-nix;
in
{
  imports = [ landrun-nix.flakeModule ];

  # Home-manager module to ensure landrun rw paths exist
  # landrun-nix wrapper.nix adds rw/rwx paths unconditionally (no existence check),
  # so these directories must exist at runtime or landrun fails with ENOENT
  flake.modules.homeManager.ai =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf pkgs.stdenv.isLinux {
      home.activation.ensureLandrunPaths = {
        after = [ "writeBoundary" ];
        before = [ ];
        data = ''
          # Ensure directories exist for landrun rw paths
          # These are created empty if missing; claude/gcloud will populate as needed
          mkdir -p "$HOME/.claude"
          mkdir -p "$HOME/.config/gcloud"
          mkdir -p "$HOME/.cache/claude-cli-nodejs"
          mkdir -p "$HOME/projects"

          # Note: $HOME/.claude.json is a file, not a directory
          # claude creates it on first run; landrun handles file creation fine
          # (the error is about non-existent parent directories, not files)
        '';
      };
    };

  perSystem =
    {
      pkgs,
      system,
      lib,
      ...
    }:
    let
      # Restrict to x86_64-linux only: landrun tests fail on aarch64-linux
      # due to Landlock test failures (permission denied in --add-exec --ldd test)
      isLinux = system == "x86_64-linux";
      claudePkg = inputs.llm-agents.packages.${system}.claude-code;

      # Wrapper script that invokes claude with --dangerously-skip-permissions
      # This is needed because landrun's extraArgs are landrun arguments, not program arguments
      ccdsSandboxedWrapper = pkgs.writeShellScript "ccds-sandboxed-inner" ''
        exec ${claudePkg}/bin/claude --dangerously-skip-permissions "$@"
      '';

      # Shared sandbox configuration for Claude Code
      # Allows full access within workspace directories while restricting everything else
      claudeSandboxBase = {
        imports = [
          landrun-nix.landrunModules.gh # GitHub CLI with D-Bus keyring support
          landrun-nix.landrunModules.git # Git with TTY and repository access
        ];

        features = {
          tty = true; # Terminal support for interactive usage
          nix = true; # Nix store access (read) and daemon socket
          network = true; # Outbound network for API calls
          # Disable dbus feature inherited from landrunModules.gh
          # The gh module enables dbus for keyring/Secret Service API access,
          # but $HOME/.local/share/keyrings may not exist on all systems
          dbus = lib.mkForce false;
        };

        cli = {
          # Read-write paths for Claude state and credentials
          # Note: landrun requires rw/rwx paths to exist at runtime (unlike ro/rox which are conditional)
          # The ensureLandrunPaths activation script creates these directories if missing
          rw = [
            "$HOME/.claude" # Claude state directory
            "$HOME/.claude.json" # Claude config file (created by claude on first run)
            "$HOME/.config/gcloud" # Google Cloud auth (for Vertex AI)
            "$HOME/.cache/claude-cli-nodejs" # Node.js cache
          ];

          # Read-write-execute for workspace directories
          # These are the meta-workspace boundaries within which Claude operates freely
          rwx = [
            "$HOME/projects" # Primary workspace: all project repositories
          ];

          # Environment variables to pass through
          env = [
            "HOME" # Required for path resolution
            "ANTHROPIC_MODEL"
            "ANTHROPIC_API_KEY"
            "ANTHROPIC_BASE_URL"
          ];
        };
      };
    in
    lib.mkIf isLinux {
      landrunApps = {
        # Standard sandboxed Claude - internal permission prompts remain active
        claude-sandboxed = claudeSandboxBase // {
          program = "${claudePkg}/bin/claude";
        };

        # Sandboxed Claude with --dangerously-skip-permissions
        # Internal prompts bypassed, but landrun enforces workspace boundaries
        # Uses wrapper script since extraArgs are landrun arguments, not program arguments
        ccds-sandboxed = claudeSandboxBase // {
          program = "${ccdsSandboxedWrapper}";
        };
      };
    };
}
