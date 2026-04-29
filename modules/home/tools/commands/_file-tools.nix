{
  pkgs,
  lib,
  config,
}:
{
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
