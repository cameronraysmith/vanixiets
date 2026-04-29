{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "stash-staged";
          runtimeInputs = with pkgs; [ git ];
          text = ''
            case "''${1:-}" in
              -h|--help)
                cat <<'HELP'
            Save staged changes to stash while keeping them staged

            Usage: stash-staged MESSAGE

            Creates a stash containing only the staged changes, then immediately
            reapplies them to keep them staged. This allows you to save a snapshot
            of staged changes while continuing to work with them.

            Arguments:
              MESSAGE    Required stash message describing the changes

            Workflow:
              1. Stashes staged changes with your message
              2. Reapplies the stash to restore staged state
              3. Shows current stash list
              4. Provides command to view the stash later

            Example:
              stash-staged "API refactoring"

            To view the stash later:
              PAGER=cat git stash show -p stash@{0}
            HELP
                exit 0
                ;;
              "")
                echo "Error: Stash message required" >&2
                echo "Usage: stash-staged MESSAGE" >&2
                echo "Try 'stash-staged --help' for more information." >&2
                exit 1
                ;;
            esac

            message="$1"

            echo "Stashing staged changes: $message"
            git stash push --staged -m "$message"

            echo "Reapplying staged changes..."
            git stash apply --index

            echo
            echo "Current stash list:"
            git stash list

            echo
            echo "To view this stash later, run:"
            echo "PAGER=cat git stash show -p stash@{0}"
          '';
          meta.description = "Save staged changes to stash while keeping them staged";
        })
      ];
    };
}
