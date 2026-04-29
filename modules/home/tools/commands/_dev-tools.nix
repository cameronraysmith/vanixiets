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

}
