{ ... }:
{
  flake.modules.darwin.zed-delta =
    { pkgs, ... }:
    {
      homebrew.casks = [
        {
          name = "zed-delta";
          # The cask links its binary as bin/delta, the name of the git diff
          # pager that git, jj and lazygit call.
          args.no_binaries = true;
        }
      ];

      environment.systemPackages = [
        (pkgs.writeShellApplication {
          name = "zed-delta";
          text = ''
            app=/Applications/Delta.app/Contents/MacOS/delta
            if [ ! -x "$app" ]; then
              echo "zed-delta: Delta.app is not installed in /Applications" >&2
              exit 127
            fi
            exec "$app" "$@"
          '';
        })
      ];
    };
}
