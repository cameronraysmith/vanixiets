# Remote nix builders as one fleet capability, over nix-grpc-store.
#
# roles.builder runs nix-grpc-daemon on port 50051 in front of the local
# nix-daemon, requiring mutual TLS against the instance CA and granting the
# `trusted` role only to certificates whose CN names a dispatcher. trustClients
# makes the proxy user a Nix trusted user, store-root-equivalent on the builder;
# an untrusted user cannot receive unsigned paths the caller evaluated itself.
# `exclude` decides where a dispatcher sends work, not who is authorized.
#
# The port is reachable only over ZeroTier. NixOS opens it on `zt+` and binds the
# wildcard through socket activation. nix-darwin has no per-interface firewall,
# so darwin builders bind their ZeroTier address and KeepAlive retries until that
# address exists after boot; launchd has no socket activation, so idleTimeout is
# null there. The upstream darwin module starts the daemon by its store path,
# which launchd can try before the store volume is mounted and then never
# retries, so the arguments are restated behind /bin/wait4path.
#
# Identities are clan vars: one shared CA whose private key is never deployed,
# and one certificate per machine with the machine name as CN and both serverAuth
# and clientAuth, so a builder presents it as server and a dispatcher as client.
# Builder certificates carry the ZeroTier address as an IP SAN, because
# dispatchers connect to that literal address rather than through DNS.
#
# roles.dispatcher exposes a read-only buildMachines list that machines splice
# into their own nix.buildMachines; this service never assigns that option,
# because stibnite merges it with nix-rosetta-builder's entries under mkForce.
#
# Nix names a per-builder lock file after the whole store URI, which overflows
# NAME_MAX once the URI spells out store paths, so the URI carries only
# `ca-cert`; putting the instance CA in the system bundle instead would make
# every TLS client on the host trust it. The client certificate and key resolve
# from the plugin's default directory, /run/nix-grpc-store, as symlinks that
# survive secret regeneration. NixOS creates them with tmpfiles; darwin empties
# /run at boot and reruns no activation script, so a RunAtLoad daemon does.
#
# An unreachable builder costs connection retries, after which nix marks it
# disabled for the rest of the hook's lifetime and falls back to a local build;
# work only that builder could take fails with `missing system features`.
{ inputs, ... }:
{
  clan.modules.nix-builders =
    { lib, ... }:
    let
      port = 50051;
      clientDir = "/run/nix-grpc-store";

      # The plugin's default client file names, mapped to this machine's vars.
      clientFiles = vars: {
        "ca.crt" = vars.nix-grpc-ca.files."ca.crt".path;
        "client.crt" = vars.nix-grpc-cert.files."cert.pem".path;
        "client.key" = vars.nix-grpc-cert.files."key.pem".path;
      };

      # Symlinks keep each target's owner and mode: the key stays 0400, owned
      # by root, or by nix-grpc-daemon on a machine that also builds, and root
      # reads it either way.
      clientIdentityNixos =
        { config, ... }:
        {
          systemd.tmpfiles.rules = [
            "d ${clientDir} 0755 root root - -"
          ]
          ++ lib.mapAttrsToList (name: target: "L+ ${clientDir}/${name} - - - - ${target}") (
            clientFiles config.clan.core.vars.generators
          );
        };

      # The links' targets are in the plist, so a changed target reloads the
      # daemon and RunAtLoad recreates them on activation as well as at boot.
      clientIdentityDarwin =
        { config, ... }:
        {
          launchd.daemons.nix-grpc-client-identity = {
            script = ''
              install -d -m 0755 -o root -g wheel ${clientDir}
            ''
            + lib.concatStrings (
              lib.mapAttrsToList (name: target: ''
                ln -sfn ${target} ${clientDir}/${name}
              '') (clientFiles config.clan.core.vars.generators)
            );
            serviceConfig.RunAtLoad = true;
          };
        };

      # readOnly counts a default as a definition, so the option has none: the
      # dispatcher role defines it once, and perMachine supplies the empty
      # value on machines without that role.
      outputModule = machineRoles: {
        options.services.nix-builders.buildMachines = lib.mkOption {
          type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
          readOnly = true;
          description = ''
            nix.buildMachines entries for every builder this machine
            dispatches to; [] on non-dispatchers. Machines splice this into
            their own nix.buildMachines; the service never sets that option.
          '';
        };
        config.services.nix-builders = lib.optionalAttrs (!lib.elem "dispatcher" machineRoles) {
          buildMachines = [ ];
        };
      };

      # The CA and this machine's certificate, defined once per machine whatever
      # its roles, so a machine that both builds and dispatches has one identity.
      identityModule =
        { machine, instances }:
        { pkgs, ... }:
        let
          builderAddresses = lib.unique (
            lib.concatMap (
              instance:
              lib.optional (
                instance.roles ? builder && instance.roles.builder.machines ? ${machine.name}
              ) instance.roles.builder.machines.${machine.name}.settings.address
            ) (lib.attrValues instances)
          );
          subjectAltNames = [
            "DNS:${machine.name}.zt"
          ]
          ++ map (address: "IP:${address}") builderAddresses;
        in
        {
          clan.core.vars.generators = {
            # Shared: every machine of the instance trusts the same CA. The
            # private key stays in the repository's encrypted vars and signs
            # machine certificates at generation time only.
            nix-grpc-ca = {
              share = true;
              files."ca.key".deploy = false;
              files."ca.crt".secret = false;
              runtimeInputs = [ pkgs.openssl ];
              script = ''
                openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$out"/ca.key
                openssl req -x509 -new -key "$out"/ca.key -sha256 -days 3650 \
                  -subj "/CN=nix-builders CA" \
                  -addext "basicConstraints=critical,CA:TRUE" \
                  -addext "keyUsage=critical,keyCertSign,cRLSign" \
                  -addext "subjectKeyIdentifier=hash" \
                  -out "$out"/ca.crt
              '';
            };

            # The builder's daemon runs as nix-grpc-daemon and reads the key
            # itself; a dispatcher's build hook runs as root inside nix-daemon.
            # validation regenerates the certificate when its SANs change.
            nix-grpc-cert = {
              dependencies = [ "nix-grpc-ca" ];
              files."key.pem" = lib.optionalAttrs (builderAddresses != [ ]) { owner = "nix-grpc-daemon"; };
              files."cert.pem".secret = false;
              # clan's validation accepts scalars, so the SAN list is joined into
              # the same string the certificate extension uses.
              validation.subjectAltNames = lib.concatStringsSep "," subjectAltNames;
              runtimeInputs = [ pkgs.openssl ];
              script = ''
                openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$out"/key.pem
                openssl req -new -key "$out"/key.pem -subj "/CN=${machine.name}" -out cert.csr
                cat > cert.ext <<'EOF'
                basicConstraints=critical,CA:FALSE
                keyUsage=critical,digitalSignature
                extendedKeyUsage=serverAuth,clientAuth
                subjectAltName=${lib.concatStringsSep "," subjectAltNames}
                EOF
                openssl x509 -req -in cert.csr \
                  -CA "$in"/nix-grpc-ca/ca.crt -CAkey "$in"/nix-grpc-ca/ca.key \
                  -set_serial "0x$(openssl rand -hex 16)" \
                  -sha256 -days 3650 -extfile cert.ext \
                  -out "$out"/cert.pem
              '';
            };
          };
        };

      # Shared by both classes; listen address and activation differ per class.
      mkBuilderModule =
        { roles, machine }:
        { config, ... }:
        let
          vars = config.clan.core.vars.generators;
        in
        {
          services.nix-grpc-daemon = {
            enable = true;
            # Remote builds import unsigned store paths from the dispatcher.
            trustClients = true;
            tls = {
              certFile = vars.nix-grpc-cert.files."cert.pem".path;
              keyFile = vars.nix-grpc-cert.files."key.pem".path;
              clientCaFile = vars.nix-grpc-ca.files."ca.crt".path;
            };
            # First match wins and a certificate matching no rule is denied,
            # so a builder that does not dispatch cannot use its peers.
            accessRules = map (dispatcher: {
              cn = dispatcher;
              role = "trusted";
            }) (lib.filter (d: d != machine.name) (lib.attrNames roles.dispatcher.machines));
          };
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
            description = ''
              Deterministic ZeroTier IPv6, matching modules/system/ssh-known-hosts.nix.
              Dispatchers connect to it directly and the builder's certificate names it.
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
        {
          roles,
          settings,
          machine,
        }:
        let
          builders = lib.filterAttrs (
            name: _: name != machine.name && !(lib.elem name settings.exclude)
          ) roles.builder.machines;
          # The client certificate and key resolve by default; the CA does
          # not, because the plugin's default is the system bundle.
          # connect-timeout stays well below the plugin's 30s default: laptops
          # in this fleet are routinely asleep, and a build must not stall half
          # a minute per unreachable builder before nix disables it.
          storeUri =
            builder:
            "grpc://[${builder.settings.address}]:${toString port}?ca-cert=${clientDir}/ca.crt&connect-timeout=5";
        in
        {
          # The flake exports the client only under nixosModules; it sets
          # nix.settings alone, which nix-darwin provides too.
          imports = [ inputs.nix-grpc-store.nixosModules.client ];

          programs.nix-grpc-store.enable = true;

          services.nix-builders.buildMachines = lib.mapAttrsToList (_: builder: {
            hostName = storeUri builder;
            protocol = null;
            inherit (builder.settings)
              systems
              maxJobs
              speedFactor
              supportedFeatures
              mandatoryFeatures
              ;
          }) builders;

          nix.distributedBuilds = true;
          nix.settings.builders-use-substitutes = lib.mkIf settings.buildersUseSubstitutes true;
        };
    in
    {
      _class = "clan.service";
      manifest = {
        name = "nix-builders";
        description = "Remote nix builders and the machines that dispatch to them";
        categories = [ "System" ];
        readme = ''
          Remote nix build capability across the fleet over nix-grpc-store.
          `builder` machines run nix-grpc-daemon on port 50051, reachable
          over ZeroTier only, and grant the `trusted` role to every
          dispatcher of the instance by mTLS certificate CN; `dispatcher`
          machines load the grpc:// store plugin and expose
          `services.nix-builders.buildMachines` for their nix.buildMachines.
        '';
      };

      # The client identity is per machine, like the vars it links, so a
      # machine dispatching in several instances links it once.
      perMachine =
        { machine, instances, ... }:
        let
          dispatches = lib.elem "dispatcher" machine.roles;
        in
        {
          nixosModule = {
            imports = [
              (outputModule machine.roles)
              (identityModule { inherit machine instances; })
            ]
            ++ lib.optional dispatches clientIdentityNixos;
          };
          darwinModule = {
            imports = [
              (outputModule machine.roles)
              (identityModule { inherit machine instances; })
            ]
            ++ lib.optional dispatches clientIdentityDarwin;
          };
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
          {
            nixosModule = {
              imports = [
                inputs.nix-grpc-store.nixosModules.server
                (mkBuilderModule { inherit roles machine; })
              ];
              # Socket activation binds the wildcard at boot, before ZeroTier
              # is up; the firewall keeps the port off every other interface.
              services.nix-grpc-daemon.listen = "[::]:${toString port}";
              networking.firewall.interfaces."zt+".allowedTCPPorts = [ port ];
            };

            darwinModule =
              { config, pkgs, ... }:
              {
                imports = [
                  inputs.nix-grpc-store.darwinModules.default
                  (mkBuilderModule { inherit roles machine; })
                ];
                services.nix-grpc-daemon = {
                  listen = "[${settings.address}]:${toString port}";
                  # The upstream darwin module asserts this: launchd provides
                  # no socket activation to restart an idle-exited daemon.
                  idleTimeout = null;
                };
                launchd.daemons.nix-grpc-daemon.serviceConfig.ProgramArguments = lib.mkForce (
                  [
                    "/bin/sh"
                    "-c"
                    ''/bin/wait4path /nix/store && exec "$@"''
                    "sh"
                  ]
                  ++ map toString (
                    import "${inputs.nix-grpc-store}/nixos/daemon-args.nix" {
                      cfg = config.services.nix-grpc-daemon;
                      inherit lib pkgs;
                    }
                  )
                );

                nix.daemonProcessType = lib.mkIf (settings.daemonProcessType != null) settings.daemonProcessType;
                nix.daemonIOLowPriority = lib.mkIf (
                  settings.daemonIOLowPriority != null
                ) settings.daemonIOLowPriority;
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
            nixosModule = mkDispatcher { inherit roles settings machine; };
            darwinModule = mkDispatcher { inherit roles settings machine; };
          };
      };
    };
}
