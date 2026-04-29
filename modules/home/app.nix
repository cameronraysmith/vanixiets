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
        home = {
          type = "app";
          program = lib.getExe (
            pkgs.writeShellApplication {
              name = "home-switch";
              runtimeInputs = [
                pkgs.nh
              ];
              meta.description = "Activate home-manager configuration for a user on the current system architecture (uses nh)";
              text = ''
                set -euo pipefail

                # Show help if requested or no args provided
                if [ $# -eq 0 ] || [ "''${1:-}" = "-h" ] || [ "''${1:-}" = "--help" ]; then
                  current_user="''${USER:-$(id -un)}"
                  cat >&2 <<-EOF
                	Usage: nix run <flake> -- <username> [flake] [NH_FLAGS...]

                	Examples:
                	  # Remote usage (most common - uses default app)
                	  nix run github:cameronraysmith/vanixiets -- $current_user
                	  nix run github:cameronraysmith/vanixiets -- $current_user --dry

                	  # Explicit app reference (equivalent)
                	  nix run github:cameronraysmith/vanixiets#home -- $current_user

                	  # Development/local usage (override flake location)
                	  nix run .#home -- $current_user .
                	  nix run . -- $current_user . --dry

                	Activates the home-manager configuration for the specified user
                	on the current system architecture (${system}).

                	Arguments:
                	  username  - User to activate home-manager for (required)
                	  flake     - Flake path (optional, default: github:cameronraysmith/vanixiets)
                	  NH_FLAGS  - Flags passed to 'nh home switch' (--dry, --verbose, --ask, etc.)

                	This works even when run as root, as long as the target user exists.
                	EOF
                  exit 1
                fi

                username="$1"
                shift

                # Check if next arg is a flake path (doesn't start with -)
                # Default to remote repo for common case, allow override for development
                if [ $# -gt 0 ] && [[ ! "$1" =~ ^- ]]; then
                  flake="$1"
                  shift
                else
                  flake="github:cameronraysmith/vanixiets"
                fi

                system="${system}"
                # Full flake attribute path including activationPackage
                # Format: flake#homeConfigurations."USERNAME@SYSTEM".activationPackage
                config_path="homeConfigurations.\"$username@$system\".activationPackage"

                cat <<-EOF
                	Activating home-manager configuration...
                	  User:   $username
                	  System: $system
                	  Flake:  $flake
                	  Config: $config_path

                	EOF

                # Use full installable path (not -c flag) for nested structure
                # Pass any additional arguments (like --dry, --verbose, etc.) to nh
                # Always include --accept-flake-config for nh's internal nix calls
                exec nh home switch "$flake#$config_path" --accept-flake-config "$@"
              '';
            }
          );
        };

        # Make home the default app for ergonomic usage:
        # nix run github:cameronraysmith/vanixiets -- crs58
        default = config.apps.home;
      };
    };
}
