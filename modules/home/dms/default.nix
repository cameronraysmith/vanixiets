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
        package = pkgs.dms-shell;
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
          barConfigs = [
            {
              id = "default";
              name = "Main Bar";
              enabled = true;
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
        };
      };

      programs.quickshell.systemd.enable = false;
      systemd.user.services.dms = {
        Unit = {
          Requisite = [ "niri.service" ];
          ConditionEnvironment = "XDG_CURRENT_DESKTOP=niri";
        };
        Service = {
          Type = "dbus";
          BusName = "org.freedesktop.Notifications";
          Environment = [ "DMS_DISABLE_POLKIT=0" ];
        };
      };
    };
}
