# Reusable shared kanidm-OIDC SSO gateway for magnetite web UIs.
#
# One bespoke `oauth2-proxy-kanidm` systemd unit (NOT buildbot's nixpkgs
# `services.oauth2-proxy` singleton, NOT a NixOS container) gates many nginx
# vhosts behind a single central auth surface at `auth.scientistexperience.net`,
# giving cross-subdomain single-login SSO. A consumer registers in three lines:
#
#   sso.services.<name> = {
#     domain = "<svc>.scientistexperience.net";
#     allowedGroups = [ "<svc>_access" ];
#     upstream = { "/" = "http://127.0.0.1:3000"; "/api/" = "http://[..]:9270"; };
#   };
#
# and the module auto-derives every kanidm provisioning addition (group stub,
# per-group scopeMaps, claimMaps.groups) from the union of all registered
# services' allowedGroups onto one shared `sso-gateway` kanidm client.
#
# Use this gateway for services that have no OIDC of their own — it terminates
# auth in front of an opaque upstream. A service with built-in OIDC should
# instead register a direct per-service kanidm client (see kanidm.nix's
# `services.kanidm.provision.systems.oauth2.synapse`) and authenticate natively,
# bypassing the gateway; routing such a service through `sso.services.*` would
# double-gate it.
#
# Realizes openspec/changes/sso-gateway/{design.md,specs/sso-gateway/spec.md}:
#   D1 bespoke unit; D2 central auth subdomain + static client; D3 domain-wide
#   cookie; D4 distinct cookie name `_sso_gateway` (buildbot non-interference);
#   D5 per-group scopeMaps + claimMaps.groups (new vs synapse); D6 reusable
#   registration auto-deriving the kanidm config; D7 per-vhost group auth via
#   query-param allowed_groups with browser-vs-API 401 split; D8 clan-vars
#   secrets via LoadCredential with restart-on-rotation.
#
# The browser-vs-API 401 split (D7) is keyed by the upstream location path: a
# location under `/api` fails fast with `error_page 401 =401;` (API clients
# cannot follow an interactive redirect), while every other location redirects a
# 401 to the sign-in flow (browser UIs). This keeps the consumer footprint at
# `upstream = attrsOf str` (location -> proxyPass) per the spec.
#
# Tradeoff (D5, recorded): one shared kanidm client weakens per-service OAuth
# isolation relative to per-service clients — a single client secret and a single
# token audience span every gated service. Accepted as the cost of shared-gateway
# SSO and simplicity; per-service clients would restore isolation but reintroduce
# per-consumer kanidm edits and fragment login.
{
  flake.modules.nixos.sso-gateway =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.sso;

      # The union of every registered service's authorized groups. Each distinct
      # group becomes a kanidm group stub, a scopeMap entry, and a claimMap entry
      # on the one shared client (D6). The auto-derivation emits the stub and its
      # scopeMap together so the kanidm.nix:876 referential-integrity ordering
      # (group declared in entitiesByName before any scopeMap references it) holds.
      allGroups = lib.unique (lib.concatMap (svc: svc.allowedGroups) (lib.attrValues cfg.services));

      clientSecretPath = config.clan.core.vars.generators.kanidm-oauth2-sso.files.secret.path;
      cookieSecretPath = config.clan.core.vars.generators.sso-cookie-secret.files.secret.path;

      # nginx auth_request cannot pass arguments to its subrequest, so the
      # service's authorized groups travel as a query parameter on the internal
      # /oauth2/auth location (D7). The single shared oauth2-proxy admits only
      # members of these groups for this vhost.
      allowedGroupsArg =
        svc:
        lib.optionalString (svc.allowedGroups != [ ]) (
          "?allowed_groups=${lib.concatStringsSep "," (map lib.escapeURL svc.allowedGroups)}"
        );

      # API location paths (under /api) must fail a 401 fast with a clean status
      # rather than an interactive HTML redirect to sign-in (D7). Everything else
      # is a browser UI that should be redirected to the sign-in flow.
      isApiLocation = path: lib.hasPrefix "/api" path;

      perServiceVhost =
        name: svc:
        lib.nameValuePair svc.domain {
          forceSSL = true;
          enableACME = true;

          # Vhost-level auth_request wiring shared by every browser location: a
          # 401 is sent to the named sign-in redirect, and the authenticated
          # user/email are surfaced to upstreams via auth_request_set (requires
          # the gateway's --set-xauthrequest).
          extraConfig = ''
            auth_request /oauth2/auth;
            error_page 401 = @sso_signin;

            auth_request_set $user  $upstream_http_x_auth_request_user;
            auth_request_set $email $upstream_http_x_auth_request_email;
          '';

          locations =
            # The consumer's upstream map: each key is an nginx location, each
            # value a proxyPass target. API locations override the vhost-level
            # browser redirect with a fast 401.
            (lib.mapAttrs (path: target: {
              proxyPass = target;
              extraConfig = ''
                proxy_set_header X-User  $user;
                proxy_set_header X-Email $email;

                # TLS terminates here; the upstream sees a plaintext http
                # connection. Surface the external scheme so a scheme-aware
                # backend can build https absolute URLs. (srvos's
                # recommendedProxySettings already injects this same header
                # http-wide; re-asserting it keeps the contract local to the
                # proxied location and independent of that default.)
                proxy_set_header X-Forwarded-Proto $scheme;

                # recommendedProxySettings sets `proxy_redirect off;` http-wide,
                # so a backend that ignores X-Forwarded-Proto (cognee's uvicorn
                # is started without --proxy-headers/FORWARDED_ALLOW_IPS) emits
                # its trailing-slash 307 Location as `http://<host>/...`, which
                # an https page cannot follow (mixed-content block). Rewrite any
                # http:// Location from the upstream back to https:// so the
                # redirect stays same-scheme. Re-enabling proxy_redirect for this
                # location overrides the inherited `off`.
                proxy_redirect ~^http://([^/]+)(/.*)$ https://$1$2;
              ''
              + lib.optionalString (isApiLocation path) ''
                error_page 401 = @sso_401;
              '';
            }) svc.upstream)
            // {
              # Internal auth subrequest target carrying this service's group
              # authorization as a query param. proxy_pass_request_body off
              # because nginx auth_request includes headers but not the body.
              "= /oauth2/auth" = {
                proxyPass = "http://${cfg.listenAddress}/oauth2/auth${allowedGroupsArg svc}";
                extraConfig = ''
                  internal;
                  proxy_set_header X-Original-URI $request_uri;
                  proxy_set_header Content-Length "";
                  proxy_pass_request_body         off;
                '';
              };

              # Unauthenticated browser requests land here and are bounced to the
              # central auth surface's sign-in flow, returning to the original URL.
              "@sso_signin" = {
                return = "302 https://${cfg.authDomain}/oauth2/start?rd=$scheme://$host$request_uri";
              };

              # API locations route their 401 here for a clean status. A bare
              # `error_page 401 =401;` is malformed (nginx parses `=401` as a URI
              # and replies `302 Location: =401`), so API clients need a named
              # location that simply returns 401.
              "@sso_401" = {
                return = "401";
              };
            };
        };

      # Each service with a portalCard emits an additional standalone public
      # (PKCE-enforced, secret-less) kanidm OAuth2 client `<name>-portal`. The
      # tile launches the service's own landing URL; its scopeMap is scoped to
      # the service's authorized group(s) so the tile is visible to exactly the
      # members the gateway admits. Public clients omit basicSecretFile (nixpkgs
      # assertion forbids it) and omit claimMaps entirely (the tile carries no
      # group claim; gateway admission, not the tile, gates the real service —
      # and an empty claimMap would trip the kanidm.nix:901 assertion).
      portalScopeGroups = svc: if svc.allowedGroups != [ ] then svc.allowedGroups else [ ];

      portalClients = lib.listToAttrs (
        lib.concatLists (
          lib.mapAttrsToList (
            name: svc:
            lib.optional (svc.portalCard != null) (
              lib.nameValuePair "${name}-portal" (
                {
                  public = true;
                  displayName = svc.portalCard.displayName;
                  originUrl = svc.portalCard.landingUrl;
                  originLanding = svc.portalCard.landingUrl;
                  scopeMaps = lib.genAttrs (portalScopeGroups svc) (_: [ "openid" ]);
                }
                // lib.optionalAttrs (svc.portalCard.imageFile != null) {
                  imageFile = svc.portalCard.imageFile;
                }
              )
            )
          ) cfg.services
        )
      );
    in
    {
      options.sso = {
        enable = lib.mkEnableOption "the shared kanidm-OIDC SSO gateway";

        authDomain = lib.mkOption {
          type = lib.types.str;
          default = "auth.scientistexperience.net";
          description = ''
            The central auth subdomain owning the single `/oauth2/` surface and
            the single kanidm redirect URI `https://<authDomain>/oauth2/callback`.
          '';
        };

        cookieDomain = lib.mkOption {
          type = lib.types.str;
          default = ".scientistexperience.net";
          description = ''
            The domain-wide cookie scope enabling cross-subdomain single-login
            SSO. Passed as `--cookie-domain` and `--whitelist-domain`.
          '';
        };

        cookieName = lib.mkOption {
          type = lib.types.str;
          default = "_sso_gateway";
          description = ''
            The gateway cookie name. Deliberately distinct from oauth2-proxy's
            default `_oauth2_proxy`, which buildbot uses as a host-only cookie; a
            domain-wide cookie under the default name would shadow buildbot's
            cookie and break buildbot auth (hard constraint, D4).
          '';
        };

        clientId = lib.mkOption {
          type = lib.types.str;
          default = "sso-gateway";
          description = "The shared kanidm OAuth2 client id (also the kanidm provision entity name).";
        };

        clientDisplayName = lib.mkOption {
          type = lib.types.str;
          default = "SSO";
          description = ''
            The kanidm apps-portal card label for the shared client
            (`oauth2_rs_displayname`). One shared client emits one card, so this
            single label applies regardless of how many services register.
          '';
        };

        landingUrl = lib.mkOption {
          type = lib.types.str;
          default = "https://${cfg.authDomain}/";
          description = ''
            The kanidm apps-portal card launch/landing URL
            (`oauth2_rs_origin_landing`). Independent of `originUrl` (the OAuth2
            callback), so changing it does not affect the auth flow.
          '';
        };

        clientImageFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = ''
            Optional apps-portal card image for the shared client
            (`oauth2_rs_image`). kanidm derives the MIME type from the file
            extension, so the path must end in one of .png/.jpg/.jpeg/.gif/.svg/.webp.
            Null leaves the card with no image.
          '';
        };

        rootRedirectUrl = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Optional 302 target for the auth subdomain root `/`. The auth vhost
            only defines the `/oauth2/` surface, so without this `/` falls through
            to the stock nginx welcome page (which is also where the shared "SSO"
            apps-portal card lands). When set, `/` returns a 302 to this URL —
            typically the kanidm apps portal — while `/oauth2/*` is unaffected
            (nginx longest-prefix keeps the callback/start/auth on the oauth2
            location). When null, `/` is left unhandled.
          '';
        };

        issuerUrl = lib.mkOption {
          type = lib.types.str;
          default = "https://accounts.scientistexperience.net/oauth2/openid/sso-gateway";
          description = "The kanidm OIDC issuer URL for the shared client (auto-discovery).";
        };

        listenAddress = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1:4181";
          description = "The loopback address the bespoke oauth2-proxy-kanidm unit listens on.";
        };

        services = lib.mkOption {
          default = { };
          description = ''
            Per-service registrations. Each entry emits a `forceSSL`+`enableACME`
            nginx vhost gated by the shared gateway and contributes its
            `allowedGroups` to the auto-derived kanidm provisioning. Register a
            service here only when it has no OIDC of its own; a service with
            built-in OIDC should instead define its own kanidm client (the
            `services.kanidm.provision.systems.oauth2` pattern in kanidm.nix) and
            authenticate natively rather than route through this gateway.
          '';
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                domain = lib.mkOption {
                  type = lib.types.str;
                  description = "The public FQDN of this gated service's vhost.";
                };
                allowedGroups = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  description = ''
                    kanidm groups authorized to access this service. The empty
                    list authorizes any authenticated user. Each distinct group
                    across all services is auto-derived into a kanidm group stub,
                    a scopeMap entry, and a claimMaps.groups entry on the shared
                    `sso-gateway` client.
                  '';
                };
                upstream = lib.mkOption {
                  type = lib.types.attrsOf lib.types.str;
                  description = ''
                    nginx `location` path -> `proxyPass` target. Locations under
                    `/api` fail a 401 fast (`error_page 401 =401;`); every other
                    location redirects a 401 to the sign-in flow (D7).
                  '';
                };
                portalCard = lib.mkOption {
                  default = null;
                  description = ''
                    Optional dedicated apps-portal tile for this service. When
                    set, emits an ADDITIONAL public (PKCE, no secret) kanidm
                    OAuth2 client `<name>-portal` whose card launches the
                    service's own landing URL, so each gated service gets its
                    own branded portal tile instead of sharing the single
                    `sso-gateway` card. Tile visibility is scoped to this
                    service's authorized group, matching gateway admission.
                  '';
                  type = lib.types.nullOr (
                    lib.types.submodule {
                      options = {
                        displayName = lib.mkOption {
                          type = lib.types.str;
                          description = "The apps-portal card label for this service's tile.";
                        };
                        landingUrl = lib.mkOption {
                          type = lib.types.str;
                          description = "The tile's launch/landing URL (also used as the dummy originUrl).";
                        };
                        imageFile = lib.mkOption {
                          type = lib.types.nullOr lib.types.path;
                          default = null;
                          description = ''
                            Optional tile image. Path must end in one of
                            .png/.jpg/.jpeg/.gif/.svg/.webp.
                          '';
                        };
                      };
                    }
                  );
                };
              };
            }
          );
        };
      };

      config = lib.mkIf cfg.enable {
        # OAuth2 client secret: openssl-random hex. Owned by kanidm:kanidm because
        # host-side kanidm-provision reads it directly (basicSecretFile) to upload
        # the basic_secret to the OAuth2 resource server; the gateway unit also
        # consumes it via LoadCredential (LoadCredential staging is root-side, so
        # the source ownership does not constrain the gateway side). restartUnits
        # names both real consumers: kanidm.service re-runs provision against the
        # new secret, oauth2-proxy-kanidm re-reads it via the unit-start
        # LoadCredential snapshot (memory: reference_loadcredential-snapshot-staleness).
        clan.core.vars.generators.kanidm-oauth2-sso = {
          files.secret = {
            secret = true;
            owner = "kanidm";
            group = "kanidm";
            mode = "0400";
            restartUnits = [
              "kanidm.service"
              "oauth2-proxy-kanidm.service"
            ];
          };
          runtimeInputs = [ pkgs.openssl ];
          # printf '%s' strips the trailing newline `openssl rand -hex 32 >` would
          # leave: kanidm-provision .trim()s the basic_secret it stores but
          # oauth2-proxy reads --client-secret-file verbatim, so a 65th newline
          # byte makes the presented secret mismatch kanidm's 64-char store and
          # fails the /oauth2/token exchange (401 -> oauth2-proxy 500 at callback).
          script = ''
            printf '%s' "$(openssl rand -hex 32)" > "$out/secret"
          '';
        };

        # Cookie secret: oauth2-proxy requires a 16/24/32-byte secret; 32 chosen.
        # base64-then-strip-to-32-alnum yields exactly 32 bytes of key material.
        # Consumed only by the gateway unit via LoadCredential; restartUnits names
        # it so a rotated cookie secret is not left stale behind the unit-start
        # snapshot.
        clan.core.vars.generators.sso-cookie-secret = {
          files.secret = {
            secret = true;
            mode = "0400";
            restartUnits = [ "oauth2-proxy-kanidm.service" ];
          };
          runtimeInputs = [ pkgs.openssl ];
          script = ''
            openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 32 > "$out/secret"
          '';
        };

        # The bespoke second oauth2-proxy instance (D1). buildbot owns the host's
        # one nixpkgs services.oauth2-proxy singleton (GitHub provider) and
        # oauth2-proxy cannot run two providers in one process (upstream #926), so
        # the kanidm gateway is a hand-rolled unit. Hand-rolling also lets us pass
        # --whitelist-domain, which the nixpkgs module does not expose (D3).
        systemd.services.oauth2-proxy-kanidm = {
          description = "kanidm-OIDC SSO gateway (oauth2-proxy)";
          wantedBy = [ "multi-user.target" ];
          after = [
            "network-online.target"
            "kanidm.service"
          ];
          wants = [
            "network-online.target"
            "kanidm.service"
          ];
          serviceConfig = {
            DynamicUser = true;
            RuntimeDirectory = "oauth2-proxy-kanidm";
            Restart = "always";
            RestartSec = "10s";
            LoadCredential = [
              "client-secret:${clientSecretPath}"
              "cookie-secret:${cookieSecretPath}"
            ];
            ExecStart = lib.concatStringsSep " " [
              (lib.getExe pkgs.oauth2-proxy)
              "--provider=oidc"
              "--oidc-issuer-url=${cfg.issuerUrl}"
              "--client-id=${cfg.clientId}"
              "--client-secret-file=%d/client-secret"
              "--cookie-secret-file=%d/cookie-secret"
              "--cookie-domain=${cfg.cookieDomain}"
              "--whitelist-domain=${cfg.cookieDomain}"
              "--cookie-name=${cfg.cookieName}"
              "--email-domain=*"
              "--reverse-proxy=true"
              "--trusted-proxy-ip=127.0.0.1"
              "--set-xauthrequest=true"
              "--code-challenge-method=S256"
              "--http-address=${cfg.listenAddress}"
              "--redirect-url=https://${cfg.authDomain}/oauth2/callback"
            ];
          };
        };

        # Auto-derived kanidm provisioning (D5, D6). Each distinct group becomes a
        # stub (members managed operationally, not declaratively, per the
        # synapse/matrix_users precedent), and the one shared client gains the
        # per-group scopeMaps plus claimMaps.groups so the token's `groups` claim
        # carries clean literal names that oauth2-proxy's allowed_groups match.
        services.kanidm.provision = {
          groups = lib.genAttrs allGroups (_: {
            members = [ ];
            overwriteMembers = false;
          });

          systems.oauth2 = {
            ${cfg.clientId} = {
              displayName = cfg.clientDisplayName;
              originUrl = "https://${cfg.authDomain}/oauth2/callback";
              originLanding = cfg.landingUrl;
              basicSecretFile = clientSecretPath;
              scopeMaps = lib.genAttrs allGroups (_: [
                "openid"
                "email"
                "profile"
              ]);
              # claimMaps.groups is a NEW requirement vs synapse (which uses none):
              # oauth2-proxy authorizes on literal group names in the token's
              # `groups` claim. Guarded against the empty-union case because the
              # nixpkgs kanidm assertion (kanidm.nix:~904) rejects a claimMap whose
              # valuesByGroup maps no group to a non-empty value list.
              claimMaps = lib.optionalAttrs (allGroups != [ ]) {
                groups = {
                  joinType = "array";
                  valuesByGroup = lib.genAttrs allGroups (g: [ g ]);
                };
              };
            }
            // lib.optionalAttrs (cfg.clientImageFile != null) {
              imageFile = cfg.clientImageFile;
            };
          }
          // portalClients;
        };

        services.nginx.virtualHosts = {
          # The central auth vhost (D2): the sole `/oauth2/` surface and the sole
          # redirect URI. Per-service vhosts only run auth_request against it.
          # When rootRedirectUrl is set, `/` 302s there (e.g. the kanidm apps
          # portal) instead of the stock nginx welcome page; `/oauth2/*` is
          # unaffected because nginx longest-prefix routing keeps the callback,
          # start, and auth subrequests on the `/oauth2/` location. No
          # auth_request guards `/` — it is a bare redirect, not a gated UI.
          ${cfg.authDomain} = {
            forceSSL = true;
            enableACME = true;
            locations = {
              "/oauth2/".proxyPass = "http://${cfg.listenAddress}";
            }
            // lib.optionalAttrs (cfg.rootRedirectUrl != null) {
              "/".return = "302 ${cfg.rootRedirectUrl}";
            };
          };
        }
        // lib.mapAttrs' perServiceVhost cfg.services;
      };
    };
}
