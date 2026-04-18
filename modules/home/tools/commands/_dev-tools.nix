{
  pkgs,
  lib,
  config,
}:
{
  # npm claude code with dangerously skip permissions
  npmccds = {
    runtimeInputs = with pkgs; [ bun ];
    text = ''
      exec bunx -p @anthropic-ai/claude-code@next claude --dangerously-skip-permissions "$@"
    '';
  };

  # list claude code npm package versions with tags
  ccvers = {
    runtimeInputs = with pkgs; [
      nodejs
      jq
      coreutils
      gawk
    ];
    text = ''
      case "''${1:-}" in
        -h|--help)
          cat <<'HELP'
      List Claude Code npm package versions with tags and release times

      Usage: ccvers [LIMIT]

      Shows recent versions of @anthropic-ai/claude-code package with:
        - Release timestamp in Eastern Time (EDT/EST)
        - Version number
        - Distribution tags (latest, next, etc.) if applicable

      Arguments:
        LIMIT    Number of recent versions to show (default: 20)

      Examples:
        ccvers       # Show last 20 versions
        ccvers 10    # Show last 10 versions
        ccvers 50    # Show last 50 versions
      HELP
          exit 0
          ;;
      esac

      limit="''${1:-20}"

      npm view @anthropic-ai/claude-code --json | jq -r '
        ."dist-tags" as $tags |
        .time as $times |
        .versions[] |
        . as $v |
        ($tags | to_entries | map(select(.value == $v) | .key) | join(", ")) as $labels |
        $times[$v] as $timestamp |
        if ($labels | length) > 0 then
          "\($timestamp)|\($v)|(\($labels))"
        else
          "\($timestamp)|\($v)|"
        end
      ' | sort -t'|' -k2Vr | head -"$limit" | awk -F'|' '{
        cmd = "TZ=America/New_York date -d \""$1"\" \"+%Y-%m-%d %H:%M %Z\""
        cmd | getline eastern
        close(cmd)
        printf "%s  %s %s\n", eastern, $2, $3
      }'
    '';
  };

  # get claude code session working directory
  claude-session-cwd = {
    runtimeInputs = with pkgs; [
      findutils
      jq
      gnugrep
      gnused
      coreutils
    ];
    text = ''
      case "''${1:-}" in
        -h|--help)
          cat <<'HELP'
      Get Claude Code session working directory and metadata

      Usage: claude-session-cwd SESSION_ID

      Displays the working directory and metadata for a Claude Code session.

      Arguments:
        SESSION_ID    UUID of the Claude Code session to query

      Output:
        - Session ID
        - Working directory (cwd)
        - Git branch (if applicable)
        - Session file path

      Examples:
        claude-session-cwd a2d00721-39cb-49d9-8827-099d0e9f5d38
      HELP
          exit 0
          ;;
        "")
          echo "Error: Session ID required" >&2
          echo "Usage: claude-session-cwd SESSION_ID" >&2
          echo "Try 'claude-session-cwd --help' for more information." >&2
          exit 1
          ;;
      esac

      session_id="$1"
      user_home="''${HOME:-${config.home.homeDirectory}}"
      projects_dir="$user_home/.claude/projects"

      # Find the session file
      session_file=$(find "$projects_dir" -name "''${session_id}.jsonl" -type f 2>/dev/null | head -1)

      if [ -z "$session_file" ]; then
        echo "Error: Session not found: $session_id" >&2
        exit 1
      fi

      # Extract metadata
      cwd=$(grep -m1 '"cwd"' "$session_file" | grep -o '"cwd":"[^"]*"' | cut -d'"' -f4)
      git_branch=$(grep -m1 '"gitBranch"' "$session_file" | grep -o '"gitBranch":"[^"]*"' | cut -d'"' -f4)

      if [ -z "$git_branch" ] || [ "$git_branch" = "null" ]; then
        git_branch="N/A"
      fi

      # Display results
      echo "Session ID: $session_id"
      echo "Directory:  $cwd"
      echo "Git Branch: $git_branch"
      echo "File:       $session_file"
    '';
  };

  # create kind cluster
  kindc = {
    runtimeInputs = with pkgs; [ kind ];
    text = ''
      case "''${1:-}" in
        -h|--help)
          cat <<'HELP'
      Create a kind Kubernetes cluster with ingress support

      Usage: kindc

      Creates a local Kubernetes cluster using kind with:
        - Control plane node with ingress support
        - Port mappings: 8080->80, 8443->443
        - Node labels for ingress readiness

      Example:
        kindc    # Create the configured cluster
      HELP
          exit 0
          ;;
      esac

      cat <<EOF | kind create cluster --config=-
      kind: Cluster
      apiVersion: kind.x-k8s.io/v1alpha4
      nodes:
      - role: control-plane
        - |
          kind: InitConfiguration
          nodeRegistration:
            kubeletExtraArgs:
              node-labels: "ingress-ready=true"
        extraPortMappings:
        - containerPort: 80
          hostPort: 8080
          protocol: TCP
        - containerPort: 443
          hostPort: 8443
          protocol: TCP
      EOF
    '';
  };

  # tmux resurrect session restore
  tre = {
    runtimeInputs = with pkgs; [
      tmux
      fzf
      coreutils
    ];
    text = ''
      case "''${1:-}" in
        -h|--help)
          cat <<'HELP'
      Tmux resurrect restore with session selection

      Usage: tre [SESSION_FILE]

      Restores a specific tmux-resurrect session on new server startup.
      If no session file is specified, uses fzf to interactively select one.

      Arguments:
        SESSION_FILE    Path to resurrect session file (optional)

      Workflow:
        1. Select or use specified session file
        2. Update resurrect 'last' symlink
        3. Start new tmux server if needed
        4. Run resurrect restore script
        5. Attach to restored session

      Examples:
        tre                                                # Interactive selection
        tre ~/.tmux/resurrect/tmux_resurrect_20250908.txt  # Restore specific session
      HELP
          exit 0
          ;;
      esac

      resurrect_dir="${config.home.homeDirectory}/.tmux/resurrect"

      if [ ! -d "$resurrect_dir" ]; then
        echo "Error: Resurrect directory not found: $resurrect_dir" >&2
        exit 1
      fi

      # Select session file
      if [ -n "''${1:-}" ]; then
        session_file="$1"
        if [ ! -f "$session_file" ]; then
          echo "Error: Session file not found: $session_file" >&2
          exit 1
        fi
      else
        # Use fzf to select from available sessions (newest first)
        # shellcheck disable=SC2012
        session_file=$(ls -t "$resurrect_dir"/tmux_resurrect_*.txt 2>/dev/null | fzf --prompt='Select resurrect session: ' --height=40%)

        if [ -z "$session_file" ]; then
          echo "No session file selected" >&2
          exit 1
        fi
      fi

      echo "Restoring session: $(basename "$session_file")"

      # Update last symlink to selected session
      ln -sf "$session_file" "$resurrect_dir/last"

      # Start tmux server if not running (without creating a session)
      if ! tmux has-session 2>/dev/null; then
        echo "Starting new tmux server..."
        tmux start-server
      fi

      # Run resurrect restore script (path resolved at build time from Nix package)
      tmux run-shell "${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect/scripts/restore.sh"

      # Small delay to let restore complete
      sleep 1

      # Attach to restored session
      exec tmux attach-session
    '';
  };

  # fetch buildbot-nix build logs from magnetite via ssh
  buildbot-logs = {
    runtimeInputs = with pkgs; [ openssh ];
    text = ''
      case "''${1:-}" in
        -h|--help)
          cat <<'HELP'
      Fetch all step logs for a buildbot-nix build from the magnetite CI host

      Usage: buildbot-logs BUILDER_ID BUILD_ID

      Retrieves every non-hidden step's log (stdio plus any named logs such as
      Evaluation Warnings) from the buildbot-nix master via ssh to magnetite.zt
      on the ZeroTier mesh, and concatenates results to stdout with clear
      step/log section headers. Intended to be redirected to a local file for
      offline search, mirroring the 'gh run download -> unzip -> grep' pattern
      used for GitHub Actions logs:

          buildbot-logs 48 30 > logs/buildbot-48-30.log
          rg "error:" logs/buildbot-48-30.log

      Arguments:
        BUILDER_ID  Numeric builder id (e.g. 48 for the nix-eval builder of
                    cameronraysmith/vanixiets)
        BUILD_ID    Build number within that builder

      Environment:
        BUILDBOT_SSH_HOST         Override ssh target (default: magnetite.zt).
                                  Accepts user@host form, e.g. root@magnetite.zt.
                                  Leave unset to rely on local ~/.ssh/config.
        BUILDBOT_INCLUDE_HIDDEN   Set to 1 to include steps marked hidden in
                                  buildbot (default: skip hidden steps).

      Mapping a PR check row to BUILDER_ID/BUILD_ID:
        gh pr checks <PR> --json name,link \
          | jq -r '.[] | select(.name=="buildbot/nix-build") | .link'
        # URL shape: /#/builders/<BUILDER_ID>/builds/<BUILD_ID>
        # (Both buildbot/nix-build and buildbot/nix-eval share this URL — the
        # parent nix-eval build contains both phases' logs as separate steps.)

      Privacy: captured logs may include build output, worker names, store
      paths, and buildbot-masked token references (e.g. <github-token-N>).
      Review before sharing publicly.
      HELP
          exit 0
          ;;
      esac

      if [ "$#" -lt 2 ]; then
        echo "Error: BUILDER_ID and BUILD_ID required" >&2
        echo "Try 'buildbot-logs --help' for more information." >&2
        exit 2
      fi

      builder="$1"
      build="$2"
      host="''${BUILDBOT_SSH_HOST:-magnetite.zt}"
      include_hidden="''${BUILDBOT_INCLUDE_HIDDEN:-0}"

      case "$builder$build" in
        *[!0-9]*|"")
          echo "Error: BUILDER_ID and BUILD_ID must be positive integers" >&2
          exit 2
          ;;
      esac

      echo "Fetching logs for build $builder/$build from $host..." >&2

      ssh -T "$host" \
        "BUILDER=$builder BUILD=$build INCLUDE_HIDDEN=$include_hidden bash -s" \
      <<'REMOTE_SCRIPT'
      set -euo pipefail

      API=http://127.0.0.1:8010/api/v2
      PW=$(sudo -n bash -c 'cat /run/secrets.d/*/vars/buildbot-http-basic-auth-password/secret' 2>/dev/null) || {
        echo "Error: failed to read buildbot http basic auth password on $(hostname)" >&2
        exit 3
      }

      api() { curl -fsS -u "buildbot:$PW" "$API/$1"; }

      echo "=== BUILD $BUILDER/$BUILD ==="
      api "builders/$BUILDER/builds/$BUILD" | jq '.builds[0]' || {
        echo "Error: build $BUILDER/$BUILD not found or API unreachable" >&2
        exit 4
      }
      echo

      echo "=== STEPS ==="
      steps_json=$(api "builders/$BUILDER/builds/$BUILD/steps")
      echo "$steps_json" | jq -r '.steps[]
        | "\(.number)\t\(.name)\t\(.state_string // "")\tstepid=\(.stepid)\thidden=\(.hidden // false)"'
      echo

      echo "$steps_json" | jq -c '.steps[]' | while read -r step; do
        number=$(echo "$step"  | jq -r '.number')
        name=$(echo "$step"    | jq -r '.name')
        stepid=$(echo "$step"  | jq -r '.stepid')
        hidden=$(echo "$step"  | jq -r '.hidden // false')
        if [ "$hidden" = "true" ] && [ "$INCLUDE_HIDDEN" != "1" ]; then continue; fi
        logs_json=$(api "steps/$stepid/logs" || echo '{"logs":[]}')
        echo "$logs_json" | jq -c '.logs[]?' | while read -r log; do
          logid=$(echo "$log"     | jq -r '.logid')
          logname=$(echo "$log"   | jq -r '.name')
          num_lines=$(echo "$log" | jq -r '.num_lines // 0')
          echo "=== STEP $number: $name / LOG: $logname ($num_lines lines) ==="
          api "logs/$logid/raw" || echo "(log fetch failed)"
          echo
        done
      done
      REMOTE_SCRIPT

      echo "Done." >&2
    '';
  };

  # clean secrets from shell history
  clean-shell-history-secrets = {
    runtimeInputs = with pkgs; [
      atuin
      gitleaks
      jq
    ];
    text = ''
      case "''${1:-}" in
        -h|--help)
          cat <<'HELP'
      Clean secrets from shell history using atuin and gitleaks

      Usage: clean-shell-history-secrets

      Scans all command history via atuin for potential secrets using gitleaks,
      then removes any history entries containing detected secrets.

      Steps:
        1. Export all atuin history (up to 100M entries)
        2. Scan with gitleaks for secret patterns
        3. Delete matching history entries from atuin
        4. Clean up temporary files

      Example:
        clean-shell-history-secrets    # Scan and clean history
      HELP
          exit 0
          ;;
      esac

      # Create temporary file for gitleaks report
      report_file=$(mktemp -t gitleaks-report.XXXXXX)
      trap 'rm -f "$report_file"' EXIT

      echo "Scanning command history for secrets..."

      # Export history and scan with gitleaks
      # Note: gitleaks exits with 1 when secrets are found, which is expected
      set +e
      atuin search --limit 100000000 --filter-mode global | gitleaks detect --pipe -r "$report_file"
      gitleaks_status=$?
      set -e

      # gitleaks exit codes: 0 = no leaks, 1 = leaks found, 2+ = error
      if [ $gitleaks_status -gt 1 ]; then
        echo "Error: gitleaks failed with status $gitleaks_status" >&2
        exit 1
      fi

      # Check if any secrets were found
      if [ ! -s "$report_file" ]; then
        echo "No secrets found in command history"
        exit 0
      fi

      secret_count=$(jq '. | length' "$report_file" 2>/dev/null || echo "0")
      if [ "$secret_count" -eq 0 ]; then
        echo "No secrets found in command history"
        exit 0
      fi

      echo "Found $secret_count secret(s) in command history"
      echo "Deleting entries containing secrets..."

      # Extract unique secrets and delete corresponding history entries
      jq -r '.[].Secret' "$report_file" | sort -u | while IFS= read -r secret; do
        # Show truncated secret for logging without exposing full value
        echo "  Deleting entries containing: ''${secret:0:10}..."
        atuin search --delete "$secret" 2>/dev/null || true
      done

      echo "History cleanup complete"
    '';
  };
}
