{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "flakeup";
          runtimeInputs = with pkgs; [ nix ];
          text = ''
            case "''${1:-}" in
              -h|--help)
                cat <<'HELP'
            Update Nix flake and commit lock file

            Usage: flakeup [FLAKE_ARGS...]

            Updates flake inputs and automatically commits the lock file.

            Arguments:
              FLAKE_ARGS    Additional arguments for 'nix flake update'

            Examples:
              flakeup                    # Update all inputs
              flakeup --update-input foo # Update specific input
            HELP
                exit 0
                ;;
            esac

            exec nix flake update --commit-lock-file "$@"
          '';
          meta.description = "Update Nix flake and commit lock file";
        })
      ];
    };
}
