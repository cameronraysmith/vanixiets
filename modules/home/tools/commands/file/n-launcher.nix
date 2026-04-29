{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "n-launcher";
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
          meta.description = "Launch nnn file manager with preset options";
        })
      ];
    };
}
