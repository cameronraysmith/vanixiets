# Homebrew package management for darwin systems
# Defines custom.homebrew options and base GUI application fleet
{ ... }:
{
  flake.modules = {
    darwin.base =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        cfg = config.custom.homebrew;

        # Core GUI applications managed via homebrew casks
        baseCaskApps = [
          "agentsview"
          "aldente"
          "alt-tab"
          "betterdisplay"
          "block-buzz"
          "calibre"
          "chatgpt"
          "claude"
          "cyberduck"
          "discord"
          "element"
          "factory"
          "fork"
          "ghostty"
          "handy"
          "helium-browser"
          "itsycal"
          "hewigovens/tap/jayjay"
          "linear"
          # This declares which version Homebrew installs; the app's own in-app
          # updater replaces its bundle independently of Homebrew and has no
          # `defaults` key to disable, so that toggle must stay off by hand
          # (a mid-session bundle swap forces a full Gatekeeper re-assessment).
          "logi-options+"
          "logseq"
          "neohtop"
          "obs"
          "obsidian"
          "orbstack"
          "pomatez"
          "podman-desktop"
          "raindropio"
          "raycast"
          "rescuetime"
          "skim"
          "slack"
          "soundsource"
          "spotify"
          "stats"
          "tableplus"
          "visual-studio-code"
          "wezterm@nightly"
          "zed"
          "zen"
          "zoom"
          "zotero"
        ];

        # Mac App Store applications (ID mapping)
        baseMasApps = {
          bitwarden = 1352778147;
          flighty-live-flight-tracker = 1358823008;
          livepdfviewer = 1477861108;
          whatsapp = 310633997;
        };

        # Font packages via homebrew cask
        caskFonts = map (name: "font-${name}") [
          "cascadia-code"
          "cascadia-code-nf"
          "fira-code"
          "fira-code-nerd-font"
          "geist"
          "geist-mono"
          "inter"
          "jetbrains-mono"
          "jetbrains-mono-nerd-font"
          "latin-modern"
          "monaspace"
          "roboto"
          "roboto-mono"
          "ubuntu"
          "ubuntu-mono"
        ];
      in
      {
        options.custom.homebrew = {
          enable = lib.mkEnableOption "homebrew package management";

          additionalBrews = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Additional brew formulas to install";
          };

          additionalCasks = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Additional cask applications to install";
          };

          additionalMasApps = lib.mkOption {
            type = lib.types.attrsOf lib.types.int;
            default = { };
            description = "Additional Mac App Store apps to install";
          };

          manageFonts = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to manage fonts via homebrew casks";
          };
        };

        config = lib.mkIf cfg.enable {
          homebrew = {
            enable = true;

            global = {
              autoUpdate = true;
            };

            onActivation = {
              # brew bundle self-updating in-process races its own long install run;
              # `just activate-darwin` runs `brew update` as a separate step first
              autoUpdate = false;
              upgrade = true;
              # https://nix-darwin.github.io/nix-darwin/manual/#opt-homebrew.onActivation.cleanup
              cleanup = "uninstall";
              # homebrew >=6.0 tap-trust gate reads per-user trust.json which activation's env-scrubbed sudo never sees
              extraEnv.HOMEBREW_NO_REQUIRE_TAP_TRUST = "1";
            };

            # quarantine stays on: `no_quarantine = true` would emit --no-quarantine and
            # suppress Gatekeeper's first-run verification for every cask; the option is
            # also deprecated upstream (Homebrew/brew#20755)
            caskArgs = {
              no_quarantine = false;
            };

            taps = [
              "humanlayer/humanlayer"
              "steipete/tap"
            ];

            brews = [
              "mas"
              "pinentry-mac"
              # https://github.com/tailscale/tailscale/wiki/Tailscaled-on-macOS#installing-tailscaled-from-homebrew
              # "tailscale"
            ]
            ++ cfg.additionalBrews;

            casks = baseCaskApps ++ cfg.additionalCasks ++ (lib.optionals cfg.manageFonts caskFonts);

            masApps = baseMasApps // cfg.additionalMasApps;
          };
        };
      };
  };
}
