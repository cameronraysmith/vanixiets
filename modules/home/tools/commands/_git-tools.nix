{
  pkgs,
  lib,
  config,
}:
{
  # pre-merge check for git branches
  pmc = {
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
  };

  # git log lines as JSON
  gitjsonl = {
    runtimeInputs = with pkgs; [
      git
      jc
      nushell
    ];
    text = ''
      case "''${1:-}" in
        -h|--help)
          cat <<'HELP'
      Display git log lines as JSON

      Usage: gitjsonl [LINES]

      Shows specified number of git log entries as JSON in transposed format.

      Arguments:
        LINES    Number of log entries to show (default: 1)

      Examples:
        gitjsonl      # Show latest commit as JSON
        gitjsonl 5    # Show latest 5 commits as JSON
      HELP
          exit 0
          ;;
      esac

      lines="''${1:-1}"
      exec nu -c "git log | jc --git-log | from json | take $lines | transpose"
    '';
  };

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

  # show PR diff with added/removed lines
  pr-diff = {
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

  # backport a GitHub PR by cherry-picking its merge commit
  jj-backport-github-pr = {
    runtimeInputs = with pkgs; [
      gh
      jujutsu
    ];
    text = ''
      case "''${1:-}" in
        -h|--help)
          cat <<'HELP'
      Backport a GitHub PR by cherry-picking its merge commit

      Usage: jj-backport-github-pr PR

      Resolves the merge commit SHA from a GitHub PR and cherry-picks
      the merged changes into the current jujutsu working copy using
      the cherry-pick alias (which adds provenance trailers).

      Arguments:
        PR    GitHub PR number, URL, or owner/repo#N format

      Requirements:
        - GitHub CLI (gh) must be authenticated
        - jj cherry-pick alias must be configured
        - Repository must have the PR's commits fetched

      Examples:
        jj-backport-github-pr 123
        jj-backport-github-pr https://github.com/org/repo/pull/123
      HELP
          exit 0
          ;;
        "")
          echo "Error: PR identifier required" >&2
          echo "Usage: jj-backport-github-pr PR" >&2
          echo "Try 'jj-backport-github-pr --help' for more information." >&2
          exit 1
          ;;
      esac

      sha=$(gh pr view "$1" --json mergeCommit --jq .mergeCommit.oid)

      if [ -z "$sha" ]; then
        echo "Error: Could not resolve merge commit for PR: $1" >&2
        echo "The PR may not be merged yet." >&2
        exit 1
      fi

      echo "Backporting merge commit: $sha"
      jj cherry-pick -r "merged($sha)"
    '';
  };
}
