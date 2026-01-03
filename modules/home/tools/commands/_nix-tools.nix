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

  # compute sha256 nix hash from URL
  get-nix-hash = {
    runtimeInputs = with pkgs; [ nix ];
    text = ''
      case "''${1:-}" in
        -h|--help)
          cat <<'HELP'
      Compute SHA256 Nix hash of a file from URL

      Usage: get-nix-hash URL

      Downloads a file from the given URL and computes its SHA256 hash
      in SRI format for use in Nix expressions.

      Arguments:
        URL    The URL of the file to hash

      Example:
        get-nix-hash https://example.com/file.tar.gz
      HELP
          exit 0
          ;;
        "")
          echo "Error: URL required" >&2
          echo "Usage: get-nix-hash URL" >&2
          echo "Try 'get-nix-hash --help' for more information." >&2
          exit 1
          ;;
      esac

      url="$1"
      nix_hash=$(nix-prefetch-url "$url")
      nix hash convert --to sri --hash-algo sha256 "$nix_hash"
    '';
  };

  # nix garbage collection for both system and user
  ngc = {
    runtimeInputs = with pkgs; [ nix ];
    text = ''
      case "''${1:-}" in
        -h|--help)
          cat <<'HELP'
      Nix garbage collection for system and user

      Usage: ngc

      Performs garbage collection on Nix store:
        1. System-wide GC (removes profiles older than 7 days)
        2. User GC (removes profiles older than 7 days)
        3. Optimizes Nix store (hardlinks identical files)

      Note: Requires sudo for system-wide collection

      Example:
        ngc    # Run full garbage collection
      HELP
          exit 0
          ;;
      esac

      set -x
      sudo nix-collect-garbage --delete-older-than 7d
      nix-collect-garbage --delete-older-than 7d
      nix store optimise
    '';
  };

  # update nix flake and commit lock file
  flakeup = {
    runtimeInputs = with pkgs; [ nix ];
    text = ''
      case "''${1:-}" in
        -h|--help)
          cat <<'HELP'
      Update Nix flake and commit lock file

      Usage: flakeup [FLAKE_ARGS...]

      Updates flake inputs and automatically commits the lock file.

      Arguments:
        FLAKE_ARGS    Additional arguments for 'nix flake update'

      Examples:
        flakeup                    # Update all inputs
        flakeup --update-input foo # Update specific input
      HELP
          exit 0
          ;;
      esac

      exec nix flake update --commit-lock-file "$@"
    '';
  };

  # quick nix develop wrapper
  dev = {
    runtimeInputs = with pkgs; [ nix ];
    text = ''
      case "''${1:-}" in
        -h|--help)
          cat <<'HELP'
      Enter Nix development shell

      Usage: dev [NIX_ARGS...]

      Shorthand wrapper for 'nix develop'.

      Arguments:
        NIX_ARGS    Arguments to pass to 'nix develop'

      Examples:
        dev                   # Enter default devShell
        dev .#backend         # Enter specific devShell
        dev --command bash    # Run command in devShell
      HELP
          exit 0
          ;;
      esac

      exec nix develop "$@"
    '';
  };
}
