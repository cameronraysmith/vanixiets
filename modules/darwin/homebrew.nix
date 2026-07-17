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
          "calibre"
          "chatgpt"
          "claude"
          "cyberduck"
          "discord"
          "element"
          "factory"
          "fork"
          "ghostty"
          "helium-browser"
          "itsycal"
          "hewigovens/tap/jayjay"
          "linear"
          "logi-options+"
          "logseq"
          "neohtop"
          "obs"
          "obsidian"
          "orbstack"
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
              autoUpdate = true;
              upgrade = true;
              # https://nix-darwin.github.io/nix-darwin/manual/#opt-homebrew.onActivation.cleanup
              cleanup = "uninstall";
              # homebrew >=5.1.15 requires --force-cleanup for brew bundle --cleanup (nix-darwin#1787)
              extraFlags = [ "--force-cleanup" ];
              # homebrew >=6.0 tap-trust gate reads per-user trust.json which activation's env-scrubbed sudo never sees
              extraEnv.HOMEBREW_NO_REQUIRE_TAP_TRUST = "1";
            };

            # apply --no-quarantine to all casks
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
