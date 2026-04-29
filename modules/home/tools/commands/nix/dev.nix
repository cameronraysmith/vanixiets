{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "dev";
          runtimeInputs = with pkgs; [ nix ];
          text = ''
            case "''${1:-}" in
              -h|--help)
                cat <<'HELP'
            Enter Nix development shell

            Usage: dev [NIX_ARGS...]

            Shorthand wrapper for 'nix develop'.

            Arguments:
              NIX_ARGS    Arguments to pass to 'nix develop'

            Examples:
              dev                   # Enter default devShell
              dev .#backend         # Enter specific devShell
              dev --command bash    # Run command in devShell
            HELP
                exit 0
                ;;
            esac

            exec nix develop "$@"
          '';
          meta.description = "Enter Nix development shell";
        })
      ];
    };
}
