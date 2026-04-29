{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "pr-diff";
          runtimeInputs = with pkgs; [
            gh
            ripgrep
          ];
          text = ''
            case "''${1:-}" in
              -h|--help)
                cat <<'HELP'
            Show added/removed lines from a pull request diff

            Usage: pr-diff PR_NUMBER [LINES]

            Displays lines beginning with + or - from the PR's unified diff,
            limited to the specified number of output lines.

            Arguments:
              PR_NUMBER    Pull request number (required)
              LINES        Maximum output lines (default: 50)

            Examples:
              pr-diff 1004        # Show first 50 +/- lines
              pr-diff 1004 100    # Show first 100 +/- lines
            HELP
                exit 0
                ;;
              "")
                echo "Error: PR number required" >&2
                echo "Usage: pr-diff PR_NUMBER [LINES]" >&2
                echo "Try 'pr-diff --help' for more information." >&2
                exit 1
                ;;
            esac

            if ! [[ "$1" =~ ^[0-9]+$ ]]; then
              echo "Error: PR number must be a positive integer: $1" >&2
              exit 1
            fi

            pr_number="$1"
            lines="''${2:-50}"

            gh pr diff "$pr_number" | rg '^[+-]' | head -"$lines"
          '';
          meta.description = "Show added/removed lines from a pull request diff";
        })
      ];
    };
}
