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

  perSystem =
    {
      pkgs,
      system,
      lib,
      ...
    }:
    let
      isLinux = lib.hasSuffix "-linux" system;
      claudePkg = inputs.llm-agents.packages.${system}.claude-code;

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
        };

        cli = {
          # Read-write paths for Claude state and credentials
          rw = [
            "$HOME/.claude" # Claude state directory
            "$HOME/.claude.json" # Claude config file
            "$HOME/.config/gcloud" # Google Cloud auth (for Vertex AI)
            "$HOME/.cache/claude-cli-nodejs" # Node.js cache
          ];

          # Read-write-execute for workspace directories
          # These are the meta-workspace boundaries within which Claude operates freely
          rwx = [
            "$HOME/projects" # Primary workspace: all project repositories
            "$HOME/agents" # Agent workspace directories
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
        ccds-sandboxed = claudeSandboxBase // {
          program = "${claudePkg}/bin/claude";
          cli = claudeSandboxBase.cli // {
            extraArgs = [
              "--"
              "--dangerously-skip-permissions"
            ];
          };
        };
      };
    };
}
