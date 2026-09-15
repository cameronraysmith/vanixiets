{
  inputs,
  config,
  lib,
  ...
}:
{
  perSystem =
    { system, ... }:
    lib.mkIf (system == "x86_64-linux") {
      checks.pyrite-dankgreeter-config =
        let
          machine = config.flake.nixosConfigurations.pyrite;
          cfg = machine.config;
          pkgs = machine.pkgs;
          greeter = cfg.services.displayManager.dms-greeter;
          configuration = pkgs.writeText "pyrite-dankgreeter.kdl" greeter.compositor.customConfig;
          launcher = cfg.services.greetd.settings.default_session.command;
          assets = "${greeter.package}/share/quickshell/dms";
        in
        pkgs.runCommand "pyrite-dankgreeter-config" { } ''
          ${lib.getExe cfg.programs.niri.package} validate -c ${configuration}
          test -x ${launcher}
          test -f ${assets}/Modules/Greetd/assets/dms-greeter
          test -f ${assets}/shell.qml
          ${pkgs.gnugrep}/bin/grep -F -- '${assets}/Modules/Greetd/assets/dms-greeter' ${launcher}
          ${pkgs.gnugrep}/bin/grep -F -- '${cfg.programs.niri.package}/bin' ${launcher}
          ${pkgs.gnugrep}/bin/grep -F -- '${greeter.quickshell.package}/bin' ${launcher}
          ${pkgs.gnugrep}/bin/grep -F -- ' -C ' ${launcher}
          mkdir -p "$out"
          cp ${configuration} "$out/config.kdl"
          cp ${launcher} "$out/launcher"
        '';
    };
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
      greeter = config.services.displayManager.dms-greeter;
      greetd = config.services.greetd;
      loginPam = config.security.pam.services.login;
      greeterPam = config.security.pam.services.dms-greeter;
      greetdPam = config.security.pam.services.greetd;
      nativeGreeterModule = "${inputs.nixpkgs}/nixos/modules/services/display-managers/dms-greeter.nix";
      enabledRules = rules: lib.filterAttrs (_: rule: rule.enable) rules;
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
            && bar.id == "default"
            && (bar.autoHide or false)
            && !(bar.showOnWindowsOpen or false)
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
          message = "pyrite desktop: native DankGreeter declaration provenance";
          assertion = lib.all (option: map toString option.declarations == [ nativeGreeterModule ]) [
            options.services.displayManager.dms-greeter.enable
            options.services.displayManager.dms-greeter.package
            options.services.displayManager.dms-greeter.compositor.name
          ];
        }
        {
          message = "pyrite desktop: native greeter isolation without autologin";
          assertion =
            greeter.enable
            && greetd.enable
            && !config.services.displayManager.gdm.enable
            && !config.services.desktopManager.gnome.enable
            && config.services.displayManager.sessionData.sessionNames == [ "niri" ]
            && config.services.displayManager.defaultSession == null
            && !config.services.displayManager.autoLogin.enable
            && !(greetd.settings ? initial_session)
            && greetd.settings.default_session.user == "dms-greeter"
            && lib.hasSuffix "/bin/dms-greeter-start" greetd.settings.default_session.command
            && greeter.compositor.name == "niri"
            && toString greeter.package == toString pkgs.dms-shell
            && toString greeter.quickshell.package == toString pkgs.quickshell
            && greeter.configHome == null
            && greeter.configFiles == [ ]
            && config.systemd.services.greetd.preStart == ""
            && (config.systemd.services.greetd.serviceConfig.ExecStartPre or [ ]) == [ ]
            && !greeter.logs.save
            && lib.hasInfix "disable-power-key-handling" greeter.compositor.customConfig
            && lib.hasInfix ''"DMS_RUN_GREETER" "1"'' greeter.compositor.customConfig
            && lib.all (token: !lib.hasInfix token greeter.compositor.customConfig) [
              "include "
              "spawn"
              "binds"
            ]
            && !(config.environment.etc ? "greetd/niri_overrides.kdl")
            && config.users.users.dms-greeter.isSystemUser
            && config.users.users.dms-greeter.home == "/var/lib/dms-greeter"
            && config.users.users.dms-greeter.createHome
            && config.systemd.tmpfiles.settings."10-dms-greeter"."/var/lib/dms-greeter".d.user == "dms-greeter"
            && !(config.systemd.services.greetd.serviceConfig ? User)
            && !(config.home-manager.users ? dms-greeter)
            && config.systemd.services.greetd.aliases == [ "display-manager.service" ]
            && !config.systemd.services.greetd.restartIfChanged;
        }
        {
          message = "pyrite desktop: native greetd and greeter PAM wiring";
          assertion =
            greetd.settings.general.service == "greetd"
            && greetd.settings.default_session.service == "dms-greeter"
            && !greetdPam.useDefaultRules
            &&
              lib.all
                (
                  kind:
                  builtins.attrNames (enabledRules greetdPam.rules.${kind}) == [ "login" ]
                  && greetdPam.rules.${kind}.login.modulePath == "login"
                  &&
                    greetdPam.rules.${kind}.login.control == (
                      if
                        lib.elem kind [
                          "auth"
                          "password"
                        ]
                      then
                        "substack"
                      else
                        "include"
                    )
                )
                [
                  "auth"
                  "account"
                  "password"
                  "session"
                ]
            && greeterPam.useDefaultRules
            && greeterPam.rules.account.unix.enable
            && greeterPam.rules.session.unix.enable
            && greeterPam.startSession
            && greeterPam.rules.session.systemd.enable
            && greeterPam.rules.session.systemd.control == "optional"
            &&
              greeterPam.rules.session.systemd.modulePath
              == "${config.systemd.package}/lib/security/pam_systemd.so"
            && loginPam.useDefaultRules
            && loginPam.unixAuth
            && !loginPam.allowNullPassword
            && lib.all (line: !(lib.hasPrefix "auth " line) || !lib.hasInfix " nullok" line) (
              lib.splitString "\n" loginPam.text
            )
            && !loginPam.rootOK
            && !loginPam.fprintAuth
            && !loginPam.u2f.enable
            && loginPam.rules.auth.unix.enable
            && loginPam.rules.auth.unix.modulePath == "${pkgs.pam}/lib/security/pam_unix.so"
            && loginPam.rules.auth.deny.enable
            && loginPam.rules.auth.deny.control == "required"
            && loginPam.rules.auth.deny.modulePath == "${pkgs.pam}/lib/security/pam_deny.so"
            && loginPam.enableGnomeKeyring
            && loginPam.rules.auth.gnome_keyring.enable
            && loginPam.rules.session.gnome_keyring.enable;
        }
      ];
    };
}
