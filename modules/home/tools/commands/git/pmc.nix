{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "pmc";
          runtimeInputs = with pkgs; [ git ];
          text = ''
            case "''${1:-}" in
              -h|--help)
                cat <<'HELP'
            Pre-merge check for git branches

            Usage: pmc [BRANCH]

            Shows detailed information about changes between current HEAD and
            target branch to review before merging.

            Arguments:
              BRANCH    Branch to compare against (default: upstream/main)

            Output includes:
              - Commit summary (one-line)
              - Detailed commit logs
              - Files changed with status

            Examples:
              pmc                    # Compare with upstream/main
              pmc origin/develop     # Compare with origin/develop
            HELP
                exit 0
                ;;
            esac

            branch="''${1:-upstream/main}"
            export PAGER=cat

            echo 'Commit Summary:'
            git log HEAD.."$branch" --oneline
            echo
            echo 'Detailed Commit Logs:'
            git log HEAD.."$branch"
            echo
            echo 'Files Changed (Name Status):'
            git diff --name-status HEAD..."$branch"
          '';
          meta.description = "Pre-merge check for git branches";
        })
      ];
    };
}
