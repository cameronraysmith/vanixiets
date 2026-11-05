# Perses dashboard service (design D2 to D10).
#
# flake.lib.persesServingFailures is the one predicate over the serving
# configuration (design D10): it returns one failure string per violated
# clause, each prefixed with the clause's number. The module asserts it over
# the host's own values, and checks.x86_64-linux.perses-config judges it
# over a literal valid input and one mutant per clause without evaluating a
# NixOS configuration.
#
# Site-neutral and free of clan vars, as modules/nixos/greptimedb.nix is, so
# the container test imports it with its own credentials: the host supplies
# the three LoadCredential entries and the Kanidm client the predicate reads.
{ config, lib, ... }:
let
  flakeLib = config.flake.lib;
  credsDir = "/run/credentials/perses.service";
  issuer = "https://accounts.scientistexperience.net/oauth2/openid/perses";
  redirectUri = "https://obs.scientistexperience.net/api/auth/providers/oidc/kanidm/callback";
  storeUrls = [
    "http://127.0.0.1:4000/v1/prometheus"
    "http://127.0.0.1:4000"
  ];
  allowHeaders = [
    "Accept"
    "Accept-Encoding"
    "Content-Type"
    "Content-Length"
    "User-Agent"
    "x-greptime-db-name"
  ];
  wipe = "rm -rf /var/lib/perses/db /var/lib/perses/plugins";
  strip = ''proxy_set_header x-greptime-auth "";'';

  persesServingFailures =
    {
      settings,
      listenAddress,
      port,
      unit,
      vhost,
      client,
      resources,
    }:
    let
      sec = settings.security or { };
      authn = sec.authentication or { };
      providers = authn.providers or { };
      oidc = providers.oidc or [ ];
      provider = lib.head oidc;

      # Seconds of a Go duration written as <n>s, <n>m or <n>h; null otherwise,
      # so an unparsed value fails the bound rather than passing it.
      seconds =
        d:
        let
          m = if lib.isString d then builtins.match "([0-9]+)([smh])" d else null;
        in
        if m == null then
          null
        else
          lib.toInt (lib.head m)
          * {
            s = 1;
            m = 60;
            h = 3600;
          }
          .${lib.elemAt m 1};
      refresh = seconds (authn.refresh_token_ttl or null);
      access = seconds (authn.access_token_ttl or null);

      # Bytes of a systemd memory value written as <n>, <n>K, <n>M, <n>G or <n>T
      # (base 1024); null otherwise.
      bytes =
        v:
        let
          m = builtins.match "([0-9]+)([KMGT]?)" (toString v);
        in
        if v == null || m == null then
          null
        else
          lib.toInt (lib.head m)
          * {
            "" = 1;
            K = 1024;
            M = 1024 * 1024;
            G = 1024 * 1024 * 1024;
            T = 1024 * 1024 * 1024 * 1024;
          }
          .${lib.elemAt m 1};
      memMax = bytes (unit.serviceConfig.MemoryMax or null);
      memHigh = bytes (unit.serviceConfig.MemoryHigh or null);

      ofKind = kind: lib.filter (r: (r.kind or null) == kind) resources;
      secrets = ofKind "GlobalSecret";
      datasources = ofKind "GlobalDatasource";
      proxyOf = r: r.spec.plugin.spec.proxy.spec or { };

      credentialIds = map (c: lib.head (lib.splitString ":" c)) (
        lib.toList (unit.serviceConfig.LoadCredential or [ ])
      );
      secretFiles = [
        (sec.encryption_key_file or null)
      ]
      ++ map (p: p.client_secret_file or null) oidc
      ++ map (s: s.spec.basicAuth.passwordFile or null) secrets;
      badSecretFiles = lib.filter (
        f: !(lib.isString f && lib.hasPrefix "${credsDir}/" f && lib.elem (baseNameOf f) credentialIds)
      ) secretFiles;

      badDatasources = lib.filter (
        r:
        let
          p = proxyOf r;
          endpoints = p.allowedEndpoints or [ ];
        in
        !(
          lib.elem (p.url or null) storeUrls
          && (p.headers or { }) == { "x-greptime-db-name" = "fleet"; }
          && (p.secret or null) == "greptimedb-perses"
          && (p.allowHeaders or null) == allowHeaders
          && endpoints != [ ]
          && lib.all (
            e:
            lib.elem (e.method or null) [
              "GET"
              "POST"
            ]
            && builtins.match "\\^.*\\$" (e.endpointPattern or "") != null
          ) endpoints
        )
      ) datasources;

      locations = vhost.locations or { };
      root = locations."/" or { };
      metrics = locations."= /metrics" or { };

      fail =
        clause: ok: message:
        lib.optional (!ok) "${toString clause}: ${message}";
    in
    lib.concatLists [
      (fail 1 (
        lib.hasPrefix "127." listenAddress && port != 8080
      ) "Perses listens on '${listenAddress}:${toString port}', not on loopback away from 8080")
      (fail 2 (sec.readonly or false) "security.readonly must be true")
      (fail 2 (sec.enable_auth or false) "security.enable_auth must be true")
      (fail 2 (sec.cookie.secure or false) "security.cookie.secure must be true")
      (fail 2 ((providers.enable_native or true) == false) "native login must be disabled")
      (fail 2 (authn.disable_sign_up or false) "sign-up must be disabled")
      (fail 2 (
        refresh != null && access != null && refresh + access <= 3600
      ) "refresh_token_ttl plus access_token_ttl must be set as <n>s, <n>m or <n>h and total at most 1h")
      (fail 3 (lib.length oidc == 1) "exactly one OIDC provider must be configured")
      # Only once there is exactly one provider, so an empty list is reported
      # once rather than also forcing its head.
      (fail 3 (
        lib.length oidc != 1
        || (
          (provider.issuer or null) == issuer
          && (provider.redirect_uri or null) == redirectUri
          && !(provider.disable_pkce or false)
        )
      ) "the OIDC provider must have issuer ${issuer}, redirect_uri ${redirectUri} and PKCE enabled")
      (fail 3 (
        lib.toList (client.originUrl or [ ]) == [ redirectUri ]
      ) "the Kanidm client's originUrl must be ${redirectUri}")
      (fail 4 (
        (sec.secret_file_allowed_directories or null) == [ credsDir ]
      ) "secret_file_allowed_directories must be exactly [ ${credsDir} ]")
      (fail 4 (badSecretFiles == [ ])
        "secret files ${builtins.toJSON badSecretFiles} are not credentials of perses.service under ${credsDir}"
      )
      (fail 5 (
        (settings.datasource.proxy.allowed_networks or null) == [ "127.0.0.0/8" ]
      ) "datasource.proxy.allowed_networks must be exactly [ 127.0.0.0/8 ]")
      (fail 6 (lib.all (g: (g.actions or null) == [ "read" ]) (
        sec.authorization.provider.native.guest_permissions or [ ]
      )) "a guest permission allows an action other than read")
      (fail 7 (badDatasources == [ ])
        "GlobalDatasources ${
          builtins.toJSON (map (r: r.metadata.name or "?") badDatasources)
        } differ in URL, header, secret, allowHeaders or anchored GET/POST endpoints"
      )
      (fail 8 (lib.all (
        r: !(r ? spec.basicAuth.password)
      ) resources) "a resource carries a literal basicAuth.password")
      (fail 8 (
        ofKind "Datasource" == [ ] && ofKind "Secret" == [ ]
      ) "a project Datasource or Secret is provisioned")
      (fail 9 (
        (vhost.forceSSL or false) && (vhost.enableACME or false)
      ) "the vhost must set forceSSL and enableACME")
      (fail 9
        (
          lib.attrNames locations == [
            "/"
            "= /metrics"
          ]
          && (root.proxyPass or null) == "http://127.0.0.1:${toString port}"
          && lib.hasInfix strip (root.extraConfig or "")
          && toString (metrics.return or "") == "404"
        )
        "the vhost must hold only / proxying to the listener with the x-greptime-auth strip and = /metrics returning 404"
      )
      (fail 10 (
        lib.attrNames (client.scopeMaps or { }) == [ "perses_users" ]
      ) "the client's scope maps must name only perses_users")
      (fail 11 (
        !(lib.hasPrefix "/run" (settings.plugin.path or "/run"))
      ) "plugin.path must lie outside /run")
      (fail 11 (lib.hasInfix wipe (unit.preStart or "")) "preStart must run '${wipe}'")
      (fail 11 (
        memMax != null && memHigh != null && memMax <= 268435456 && memHigh < memMax
      ) "MemoryMax must be at most 256M and MemoryHigh below it")
    ];
in
{
  flake.lib.persesServingFailures = persesServingFailures;

  flake.modules.nixos.perses =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.vanixiets.perses;
      domain = "obs.scientistexperience.net";
      port = 8095;
      # Copied by content, so the configuration and the restart trigger change
      # only when a resource file does, not with every commit of the flake.
      resources = builtins.path {
        path = ./perses/resources;
        name = "perses-resources";
      };
      curated = flakeLib.persesCuratedArchives pkgs pkgs.perses-bin;
      servingFailures = persesServingFailures {
        inherit (config.services.perses) settings listenAddress port;
        unit = config.systemd.services.perses;
        vhost = config.services.nginx.virtualHosts.${domain};
        client = config.services.kanidm.provision.systems.oauth2.perses or { };
        resources = map (f: lib.importJSON (resources + "/${f}")) (
          lib.attrNames (builtins.readDir resources)
        );
      };
    in
    {
      options.vanixiets.perses.acceptedServingFailures = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          The failures of flake.lib.persesServingFailures this host accepts,
          compared for equality. Only the container test sets it, to the
          failures its native login, its lack of a provider and plain HTTP
          explain; every other clause still holds there.
        '';
      };

      config = {
        services.perses = {
          enable = true;
          package = pkgs.perses-bin;
          listenAddress = "127.0.0.1";
          inherit port;
          settings = {
            security = {
              enable_auth = true;
              readonly = true;
              cookie.secure = true;
              encryption_key_file = "${credsDir}/encryption-key";
              secret_file_allowed_directories = [ credsDir ];
              authentication = {
                disable_sign_up = true;
                # A refresh issues an access token valid from the refresh and
                # keeps the refresh token, so a removed member keeps access for
                # at most the sum, 1 h.
                refresh_token_ttl = "45m";
                access_token_ttl = "15m";
                providers = {
                  enable_native = false;
                  oidc = [
                    {
                      slug_id = "kanidm";
                      name = "Kanidm";
                      client_id = "perses";
                      client_secret_file = "${credsDir}/kanidm-client-secret";
                      inherit issuer;
                      # Set rather than derived from forwarded headers.
                      redirect_uri = redirectUri;
                      scopes = [
                        "openid"
                        "profile"
                        "email"
                      ];
                    }
                  ];
                };
              };
              # The older security.authorization.guest_permissions is
              # deprecated and warns at every start.
              authorization.provider.native.guest_permissions = [
                {
                  actions = [ "read" ];
                  scopes = [
                    "Dashboard"
                    "Project"
                    "Folder"
                    "GlobalDatasource"
                    "Datasource"
                    "Variable"
                    "GlobalVariable"
                  ];
                }
              ];
            };
            datasource.proxy.allowed_networks = [ "127.0.0.0/8" ];
            database.file = {
              folder = "/var/lib/perses/db";
              extension = "json";
            };
            provisioning.folders = [ "${resources}" ];
            # On disk rather than the default /run/perses/plugins, whose tmpfs
            # would count the unpacked plugins against the unit's memory.
            plugin = {
              path = "/var/lib/perses/plugins";
              archive_paths = [ "${curated}" ];
            };
          };
        };

        systemd.services.perses = {
          # Perses exits when OIDC discovery fails at start, so it waits for
          # Kanidm and keeps retrying without a start limit.
          after = [
            "kanidm.service"
            "greptimedb.service"
          ];
          wants = [
            "kanidm.service"
            "greptimedb.service"
          ];
          restartTriggers = [ resources ];
          # Provisioning creates and updates but never deletes, and Perses
          # loads every plugin directory it finds, so each start begins from an
          # empty database and extracts only the curated archives.
          preStart = lib.mkBefore "${wipe}\n";
          unitConfig.StartLimitIntervalSec = 0;
          serviceConfig = {
            MemoryHigh = "192M";
            MemoryMax = "256M";
            MemorySwapMax = 0;
            Restart = lib.mkForce "always";
            RestartSec = "10s";
            # Above the store's 500 and below the evaluator's 900, so under
            # host exhaustion the kernel kills the evaluator, then Perses,
            # then the store.
            OOMScoreAdjust = 600;
          };
        };

        services.nginx.virtualHosts.${domain} = {
          forceSSL = true;
          enableACME = true;
          # The store reads x-greptime-auth before Authorization; nginx drops a
          # header set to the empty string.
          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString port}";
            extraConfig = strip;
          };
          # Perses serves its own metrics on the listener without a session.
          locations."= /metrics".return = "404";
        };

        assertions = [
          {
            assertion = servingFailures == cfg.acceptedServingFailures;
            message = "perses: ${lib.concatStringsSep "; " servingFailures}";
          }
        ];
      };
    };
}
