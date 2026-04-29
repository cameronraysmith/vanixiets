{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "get-nix-hash";
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
          meta.description = "Compute SHA256 Nix hash of a file from URL";
        })
      ];
    };
}
