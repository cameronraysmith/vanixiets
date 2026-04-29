{
  pkgs,
  lib,
  config,
}:
{
  # save staged changes to stash while keeping them staged
  stash-staged = {
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
  };

  # re-run github actions workflow checks for a PR
  rerun-pr-checks = {
    runtimeInputs = with pkgs; [ gh ];
    text = ''
      show_help() {
        cat <<'HELP'
      Re-run GitHub Actions workflow checks for a pull request

      Usage: rerun-pr-checks [OPTIONS] PR_NUMBER

      Re-runs the latest workflow run associated with a pull request.
      By default, only failed jobs are re-run.

      Arguments:
        PR_NUMBER    Pull request number (required)

      Options:
        -f, --failed    Re-run only failed jobs (default)
        -a, --all       Re-run all jobs, not just failed ones
        -h, --help      Show this help message

      Examples:
        rerun-pr-checks 170           # Re-run failed jobs for PR #170
        rerun-pr-checks --failed 170  # Same as above (explicit)
        rerun-pr-checks --all 170     # Re-run all jobs for PR #170

      Requirements:
        - GitHub CLI (gh) must be authenticated
        - Must have appropriate permissions on the repository
      HELP
      }

      # Default to --failed
      rerun_mode="--failed"
      pr_number=""

      # Parse arguments
      while [[ $# -gt 0 ]]; do
        case "$1" in
          -h|--help)
            show_help
            exit 0
            ;;
          -f|--failed)
            rerun_mode="--failed"
            shift
            ;;
          -a|--all)
            rerun_mode=""
            shift
            ;;
          -*)
            echo "Error: Unknown option: $1" >&2
            echo "Try 'rerun-pr-checks --help' for more information." >&2
            exit 1
            ;;
          *)
            if [[ -z "$pr_number" ]]; then
              pr_number="$1"
            else
              echo "Error: Unexpected argument: $1" >&2
              echo "Try 'rerun-pr-checks --help' for more information." >&2
              exit 1
            fi
            shift
            ;;
        esac
      done

      # Validate PR number
      if [[ -z "$pr_number" ]]; then
        echo "Error: PR number required" >&2
        echo "Usage: rerun-pr-checks [OPTIONS] PR_NUMBER" >&2
        echo "Try 'rerun-pr-checks --help' for more information." >&2
        exit 1
      fi

      if ! [[ "$pr_number" =~ ^[0-9]+$ ]]; then
        echo "Error: PR number must be a positive integer: $pr_number" >&2
        exit 1
      fi

      # Get the head branch of the PR
      echo "Looking up PR #$pr_number..."
      head_branch=$(gh pr view "$pr_number" --json headRefName -q '.headRefName' 2>/dev/null)

      if [[ -z "$head_branch" ]]; then
        echo "Error: Could not find PR #$pr_number or retrieve its head branch" >&2
        echo "Make sure you are in a repository with this PR or specify -R owner/repo" >&2
        exit 1
      fi

      echo "PR head branch: $head_branch"

      # Get the latest workflow run for this branch
      run_id=$(gh run list --branch "$head_branch" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null)

      if [[ -z "$run_id" ]]; then
        echo "Error: No workflow runs found for branch: $head_branch" >&2
        exit 1
      fi

      echo "Latest workflow run ID: $run_id"

      # Re-run the workflow
      if [[ -n "$rerun_mode" ]]; then
        echo "Re-running failed jobs..."
        gh run rerun "$run_id" $rerun_mode
      else
        echo "Re-running all jobs..."
        gh run rerun "$run_id"
      fi

      echo "Re-run initiated. View progress with: gh run watch $run_id"
    '';
  };

}
