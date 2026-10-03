# Remote nix builders as one fleet capability.
#
# roles.builder serves the nix build protocol: an account whose only
# authorized keys are the dispatchers' `nix-remote-build` public keys, each
# confined at the SSH boundary by `restrict` and a forced `nix-daemon --stdio`.
# That account is a Nix trusted user, which is store-root-equivalent on the
# builder: an untrusted account cannot receive the unsigned paths a caller
# evaluated itself. The forced command restricts which program the key starts,
# not that program's authority. Every dispatcher of the instance is authorized
# on every builder; `exclude` only decides where a dispatcher sends work.
#
# roles.dispatcher owns the `nix-remote-build` keypair (clan vars, private
# half encrypted for the machine) and, for each builder it does not exclude,
# an ssh Host block plus an entry in the read-only
# `services.nix-builders.buildMachines`. Machines splice that list into their
# own nix.buildMachines; this service never assigns nix.buildMachines, because
# stibnite has to merge it with nix-rosetta-builder's entries under mkForce.
#
# An unreachable builder (a sleeping laptop) is bounded by the ssh block:
# BatchMode keeps the daemon off prompts it cannot answer, ConnectTimeout keeps
# an absent host from absorbing the kernel's SYN retry schedule, and the
# ServerAlive pair tears down a session to a host that suspends mid-transfer.
# nix 2.35 then marks that machine disabled for the rest of the hook's
# lifetime and reconsiders the others, falling back to a local build where the
# caller can build; work only that builder could take fails with `missing
# system features` rather than degrading.
{ config, ... }:
let
  inventoryMachines = config.flake.clan.inventory.machines;
in
{
  clan.modules.nix-builders =
    { lib, clanLib, ... }:
    let
      isDarwin = name: inventoryMachines.${name}.machineClass == "darwin";

      builderUser =
        name: settings:
        if settings.user != null then
          settings.user
        else if isDarwin name then
          "nixbuild"
        else
          "builder";

      builderHostAlias =
        name: settings: if settings.hostAlias != null then settings.hostAlias else "${name}-builder";

      builderHostKeyAlias =
        name: settings: if settings.hostKeyAlias != null then settings.hostKeyAlias else "${name}.zt";

      # readOnly counts a default as a definition, so these options have none:
      # the role that computes a value defines it once, and perMachine supplies
      # the empty value on machines without that role.
      outputModule = machineRoles: {
        options.services.nix-builders = {
          buildMachines = lib.mkOption {
            type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
            readOnly = true;
            description = ''
              nix.buildMachines entries for every builder this machine
              dispatches to; [] on non-dispatchers. Machines splice this into
              their own nix.buildMachines; the service never sets that option.
            '';
          };
          forcedCommand = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            readOnly = true;
            description = "The program forced on every dispatcher key of this builder; null on non-builders.";
          };
          acPowerGate = lib.mkOption {
            type = lib.types.nullOr lib.types.package;
            readOnly = true;
            description = "The AC-power gate script forced on dispatcher keys, or null when the builder accepts work on battery.";
          };
        };
        config.services.nix-builders =
          lib.optionalAttrs (!lib.elem "dispatcher" machineRoles) { buildMachines = [ ]; }
          // lib.optionalAttrs (!lib.elem "builder" machineRoles) {
            forcedCommand = null;
            acPowerGate = null;
          };
      };

      # Shared by both classes; the account itself differs per class.
      mkBuilderModule =
        {
          roles,
          settings,
          machine,
        }:
        { config, pkgs, ... }:
        let
          user = builderUser machine.name settings;
          daemon = "${config.nix.package}/bin/nix-daemon --stdio";
          # stdout carries the nix protocol, so the refusal goes to stderr,
          # which ssh relays to the dispatcher's build log.
          acPowerGate =
            if settings.acceptOnBattery then
              null
            else
              pkgs.writeShellScript "nix-builders-ac-power-gate" ''
                case "$(/usr/bin/pmset -g batt)" in
                  *"AC Power"*) ;;
                  *)
                    echo "on battery; declining remote builds" >&2
                    exit 1
                    ;;
                esac
                exec ${daemon}
              '';
          forcedCommand = if acPowerGate == null then daemon else "${acPowerGate}";
          dispatcherKeys = map (
            dispatcher:
            lib.removeSuffix "\n" (
              clanLib.getPublicValue {
                flake = config.clan.core.settings.directory;
                machine = dispatcher;
                generator = "nix-remote-build";
                file = "key.pub";
              }
            )
          ) (lib.filter (d: d != machine.name) (lib.attrNames roles.dispatcher.machines));
        in
        {
          services.nix-builders = { inherit forcedCommand acPowerGate; };

          # sshd runs a forced command through the account's login shell, so
          # the shell must stay executable; a nologin shell would break the
          # protocol rather than harden it. `ssh://`, which would run
          # `nix-store --serve`, is deliberately not served.
          users.users.${user}.openssh.authorizedKeys.keys = map (
            key: ''restrict,command="${forcedCommand}" ${key}''
          ) dispatcherKeys;

          nix.settings.trusted-users = [ user ];
        };

      builderInterface = {
        options = {
          systems = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = "Systems this builder builds for.";
          };
          supportedFeatures = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "System features advertised to the scheduler; only claims the host can honour.";
          };
          mandatoryFeatures = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Features a derivation must require to be dispatched here.";
          };
          maxJobs = lib.mkOption {
            type = lib.types.ints.positive;
            default = 1;
            description = "Concurrent jobs a dispatcher sends to this builder.";
          };
          speedFactor = lib.mkOption {
            type = lib.types.ints.positive;
            default = 1;
            description = "Scheduler weight, compared among builders of the same system.";
          };
          address = lib.mkOption {
            type = lib.types.str;
            description = "Deterministic ZeroTier IPv6, matching modules/system/ssh-known-hosts.nix.";
          };
          hostAlias = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "ssh Host alias dispatchers resolve; null means `<machine>-builder`, distinct from interactive aliases.";
          };
          hostKeyAlias = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "known_hosts name the host key is pinned under; null means `<machine>.zt`.";
          };
          user = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Build account; null means `builder` on NixOS and `nixbuild` on darwin.";
          };
          uid = lib.mkOption {
            type = lib.types.nullOr lib.types.int;
            default = null;
            description = "UID of the build account; required on darwin, where accounts are created with a fixed uid.";
          };
          authorizeSshAccessGroup = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              darwin: add the build account to macOS's `com.apple.access_ssh`
              service ACL at activation. That ACL nests only the admin group
              and the build account is not an admin, so without it every
              dispatch fails as `Permission denied (publickey)`. Set false to
              manage the ACL by hand.
            '';
          };
          acceptOnBattery = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              darwin: false forces a gate in front of nix-daemon that refuses
              the connection unless `pmset -g batt` reports AC Power, so a
              laptop on battery declines remote work and dispatchers fall
              back to their other builders.
            '';
          };
          daemonProcessType = lib.mkOption {
            type = lib.types.nullOr (
              lib.types.enum [
                "Background"
                "Standard"
                "Adaptive"
                "Interactive"
              ]
            );
            default = null;
            description = "darwin: nix.daemonProcessType when non-null. Host-wide: it also governs the owner's local builds.";
          };
          daemonIOLowPriority = lib.mkOption {
            type = lib.types.nullOr lib.types.bool;
            default = null;
            description = "darwin: nix.daemonIOLowPriority when non-null. Host-wide.";
          };
        };
      };

      dispatcherInterface = {
        options = {
          connectTimeout = lib.mkOption {
            type = lib.types.ints.positive;
            default = 5;
            description = "ssh ConnectTimeout in seconds for every builder.";
          };
          serverAliveInterval = lib.mkOption {
            type = lib.types.ints.positive;
            default = 15;
            description = "ssh ServerAliveInterval in seconds.";
          };
          serverAliveCountMax = lib.mkOption {
            type = lib.types.ints.positive;
            default = 2;
            description = "ssh ServerAliveCountMax.";
          };
          buildersUseSubstitutes = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Let builders substitute dependencies from their caches instead of receiving them from this machine.";
          };
          exclude = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Builders this machine does not dispatch to.";
          };
        };
      };

      mkDispatcher =
        class:
        {
          roles,
          settings,
          machine,
        }:
        { config, pkgs, ... }:
        let
          sshKey = config.clan.core.vars.generators.nix-remote-build.files.key.path;
          builders = lib.filterAttrs (
            name: _: name != machine.name && !(lib.elem name settings.exclude)
          ) roles.builder.machines;
          resolved = lib.mapAttrs (name: builder: {
            inherit (builder) settings;
            user = builderUser name builder.settings;
            hostAlias = builderHostAlias name builder.settings;
            hostKeyAlias = builderHostKeyAlias name builder.settings;
          }) builders;
          sshBlock = b: ''
            Host ${b.hostAlias}
              HostName ${b.settings.address}
              User ${b.user}
              IdentityFile ${sshKey}
              IdentitiesOnly yes
              HostKeyAlias ${b.hostKeyAlias}
              BatchMode yes
              ConnectTimeout ${toString settings.connectTimeout}
              ServerAliveInterval ${toString settings.serverAliveInterval}
              ServerAliveCountMax ${toString settings.serverAliveCountMax}
          '';
        in
        {
          # Generated rather than operator-populated: no plaintext private half
          # leaves the machine. Builders read the public value at evaluation
          # time through clanLib.getPublicValue.
          clan.core.vars.generators.nix-remote-build = {
            files.key = { };
            files."key.pub".secret = false;
            runtimeInputs = [ pkgs.openssh ];
            script = ''
              ssh-keygen -t ed25519 -N "" -C "nix-remote-build" -f "$out"/key
            '';
          };

          services.nix-builders.buildMachines = lib.mapAttrsToList (_: b: {
            hostName = b.hostAlias;
            protocol = "ssh-ng";
            sshUser = b.user;
            inherit sshKey;
            inherit (b.settings)
              systems
              maxJobs
              speedFactor
              supportedFeatures
              mandatoryFeatures
              ;
          }) resolved;

          nix.distributedBuilds = true;
          nix.settings.builders-use-substitutes = lib.mkIf settings.buildersUseSubstitutes true;

          # darwin keeps one ssh_config.d file per builder; NixOS has a single
          # ssh_config assembled from programs.ssh.extraConfig.
          programs.ssh.extraConfig = lib.mkIf (class == "nixos") (
            lib.concatStrings (lib.mapAttrsToList (_: sshBlock) resolved)
          );

          environment.etc =
            lib.optionalAttrs (class == "darwin") (
              lib.mapAttrs' (
                name: b: lib.nameValuePair "ssh/ssh_config.d/120-${name}.conf" { text = sshBlock b; }
              ) resolved
            )
            # The other way to reach a builder's store: `nix build --store
            # "$(cat /etc/nix/<builder>-store-uri)"` builds entirely there with
            # nothing copied back. The key is root-owned, so a non-root caller
            # needs `sudo -E`.
            // lib.mapAttrs' (
              name: b:
              lib.nameValuePair "nix/${name}-store-uri" {
                text = "ssh-ng://${b.user}@${b.hostAlias}?ssh-key=${sshKey}\n";
              }
            ) resolved;
        };
    in
    {
      _class = "clan.service";
      manifest = {
        name = "nix-builders";
        description = "Remote nix builders and the machines that dispatch to them";
        categories = [ "System" ];
        readme = ''
          Remote nix build capability across the fleet. `builder` machines
          serve the nix build protocol to every dispatcher of the instance
          under a forced, restricted `nix-daemon --stdio`; `dispatcher`
          machines own the `nix-remote-build` key and expose
          `services.nix-builders.buildMachines` for their nix.buildMachines.
        '';
      };

      perMachine =
        { machine, ... }:
        {
          nixosModule = outputModule machine.roles;
          darwinModule = outputModule machine.roles;
        };

      roles.builder = {
        description = "Serves remote builds to the instance's dispatchers";
        interface = builderInterface;
        perInstance =
          {
            roles,
            settings,
            machine,
            ...
          }:
          let
            user = builderUser machine.name settings;
          in
          {
            nixosModule = {
              imports = [ (mkBuilderModule { inherit roles settings machine; }) ];
              assertions = [
                {
                  assertion = settings.acceptOnBattery;
                  message = "nix-builders: acceptOnBattery = false relies on macOS pmset and is darwin-only (${machine.name}).";
                }
              ];
              users.users.${user} = {
                isNormalUser = true;
                description = "Remote nix build account";
                uid = lib.mkIf (settings.uid != null) settings.uid;
              };
            };

            darwinModule = {
              imports = [ (mkBuilderModule { inherit roles settings machine; }) ];
              assertions = [
                {
                  assertion = settings.uid != null;
                  message = "nix-builders: darwin builder ${machine.name} needs settings.uid.";
                }
              ];
              users.users.${user} = {
                uid = settings.uid;
                description = "Remote nix build account";
                # nix-darwin's default for shell = null is /usr/bin/false,
                # which would break the forced command rather than harden it.
                shell = "/bin/sh";
              };
              users.knownUsers = [ user ];

              nix.daemonProcessType = lib.mkIf (settings.daemonProcessType != null) settings.daemonProcessType;
              nix.daemonIOLowPriority = lib.mkIf (
                settings.daemonIOLowPriority != null
              ) settings.daemonIOLowPriority;

              system.activationScripts.postActivation.text = lib.mkIf settings.authorizeSshAccessGroup ''
                if ! /usr/sbin/dseditgroup -o checkmember -m ${user} com.apple.access_ssh >/dev/null 2>&1; then
                  echo "Adding ${user} to the com.apple.access_ssh service ACL..."
                  /usr/sbin/dseditgroup -o edit -a ${user} -t user com.apple.access_ssh
                fi
              '';
            };
          };
      };

      roles.dispatcher = {
        description = "Dispatches builds to the instance's builders";
        interface = dispatcherInterface;
        perInstance =
          {
            roles,
            settings,
            machine,
            ...
          }:
          {
            nixosModule = mkDispatcher "nixos" { inherit roles settings machine; };
            darwinModule = mkDispatcher "darwin" { inherit roles settings machine; };
          };
      };
    };
}
