# Matrix homeserver for magnetite
#
# Composes a full Matrix homeserver stack on the public hostname
# matrix.scientistexperience.net using direct nixpkgs services:
#
#   - matrix-synapse: federated-disabled Synapse with rate-limiting and
#     OIDC-only authentication via kanidm
#   - livekit + lk-jwt-service: MatrixRTC backend for Element Call,
#     sharing a single keyfile
#   - coturn: TURN/STUN relay for NAT-traversal fallback
#   - element-call SPA: Element Call web client served as static assets
#     with a runtime-substituted config.json
#   - nginx vhost: single-vhost composition serving SPA at /, Synapse
#     APIs at /_matrix and /_synapse, lk-jwt-service at /livekit/jwt,
#     and literal-JSON .well-known/matrix/{server,client} for client
#     discovery and MSC4143 rtc_foci advertisement
#
# Password authentication and shared-secret user provisioning have been
# removed. The legacy rail consisted of:
#   - clan.core.vars.generators.synapse-registration-shared-secret
#   - clan.core.vars.generators.matrix-password-<user> (per-user)
#   - systemd.services.matrix-synapse-register-users (oneshot)
#   - services.matrix-synapse.extraConfigFiles entry for the shared secret
# These were retired in a single deploy together with
# password_config.enabled = false. Admin recovery for SSO breakage now
# goes via the synapse admin API
# (POST /_synapse/admin/v1/reset_password/<user>) which does not depend
# on the retired clan-vars secrets.
#
# clan-vars generators are declared inline within this module per the
# gitea.nix/buildbot.nix four-part dendritic pattern. The coturn
# generator binds owner to the static service user; the LiveKit
# keyfile generator omits owner because both LiveKit and lk-jwt-service
# run with DynamicUser=true and the upstream modules materialize the
# secret via LoadCredential internally.
#
# Sharp edges honored:
#   - allow_unsafe_locale at settings.database level (not args)
#     per cinnabar c62e9690f.
#   - coturn relay range 49152-49999 to avoid LiveKit's default
#     50000-51000 RTC range.
#   - ACME group=turnserver + reloadServices=[coturn.service] so coturn
#     can read the renewed key.
#   - LiveKit and lk-jwt-service share the SAME keyfile path.
#   - .well-known/matrix/client served by nginx (not Synapse) with
#     org.matrix.msc4143.rtc_foci pointing at the LiveKit SFU URL.
#   - Federation closed at the nginx layer: the synapse listener mounts
#     both `client` and `federation` resources on localhost, but nginx
#     exposes only the exact-match `/_matrix/federation/v1/openid/userinfo`
#     endpoint (required by lk-jwt-service for Element Call OpenID token
#     validation). All other `/_matrix/federation/` paths return 404,
#     federation_domain_whitelist = [ ], enable_registration = false,
#     password_config.enabled = false (OIDC-only via kanidm).
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
              # Both `client` and `federation` resources are mounted on this
              # single localhost listener. Public exposure of federation is
              # gated at the nginx layer: only the OpenID userinfo endpoint
              # is allowed through, which lk-jwt-service requires to validate
              # Element Call participants. All other federation paths are
              # denied at nginx, preserving the federation-closed posture
              # while unblocking Element Call.
              resources = [
                {
                  names = [
                    "client"
                    "federation"
                  ];
                  compress = false;
                }
              ];
            }
          ];

          # Federation closure (defense-in-depth alongside the listener
          # surface above). Empty whitelist disables outbound federation.
          federation_domain_whitelist = [ ];

          # Registration policy: account creation flows exclusively through
          # OIDC SSO (kanidm IdP). The shared-secret registration oneshot
          # has been retired.
          enable_registration = false;

          # Belt-and-suspenders against upstream-default drift: these declare the
          # safe values explicitly even when upstream Synapse already defaults to
          # them, so a future minor-version default change cannot silently flip
          # the posture for a public-internet homeserver.
          allow_guest_access = false;
          enable_registration_without_verification = false;

          # Password authentication is disabled. Authentication is OIDC-only
          # via the kanidm IdP; password rotation and the shared-secret
          # registration oneshot have been retired. Admin recovery for SSO
          # breakage goes via POST /_synapse/admin/v1/reset_password/<user>,
          # which does not depend on the retired clan-vars secrets.
          password_config = {
            enabled = false;
            # Policy block is retained for defense-in-depth: if a future
            # operator re-enables password auth, these constraints take
            # effect immediately on new accounts and password changes.
            policy = {
              enabled = true;
              minimum_length = 12;
            };
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
          # time.
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

          # OIDC provider wiring — kanidm IdP.
          #
          # The client_secret_path consumes a credential populated by
          # LoadCredential below from the kanidm-oauth2-synapse clan-vars
          # generator declared in modules/nixos/kanidm.nix.
          #
          # `issuer` is the per-client OIDC discovery URL
          # (https://accounts.../oauth2/openid/<clientId>), NOT the kanidm root.
          # `client_id` must match the kanidm OAuth2 client name declared in
          # kanidm.nix.
          #
          # `pkce_method = "always"` follows the defelo-nixos reference shape.
          # `localpart_template = "{{ user.preferred_username }}"` is paired
          # with `preferShortUsername = true` on the kanidm client.
          #
          # `allow_existing_users = true` enables binding the OIDC `sub` claim
          # to the existing local @cameron MXID on first SSO sign-in,
          # preserving rooms, history, and E2EE device sessions. The flag is
          # inert until a kanidm person with matching account_name exists and a
          # browser SSO sign-in occurs.
          oidc_providers = [
            {
              idp_id = "kanidm";
              idp_name = "Matrix SSO";
              issuer = "https://accounts.scientistexperience.net/oauth2/openid/synapse";
              client_id = "synapse";
              client_secret_path = "/run/credentials/matrix-synapse.service/oidc-secret";
              pkce_method = "always";
              scopes = [
                "openid"
                "profile"
                "email"
              ];
              user_mapping_provider.config = {
                localpart_template = "{{ user.preferred_username }}";
                display_name_template = "{{ user.name }}";
                email_template = "{{ user.email }}";
              };
              allow_existing_users = true;
            }
          ];
        };
      };

      ############################################################
      # Part 2b: Synapse systemd unit extensions for OIDC
      ############################################################

      # LoadCredential delivers the OIDC client secret as a one-shot snapshot
      # at unit-start into /run/credentials/matrix-synapse.service/oidc-secret,
      # matching the `client_secret_path` set in oidc_providers above.
      #
      # The source clan-vars generator (modules/nixos/kanidm.nix) declares
      # `restartUnits = [ "matrix-synapse.service" ]` so secret rotations
      # automatically trigger a unit restart, defeating the LoadCredential
      # snapshot-staleness invariant (memory reference:
      # reference_loadcredential-snapshot-staleness).
      #
      # preStart curl-polls the kanidm root before synapse starts, mitigating
      # the synapse-boots-before-kanidm startup race. Pattern is the
      # defelo-nixos reference at
      # ~/projects/nix-workspace/defelo-nixos/hosts/srv/matrix/synapse.nix
      # lines 97-103, adapted to the magnetite hostname.
      systemd.services.matrix-synapse = {
        serviceConfig.LoadCredential = [
          "oidc-secret:${config.clan.core.vars.generators.kanidm-oauth2-synapse.files."secret".path}"
        ];
        preStart = ''
          while ! ${lib.getExe pkgs.curl} -sL -o/dev/null --fail https://accounts.scientistexperience.net; do
            echo "waiting for kanidm at https://accounts.scientistexperience.net"
            sleep 1
          done
        '';
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
          # Selectively expose ONLY the federation OpenID userinfo endpoint
          # (required by lk-jwt-service to validate Element Call OpenID
          # tokens issued via /openid/request_token). All other federation
          # paths are denied below. nginx longest-prefix/exact-match rules
          # ensure the exact-match wins over the deny-prefix.
          "= /_matrix/federation/v1/openid/userinfo" = {
            proxyPass = "http://127.0.0.1:${toString synapsePort}";
          };
          "/_matrix/federation/" = {
            extraConfig = "return 404;";
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

    };
}
