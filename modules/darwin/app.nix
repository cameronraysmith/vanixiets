# The .#darwin app: activate a nix-darwin configuration with nh, after
# checking the host's clan machine key.
#
# Local activation never installs /var/lib/sops-nix/key.txt (only
# `clan machines update|install` and `clan vars upload` do), and sops-nix
# fails to install secrets without it. So for every darwin host whose
# machine key exists in this repository (sops/secrets/<host>-age.key), the
# app compares the public key of the installed key file with
# sops/machines/<host>/key.json before activating, and stops with the remedy
# when it is missing or different (continuing under --dry). The expected keys
# are baked in from the flake the app was built from. Only public keys are
# printed. MACHINE_KEY_FILE overrides the key file path for testing.
topArgs@{ ... }:
let
  inherit (topArgs) lib;
  machineKeys = lib.filterAttrs (_: v: v != null) (
    lib.genAttrs (lib.attrNames topArgs.config.flake.darwinConfigurations) (
      host:
      if builtins.pathExists (../../sops/secrets + "/${host}-age.key/secret") then
        (builtins.head (builtins.fromJSON (builtins.readFile (../../sops/machines + "/${host}/key.json"))))
        .publickey
      else
        null
    )
  );
in
{
  # Expected machine public keys per darwin host, for the guard below and for inspection.
  flake.lib.darwinMachineKeys = machineKeys;

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
                pkgs.age
              ];
              meta.description = "Build and activate the nix-darwin configuration for a hostname (uses nh)";
              text = ''
                set -euo pipefail

                # Show help if requested or no args provided
                if [ $# -eq 0 ] || [ "''${1:-}" = "-h" ] || [ "''${1:-}" = "--help" ]; then
                  cat >&2 <<-EOF
                	Usage: nix run <flake>#darwin -- <hostname> [flake] [NH_FLAGS...]

                	Examples:
                	  # Remote usage (most common)
                	  nix run github:cameronraysmith/vanixiets#darwin -- blackphos
                	  nix run github:cameronraysmith/vanixiets#darwin -- blackphos --dry

                	  # Development/local usage (override flake location)
                	  nix run .#darwin -- blackphos .
                	  nix run .#darwin -- blackphos . --dry

                	  # Auto-detect hostname from system (if hostname matches config)
                	  nix run .#darwin -- \$(hostname -s) . --dry

                	Builds and activates the nix-darwin configuration for the specified hostname.

                	Arguments:
                	  hostname  - Darwin machine hostname (required)
                	  flake     - Flake path (optional, default: github:cameronraysmith/vanixiets)
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
                  flake="github:cameronraysmith/vanixiets"
                fi

                # Machine-key guard: see the header of modules/darwin/app.nix.
                expected=""
                case "$hostname" in
                ${lib.concatStrings (lib.mapAttrsToList (h: k: "  ${h}) expected=${k} ;;\n") machineKeys)}
                esac
                dry=0
                for arg in "$@"; do [ "$arg" = "--dry" ] && dry=1; done
                if [ -n "$expected" ]; then
                  key_file="''${MACHINE_KEY_FILE:-/var/lib/sops-nix/key.txt}"
                  actual=""
                  found="missing"
                  if [ -e "$key_file" ]; then
                    if [ -r "$key_file" ]; then
                      actual=$(age-keygen -y "$key_file" 2>/dev/null || true)
                    else
                      actual=$(sudo ${pkgs.age}/bin/age-keygen -y "$key_file" 2>/dev/null || true)
                    fi
                    found="''${actual:-present but unreadable (sudo age-keygen -y failed)}"
                  fi
                  if [ "$actual" != "$expected" ]; then
                    cat >&2 <<-EOF
                	Machine key check failed for $hostname ($key_file):
                	  expected: $expected (sops/machines/$hostname/key.json)
                	  found:    $found
                	sops-nix cannot install this host's secrets without it.
                	Install it with: clan vars upload $hostname
                	EOF
                    if [ "$dry" -eq 1 ]; then
                      echo "--dry: continuing despite the machine key check" >&2
                    else
                      exit 1
                    fi
                  fi
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
