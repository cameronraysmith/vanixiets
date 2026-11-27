# Fleet metrics collection as one clan service (ADR-003; design D8 to D10),
# and the logs path of S2's dev-loop tables (S2 design D4).
#
# Both roles' NixOS fragments merge into one services.opentelemetry-collector,
# because the NixOS module runs one collector per host. On magnetite, which
# holds both roles, the agent pipelines export to an in-process `forward`
# connector that the ingress pipelines receive from; every other agent host
# exports over mutual TLS to the ingress's otlp/mesh receiver on magnetite's
# ZeroTier address (S4 design D2, D3). The ingress converts
# exponential histograms while the store is below 1.3.0 (ADR-001 R1.2), routes
# metrics on the `vanixiets.database` resource attribute and logs on it and
# `vanixiets.table`, and writes each database, and each devloop table, through
# its own otlp_http exporter with a persistent queue, authenticating as the
# store's write-only `collector` user.
#
# The fragments are plain NixOS modules, flake.modules.nixos.otel-collector-
# agent and -ingress, so the container test imports them without clan; only
# the clan roles read clan vars: the agent role's otel-ca and otel-cert
# generators and the ntfy-alerter token on every host of
# flake.lib.observabilityHosts, and the ingress role's collector password.
#
# This file holds the clan service; agent.nix and ingress.nix hold the two
# fragments, and _shared.nix the bindings the three share.
{ config, ... }:
let
  inherit (import ./_shared.nix { inherit config; })
    nixosModules
    darwinModules
    flakeLib
    schema
    agentSessionUnit
    ;
in
{
  flake.clan.modules.otel-collector =
    { ... }:
    {
      _class = "clan.service";
      manifest = {
        name = "otel-collector";
        description = "Fleet metrics collection into the telemetry store";
        categories = [ "System" ];
        readme = ''
          OpenTelemetry collector for the fleet. `agent` collects the
          machine's host, process, unit and service metrics, runs
          node_exporter on loopback, and imports the observability-notify@
          failure notifier. `ingress` converts, routes and writes metrics
          into GreptimeDB on 127.0.0.1:4000, one otlp_http exporter per
          database with a persistent queue. On a machine holding both
          roles they share one collector, joined by a `forward` connector.
        '';
      };

      roles.agent = {
        description = "Collects the machine's own metrics and posts unit failures to ntfy";
        interface = { };
        perInstance =
          { roles, machine, ... }:
          let
            # One definition of the CA and the certificate for both module
            # classes; clan compares a shared generator's files, prompts,
            # dependencies and validation across machines and ignores owner,
            # group and mode (clan_lib/vars/generator.py:106-116).
            otelGenerators =
              { lib, pkgs }:
              let
                isIngress = roles.ingress.machines ? ${machine.name};
                host = flakeLib.hosts.${machine.name};
                # The ingress is named on both transports while ZeroTier runs.
                sans = lib.optionalString isIngress (
                  lib.concatStringsSep "," [
                    "IP:${host.zerotier.address}"
                    "DNS:${machine.name}.zt"
                    "IP:${host.address}"
                    "DNS:${host.fqdn}"
                  ]
                );
                usage = if isIngress then "serverAuth,clientAuth" else "clientAuth";
              in
              {
                # Shared: every agent trusts one CA; its key signs at generation time
                # only and is never deployed (ADR-003 Q2; design D1).
                otel-ca = {
                  share = true;
                  files."ca.key".deploy = false;
                  files."ca.crt".secret = false;
                  runtimeInputs = [ pkgs.openssl ];
                  script = ''
                    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$out"/ca.key
                    openssl req -x509 -new -key "$out"/ca.key -sha256 -days 3650 -subj "/CN=otel-ca" \
                      -addext "basicConstraints=critical,CA:TRUE" \
                      -addext "keyUsage=critical,keyCertSign,cRLSign" \
                      -addext "subjectKeyIdentifier=hash" -out "$out"/ca.crt
                  '';
                };
                # The SANs and the usage enter validation, so moving a host into the
                # ingress role regenerates its certificate (design D1).
                otel-cert = {
                  dependencies = [ "otel-ca" ];
                  files."cert.pem".secret = false;
                  validation = {
                    subjectAltNames = sans;
                    extendedKeyUsage = usage;
                  };
                  runtimeInputs = [ pkgs.openssl ];
                  script = ''
                    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$out"/key.pem
                    openssl req -new -key "$out"/key.pem -subj "/CN=${machine.name}" -out cert.csr
                    {
                      echo "basicConstraints=critical,CA:FALSE"
                      echo "keyUsage=critical,digitalSignature"
                      echo "extendedKeyUsage=${usage}"
                      ${lib.optionalString isIngress ''echo "subjectAltName=${sans}"''}
                    } > cert.ext
                    openssl x509 -req -in cert.csr -CA "$in"/otel-ca/ca.crt -CAkey "$in"/otel-ca/ca.key \
                      -set_serial "0x$(openssl rand -hex 16)" -sha256 -days 3650 -extfile cert.ext -out "$out"/cert.pem
                  '';
                };
              };
            # Langfuse Cloud's project keys (agent-session-telemetry design
            # D16): one shared var, entered once at hidden prompts and kept,
            # so every flagged host sends with the same project's keys and
            # each must be its recipient (flake.lib.sharedVarsObligations).
            # The script only checks their shape; clan writes each prompt to
            # its file. One definition for both module classes, as
            # otelGenerators (darwin-agent-session-telemetry design D5).
            langfuseGenerator = pkgs: {
              share = true;
              prompts.public-key = {
                description = ''
                  Public key (pk-lf-…) of the Langfuse Cloud project
                  (EU, https://cloud.langfuse.com) that receives the
                  fleet's agent spans; used by no other service.
                '';
                type = "hidden";
                persist = true;
                display = {
                  group = "langfuse";
                  label = "LANGFUSE_PUBLIC_KEY";
                };
              };
              prompts.secret-key = {
                description = "Secret key (sk-lf-…) paired with the public key above.";
                type = "hidden";
                persist = true;
                display = {
                  group = "langfuse";
                  label = "LANGFUSE_SECRET_KEY";
                };
              };
              runtimeInputs = [ pkgs.gnugrep ];
              script = ''
                grep -Eqx 'pk-lf-[A-Za-z0-9-]+' "$out/public-key" || { echo "langfuse: public-key is not pk-lf-…" >&2; exit 1; }
                grep -Eqx 'sk-lf-[A-Za-z0-9-]+' "$out/secret-key" || { echo "langfuse: secret-key is not sk-lf-…" >&2; exit 1; }
              '';
            };
          in
          {
            nixosModule =
              {
                config,
                lib,
                pkgs,
                ...
              }:
              let
                # Static data, so it can select imports without evaluating the host (design D6).
                collect = flakeLib.observabilityHosts.${machine.name}.collect;
                agentTelemetry = collect && flakeLib.observabilityHosts.${machine.name}.agentTelemetry;
                langfuse = agentTelemetry && flakeLib.observabilityHosts.${machine.name}.langfuse;
                credentials = [
                  "otel-cert:${gens.otel-cert.files."cert.pem".path}"
                  "otel-key:${gens.otel-cert.files."key.pem".path}"
                ];
                restart =
                  lib.optional collect "opentelemetry-collector.service"
                  ++ lib.optional agentTelemetry "${agentSessionUnit}.service";
                gens = config.clan.core.vars.generators;
              in
              {
                # Declared on every agent host, so one vars step covers all six; on a host
                # that does not collect yet they are uploaded files no unit reads.
                imports = [
                  nixosModules.ntfy-alerter
                ]
                ++ lib.optional collect nixosModules.otel-collector-agent;

                config = lib.mkMerge [
                  {
                    # restartUnits only here: clan throws on it on darwin
                    # (clan-core generic-generator.nix:193-208; design D5).
                    clan.core.vars.generators = lib.mkMerge [
                      (otelGenerators { inherit lib pkgs; })
                      {
                        otel-cert.files."key.pem".restartUnits = restart;
                        otel-cert.files."cert.pem".restartUnits = restart;
                      }
                    ];
                  }
                  {
                    assertions = [
                      {
                        assertion = !flakeLib.observabilityHosts.${machine.name}.langfuse || agentTelemetry;
                        message = "otel-collector agent on ${machine.name}: flake.lib.observabilityHosts sets langfuse without collect and agentTelemetry; Langfuse is fed by the agent-session collector (agent-session-telemetry design D16).";
                      }
                    ];
                  }
                  # ca.crt reaches the collector as a store path, so a new CA changes
                  # the configuration and restarts it (design D1). The credentials
                  # load on the ingress host too, where otlp/mesh presents them.
                  # optionalAttrs, not mkIf: where collect is false these options
                  # are not declared, and collect is static data.
                  (lib.optionalAttrs collect {
                    vanixiets.otelCollector.caFile = pkgs.writeText "otel-ca.crt" gens.otel-ca.files."ca.crt".value;
                    vanixiets.otelCollector.smartDevices = flakeLib.observabilityHosts.${machine.name}.smartDevices;
                    vanixiets.otelCollector.agentTelemetry = flakeLib.observabilityHosts.${machine.name}.agentTelemetry;
                    vanixiets.otelCollector.langfuse = langfuse;
                    services.observability-notify = {
                      units = flakeLib.observabilityHosts.${machine.name}.notifiedUnits;
                      tokenFile = gens.ntfy-alerter.files.token.path;
                    };
                    systemd.services.opentelemetry-collector.serviceConfig.LoadCredential = credentials;
                  })
                  # The agent-session collector presents the same certificate
                  # (agent-session-telemetry design D14).
                  (lib.optionalAttrs agentTelemetry {
                    systemd.services.${agentSessionUnit}.serviceConfig.LoadCredential = credentials;
                  })
                  # Langfuse Cloud's project keys (agent-session-telemetry
                  # design D16), with the unit's restart on a change.
                  (lib.optionalAttrs langfuse {
                    clan.core.vars.generators.langfuse = lib.mkMerge [
                      (langfuseGenerator pkgs)
                      {
                        files.public-key.restartUnits = [ "${agentSessionUnit}.service" ];
                        files.secret-key.restartUnits = [ "${agentSessionUnit}.service" ];
                      }
                    ];
                    systemd.services.${agentSessionUnit}.serviceConfig.LoadCredential = [
                      "langfuse-public-key:${gens.langfuse.files.public-key.path}"
                      "langfuse-secret-key:${gens.langfuse.files.secret-key.path}"
                    ];
                  })
                ];
              };

            # Every darwin row, whatever its collect: the collector's account
            # and its three secrets, so the files have their owner before any
            # collector runs; the fragment only where collect is true (design
            # D1, D2, D5). nix-darwin has no tmpfiles and no restartUnits:
            # the fragment's OTEL_CERT_SHA256 reloads the agent on a reissue.
            # Where the row sets agentTelemetry, the agent-session daemon's
            # own account _otelagent, so that only it can read the Langfuse
            # keys, as only otel-agent-session.service loads them on NixOS;
            # the client key both collectors present is then group _otelcert's
            # at 0440 (darwin-agent-session-telemetry design D3, D5).
            darwinModule =
              {
                lib,
                pkgs,
                ...
              }:
              let
                # Static data, so it can select imports without evaluating the host (design D6).
                collect = flakeLib.observabilityHosts.${machine.name}.collect;
                agentTelemetry = collect && flakeLib.observabilityHosts.${machine.name}.agentTelemetry;
                langfuse = agentTelemetry && flakeLib.observabilityHosts.${machine.name}.langfuse;
                otelcol = {
                  owner = "_otelcol";
                  group = "_otelcol";
                  mode = "0400";
                };
              in
              {
                imports = [
                  darwinModules.ntfy-alerter
                ]
                ++ lib.optional collect darwinModules.otel-collector-agent;

                config = lib.mkMerge [
                  {
                    assertions = [
                      {
                        assertion = !flakeLib.observabilityHosts.${machine.name}.langfuse || agentTelemetry;
                        message = "otel-collector agent on ${machine.name}: flake.lib.observabilityHosts sets langfuse without collect and agentTelemetry; Langfuse is fed by the agent-session collector (agent-session-telemetry design D16).";
                      }
                    ];

                    # As nix-grpc-store's darwin module declares nix-grpc-daemon.
                    users.knownGroups = [ "_otelcol" ];
                    users.knownUsers = [ "_otelcol" ];
                    users.groups._otelcol.gid = 536;
                    users.users._otelcol = {
                      uid = 536;
                      gid = 536;
                      home = "/var/empty";
                      shell = "/usr/bin/false";
                      isHidden = true;
                      description = "OpenTelemetry collector agent";
                    };

                    clan.core.vars.generators = lib.mkMerge [
                      (otelGenerators { inherit lib pkgs; })
                      {
                        otel-cert.files."key.pem" =
                          otelcol
                          // {
                            neededFor = "services";
                          }
                          // lib.optionalAttrs agentTelemetry {
                            group = "_otelcert";
                            mode = "0440";
                          };
                        ntfy-alerter.files.token = {
                          inherit (otelcol) owner mode;
                        };
                      }
                    ];
                  }
                  # The fragment declares these, as the NixOS role sets them: the
                  # agent-telemetry home module reads agentTelemetry to turn the
                  # emitters on (darwin-agent-session-telemetry design D10).
                  (lib.optionalAttrs collect {
                    vanixiets.otelCollector = { inherit agentTelemetry langfuse; };
                  })
                  (lib.optionalAttrs agentTelemetry {
                    users.knownGroups = [
                      "_otelagent"
                      "_otelcert"
                    ];
                    users.knownUsers = [ "_otelagent" ];
                    users.groups._otelagent.gid = 537;
                    users.groups._otelcert = {
                      gid = 538;
                      members = [
                        "_otelcol"
                        "_otelagent"
                      ];
                    };
                    users.users._otelagent = {
                      uid = 537;
                      gid = 537;
                      home = "/var/empty";
                      shell = "/usr/bin/false";
                      isHidden = true;
                      description = "OpenTelemetry agent-session collector";
                    };
                  })
                  # Read by path through basicauth/langfuse's username_file and
                  # password_file; no restartUnits on darwin, the daemon's
                  # LANGFUSE_VAR_SHA256 reloads it instead.
                  (lib.optionalAttrs langfuse {
                    clan.core.vars.generators.langfuse = lib.mkMerge [
                      (langfuseGenerator pkgs)
                      {
                        files = lib.genAttrs [ "public-key" "secret-key" ] (_: {
                          owner = "_otelagent";
                          group = "_otelagent";
                          mode = "0400";
                          neededFor = "services";
                        });
                      }
                    ];
                  })
                ];
              };
          };
      };

      roles.ingress = {
        description = "Writes collected metrics into the telemetry store";
        interface = { };
        perInstance =
          { ... }:
          {
            nixosModule =
              { config, lib, ... }:
              {
                imports = [ nixosModules.otel-collector-ingress ];
                systemd.services.opentelemetry-collector.serviceConfig.LoadCredential = [
                  "collector-password:${config.clan.core.vars.generators.greptimedb-users.files.collector-password.path}"
                ];
                # The hourly budget over the store, read as `regulator`
                # (design D8); the envelope reads every host's notified units.
                vanixiets.otelCollector.envelopeBudget = {
                  storeUrl = "http://127.0.0.1:4000";
                  notifiedUnits = lib.mapAttrs (_: h: h.notifiedUnits) flakeLib.observabilityHosts;
                  databases = schema.databases;
                };
                systemd.services.otel-envelope = {
                  after = [ "greptimedb.service" ];
                  serviceConfig.LoadCredential = [
                    "regulator-password:${config.clan.core.vars.generators.greptimedb-users.files.regulator-password.path}"
                  ];
                };
                # otlp/mesh, on the mesh interfaces only. magnetite's
                # net.ipv6.ip_nonlocal_bind = 1 lets the receiver bind its
                # address before the mesh daemon holds it.
                networking.firewall.interfaces = lib.genAttrs (flakeLib.meshInterfaces config) (_: {
                  allowedTCPPorts = [ 4318 ];
                });
              };
          };
      };
    };
}
