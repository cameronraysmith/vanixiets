{
  inputs,
  config,
  lib,
  ...
}:
let
  # dms-src is pinned by release tag. Only its home-manager module (distro/nix)
  # is imported; the shell itself is nixpkgs' dux-shell. The invariant is that
  # the module and the running shell are the same release: the tag declared in
  # flake.nix (`original.ref`), the release the fetched tree names in
  # quickshell/VERSION, and the packaged dux-shell version must all agree. A
  # nixpkgs bump of dux-shell therefore fails until the tag follows it, and a
  # tag bump fails until nixpkgs ships that release; an untagged master
  # revision fails because its VERSION names the next pre-release, not a
  # shipped one.
  #
  # Input names are resolved through the root node's input map rather than
  # indexed directly, because a lock node's key is not its input name once nix
  # deduplicates: the root's "nixpkgs" is the node "nixpkgs_9" here, and any
  # input can acquire such a suffix as the graph changes.
  lock = builtins.fromJSON (builtins.readFile ../../flake.lock);
  declaredRef = name: lock.nodes.${lock.nodes.root.inputs.${name}}.original.ref or null;
  dmsSrcVersion = lib.trim (builtins.readFile "${inputs.dms-src}/quickshell/VERSION");
in
{
  perSystem =
    { system, ... }:
    lib.mkIf (system == "x86_64-linux") {
      checks.pyrite-zen-desktop =
        let
          machine = config.flake.nixosConfigurations.pyrite;
          pkgs = machine.pkgs;
          zen = inputs.zen-browser.packages.${system}.zen-browser;
        in
        pkgs.runCommand "pyrite-zen-desktop" { } ''
          desktop=${zen}/share/applications/zen.desktop
          ${pkgs.desktop-file-utils}/bin/desktop-file-validate "$desktop"
          ${pkgs.gnugrep}/bin/grep -Fx 'Name=Zen Browser' "$desktop"
          ${pkgs.gnugrep}/bin/grep -Fx 'Exec=zen --name zen %U' "$desktop"
          test -x ${zen}/bin/zen
          mkdir -p "$out"
          cp "$desktop" "$out/zen.desktop"
        '';
      checks.pyrite-dankgreeter-config =
        let
          machine = config.flake.nixosConfigurations.pyrite;
          cfg = machine.config;
          pkgs = machine.pkgs;
          greeter = cfg.services.displayManager.dux-greeter;
          configuration = pkgs.writeText "pyrite-dankgreeter.kdl" greeter.compositor.customConfig;
          launcher = cfg.services.greetd.settings.default_session.command;
          greeterBin = "${greeter.package}/bin/dms-greeter";
        in
        pkgs.runCommand "pyrite-dankgreeter-config" { } ''
          ${lib.getExe cfg.programs.niri.package} validate -c ${configuration}
          test -x ${launcher}
          test -x ${greeterBin}
          ${greeterBin} --help > help.txt
          ${pkgs.gnugrep}/bin/grep -F -- '--cache-dir' help.txt
          ${pkgs.gnugrep}/bin/grep -F -- '--command' help.txt
          ${pkgs.gnugrep}/bin/grep -F -- '-C, --config' help.txt
          ${pkgs.gnugrep}/bin/grep -F -- '${greeterBin} --cache-dir /var/lib/dms-greeter --command niri' ${launcher}
          ${pkgs.gnugrep}/bin/grep -F -- '${cfg.programs.niri.package}/bin' ${launcher}
          ${pkgs.gnugrep}/bin/grep -F -- '${greeter.quickshell.package}/bin' ${launcher}
          ${pkgs.gnugrep}/bin/grep -F -- ' -C ' ${launcher}
          mkdir -p "$out"
          cp ${configuration} "$out/config.kdl"
          cp ${launcher} "$out/launcher"
        '';
      checks.pyrite-bitwarden-unlock =
        let
          machine = config.flake.nixosConfigurations.pyrite;
          cfg = machine.config;
          pkgs = machine.pkgs;
          grep = "${pkgs.gnugrep}/bin/grep";
          # pamu2fcfg enrollment of YubiKey 32720759 on pyrite.
          enrolled = "wbQkIcFPc8ZPBnA+bv6Q1Mrt8JCMg5zNLLqQEKKLtJ0sX8/TQLheF50rdm1jilbDRFW4y+HuKH6AJyAQ9QNNWQ==,XQiB0F5NY5qU5w6Coo2WRDycGgTm7dxPAmBWcvU/IaHfvADIFnPK/9/7lqcF9RlXNfQ0I333IMt+Ax7bxFVZ2A==,es256,+presence";
          authfile = cfg.security.pam.u2f.settings.authfile;
        in
        pkgs.runCommand "pyrite-bitwarden-unlock" { } ''
          policy=${cfg.system.path}/share/polkit-1/actions/com.bitwarden.Bitwarden.policy
          ${grep} -F 'id="com.bitwarden.Bitwarden.unlock"' "$policy"
          ${grep} -E '^cameron:(.*:)?${lib.escapeRegex enrolled}(:|$)' ${authfile}
          mkdir -p "$out"
          cp "$policy" "$out/com.bitwarden.Bitwarden.policy"
          cp ${authfile} "$out/u2f-keys"
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
      greeter = config.services.displayManager.dux-greeter;
      greetd = config.services.greetd;
      loginPam = config.security.pam.services.login;
      greeterPam = config.security.pam.services.dms-greeter;
      greetdPam = config.security.pam.services.greetd;
      nativeGreeterModule = "${inputs.nixpkgs}/nixos/modules/services/display-managers/dux-greeter.nix";
      enabledRules = rules: lib.filterAttrs (_: rule: rule.enable) rules;
      polkitPam = config.security.pam.services.polkit-1;
      u2f = config.security.pam.u2f;
      polkitHelper = config.systemd.services."polkit-agent-helper@".serviceConfig;
      polkitAuthLines = lib.filter (lib.hasPrefix "auth ") (lib.splitString "\n" polkitPam.text);
      polkitAuthIndex = module: lib.lists.findFirstIndex (lib.hasInfix "/${module}") null polkitAuthLines;
      polkitU2fIndex = polkitAuthIndex "pam_u2f.so";
      polkitUnixIndex = polkitAuthIndex "pam_unix.so";
      bitwardenSocket = "${home.home.homeDirectory}/.bitwarden-ssh-agent.sock";
      pinnedKey =
        host:
        let
          block = home.programs.ssh.settings.${host}.data or { };
          file = home.home.file.${lib.removePrefix "~/" (block.IdentityFile or "")} or { };
        in
        if (block.IdentitiesOnly or false) == true then lib.trim (file.text or "") else null;
      loginKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdO9rInDa9HvdtZZxmkgeEdAlTupCy3BgA/sqSGyUH+";
      # The key https://github.com/cameronraysmith.keys lists for authentication.
      githubAuthKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDFGXo7HSSakYB5eEvp22xKmNrMwpI7OTlB3RqP+mGagbggljJP/YBmUCptstAMsZuKeMRXjm6UXUgNeUhECLZQHEDy2+Mrm42OM0svsMqlgZj1ZZdY1yYcquKQO4oyx7CjPOj7NXqSueZmpcwYRJFU7xQO421wb9rNewxCRs8jwRr5beTCUF0MuGLNEJGPMPk++d6Mkd3TYojE524AAoDWgx5z2WavZnewuYYd8PAGrFO4yWQn6LX50qYq2bPo53J/7CT9KwEo4ZaYl6TiSb9x3Oj+iUiTMNBmKBLSMYyj7eV8CU4iIXYqySvEf/mA7EytZnKT37cYo25CMAsobCHZ07htv6bbW+FPb1jehjT96Oo6i0zVGIs/gptw1k9xXSTS0GxfQ1P0XK7+9RZE7bWw/kxepF+OzLcvKKz3SdPEb/SOmqPoq4AFalljM0iwi8DXmH2dhp1Ughh4ImQQxVGrq+U2EwuSZEQHuSXlvfB/MKj2yvcF0BYhPaYfCLovq5LbXXu1QpnL/C9FiY21ehmVFZwHvo+L8y2NxwCaoXYuPGwGc5kH5fNjBh/S7RpypV+oHHGY90lGV6CoQpxXb65rI/ob7cTR2npWUC577fmidYTSmOqU3HhewcZDgxf2iZkVCm7F/Sb2tga3BClr3lV92EBFm9JsayzM9DLuAIz7rQ==";
    in
    {
      assertions = [
        {
          message = "pyrite desktop: one wrapped Zen Browser in cameron's home";
          assertion =
            inputs.zen-browser.inputs.nixpkgs.outPath == inputs.nixpkgs.outPath
            &&
              builtins.length (
                builtins.filter (
                  package:
                  toString package
                  == toString inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.zen-browser
                ) home.home.packages
              ) == 1;
        }
        {
          message = "pyrite desktop: native package identities and configuration pins";
          assertion =
            toString config.programs.niri.package == toString pkgs.niri
            && toString niri.package == toString pkgs.niri
            && toString dms.package == toString pkgs.dux-shell
            && toString dms.quickshell.package == toString pkgs.quickshell
            && toString home.programs.quickshell.package == toString pkgs.quickshell
            && declaredRef "dms-src" == dmsSrcVersion
            && dmsSrcVersion == "v${pkgs.dux-shell.version}"
            && pkgs.dux-greeter.version == "2.1.2"
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
            && unit.Service.ExecStart == [ "${lib.getExe pkgs.dux-shell} run --session" ]
            && unit.Service.Type == "notify"
            && unit.Service.NotifyAccess == "main"
            && (unit.Service.BusName or null) == "org.freedesktop.Notifications"
            && !config.programs.dux-shell.enable
            && !home.programs.quickshell.systemd.enable
            &&
              niri.settings.includes == {
                before = [ ];
                after = [ ];
              }
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
              (lib.getExe pkgs.dux-shell)
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
            && config.hardware.bluetooth.enable
            && config.services.hardware.bolt.enable
            && config.services.udisks2.enable
            && config.services.libinput.enable
            && config.security.rtkit.enable;
        }
        {
          message = "pyrite desktop: polkit unlocks Bitwarden by YubiKey touch";
          assertion =
            lib.elem (toString pkgs.bitwarden-desktop) (map toString config.environment.systemPackages)
            && lib.elem "/share/polkit-1" config.environment.pathsToLink
            && !u2f.enable
            && polkitPam.u2f.enable
            && polkitPam.u2f.control == "sufficient"
            && polkitPam.rules.auth.u2f.enable
            && polkitPam.rules.auth.u2f.control == "sufficient"
            && u2f.settings.origin == "pam://pyrite"
            && u2f.settings.appid == "pam://pyrite"
            && u2f.settings.cue
            && polkitU2fIndex != null
            && polkitUnixIndex != null
            && polkitU2fIndex < polkitUnixIndex
            && (
              let
                line = builtins.elemAt polkitAuthLines polkitU2fIndex;
              in
              lib.hasPrefix "auth sufficient " line
              && lib.all (setting: lib.elem setting (lib.splitString " " line)) [
                "authfile=${u2f.settings.authfile}"
                "origin=pam://pyrite"
                "appid=pam://pyrite"
                "cue"
              ]
            )
            && lib.all (service: !lib.hasInfix "pam_u2f" service.text) [
              pam
              loginPam
            ]
            && (polkitHelper.PrivateDevices or true) == false
            && lib.all (rule: lib.elem rule (lib.toList (polkitHelper.DeviceAllow or [ ]))) [
              "/dev/urandom r"
              "char-hidraw rw"
            ]
            && (polkitHelper.ProtectHome or null) == "read-only";
        }
        {
          message = "pyrite desktop: Bitwarden Desktop is the only SSH agent";
          assertion =
            !config.services.gnome.gcr-ssh-agent.enable
            && !config.programs.ssh.startAgent
            && !home.services.ssh-agent.enable
            && !home.services.gpg-agent.enableSshSupport
            && home.programs.bitwarden-ssh-agent.enable
            && (home.home.sessionVariables.SSH_AUTH_SOCK or null) == bitwardenSocket
            && (home.systemd.user.sessionVariables.SSH_AUTH_SOCK or null) == bitwardenSocket
            && !(config.environment.sessionVariables ? SSH_AUTH_SOCK)
            && !(config.environment.variables ? SSH_AUTH_SOCK)
            && !lib.hasInfix "SSH_AUTH_SOCK" config.environment.extraInit;
        }
        {
          message = "pyrite desktop: fleet hosts pin the login key and GitHub its authentication key";
          assertion = pinnedKey "*.zt" == loginKey && pinnedKey "github.com" == githubAuthKey;
        }
        {
          message = "pyrite desktop: ssh_known_hosts carries GitHub's host key";
          assertion =
            (config.programs.ssh.knownHosts."github.com".publicKey or null) != null
            && lib.any (lib.hasPrefix "github.com ssh-ed25519 ") (
              lib.splitString "\n" (config.environment.etc."ssh/ssh_known_hosts".text or "")
            );
        }
        {
          # Two DHCP clients on one link give it two leases and two default
          # routes. networkd ignores a .network with an empty [Match], so only
          # networks with match settings can claim a link.
          message = "pyrite desktop: networkd configures only links NetworkManager leaves unmanaged";
          assertion =
            !config.networking.networkmanager.enable
            || lib.all (
              network:
              network.matchConfig == { }
              || (
                network.matchConfig ? Name
                && lib.all (name: lib.elem "interface-name:${name}" config.networking.networkmanager.unmanaged) (
                  lib.toList network.matchConfig.Name
                )
              )
            ) (lib.filter (network: network.enable) (lib.attrValues config.systemd.network.networks));
        }
        {
          message = "pyrite desktop: native DankGreeter declaration provenance";
          assertion = lib.all (option: map toString option.declarations == [ nativeGreeterModule ]) [
            options.services.displayManager.dux-greeter.enable
            options.services.displayManager.dux-greeter.package
            options.services.displayManager.dux-greeter.compositor.name
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
            && toString greeter.package == toString pkgs.dux-greeter
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
