{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "github-email";
          runtimeInputs = with pkgs; [ gh ];
          text = ''
            case "''${1:-}" in
              -h|--help)
                cat <<'HELP'
            Get GitHub noreply email address for a user

            Usage: github-email USERNAME

            Retrieves the noreply email address for a GitHub user using the
            GitHub API.

            Arguments:
              USERNAME    GitHub username

            Example:
              github-email octocat
              # Returns: 1234567+octocat@users.noreply.github.com
            HELP
                exit 0
                ;;
              "")
                echo "Error: Username required" >&2
                echo "Usage: github-email USERNAME" >&2
                echo "Try 'github-email --help' for more information." >&2
                exit 1
                ;;
            esac

            username="$1"

            if ! command -v gh &> /dev/null; then
              echo "Error: GitHub CLI (gh) is not installed" >&2
              exit 1
            fi

            user_id=$(gh api "users/''${username}" --jq ".id" 2>/dev/null)

            if [ -z "$user_id" ]; then
              echo "Error: Failed to retrieve user ID for username: ''${username}" >&2
              exit 1
            fi

            echo "''${user_id}+''${username}@users.noreply.github.com"
          '';
          meta.description = "Get GitHub noreply email address for a user";
        })
      ];
    };
}
