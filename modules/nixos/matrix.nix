# Matrix homeserver for magnetite
#
# Composes a full Matrix homeserver stack on the public hostname
# matrix.scientistexperience.net using direct nixpkgs services (Option A
# per the Phase-1 research deliverable at
# docs/notes/matrix/magnetite-public-deployment-research.md):
#
#   - matrix-synapse: federated-disabled Synapse with rate-limiting and
#     shared-secret registration (mag-3, mag-6)
#   - livekit + lk-jwt-service: MatrixRTC backend for Element Call,
#     sharing a single keyfile (mag-4, mag-8)
#   - coturn: TURN/STUN relay for NAT-traversal fallback (mag-5, mag-9)
#   - element-call SPA: Element Call web client served as static assets
#     with a runtime-substituted config.json (mag-11)
#   - nginx vhost: single-vhost composition serving SPA at /, Synapse
#     APIs at /_matrix and /_synapse, lk-jwt-service at /livekit/jwt,
#     and literal-JSON .well-known/matrix/{server,client} for client
#     discovery and MSC4143 rtc_foci advertisement (mag-12)
#   - register-users systemd-oneshot: idempotent user provisioning via
#     register_new_matrix_user with the shared registration secret
#     (mag-13)
#
# clan-vars generators are declared inline within this module per the
# gitea.nix/buildbot.nix four-part dendritic pattern. The Synapse and
# coturn generators bind owner to the static service user; the LiveKit
# keyfile generator omits owner because both LiveKit and lk-jwt-service
# run with DynamicUser=true and the upstream modules materialize the
# secret via LoadCredential internally.
#
# Sharp edges honored:
#   - allow_unsafe_locale at settings.database level (not args)
#     per cinnabar c62e9690f.
#   - register_new_matrix_user --exists-ok required for idempotent
#     re-runs per cinnabar fcb49967e.
#   - coturn relay range 49152-49999 to avoid LiveKit's default
#     50000-51000 RTC range.
#   - ACME group=turnserver + reloadServices=[coturn.service] so coturn
#     can read the renewed key.
#   - LiveKit and lk-jwt-service share the SAME keyfile path.
#   - .well-known/matrix/client served by nginx (not Synapse) with
#     org.matrix.msc4143.rtc_foci pointing at the LiveKit SFU URL.
#   - Federation closed at the listener level: resources = [ "client" ]
#     only, federation_domain_whitelist = [ ], enable_registration =
#     false (Phase-1 registration goes through the systemd-oneshot).
{
  config,
  inputs,
  ...
}:
{
  flake.modules.nixos.matrix =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      domain = "matrix.scientistexperience.net";
      synapsePort = 8008;
      lkJwtPort = 8080;
      # Intended Matrix users — small initial list mirroring cinnabar.
      # Adding a user requires (a) extending this list, (b) the supervising
      # operator invoking `clan vars generate magnetite --generator
      # matrix-password-<user>` to populate the password file.
      matrixUsers = [ "cameron" ];

      # Element Call SPA overlay. Copies the upstream package and writes
      # a config.json pointing the client at this homeserver and the
      # lk-jwt-service mounted at /livekit/jwt. Pattern mirrors the
      # clan-core matrix-synapse element-web overlay at
      # clanServices/matrix-synapse/default.nix:215-223, substituting
      # element-call for element-web.
      elementCallConfig = pkgs.runCommand "element-call-config" { } ''
        cp -r ${pkgs.element-call} $out
        chmod -R u+w $out
        cat > $out/config.json <<'EOF'
        ${builtins.toJSON {
          default_server_config = {
            "m.homeserver" = {
              base_url = "https://${domain}";
              server_name = domain;
            };
          };
          livekit = {
            livekit_service_url = "https://${domain}/livekit/jwt";
          };
        }}
        EOF
      '';

      # Literal JSON served by nginx for client discovery. Carries the
      # MSC4143 rtc_foci advertisement so Element Call clients find the
      # LiveKit SFU without out-of-band configuration.
      wellKnownClient = builtins.toJSON {
        "m.homeserver" = {
          base_url = "https://${domain}";
        };
        "org.matrix.msc4143.rtc_foci" = [
          {
            type = "livekit";
            livekit_service_url = "https://${domain}/livekit/jwt";
          }
        ];
      };

      # Literal JSON for server-server discovery. Even with federation
      # disabled, serving the canonical record keeps third-party clients
      # that probe before attempting federation from receiving 404s that
      # they may mis-classify as transient.
      wellKnownServer = builtins.toJSON {
        "m.server" = "${domain}:443";
      };
    in
    {
      ############################################################
      # Part 1: clan-vars generators
      ############################################################

      # Synapse shared registration secret. Synapse expects a YAML file
      # with key registration_shared_secret loaded via extraConfigFiles;
      # the register-users oneshot extracts the bare secret via sed.
      clan.core.vars.generators.synapse-registration-shared-secret = {
        files."shared-secret.yaml" = {
          neededFor = "services";
          owner = "matrix-synapse";
        };
        runtimeInputs = [
          pkgs.coreutils
          pkgs.pwgen
        ];
        script = ''
          SECRET=$(pwgen -s 32 1)
          echo "registration_shared_secret: \"$SECRET\"" > $out/shared-secret.yaml
        '';
      };

      # LiveKit and lk-jwt-service share this keyfile. Both upstream
      # modules run with DynamicUser=true and materialize the file via
      # LoadCredential into /run/credentials/<unit>/livekit-secrets, so
      # the generator MUST NOT set owner (the dynamic UID does not exist
      # at generator-run time).
      clan.core.vars.generators.livekit-keyfile = {
        files."keyfile" = {
          neededFor = "services";
        };
        runtimeInputs = [
          pkgs.coreutils
          pkgs.openssl
        ];
        script = ''
          # LiveKit keyfile format: `<api-key>: <secret>` on a single line.
          KEY=$(openssl rand -hex 8)
          SECRET=$(openssl rand -hex 32)
          echo "$KEY: $SECRET" > $out/keyfile
        '';
      };

      # coturn static-auth-secret (TURN REST auth model). coturn runs as
      # the static `turnserver` user so the generator binds owner=turnserver.
      clan.core.vars.generators.coturn-static-auth-secret = {
        files."secret" = {
          neededFor = "services";
          owner = "turnserver";
        };
        runtimeInputs = [
          pkgs.coreutils
          pkgs.openssl
        ];
        script = ''
          openssl rand -hex 32 > $out/secret
        '';
      };

      # Per-user matrix-password-<user> generators. Owned by matrix-synapse
      # because the register-users oneshot runs as User=matrix-synapse and
      # reads each password via systemd LoadCredential.
      imports = [
        {
          clan.core.vars.generators = lib.listToAttrs (
            map (u: {
              name = "matrix-password-${u}";
              value = {
                files."password" = {
                  neededFor = "services";
                  owner = "matrix-synapse";
                };
                runtimeInputs = [
                  pkgs.coreutils
                  pkgs.xkcdpass
                ];
                script = ''
                  xkcdpass -n 4 -d - > $out/password
                '';
              };
            }) matrixUsers
          );
        }
      ];

      ############################################################
      # Part 2: Synapse homeserver
      ############################################################

      services.matrix-synapse = {
        enable = true;
        settings = {
          server_name = domain;
          public_baseurl = "https://${domain}";

          listeners = [
            {
              port = synapsePort;
              bind_addresses = [ "127.0.0.1" ];
              type = "http";
              tls = false;
              x_forwarded = true;
              # Federation listener is intentionally omitted. The single
              # `client` resource exposes the Client-Server API only.
              resources = [
                {
                  names = [ "client" ];
                  compress = false;
                }
              ];
            }
          ];

          # Federation closure (defense-in-depth alongside the listener
          # surface above). Empty whitelist disables outbound federation.
          federation_domain_whitelist = [ ];

          # Phase-1 registration policy: the only legitimate caller of
          # registration is the systemd-oneshot below via shared secret.
          enable_registration = false;

          # Belt-and-suspenders against upstream-default drift: these declare the
          # safe values explicitly even when upstream Synapse already defaults to
          # them, so a future minor-version default change cannot silently flip
          # the posture for a public-internet homeserver.
          allow_guest_access = false;
          enable_registration_without_verification = false;

          # Enforce password policy on new accounts / password changes. Existing
          # passwords are grandfathered. Length-only (high-entropy passphrase
          # style) — character-class requirements provide weaker entropy/UX
          # tradeoff and are deliberately omitted.
          password_config.policy = {
            enabled = true;
            minimum_length = 12;
          };

          database = {
            name = "psycopg2";
            # allow_unsafe_locale must be at settings.database level, NOT
            # inside settings.database.args (cinnabar c62e9690f). Placing
            # it inside args produces psycopg2 ProgrammingError: invalid
            # connection option at startup. The option compensates for
            # ensureDatabases creating the database with the system
            # en_US.UTF-8 locale when Synapse expects C collation; text
            # sort order is irrelevant for this deployment.
            allow_unsafe_locale = true;
            args = {
              database = "matrix-synapse";
              user = "matrix-synapse";
              host = "/run/postgresql";
            };
          };

          # MSC4140 (delayed events) gates upcoming Element Call
          # features. Verify the precise required experimental_features
          # set against Element Call 0.18.0's release notes at deployment
          # time per the briefing's sharp-edges section.
          experimental_features = {
            msc4140_enabled = true;
          };

          # Rate limiting (defense against registration spam and login
          # brute-force on the public listener). Values mirror cinnabar
          # Phase-1 hardening.
          rc_message = {
            per_second = 0.5;
            burst_count = 10;
          };
          rc_registration = {
            per_second = 0.17;
            burst_count = 3;
          };
          rc_login = {
            address = {
              per_second = 0.17;
              burst_count = 3;
            };
            account = {
              per_second = 0.17;
              burst_count = 3;
            };
            failed_attempts = {
              per_second = 0.17;
              burst_count = 3;
            };
          };
        };

        # Shared secret YAML overlay (Synapse merges keys from each file).
        extraConfigFiles = [
          config.clan.core.vars.generators.synapse-registration-shared-secret.files."shared-secret.yaml".path
        ];
      };

      ############################################################
      # Part 3: PostgreSQL additions (shared instance, auto-merged)
      ############################################################

      # Auto-merges with the existing shared services.postgresql instance
      # configured by other modules (Gitea, Buildbot). Adds a database
      # owned by the static matrix-synapse user. allow_unsafe_locale
      # above accepts the system-locale database that ensureDBOwnership
      # creates.
      services.postgresql = {
        ensureDatabases = [ "matrix-synapse" ];
        ensureUsers = [
          {
            name = "matrix-synapse";
            ensureDBOwnership = true;
          }
        ];
      };

      ############################################################
      # Part 4: MatrixRTC backend (LiveKit + lk-jwt-service)
      ############################################################

      services.livekit = {
        enable = true;
        # Same keyfile path as lk-jwt-service below.
        keyFile = config.clan.core.vars.generators.livekit-keyfile.files."keyfile".path;
        # Opens TCP main port (7880 by default) and the UDP RTC range
        # (50000-51000 by default) in the firewall.
        openFirewall = true;
      };

      services.lk-jwt-service = {
        enable = true;
        port = lkJwtPort;
        livekitUrl = "wss://${domain}/livekit/sfu";
        # SAME path as services.livekit.keyFile above. The single key
        # pair is shared between the SFU and the JWT issuer; do not
        # generate two keys.
        keyFile = config.clan.core.vars.generators.livekit-keyfile.files."keyfile".path;
      };

      ############################################################
      # Part 5: coturn TURN/STUN relay
      ############################################################

      services.coturn = {
        enable = true;
        use-auth-secret = true;
        static-auth-secret-file =
          config.clan.core.vars.generators.coturn-static-auth-secret.files."secret".path;
        realm = domain;

        # Relay UDP range 49152-49999 to avoid colliding with LiveKit's
        # default RTC range 50000-51000. coturn default min-port is
        # already 49152; explicit max-port keeps the upper bound below
        # the LiveKit range.
        min-port = 49152;
        max-port = 49999;

        # TLS material from ACME for the homeserver vhost (coturn
        # advertises turns: over 5349).
        cert = "${config.security.acme.certs.${domain}.directory}/fullchain.pem";
        pkey = "${config.security.acme.certs.${domain}.directory}/key.pem";
      };

      ############################################################
      # Part 6: ACME wiring for coturn + nginx key access
      ############################################################

      # ACME-issued key material defaults to mode 0640 owned by acme:acme.
      # Granting group=turnserver lets the static coturn user read the
      # private key. nginx also terminates TLS for the matrix vhost and
      # must read the same cert; adding nginx to the turnserver group
      # satisfies the mk-cert-ownership-assertion check (nixpkgs requires
      # every consuming service's user to be a member of cert.group).
      # reloadServices wires coturn explicitly; nginx.service is
      # auto-appended by services.nginx for any ACME-managed vhost
      # (nixpkgs nginx/default.nix acmePairs), so do not re-add it here.
      security.acme.certs.${domain} = {
        group = "turnserver";
        reloadServices = [ "coturn.service" ];
      };

      users.users.nginx.extraGroups = [ "turnserver" ];

      ############################################################
      # Part 7: Firewall
      ############################################################

      # coturn UDP+TCP on 3478 (STUN/TURN) and 5349 (TURNS/STUN-TLS);
      # relay UDP range 49152-49999. nginx 80/443 are opened by
      # magnetite's host-level firewall block. LiveKit firewall is opened
      # by services.livekit.openFirewall above.
      networking.firewall = {
        allowedTCPPorts = [
          3478
          5349
        ];
        allowedUDPPorts = [
          3478
          5349
        ];
        allowedUDPPortRanges = [
          {
            from = 49152;
            to = 49999;
          }
        ];
      };

      ############################################################
      # Part 8: nginx vhost (single-vhost composition)
      ############################################################

      services.nginx.virtualHosts.${domain} = {
        enableACME = true;
        forceSSL = true;
        locations = {
          # Element Call SPA at the site root.
          "/" = {
            root = "${elementCallConfig}";
            tryFiles = "$uri $uri/ /index.html";
          };

          # Synapse Client-Server API.
          "/_matrix" = {
            proxyPass = "http://127.0.0.1:${toString synapsePort}";
          };
          "/_synapse" = {
            proxyPass = "http://127.0.0.1:${toString synapsePort}";
          };

          # lk-jwt-service: clients POST here to obtain LiveKit room JWTs.
          # Trailing slash on both sides preserves the path remainder.
          "/livekit/jwt/" = {
            proxyPass = "http://127.0.0.1:${toString lkJwtPort}/";
          };

          # LiveKit SFU WebSocket endpoint. The JS SDK appends /rtc,
          # /rtc/v1, /rtc/validate, /rtc/v1/validate to the base
          # livekitUrl (see livekit pkg/service/rtcservice.go:90-93),
          # so the rewrite strips the /livekit/sfu prefix to deliver
          # those paths intact to the LiveKit mux.
          "/livekit/sfu" = {
            proxyPass = "http://127.0.0.1:${toString config.services.livekit.settings.port}";
            recommendedProxySettings = true;
            proxyWebsockets = true;
            extraConfig = ''
              rewrite ^/livekit/sfu/(.*)$ /$1 break;
            '';
          };

          # Literal-JSON discovery endpoints. Served by nginx (NOT
          # Synapse) so the .well-known surface stays independent of
          # Synapse uptime and so MSC4143 rtc_foci can be advertised.
          "= /.well-known/matrix/server" = {
            extraConfig = ''
              default_type application/json;
              add_header Access-Control-Allow-Origin *;
              return 200 '${wellKnownServer}';
            '';
          };
          "= /.well-known/matrix/client" = {
            extraConfig = ''
              default_type application/json;
              add_header Access-Control-Allow-Origin *;
              return 200 '${wellKnownClient}';
            '';
          };
        };
      };

      ############################################################
      # Part 9: register-users systemd-oneshot (mag-13)
      ############################################################

      # Idempotent user provisioning. The --exists-ok flag (cinnabar
      # fcb49967e) is required for re-runs: without it the second
      # invocation fails with "User already exists". The shared secret
      # arrives as a systemd credential (LoadCredential) so the script
      # can run as the matrix-synapse user without privileged access to
      # the clan-vars sops backend.
      systemd.services.matrix-synapse-register-users = {
        description = "Provision Matrix Synapse users (idempotent, shared-secret)";
        after = [ "matrix-synapse.service" ];
        requires = [ "matrix-synapse.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "matrix-synapse";
          Group = "matrix-synapse";
          LoadCredential = [
            "shared-secret:${
              config.clan.core.vars.generators.synapse-registration-shared-secret.files."shared-secret.yaml".path
            }"
          ]
          ++ map (
            u: "${u}-pw:${config.clan.core.vars.generators."matrix-password-${u}".files."password".path}"
          ) matrixUsers;
        };
        path = [
          pkgs.curl
          pkgs.coreutils
          pkgs.gnused
          config.services.matrix-synapse.package
        ];
        script = ''
          set -euo pipefail

          # Wait for Synapse readiness via the public health endpoint.
          for i in $(seq 1 60); do
            if curl -fsS "http://localhost:${toString synapsePort}/_matrix/client/versions" >/dev/null 2>&1; then
              break
            fi
            if [ "$i" -eq 60 ]; then
              echo "matrix-synapse did not become ready within 120s" >&2
              exit 1
            fi
            sleep 2
          done

          # Extract the bare secret from the registration_shared_secret YAML.
          SHARED_SECRET=$(sed -n 's/^registration_shared_secret: "\(.*\)"$/\1/p' "$CREDENTIALS_DIRECTORY/shared-secret")

          ${lib.concatMapStringsSep "\n" (u: ''
            register_new_matrix_user \
              --exists-ok \
              --admin \
              --user ${u} \
              --password "$(cat "$CREDENTIALS_DIRECTORY/${u}-pw")" \
              --shared-secret "$SHARED_SECRET" \
              "http://localhost:${toString synapsePort}"
          '') matrixUsers}
        '';
      };
    };
}
