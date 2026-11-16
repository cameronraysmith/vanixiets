{ inputs, ... }:
{
  flake.modules.homeManager.dms =
    { pkgs, ... }@args:
    {
      imports = [
        (import "${inputs.dms-src}/distro/nix/home.nix" (args // { dmsPkgs = pkgs; }))
      ];

      programs.dank-material-shell = {
        enable = true;
        package = pkgs.dux-shell;
        quickshell.package = pkgs.quickshell;
        systemd = {
          enable = true;
          target = "niri.service";
        };
        enableSystemMonitoring = false;
        enableVPN = false;
        enableDynamicTheming = false;
        enableAudioWavelength = false;
        enableCalendarEvents = false;

        settings = {
          showClipboard = true;
          # DMS ignores the en_US locale for weather units; this also switches pressure to inHg.
          useFahrenheit = true;
          barConfigs = [
            {
              id = "default";
              name = "Main Bar";
              enabled = true;
              autoHide = true;
              position = 0;
              screenPreferences = [ "all" ];
              showOnLastDisplay = true;
              leftWidgets = [
                "launcherButton"
                "workspaceSwitcher"
                "focusedWindow"
              ];
              centerWidgets = [
                "music"
                "clock"
              ];
              rightWidgets = [
                "systemTray"
                "clipboard"
                "notificationButton"
                "battery"
                "controlCenterButton"
              ];
            }
          ];
          acSuspendTimeout = 0;
          batterySuspendTimeout = 0;
          acLockTimeout = 1800;
          batteryLockTimeout = 1800;
          lockPamPath = "/etc/pam.d/dankshell";
          lockPamExternallyManaged = true;
          loginctlLockIntegration = true;
          lockBeforeSuspend = true;
          # DMS 2.1.2's lockWidgetDefaults() (dux-qml-common SharedSettingsSpec.js) with Power enabled;
          # nix-generated settings skip the lockScreenShowPowerActions migration. Re-check on DMS bumps.
          lockScreenWidgetInstances =
            let
              tint = {
                colorMode = "default";
                customColor = "#ffffff";
              };
              entry = id: widgetType: enabled: config: {
                inherit id widgetType enabled;
                config = {
                  displayPreferences = [ "all" ];
                  syncPositionAcrossScreens = true;
                }
                // config;
              };
            in
            [
              (entry "lock_clock" "desktopClock" true (
                {
                  style = "expressive";
                  transparency = 0;
                  weight = 0;
                  twoTone = true;
                  showDate = false;
                  showDigitalSeconds = false;
                  showAnalogNumbers = false;
                  showAnalogSeconds = true;
                  autoPosition = true;
                }
                // tint
              ))
              (entry "lock_date" "lockDate" false ({ format = "short"; } // tint))
              (entry "lock_auth" "lockAuth" true {
                style = "expressive";
                profileVisibility = "always";
                passwordVisibility = "always";
              })
              (entry "lock_notifications" "lockNotifications" true { mode = 2; })
              (entry "lock_status" "lockStatus" true {
                showMediaPlayer = true;
                showWeather = true;
                background = false;
              })
              (entry "lock_power" "lockPower" true { shape = "round"; })
            ];
        };
      };

      # Qt in the DMS shell takes its icon theme from GTK (QT_QPA_PLATFORMTHEME=gtk3), and home-manager
      # applies gtk.iconTheme only with gtk.enable. catppuccin.gtk.icon (autoEnable) then supplies
      # Papirus-Dark; with no icon theme installed every named launcher icon failed to resolve.
      gtk.enable = true;

      programs.quickshell.systemd.enable = false;
      systemd.user.services.dms = {
        Unit = {
          Requisite = [ "niri.service" ];
          ConditionEnvironment = "XDG_CURRENT_DESKTOP=niri";
        };
        Service.Environment = [ "DMS_DISABLE_POLKIT=0" ];
      };
    };
}
