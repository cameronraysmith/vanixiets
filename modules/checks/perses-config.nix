# perses-config - the serving configuration is judged by one predicate.
#
# flake.lib.persesServingFailures (modules/nixos/perses.nix) is asserted over
# magnetite's own values in the module; this check judges the predicate
# itself without evaluating a NixOS configuration: a literal valid input,
# written here independently of the module, must pass, and at least one
# mutant per clause of design D10 must fail. Each mutant's name carries the
# clause number it targets, and the check requires the first failure it
# reports to be that clause's, so a mutant rejected for another reason does
# not count for its clause.
{ config, lib, ... }:
let
  credsDir = "/run/credentials/perses.service";
  allowHeaders = [
    "Accept"
    "Accept-Encoding"
    "Content-Type"
    "Content-Length"
    "User-Agent"
    "x-greptime-db-name"
  ];
  valid = {
    listenAddress = "127.0.0.1";
    port = 8095;
    settings = {
      security = {
        enable_auth = true;
        readonly = true;
        cookie.secure = true;
        encryption_key_file = "${credsDir}/encryption-key";
        secret_file_allowed_directories = [ credsDir ];
        authentication = {
          disable_sign_up = true;
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
                issuer = "https://accounts.scientistexperience.net/oauth2/openid/perses";
                redirect_uri = "https://obs.scientistexperience.net/api/auth/providers/oidc/kanidm/callback";
                scopes = [
                  "openid"
                  "profile"
                  "email"
                ];
              }
            ];
          };
        };
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
      plugin.path = "/var/lib/perses/plugins";
      database.file.folder = "/var/lib/perses/db";
    };
    unit = {
      serviceConfig = {
        LoadCredential = [
          "kanidm-client-secret:/run/secrets/k"
          "encryption-key:/run/secrets/e"
          "perses-password:/run/secrets/p"
        ];
        MemoryHigh = "192M";
        MemoryMax = "256M";
      };
      preStart = "rm -rf /var/lib/perses/db /var/lib/perses/plugins\n";
    };
    vhost = {
      forceSSL = true;
      enableACME = true;
      locations = {
        "/" = {
          proxyPass = "http://127.0.0.1:8095";
          extraConfig = ''proxy_set_header x-greptime-auth "";'';
        };
        "= /metrics" = {
          return = "404";
        };
      };
    };
    client = {
      originUrl = "https://obs.scientistexperience.net/api/auth/providers/oidc/kanidm/callback";
      scopeMaps.perses_users = [
        "openid"
        "profile"
        "email"
      ];
    };
    resources = [
      {
        kind = "GlobalSecret";
        metadata.name = "greptimedb-perses";
        spec.basicAuth = {
          username = "perses";
          passwordFile = "${credsDir}/perses-password";
        };
      }
      {
        kind = "GlobalDatasource";
        metadata.name = "greptimedb-promql";
        spec.plugin.spec.proxy.spec = {
          url = "http://127.0.0.1:4000/v1/prometheus";
          secret = "greptimedb-perses";
          headers."x-greptime-db-name" = "fleet";
          inherit allowHeaders;
          allowedEndpoints = [
            {
              method = "POST";
              endpointPattern = "^/api/v1/(query|query_range|labels|series)$";
            }
          ];
        };
      }
    ];
  };
  set = path: value: lib.recursiveUpdate valid (lib.setAttrByPath path value);
  mapProvider =
    f:
    set [ "settings" "security" "authentication" "providers" "oidc" ] (
      map f valid.settings.security.authentication.providers.oidc
    );
  mapResource =
    kind: f:
    valid
    // {
      resources = map (r: if r.kind == kind then f r else r) valid.resources;
    };
  mapDsSpec =
    f:
    mapResource "GlobalDatasource" (
      r: lib.recursiveUpdate r { spec.plugin.spec.proxy.spec = f r.spec.plugin.spec.proxy.spec; }
    );
  # Keyed "<clause>-<name>"; the clause is design D10's number.
  mutants = {
    "1-listenAll" = set [ "listenAddress" ] "";
    "1-port8080" = set [ "port" ] 8080;
    "2-notReadonly" = set [ "settings" "security" "readonly" ] false;
    "2-noAuth" = set [ "settings" "security" "enable_auth" ] false;
    "2-insecureCookie" = set [ "settings" "security" "cookie" "secure" ] false;
    "2-nativeLogin" = set [ "settings" "security" "authentication" "providers" "enable_native" ] true;
    "2-signUp" = set [ "settings" "security" "authentication" "disable_sign_up" ] false;
    "2-longRefresh" = set [ "settings" "security" "authentication" "refresh_token_ttl" ] "24h";
    "2-longAccess" = set [ "settings" "security" "authentication" "access_token_ttl" ] "30m";
    "2-unparsedTtl" = set [ "settings" "security" "authentication" "access_token_ttl" ] "15 minutes";
    "3-noProvider" = set [ "settings" "security" "authentication" "providers" "oidc" ] [ ];
    "3-pkceOff" = mapProvider (p: p // { disable_pkce = true; });
    "3-otherIssuer" = mapProvider (
      p: p // { issuer = "https://accounts.scientistexperience.net/oauth2/openid/omnigent"; }
    );
    "3-redirectElsewhere" = set [ "client" "originUrl" ] "https://omni.scientistexperience.net/cb";
    "4-keyOutside" = set [ "settings" "security" "encryption_key_file" ] "/var/lib/perses/key";
    "4-secretOutside" = mapProvider (p: p // { client_secret_file = "/etc/perses/client-secret"; });
    "4-passwordOutside" = mapResource "GlobalSecret" (
      r: lib.recursiveUpdate r { spec.basicAuth.passwordFile = "/nix/store/x-perses-password"; }
    );
    "4-secondAllowedDir" =
      set
        [ "settings" "security" "secret_file_allowed_directories" ]
        [
          credsDir
          "/etc"
        ];
    "4-notLoaded" =
      set
        [ "unit" "serviceConfig" "LoadCredential" ]
        [
          "kanidm-client-secret:/run/secrets/k"
          "perses-password:/run/secrets/p"
        ];
    "5-anyNetwork" = set [ "settings" "datasource" "proxy" "allowed_networks" ] [ "0.0.0.0/0" ];
    "6-guestWrites" =
      set
        [ "settings" "security" "authorization" "provider" "native" "guest_permissions" ]
        [
          {
            actions = [ "*" ];
            scopes = [ "Dashboard" ];
          }
        ];
    "7-unanchored" = mapDsSpec (_: {
      allowedEndpoints = [
        {
          method = "POST";
          endpointPattern = "/api/v1/query";
        }
      ];
    });
    "7-unanchoredEnd" = mapDsSpec (_: {
      allowedEndpoints = [
        {
          method = "POST";
          endpointPattern = "^/api/v1/query";
        }
      ];
    });
    "7-deleteMethod" = mapDsSpec (_: {
      allowedEndpoints = [
        {
          method = "DELETE";
          endpointPattern = "^/api/v1/series$";
        }
      ];
    });
    # Perses forwards every path of a datasource that lists no endpoints.
    "7-noEndpoints" = mapDsSpec (_: {
      allowedEndpoints = [ ];
    });
    "7-otherDatabase" = mapDsSpec (_: {
      headers."x-greptime-db-name" = "devloop";
    });
    "7-otherSecret" = mapDsSpec (_: {
      secret = "greptimedb-admin";
    });
    "7-storeElsewhere" = mapDsSpec (_: {
      url = "http://127.0.0.1:4006/v1/prometheus";
    });
    "7-portPrefix" = mapDsSpec (_: {
      url = "http://127.0.0.1:40001/v1/prometheus";
    });
    "7-noAllowHeaders" = mapResource "GlobalDatasource" (
      r: lib.recursiveUpdate r { spec.plugin.spec.proxy.spec.allowHeaders = null; }
    );
    "7-authAllowed" = mapDsSpec (_: {
      allowHeaders = allowHeaders ++ [ "x-greptime-auth" ];
    });
    "8-literalPassword" = mapResource "GlobalSecret" (
      r: lib.recursiveUpdate r { spec.basicAuth.password = "x"; }
    );
    "8-projectDatasource" = valid // {
      resources = valid.resources ++ [
        {
          kind = "Datasource";
          metadata = {
            name = "open";
            project = "fleet";
          };
          spec = { };
        }
      ];
    };
    "8-projectSecret" = valid // {
      resources = valid.resources ++ [
        {
          kind = "Secret";
          metadata = {
            name = "s";
            project = "fleet";
          };
          spec = { };
        }
      ];
    };
    "9-noTls" = set [ "vhost" "forceSSL" ] false;
    "9-noAcme" = set [ "vhost" "enableACME" ] false;
    "9-noStrip" = set [ "vhost" "locations" "/" "extraConfig" ] "";
    "9-otherUpstream" = set [ "vhost" "locations" "/" "proxyPass" ] "http://127.0.0.1:4000";
    "9-metricsOpen" = valid // {
      vhost = valid.vhost // {
        locations = removeAttrs valid.vhost.locations [ "= /metrics" ];
      };
    };
    "9-metricsServed" = set [ "vhost" "locations" "= /metrics" "return" ] "200";
    "9-extraLocation" = set [ "vhost" "locations" "/dashboard/" ] {
      proxyPass = "http://127.0.0.1:4000";
    };
    "10-secondGroup" = set [ "client" "scopeMaps" "cognee_access" ] [ "openid" ];
    "11-pluginsOnTmpfs" = set [ "settings" "plugin" "path" ] "/run/perses/plugins";
    "11-noWipe" = set [ "unit" "preStart" ] "";
    "11-noPluginWipe" = set [ "unit" "preStart" ] "rm -rf /var/lib/perses/db\n";
    "11-bigMemory" = set [ "unit" "serviceConfig" "MemoryMax" ] "1G";
    "11-highAtMax" = set [ "unit" "serviceConfig" "MemoryHigh" ] "256M";
  };
  clauseOf = name: lib.head (lib.splitString "-" name);
  failures = config.flake.lib.persesServingFailures;
  # The first failure a mutant draws must be its own clause's, numbered "<n>:".
  misjudged = lib.filterAttrs (
    n: m:
    let
      fs = failures m;
    in
    fs == [ ] || !(lib.any (f: lib.hasPrefix "${clauseOf n}: " f) fs)
  ) mutants;
  clausesCovered = lib.unique (map clauseOf (lib.attrNames mutants));
in
{
  perSystem =
    { pkgs, system, ... }:
    {
      # System-independent: the predicate is pure Nix, so it is emitted once.
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        perses-config =
          assert lib.assertMsg (
            failures valid == [ ]
          ) "perses-config: valid input failed: ${builtins.toJSON (failures valid)}";
          assert lib.assertMsg (lib.all (m: m != valid) (
            lib.attrValues mutants
          )) "perses-config: a mutant equals valid";
          assert lib.assertMsg (
            lib.length clausesCovered == 11
          ) "perses-config: the mutants cover clauses ${builtins.toJSON clausesCovered}, not all eleven";
          assert lib.assertMsg (misjudged == { })
            "perses-config: accepted a serving mutant, or rejected it for another clause: ${
              builtins.toJSON (lib.mapAttrs (_: failures) misjudged)
            }";
          pkgs.runCommand "perses-config" { passthru = { inherit failures valid mutants; }; } ''
            ${lib.concatStrings (
              lib.mapAttrsToList (
                n: m:
                "echo ${lib.escapeShellArg "rejected: ${n}: ${lib.findFirst (f: lib.hasPrefix "${clauseOf n}: " f) "" (failures m)}"}\n"
              ) mutants
            )}
            touch $out
          '';
      };
    };
}
