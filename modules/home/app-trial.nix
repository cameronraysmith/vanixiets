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
      apps.home-trial = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "home-trial";
            runtimeInputs = [
              pkgs.nix
            ];
            meta.description = "Trial-activate target user's portable subset under operator's $USER and $HOME (no secrets, stranger-safe)";
            text = ''
              set -euo pipefail

              if [ $# -eq 0 ] || [ "''${1:-}" = "-h" ] || [ "''${1:-}" = "--help" ]; then
                cat >&2 <<-EOF
                	Usage: nix run <flake>#home-trial -- <template-user> [flake]

                	Trial-activate <template-user>'s PORTABLE content under the
                	current login (\$USER, \$HOME). No secrets, no sops keys, no
                	identity-bound files (e.g. signing keys, allowed_signers).

                	Use case: stranger wanting to experiment with a curated subset
                	of someone else's home configuration without their secrets.

                	Examples:
                	  nix run github:cameronraysmith/vanixiets#home-trial -- crs58
                	  nix run .#home-trial -- crs58 .
                EOF
                exit 1
              fi

              target_user="$1"
              shift

              if [ $# -gt 0 ] && [[ ! "$1" =~ ^- ]]; then
                flake="$1"
                shift
              else
                flake="github:cameronraysmith/vanixiets"
              fi

              system="${system}"
              operator_username="''${USER:-$(id -un)}"
              operator_home="''${HOME:?HOME must be set}"

              cat <<-EOF
              	Building home-trial activation package...
              	  Target template: $target_user (portable subset only)
              	  Operator user:   $operator_username
              	  Operator HOME:   $operator_home
              	  System:          $system
              	  Flake:           $flake

              EOF

              activation=$(nix --extra-experimental-features 'nix-command flakes' \
                build --impure --no-link --print-out-paths "$@" \
                --expr "
                  let
                    flake = builtins.getFlake \"$flake\";
                  in
                    (flake.lib.mkHome {
                      user = \"$target_user\";
                      username = \"$operator_username\";
                      homeDirectory = \"$operator_home\";
                      system = \"$system\";
                      includePrivate = false;
                    }).activationPackage
                ")

              echo "Built: $activation"
              echo "Running: $activation/activate"
              exec "$activation/activate"
            '';
          }
        );
      };
    };
}
