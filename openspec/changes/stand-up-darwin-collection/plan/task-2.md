### Task 2: Host table, certificates, renderers and the darwin fragment

Implements `tasks.md` 2.1–2.7 (design D1–D5, D7, D8, D11, D13; FII `One host table declares the agent hosts and what each reports`, `The collection CA issues each agent host one certificate`, `Each agent exports by its role`, `The darwin probe reports each allow-listed launchd job and the host's disk health in a textfile`, `A laptop's disk health is read on the host and served on loopback`, `No darwin collection job runs on a calendar schedule`; TSI `Credentials exist only as activation-resolved files owned by non-worker users`, `The collector's configuration bounds what it gathers`, `Scrape targets are reached on loopback`, `Omnigent unit names are stored under aliases`, `The telemetry store and the collector run inside a declared envelope`; FAI `The alerter token travels only as a file`; HMC `Stored unit names carry no owner's name`, `Collection survives a telemetry store restart without losing the queued interval`; DCI `Each agent host's collector ships its own deploy records`).
This is the first part of pull request 1; Task 3 adds the wrapper, the darwin envelope and the alert plumbing to the same pull request, which is opened only in Task 3 Step 8.
It starts only after Task 1 Step 4: its hunks in `modules/clan/services/otel-collector/flake-module.nix` (FM) and `schema.nix` (SC) are written, or rebased, onto the omnigent session's merged edits of those two files, and touch only the agent role (Step 2) and SC's two new keys (Step 4).
Every regulator comes first: the platform assertion fails before the field exists (Step 1), the check fails before the renderer exists (Step 4), the parser fixtures fail before the probe exists (Step 5), and each fragment assertion is shown failing by an `extendModules` override before the daemons it judges are written (Step 6).
stibnite's row has `collect = false` throughout this task, so its collecting configuration is evaluated only in the scratch tree of plan Global Constraints; nothing here activates stibnite or deploys magnetite, and the vars step (Step 3) writes only `vars/` in the working copy.

**Files:**
- Modify: `modules/lib/observability-hosts.nix` (HT): the `agent` helper (`:12-21`) gains `platform = "nixos"`; stibnite's row after scheelite's (`:54`)
- Modify: `modules/clan/inventory/services/otel-collector.nix:1-14`: the platform assertion
- Modify: FM: the top `let` (`:33-36`) gains `darwinModules`; the agent role (`:930-1027`): the generator attrsets (`:962-1005`) bound once and shared, `otel-cert`'s `restartUnits` (`:982`, `:985`) kept in `nixosModule` alone, and `perInstance.darwinModule` added after `nixosModule` (`:1025`)
- Modify: `modules/nixos/ntfy-alerter.nix:17-31`: the generator bound once and exposed also as `flake.modules.darwin.ntfy-alerter`
- Modify: SC: `darwinNodeExporterKeep` and `launchdLabels` after `smartctlKeep` (`:90-99`)
- Create: `modules/lib/otel-collector-darwin.nix` (`flake.lib.otelCollectorDarwin`), `modules/lib/otel-host-probe.nix` (`flake.lib.otelHostProbe`), `modules/darwin/otel-collector-agent.nix` (`flake.modules.darwin.otel-collector-agent`)
- Create: `modules/checks/otel-collector-darwin.nix` (`checks.x86_64-linux.otel-collector-darwin`), `modules/checks/otel-collector-darwin/launchctl/*.txt` and `*.rc`, `modules/checks/otel-collector-darwin/smartctl-disk0.json`, `modules/checks/otel-collector-darwin/expected/*.prom`
- Create (committed): `vars/per-machine/stibnite/otel-cert/**`, and the reader entries `clan vars fix` writes under `vars/shared/otel-ca/` and `vars/shared/ntfy-alerter/`
- Create (git-ignored): `logs/s5-evidence/2.<n>-*.log`, `logs/s5-evidence/2.6-overrides.nix`, and the scratch tree `$SCRATCH`

**Interfaces:**
- Consumes: Task 1's baselines (`logs/s5-evidence/1.2-baseline-*.log`, re-measured at the gate in `1.4-gate-*.log`), its recordings under `logs/s5-evidence/1.3-fixtures/`, the argument lists and the telemetry setting it recorded; `flake.lib.hosts.magnetite.zt` (`modules/lib/hosts.nix`); `flake.lib.devloopCollection.{keepAttributes,dropBody,deployRecordFile}` as FM:529-543 uses them, with SC's `devloop.tables.deploy_record`; `flake.lib.otelTestPki pkgs` (`modules/vm-tests/otel-test-pki.nix`); the `nix-builders` role's `darwinModule` precedent (`modules/clan/services/nix-builders/flake-module.nix:324-335`, `:360-401`, `:416-417`); `omnigent-host`'s activation pre-step (`modules/darwin/omnigent-host.nix:453-475`); the store-path guard (`modules/darwin/launchd-wait4path.nix:1-46`); nix-darwin's node_exporter module (`nix-darwin/nix-darwin@bb0b90db:modules/services/monitoring/prometheus-node-exporter.nix:35-119`) and daemon `command`/`script` handling (`nix-darwin/nix-darwin@bb0b90db:modules/launchd/default.nix:83-95`, which runs `command` as `/bin/sh -c "/bin/wait4path /nix/store && exec <command>"`); clan's darwin `restartUnits` throw (`clan-core@dbae2101:modules/clan/export-modules/generic-generator.nix:193-208`) and its shared-generator comparison, which ignores `owner`, `group` and `mode` and compares `files`, `prompts`, `dependencies` and `validationHash` (`clan-core@dbae2101:pkgs/clan-cli/clan_lib/vars/generator.py:106-116`, `:203-228`).
- Produces: everything in plan.md's Interface contract marked Task 2, which Tasks 3 to 6 rely on: `platform` and stibnite's row; the role's `darwinModule` with the `_otelcol` account and the three generators; `flake.lib.otelCollectorDarwin`; `flake.lib.otelHostProbe`; SC's `darwinNodeExporterKeep` and `launchdLabels`; the fragment with its daemons and assertions; `checks.x86_64-linux.otel-collector-darwin` with its case list, which Task 3 Step 1 extends.
  Two names are added beside the contract and recorded here so later tasks use them: the renderer also returns `node = { listenAddress; port; extraFlags; }`, the node_exporter settings the fragment applies and the check judges (tasks.md 2.4's node clause has no other Linux-evaluable source); and the fragment declares `vanixiets.otelCollector.darwin.agentSettings` and `processSettings`, the rendered configurations as mergeable options, so Step 6's overrides can change a value its assertions judge.

- [ ] **Step 1: The platform field, its assertion seen failing, and stibnite's row (tasks.md 2.1)**

The two value sources, named before the assertion is written: A, each row's `platform` in HT; B, `machineClass` of the same machine in `modules/clan/inventory/machines.nix` (`:23`, `:35`, `:47`, `:60`, `:72`, `:83` `"nixos"`; `:106` stibnite `"darwin"`), written for clan's machine registry and read by nothing in HT.
Replace `modules/clan/inventory/services/otel-collector.nix` with:

```nix
# Collector roles. Every host of flake.lib.observabilityHosts runs the agent;
# magnetite also runs the ingress, joined in-process by `forward`. A row's
# `platform` must equal its machine's machineClass, so the rules choose a
# host's expected signals by the class clan builds it as (design D7).
{ config, lib, ... }:
let
  hosts = config.flake.lib.observabilityHosts;
  machines = config.clan.inventory.machines;
  mismatched = lib.filterAttrs (
    name: h: (h.platform or null) != (machines.${name}.machineClass or null)
  ) hosts;
in
{
  clan.inventory.instances.otel-collector = {
    module = {
      name = "otel-collector";
      input = "self";
    };

    roles.agent.machines =
      assert lib.assertMsg (mismatched == { })
        "otel-collector: flake.lib.observabilityHosts rows whose platform differs from the inventory's machineClass: ${
          builtins.toJSON (lib.mapAttrs (n: h: { platform = h.platform or null; machineClass = machines.${n}.machineClass or null; }) mismatched)
        }";
      lib.mapAttrs (_: _: { }) hosts;
    roles.ingress.machines.magnetite = { };
  };
}
```

Run:

```bash
jj st --no-pager >/dev/null
L=logs/s5-evidence/2.1-platform-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
nix eval --raw .#nixosConfigurations.electrum.config.system.build.toplevel.drvPath 2>&1 | grep -o 'otel-collector: flake.lib.observabilityHosts rows[^"]*' | head -n 1 | tee "$L"
```

Expected: the assertion's message, naming all six rows with `"platform":null` (RED).
Then, in HT, add `platform = "nixos";` to the `agent` helper after `collect = true;`, replace the header comment's second sentence to name `platform` among what the table carries, and add after scheelite:

```nix
      # A darwin workstation: launchd jobs and the probe's textfile instead of
      # systemd units; its SMART device is read by the probe (design D4, D7).
      stibnite = agent [ ] // {
        platform = "darwin";
        notifiedUnits = [ "otel-envelope" ];
        smartDevices = [ "disk0" ];
        collect = false;
      };
```

stibnite's `notifiedUnits` replace the helper's: `otel-envelope` posts its own notices through the wrapper (Task 3), and no darwin job is named `opentelemetry-collector`.
Steps 1 to 3 are committed together, so no commit has stibnite's row without the role's `darwinModule` (Step 2).
Run:

```bash
jj st --no-pager >/dev/null
nix eval --json .#lib.observabilityHosts --apply 'builtins.mapAttrs (_: h: h.platform)' | tee -a "$L"
nix eval --json .#lib.observabilityHosts.stibnite | tee -a "$L"
nix eval --raw .#nixosConfigurations.electrum.config.system.build.toplevel.drvPath | tee -a "$L"; echo
```

Expected: seven rows, six `"nixos"` and `"stibnite":"darwin"`; stibnite's row `{"alwaysOn":false,"collect":false,"notifiedUnits":["otel-envelope"],"platform":"darwin","smartDevices":["disk0"]}`; a drvPath (evaluation).
The negative control, in the scratch tree at the working copy's commit (plan Global Constraints), with stibnite's `platform` edited to `"nixos"`:

```bash
SCRATCH=$REPO/../vanixiets-worktrees/scratch
git -C $REPO worktree add --detach $SCRATCH "$(jj log --no-pager --no-graph -r @ -T commit_id)"
# in $SCRATCH, set stibnite's platform = "nixos" in modules/lib/observability-hosts.nix
(cd $SCRATCH && nix eval --raw .#nixosConfigurations.electrum.config.system.build.toplevel.drvPath 2>&1 | grep -o '"stibnite":{[^}]*}' | head -n 1) | tee -a "$REPO/$L"
git -C $REPO worktree remove --force $SCRATCH
```

Expected: `"stibnite":{"machineClass":"darwin","platform":"nixos"}` (negative control).

- [ ] **Step 2: The agent role on darwin (tasks.md 2.2)**

Record first, in `$DEPLOY` at `origin/main`, the NixOS generators this step refactors, so the refactor is shown not to change them:

```bash
L=$REPO/logs/s5-evidence/2.2-role-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
gen='g: { inherit (g) dependencies validation share; script = g.script; files = builtins.mapAttrs (_: f: { inherit (f) secret deploy restartUnits owner mode neededFor; }) g.files; }'
for h in magnetite electrum; do for g in otel-ca otel-cert ntfy-alerter; do
  printf '%s %s %s\n' "$h" "$g" "$(cd $DEPLOY && nix eval --json ".#nixosConfigurations.$h.config.clan.core.vars.generators.$g" --apply "$gen" | sha256sum | cut -d' ' -f1)"
done; done | tee "$L"
```

In FM's top `let` add `darwinModules = config.flake.modules.darwin;` beside `nixosModules`.
In the agent role's `perInstance`, bind the two generators once, before `nixosModule`, from the existing text (`:965-1004`) without `restartUnits`:

```nix
            # One definition of the CA and the certificate for both module
            # classes; clan compares a shared generator's files, prompts,
            # dependencies and validation across machines and ignores
            # owner, group and mode (clan_lib/vars/generator.py:106-116).
            otelGenerators =
              { lib, pkgs }:
              let
                isIngress = roles.ingress.machines ? ${machine.name};
                sans = lib.optionalString isIngress "IP:${flakeLib.hosts.magnetite.zt},DNS:magnetite.zt";
                usage = if isIngress then "serverAuth,clientAuth" else "clientAuth";
              in
              {
                otel-ca = { /* :966-976 unchanged */ };
                otel-cert = {
                  dependencies = [ "otel-ca" ];
                  files."cert.pem".secret = false;
                  validation = { subjectAltNames = sans; extendedKeyUsage = usage; };
                  runtimeInputs = [ pkgs.openssl ];
                  script = ''/* :993-1002 unchanged */'';
                };
              };
```

In `nixosModule`, replace the generator attrset (`:962-1005`) with `clan.core.vars.generators = lib.mkMerge [ (otelGenerators { inherit lib pkgs; }) { otel-cert.files."key.pem".restartUnits = restart; otel-cert.files."cert.pem".restartUnits = restart; } ];`, keeping the comments; `restartUnits` stays in the NixOS module alone, because clan throws on it on darwin (`generic-generator.nix:193-208`; design D5).
In `modules/nixos/ntfy-alerter.nix`, bind the generator once in a `let` and define both `flake.modules.nixos.ntfy-alerter` and `flake.modules.darwin.ntfy-alerter` from it, with the header comment saying one definition serves both classes, so the shared script cannot drift.
After `nixosModule`, add:

```nix
            # Every darwin row, whatever its collect: the collector's account
            # and its three secrets, so the files have their owner before any
            # collector runs; the fragment only where collect is true (design
            # D1, D2, D5). nix-darwin has no tmpfiles and no restartUnits:
            # the fragment's OTEL_CERT_SHA256 reloads the agent on a reissue.
            darwinModule =
              {
                config,
                lib,
                pkgs,
                ...
              }:
              let
                # Static data, so it can select imports without evaluating the host (design D6).
                collect = flakeLib.observabilityHosts.${machine.name}.collect;
                otelcol = {
                  owner = "_otelcol";
                  group = "_otelcol";
                  mode = "0400";
                };
              in
              {
                imports = [ darwinModules.ntfy-alerter ] ++ lib.optional collect darwinModules.otel-collector-agent;

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
                    otel-cert.files."key.pem" = otelcol // { neededFor = "services"; };
                    ntfy-alerter.files.token = { inherit (otelcol) owner mode; };
                  }
                ];
              };
```

`darwinModules.otel-collector-agent` is referenced inside `lib.optional collect`, so this commit evaluates before Step 6 defines it, while stibnite's `collect` is false.
Run:

```bash
jj st --no-pager >/dev/null
for h in magnetite electrum; do for g in otel-ca otel-cert ntfy-alerter; do
  printf '%s %s %s\n' "$h" "$g" "$(nix eval --json ".#nixosConfigurations.$h.config.clan.core.vars.generators.$g" --apply "$gen" | sha256sum | cut -d' ' -f1)"
done; done | diff - <(head -n 6 "$L") && echo "nixos generators unchanged" | tee -a "$L"
nix eval --raw .#darwinConfigurations.stibnite.config.system.build.toplevel.drvPath | tee -a "$L"; echo
nix eval --json '.#darwinConfigurations.stibnite.config.clan.core.vars.generators' --apply 'g: { key = { inherit (g.otel-cert.files."key.pem") owner group mode neededFor restartUnits; }; token = { inherit (g.ntfy-alerter.files.token) owner mode; }; ca = g.otel-ca.share; }' | tee -a "$L"
nix eval --json '.#darwinConfigurations.stibnite.config.users.users._otelcol' --apply 'u: { inherit (u) uid gid home shell; }' | tee -a "$L"
nix eval --json '.#darwinConfigurations.stibnite.config.users.knownUsers' | tee -a "$L"
```

Expected: `nixos generators unchanged`; stibnite's drvPath with `collect = false`; `{"ca":true,"key":{"group":"_otelcol","mode":"0400","neededFor":"services","owner":"_otelcol","restartUnits":[]},"token":{"mode":"0400","owner":"_otelcol"}}`; `{"gid":536,"home":"/var/empty","shell":"/usr/bin/false","uid":536}`; `knownUsers` containing `_otelcol` beside `crs58` and `omnigent-cameron` (evaluation).

- [ ] **Step 3: The vars step (tasks.md 2.3)**

Recording hashes around every command (`h` records the decrypted `ntfy-alerter` token's sha256 and `otel-ca`'s certificate's, compares them with Task 1's, and stops on any change), under `/bin/bash` in `$REPO`:

```bash
set -euo pipefail
L=logs/s5-evidence/2.3-vars-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
B=$(ls -t logs/s5-evidence/1.2-baseline-*.log | head -n 1)
T0=$(awk '$1 == "ntfy-alerter" { print $2 }' "$B"); C0=$(awk '$1 == "otel-ca" { print $2 }' "$B")
# The token is compared by its decrypted value: `clan vars fix` re-encrypts the
# file for a new reader, so the encrypted file's own hash changes by design.
tok() { clan vars get magnetite ntfy-alerter/token | sha256sum | cut -d' ' -f1; }
h() {
  t=$(tok); c=$(sha256sum < vars/shared/otel-ca/ca.crt/value | cut -d' ' -f1)
  echo "== $1 token=$t otel-ca=$c" | tee -a "$L"
  [ "$t" = "$T0" ] || { echo "STOP: the ntfy-alerter token changed at $1" | tee -a "$L"; return 1; }
  [ "$c" = "$C0" ] || { echo "STOP: otel-ca's certificate changed at $1" | tee -a "$L"; return 1; }
}
jj st --no-pager >/dev/null
h before
CLAN_NO_COMMIT=1 clan vars generate stibnite --generator otel-cert 2>&1 | tee -a "$L"; h otel-cert
CLAN_NO_COMMIT=1 clan vars fix stibnite --generator otel-ca 2>&1 | tee -a "$L"; h fix-otel-ca
CLAN_NO_COMMIT=1 clan vars fix stibnite --generator ntfy-alerter 2>&1 | tee -a "$L"; h fix-ntfy-alerter
grep -c '^== ' "$L"
```

Expected: 4 `==` records, every hash equal to Task 1's, no `STOP` line; a `STOP` ends the script under `set -e`, and `vars/` is restored with `jj restore --from @- vars/` before the cause is investigated (design D5).
The token value is hashed in a pipe and never printed; `clan vars get` decrypts with the operator's key on stibnite; `clan vars generate` runs only on `otel-cert`, a per-machine generator, and the two shared generators only gain a reader (O2).
Then verify the certificate (tasks.md 2.3's verify):

```bash
c=vars/per-machine/stibnite/otel-cert/cert.pem/value
openssl x509 -noout -subject -dates -ext subjectAltName,extendedKeyUsage,keyUsage -in "$c" 2>&1 | tee -a "$L"
openssl verify -CAfile vars/shared/otel-ca/ca.crt/value "$c" 2>&1 | tee -a "$L"
ls vars/shared/ntfy-alerter/token/machines/ | tee -a "$L"
ls vars/shared/otel-ca/ca.key/machines/ 2>/dev/null | tee -a "$L"
```

Expected: `subject=CN=stibnite`, `notAfter` about 3650 days on, `TLS Web Client Authentication`, no SAN extension; `<path>: OK`; seven token readers, stibnite among them; the `otel-ca` reader list, if the pinned clan keeps one for the undeployed key, with stibnite added (command).
Commit Steps 1 to 3 after `nix fmt` (plan Global Constraints), for example "Add stibnite to the collection host table with its own collection certificate"; the vars are in this commit.

- [ ] **Step 4: The darwin renderer, its check written first (tasks.md 2.4)**

Measure first: `otel-collector-darwin` has no "before" (design D13); record `otel-collector-config`'s cost again, since SC changes here.
Write `modules/checks/otel-collector-darwin.nix` before `modules/lib/otel-collector-darwin.nix` exists.
It renders both configurations with `flake.lib` data only, never evaluating `darwinConfigurations.stibnite` (design D13), with the throwaway certificates of `flake.lib.otelTestPki pkgs`, so validation can open real files:

```nix
# checks.x86_64-linux.otel-collector-darwin: the darwin agent's and
# otelcol-process's configurations, rendered by flake.lib.otelCollectorDarwin
# from flake.lib data only, judged by R3.1's darwin clauses (ADR-003:240) and
# validated by the root pin's otelcol-contrib 0.155.0, the version stibnite
# runs: validation reads component configuration, not the platform. Later
# cases run the probe's parser over launchctl and smartctl output recorded
# on stibnite at macOS 26.7.1, and the notifier wrapper over a recording
# ntfy-send. Each clause names its two value sources; each mutant changes
# one input and runs only its own clause or case, printed as
# `mutant <name> rejected: <case>`. Relations within one host are the darwin
# fragment's assertions, not clauses here.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      pki = self.lib.otelTestPki pkgs;
      render =
        args:
        self.lib.otelCollectorDarwin (
          {
            hostName = "stibnite";
            certFile = "${pki}/agent.crt";
            keyFile = "${pki}/agent.key";
            caFile = "${pki}/ca.crt";
          }
          // args
        );
      # Source A of the exporter clause: the address clan's ZeroTier service
      # assigned to magnetite, not the registry the renderer reads.
      ztAddress = lib.trim (builtins.readFile "${self}/vars/shared/zerotier-ip-magnetite-zerotier/ip/value");
      input = {
        r = render { };
        inherit ztAddress;
        credentialPaths = [ "${pki}/agent.crt" "${pki}/agent.key" "${pki}/ca.crt" "/run/secrets" ];
      };
      isLoopback = /* as modules/checks/otel-collector-config.nix:42-45 */;
      collectEndpoints = /* as modules/checks/otel-collector-config.nix:48-60 */;
      # ADR-004:89's six identity attributes, typed here from the decision
      # record, not read from the renderer.
      identity = [ "process.pid" "process.parent_pid" "process.command" "process.command_line" "process.executable.path" "process.owner" ];
      clauses = i: {
        nodeTextfileOnLoopback = i.r.node.listenAddress == "127.0.0.1" && i.r.node.port == 9100
          && i.r.node.extraFlags == [ "--collector.disable-defaults" "--collector.textfile" "--collector.textfile.directory=/var/lib/prometheus-node-exporter/textfile" ];
        processIdentityOff =
          let a = i.r.process.receivers."host_metrics/process".scrapers.process.resource_attributes; in
          lib.all (n: (a.${n}.enabled or true) == false) identity
          && lib.all (n: builtins.elem n identity || (a.${n}.enabled or false) == false) (builtins.attrNames a);
        processNoListenerNoCredential =
          collectEndpoints i.r.process.receivers == [ ]
          && (i.r.process.service.telemetry.metrics.level or null) == "none"
          && !(i.r.process.service.telemetry.metrics ? readers)
          && lib.all (p: !(lib.hasInfix p (builtins.toJSON i.r.process))) i.credentialPaths
          && i.r.process.exporters."otlp_http/agent".endpoint == "http://127.0.0.1:4318";
        strictIncludes =
          let s = i.r.agent.receivers."host_metrics/memory".scrapers; in
          s.disk.include == { devices = [ "disk0" ]; match_type = "strict"; }
          && s.disk.metrics."system.disk.io_time".enabled == false
          && s.disk.metrics."system.disk.pending_operations".enabled == false
          && s.filesystem.include_mount_points == { mount_points = [ "/System/Volumes/Data" ]; match_type = "strict"; }
          && !(s ? paging) && !(i.r.agent.receivers ? systemd);
        loopbackButIngress =
          lib.all isLoopback (
            collectEndpoints i.r.agent.receivers
            ++ lib.concatMap (j: lib.concatMap (c: c.targets) j.static_configs) i.r.agent.receivers.prometheus.config.scrape_configs
            ++ map (r: "${r.pull.exporter.prometheus.host}") i.r.agent.service.telemetry.metrics.readers
          )
          && lib.all (n: i.r.agent.exporters.${n}.endpoint == "https://[${i.ztAddress}]:4318") [ "otlp_http/ingress" "otlp_http/ingress-logs" ]
          && builtins.attrNames i.r.agent.exporters == [ "otlp_http/ingress" "otlp_http/ingress-logs" ];
      };
      mutants = {
        nodeListenEmpty = { clause = "nodeTextfileOnLoopback"; apply = i: i // { r = lib.recursiveUpdate i.r { node.listenAddress = ""; }; }; };
        seventhIdentityAttribute = { clause = "processIdentityOff"; apply = i: i // { r = lib.recursiveUpdate i.r { process.receivers."host_metrics/process".scrapers.process.resource_attributes."process.cgroup".enabled = true; }; }; };
        processEndpoint = { clause = "processNoListenerNoCredential"; apply = i: i // { r = lib.recursiveUpdate i.r { process.receivers.otlp.protocols.http.endpoint = "127.0.0.1:4319"; }; }; };
        diskIncludeAll = { clause = "strictIncludes"; apply = i: i // { r = lib.recursiveUpdate i.r { agent.receivers."host_metrics/memory".scrapers.disk.include = { devices = [ ".*" ]; match_type = "regexp"; }; }; }; };
        exporterAddressOther = { clause = "loopbackButIngress"; apply = i: i // { ztAddress = "fddb:4344:343b:14b9:399:930f:39db:40d3"; }; };
      };
```

The value sources of each clause, named here before its mutant: `nodeTextfileOnLoopback`, the renderer's `node` against ADR-003 item 23's flags (`ADR-003-collection-topology.md:112`) typed in the check; `processIdentityOff`, the rendered scraper against ADR-004:89's list typed in the check; `processNoListenerNoCredential`, the rendered `otelcol-process` configuration against the telemetry value Task 1 Step 3 read from the vendored source and the throwaway credential paths the check itself passed in; `strictIncludes`, the rendered scrapers against ADR-003 item 21 and ADR-004:100 typed in the check; `loopbackButIngress`, the rendered endpoints against the loopback pattern and against the address in `vars/shared/zerotier-ip-magnetite-zerotier/ip/value`, where the renderer reads `flake.lib.hosts.magnetite.zt`.
The check asserts at evaluation that every clause holds for `input` and that each mutant's own clause fails for `mutant.apply input`, and its `runCommand` (`x86_64-linux` only, like `otel-envelope`) prints `ok: <clause>` for each clause and `mutant <name> rejected: <clause>` for each mutant, then runs the root pin's `otelcol-contrib validate --config <file>` (Task 1 Step 3's argument list) on `pkgs.formats.yaml`-rendered `agent` and `process`, printing `ok: validate <name>`, and, as its negative control, on a copy of `agent` with `exporters."otlp_http/ingress".sending_queue.queue_sizee = 1` added, which must exit non-zero, printing `control validateRejectsUnknownKey rejected`.
Run:

```bash
jj st --no-pager >/dev/null
nix build .#checks.x86_64-linux.otel-collector-darwin 2>&1 | tee logs/s5-evidence/2.4-red-$(/bin/date -u +%Y%m%dT%H%M%SZ).log | tail -n 3
```

Expected: FAIL at evaluation, `attribute 'otelCollectorDarwin' missing` (RED).
Then add to SC, after `smartctlKeep`:

```nix
    # Darwin node_exporter series kept besides smartctlKeep, which the
    # probe's textfile writes under the same names (ADR-004:93, :95-96).
    darwinNodeExporterKeep = [
      "launchd_job_state"
      "launchd_job_last_exit_code"
      "launchd_job_runs_total"
      "node_textfile_mtime_seconds"
      "node_textfile_scrape_error"
    ];

    # ADR-004:121's launchd allow-list, by label, as glob patterns; each
    # darwin host's probe reads the labels on it that its evaluated
    # launchd.daemons defines.
    launchdLabels = [
      "org.nixos.nix-daemon"
      "org.nixos.nix-grpc-daemon"
      "org.nixos.harmonia-gc"
      "org.nixos.nix-cleanup-gcroots"
      "org.nixos.sops-install-secrets"
      "org.nixos.dnscrypt-proxy"
      "org.nixos.otelcol"
      "org.nixos.otelcol-process"
      "org.nixos.prometheus-node-exporter"
      "org.nixos.omnigent-host-*"
    ];
```

and create `modules/lib/otel-collector-darwin.nix`:

```nix
# flake.lib.otelCollectorDarwin { hostName; certFile; keyFile; caFile; }: the
# darwin agent's and otelcol-process's configurations as plain attrsets, from
# flake.lib data only, so checks.x86_64-linux.otel-collector-darwin judges
# them without evaluating a darwin host (design D2, D3, D13). `targets` and
# `exporters` are what the darwin otel-envelope probes and reads; `node` is
# the loopback node_exporter's settings. The Linux-only parts of the NixOS
# agent are absent: the systemd receiver errors at start off Linux, and the
# darwin memory scraper's available-memory and paging series are empty or
# zero (design "Requirement applicability").
{ config, lib, ... }:
let
  flakeLib = config.flake.lib;
  schema = flakeLib.otelCollectorSchema;
  mib = n: n * 1024 * 1024;
  keepRegex = names: lib.concatStringsSep "|" names;
  scrape = job: target: extra: { job_name = job; scrape_interval = "60s"; static_configs = [ { targets = [ target ]; } ]; } // extra;
  keep = names: { metric_relabel_configs = [ { source_labels = [ "__name__" ]; regex = keepRegex names; action = "keep"; } ]; };
in
{
  flake.lib.otelCollectorDarwin =
    { hostName, certFile, keyFile, caFile }:
    let
      ingressExporter = queueSize: {
        endpoint = "https://[${flakeLib.hosts.magnetite.zt}]:4318";
        tls = { ca_file = caFile; cert_file = certFile; key_file = keyFile; min_version = "1.3"; };
        sending_queue = { storage = "file_storage"; sizer = "bytes"; queue_size = queueSize; };
        retry_on_failure = { enabled = true; max_interval = "60s"; max_elapsed_time = "0s"; };
      };
      node = {
        listenAddress = "127.0.0.1";
        port = 9100;
        extraFlags = [ "--collector.disable-defaults" "--collector.textfile" "--collector.textfile.directory=/var/lib/prometheus-node-exporter/textfile" ];
      };
    in
    rec {
      inherit node;
      agent = {
        extensions.file_storage = { directory = "/var/lib/opentelemetry-collector/queue"; create_directory = true; };
        receivers = {
          "host_metrics/memory" = {
            collection_interval = "60s";
            scrapers = {
              memory = { };
              disk = {
                include = { devices = [ "disk0" ]; match_type = "strict"; };
                metrics = { "system.disk.io_time".enabled = false; "system.disk.pending_operations".enabled = false; };
              };
              # darwin ignores include_virtual_filesystems, so the strict
              # list is the only bound (gopsutil@v4.26.5:disk/disk_darwin.go:21-30).
              filesystem = {
                include_mount_points = { mount_points = [ "/System/Volumes/Data" ]; match_type = "strict"; };
                metrics = { "system.filesystem.usage".enabled = true; "system.filesystem.inodes.usage".enabled = false; "system.filesystem.utilization".enabled = false; };
              };
            };
          };
          # otelcol-process's points; no logs pipeline reads it (ADR-003:81).
          otlp.protocols.http.endpoint = "127.0.0.1:4318";
          prometheus.config.scrape_configs = [
            (scrape "node" "${node.listenAddress}:${toString node.port}" (keep (schema.darwinNodeExporterKeep ++ schema.smartctlKeep)))
            (scrape "otelcol" "127.0.0.1:8888" (lib.recursiveUpdate (keep schema.otelcolKeep) {
              metric_relabel_configs = (keep schema.otelcolKeep).metric_relabel_configs ++ [ { regex = "service_instance_id"; action = "labeldrop"; } ];
            }))
          ];
        };
        processors = {
          memory_limiter = { check_interval = "1s"; limit_mib = 150; spike_limit_mib = 30; };
          "resource/agent".attributes = [
            { key = "host.name"; value = hostName; action = "upsert"; }
            { key = "vanixiets.database"; value = "fleet"; action = "upsert"; }
          ];
        };
        exporters = {
          "otlp_http/ingress" = ingressExporter (mib 400);
          "otlp_http/ingress-logs" = ingressExporter (mib 16);
        };
        service = {
          extensions = [ "file_storage" ];
          # Explicit, so the loopback clause judges the listener.
          telemetry.metrics.readers = [ { pull.exporter.prometheus = { host = "127.0.0.1"; port = 8888; }; } ];
          pipelines."metrics/host" = {
            receivers = [ "host_metrics/memory" "otlp" "prometheus" ];
            processors = [ "memory_limiter" "resource/agent" ];
            exporters = [ "otlp_http/ingress" ];
          };
        };
      };
      process = {
        receivers."host_metrics/process" = {
          collection_interval = "60s";
          scrapers.process = {
            mute_process_all_errors = true;
            resource_attributes = lib.genAttrs [ "process.pid" "process.parent_pid" "process.command" "process.command_line" "process.executable.path" "process.owner" ] (_: { enabled = false; });
            metrics = { "process.memory.usage".enabled = true; "process.cpu.time".enabled = false; "process.disk.io".enabled = false; "process.memory.virtual".enabled = false; };
          };
        };
        processors = {
          memory_limiter = { check_interval = "1s"; limit_mib = 64; spike_limit_mib = 16; };
          # As the NixOS agent's (FM:310-332; ADR-003 item 16).
          "groupbyattrs/compact".keys = [ ];
          "metrics_transform/process".transforms = [ /* FM:313-326 */ ];
          "filter/process-min" = { /* FM:327-332, reading schema.process.minBytes */ };
          "resource/process".attributes = [ { key = "service.name"; value = "otelcol-process"; action = "upsert"; } ];
        };
        exporters."otlp_http/agent" = { endpoint = "http://127.0.0.1:4318"; sending_queue.enabled = true; };
        # No listener and no reader: Task 1 Step 3's vendored reading.
        service.telemetry.metrics.level = "none";
        service.pipelines."metrics/process" = {
          receivers = [ "host_metrics/process" ];
          processors = [ "memory_limiter" "groupbyattrs/compact" "metrics_transform/process" "filter/process-min" "resource/process" ];
          exporters = [ "otlp_http/agent" ];
        };
      };
      targets = [
        { job = "node"; url = "http://${node.listenAddress}:${toString node.port}/metrics"; }
        { job = "otelcol"; url = "http://127.0.0.1:8888/metrics"; }
      ];
      exporters = builtins.attrNames agent.exporters;
    };
}
```

The three process processors repeat the NixOS agent's text because FM's agent fragment is a NixOS module the darwin side cannot import, and design D1 keeps the darwin code out of FM; a disagreement between the two shows as `process_memory_usage_bytes` series of stibnite that differ in shape from the NixOS hosts' at Task 5's capture.
The renderer has no `transform/omnigent-alias`, which design D2 lists: that processor rewrites `systemd.unit.name` (FM:294-297), which no darwin receiver emits, and on darwin the owner alias is written by the probe into `launchd_label` (Step 5).
If Task 1 Step 3 found a different darwin `disk` include key or telemetry reader shape at 0.155.0, the renderer and the check use the recorded one.
Run:

```bash
jj st --no-pager >/dev/null
L=logs/s5-evidence/2.4-check-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
nix build .#checks.x86_64-linux.otel-collector-darwin -L 2>&1 | tee "$L" | grep -E '^(ok|mutant|control|FAIL)'
for c in otel-collector-darwin otel-collector-config; do
  NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/$c-stats.json nix eval --option eval-cache false --raw ".#.checks.x86_64-linux.$c.drvPath" >/dev/null
  printf '%s %s %s\n' "$c" "$(jq '.gc.totalBytes // 0' /tmp/$c-stats.json)" "$(jq '.cpuTime // 0' /tmp/$c-stats.json)"
done | tee -a "$L"
```

Expected: five `ok:` clause lines, two `ok: validate` lines, five `mutant … rejected` lines, `control validateRejectsUnknownKey rejected`, no `FAIL`; `otel-collector-darwin` between about 0.15 and 0.25 GiB (design D13) and below 536,870,912; `otel-collector-config` unchanged from Task 1's figure, since it reads no new key; a figure over the budget stops the task (build).
Commit, for example "Render the darwin collector configurations and check them on Linux".

- [ ] **Step 5: The probe, its fixtures first (tasks.md 2.5)**

Copy from `logs/s5-evidence/1.3-fixtures/` into `modules/checks/otel-collector-darwin/`: `launchctl/org.nixos.nix-daemon.{txt,rc}` (a running kept-alive job), `launchctl/org.nixos.omnigent-host-cameron.{txt,rc}`, `launchctl/org.nixos.otelcol.{txt,rc}` (answered `Could not find service`), `launchctl/com.apple.progressd.{txt,rc}` saved as `launchctl/org.nixos.jetsam-killed.{txt,rc}` (a `last exit reason` and no exit-code line), `launchctl/org.nixos.exit-78.{txt,rc}` (Task 1 Step 3's job with `last exit code = 78`, or its marked edited copy), and `smartctl-disk0.json`; the fixtures keep their `pid` lines, which the parser must ignore and the `pidWritten` mutant writes.
Write by hand, from ADR-004:93-95 and the recordings, not from any parser output, `expected/launchd-<label>.prom` for each label and `expected/smartctl.prom`; for a running job the expected text is:

```text
# HELP launchd_job_state 1 for the launchd job's current state, 0 for the others.
# TYPE launchd_job_state gauge
launchd_job_state{launchd_label="org.nixos.nix-daemon",launchd_state="running"} 1
launchd_job_state{launchd_label="org.nixos.nix-daemon",launchd_state="not_running"} 0
launchd_job_state{launchd_label="org.nixos.nix-daemon",launchd_state="unloaded"} 0
launchd_job_state{launchd_label="org.nixos.nix-daemon",launchd_state="other"} 0
# HELP launchd_job_last_exit_code The job's last exit status; 0 if it never exited, -1 if not an integer.
# TYPE launchd_job_last_exit_code gauge
launchd_job_last_exit_code{launchd_label="org.nixos.nix-daemon"} 0
# HELP launchd_job_runs_total Launches since the job was loaded.
# TYPE launchd_job_runs_total counter
launchd_job_runs_total{launchd_label="org.nixos.nix-daemon"} <runs from the recording>
```

`org.nixos.omnigent-host-cameron`'s expected file names `org.nixos.omnigent-host-owner-1` (SC's `ownerAliases`, `schema.nix:48-51`); `org.nixos.otelcol`'s has only the four state lines with `unloaded` 1; `org.nixos.jetsam-killed`'s has `launchd_job_last_exit_code` -1; `org.nixos.exit-78`'s has 78.
`expected/smartctl.prom` has the eight names of `smartctlKeep` with `device="disk0"`, `smartctl_device_temperature` with `temperature_type="current"` too, `# TYPE … counter` for every name but `smartctl_device_smart_status` and `smartctl_device_temperature`, as smartctl_exporter declares them (ADR-004:94), and the values of the recording: `smart_status.passed` as 1, and `nvme_smart_health_information_log`'s `critical_warning`, `media_errors`, `percentage_used`, `available_spare`, `available_spare_threshold` and `num_err_log_entries`.
Add to the check the probe's cases, each building `self.lib.otelHostProbe` over `pkgs.extend (_: _: { smartmontools = smartctlStub; })`, where `smartctlStub` provides `bin/smartctl` printing `smartctl-disk0.json` when called with exactly `-j -H -A disk0` and exiting 2 otherwise, with `launchctl` a stub that, called with exactly `print system/<label>`, prints `launchctl/<label>.txt` (less a first `#` line) and exits with `launchctl/<label>.rc`, and with `textfileDir` a fresh temporary directory:

| Case | Probe arguments | Passes when |
|---|---|---|
| `runningJob` | labels `[ "org.nixos.nix-daemon" ]` | `launchd.prom` equals `expected/launchd-org.nixos.nix-daemon.prom` |
| `exitCode78` | `[ "org.nixos.exit-78" ]` | equals its expected file |
| `omnigentAlias` | `[ "org.nixos.omnigent-host-cameron" ]`, `ownerAliases` from SC | equals its expected file, and `grep -c cameron launchd.prom` is 0 |
| `notLoaded` | `[ "org.nixos.otelcol" ]` | equals its expected file |
| `jetsamKilled` | `[ "org.nixos.jetsam-killed" ]` | equals its expected file |
| `smartctl` | `devices = [ "disk0" ]` | `smartctl.prom` equals `expected/smartctl.prom` |
| `renamedIntoPlace` | all labels, `devices = [ "disk0" ]` | the directory holds exactly `launchd.prom` and `smartctl.prom`, no temporary file |

and the mutants, each replacing the line after its `# mutant: <name>` marker in the built script and running only its case: `aliasDropped` (`omnigentAlias`), `pidWritten` (`runningJob`), `missingExitCodeAsZero` (`jetsamKilled`).
The value sources: the hand-written expected files, from the decision record and the recordings, against the probe's output from the same recordings.
Run `nix build .#checks.x86_64-linux.otel-collector-darwin -L 2>&1 | tee logs/s5-evidence/2.5-red-<ts>.log | tail -n 3` and see it fail at evaluation, `attribute 'otelHostProbe' missing` (RED).
Then create `modules/lib/otel-host-probe.nix`:

```nix
# flake.lib.otelHostProbe pkgs { labels; devices; ownerAliases; textfileDir;
# launchctl ? "/bin/launchctl"; }: the darwin probe (ADR-003 items 23, 24;
# design D4), run every 60 s as _prometheus-node-exporter. For each label it
# runs exactly `launchctl print system/<label>` and writes launchd_job_state,
# launchd_job_last_exit_code and launchd_job_runs_total (ADR-004:95); for each
# device it runs exactly `smartctl -j -H -A <device>` and writes ADR-004:92's
# eight names. A job's pid is never written (ADR-004:125). launchctl's text is
# not API (launchctl(1)); a format change writes no series, which
# RuleSignalMissing reports. Each file is written to a temporary name in the
# textfile directory and renamed, so node_exporter never reads half a file.
# checks.x86_64-linux.otel-collector-darwin replaces each line marked
# `# mutant: <name>` and requires that mutant's case to fail.
{ lib, ... }:
{
  flake.lib.otelHostProbe =
    pkgs:
    { labels, devices, ownerAliases, textfileDir, launchctl ? "/bin/launchctl" }:
    pkgs.writeShellApplication {
      name = "otel-host-probe";
      runtimeInputs = [ pkgs.coreutils pkgs.gawk pkgs.jq pkgs.smartmontools ];
      text = ''
        dir=${lib.escapeShellArg textfileDir}
        aliases=${lib.escapeShellArg (lib.concatStrings (lib.mapAttrsToList (o: a: "${o} ${a}\n") ownerAliases))}
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        : > "$tmp/state"; : > "$tmp/exit"; : > "$tmp/runs"
        # A first-level field of `launchctl print`, indented by one tab.
        field() { awk -F' = ' -v k="$1" '$1 == "\t" k { print $2; exit }' "$tmp/out"; }
        for label in ${lib.escapeShellArgs labels}; do
          shown=$label
          if [[ $label == org.nixos.omnigent-host-* ]]; then
            owner=''${label#org.nixos.omnigent-host-}
            alias=$(awk -v o="$owner" '$1 == o { print $2 }' <<< "$aliases")
            # mutant: aliasDropped
            if [ -z "$alias" ]; then continue; fi; shown=org.nixos.omnigent-host-$alias
          fi
          rc=0; ${launchctl} print "system/$label" > "$tmp/out" 2>&1 || rc=$?
          if [ "$rc" != 0 ] && grep -q 'Could not find service' "$tmp/out"; then
            st=unloaded
          else
            case $(field state) in running) st=running ;; "not running") st=not_running ;; *) st=other ;; esac
            code=$(field "last exit code"); code=''${code%%:*}
            # mutant: missingExitCodeAsZero
            case $code in "(never exited)") code=0 ;; "" | *[!0-9-]* | -) code=-1 ;; esac
            echo "launchd_job_last_exit_code{launchd_label=\"$shown\"} $code" >> "$tmp/exit"
            runs=$(field runs)
            # mutant: pidWritten
            [[ $runs =~ ^[0-9]+$ ]] && echo "launchd_job_runs_total{launchd_label=\"$shown\"} $runs" >> "$tmp/runs"
          fi
          for s in running not_running unloaded other; do
            echo "launchd_job_state{launchd_label=\"$shown\",launchd_state=\"$s\"} $([ "$s" = "$st" ] && echo 1 || echo 0)" >> "$tmp/state"
          done
        done
        # … HELP/TYPE lines and the three files concatenated into "$dir/.launchd.prom.$$", then:
        mv -f "$dir/.launchd.prom.$$" "$dir/launchd.prom"
        # smartctl.prom: for each device, `smartctl -j -H -A "$device"` through a jq
        # program emitting the eight names (counter TYPE as smartctl_exporter
        # declares them), into "$dir/.smartctl.prom.$$", then renamed.
      '';
    };
}
```

The comment lines above with `…` stand for the HELP/TYPE header text of the expected files and the jq program over the recorded field names; the step writes them in full.
Run:

```bash
jj st --no-pager >/dev/null
L=logs/s5-evidence/2.5-probe-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
nix build .#checks.x86_64-linux.otel-collector-darwin -L 2>&1 | tee "$L" | grep -E '^(ok|mutant|control|FAIL)'
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/otel-collector-darwin-stats.json nix eval --option eval-cache false --raw .#.checks.x86_64-linux.otel-collector-darwin.drvPath >/dev/null && jq '.gc.totalBytes, .cpuTime' /tmp/otel-collector-darwin-stats.json | tee -a "$L"
```

Expected: the seven probe cases `ok:` beside Step 4's, `mutant aliasDropped rejected: omnigentAlias`, `mutant pidWritten rejected: runningJob`, `mutant missingExitCodeAsZero rejected: jetsamKilled`, no `FAIL`; the cost below 536,870,912 (build).
Commit, for example "Report stibnite's launchd jobs and disk health in a node_exporter textfile".

- [ ] **Step 6: The darwin fragment, its assertions seen failing first (tasks.md 2.6)**

The assertions' value sources, named before any override: the 24 h relation, the agent's rendered `otlp_http/ingress` queue against SC's `fleetBytesPerMinute` (`schema.nix:115`); the 512 MiB sum, the two rendered queues against ADR-003's envelope literal; loopback, each listener (the `otlp` receiver's endpoint, the telemetry reader's host, node_exporter's evaluated `listenAddress`, `otelcol-process`'s exporter) against the loopback pattern; no calendar, the fragment's daemons' evaluated `StartCalendarInterval` against null (design D8), over the fragment's own labels only, because `harmonia-gc` and `nix-cleanup-gcroots` keep their calendars (Task 1 Step 2); aliases, the host's evaluated `launchd.daemons` names `omnigent-host-<owner>` against SC's `ownerAliases` (as FM:283-288 judges `systemd.services` on NixOS).
Create `modules/darwin/otel-collector-agent.nix` with the options and the assertions only:

```nix
# The darwin collection fragment (ADR-003 items 1, 21-24; design D2-D4, D8),
# imported by the otel-collector agent role's darwinModule where the host's
# collect is true; the role declares the _otelcol account and the secrets.
# Relations within the host are assertions, which stibnite's activation
# evaluates before it switches.
{ config, ... }:
let
  flakeLib = config.flake.lib;
  schema = flakeLib.otelCollectorSchema;
in
{
  flake.modules.darwin.otel-collector-agent =
    { config, lib, pkgs, ... }:
    let
      cfg = config.vanixiets.otelCollector.darwin;
      gens = config.clan.core.vars.generators;
      mib = n: n * 1024 * 1024;
      own = [ "otelcol" "otelcol-process" "otel-host-probe" "prometheus-node-exporter" ];
      q = n: cfg.agentSettings.exporters.${n}.sending_queue or { };
      agentExporters = [ "otlp_http/ingress" "otlp_http/ingress-logs" ];
      isLoopback = s: builtins.match "(https?://)?(127\\.[0-9]+\\.[0-9]+\\.[0-9]+|\\[::1]|localhost)(:[0-9]+)?(/.*)?" s != null;
      owners = lib.concatMap (n: let m = builtins.match "omnigent-host-(.+)" n; in lib.optional (m != null) (builtins.head m)) (builtins.attrNames config.launchd.daemons);
      rendered = flakeLib.otelCollectorDarwin {
        hostName = config.networking.hostName;
        certFile = gens.otel-cert.files."cert.pem".path;
        keyFile = gens.otel-cert.files."key.pem".path;
        caFile = pkgs.writeText "otel-ca.crt" gens.otel-ca.files."ca.crt".value;
      };
    in
    {
      options.vanixiets.otelCollector.darwin = {
        agentSettings = lib.mkOption { type = lib.types.attrsOf lib.types.anything; description = "The agent's rendered configuration, flake.lib.otelCollectorDarwin's `agent`."; };
        processSettings = lib.mkOption { type = lib.types.attrsOf lib.types.anything; description = "otelcol-process's rendered configuration."; };
      };
      config = {
        vanixiets.otelCollector.darwin = { agentSettings = rendered.agent; processSettings = rendered.process; };
        assertions = [
          { assertion = lib.all (n: (q n).storage or null == "file_storage" && (q n).sizer or null == "bytes"
                && (cfg.agentSettings.exporters.${n}.retry_on_failure.max_elapsed_time or null) == "0s") agentExporters
              && ((q "otlp_http/ingress").queue_size or 0) >= 24 * 60 * schema.fleetBytesPerMinute;
            message = "otel-collector darwin agent: both ingress exporters must queue in file_storage by bytes with unlimited retry, and the metrics queue must hold 24 h at fleetBytesPerMinute (ADR-003 envelope; design D2)."; }
          { assertion = lib.foldl' (s: n: s + ((q n).queue_size or 0)) 0 agentExporters < mib 512;
            message = "otel-collector darwin agent: the ingress exporters' queues must sum below 512 MiB (ADR-003 envelope)."; }
          { assertion = lib.all isLoopback ([ cfg.agentSettings.receivers.otlp.protocols.http.endpoint
                config.services.prometheus.exporters.node.listenAddress
                cfg.processSettings.exporters."otlp_http/agent".endpoint ]
              ++ map (r: r.pull.exporter.prometheus.host) cfg.agentSettings.service.telemetry.metrics.readers);
            message = "otel-collector darwin agent: every receiver, telemetry and node_exporter listener and otelcol-process's exporter must be on loopback (ADR-003 items 18-23)."; }
          { assertion = lib.all (n: (config.launchd.daemons.${n}.serviceConfig.StartCalendarInterval or null) == null) (builtins.filter (n: config.launchd.daemons ? ${n}) own);
            message = "otel-collector darwin agent: ${builtins.toJSON own} must use KeepAlive or StartInterval, never StartCalendarInterval, whose local-time firings coalesce at wake (design D8)."; }
          { assertion = lib.all (o: schema.ownerAliases ? ${o}) owners
              && lib.all (a: lib.all (o: !(lib.hasInfix o a)) owners) (builtins.attrValues schema.ownerAliases);
            message = "otel-collector darwin agent: every omnigent-host-<owner> launchd daemon needs an alias in ownerAliases that does not contain an owner's name; owners ${builtins.toJSON owners}"; }
        ];
      };
    };
}
```

Step 3 of Task 3 adds `otel-envelope` to `own`.
Create `logs/s5-evidence/2.6-overrides.nix`, which takes the flake and returns `config.system.build.toplevel.drvPath` of five `darwinConfigurations.stibnite.extendModules` evaluations: `queue64` (`vanixiets.otelCollector.darwin.agentSettings.exporters."otlp_http/ingress".sending_queue.queue_size = lib.mkForce (64 * 1024 * 1024)`), `queues600` (`…"otlp_http/ingress-logs".sending_queue.queue_size = lib.mkForce (200 * 1024 * 1024)`), `nodeWildcard` (`services.prometheus.exporters.node.listenAddress = lib.mkForce ""`), `probeCalendar` (`launchd.daemons.otel-host-probe.serviceConfig.StartCalendarInterval = [ { Minute = 0; } ]`) and `omnigentNobody` (`launchd.daemons.omnigent-host-nobody.command = "/usr/bin/true"`).
In the scratch tree (Step 1's form, at the working copy's commit, with stibnite's `collect = false` removed), run each before the daemons exist:

```bash
jj st --no-pager >/dev/null
git -C $REPO worktree add --detach $SCRATCH "$(jj log --no-pager --no-graph -r @ -T commit_id)"
# in $SCRATCH, remove stibnite's `collect = false;` from modules/lib/observability-hosts.nix
L=$REPO/logs/s5-evidence/2.6-assertions-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
cd $SCRATCH
for o in queue64 queues600 nodeWildcard probeCalendar omnigentNobody; do echo "== $o"
  nix eval --impure --raw --expr "(import $REPO/logs/s5-evidence/2.6-overrides.nix (builtins.getFlake (toString ./.))).$o" 2>&1 | grep -o 'otel-collector darwin agent[^(]*' | head -n 1
done 2>&1 | tee "$L"
cd $REPO
```

Expected: `queue64` and `queues600` print their queue messages, `omnigentNobody` the alias message naming `nobody`; `nodeWildcard` and `probeCalendar` fail on a missing attribute or print nothing, because node_exporter and the probe are not declared yet, and are run again below (RED).
Then add to the fragment's `config`:

```nix
        # Ordered as omnigent-host's (modules/darwin/omnigent-host.nix:453-475):
        # after users are created, before launchd loads the jobs. /run is
        # emptied at boot on darwin, so state lives under /var (design D2).
        system.activationScripts.launchd.text = lib.mkBefore ''
          install -d -m 0700 -o _otelcol -g _otelcol /var/lib/opentelemetry-collector /var/lib/opentelemetry-collector/queue /var/lib/otel-envelope /var/log/otelcol
          install -d -m 0755 -o _prometheus-node-exporter -g _prometheus-node-exporter /var/lib/prometheus-node-exporter/textfile
        '';

        services.prometheus.exporters.node = { enable = true; inherit (rendered.node) listenAddress port extraFlags; };

        launchd.daemons = {
          # `script` runs behind /bin/wait4path /nix/store (nix-darwin
          # modules/launchd/default.nix:83-95); the key's wait covers boot,
          # before sops-install-secrets has run (design D2). The certificate's
          # hash changes the plist on a reissue, so nix-darwin reloads the job
          # (design D5).
          otelcol = {
            script = ''
              /bin/wait4path ${gens.otel-cert.files."key.pem".path}
              exec ${lib.getExe' pkgs.opentelemetry-collector-contrib "otelcol-contrib"} --config ${(pkgs.formats.yaml { }).generate "otelcol-agent.yaml" cfg.agentSettings}
            '';
            environment.OTEL_CERT_SHA256 = builtins.hashString "sha256" gens.otel-cert.files."cert.pem".value;
            serviceConfig = {
              UserName = "_otelcol"; GroupName = "_otelcol";
              KeepAlive = true; RunAtLoad = true;
              StandardOutPath = "/var/log/otelcol/otelcol.log"; StandardErrorPath = "/var/log/otelcol/otelcol.log";
            };
          };
          # Root, for proc_pidinfo over other users' processes; no listener and
          # no credential (design D3; A8 item 4).
          otelcol-process = {
            script = "exec ${lib.getExe' pkgs.opentelemetry-collector-contrib "otelcol-contrib"} --config ${(pkgs.formats.yaml { }).generate "otelcol-process.yaml" cfg.processSettings}";
            serviceConfig = {
              KeepAlive = true; RunAtLoad = true;
              StandardOutPath = "/var/log/otelcol/otelcol-process.log"; StandardErrorPath = "/var/log/otelcol/otelcol-process.log";
            };
          };
          otel-host-probe = {
            script = "exec ${lib.getExe (flakeLib.otelHostProbe pkgs {
              # ADR-004:121: the allow-listed labels this host defines.
              labels = builtins.filter (l: lib.any (p: builtins.match (builtins.replaceStrings [ "." "*" ] [ "[.]" ".*" ] p) l != null) schema.launchdLabels)
                (lib.mapAttrsToList (_: d: d.serviceConfig.Label) config.launchd.daemons);
              devices = flakeLib.observabilityHosts.${config.networking.hostName}.smartDevices;
              inherit (schema) ownerAliases;
              textfileDir = "/var/lib/prometheus-node-exporter/textfile";
            })}";
            serviceConfig = {
              UserName = "_prometheus-node-exporter"; GroupName = "_prometheus-node-exporter";
              StartInterval = 60; RunAtLoad = true;
              StandardOutPath = "/var/log/otelcol/otel-host-probe.log"; StandardErrorPath = "/var/log/otelcol/otel-host-probe.log";
            };
          };
        };
```

`/var/log/otelcol` is `_otelcol`'s and mode 0700, so the probe's log goes to the node_exporter's home instead if launchd cannot open it as `_prometheus-node-exporter` [INFERENCE: launchd opens the log paths as root before dropping privileges, as `omnigent-host.nix:453` relies on; the activation in Task 4 shows which]; the step that sees otherwise moves the path to `/var/lib/prometheus-node-exporter/otel-host-probe.log`.
Then the loopback and calendar overrides again, and the unmodified evaluation, in the scratch tree, appending to `$L`; then a build of the collecting toplevel on stibnite:

```bash
cd $SCRATCH
for o in nodeWildcard probeCalendar; do echo "== $o"
  nix eval --impure --raw --expr "(import $REPO/logs/s5-evidence/2.6-overrides.nix (builtins.getFlake (toString ./.))).$o" 2>&1 | grep -o 'otel-collector darwin agent[^(]*' | head -n 1
done 2>&1 | tee -a "$L"
nix eval --raw .#darwinConfigurations.stibnite.config.system.build.toplevel.drvPath 2>&1 | tee -a "$L"; echo
nix eval --json .#darwinConfigurations.stibnite.config.launchd.daemons --apply 'd: builtins.mapAttrs (_: v: { inherit (v.serviceConfig) UserName KeepAlive StartInterval StartCalendarInterval; args = v.serviceConfig.ProgramArguments; }) (builtins.intersectAttrs { otelcol = 0; otelcol-process = 0; otel-host-probe = 0; prometheus-node-exporter = 0; } d)' | tee -a "$L"
nix eval --json .#darwinConfigurations.stibnite.config.launchd.daemons.otelcol.serviceConfig.EnvironmentVariables | tee -a "$L"
nix build --no-link --print-out-paths .#darwinConfigurations.stibnite.config.system.build.toplevel 2>&1 | tail -n 1 | tee -a "$L"
cd $REPO && git worktree remove --force $SCRATCH
```

Expected: `nodeWildcard` prints the loopback message and `probeCalendar` the calendar message (negative controls); a drvPath; four daemons, `otelcol` `_otelcol` `KeepAlive` true, `otelcol-process` with no `UserName`, `otel-host-probe` `_prometheus-node-exporter` with `StartInterval` 60, `prometheus-node-exporter` `KeepAlive` true, every `StartCalendarInterval` null and every `args` beginning `/bin/sh -c /bin/wait4path /nix/store && exec`; `OTEL_CERT_SHA256` equal to `sha256sum vars/per-machine/stibnite/otel-cert/cert.pem/value`; a built toplevel store path, nothing activated (evaluation, build, negative control).
The launchd-wait4path assertion (`modules/darwin/launchd-wait4path.nix:41-46`) holds, because every daemon above uses `script`.
Then evaluate stibnite at the working copy, where `collect` is false: `nix eval --raw .#darwinConfigurations.stibnite.config.system.build.toplevel.drvPath` and `nix eval --json .#darwinConfigurations.stibnite.config.launchd.daemons --apply 'd: builtins.filter (n: builtins.match "otel.*|prometheus-node-exporter" n != null) (builtins.attrNames d)'`, expecting a drvPath and `[]`.

- [ ] **Step 7: Deploy records from the darwin agent (tasks.md 2.7)**

In `modules/lib/otel-collector-darwin.nix`, add to `agent` what FM:526-571 gives every NixOS agent host, with the same receiver id and settings, so the stored rows have the same shape:

```nix
        receivers."file_log/deploy-record" = {
          include = [ flakeLib.devloopCollection.deployRecordFile ];
          start_at = "beginning";
          storage = "file_storage";
          operators = [
            { type = "json_parser"; id = "parse-line"; }
            (flakeLib.devloopCollection.keepAttributes (map (column: column.name) schema.devloop.tables.deploy_record.columns))
            flakeLib.devloopCollection.dropBody
          ];
        };
        processors."resource/devloop-deploy_record".attributes = [
          { key = "vanixiets.database"; value = "devloop"; action = "upsert"; }
          { key = "vanixiets.table"; value = "deploy_record"; action = "upsert"; }
          { key = "host.name"; value = hostName; action = "upsert"; }
        ];
        service.pipelines."logs/devloop-deploy_record" = {
          receivers = [ "file_log/deploy-record" ];
          processors = [ "memory_limiter" "resource/devloop-deploy_record" ];
          exporters = [ "otlp_http/ingress-logs" ];
        };
```

From here `otlp_http/ingress-logs`, configured since Step 4, has its pipeline; if Step 4's validate case rejected the exporter as unused, Step 4 adds this pipeline in its place and this step only runs the verification below.
Run:

```bash
jj st --no-pager >/dev/null
L=logs/s5-evidence/2.7-deploy-record-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
nix eval --json .#lib.otelCollectorDarwin --apply 'f: (f { hostName = "stibnite"; certFile = "c"; keyFile = "k"; caFile = "a"; }).agent.service.pipelines."logs/devloop-deploy_record"' | tee "$L"
diff <(nix eval --json .#lib.otelCollectorDarwin --apply 'f: (f { hostName = "x"; certFile = "c"; keyFile = "k"; caFile = "a"; }).agent.receivers."file_log/deploy-record"') \
     <(nix eval --json '.#nixosConfigurations.electrum.config.services.opentelemetry-collector.settings.receivers."file_log/deploy-record"') && echo "receiver equal to electrum's" | tee -a "$L"
nix build .#checks.x86_64-linux.otel-collector-darwin -L 2>&1 | tee -a "$L" | grep -E '^(ok: validate|FAIL)'
```

Expected: `{"exporters":["otlp_http/ingress-logs"],"processors":["memory_limiter","resource/devloop-deploy_record"],"receivers":["file_log/deploy-record"]}`; `receiver equal to electrum's`; both `ok: validate` lines, the agent's now covering the logs pipeline (evaluation, build).
The renderer is a function of the credential paths, so both calls pass placeholder paths, as tasks.md 2.7's verify does.

- [ ] **Step 8: Evaluate, cost and commit**

Run, appending the figures beside Task 1's:

```bash
L=logs/s5-evidence/2.8-cost-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
for c in x86_64-linux.otel-collector-darwin x86_64-linux.otel-collector-config x86_64-linux.nixos-magnetite aarch64-darwin.darwin-stibnite; do
  s=/tmp/${c#*.}-stats.json
  NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=$s nix eval --option eval-cache false --raw ".#.checks.$c.drvPath" >/dev/null
  printf '%s %s %s\n' "$c" "$(jq '.gc.totalBytes // 0' "$s")" "$(jq '.cpuTime // 0' "$s")"
done 2>&1 | tee "$L"
nix eval --raw .#nixosConfigurations.magnetite.config.system.build.toplevel.drvPath | tee -a "$L"; echo
```

Expected: `otel-collector-darwin` and `otel-collector-config` below 536,870,912; the two machine checks recorded beside 1.2's; magnetite evaluates (evaluation).
Commit the work of Steps 4 to 7 not yet committed as changes off `main@origin` after `nix fmt`, with plain messages, for example "Run the collector agent, the process collector, node_exporter and the probe on darwin under launchd".
