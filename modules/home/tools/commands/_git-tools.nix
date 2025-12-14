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

  # git log as JSON
  gitjson = {
    runtimeInputs = with pkgs; [
      git
      jc
      nushell
    ];
    text = ''
      case "''${1:-}" in
        -h|--help)
          cat <<'HELP'
      Display git log as JSON

      Usage: gitjson

      Converts git log output to JSON format using jc and displays
      it with nushell for better formatting.

      Example:
        gitjson    # Show entire git log as JSON
      HELP
          exit 0
          ;;
      esac

      exec nu -c "git log | jc --git-log | from json"
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

  # create a private github fork
  gfork = {
    runtimeInputs = with pkgs; [
      gh
      git
    ];
    text = ''
      case "''${1:-}" in
        -h|--help)
          cat <<'HELP'
      Create a private fork of current repository

      Usage: gfork

      Creates a private GitHub repository as a fork:
        1. Renames 'origin' remote to 'upstream'
        2. Creates new private repo on your GitHub account
        3. Sets the new repo as 'origin'
        4. Pushes current branch to new origin

      Requirements:
        - Must be run inside a git repository
        - GitHub CLI (gh) must be authenticated

      Interactive:
        - Prompts for confirmation or new repo name
      HELP
          exit 0
          ;;
      esac

      if ! command -v gh &> /dev/null; then
        echo "Error: GitHub CLI (gh) is not installed" >&2
        exit 1
      fi

      if ! git rev-parse --is-inside-work-tree &> /dev/null; then
        echo "Error: Not inside a git repository" >&2
        exit 1
      fi

      echo "Current remotes:"
      git remote -v

      echo
      echo "Renaming origin to upstream..."
      git remote rename origin upstream 2>/dev/null || echo "Note: No 'origin' remote to rename"

      repo_name=$(basename "$(git rev-parse --show-toplevel)")
      gh_username=$(gh api user --jq .login 2>/dev/null)

      if [ -z "$gh_username" ]; then
        echo "Error: Could not get GitHub username. Please run 'gh auth login'" >&2
        exit 1
      fi

      echo "Creating repo: $gh_username/$repo_name"
      printf "Press enter to continue or type new name: "
      read -r new_name

      final_name="''${new_name:-$repo_name}"
      echo "Creating private repository: $gh_username/$final_name"

      if gh repo create "$gh_username/$final_name" --private --push -r origin -s .; then
        echo "Successfully created and pushed to private repository: $gh_username/$final_name"
        echo "Updated remotes:"
        git remote -v
      else
        echo "Error: Failed to create repository" >&2
        exit 1
      fi
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

  # get github noreply email address
  github-email = {
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
  };

  # check github token scopes
  check-github-token-scopes = {
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
  };

  # approve open PRs with optional exclusions
  gh-approve-open-prs = {
    runtimeInputs = with pkgs; [ gh ];
    text = ''
      show_help() {
        cat <<'HELP'
      Approve all open pull requests with optional exclusions

      Usage: gh-approve-open-prs [OPTIONS] [EXCLUDE...]

      Approves all open PRs in the current repository, optionally excluding
      specific PR numbers.

      Arguments:
        EXCLUDE...    PR numbers to exclude from approval (optional)

      Options:
        -n, --dry-run    Show what would be approved without approving
        -h, --help       Show this help message

      Examples:
        gh-approve-open-prs                    # Approve all open PRs
        gh-approve-open-prs 158 191            # Approve all except #158 and #191
        gh-approve-open-prs -n                 # Dry run: list PRs that would be approved
        gh-approve-open-prs -n 158             # Dry run excluding #158

      Requirements:
        - GitHub CLI (gh) must be authenticated
        - Must be run inside a git repository with a GitHub remote
      HELP
      }

      dry_run=false
      exclude_prs=()

      # Parse arguments
      while [[ $# -gt 0 ]]; do
        case "$1" in
          -h|--help)
            show_help
            exit 0
            ;;
          -n|--dry-run)
            dry_run=true
            shift
            ;;
          -*)
            echo "Error: Unknown option: $1" >&2
            echo "Try 'gh-approve-open-prs --help' for more information." >&2
            exit 1
            ;;
          *)
            if ! [[ "$1" =~ ^[0-9]+$ ]]; then
              echo "Error: PR number must be a positive integer: $1" >&2
              exit 1
            fi
            exclude_prs+=("$1")
            shift
            ;;
        esac
      done

      # Get all open PR numbers
      all_prs=$(gh pr list --state open --json number --jq '.[].number' 2>/dev/null)

      if [[ -z "$all_prs" ]]; then
        echo "No open PRs found."
        exit 0
      fi

      # Filter out excluded PRs
      prs_to_approve=()
      while IFS= read -r pr; do
        skip=false
        for excl in "''${exclude_prs[@]}"; do
          if [[ "$pr" == "$excl" ]]; then
            skip=true
            break
          fi
        done
        if ! $skip; then
          prs_to_approve+=("$pr")
        fi
      done <<< "$all_prs"

      if [[ ''${#prs_to_approve[@]} -eq 0 ]]; then
        echo "No PRs to approve after exclusions."
        exit 0
      fi

      # Show what will be approved
      echo "PRs to approve: ''${prs_to_approve[*]}"
      if [[ ''${#exclude_prs[@]} -gt 0 ]]; then
        echo "Excluded PRs: ''${exclude_prs[*]}"
      fi
      echo

      if $dry_run; then
        echo "[Dry run] Would approve ''${#prs_to_approve[@]} PR(s):"
        for pr in "''${prs_to_approve[@]}"; do
          title=$(gh pr view "$pr" --json title --jq '.title' 2>/dev/null)
          echo "  #$pr - $title"
        done
        exit 0
      fi

      # Approve PRs
      approved=0
      failed=0
      for pr in "''${prs_to_approve[@]}"; do
        echo "Approving PR #$pr..."
        if gh pr review "$pr" --approve; then
          ((approved++))
        else
          echo "Warning: Failed to approve PR #$pr" >&2
          ((failed++))
        fi
      done

      echo
      echo "Approved: $approved, Failed: $failed"
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
