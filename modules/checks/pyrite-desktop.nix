{ inputs, ... }:
{
  flake.modules.nixos."machines/nixos/pyrite" =
    {
      config,
      options,
      lib,
      pkgs,
      ...
    }:
    let
      home = config.home-manager.users.cameron;
      dms = home.programs.dank-material-shell;
      settings = dms.settings;
      unit = home.systemd.user.services.dms;
      niri = home.programs.niri;
      pam = config.security.pam.services.dankshell;
      login = config.services.logind.settings.Login;
      expectedIpc = {
        "Mod+Space" = [
          "spotlight"
          "toggle"
        ];
        "Mod+N" = [
          "notifications"
          "toggle"
        ];
        "Mod+Comma" = [
          "settings"
          "toggle"
        ];
        "Super+Alt+L" = [
          "lock"
          "lock"
        ];
        "Mod+V" = [
          "clipboard"
          "toggle"
        ];
        "Mod+X" = [
          "powermenu"
          "toggle"
        ];
        "XF86AudioRaiseVolume" = [
          "audio"
          "increment"
          "3"
        ];
        "XF86AudioLowerVolume" = [
          "audio"
          "decrement"
          "3"
        ];
        "XF86AudioMute" = [
          "audio"
          "mute"
        ];
        "XF86AudioMicMute" = [
          "audio"
          "micmute"
        ];
        "XF86MonBrightnessUp" = [
          "brightness"
          "increment"
          "5"
          ""
        ];
        "XF86MonBrightnessDown" = [
          "brightness"
          "decrement"
          "5"
          ""
        ];
        "XF86KbdBrightnessUp" = [
          "brightness"
          "increment"
          "5"
          "leds:spi::kbd_backlight"
        ];
        "XF86KbdBrightnessDown" = [
          "brightness"
          "decrement"
          "5"
          "leds:spi::kbd_backlight"
        ];
        "XF86AudioPlay" = [
          "mpris"
          "playPause"
        ];
        "XF86AudioNext" = [
          "mpris"
          "next"
        ];
        "XF86AudioPrev" = [
          "mpris"
          "previous"
        ];
      };
      competingUnits = [
        "quickshell"
        "dms-shell"
        "waybar"
        "mako"
        "dunst"
        "swaync"
        "swayidle"
        "hypridle"
        "swaylock"
        "hyprlock"
        "xss-lock"
        "cliphist"
        "wl-paste"
        "network-manager-applet"
        "nm-applet"
        "polkit-gnome-authentication-agent-1"
        "niri-flake-polkit"
      ];
      bar = builtins.head settings.barConfigs;
      widgets = bar.leftWidgets ++ bar.centerWidgets ++ bar.rightWidgets;
      gnomeSettings = (builtins.head config.programs.dconf.profiles.user.databases).settings;
      power = gnomeSettings."org/gnome/settings-daemon/plugins/power";
    in
    {
      assertions = [
        {
          message = "pyrite desktop: native package identities and configuration pins";
          assertion =
            toString config.programs.niri.package == toString pkgs.niri
            && toString niri.package == toString pkgs.niri
            && toString dms.package == toString pkgs.dms-shell
            && toString dms.quickshell.package == toString pkgs.quickshell
            && toString home.programs.quickshell.package == toString pkgs.quickshell
            && pkgs.dms-shell.version == "1.5.3"
            && inputs.niri-flake.rev == "db2615fc6b3f75539ec681a984e3311b8d79ede0"
            && inputs.dms-src.rev == "069ddab041c738236a8910e4c39b65d9628d3018"
            &&
              map toString options.programs.niri.enable.declarations == [
                "${inputs.nixpkgs}/nixos/modules/programs/wayland/niri.nix"
              ];
        }
        {
          message = "pyrite desktop: one niri-scoped DMS owner";
          assertion =
            dms.enable
            && dms.systemd.enable
            && unit.Unit.PartOf == [ "niri.service" ]
            && unit.Unit.After == [ "niri.service" ]
            && unit.Unit.Requisite == [ "niri.service" ]
            && unit.Install.WantedBy == [ "niri.service" ]
            && unit.Unit.ConditionEnvironment == "XDG_CURRENT_DESKTOP=niri"
            && unit.Service.ExecStart == [ "${lib.getExe pkgs.dms-shell} run --session" ]
            && unit.Service.Type == "dbus"
            && unit.Service.BusName == "org.freedesktop.Notifications"
            && !config.programs.dms-shell.enable
            && !home.programs.quickshell.systemd.enable
            && niri.settings.includes == [ ]
            && niri.settings.spawn-at-startup == [ ]
            && lib.all (name: !(builtins.hasAttr name home.systemd.user.services)) competingUnits
            && lib.all (name: !(config.systemd.user.services.${name}.enable or false)) competingUnits
            && !home.services.network-manager-applet.enable;
        }
        {
          message = "pyrite desktop: DMS exposes the required shell controls";
          assertion =
            builtins.length settings.barConfigs == 1
            && bar.enabled
            &&
              widgets == [
                "launcherButton"
                "workspaceSwitcher"
                "focusedWindow"
                "music"
                "clock"
                "systemTray"
                "clipboard"
                "notificationButton"
                "battery"
                "controlCenterButton"
              ]
            && settings.showClipboard
            && !dms.enableSystemMonitoring
            && !dms.enableVPN
            && !dms.enableDynamicTheming
            && !dms.enableAudioWavelength
            && !dms.enableCalendarEvents
            && dms.plugins == { };
        }
        {
          message = "pyrite desktop: typed DMS keybindings";
          assertion = lib.all (
            key:
            niri.settings.binds.${key}.action.spawn == [
              (lib.getExe pkgs.dms-shell)
              "ipc"
              "call"
            ]
            ++ expectedIpc.${key}
            && niri.settings.binds.${key}.allow-when-locked == lib.hasPrefix "XF86" key
          ) (builtins.attrNames expectedIpc);
        }
        {
          message = "pyrite desktop: native password lock and logind integration";
          assertion =
            settings.lockPamPath == "/etc/pam.d/dankshell"
            && settings.lockPamExternallyManaged
            && settings.loginctlLockIntegration
            && settings.lockBeforeSuspend
            && settings.acLockTimeout == 1800
            && settings.batteryLockTimeout == 1800
            && settings.acSuspendTimeout == 0
            && settings.batterySuspendTimeout == 0
            && pam.useDefaultRules
            && pam.unixAuth
            && !pam.allowNullPassword
            && !pam.rootOK
            && !pam.fprintAuth
            && !pam.u2f.enable
            && pam.rules.auth.unix.enable
            && pam.rules.auth.unix.modulePath == "${pkgs.pam}/lib/security/pam_unix.so"
            && pam.rules.auth.deny.enable
            && pam.rules.auth.deny.control == "required"
            && pam.rules.auth.deny.modulePath == "${pkgs.pam}/lib/security/pam_deny.so";
        }
        {
          message = "pyrite desktop: lid power-key and manual-suspend policy";
          assertion =
            login.IdleAction == "ignore"
            && login.HandlePowerKey == "ignore"
            && login.HandleLidSwitch == "lock"
            && login.HandleLidSwitchExternalPower == "lock"
            && login.HandleLidSwitchDocked == "ignore"
            && !niri.settings.input.power-key-handling.enable
            && !(builtins.hasAttr "XF86PowerOff" niri.settings.binds)
            && config.systemd.sleep.settings.Sleep == { }
            && lib.all (name: config.systemd.targets.${name}.enable or true) [
              "sleep"
              "suspend"
            ];
        }
        {
          message = "pyrite desktop: native portals and polkit";
          assertion =
            config.xdg.portal.enable
            && config.programs.niri.useNautilus
            &&
              config.xdg.portal.config.niri == {
                default = "gnome;gtk";
                "org.freedesktop.impl.portal.Access" = "gtk";
                "org.freedesktop.impl.portal.Notification" = "gtk";
                "org.freedesktop.impl.portal.Secret" = "gnome-keyring";
              }
            && lib.all (package: lib.elem (toString package) (map toString config.xdg.portal.extraPortals)) [
              pkgs.xdg-desktop-portal-gnome
              pkgs.xdg-desktop-portal-gtk
            ]
            && lib.elem (toString pkgs.nautilus) (map toString config.services.dbus.packages)
            && !home.xdg.portal.enable
            && config.security.polkit.enable
            && lib.elem "DMS_DISABLE_POLKIT=0" unit.Service.Environment;
        }
        {
          message = "pyrite desktop: existing supporting services are preserved";
          assertion =
            config.networking.networkmanager.enable
            && config.services.pipewire.enable
            && config.services.accounts-daemon.enable
            && config.services.upower.enable
            && config.services.power-profiles-daemon.enable
            && !config.services.tlp.enable
            && config.services.gnome.gnome-keyring.enable
            && config.services.gnome.gcr-ssh-agent.enable
            && config.hardware.bluetooth.enable
            && config.services.hardware.bolt.enable
            && config.services.udisks2.enable
            && config.services.libinput.enable
            && config.security.rtkit.enable;
        }
        {
          message = "pyrite desktop: GNOME and GDM selection and inactivity are preserved";
          assertion =
            config.services.displayManager.gdm.enable
            && config.services.desktopManager.gnome.enable
            && !config.services.displayManager.gdm.autoSuspend
            && config.services.displayManager.defaultSession == null
            &&
              config.services.displayManager.sessionData.sessionNames == [
                "gnome"
                "niri"
              ]
            && !config.services.displayManager.autoLogin.enable
            && !config.services.greetd.enable
            && !config.services.displayManager.dms-greeter.enable
            && toString power.sleep-inactive-ac-timeout == "0"
            && toString power.sleep-inactive-battery-timeout == "0"
            && power.sleep-inactive-ac-type == "nothing"
            && power.sleep-inactive-battery-type == "nothing"
            && power.power-button-action == "nothing"
            && toString gnomeSettings."org/gnome/desktop/session".idle-delay == "@u 1800";
        }
      ];
    };
}
