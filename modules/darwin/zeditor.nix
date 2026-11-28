{ ... }:
{
  flake.modules.darwin.zeditor =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        (pkgs.writeShellApplication {
          name = "zeditor";
          text = ''
            app=/Applications/Zed.app/Contents/MacOS/cli
            if [ ! -x "$app" ]; then
              echo "zeditor: Zed.app is not installed in /Applications" >&2
              exit 127
            fi
            exec "$app" "$@"
          '';
        })
      ];
    };
}
