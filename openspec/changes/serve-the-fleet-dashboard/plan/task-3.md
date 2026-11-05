### Task 3: The serving predicate and its check

Implements `tasks.md` 3.1–3.2 (design D10).
Pull request 2.

**Files:**
- Create: `modules/checks/perses-config.nix`
- Create: `modules/nixos/perses.nix`, holding `flake.lib.persesServingFailures` only in this task

**Interfaces:**
- Consumes: nothing from Task 2 beyond the repository at its merge.
- Produces: `flake.lib.persesServingFailures`, which Task 4's module asserts over magnetite's values.

**Grounding:**
- The check's shape is `modules/checks/omnigent-environment.nix:96-125`: `assert actual == [ ]`, `assert lib.all (m: failures m != [ ]) mutants`, then a `runCommand` that touches `$out`.
- Perses settings at 0.55.0: guest permissions live at `security.authorization.provider.native.guest_permissions`, the older path being deprecated (`perses/perses@v0.55.0:pkg/model/api/config/authorization.go:98-112`); a refresh issues an access token valid for `access_token_ttl` from the refresh and keeps the refresh token (`internal/api/crypto/jwt.go:102-110`, `internal/api/impl/auth/auth.go:167-207`).
- Input shape, the same one Task 4 renders from magnetite: `settings` is `services.perses.settings`; `listenAddress` and `port` are `services.perses.{listenAddress,port}`; `unit` is `{ serviceConfig = { LoadCredential; MemoryHigh; MemoryMax; }; preStart; }`; `vhost` is `services.nginx.virtualHosts."obs.scientistexperience.net"`'s `{ forceSSL; enableACME; locations; }`; `client` is `services.kanidm.provision.systems.oauth2.perses`; `resources` is the list of parsed JSON files of `modules/nixos/perses/resources/`.

- [ ] **Step 1: The check, before the predicate (tasks.md 3.1)**

`modules/checks/perses-config.nix`:

```nix
{ config, lib, ... }:
let
  credsDir = "/run/credentials/perses.service";
  allowHeaders = [ "Accept" "Accept-Encoding" "Content-Type" "Content-Length" "User-Agent" "x-greptime-db-name" ];
  valid = {
    listenAddress = "127.0.0.1";
    port = 8095;
    settings = {
      security = {
        enable_auth = true; readonly = true; cookie.secure = true;
        encryption_key_file = "${credsDir}/encryption-key";
        secret_file_allowed_directories = [ credsDir ];
        authentication = {
          disable_sign_up = true; refresh_token_ttl = "45m"; access_token_ttl = "15m";
          providers = {
            enable_native = false;
            oidc = [ {
              slug_id = "kanidm"; name = "Kanidm"; client_id = "perses";
              client_secret_file = "${credsDir}/kanidm-client-secret";
              issuer = "https://accounts.scientistexperience.net/oauth2/openid/perses";
              redirect_uri = "https://obs.scientistexperience.net/api/auth/providers/oidc/kanidm/callback";
              scopes = [ "openid" "profile" "email" ];
            } ];
          };
        };
        authorization.provider.native.guest_permissions = [ { actions = [ "read" ]; scopes = [ "Dashboard" "Project" "Folder" "GlobalDatasource" "Datasource" "Variable" "GlobalVariable" ]; } ];
      };
      datasource.proxy.allowed_networks = [ "127.0.0.0/8" ];
      plugin.path = "/var/lib/perses/plugins";
      database.file.folder = "/var/lib/perses/db";
    };
    unit = {
      serviceConfig = {
        LoadCredential = [ "kanidm-client-secret:/run/secrets/k" "encryption-key:/run/secrets/e" "perses-password:/run/secrets/p" ];
        MemoryHigh = "192M"; MemoryMax = "256M";
      };
      preStart = "rm -rf /var/lib/perses/db /var/lib/perses/plugins\n";
    };
    vhost = {
      forceSSL = true; enableACME = true;
      locations = {
        "/" = { proxyPass = "http://127.0.0.1:8095"; extraConfig = ''proxy_set_header x-greptime-auth "";''; };
        "= /metrics" = { return = "404"; };
      };
    };
    client = {
      originUrl = "https://obs.scientistexperience.net/api/auth/providers/oidc/kanidm/callback";
      scopeMaps.perses_users = [ "openid" "profile" "email" ];
    };
    resources = [
      { kind = "GlobalSecret"; metadata.name = "greptimedb-perses"; spec.basicAuth = { username = "perses"; passwordFile = "${credsDir}/perses-password"; }; }
      { kind = "GlobalDatasource"; metadata.name = "greptimedb-promql"; spec.plugin.spec.proxy.spec = {
          url = "http://127.0.0.1:4000/v1/prometheus"; secret = "greptimedb-perses";
          headers."x-greptime-db-name" = "fleet";
          inherit allowHeaders;
          allowedEndpoints = [ { method = "POST"; endpointPattern = "^/api/v1/(query|query_range|labels|series)$"; } ];
        }; }
    ];
  };
  set = path: value: lib.recursiveUpdate valid (lib.setAttrByPath path value);
  mapProvider = f: set [ "settings" "security" "authentication" "providers" "oidc" ] (map f valid.settings.security.authentication.providers.oidc);
  mapResource = kind: f: valid // { resources = map (r: if r.kind == kind then f r else r) valid.resources; };
  mapDsSpec = f: mapResource "GlobalDatasource" (r: lib.recursiveUpdate r { spec.plugin.spec.proxy.spec = f r.spec.plugin.spec.proxy.spec; });
  mutants = {
    listenAll = set [ "listenAddress" ] "";
    port8080 = set [ "port" ] 8080;
    notReadonly = set [ "settings" "security" "readonly" ] false;
    nativeLogin = set [ "settings" "security" "authentication" "providers" "enable_native" ] true;
    signUp = set [ "settings" "security" "authentication" "disable_sign_up" ] false;
    longRefresh = set [ "settings" "security" "authentication" "refresh_token_ttl" ] "24h";
    longAccess = set [ "settings" "security" "authentication" "access_token_ttl" ] "30m";
    pkceOff = mapProvider (p: p // { disable_pkce = true; });
    keyOutside = set [ "settings" "security" "encryption_key_file" ] "/var/lib/perses/key";
    anyNetwork = set [ "settings" "datasource" "proxy" "allowed_networks" ] [ "0.0.0.0/0" ];
    guestWrites = set [ "settings" "security" "authorization" "provider" "native" "guest_permissions" ] [ { actions = [ "*" ]; scopes = [ "Dashboard" ]; } ];
    unanchored = mapDsSpec (s: { allowedEndpoints = [ { method = "POST"; endpointPattern = "/api/v1/query"; } ]; });
    otherDatabase = mapDsSpec (s: { headers."x-greptime-db-name" = "devloop"; });
    storeElsewhere = mapDsSpec (s: { url = "http://127.0.0.1:4006/v1/prometheus"; });
    portPrefix = mapDsSpec (s: { url = "http://127.0.0.1:40001/v1/prometheus"; });
    noAllowHeaders = mapResource "GlobalDatasource" (r: lib.recursiveUpdate r { spec.plugin.spec.proxy.spec.allowHeaders = null; });
    authAllowed = mapDsSpec (s: { allowHeaders = allowHeaders ++ [ "x-greptime-auth" ]; });
    literalPassword = mapResource "GlobalSecret" (r: lib.recursiveUpdate r { spec.basicAuth.password = "x"; });
    noStrip = set [ "vhost" "locations" "/" "extraConfig" ] "";
    metricsOpen = valid // { vhost = valid.vhost // { locations = removeAttrs valid.vhost.locations [ "= /metrics" ]; }; };
    extraLocation = set [ "vhost" "locations" "/dashboard/" ] { proxyPass = "http://127.0.0.1:4000"; };
    secondGroup = set [ "client" "scopeMaps" "cognee_access" ] [ "openid" ];
    pluginsOnTmpfs = set [ "settings" "plugin" "path" ] "/run/perses/plugins";
    noWipe = set [ "unit" "preStart" ] "";
    noPluginWipe = set [ "unit" "preStart" ] "rm -rf /var/lib/perses/db\n";
    bigMemory = set [ "unit" "serviceConfig" "MemoryMax" ] "1G";
  };
  failures = config.flake.lib.persesServingFailures;
in
{
  perSystem = { pkgs, system, ... }: {
    checks = lib.optionalAttrs (system == "x86_64-linux") {
      perses-config =
        assert lib.assertMsg (failures valid == [ ]) "perses-config: valid input failed: ${builtins.toJSON (failures valid)}";
        assert lib.assertMsg (lib.all (m: m != valid) (lib.attrValues mutants)) "perses-config: a mutant equals valid";
        assert lib.assertMsg (lib.all (m: failures m != [ ]) (lib.attrValues mutants)) "perses-config: accepted a serving mutant";
        pkgs.runCommand "perses-config" { passthru = { inherit failures valid mutants; }; } ''
          ${lib.concatStrings (lib.mapAttrsToList (n: m: "echo ${lib.escapeShellArg "rejected: ${n}: ${lib.head (failures m)}"}\n") mutants)}
          touch $out
        '';
    };
  };
}
```

The mutants are written in full, as the plan review's prototype wrote them (`logs/cam73-evidence/1.1-proto-fixed-diff-20261104T235029Z.patch`); `longAccess`, `portPrefix`, `noAllowHeaders`, `authAllowed` and `noPluginWipe` judge the clauses the plan review's F7, F22, F13 and F14 changed.
Each `echo` passes through `lib.escapeShellArg`, so a failure message holding `'` cannot break the build.

No mutant may equal `valid`, which the assertion `lib.all (m: m != valid)` requires.

Run: `jj st --no-pager >/dev/null; nix build .#checks.x86_64-linux.perses-config -L 2>&1 | tee logs/cam73-evidence/3.1-config-red-<ts>.log`

Expected: evaluation fails with `attribute 'persesServingFailures' missing`.

- [ ] **Step 2: The predicate (tasks.md 3.2)**

In `modules/nixos/perses.nix`, `flake.lib.persesServingFailures = input: lib.concatLists [ … ]`, one `lib.optional (not clause) "<clause>: <what is wrong>"` per clause of design D10:

1. `lib.hasPrefix "127." listenAddress` and `port != 8080`;
2. `security.readonly`, `security.enable_auth`, `security.cookie.secure`, `!authentication.providers.enable_native`, `authentication.disable_sign_up`, and `authentication.refresh_token_ttl` and `authentication.access_token_ttl` both set and summing to at most 3,600 s, each parsed by a helper that accepts `<n>s`, `<n>m` and `<n>h` and yields `null` otherwise;
3. `lib.length providers.oidc == 1`, and only then, through `&&`'s laziness, its `issuer` and `redirect_uri` as constants, `redirect_uri == client.originUrl`, `!(provider.disable_pkce or false)`; the container test sets `oidc = [ ]`, so `lib.head` must not be forced first;
4. `secret_file_allowed_directories == [ credsDir ]`; `encryption_key_file`, `client_secret_file` and every GlobalSecret `passwordFile` start with `credsDir + "/"`, and their basenames are ids in `unit.serviceConfig.LoadCredential`;
5. `datasource.proxy.allowed_networks == [ "127.0.0.0/8" ]`;
6. every entry of `security.authorization.provider.native.guest_permissions` has `actions == [ "read" ]`;
7. every GlobalDatasource's `url` is exactly `http://127.0.0.1:4000/v1/prometheus` or `http://127.0.0.1:4000`, not a prefix match, which `http://127.0.0.1:40001` would pass; `headers."x-greptime-db-name" == "fleet"`; `secret == "greptimedb-perses"`; `allowHeaders == [ "Accept" "Accept-Encoding" "Content-Type" "Content-Length" "User-Agent" "x-greptime-db-name" ]`; and every `allowedEndpoints` entry has method in `[ "GET" "POST" ]` and a pattern matching `^\^.*\$$`;
8. no resource has `spec.basicAuth.password`, and none has `kind` `Datasource` or `Secret`;
9. `vhost.forceSSL`, `vhost.enableACME`, `locations` names exactly `[ "/" "= /metrics" ]`, `"/".proxyPass == "http://127.0.0.1:${toString port}"`, `"/".extraConfig` contains `proxy_set_header x-greptime-auth "";`, `"= /metrics".return == "404"`;
10. `lib.attrNames client.scopeMaps == [ "perses_users" ]`;
11. `plugin.path` not under `/run`; `unit.preStart` contains `rm -rf /var/lib/perses/db /var/lib/perses/plugins`; `MemoryMax` parsed to bytes at most 268,435,456 and `MemoryHigh` below it.

Run:

```bash
L=logs/cam73-evidence/3.2-config-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
nix build .#checks.x86_64-linux.perses-config -L 2>&1 | tee -a "$L"
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/perses-config-stats.json \
  nix eval --option eval-cache false --raw .#.checks.x86_64-linux.perses-config.drvPath >/dev/null
jq '.gc.totalBytes, .cpuTime' /tmp/perses-config-stats.json | tee -a "$L"
```

Expected: one `rejected:` line per mutant, each naming the clause design D10 numbers; `totalBytes` below 536,870,912.
