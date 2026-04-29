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
      apps.home-as = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "home-as";
            runtimeInputs = [
              pkgs.nix
            ];
            meta.description = "Activate target user's home-manager content under operator's $USER and $HOME (same human, different login; mkForce identity override)";
            text = ''
              set -euo pipefail

              if [ $# -eq 0 ] || [ "''${1:-}" = "-h" ] || [ "''${1:-}" = "--help" ]; then
                cat >&2 <<-EOF
                	Usage: nix run <flake>#home-as -- <target-user> [flake]

                	Activate <target-user>'s home configuration content under the
                	current login (\$USER, \$HOME). Identity (home.username and
                	home.homeDirectory) is overridden to the operator's values
                	via mkForce; package selection, dotfiles, and secrets-bearing
                	options come from <target-user>'s users/<target-user> module.

                	Use case: same human, different login on a different machine.
                	(Activation requires the target user's age key for sops decryption.)

                	Examples:
                	  nix run github:cameronraysmith/vanixiets#home-as -- crs58
                	  nix run .#home-as -- crs58 .
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
              	Building home-as activation package...
              	  Target template: $target_user
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
