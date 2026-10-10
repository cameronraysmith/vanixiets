# Structural check for the nix-builders clan service across the fleet.
#
# It guards pairings between machines' configurations that no single machine's
# evaluation can catch. A dispatcher reaches a builder at the builder's
# ZeroTier address over grpc://, verifying it against the instance CA and
# presenting its own certificate; the builder trusts that CA and grants the
# `trusted` role by certificate CN to every other dispatcher. A builder that
# names the wrong CA, a CN rule for the wrong machine, or a port opened beyond
# ZeroTier builds and activates and is wrong in the one way that matters.
#
# It also pins what each dispatcher actually schedules (the entries and the
# store URI each one names), that the grpc:// plugin is loaded where it
# dispatches and finds the dispatcher's certificate, key and CA linked at its
# default lookup path, and that the build accounts and dispatch keys of the
# retired ssh transport stay gone.
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
        "stibnite"
      ];

      # ZeroTier IPv6 addresses, as in modules/system/ssh-known-hosts.nix.
      address = {
        magnetite = "fddb:4344:343b:14b9:399:930f:39db:40d2";
        pyrite = "fddb:4344:343b:14b9:399:937e:8067:8028";
        stibnite = "fddb:4344:343b:14b9:399:9324:19d9:3451";
        rosegold = "fddb:4344:343b:14b9:399:9315:3431:ee8";
        argentum = "fddb:4344:343b:14b9:399:93f7:54d5:ad7e";
      };

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

      # The fleet entries a dispatcher schedules, read from nix.buildMachines
      # itself so the splice is under test, keyed by store URI.
      fleetEntries =
        machine:
        builtins.filter (entry: entry.hostName != "rosetta-builder") (configOf machine).nix.buildMachines;
      dispatched =
        machine:
        builtins.listToAttrs (
          map (entry: {
            name = plain entry.hostName;
            value = projectEntry entry;
          }) (fleetEntries machine)
        );
      # Rosetta entries keep their place; the fleet's follow in any order.
      splice =
        machine:
        let
          names = map (entry: plain entry.hostName) (configOf machine).nix.buildMachines;
          rosetta = builtins.filter (name: name == "rosetta-builder") names;
        in
        {
          order = rosetta ++ sortStrings (lib.drop (builtins.length rosetta) names);
          fleetEntriesAreTheService =
            map projectEntry (fleetEntries machine)
            == map projectEntry (configOf machine).services.nix-builders.buildMachines;
        };

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
          zeroTierPort =
            if isDarwin machine then
              null
            else
              builtins.elem 50051 (config.networking.firewall.interfaces."zt+".allowedTCPPorts or [ ]);
          globalPort =
            if isDarwin machine then null else builtins.elem 50051 config.networking.firewall.allowedTCPPorts;
          sshBuildAccounts = builtins.filter (user: config.users.users ? ${user}) [
            "builder"
            "nixbuild"
          ];
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
        zeroTierPort = if isDarwin machine then null else true;
        globalPort = if isDarwin machine then null else false;
        sshBuildAccounts = [ ];
      };

      stibnite = configOf "stibnite";
      magnetite = configOf "magnetite";

      rosettaEntries = builtins.filter (
        entry: entry.hostName == "rosetta-builder"
      ) stibnite.nix.buildMachines;

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

      stibniteDispatch = [
        (expectedDispatch {
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
        })
        (expectedDispatch {
          builder = "pyrite";
          systems = [ "x86_64-linux" ];
          maxJobs = 1;
          speedFactor = 1;
          supportedFeatures = [
            "kvm"
            "nixos-test"
          ];
        })
      ];
      magnetiteDispatch = [
        (expectedDispatch {
          builder = "stibnite";
          systems = [ "aarch64-darwin" ];
          maxJobs = 4;
          speedFactor = 1;
          supportedFeatures = [
            "apple-virt"
            "big-parallel"
          ];
        })
      ];
    in
    {
      # The fact is the same on every system and darwin builds are
      # best-effort, so it is evaluated once, on x86_64-linux.
      checks = lib.optionalAttrs (system == "x86_64-linux") {
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
            };
            dispatchers = lib.genAttrs dispatchers dispatcherSide;
            builders = lib.genAttrs builders builderSide;
            sessionKeyAuthorizedForSessions = lib.hasInfix sessionKey sessionAuthorized;
          };
          expected = {
            stibnite = {
              # nix-rosetta-builder's local VM keeps its own ssh-ng transport.
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
                ]
                ++ sortStrings (map (entry: entry.name) stibniteDispatch);
                fleetEntriesAreTheService = true;
              };
              # rosegold and argentum are excluded: stibnite builds
              # aarch64-darwin itself.
              dispatch = builtins.listToAttrs stibniteDispatch;
            };
            magnetite = {
              splice = {
                order = map (entry: entry.name) magnetiteDispatch;
                fleetEntriesAreTheService = true;
              };
              # pyrite is excluded: magnetite builds x86_64-linux itself.
              # rosegold and argentum are excluded until the binary cache
              # holds nixbot's darwin outputs.
              dispatch = builtins.listToAttrs magnetiteDispatch;
            };
            dispatchers = lib.genAttrs dispatchers expectedDispatcherSide;
            builders = lib.genAttrs builders expectedBuilderSide;
            sessionKeyAuthorizedForSessions = true;
          };
        };
      };
    };
}
