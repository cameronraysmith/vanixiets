### Task 4: Resources, module, identity and DNS

Implements `tasks.md` 3.3–3.6 (design D2–D9).
Pull request 2.

**Files:**
- Create: `modules/nixos/perses/resources/{project,globalsecret,globaldatasource-promql,globaldatasource-sql,dashboard-fleet-hosts,dashboard-devloop}.json`; delete `dashboard-fixture.json`
- Modify: `modules/nixos/perses.nix` (the module beside the predicate)
- Modify: `modules/nixos/kanidm.nix`, `modules/machines/nixos/magnetite/default.nix`, `modules/lib/observability-hosts.nix`, `modules/terranix/cloudflare.nix`

**Interfaces:**
- Consumes: `pkgs.perses-bin`, `flake.lib.persesCuratedArchives` (Task 2); `flake.lib.persesServingFailures` (Task 3).
- Produces: `flake.modules.nixos.perses`, imported by magnetite; the client, group and generators; the record.

**Grounding:**
- NP's module: `ExecStart = perses -config=/run/perses/config.yaml -web.listen-address=<listenAddress>:<port>`; `preStart` renders `settings` to `/run/perses/config.yaml`; `DynamicUser`, `StateDirectory = "perses"`, `WorkingDirectory = /var/lib/perses`, `Restart = "on-failure"` (NP `nixos/modules/services/monitoring/perses.nix:72-127`).
- Perses keys, read at 0.55.0 and probed at 0.55.1 in Task 2 Step 1: `perses/perses@v0.55.0:pkg/model/api/config/{security,authentication,authorization,datasource,database,plugin,provisioning}.go`, as `brainstorm.md` lists; guest permissions at `security.authorization.provider.native.guest_permissions` (`authorization.go:98-112`); the proxy's `allowHeaders` (`perses/spec@v0.3.0-rc.1:go/datasource/proxy/http/http.go:89-93`).
- The client to mirror: `modules/nixos/kanidm.nix:259-277`; the stub: `:222-225`; the generator: `:123-152`.
- The store's kill order: `OOMScoreAdjust = 500` (`modules/nixos/greptimedb.nix:340`); magnetite's kill-order assertion reads each unit's `OOMScoreAdjust` through `unitAdj` (`modules/machines/nixos/magnetite/default.nix:705`), collects them in its `order` set (`:707-712`), and states the relation and its message at `:729-739`; the evaluator's adjustment is 900.
- `notifiedUnits` already sets `OnFailure=observability-notify@%n.service` for each listed unit (`modules/nixos/observability-notify.nix:185-186`).
- PromQL in the store writes a literal dot as `[.]` (`modules/nixos/fleet-alert/rules.nix:11-13`).

- [ ] **Step 1: The resources (tasks.md 3.3)**

`project.json`: `{"kind":"Project","metadata":{"name":"fleet"},"spec":{"display":{"name":"Fleet"}}}`.

`globalsecret.json`: `{"kind":"GlobalSecret","metadata":{"name":"greptimedb-perses"},"spec":{"basicAuth":{"username":"perses","passwordFile":"/run/credentials/perses.service/perses-password"}}}`.

`globaldatasource-promql.json`:

```json
{"kind":"GlobalDatasource","metadata":{"name":"greptimedb-promql"},
 "spec":{"default":true,"plugin":{"kind":"PrometheusDatasource","spec":{"proxy":{"kind":"HTTPProxy","spec":{
   "url":"http://127.0.0.1:4000/v1/prometheus","secret":"greptimedb-perses",
   "headers":{"x-greptime-db-name":"fleet"},
   "allowHeaders":["Accept","Accept-Encoding","Content-Type","Content-Length","User-Agent","x-greptime-db-name"],
   "allowedEndpoints":[
     {"method":"POST","endpointPattern":"^/api/v1/(query|query_range|labels|series)$"},
     {"method":"GET","endpointPattern":"^/api/v1/(label/[A-Za-z_][A-Za-z0-9_]*/values|labels|series|query|query_range)$"}]}}}}}}
```

`globaldatasource-sql.json`: the same with `GreptimeDBDatasource`, `"url":"http://127.0.0.1:4000"`, `"default":false`, the same `allowHeaders`, and the single endpoint `{"method":"POST","endpointPattern":"^/v1/sql$"}`.

`dashboard-fleet-hosts.json`: project `fleet`; variable `host_name`, kind `ListVariable` with plugin `PrometheusLabelValuesVariable` (`labelName: "host_name"`, `matchers: ["system_memory_usage_bytes"]`), `allowMultiple: true`, `allowAllValue: true`; one `TimeSeriesChart` panel per expression of design D9 with `{host_name=~"$host_name"}` added to each selector, and a `Table` panel for pools and failed units; every query's datasource `{"kind":"PrometheusDatasource","name":"greptimedb-promql"}`.
Copy each expression an alert rule runs from `modules/nixos/fleet-alert/rules.nix` at the line design D9 cites, dropping the alert threshold; write the others (processes, pools, ARC, units) over the series the collector stores, which the container test's views case then runs.

`dashboard-devloop.json`: project `fleet`; `GreptimeDBTimeSeriesQuery` panels on `{"kind":"GreptimeDBDatasource","name":"greptimedb-sql"}`, adapted from `modules/nixos/devloop-collection.nix`'s questions as design D9 lists, every table written `"devloop"."<table>"` and no CTE:
- `queueWait` as three queries, one per percentile column;
- formation to landing: `formationToLand`'s join with `d."ts"` selected first as the time column and `formation_to_land_s` as the first numeric column, without `batch` in the result;
- build outcomes: `count(*)` per outcome per day from `"devloop"."ci_attribute"`, with the day as the time column;
- deploys: `"devloop"."deploy_record"`'s `"ts"` and `"host"` with a constant numeric column `1 AS n`.

Run: `nix build .#checks.x86_64-linux.perses-lint -L` (after deleting the fixture).

Expected: the six files pass; the seven mutants are still rejected with their messages.
The pass is evidence for the two dashboards and for the two datasources' plugin schemas only: lint applies the custom rules to Dashboards alone and does not validate `project.json` or `globalsecret.json`, whose properties D10's clauses 7 and 8 judge.

- [ ] **Step 2: The module (tasks.md 3.4)**

In `modules/nixos/perses.nix`, beside the predicate:

```nix
flake.modules.nixos.perses =
  { config, lib, pkgs, ... }:
  let
    credsDir = "/run/credentials/perses.service";
    domain = "obs.scientistexperience.net";
    port = 8095;
    resources = ./perses/resources;
    curated = flakeLib.persesCuratedArchives pkgs pkgs.perses-bin;
    readResources = map (f: lib.importJSON "${resources}/${f}") (lib.attrNames (builtins.readDir resources));
  in
  {
    services.perses = {
      enable = true;
      package = pkgs.perses-bin;
      listenAddress = "127.0.0.1";
      inherit port;
      settings = {
        security = { /* exactly the `valid.settings.security` of Task 3, guest permissions at `authorization.provider.native` */ };
        datasource.proxy.allowed_networks = [ "127.0.0.0/8" ];
        database.file = { folder = "/var/lib/perses/db"; extension = "json"; };
        provisioning.folders = [ "${resources}" ];
        plugin = { path = "/var/lib/perses/plugins"; archive_paths = [ "${curated}" ]; };
      };
    };
    systemd.services.perses = {
      after = [ "kanidm.service" "greptimedb.service" ];
      wants = [ "kanidm.service" "greptimedb.service" ];
      restartTriggers = [ resources ];
      preStart = lib.mkBefore "rm -rf /var/lib/perses/db /var/lib/perses/plugins\n";
      unitConfig.StartLimitIntervalSec = 0;
      serviceConfig = {
        LoadCredential = [
          "kanidm-client-secret:${config.clan.core.vars.generators.kanidm-oauth2-perses.files.secret.path}"
          "encryption-key:${config.clan.core.vars.generators.perses-encryption-key.files.key.path}"
          "perses-password:${config.clan.core.vars.generators.greptimedb-users.files.perses-password.path}"
        ];
        MemoryHigh = "192M"; MemoryMax = "256M"; MemorySwapMax = 0;
        Restart = lib.mkForce "always"; RestartSec = "10s";
        OOMScoreAdjust = 600;
      };
    };
    services.nginx.virtualHosts.${domain} = {
      forceSSL = true; enableACME = true;
      locations."/" = { proxyPass = "http://127.0.0.1:${toString port}"; extraConfig = ''proxy_set_header x-greptime-auth "";''; };
      locations."= /metrics".return = "404";
    };
    assertions = [ {
      assertion = servingFailures == [ ];
      message = "perses: ${lib.concatStringsSep "; " servingFailures}";
    } ];
  };
```

where `flakeLib` is the flake-parts `config.flake.lib` captured outside the NixOS module, and `servingFailures` applies `persesServingFailures` to `{ inherit (config.services.perses) settings listenAddress port; unit = config.systemd.services.perses; vhost = config.services.nginx.virtualHosts.${domain}; client = config.services.kanidm.provision.systems.oauth2.perses; resources = readResources; }`.
The module sets no `onFailure`: `perses` in magnetite's `notifiedUnits` (Step 3) already sets it, and a second setting renders the line twice.
Before writing the `LoadCredential` merge, evaluate NP's module's own `LoadCredential` (empty when no `_secret` is used) and confirm the list concatenates rather than conflicts.
`restartTriggers` on a store path restarts the unit when the directory's content changes.

Import `flake.modules.nixos.perses` in magnetite's module list beside `sso-gateway`'s import (`modules/machines/nixos/magnetite/default.nix:69`).

Show the assertion failing:

```bash
L=logs/cam73-evidence/3.4-assertions-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
for o in '{ services.nginx.virtualHosts."obs.scientistexperience.net".locations."/".extraConfig = lib.mkForce ""; }' \
         '{ services.perses.settings.security.authentication.refresh_token_ttl = lib.mkForce "24h"; }'; do
  nix eval --raw .#nixosConfigurations.magnetite --apply "c: (c.extendModules { modules = [ ({ lib, ... }: $o) ]; }).config.system.build.toplevel.drvPath" 2>&1 | tail -3 | tee -a "$L"
done
```

Expected (after Step 3, when the client exists): each fails with `perses: ` and the clause's message.

- [ ] **Step 3: Identity, secrets, holders and kill order (tasks.md 3.5)**

In `modules/nixos/kanidm.nix`: `groups.perses_users = { members = [ ]; overwriteMembers = false; };` beside `omnigent_users`; `systems.oauth2.perses = { displayName = "Observability"; originUrl = "https://obs.scientistexperience.net/api/auth/providers/oidc/kanidm/callback"; originLanding = "https://obs.scientistexperience.net/"; imageFile = pkgs.fetchurl { url = "https://raw.githubusercontent.com/perses/perses/bfaf3ce26d8b36397efb41ce185197a6e22f28b1/docs/images/perses_logo_cropped.svg"; hash = "sha256-8hLSMQekM6OfRq1SXh+fqdFaQcIH7jHEkqJfTfKfalo="; }; preferShortUsername = true; scopeMaps.perses_users = [ "openid" "profile" "email" ]; basicSecretFile = config.clan.core.vars.generators.kanidm-oauth2-perses.files.secret.path; };`; and `clan.core.vars.generators.kanidm-oauth2-perses` with one file `secret`, as `kanidm-oauth2-omnigent` without `env`, `restartUnits = [ "kanidm.service" "perses.service" ]`.
The logo is pinned at the v0.55.0 commit, whose image the plan review evaluated; record the URL in a comment, as omnigent's is.

In magnetite's configuration: `clan.core.vars.generators.perses-encryption-key = { files.key = { secret = true; mode = "0400"; restartUnits = [ "perses.service" ]; }; runtimeInputs = [ pkgs.openssl ]; script = ''printf '%s' "$(openssl rand -hex 16)" > "$out/key"''; };`; `files.perses-password.restartUnits = [ "perses.service" ];` in `greptimedb-users` (MG:529); `perses-password = [ "perses" ];` in the holder assertion (MG:636); in the kill-order assertion, `perses = unitAdj "perses";` in the `order` set (MG:707-712), the relation `evaluatorAdj > order.perses && order.perses > order.greptimedb` in place of `evaluatorAdj > order.greptimedb` (MG:729-739), and `perses` in its message between `nix-eval-jobs` and `greptimedb`.
In `modules/lib/observability-hosts.nix`, add `"perses"` to magnetite's `notifiedUnits`.

Show both assertions failing:

```bash
L=logs/cam73-evidence/3.5-identity-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
nix eval --json .#nixosConfigurations.magnetite.config.services.kanidm.provision.systems.oauth2.perses.scopeMaps --apply builtins.attrNames | tee -a "$L"
for o in '{ systemd.services.fleet-alert.serviceConfig.LoadCredential = [ "x:${config.clan.core.vars.generators.greptimedb-users.files.perses-password.path}" ]; }' \
         '{ systemd.services.perses.serviceConfig.OOMScoreAdjust = lib.mkForce 400; }'; do
  nix eval --raw .#nixosConfigurations.magnetite --apply "c: (c.extendModules { modules = [ ({ config, lib, ... }: $o) ]; }).config.system.build.toplevel.drvPath" 2>&1 | tail -3 | tee -a "$L"
done
nix eval --raw .#nixosConfigurations.magnetite.config.system.build.toplevel.drvPath | tee -a "$L"
```

Expected: `["perses_users"]`; the first override fails on the holder assertion naming `perses-password`, the second on the kill-order assertion; magnetite's toplevel evaluates.
Before the vars exist, clan evaluates their paths as `/no-such-path`; the predicate's clause 4 compares credential ids, not source paths, so it holds.

- [ ] **Step 4: The DNS record (tasks.md 3.6)**

In `modules/terranix/cloudflare.nix`, after `omni` (CF:186-193):

```nix
resource.cloudflare_dns_record.obs = {
  zone_id = config.data.cloudflare_zone.scientistexperience "id";
  name = "obs.scientistexperience.net";
  type = "CNAME";
  content = "magnetite.scientistexperience.net";
  ttl = 1;
  proxied = false;
};
```

Gated, the operator: `just terraform-plan`, recorded in `logs/cam73-evidence/3.6-dns-plan-<ts>.log`.

Expected: one resource to add, `cloudflare_dns_record.obs`, and no other change.
