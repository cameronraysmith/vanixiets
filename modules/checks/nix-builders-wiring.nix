# Structural check for the nix-builders clan service across the fleet.
#
# It guards pairings between machines' configurations that no single machine's
# evaluation can catch. A dispatcher generates its `nix-remote-build` keypair
# and every builder authorizes the public half under its build account; a key
# authorized without its forced command, under the wrong account, or next to
# stibnite's interactive session key builds and activates and is wrong in the
# one way that matters — the build key would carry a login, or the separately
# revocable identities would collapse into one.
#
# It also pins what each dispatcher actually schedules (the entries, the ssh
# alias that makes an unreachable builder fail in seconds rather than hang, and
# the identity file each entry names) and that the darwin builders, which are
# laptops, decline work on battery through their forced command.
{
  self,
  lib,
  ...
}:
{
  perSystem =
    { pkgs, system, ... }:
    let
      mkCheck = self.lib.mkStructuralCheck pkgs;

      # Assertions compare text, not store paths: the check must stay buildable
      # on x86_64-linux even though the darwin forced command is a store path
      # nothing on Linux can realise.
      plain = builtins.unsafeDiscardStringContext;
      sortStrings = lib.sort lib.lessThan;

      isDarwin = machine: self.darwinConfigurations ? ${machine};
      configOf =
        machine:
        if isDarwin machine then
          self.darwinConfigurations.${machine}.config
        else
          self.nixosConfigurations.${machine}.config;

      # Build accounts as the fleet expects them, independent of the service's
      # defaults.
      builders = {
        magnetite = "builder";
        pyrite = "builder";
        stibnite = "nixbuild";
        rosegold = "nixbuild";
        argentum = "nixbuild";
      };
      dispatchers = [
        "stibnite"
        "magnetite"
      ];

      remoteBuild = machine: (configOf machine).clan.core.vars.generators.nix-remote-build.files;
      dispatchKey = machine: lib.removeSuffix "\n" (remoteBuild machine)."key.pub".value;
      dispatchKeyPath = machine: plain (remoteBuild machine).key.path;

      authorizedKeys =
        machine: user: map plain (configOf machine).users.users.${user}.openssh.authorizedKeys.keys;

      # ssh client configuration as each class materializes it: nix-darwin as
      # drop-ins under /etc/ssh/ssh_config.d, NixOS through programs.ssh.
      sshClientText =
        machine:
        let
          config = configOf machine;
        in
        if isDarwin machine then
          lib.concatStringsSep "\n" (
            lib.mapAttrsToList (_: file: file.text or "") (
              lib.filterAttrs (name: _: lib.hasPrefix "ssh/ssh_config.d/" name) config.environment.etc
            )
          )
        else
          config.programs.ssh.extraConfig;

      # The keyword/value pairs of the `Host <alias>` block; ssh honours the
      # first value of a repeated keyword, and so does listToAttrs.
      sshBlock =
        machine: alias:
        let
          step =
            acc: line:
            if lib.hasPrefix "Host " line || lib.hasPrefix "Match " line then
              acc // { inBlock = line == "Host ${alias}"; }
            else if acc.inBlock then
              acc // { lines = acc.lines ++ [ line ]; }
            else
              acc;
          collected = builtins.foldl' step {
            inBlock = false;
            lines = [ ];
          } (map lib.trim (lib.splitString "\n" (sshClientText machine)));
          pairs = builtins.filter (pair: pair != null) (
            map (builtins.match "([A-Za-z]+)[[:space:]]+(.*)") collected.lines
          );
        in
        builtins.listToAttrs (
          map (pair: {
            name = builtins.elemAt pair 0;
            value = builtins.elemAt pair 1;
          }) pairs
        );

      projectEntry = entry: {
        inherit (entry)
          hostName
          protocol
          systems
          maxJobs
          speedFactor
          ;
        sshUser = entry.sshUser or null;
        sshKey = if (entry.sshKey or null) == null then null else plain entry.sshKey;
        supportedFeatures = sortStrings entry.supportedFeatures;
        mandatoryFeatures = sortStrings entry.mandatoryFeatures;
      };

      # The fleet entries a dispatcher schedules, read from nix.buildMachines
      # itself so the splice is under test, keyed by alias, with the ssh block
      # each one dispatches through.
      fleetEntries =
        machine:
        builtins.filter (entry: entry.hostName != "rosetta-builder") (configOf machine).nix.buildMachines;
      dispatched =
        machine:
        builtins.listToAttrs (
          map (entry: {
            name = entry.hostName;
            value = {
              entry = projectEntry entry;
              ssh =
                let
                  block = sshBlock machine entry.hostName;
                in
                lib.genAttrs [
                  "HostName"
                  "User"
                  "IdentityFile"
                  "IdentitiesOnly"
                  "HostKeyAlias"
                  "BatchMode"
                  "ConnectTimeout"
                  "ServerAliveInterval"
                  "ServerAliveCountMax"
                ] (keyword: block.${keyword} or null);
            };
          }) (fleetEntries machine)
        );
      # Rosetta entries keep their place; the fleet's follow in any order.
      splice =
        machine:
        let
          names = map (entry: entry.hostName) (configOf machine).nix.buildMachines;
          rosetta = builtins.filter (name: name == "rosetta-builder") names;
        in
        {
          order = rosetta ++ sortStrings (lib.drop (builtins.length rosetta) names);
          fleetEntriesAreTheService =
            map projectEntry (fleetEntries machine)
            == map projectEntry (configOf machine).services.nix-builders.buildMachines;
        };

      expectedDispatch =
        {
          dispatcher,
          hostName,
          builder,
          address,
          systems,
          maxJobs,
          speedFactor,
          supportedFeatures,
        }:
        {
          name = hostName;
          value = {
            entry = {
              inherit
                hostName
                systems
                maxJobs
                speedFactor
                ;
              protocol = "ssh-ng";
              sshUser = builders.${builder};
              sshKey = dispatchKeyPath dispatcher;
              supportedFeatures = sortStrings supportedFeatures;
              mandatoryFeatures = [ ];
            };
            ssh = {
              HostName = address;
              User = builders.${builder};
              IdentityFile = dispatchKeyPath dispatcher;
              IdentitiesOnly = "yes";
              HostKeyAlias = "${builder}.zt";
              BatchMode = "yes";
              ConnectTimeout = "5";
              ServerAliveInterval = "15";
              ServerAliveCountMax = "2";
            };
          };
        };

      # ZeroTier IPv6 addresses, as in modules/system/ssh-known-hosts.nix.
      address = {
        magnetite = "fddb:4344:343b:14b9:399:930f:39db:40d2";
        pyrite = "fddb:4344:343b:14b9:399:937e:8067:8028";
        stibnite = "fddb:4344:343b:14b9:399:9324:19d9:3451";
        rosegold = "fddb:4344:343b:14b9:399:9315:3431:ee8";
        argentum = "fddb:4344:343b:14b9:399:93f7:54d5:ad7e";
      };

      darwinLaptopBuilder = dispatcher: builder: {
        inherit dispatcher builder;
        hostName = "${builder}-builder";
        address = address.${builder};
        systems = [ "aarch64-darwin" ];
        maxJobs = 2;
        speedFactor = 1;
        supportedFeatures = [ "big-parallel" ];
      };

      stibnite = configOf "stibnite";
      magnetite = configOf "magnetite";

      rosettaEntries = builtins.filter (
        entry: entry.hostName == "rosetta-builder"
      ) stibnite.nix.buildMachines;
      stibniteBuilderEntry = lib.findFirst (
        entry: entry.hostName == "stibnite-builder"
      ) null magnetite.nix.buildMachines;

      # The account side of one builder: the forced command and the lines its
      # build account authorizes. A darwin builder's forced command is the
      # AC-power gate, a store script; its text is read from the derivation.
      builderSide =
        machine:
        let
          config = configOf machine;
          user = builders.${machine};
          gate = config.services.nix-builders.acPowerGate;
        in
        {
          forcedCommand = plain config.services.nix-builders.forcedCommand;
          forcedCommandIsGate =
            gate != null && plain config.services.nix-builders.forcedCommand == plain "${gate}";
          gate =
            if gate == null then
              null
            else
              {
                readsPowerSource = lib.hasInfix "/usr/bin/pmset -g batt" gate.text;
                requiresAcPower = lib.hasInfix "AC Power" gate.text;
                declinesOnBattery = lib.hasInfix "exit 1" gate.text;
                execsDaemon = lib.hasInfix "exec ${plain config.nix.package}/bin/nix-daemon --stdio" (
                  plain gate.text
                );
              };
          authorizes = sortStrings (authorizedKeys machine user);
          trusted = builtins.elem user config.nix.settings.trusted-users;
          known = if isDarwin machine then builtins.elem user config.users.knownUsers else null;
        };

      expectedBuilderSide =
        machine:
        let
          config = configOf machine;
          daemon = "${plain config.nix.package}/bin/nix-daemon --stdio";
          forcedCommand =
            if !(isDarwin machine) then
              daemon
            else if config.services.nix-builders.acPowerGate == null then
              "<AC-power gate>"
            else
              plain "${config.services.nix-builders.acPowerGate}";
        in
        {
          inherit forcedCommand;
          forcedCommandIsGate = isDarwin machine;
          gate =
            if isDarwin machine then
              {
                readsPowerSource = true;
                requiresAcPower = true;
                declinesOnBattery = true;
                execsDaemon = true;
              }
            else
              null;
          # Every dispatcher but the builder itself; a dispatcher's exclude
          # narrows what it schedules, not what builders authorize.
          authorizes = sortStrings (
            map (dispatcher: ''restrict,command="${forcedCommand}" ${dispatchKey dispatcher}'') (
              builtins.filter (dispatcher: dispatcher != machine) dispatchers
            )
          );
          trusted = true;
          known = if isDarwin machine then true else null;
        };

      # stibnite's interactive session identity, generated on magnetite.
      sessionKey =
        lib.removeSuffix "\n"
          magnetite.clan.core.vars.generators.stibnite-agent-session.files."key.pub".value;
      sessionUser = stibnite.services.stibnite-session-host.user;
      sessionAuthorized = lib.concatStringsSep "\n" (authorizedKeys "stibnite" sessionUser);
    in
    {
      checks =
        lib.optionalAttrs
          (builtins.elem system [
            "x86_64-linux"
            "aarch64-darwin"
          ])
          {
            nix-builders-wiring = mkCheck {
              name = "nix-builders-wiring";
              actual = {
                stibnite = {
                  rosetta = map projectEntry rosettaEntries;
                  # The rosetta entries come first and everything after them
                  # is the service's list, unaltered.
                  splice = splice "stibnite";
                  dispatch = dispatched "stibnite";
                };
                magnetite = {
                  splice = splice "magnetite";
                  dispatch = dispatched "magnetite";
                  # The remote store and the remote builder name one account
                  # through one alias.
                  storeUriNamesBuildAccount =
                    stibniteBuilderEntry != null
                    &&
                      magnetite.environment.etc."nix/stibnite-store-uri".text
                      == "ssh-ng://${stibniteBuilderEntry.sshUser}@${stibniteBuilderEntry.hostName}?ssh-key=${stibniteBuilderEntry.sshKey}\n";
                };
                builders = lib.genAttrs (builtins.attrNames builders) builderSide;
                # Key separation, asserted in both directions.
                sessionKeyIsNotABuildKey = lib.mapAttrs (
                  machine: user: !(lib.hasInfix sessionKey (lib.concatStringsSep "\n" (authorizedKeys machine user)))
                ) builders;
                buildKeysAreNotSessionKeys = map (
                  dispatcher: !(lib.hasInfix (dispatchKey dispatcher) sessionAuthorized)
                ) dispatchers;
                sessionKeyAuthorizedForSessions = lib.hasInfix sessionKey sessionAuthorized;
              };
              expected = {
                stibnite = {
                  rosetta = [
                    {
                      hostName = "rosetta-builder";
                      protocol = "ssh-ng";
                      systems = [ "aarch64-linux" ];
                      maxJobs = 12;
                      speedFactor = 1;
                      sshUser = null;
                      sshKey = null;
                      supportedFeatures = [
                        "benchmark"
                        "big-parallel"
                        "kvm"
                        "nixos-test"
                        "uid-range"
                      ];
                      mandatoryFeatures = [ ];
                    }
                    {
                      hostName = "rosetta-builder";
                      protocol = "ssh-ng";
                      systems = [ "x86_64-linux" ];
                      maxJobs = 12;
                      speedFactor = 1;
                      sshUser = null;
                      sshKey = null;
                      supportedFeatures = [
                        "benchmark"
                        "big-parallel"
                        "nixos-test"
                        "uid-range"
                      ];
                      mandatoryFeatures = [ ];
                    }
                  ];
                  splice = {
                    order = [
                      "rosetta-builder"
                      "rosetta-builder"
                      "magnetite"
                      "pyrite-builder"
                    ];
                    fleetEntriesAreTheService = true;
                  };
                  # rosegold and argentum are excluded: stibnite builds
                  # aarch64-darwin itself.
                  dispatch = builtins.listToAttrs [
                    (expectedDispatch {
                      dispatcher = "stibnite";
                      builder = "magnetite";
                      hostName = "magnetite";
                      address = address.magnetite;
                      systems = [ "x86_64-linux" ];
                      maxJobs = 8;
                      speedFactor = 2;
                      supportedFeatures = [
                        "big-parallel"
                        "nixos-test"
                        "uid-range"
                        "recursive-nix"
                      ];
                    })
                    (expectedDispatch {
                      dispatcher = "stibnite";
                      builder = "pyrite";
                      hostName = "pyrite-builder";
                      address = address.pyrite;
                      systems = [ "x86_64-linux" ];
                      maxJobs = 1;
                      speedFactor = 1;
                      supportedFeatures = [
                        "kvm"
                        "nixos-test"
                      ];
                    })
                  ];
                };
                magnetite = {
                  splice = {
                    order = [
                      "argentum-builder"
                      "rosegold-builder"
                      "stibnite-builder"
                    ];
                    fleetEntriesAreTheService = true;
                  };
                  # pyrite is excluded: magnetite builds x86_64-linux itself.
                  dispatch = builtins.listToAttrs [
                    (expectedDispatch {
                      dispatcher = "magnetite";
                      builder = "stibnite";
                      hostName = "stibnite-builder";
                      address = address.stibnite;
                      systems = [ "aarch64-darwin" ];
                      maxJobs = 4;
                      speedFactor = 1;
                      supportedFeatures = [
                        "apple-virt"
                        "big-parallel"
                      ];
                    })
                    (expectedDispatch (darwinLaptopBuilder "magnetite" "rosegold"))
                    (expectedDispatch (darwinLaptopBuilder "magnetite" "argentum"))
                  ];
                  storeUriNamesBuildAccount = true;
                };
                builders = lib.genAttrs (builtins.attrNames builders) expectedBuilderSide;
                sessionKeyIsNotABuildKey = lib.mapAttrs (_: _: true) builders;
                buildKeysAreNotSessionKeys = map (_: true) dispatchers;
                sessionKeyAuthorizedForSessions = true;
              };
            };
          };
    };
}
