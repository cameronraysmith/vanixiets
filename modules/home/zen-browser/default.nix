{ inputs, ... }:
{
  flake.modules.homeManager.zen-browser =
    { pkgs, ... }:
    let
      amo = slug: "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi";
      # normal_installed installs once and leaves the add-on removable and its
      # storage untouched, so an existing signed-in Bitwarden keeps its data.
      installed = slug: {
        install_url = amo slug;
        installation_mode = "normal_installed";
      };
      engine = name: template: alias: {
        inherit name;
        urls = [ { inherit template; } ];
        definedAliases = [ alias ];
      };
    in
    {
      imports = [ inputs.zen-browser.homeModules.beta ];

      # font.name.serif.x-western below names this family.
      home.packages = [ pkgs.lmodern ];

      programs.zen-browser = {
        enable = true;

        # Rabby Wallet, active on stibnite, is no longer listed on AMO, so it
        # has no install_url to declare.
        policies.ExtensionSettings = {
          "{446900e4-71c2-419f-a6a7-df9c091e268b}" = installed "bitwarden-password-manager";
          "uBlock0@raymondhill.net" = installed "ublock-origin";
          "addon@darkreader.org" = installed "darkreader";
          "{a4c4eda4-fb84-4a84-b4a1-f7c1cbf2a1ad}" = installed "refined-github-";
          "{aecec67f-0d10-4fa7-b7c7-609a2db280cf}" = installed "violentmonkey";
          "{DDC359D1-844A-42a7-9AA1-88A850A938A8}" = installed "downthemall";
          "d1b33d6a57c463f0daef4abfb625edddd1c2d5d9@mergify.com" = installed "mergify";
          "firefox-production@paperpile.com" = installed "paperpile-addon";
          "jid0-adyhmvsP91nUO8pRv0Mn2VKeB84@jetpack" = installed "raindropio";
          "{b5267224-4e4f-4f5c-bd35-3b1a79bef84a}" = installed "foxy-calculator";
          "{f8793186-e9da-4332-aa1e-dc3d9f7bb04c}" = installed "hackertab-dev";
          "extension@bitly.com" = installed "bitly-shorten";
        };

        # path must name the existing profile directory; any other value makes
        # Zen create and select a new empty profile.
        profiles.default = {
          id = 0;
          isDefault = true;
          name = "Default Profile";
          path = "v390cpau.Default Profile";

          settings = {
            "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
            "browser.urlbar.maxRichResults" = 100;
            "zen.urlbar.behavior" = "float";
            "browser.urlbar.trimURLs" = false;

            "zen.view.compact.enable-at-startup" = true;
            "zen.theme.accent-color" = "#a0d490";
            "zen.view.window.scheme" = 0;
            "browser.theme.toolbar-theme" = 0;
            "layout.css.prefers-color-scheme.content-override" = 0;
            "font.name.serif.x-western" = "Latin Modern Sans";
            "zen.glance.enabled" = false;
            "zen.view.show-newtab-button-top" = false;
            "zen.tabs.show-newtab-vertical" = false;
            "zen.workspaces.continue-where-left-off" = true;
            "zen.workspaces.separate-essentials" = false;
            "zen.pinned-tab-manager.restore-pinned-tabs-to-pinned-url" = true;
            "zen.swipe.is-fast-swipe" = false;
            "browser.tabs.hoverPreview.enabled" = true;
            "browser.tabs.warnOnClose" = true;
            "browser.ctrlTab.sortByRecentlyUsed" = true;
            "browser.link.open_newwindow.override.external" = 7;
            "findbar.highlightAll" = true;
            "media.videocontrols.picture-in-picture.enable-when-switching-tabs.enabled" = true;
            "browser.download.useDownloadDir" = false;
            "browser.aboutConfig.showWarning" = false;
            "devtools.chrome.enabled" = true;
            "devtools.debugger.remote-enabled" = true;

            "network.trr.mode" = 5;
            "doh-rollout.disable-heuristics" = true;
            "signon.rememberSignons" = false;
            "extensions.formautofill.addresses.enabled" = false;
            "extensions.formautofill.creditCards.enabled" = false;
          };

          userChrome = ''
            #urlbar[open][zen-floating-urlbar="true"] {
              top: 1vh !important;
            }

            #urlbar-results {
              max-height: 1000px !important;
            }
          '';

          search = {
            force = true;
            default = "google";
            engines = {
              google.metaData.alias = "g";
              ddg.metaData.alias = "d";
              wikipedia.metaData.alias = "wp";
              ebay.metaData.hidden = true;
              youtube = engine "YouTube" "https://www.youtube.com/results?search_query={searchTerms}" "yt";
              wiktionary =
                engine "wiktionary"
                  "https://en.wiktionary.org/w/index.php?search={searchTerms}&title=Special%3ASearch&ns0=1"
                  "wt";
              github = engine "github" "https://github.com/search?q={searchTerms}" "gh";
              google-maps = engine "google maps" "https://www.google.com/maps/search/{searchTerms}" "gm";
              npm = engine "npm node packages" "https://www.npmjs.com/search?q={searchTerms}" "npm";
              google-scholar = engine "google scholar" "https://scholar.google.com/scholar?&q={searchTerms}" "gs";
              amazon = engine "amazon" "https://www.amazon.com/s?k={searchTerms}" "aa";
            };
          };

          keyboardShortcuts = [
            {
              id = "key_savePage";
              key = "S";
              modifiers.accel = true;
            }
            {
              id = "key_openAddons";
              key = "A";
              modifiers = {
                accel = true;
                shift = true;
              };
            }
            # stibnite binds Cmd+Ctrl; accel+control would collapse to Ctrl on
            # Linux and shadow Copy and Save, so meta keeps the physical Cmd key.
            {
              id = "zen-compact-mode-toggle";
              key = "C";
              modifiers = {
                meta = true;
                control = true;
              };
            }
            # As above: the physical Cmd+Ctrl chord rather than a collapsed Ctrl.
            {
              id = "zen-compact-mode-show-sidebar";
              key = "S";
              modifiers = {
                meta = true;
                control = true;
              };
            }
            {
              id = "zen-workspace-forward";
              key = "E";
              modifiers = {
                accel = true;
                alt = true;
              };
            }
            {
              id = "zen-workspace-backward";
              key = "Q";
              modifiers = {
                accel = true;
                alt = true;
              };
            }
            {
              id = "zen-split-view-unsplit";
              key = "X";
              modifiers = {
                accel = true;
                alt = true;
              };
            }
            {
              id = "zen-toggle-sidebar";
              key = "B";
              modifiers.alt = true;
            }
          ]
          ++ map (n: {
            id = "zen-workspace-switch-${toString n}";
            disabled = true;
          }) (builtins.genList (n: n + 1) 10);
        };
      };
    };
}
