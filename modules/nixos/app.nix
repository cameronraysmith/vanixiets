{ ... }:
{
  perSystem =
    {
      pkgs,
      system,
      lib,
      config,
      ...
    }:
    {
      apps = {
        os = {
          type = "app";
          program = lib.getExe (
            pkgs.writeShellApplication {
              name = "nixos-switch";
              runtimeInputs = [
                pkgs.nh
              ];
              text = ''
                set -euo pipefail

                # Show help if requested or no args provided
                if [ $# -eq 0 ] || [ "''${1:-}" = "-h" ] || [ "''${1:-}" = "--help" ]; then
                  cat >&2 <<-EOF
                	Usage: nix run <flake>#os -- <hostname> [flake] [NH_FLAGS...]

                	Examples:
                	  # Remote usage (most common)
                	  nix run github:cameronraysmith/test-clan#os -- cinnabar
                	  nix run github:cameronraysmith/test-clan#os -- cinnabar --dry

                	  # Development/local usage (override flake location)
                	  nix run .#os -- cinnabar .
                	  nix run .#os -- cinnabar . --dry

                	  # Auto-detect hostname from system (if hostname matches config)
                	  nix run .#os -- \$(hostname) . --dry

                	Builds and activates the NixOS configuration for the specified hostname.

                	Arguments:
                	  hostname  - NixOS machine hostname (required)
                	  flake     - Flake path (optional, default: github:cameronraysmith/test-clan)
                	  NH_FLAGS  - Flags passed to 'nh os switch' (--dry, --verbose, --ask, etc.)

                	Safety:
                	  Use --dry flag to preview changes without applying them.
                	  Example: nix run .#os -- cinnabar . --dry

                	Note: Requires appropriate permissions. nh handles sudo elevation automatically.
                	EOF
                  exit 1
                fi

                hostname="$1"
                shift

                # Check if next arg is a flake path (doesn't start with -)
                # Default to remote repo for common case, allow override for development
                if [ $# -gt 0 ] && [[ ! "$1" =~ ^- ]]; then
                  flake="$1"
                  shift
                else
                  flake="github:cameronraysmith/test-clan"
                fi

                cat <<-EOF
                	Activating NixOS configuration...
                	  Hostname: $hostname
                	  Flake:    $flake
                	  Command:  nh os switch "$flake" -H "$hostname" $*

                	EOF

                # Use nh os switch with hostname flag
                # Pass any additional arguments (like --dry, --verbose, etc.) to nh
                # Always include --accept-flake-config for nh's internal nix calls
                exec nh os switch "$flake" -H "$hostname" --accept-flake-config "$@"
              '';
            }
          );
        };
      };
    };
}
