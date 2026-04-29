{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "gitjsonl";
          runtimeInputs = with pkgs; [
            git
            jc
            nushell
          ];
          text = ''
            case "''${1:-}" in
              -h|--help)
                cat <<'HELP'
            Display git log lines as JSON

            Usage: gitjsonl [LINES]

            Shows specified number of git log entries as JSON in transposed format.

            Arguments:
              LINES    Number of log entries to show (default: 1)

            Examples:
              gitjsonl      # Show latest commit as JSON
              gitjsonl 5    # Show latest 5 commits as JSON
            HELP
                exit 0
                ;;
            esac

            lines="''${1:-1}"
            exec nu -c "git log | jc --git-log | from json | take $lines | transpose"
          '';
          meta.description = "Display git log lines as JSON";
        })
      ];
    };
}
