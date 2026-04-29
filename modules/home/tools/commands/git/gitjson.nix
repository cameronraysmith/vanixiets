{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "gitjson";
          runtimeInputs = with pkgs; [
            git
            jc
            nushell
          ];
          text = ''
            case "''${1:-}" in
              -h|--help)
                cat <<'HELP'
            Display git log as JSON

            Usage: gitjson

            Converts git log output to JSON format using jc and displays
            it with nushell for better formatting.

            Example:
              gitjson    # Show entire git log as JSON
            HELP
                exit 0
                ;;
            esac

            exec nu -c "git log | jc --git-log | from json"
          '';
          meta.description = "Display git log as JSON";
        })
      ];
    };
}
