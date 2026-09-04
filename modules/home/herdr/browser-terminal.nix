{ ... }:
{
  flake.modules.homeManager.herdr =
    { config, pkgs, ... }:
    let
      # xterm.js renders in the browser and resolves fontFamily against the fonts
      # installed on the client machine, so Nerd Font glyphs (private-use
      # codepoints) render only if the client has one of these families. Fonts
      # installed in this profile do not reach the browser.
      fontFamily = "MonaspiceNe Nerd Font Mono, MonaspiceNe NF, Inconsolata Nerd Font Mono, Symbols Nerd Font Mono, Menlo, monospace";
      browser-terminal = pkgs.writeShellApplication {
        name = "browser-terminal";
        runtimeInputs = [
          pkgs.ttyd
          config.programs.herdr.package
        ];
        text = ''
          export COLORTERM=truecolor
          exec ttyd \
            -p "''${BROWSER_TERMINAL_PORT:-7681}" \
            -i "''${BROWSER_TERMINAL_INTERFACE:-127.0.0.1}" \
            -W \
            -t fontSize=14 \
            -t 'theme={"background":"#181818"}' \
            -t 'fontFamily=${fontFamily}' \
            herdr
        '';
      };
    in
    {
      home.packages = [ browser-terminal ];
    };
}
