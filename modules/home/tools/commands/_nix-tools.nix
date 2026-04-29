{
  pkgs,
  lib,
  config,
}:
{
  # find all nixpkgs packages that install a given binary
  nix-bin-providers = {
    runtimeInputs = with pkgs; [
      nix-index
      nix
      jq
      gawk
      gnused
    ];
    text = ''
      case "''${1:-}" in
        -h|--help)
          cat <<'HELP'
      Find all nixpkgs packages that install a given binary

      Usage: nix-bin-providers BINARY_NAME

      Searches for packages that would install a binary with the given name
      using two complementary methods:
        1. nix-locate (binary cache, free packages only)
        2. nix eval for meta.mainProgram (includes unfree packages)

      Note: May miss packages that install the binary without setting
      mainProgram (e.g., Python entry points). For complete coverage,
      build a local nix-index with NIXPKGS_ALLOW_UNFREE=1.

      Arguments:
        BINARY_NAME    The name of the binary to search for (e.g., "gt", "python")

      Examples:
        nix-bin-providers gt       # Find packages installing 'gt'
        nix-bin-providers python   # Find packages installing 'python'
      HELP
          exit 0
          ;;
        "")
          echo "Error: BINARY_NAME required" >&2
          echo "Usage: nix-bin-providers BINARY_NAME" >&2
          echo "Try 'nix-bin-providers --help' for more information." >&2
          exit 1
          ;;
      esac

      binary="$1"

      (
        # Method 1: nix-locate (binary cache, typically free packages)
        nix-locate --type x --type s --regex "bin/''${binary}\$" 2>/dev/null \
          | awk '{print $1}' \
          | sed 's/\.out$//'

        # Method 2: nix eval for meta.mainProgram (includes unfree)
        nix eval --impure --json --expr "
          let
            pkgs = import (builtins.getFlake \"nixpkgs\").outPath { config.allowUnfree = true; };
            check = n: (builtins.tryEval (pkgs.\''${n}.meta.mainProgram or null == \"''${binary}\")).value or false;
          in builtins.filter check (builtins.attrNames pkgs)
        " 2>/dev/null | jq -r '.[]'
      ) | sort -u
    '';
  };

}
