{
  pkgs,
  lib,
  config,
}:
{
  # nnn file manager launcher (without cd-on-quit)
  n-launcher = {
    runtimeInputs = with pkgs; [ nnn ];
    text = ''
      case "''${1:-}" in
        -h|--help)
          cat <<'HELP'
      Launch nnn file manager

      Usage: n-launcher [OPTIONS]

      Starts nnn file manager with preset options:
        -a: auto-setup temporary NNN_FIFO
        -d: detail mode
        -e: open text files in $EDITOR
        -H: show hidden files
        -o: open files only on Enter

      Note: For cd-on-quit functionality, use the 'n' shell function instead.

      Examples:
        n-launcher           # Launch nnn with default settings
        n-launcher /path     # Open nnn at specific path
      HELP
          exit 0
          ;;
      esac

      if [ -n "''${NNNLVL:-}" ] && [ "''${NNNLVL:-0}" -ge 1 ]; then
        echo "nnn is already running"
        exit 0
      fi

      exec nnn -adeHo "$@"
    '';
  };

  # clean up filenames
  cleanfn = {
    runtimeInputs = with pkgs; [ rename ];
    text = ''
      case "''${1:-}" in
        -h|--help)
          cat <<'HELP'
      Clean up filenames by removing special characters

      Usage: cleanfn FILENAME

      Standardizes filenames by:
        - Removing spaces (replaced with hyphens)
        - Removing special characters
        - Converting dots to hyphens (except file extension)
        - Collapsing multiple hyphens

      Arguments:
        FILENAME    File to rename

      Example:
        cleanfn "My Document (2023).v2.pdf"
        # Renames to: My-Document-2023-v2.pdf
      HELP
          exit 0
          ;;
        "")
          echo "Error: Filename required" >&2
          echo "Usage: cleanfn FILENAME" >&2
          echo "Try 'cleanfn --help' for more information." >&2
          exit 1
          ;;
      esac

      rename -bf 's/(\.[^.]+)$//; s/\s+/-/g; s/\./-/g; s/[^a-zA-Z0-9\-]/-/g; s/-{2,}/-/g; s/$/$1/' "$1"
    '';
  };

  # realpath with tilde home expansion
  tildepath = {
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      case "''${1:-}" in
        -h|--help)
          cat <<'HELP'
      Resolve path to absolute form with tilde expansion for home directory

      Usage: tildepath [PATH]

      Converts relative paths to absolute paths (like realpath) but replaces
      the home directory prefix with ~ for cleaner output.

      Arguments:
        PATH    Path to resolve (default: current directory)

      Examples:
        tildepath .                      # ~/projects/nix-workspace
        tildepath ../other-dir           # ~/projects/other-dir
        tildepath /Users/user/projects   # ~/projects
        tildepath /tmp                   # /tmp (unchanged, not under $HOME)
      HELP
          exit 0
          ;;
      esac

      # Use runtime HOME, fallback to build-time home directory
      user_home="''${HOME:-${config.home.homeDirectory}}"

      path="$(realpath "''${1:-$PWD}")"
      if [[ "$path" == "$user_home"/* ]]; then
        echo "~''${path#"$user_home"}"
      elif [[ "$path" == "$user_home" ]]; then
        echo "~"
      else
        echo "$path"
      fi
    '';
  };
}
