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
