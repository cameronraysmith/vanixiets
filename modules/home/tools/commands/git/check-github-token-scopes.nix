{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "check-github-token-scopes";
          runtimeInputs = with pkgs; [
            curl
            gnugrep
          ];
          text = ''
            case "''${1:-}" in
              -h|--help)
                cat <<'HELP'
            Check GitHub personal access token scopes

            Usage: check-github-token-scopes TOKEN

            Lists the active scopes of a GitHub legacy personal access token.

            Arguments:
              TOKEN    GitHub personal access token to check

            Example:
              check-github-token-scopes ghp_xxxxxxxxxxxxxxxxxxxx
            HELP
                exit 0
                ;;
              "")
                echo "Error: GitHub token required" >&2
                echo "Usage: check-github-token-scopes TOKEN" >&2
                echo "Try 'check-github-token-scopes --help' for more information." >&2
                exit 1
                ;;
            esac

            token="$1"
            curl -sS -f -I -H "Authorization: token $token" https://api.github.com | grep -i x-oauth-scopes
          '';
          meta.description = "Check GitHub personal access token scopes";
        })
      ];
    };
}
