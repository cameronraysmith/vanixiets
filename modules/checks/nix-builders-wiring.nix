# Structural check for the nix-builders clan service across the fleet.
#
# It guards pairings between machines' configurations that no single machine's
# evaluation can catch. A dispatcher reaches a builder at the builder's
# ZeroTier address over grpc://, verifying it against the instance CA and
# presenting its own certificate; the builder trusts that CA and grants the
# `trusted` role by certificate CN to every other dispatcher. A builder that
# names the wrong CA, a CN rule for the wrong machine, or a port opened beyond
# the mesh interfaces builds and activates and is wrong in the one way that matters.
#
# It also pins what each dispatcher actually schedules (the entries and the
# store URI each one names), that the grpc:// plugin is loaded where it
# dispatches and finds the dispatcher's certificate, key and CA linked at its
# default lookup path, that the build accounts and dispatch keys of the
# retired ssh transport stay gone, and that a Linux builder's own nix settings
# give it uid-range exactly when it advertises uid-range, and that a darwin
# builder's launchd job waits for the store and every daemon argument under
# /run before it execs the daemon.
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
      # on x86_64-linux even though a darwin configuration names darwin store
      # paths nothing on Linux can realise.
      plain = builtins.unsafeDiscardStringContext;
      sortStrings = lib.sort lib.lessThan;

      isDarwin = machine: self.darwinConfigurations ? ${machine};
      configOf =
        machine:
        if isDarwin machine then
          self.darwinConfigurations.${machine}.config
        else
          self.nixosConfigurations.${machine}.config;

      builders = [
        "argentum"
        "magnetite"
        "pyrite"
        "rosegold"
        "stibnite"
      ];
      dispatchers = [
        "magnetite"
        "pyrite"
        "stibnite"
      ];

      # The builders' ZeroTier IPv6 addresses, from the registry.
      address = lib.genAttrs builders (machine: self.lib.hosts.${machine}.zerotier.address);

      vars = machine: (configOf machine).clan.core.vars.generators;
      caPath = machine: plain (vars machine).nix-grpc-ca.files."ca.crt".path;
      certPath = machine: plain (vars machine).nix-grpc-cert.files."cert.pem".path;
      keyPath = machine: plain (vars machine).nix-grpc-cert.files."key.pem".path;

      projectEntry = entry: {
        inherit (entry)
          protocol
          systems
          maxJobs
          speedFactor
          ;
        hostName = plain entry.hostName;
        sshUser = entry.sshUser or null;
        sshKey = if (entry.sshKey or null) == null then null else plain entry.sshKey;
        supportedFeatures = sortStrings entry.supportedFeatures;
        mandatoryFeatures = sortStrings entry.mandatoryFeatures;
      };

      # What a dispatcher schedules, read from nix.buildMachines itself and
      # keyed by store URI; `hosts` keeps the duplicates that keying merges.
      buildMachines = machine: (configOf machine).nix.buildMachines;
      dispatched =
        machine:
        builtins.listToAttrs (
          map (entry: {
            name = plain entry.hostName;
            value = projectEntry entry;
          }) (buildMachines machine)
        );
      hosts = machine: sortStrings (map (entry: plain entry.hostName) (buildMachines machine));

      # The URI a dispatcher names for a builder: the builder's ZeroTier
      # address and the CA the dispatcher links at the plugin's default
      # client directory, where its certificate and key resolve unnamed.
      clientDir = "/run/nix-grpc-store";
      storeUri =
        builder: "grpc://[${address.${builder}}]:50051?ca-cert=${clientDir}/ca.crt&connect-timeout=5";

      expectedDispatch =
        {
          builder,
          systems,
          maxJobs,
          speedFactor,
          supportedFeatures,
        }:
        let
          hostName = storeUri builder;
        in
        {
          name = hostName;
          value = {
            inherit
              hostName
              systems
              maxJobs
              speedFactor
              ;
            protocol = null;
            sshUser = null;
            sshKey = null;
            supportedFeatures = sortStrings supportedFeatures;
            mandatoryFeatures = [ ];
          };
        };

      # The client side of one dispatcher: the plugin, the identity it finds
      # at its default lookup path, and the retired key.
      dispatcherSide =
        machine:
        let
          config = configOf machine;
          client = config.programs.nix-grpc-store;
          linker = config.launchd.daemons.nix-grpc-client-identity;
        in
        {
          pluginLoaded =
            client.enable
            && builtins.elem (plain "${client.package}/lib/nix/plugins") (
              map plain (config.nix.settings.plugin-files or [ ])
            );
          # NixOS tmpfiles rules, or the lines of darwin's boot-time script.
          clientIdentity = sortStrings (
            if isDarwin machine then
              builtins.filter (line: line != "") (lib.splitString "\n" (plain linker.script))
            else
              builtins.filter (lib.hasInfix clientDir) (map plain config.systemd.tmpfiles.rules)
          );
          clientIdentityAtBoot = if isDarwin machine then linker.serviceConfig.RunAtLoad else null;
          sshDispatchKey = config.clan.core.vars.generators ? nix-remote-build;
        };

      expectedDispatcherSide =
        machine:
        let
          links = {
            "ca.crt" = caPath machine;
            "client.crt" = certPath machine;
            "client.key" = keyPath machine;
          };
        in
        {
          pluginLoaded = true;
          clientIdentity = sortStrings (
            if isDarwin machine then
              [ "install -d -m 0755 -o root -g wheel ${clientDir}" ]
              ++ lib.mapAttrsToList (name: target: "ln -sfn ${target} ${clientDir}/${name}") links
            else
              [ "d ${clientDir} 0755 root root - -" ]
              ++ lib.mapAttrsToList (name: target: "L+ ${clientDir}/${name} - - - - ${target}") links
          );
          clientIdentityAtBoot = if isDarwin machine then true else null;
          sshDispatchKey = false;
        };

      # The server side of one builder.
      builderSide =
        machine:
        let
          config = configOf machine;
          daemon = config.services.nix-grpc-daemon;
        in
        {
          inherit (daemon)
            enable
            listen
            idleTimeout
            trustClients
            anonymousRole
            ;
          tls = lib.mapAttrs (_: plain) {
            inherit (daemon.tls) certFile keyFile clientCaFile;
          };
          accessRules = map (rule: { inherit (rule) cn role; }) daemon.accessRules;
          trusted = builtins.elem "nix-grpc-daemon" (config.nix.settings.extra-trusted-users or [ ]);
          # nix-darwin has no per-interface firewall; darwin binds the
          # ZeroTier address instead, pinned by `listen`.
          meshPort =
            if isDarwin machine then
              null
            else
              lib.genAttrs (self.lib.meshInterfaces config) (
                key: builtins.elem 50051 (config.networking.firewall.interfaces.${key}.allowedTCPPorts or [ ])
              );
          globalPort =
            if isDarwin machine then null else builtins.elem 50051 config.networking.firewall.allowedTCPPorts;
          sshBuildAccounts = builtins.filter (user: config.users.users ? ${user}) [
            "builder"
            "nixbuild"
          ];
          # nix includes uid-range only with auto-allocate-uids, which needs
          # its experimental feature; nspawn tests also need cgroups.
          uidRange =
            if isDarwin machine then
              null
            else
              let
                s = config.nix.settings;
              in
              (s.auto-allocate-uids or false)
              && builtins.elem "uid-range" (s.extra-system-features or [ ])
              && lib.all (feature: builtins.elem feature s.experimental-features) [
                "auto-allocate-uids"
                "cgroups"
              ];
          # launchd starts the darwin daemon with no ordering against
          # sops-install-secrets, so `sh -c` must wait for the store and for
          # every daemon argument under /run, which macOS empties at boot,
          # before it execs the daemon with the arguments that follow `sh`.
          start =
            if isDarwin machine then
              let
                argv = map plain config.launchd.daemons.nix-grpc-daemon.serviceConfig.ProgramArguments;
                segments = lib.splitString " && " (builtins.elemAt argv 2);
                waits = lib.init segments;
                isWait = lib.hasPrefix "/bin/wait4path ";
                waited = map (lib.removePrefix "/bin/wait4path ") (builtins.filter isWait waits);
                daemonArgs = lib.drop 4 argv;
              in
              {
                shell = lib.take 2 argv ++ [ (builtins.elemAt argv 3) ];
                daemon = baseNameOf (builtins.head daemonArgs);
                waited = sortStrings waited;
                notWaits = builtins.filter (segment: !isWait segment) waits;
                exec = lib.last segments;
                unwaited = builtins.filter (arg: lib.hasPrefix "/run/" arg && !builtins.elem arg waited) daemonArgs;
              }
            else
              null;
        };

      expectedBuilderSide = machine: {
        enable = true;
        listen = if isDarwin machine then "[${address.${machine}}]:50051" else "[::]:50051";
        idleTimeout = if isDarwin machine then null else 600;
        trustClients = true;
        anonymousRole = null;
        tls = {
          certFile = certPath machine;
          keyFile = keyPath machine;
          clientCaFile = caPath machine;
        };
        # Every dispatcher but the builder itself; a dispatcher's exclude
        # narrows what it schedules, not what builders authorize.
        accessRules = map (dispatcher: {
          cn = dispatcher;
          role = "trusted";
        }) (builtins.filter (dispatcher: dispatcher != machine) dispatchers);
        trusted = true;
        meshPort =
          if isDarwin machine then
            null
          else
            lib.genAttrs (self.lib.meshInterfaces (configOf machine)) (_: true);
        globalPort = if isDarwin machine then null else false;
        sshBuildAccounts = [ ];
        # A Linux builder honours uid-range exactly when it advertises it.
        uidRange =
          if isDarwin machine then
            null
          else
            builtins.elem "uid-range" advertised.${machine}.supportedFeatures;
        # The store and the TLS key, the one daemon argument under /run.
        start =
          if isDarwin machine then
            {
              shell = [
                "/bin/sh"
                "-c"
                "sh"
              ];
              daemon = "nix-grpc-daemon";
              waited = sortStrings [
                "/nix/store"
                (keyPath machine)
              ];
              notWaits = [ ];
              exec = ''exec "$@"'';
              unwaited = [ ];
            }
          else
            null;
      };

      stibnite = configOf "stibnite";
      magnetite = configOf "magnetite";

      # stibnite's interactive session identity, generated on magnetite. It
      # is ssh and unrelated to the build transport; the check keeps pinning
      # its authorization because nothing else does.
      sessionKey =
        lib.removeSuffix "\n"
          magnetite.clan.core.vars.generators.stibnite-agent-session.files."key.pub".value;
      sessionUser = stibnite.services.stibnite-session-host.user;
      sessionAuthorized = lib.concatStringsSep "\n" (
        map plain stibnite.users.users.${sessionUser}.openssh.authorizedKeys.keys
      );

      toMagnetite = expectedDispatch {
        builder = "magnetite";
        systems = [ "x86_64-linux" ];
        maxJobs = 8;
        speedFactor = 2;
        supportedFeatures = [
          "big-parallel"
          "nixos-test"
          "uid-range"
          "recursive-nix"
        ];
      };
      toPyrite = expectedDispatch {
        builder = "pyrite";
        systems = [ "x86_64-linux" ];
        maxJobs = 1;
        speedFactor = 1;
        supportedFeatures = [
          "kvm"
          "nixos-test"
          "uid-range"
        ];
      };
      toStibnite = expectedDispatch {
        builder = "stibnite";
        systems = [ "aarch64-darwin" ];
        maxJobs = 16;
        speedFactor = 1;
        supportedFeatures = [
          "apple-virt"
          "big-parallel"
        ];
      };

      stibniteDispatch = [
        toMagnetite
        toPyrite
      ];
      magnetiteDispatch = [ toStibnite ];
      pyriteDispatch = [
        toMagnetite
        toStibnite
      ];
      advertised = {
        magnetite = toMagnetite.value;
        pyrite = toPyrite.value;
      };
    in
    {
      # The fact is the same on every system and darwin builds are
      # best-effort, so it is evaluated once, on x86_64-linux.
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        nix-builders-wiring = mkCheck {
          name = "nix-builders-wiring";
          actual = {
            stibnite = {
              hosts = hosts "stibnite";
              dispatch = dispatched "stibnite";
            };
            magnetite = {
              hosts = hosts "magnetite";
              dispatch = dispatched "magnetite";
            };
            pyrite = {
              hosts = hosts "pyrite";
              dispatch = dispatched "pyrite";
            };
            dispatchers = lib.genAttrs dispatchers dispatcherSide;
            builders = lib.genAttrs builders builderSide;
            sessionKeyAuthorizedForSessions = lib.hasInfix sessionKey sessionAuthorized;
          };
          expected = {
            stibnite = {
              hosts = sortStrings (map (entry: entry.name) stibniteDispatch);
              # rosegold and argentum are excluded: stibnite builds
              # aarch64-darwin itself.
              dispatch = builtins.listToAttrs stibniteDispatch;
            };
            magnetite = {
              hosts = sortStrings (map (entry: entry.name) magnetiteDispatch);
              # pyrite is excluded: magnetite builds x86_64-linux itself.
              # rosegold and argentum are excluded until the binary cache
              # holds nixbot's darwin outputs.
              dispatch = builtins.listToAttrs magnetiteDispatch;
            };
            pyrite = {
              hosts = sortStrings (map (entry: entry.name) pyriteDispatch);
              # rosegold and argentum are excluded, as in stibnite's entry.
              dispatch = builtins.listToAttrs pyriteDispatch;
            };
            dispatchers = lib.genAttrs dispatchers expectedDispatcherSide;
            builders = lib.genAttrs builders expectedBuilderSide;
            sessionKeyAuthorizedForSessions = true;
          };
        };
      };
    };
}
