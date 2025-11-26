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
        darwin = {
          type = "app";
          program = lib.getExe (
            pkgs.writeShellApplication {
              name = "darwin-switch";
              runtimeInputs = [
                pkgs.nh
              ];
              text = ''
                set -euo pipefail

                # Show help if requested or no args provided
                if [ $# -eq 0 ] || [ "''${1:-}" = "-h" ] || [ "''${1:-}" = "--help" ]; then
                  cat >&2 <<-EOF
                	Usage: nix run <flake>#darwin -- <hostname> [flake] [NH_FLAGS...]

                	Examples:
                	  # Remote usage (most common)
                	  nix run github:cameronraysmith/test-clan#darwin -- blackphos
                	  nix run github:cameronraysmith/test-clan#darwin -- blackphos --dry

                	  # Development/local usage (override flake location)
                	  nix run .#darwin -- blackphos .
                	  nix run .#darwin -- blackphos . --dry

                	  # Auto-detect hostname from system (if hostname matches config)
                	  nix run .#darwin -- \$(hostname -s) . --dry

                	Builds and activates the nix-darwin configuration for the specified hostname.

                	Arguments:
                	  hostname  - Darwin machine hostname (required)
                	  flake     - Flake path (optional, default: github:cameronraysmith/test-clan)
                	  NH_FLAGS  - Flags passed to 'nh darwin switch' (--dry, --verbose, --ask, etc.)

                	Safety:
                	  Use --dry flag to preview changes without applying them.
                	  Example: nix run .#darwin -- blackphos . --dry

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
                	Activating nix-darwin configuration...
                	  Hostname: $hostname
                	  Flake:    $flake
                	  Command:  nh darwin switch "$flake" -H "$hostname" $*

                	EOF

                # Use nh darwin switch with hostname flag
                # Pass any additional arguments (like --dry, --verbose, etc.) to nh
                # Always include --accept-flake-config for nh's internal nix calls
                exec nh darwin switch "$flake" -H "$hostname" --accept-flake-config "$@"
              '';
            }
          );
        };
      };
    };
}
