# macOS dock settings
{ ... }:
{
  flake.modules.darwin.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      system.defaults.dock = {
        appswitcher-all-displays = true;
        autohide = true;
        autohide-delay = 0.0;
        autohide-time-modifier = 0.15;
        dashboard-in-overlay = false;
        enable-spring-load-actions-on-all-items = false;
        expose-animation-duration = 0.1;
        expose-group-apps = true;
        launchanim = true;
        mineffect = "scale";
        minimize-to-application = false;
        mouse-over-hilite-stack = true;
        mru-spaces = false;
        orientation = "bottom";
        show-process-indicators = true;
        show-recents = true;
        showhidden = true;
        static-only = false;
        tilesize = 48;
        # Hot corners (1 = disabled)
        wvous-bl-corner = 1;
        wvous-br-corner = 5;
        wvous-tl-corner = 1;
        wvous-tr-corner = 1;
        # TODO: add persistent-apps config to module to allow per-machine customization
        persistent-apps = [
          "/Applications/NeoHtop.app"
          "/Applications/Ghostty.app"
          "/Applications/Fork.app"
          "/Applications/Zed.app"
          "/Applications/Helium.app"
          "/Applications/Visual Studio Code.app"
          "/Applications/Zen.app"
          "/Applications/Raindrop.io.app"
          "/Applications/Skim.app"
          # "/Applications/Preview.app"
          "/Applications/calibre.app"
          "/Applications/Zotero.app"
          "/Applications/Cyberduck.app"
          "/Applications/TablePlus.app"
          "/Applications/DBeaver.app"
          "/Applications/Codelayer-Nightly.app"
          "/Applications/opcode.app"
          "/Applications/Claude.app"
          "/Applications/Logseq.app"
          "/Applications/Bitwarden.app"
          "/Applications/OrbStack.app"
          "/Applications/OBS.app"
          "/Applications/Discord.app"
          "/Applications/zoom.us.app"
          "/Applications/WhatsApp.app"
          "/Applications/Slack.app"
          # "/Applications/Utilities/Audio MIDI Setup.app"
          "/System/Applications/System Settings.app"
        ];
      };
    };
}
