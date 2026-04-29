{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "cleanfn";
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
          meta.description = "Clean up filenames by removing special characters";
        })
      ];
    };
}
