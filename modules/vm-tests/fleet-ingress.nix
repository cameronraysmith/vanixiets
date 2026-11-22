# Runtime test of the fleet's certificate-authenticated ingest
# (openspec/changes/stand-up-linux-fleet-collection, design D7, D11, D12;
# tasks.md 3.4).
#
# One systemd-nspawn container `store`, on a builder that advertises
# uid-range (magnetite), holds:
#   - the store with magnetite's databases, its schema job and the devloop
#     tables and pipelines;
#   - opentelemetry-collector.service from the agent and ingress fragments,
#     the ingress host, with otlp/mesh on 127.0.0.1:4319, otlp/mesh-tincr on
#     127.0.0.1:4320, and throwaway
#     certificates from flake.lib.otelTestPki;
#   - agent-collector.service, electrum's evaluated non-ingress collector
#     configuration exporting over mTLS to that receiver, with its queue,
#     telemetry (127.0.0.1:8889) and deploy-record file moved into its own
#     state directory and the zerotierone job removed;
#   - agent-session-collector.service, pyrite's evaluated agent-session
#     pipelines with their receiver otlp/local, the one listener here on the
#     harnesses' 127.0.0.1:4318, and their exporters, pointed at otlp/mesh,
#     with telemetry on 127.0.0.1:8890 (agent-session-telemetry design D12);
#   - the store's agent.session_event table and pipeline as magnetite
#     declares them, and a file exporter on the ingress's logs/ingress that
#     records every log record crossing the mesh, for the canary;
#   - otel-envelope.service from the agent fragment and agent-envelope.service,
#     the same unit for the agent collector, both started only by the cases;
#   - the failure notifier over all four units, posting through an ntfy-send
#     that records `<topic>|<title>` in /run/ntfy-posts.
# The container's loopback stands in for magnetite's ZeroTier address; the
# real address and refusal are observed at acceptance (design D12). It lives
# in the non-gating vmTests lane: on-demand evidence, not pull-request
# coverage.
{ self, inputs, ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    {
      vmTests = lib.optionalAttrs (system == "x86_64-linux") {
        fleet-ingress =
          let
            # The flake overlay carries greptimedb-bin; the recording
            # ntfy-send replaces the real one for the notifier.
            nodePkgs = import inputs.nixpkgs {
              inherit system;
              config.allowUnfree = true;
              overlays = [
                self.overlays.default
                (final: _prev: {
                  ntfy-send = final.writeShellScriptBin "ntfy-send" ''
                    printf '%s|%s\n' "$2" "$1" >> /run/ntfy-posts
                  '';
                })
              ];
            };
            reference = self.nixosConfigurations.magnetite.config;
            inherit (reference.services.greptimedb) databases;
            usersGenerator = reference.clan.core.vars.generators.greptimedb-users;
            devloop = self.lib.devloopCollection;
            pki = self.lib.otelTestPki pkgs;
            vars = "/run/fleet-ingress-vars";
            agentState = "/var/lib/agent-collector";
            agentDeployRecord = "${agentState}/deploy-record.jsonl";
            credentialConsumers = [
              "greptimedb.service"
              "greptimedb-schema.service"
              "opentelemetry-collector.service"
            ];

            # electrum's collector configuration as the agent role renders it
            # on a host whose `collect` is true, pointed at this container.
            # Its own telemetry moves to 8889, so its otelcol scrape follows.
            electrum = self.nixosConfigurations.electrum.config.services.opentelemetry-collector.settings;
            agentSettings =
              let
                exporter =
                  name:
                  electrum.exporters.${name}
                  // {
                    endpoint = "https://127.0.0.1:4319";
                    tls = electrum.exporters.${name}.tls // {
                      ca_file = "${pki}/ca.crt";
                      cert_file = "${pki}/agent.crt";
                      key_file = "${pki}/agent.key";
                    };
                  };
                scrapeConfigs = map (
                  job:
                  if job.job_name == "otelcol" then
                    job // { static_configs = [ { targets = [ "127.0.0.1:8889" ]; } ]; }
                  else
                    job
                ) electrum.receivers.prometheus.config.scrape_configs;
              in
              electrum
              // {
                exporters = electrum.exporters // {
                  "otlp_http/ingress" = exporter "otlp_http/ingress";
                  "otlp_http/ingress-logs" = exporter "otlp_http/ingress-logs";
                };
                extensions = electrum.extensions // {
                  file_storage = electrum.extensions.file_storage // {
                    directory = "${agentState}/queue";
                  };
                };
                receivers = builtins.removeAttrs electrum.receivers [ "prometheus/zerotier" ] // {
                  prometheus.config.scrape_configs = scrapeConfigs;
                  "file_log/deploy-record" = electrum.receivers."file_log/deploy-record" // {
                    include = [ agentDeployRecord ];
                  };
                };
                service = electrum.service // {
                  telemetry.metrics.readers = [
                    {
                      pull.exporter.prometheus = {
                        host = "127.0.0.1";
                        port = 8889;
                      };
                    }
                  ];
                  pipelines = electrum.service.pipelines // {
                    "metrics/host" = electrum.service.pipelines."metrics/host" // {
                      receivers = lib.remove "prometheus/zerotier" electrum.service.pipelines."metrics/host".receivers;
                    };
                  };
                };
              };

            # pyrite's agent-session path as the agent role renders it on a
            # host whose agentTelemetry is true (agent-session-telemetry design
            # D12): the receivers, processors and exporters its agent-session
            # pipelines name, taken from the evaluated configuration so the
            # test follows the module, with the exporters pointed at this
            # container's otlp/mesh and the queue and telemetry moved aside.
            pyrite = self.nixosConfigurations.pyrite.config.services.opentelemetry-collector.settings;
            agentSessionState = "/var/lib/agent-session-collector";
            agentSessionSettings =
              let
                # Every pyrite pipeline that consumes otlp/local, whatever its
                # name, so a third consumer fails here rather than going untested.
                pipelines = lib.filterAttrs (
                  _: pipeline: builtins.elem "otlp/local" (pipeline.receivers or [ ])
                ) pyrite.service.pipelines;
                used = kind: lib.unique (lib.concatMap (pipeline: pipeline.${kind}) (lib.attrValues pipelines));
              in
              assert lib.assertMsg
                (
                  lib.attrNames pipelines == [
                    "logs/agent-session"
                    "metrics/agent-session"
                    "traces/agent-session"
                  ]
                  && used "receivers" == [ "otlp/local" ]
                  && pyrite.receivers."otlp/local" == { protocols.http.endpoint = "127.0.0.1:4318"; }
                )
                "fleet-ingress: pyrite's otlp/local is not exactly 127.0.0.1:4318 feeding the three agent-session pipelines";
              {
                receivers = lib.genAttrs (used "receivers") (name: pyrite.receivers.${name});
                processors = lib.genAttrs (used "processors") (name: pyrite.processors.${name});
                exporters =
                  lib.genAttrs (used "exporters") (
                    name:
                    pyrite.exporters.${name}
                    // {
                      endpoint = "https://127.0.0.1:4319";
                      tls = pyrite.exporters.${name}.tls // {
                        ca_file = "${pki}/ca.crt";
                        cert_file = "${pki}/agent.crt";
                        key_file = "${pki}/agent.key";
                      };
                    }
                  )
                  # What leaves the host, beside each pipeline's own exporter,
                  # one JSON export per line, so the canary reads it before the
                  # store's pipeline closes the columns again.
                  // lib.mapAttrs' (
                    name: _:
                    lib.nameValuePair "file/tap-${lib.removeSuffix "/agent-session" name}" {
                      path = "${agentSessionState}/tap-${lib.removeSuffix "/agent-session" name}.jsonl";
                    }
                  ) pipelines;
                extensions.file_storage = pyrite.extensions.file_storage // {
                  directory = "${agentSessionState}/queue";
                };
                service = {
                  extensions = [ "file_storage" ];
                  pipelines = lib.mapAttrs (
                    name: pipeline:
                    pipeline
                    // {
                      exporters = pipeline.exporters ++ [ "file/tap-${lib.removeSuffix "/agent-session" name}" ];
                    }
                  ) pipelines;
                  telemetry.metrics.readers = [
                    {
                      pull.exporter.prometheus = {
                        host = "127.0.0.1";
                        port = 8890;
                      };
                    }
                  ];
                };
              };
            agentExecStart =
              collector: settings:
              "${lib.getExe collector} --config=file:${
                (pkgs.formats.yaml { }).generate "agent-collector.yaml" settings
              }";

            # Each mutant is a unit and the module or settings that change it;
            # helpers.py installs its ExecStart as a runtime drop-in.
            ingressMutants = {
              # The store exporter's queue at two requests (design D12).
              storeQueueTwo =
                { lib, ... }:
                {
                  services.opentelemetry-collector.settings.exporters."otlp_http/fleet".sending_queue = {
                    sizer = lib.mkForce "requests";
                    queue_size = lib.mkForce 2;
                  };
                };
              # A limiter below the collector's own footprint refuses all data.
              limiterRefusing =
                { lib, ... }:
                {
                  services.opentelemetry-collector.settings.processors.memory_limiter = {
                    limit_mib = lib.mkForce 2;
                    spike_limit_mib = lib.mkForce 1;
                  };
                };
              # design D11: the receiver's client CA file is missing.
              absentClientCa =
                { lib, ... }:
                {
                  services.opentelemetry-collector.settings.receivers."otlp/mesh".protocols.http.tls.client_ca_file =
                    lib.mkForce "/run/fleet-ingress/absent-ca.crt";
                };
            };
            agentMutants = {
              # The agent's metrics queue at 64 KiB, a few minutes of this
              # container's agent (about 16 KiB a minute), so it fills
              # within the case.
              queue64KiB = lib.recursiveUpdate agentSettings {
                exporters."otlp_http/ingress".sending_queue.queue_size = 64 * 1024;
              };
            };

            # Each case prints `=== case <name>` first and `ok: <name>` last.
            refusal = ''
              print("=== case refusal", flush=True)
              fresh_start()
              PKI = config()["pki"]
              # The agent stays stopped, so the ingress receivers accept nothing else.
              store.succeed(f"systemctl stop {AGENT}.service")
              time.sleep(5)
              # Both receivers, otlp/mesh (ZeroTier) and otlp/mesh-tincr, by
              # their loopback ports here.
              receivers = [("otlp/mesh", 4319), ("otlp/mesh-tincr", 4320)]
              def receivers_accepted():
                  return {name: metric(INGRESS_PORT, "otelcol_receiver_accepted_metric_points", {"receiver": name}) for name, _ in receivers}
              accepted_before = receivers_accepted()
              cursor = store.succeed(
                  f"journalctl -u {INGRESS} -n 0 --show-cursor -o cat | sed -n 's/^-- cursor: //p'"
              ).strip()
              # TLS 1.3 rejects a client certificate after the client's
              # Finished, so curl meets the alert while sending (55) or
              # reading (56), as timing has it; TLS 1.2 fails the handshake (35).
              attempts = [
                  ("no client certificate", "", (55, 56), "tlsv13 alert certificate required"),
                  ("a rogue CA's certificate", f"--cert {PKI}/rogue.crt --key {PKI}/rogue.key", (55, 56), "tlsv1 alert unknown ca"),
                  ("TLS 1.2 at most", f"--cert {PKI}/agent.crt --key {PKI}/agent.key --tls-max 1.2", (35,), "tlsv1 alert protocol version"),
              ]
              for receiver, port in receivers:
                  for what, args, want, error in attempts:
                      code, out = store.execute(
                          f"curl -sS --cacert {PKI}/ca.crt {args} -H 'Content-Type: application/json' "
                          f"--data '{{}}' https://127.0.0.1:{port}/v1/metrics 2>&1"
                      )
                      print(f"  {receiver}, {what}: exit {code}: {out.strip()}", flush=True)
                      assert code in want and error in out, (receiver, what, code, out)
              expected = len(receivers) * len(attempts)
              handshakes = f"journalctl -u {INGRESS} --after-cursor={shlex.quote(cursor)} -o cat | grep -c 'TLS handshake error'"
              store.wait_until_succeeds(f"test $({handshakes}) -ge {expected}", timeout=30)
              print(store.succeed(f"journalctl -u {INGRESS} --after-cursor={shlex.quote(cursor)} -o cat | grep 'TLS handshake error'"), flush=True)
              assert store.succeed(handshakes).strip() == str(expected)
              assert receivers_accepted() == accepted_before, (accepted_before, receivers_accepted())
              store.succeed(f"systemctl start {AGENT}.service")
              wait_telemetry(AGENT_PORT)
              print("ok: refusal", flush=True)
            '';

            delivery = ''
              print("=== case delivery", flush=True)
              fresh_start()
              for i in range(3):
                  store.succeed(f"{config()['deployRecord']} /nix/store/{i:032d}-fleet-ingress-{i}")
                  time.sleep(1.1)


              def electrum_stored():
                  hosts = [r["metric"].get("host_name") for r in promql("count by (host_name) (system_memory_usage_bytes)")]
                  print(f"  hosts with system_memory_usage_bytes: {hosts}", flush=True)
                  return "electrum" in hosts


              def deploy_rows():
                  return gsql("SELECT count(*) FROM deploy_record WHERE host = 'electrum'", "devloop")[0][0]


              wait_for(electrum_stored, "electrum's memory series in fleet", 180)
              wait_for(lambda: deploy_rows() >= 3, "electrum's three deploy records", 180)
              assert deploy_rows() == 3, deploy_rows()
              failed = send_failed()
              assert failed == {INGRESS_PORT: 0, AGENT_PORT: 0}, failed
              print(f"ok: delivery: electrum in fleet, 3 deploy_record rows, send_failed {failed}", flush=True)
            '';

            backPressure = ''
              print("=== case backPressure", flush=True)
              fresh_start()


              def ingress_loss_lines(lines):
                  return [l for l in lines if l.startswith("otel-envelope: C4 loss: FAIL")]


              def runs():
                  # Back-pressure is not loss: the agent passes, and the
                  # ingress counts neither otlp/mesh refusals nor its store
                  # exporters' enqueue failures as loss (design D7).
                  code, lines = envelope("agent-envelope")
                  assert code == 0, lines
                  code, lines = envelope("otel-envelope")
                  loss = ingress_loss_lines(lines)
                  assert not any("otlp/mesh" in l or "enqueue_failed" in l for l in loss), loss


              collector_with(INGRESS, "storeQueueTwo")
              wait_drained()
              agent0, mesh0 = stable_pair()
              accepted = -mesh0
              refused = 0
              enqueue_failed = 0
              queue = []
              runs()
              store.succeed("systemctl stop greptimedb.service")
              for _ in range(6):
                  time.sleep(30)
                  queue.append(agent_queue())
                  runs()
              _, mesh = stable_pair()
              accepted += mesh
              refused += metric(INGRESS_PORT, "otelcol_receiver_refused_metric_points", {"receiver": "otlp/mesh"})
              enqueue_failed += metric(INGRESS_PORT, "otelcol_exporter_enqueue_failed_metric_points", {"exporter": "otlp_http/fleet"})
              collector_with(INGRESS, "limiterRefusing")
              for _ in range(4):
                  time.sleep(30)
                  queue.append(agent_queue())
                  runs()
              _, mesh = stable_pair()
              accepted += mesh
              refused += metric(INGRESS_PORT, "otelcol_receiver_refused_metric_points", {"receiver": "otlp/mesh"})
              store.succeed("systemctl start greptimedb.service")
              store.wait_until_succeeds("curl -sf http://127.0.0.1:4000/health", timeout=120)
              collector_with(INGRESS, None)
              wait_drained()
              runs()
              agent1, mesh = stable_pair()
              accepted += mesh
              print(f"  agent queue samples {queue}; mesh refused {refused}; fleet enqueue_failed {enqueue_failed}", flush=True)
              print(f"  agent sent {agent1 - agent0}; ingress accepted on otlp/mesh {accepted}", flush=True)
              assert max(queue) > 0 and agent_queue() == 0, queue
              assert refused > 0 and enqueue_failed > 0, (refused, enqueue_failed)
              assert agent1 - agent0 == accepted, (agent1 - agent0, accepted)
              print("ok: backPressure", flush=True)
            '';

            lossControls = ''
              print("=== case lossControls", flush=True)
              fresh_start()


              def controlled(unit, clause, *detail):
                  """A run that must fail `clause` with each detail in its line."""
                  code, lines = envelope(unit)
                  assert code == 1 and clause in failing(lines), (unit, clause, lines)
                  line = next(l for l in lines if l.startswith(f"otel-envelope: {clause}: FAIL"))
                  assert all(d in line for d in detail), (detail, line)
                  print(f"  negative control {clause}: {line}", flush=True)


              def passes(unit):
                  code, lines = envelope(unit)
                  assert code == 0, (unit, lines)


              passes("agent-envelope")
              # C1: the agent's collector stopped.
              store.succeed(f"systemctl stop {AGENT}.service")
              assert envelope("agent-envelope")[0] == 0
              controlled("agent-envelope", "C1 telemetry")
              store.succeed(f"systemctl start {AGENT}.service")
              wait_telemetry(AGENT_PORT)
              passes("agent-envelope")

              # C2: node_exporter stopped.
              store.succeed("systemctl stop prometheus-node-exporter.service")
              assert envelope("agent-envelope")[0] == 0
              controlled("agent-envelope", "C2 targets", "node")
              store.succeed("systemctl start prometheus-node-exporter.service")
              store.wait_until_succeeds("curl -sf -o /dev/null http://127.0.0.1:9100/metrics", timeout=60)
              passes("agent-envelope")

              # C3, then C4: a 64 KiB agent queue with the ingress stopped.
              collector_with(AGENT, "queue64KiB")
              store.succeed(f"systemctl stop {INGRESS}.service")
              capacity = metric(AGENT_PORT, "otelcol_exporter_queue_capacity", {"exporter": "otlp_http/ingress"})
              assert capacity == 64 * 1024, capacity
              wait_for(lambda: agent_queue() * 10 >= capacity * 9, "the 64 KiB queue at 90 %", 1200)
              controlled("agent-envelope", "C3 queue", "otlp_http/ingress")
              enqueued = metric(AGENT_PORT, "otelcol_exporter_enqueue_failed_metric_points", {"exporter": "otlp_http/ingress"})
              wait_for(
                  lambda: metric(AGENT_PORT, "otelcol_exporter_enqueue_failed_metric_points", {"exporter": "otlp_http/ingress"}) > enqueued,
                  "more enqueue failures",
                  600,
              )
              controlled("agent-envelope", "C4 loss", "enqueue_failed")
              collector_with(AGENT, None)
              store.succeed(f"systemctl start {INGRESS}.service")
              wait_telemetry(INGRESS_PORT)
              wait_drained()
              passes("agent-envelope")

              # C4 on the ingress: its own memory scrape refused.
              envelope("otel-envelope")
              collector_with(INGRESS, "limiterRefusing")
              wait_for(
                  lambda: metric(INGRESS_PORT, "otelcol_receiver_refused_metric_points", {"receiver": "host_metrics/memory"}) > 0,
                  "a refused host_metrics/memory scrape",
                  300,
              )
              controlled("otel-envelope", "C4 loss", "host_metrics/memory")
              collector_with(INGRESS, None)
              wait_drained()
              passes("otel-envelope")
              passes("agent-envelope")
              print("ok: lossControls", flush=True)
            '';

            crashLoop = ''
              print("=== case crashLoop", flush=True)
              fresh_start()
              sent0, mesh0 = stable_pair()
              sent = -sent0


              def crash_run():
                  code, lines = envelope("agent-envelope")
                  assert "C4 loss" not in failing(lines), lines
                  if code != 0:
                      # Only a second run in a row without telemetry fails.
                      assert failing(lines) in (["C1 telemetry"], ["C1 telemetry", "C2 targets"]), lines


              envelope("agent-envelope")
              for kill in range(4):
                  sent += agent_sent()
                  store.succeed(f"systemctl kill -s KILL {AGENT}.service")
                  crash_run()
                  wait_telemetry(AGENT_PORT)
                  code, lines = envelope("agent-envelope")
                  assert code == 0, lines
                  if kill < 3:
                      time.sleep(120)
              wait_drained()
              last, mesh = stable_pair()
              sent += last
              accepted = mesh - mesh0
              print(f"  agent sent {sent} over four starts; ingress accepted on otlp/mesh {accepted}", flush=True)
              # A kill between the ingress's accept and the agent's count
              # resends a request, so the ingress may count more, never less.
              assert accepted >= sent, (sent, accepted)
              print("ok: crashLoop", flush=True)
            '';

            longRun = ''
              print("=== case longRun", flush=True)
              fresh_start()
              # A receiver's refused series appears at its first scrape, so
              # every receiver runs once (60 s interval) before the runs.
              time.sleep(70)
              loss = re.compile(r"^otelcol_(exporter_send_failed|receiver_refused|exporter_enqueue_failed)_[a-z_]+\{")
              targets = 2  # node and otelcol
              sizes = []
              for run in range(10):
                  code, lines = envelope("agent-envelope")
                  assert code == 0, lines
                  start, end = (
                      int(store.succeed(f"systemctl show -p {p} --value agent-envelope.service"))
                      for p in ("ExecMainStartTimestampMonotonic", "ExecMainExitTimestampMonotonic")
                  )
                  assert end - start < 240 * 1000000, (start, end)
                  series = sum(
                      1 for l in store.succeed(f"curl -sS http://127.0.0.1:{AGENT_PORT}/metrics").splitlines() if loss.match(l)
                  )
                  lines_ = int(store.succeed("wc -l < /var/lib/private/agent-envelope/state"))
                  print(f"  run {run + 1}: {(end - start) / 1e6:.1f} s, state {lines_} lines, {series} loss series", flush=True)
                  assert lines_ == series + 1 + targets, (lines_, series)
                  sizes.append(lines_)
                  time.sleep(20)
              assert len(set(sizes)) == 1, sizes
              print("ok: longRun", flush=True)
            '';

            # F64: a process whose comm fills the kernel's 15 bytes and whose
            # argv[0] carries its command line, as Chromium's retitled
            # processes do, is stored under its executable's name alone.
            processName = ''
              print("=== case processName", flush=True)
              fresh_start()
              EXE = "abcdefghijklmnop-x"
              TITLE = f"/tmp/{EXE} --field-trial-handle=3,i,7729614572803203038"
              store.succeed(
                  f"ln -sf ${pkgs.python3}/bin/python3 /tmp/{EXE}",
                  "systemd-run --unit=f64-title --property=Type=exec bash -c "
                  + shlex.quote(f"exec -a {shlex.quote(TITLE)} /tmp/{EXE} -c 'import time; b = b\"x\" * (96 << 20); time.sleep(3600)'"),
              )
              pid = store.succeed("systemctl show -p MainPID --value f64-title.service").strip()
              store.wait_until_succeeds(f"test \"$(cat /proc/{pid}/comm)\" = {EXE[:15]}", timeout=30)
              assert store.succeed(f"tr '\\0' '\\n' < /proc/{pid}/cmdline | head -n 1").strip() == TITLE
              SQL = (
                  "SELECT host_name, process_executable_name FROM process_memory_usage_bytes "
                  f"WHERE process_executable_name LIKE '{EXE[:15]}%' GROUP BY host_name, process_executable_name ORDER BY host_name"
              )


              def names():
                  rows = gsql(SQL)
                  print(f"  {rows}", flush=True)
                  return rows


              wait_for(lambda: {row[0] for row in names()} == {"electrum", "store"}, "both collectors' scrapes of the process", 240)
              assert names() == [["electrum", EXE], ["store", EXE]], names()
              store.succeed("systemctl stop f64-title.service", f"rm /tmp/{EXE}")
              print("ok: processName", flush=True)
            '';

            absentClientCa = ''
              print("=== case absentClientCa", flush=True)
              fresh_start()
              FAILED_POST = f"fleet-alerts|FAILED {INGRESS}.service on store"
              RESOLVED_POST = f"fleet-alerts|RESOLVED {INGRESS}.service on store"


              def posts(title):
                  return store.succeed("cat /run/ntfy-posts 2>/dev/null || true").splitlines().count(title)


              def failed_lines():
                  return [
                      l for l in store.succeed("cat /var/lib/observability-notify/failed.log 2>/dev/null || true").splitlines()
                      if f" {INGRESS}.service " in f"{l} "
                  ]


              failed0, posted0, resolved0 = len(failed_lines()), posts(FAILED_POST), posts(RESOLVED_POST)
              collector_with(INGRESS, "absentClientCa", wait=False)
              store.wait_until_succeeds(
                  f"journalctl -u {INGRESS} -o cat | grep -q 'failed to load client CA'", timeout=120
              )
              # sed reads to the end, so journalctl never meets a closed pipe
              # (grep -m1 made it exit 141 under pipefail once the journal grew).
              print(store.succeed(f"journalctl -u {INGRESS} -o cat | grep 'failed to load client CA' | sed -n 1p"), flush=True)
              wait_for(lambda: len(failed_lines()) > failed0, "the collector's failed.log line", 120)
              # Several automatic restarts fail inside one episode.
              time.sleep(30)
              assert len(failed_lines()) == failed0 + 1, failed_lines()
              assert posts(FAILED_POST) == posted0 + 1, store.succeed("cat /run/ntfy-posts")
              collector_with(INGRESS, None)
              wait_for(lambda: posts(RESOLVED_POST) > resolved0, "the RESOLVED post", 120)
              assert posts(RESOLVED_POST) == resolved0 + 1, store.succeed("cat /run/ntfy-posts")
              print(store.succeed("cat /run/ntfy-posts"), flush=True)
              print("ok: absentClientCa", flush=True)
            '';

            # design D8: the ingress host's envelope judges the store's budget
            # hourly; a runtime drop-in forces the hourly clauses on each run.
            # Each fixture is written through otlp/mesh with the agent's
            # certificate, so the ingress stores it as `collector`, and is
            # removed before the next.
            budget = ''
              print("=== case budget", flush=True)
              fresh_start()
              PKI = config()["pki"]
              DROP_INS = "/run/systemd/system/otel-envelope.service.d"
              BUDGET_DROP_IN = f"{DROP_INS}/zz-budget.conf"
              MUTANT_DROP_IN = f"{DROP_INS}/zz-mutant.conf"
              store.succeed(
                  f"install -d {DROP_INS}",
                  f"printf '[Service]\\nEnvironment=OTEL_ENVELOPE_FORCE_HOURLY=1\\n' > {BUDGET_DROP_IN}",
                  "systemctl daemon-reload",
              )
              CLAUSE = re.compile(r"^otel-envelope: ([BC][1-6] [a-z-]+): (ok|FAIL)(?: (.*))?$")


              def budget_run():
                  """One run of the ingress envelope: exit code and clause to
                  (verdict, detail). A run that succeeds leaves the unit
                  inactive with no InvocationID, so its lines are read after a
                  journal cursor taken before the start, until the run's last
                  clause (B6) is there or 20 s have passed."""
                  cursor = store.succeed("journalctl -n 0 --show-cursor -o cat | sed -n 's/^-- cursor: //p'").strip()
                  store.execute("systemctl start otel-envelope.service")
                  code = int(store.succeed("systemctl show -p ExecMainStatus --value otel-envelope.service"))
                  for _ in range(20):
                      lines = [
                          l for l in store.succeed(
                              f"journalctl -u otel-envelope.service --after-cursor={shlex.quote(cursor)} -o cat"
                          ).splitlines()
                          if l.startswith("otel-envelope:")
                      ]
                      if any(l.startswith("otel-envelope: B6 ttl:") for l in lines):
                          break
                      time.sleep(1)
                  clauses = {}
                  for line in lines:
                      print(f"  otel-envelope: {line}", flush=True)
                      match = CLAUSE.match(line)
                      if match:
                          clauses[match.group(1)] = (match.group(2), match.group(3) or "")
                  print(f"  otel-envelope: exit {code}", flush=True)
                  assert all(c in clauses for c in ("C1 telemetry", "C2 targets", "C3 queue", "C4 loss")), clauses
                  return code, clauses


              def clean(final=False):
                  code, clauses = budget_run()
                  assert code == 0 and all(v == "ok" for v, _ in clauses.values()), (code, clauses)
                  if final:
                      budget_clauses = sorted(c for c in clauses if c.startswith("B"))
                      assert [c.split()[0] for c in budget_clauses] == ["B1", "B2", "B3", "B4", "B5", "B6"], clauses


              def fails(what, expected, *details):
                  """A run that fails exactly the `expected` clauses, each line holding every detail."""
                  code, clauses = budget_run()
                  failed = sorted(c for c, (v, _) in clauses.items() if v == "FAIL")
                  assert code == 1 and failed == sorted(expected), (what, code, clauses)
                  for clause in expected:
                      assert all(d in clauses[clause][1] for d in details), (what, clause, details, clauses[clause])
                      print(f"  budget fixture {what}: {clause}: FAIL {clauses[clause][1]}", flush=True)


              def attribute(key, value):
                  return {"key": key, "value": {"stringValue": value}}


              def mesh_write(resources):
                  """One OTLP/HTTP JSON export through otlp/mesh: resources are
                  (resource attributes, metric name, [point attributes]) gauges."""
                  now = str(time.time_ns())
                  body = {"resourceMetrics": [
                      {
                          "resource": {"attributes": [attribute("vanixiets.database", "fleet")]
                                       + [attribute(k, v) for k, v in res.items()]},
                          "scopeMetrics": [{"metrics": [{"name": name, "gauge": {"dataPoints": [
                              {"asInt": "1", "timeUnixNano": now, "attributes": [attribute(k, v) for k, v in point.items()]}
                              for point in points
                          ]}}]}],
                      }
                      for res, name, points in resources
                  ]}
                  store.succeed(f"cat > /tmp/budget-fixture.json <<'EOF'\n{json.dumps(body)}\nEOF")
                  status = store.succeed(
                      f"curl -sS -o /dev/null -w '%{{http_code}}' --cacert {PKI}/ca.crt --cert {PKI}/agent.crt --key {PKI}/agent.key "
                      "-H 'Content-Type: application/json' --data @/tmp/budget-fixture.json https://127.0.0.1:4319/v1/metrics"
                  ).strip()
                  assert status == "200", status


              def admin_sql(sql, db="fleet"):
                  status = store.succeed(
                      f"curl -sS -o /tmp/budget-admin -w '%{{http_code}}' --netrc-file {config()['vars']}/admin.netrc "
                      f"--data-urlencode {shlex.quote('sql=' + sql)} 'http://127.0.0.1:4000/v1/sql?db={db}'"
                  ).strip()
                  assert status == "200", (sql, status, store.succeed("cat /tmp/budget-admin"))


              def stored(sql, want):
                  """sql's single value as `regulator`, once the store has it equal to want."""
                  def holds():
                      status, body = _request("/v1/sql", "fleet", [("sql", sql)])
                      rows = json.loads(body)["output"][0]["records"]["rows"] if status == 200 else None
                      print(f"  {sql}: {status} {rows}", flush=True)
                      return rows is not None and rows[0][0] == want
                  wait_for(holds, f"{sql} = {want}", 180)


              envelope("otel-envelope")
              clean()

              # labelValues: 300 values of one label key on one metric.
              mesh_write([({"host.name": "budgethost"}, "s4_fixture_wide", [{"fixture_key": f"k{i:03d}"} for i in range(300)])])
              stored("SELECT count(DISTINCT fixture_key) FROM s4_fixture_wide", 300)
              fails("labelValues", ["B2 label-values"], "s4_fixture_wide fixture_key 300")
              admin_sql("DELETE FROM s4_fixture_wide WHERE host_name = 'budgethost'")
              stored("SELECT count(*) FROM s4_fixture_wide", 0)
              clean()

              # processNames: 31 process names on one host.
              mesh_write([
                  ({"host.name": "budgethost", "process.executable.name": f"budget-proc-{i:02d}"}, "process_memory_usage_bytes", [{}])
                  for i in range(31)
              ])
              stored("SELECT count(DISTINCT process_executable_name) FROM process_memory_usage_bytes WHERE host_name = 'budgethost'", 31)
              fails("processNames", ["B3 per-host"], "budgethost process_executable_name 31")
              admin_sql("DELETE FROM process_memory_usage_bytes WHERE host_name = 'budgethost'")
              stored("SELECT count(*) FROM process_memory_usage_bytes WHERE host_name = 'budgethost'", 0)
              clean()

              # notifierOutside: a notifier instance for a unit cinnabar does not notify.
              NOT_LISTED = "observability-notify@not-listed.service.service"
              mesh_write([({"host.name": "cinnabar", "systemd.unit.name": NOT_LISTED}, "systemd_unit_state", [{}])])
              stored(f"SELECT count(*) FROM systemd_unit_state WHERE systemd_unit_name = '{NOT_LISTED}'", 1)
              fails("notifierOutside", ["B4 notifier-instances"], "cinnabar not-listed")
              admin_sql(f"DELETE FROM systemd_unit_state WHERE systemd_unit_name = '{NOT_LISTED}'")
              stored(f"SELECT count(*) FROM systemd_unit_state WHERE systemd_unit_name = '{NOT_LISTED}'", 0)
              clean()

              # ttlAltered: a database's ttl changed from SC's.
              admin_sql("ALTER DATABASE agent SET 'ttl' = '7d'")
              fails("ttlAltered", ["B6 ttl"], "agent 7days")
              admin_sql("ALTER DATABASE agent SET 'ttl' = '${databases.agent}'")
              clean()

              # renamedTable: the envelope reading a unit-state table that does not exist.
              store.succeed(
                  f"install -m 0444 /etc/fleet-ingress/mutants/renamedTable.conf {MUTANT_DROP_IN}",
                  "systemctl daemon-reload",
              )
              fails("renamedTable", ["B3 per-host", "B4 notifier-instances"], "systemd_unit_state_absent")
              store.succeed(f"rm {MUTANT_DROP_IN}", "systemctl daemon-reload")

              clean(final=True)
              store.succeed(f"rm {BUDGET_DROP_IN}", "systemctl daemon-reload")
              print("ok: budget", flush=True)
            '';

            # agent-session-telemetry design D12: Claude-shaped OTLP logs and
            # metrics posted to pyrite's otlp/local, through its agent-session
            # pipelines, otlp_http/ingress-agent and otlp/mesh into `agent`,
            # read back as `regulator`. One nonce marks the admitted prompt and
            # every canary: tool output, a raw API body, an unlisted event, a
            # record body, account identifiers, a foreign service, an unlisted
            # metric, session labels on a metric, a forged host and route. What
            # left the host (the unit's file taps) and every string column of
            # every table of every database may hold the nonce only in that
            # prompt. Posted as OTLP/JSON: the receiver decodes it to the same
            # records as protobuf, and the exporters send protobuf onward.
            agentSession = ''
              print("=== case agentSession", flush=True)
              fresh_start()
              store.succeed(f"systemctl restart {SESSION}.service")
              wait_telemetry(SESSION_PORT)
              NONCE = f"n{time.time_ns()}"
              ADMITTED = f"canary admitted prompt {NONCE}"
              now = time.time_ns()


              def s(key, value):
                  return {"key": key, "value": {"stringValue": value}}


              def n(key, value):
                  return {"key": key, "value": {"intValue": str(value)}}


              account = [
                  s("user.email", f"canary-email-{NONCE}@example.com"),
                  s("organization.id", f"canary-org-{NONCE}"),
                  s("user.account_uuid", f"canary-uuid-{NONCE}"),
              ]
              claude = account + [
                  s("service.name", "claude-code"), s("service.version", "2.1.330"), s("os.type", "linux"),
                  s("host.arch", "amd64"), s("user.name", "cameron"), s("host.name", f"canary-host-{NONCE}"),
                  s("vanixiets.database", "devloop"), s("vanixiets.table", "deploy_record"),
              ]
              other = [s("service.name", "canary-other"), s("user.name", "cameron")]


              def record(seq, event, attributes, body=None):
                  rec = {
                      "timeUnixNano": str(now + seq), "observedTimeUnixNano": str(now + seq),
                      "attributes": [s("event.name", event), n("event.sequence", seq), s("session.id", "agent-session-1"),
                                     s("prompt.id", "agent-prompt-1"), s("terminal.type", "tmux")] + account + attributes,
                  }
                  if body is not None:
                      rec["body"] = {"stringValue": body}
                  return rec


              logs = {"resourceLogs": [
                  {"resource": {"attributes": claude}, "scopeLogs": [{"scope": {"name": "com.anthropic.claude_code.events", "attributes": [s("canary.scope", f"canary-scope-{NONCE}")]}, "logRecords": [
                      record(1, "user_prompt", [s("prompt", ADMITTED), s("prompt_text", ADMITTED), n("prompt_length", len(ADMITTED))],
                             body=f"canary-body-{NONCE}"),
                      record(2, "assistant_response", [s("response", "admitted response zebrafish"), s("model", "claude-opus-5-5"),
                                                       s("request_id", "req_agent_1")]),
                      record(3, "api_request", [s("model", "claude-opus-5-5"), n("input_tokens", 100), n("output_tokens", 50),
                                                n("cache_read_tokens", 7), n("cache_creation_tokens", 3), n("cost_usd_micros", 1234),
                                                {"key": "cost_usd", "value": {"doubleValue": 0.001234}}, n("duration_ms", 900),
                                                s("speed", "normal"), s("effort", "medium")]),
                      record(4, "tool_result", [s("tool_name", "Bash"), s("success", "true"), s("duration_ms", "12"),
                                                s("tool_parameters", json.dumps({"bash_command": "ls"})),
                                                s("tool_input", json.dumps({"command": "ls"})),
                                                s("tool_output", f"canary-output-{NONCE}")]),
                      record(5, "api_request_body", [s("body", f"canary-raw-{NONCE}")]),
                      record(6, "hook_execution_complete", [s("hook_name", f"canary-unlisted-{NONCE}")]),
                  ]}]},
                  {"resource": {"attributes": other}, "scopeLogs": [{"logRecords": [
                      record(1, "user_prompt", [s("prompt", f"canary-other-{NONCE}")]),
                  ]}]},
              ]}


              def delta(name, value, attributes):
                  return {"name": name, "unit": "tokens", "sum": {"aggregationTemporality": 1, "isMonotonic": True, "dataPoints": [
                      {"asInt": str(value), "startTimeUnixNano": str(now - 60000000000), "timeUnixNano": str(now), "attributes": attributes}]}}


              metrics = {"resourceMetrics": [
                  {"resource": {"attributes": claude}, "scopeMetrics": [{"scope": {"name": "com.anthropic.claude_code", "attributes": [s("canary.scope", f"canary-scope-{NONCE}")]}, "metrics": [
                      delta("claude_code.token.usage", 42, [s("type", "input"), s("model", "claude-opus-5-5"),
                                                            s("session.id", f"canary-session-{NONCE}"),
                                                            s("prompt.id", f"canary-promptid-{NONCE}")] + account),
                      delta("canary.metric", 1, [s("marker", f"canary-metric-{NONCE}")]),
                  ]}]},
                  {"resource": {"attributes": other}, "scopeMetrics": [{"metrics": [
                      delta("claude_code.token.usage", 1, [s("type", "input"), s("model", f"canary-othermetric-{NONCE}")]),
                  ]}]},
              ]}


              def post(path, body):
                  store.succeed(f"cat > /tmp/agent-session.json <<'EOF'\n{json.dumps(body)}\nEOF")
                  status = store.succeed(
                      "curl -sS -o /tmp/agent-session-answer -w '%{http_code}' -H 'Content-Type: application/json' "
                      f"--data @/tmp/agent-session.json http://127.0.0.1:4318{path}"
                  ).strip()
                  print(f"  POST otlp/local {path}: {status} {store.succeed('cat /tmp/agent-session-answer')[:300]}", flush=True)
                  return status


              assert post("/v1/logs", logs) == "200"
              assert post("/v1/metrics", metrics) == "200"


              def stored_events():
                  status, body = _request("/v1/sql", "agent", [("sql", "SELECT count(*) FROM session_event WHERE host_name = 'pyrite'")])
                  rows = json.loads(body)["output"][0]["records"]["rows"] if status == 200 else None
                  print(f"  session_event rows from pyrite: {status} {rows}", flush=True)
                  return rows == [[4]]


              wait_for(stored_events, "pyrite's four admitted events in agent.session_event", 240)
              rows = gsql(
                  "SELECT event_name, host_name, user_name, service_name, prompt, response, input_tokens, output_tokens, "
                  "cost_usd_micros, duration_ms, success, tool_name, tool_parameters, speed FROM session_event "
                  "WHERE host_name = 'pyrite' ORDER BY event_sequence", "agent")
              for row in rows:
                  print(f"  admitted: {row}", flush=True)
              assert [r[0] for r in rows] == ["user_prompt", "assistant_response", "api_request", "tool_result"], rows
              assert all(r[1:4] == ["pyrite", "cameron", "claude-code"] for r in rows), rows
              assert rows[0][4] == ADMITTED and rows[1][5] == "admitted response zebrafish", rows
              assert rows[2][6:9] == [100, 50, 1234] and rows[2][13] == "normal", rows
              assert rows[3][9] == 12 and rows[3][10] is True and rows[3][11] == "Bash", rows
              found = gsql(f"SELECT event_name, host_name FROM session_event WHERE matches_term(prompt, '{NONCE}')", "agent")
              print(f"  matches_term(prompt, nonce): {found}", flush=True)
              assert found == [["user_prompt", "pyrite"]], found

              create = gsql("SHOW CREATE TABLE session_event", "agent")[0][1]
              print("  " + create.replace("\n", "\n  "), flush=True)
              for column in ("prompt", "response"):
                  assert f"\"{column}\" STRING NULL FULLTEXT INDEX WITH(analyzer = 'English', backend = 'bloom', case_sensitive = 'false'" in create, column
              assert "append_mode = 'false'" in create, create
              options = gsql("SELECT create_options FROM information_schema.tables WHERE table_schema = 'agent' AND table_name = 'session_event'", "agent")[0][0]
              schemata = gsql("SELECT schema_name, options FROM information_schema.schemata WHERE schema_name = 'agent'", "agent")
              print(f"  session_event create_options: {options}; agent schemata: {schemata}", flush=True)
              assert "ttl" not in options, options
              assert re.search(r"'ttl'='(30d|30days)'", schemata[0][1]), schemata


              # The metric: no session, prompt or account labels; host and person.
              def token_tables():
                  tables = [r[0] for r in gsql("SELECT table_name FROM information_schema.tables WHERE table_schema = 'agent' AND table_name LIKE 'claude_code_token_usage%'", "agent")]
                  print(f"  agent token tables: {tables}", flush=True)
                  return tables


              wait_for(lambda: len(token_tables()) == 1, "the claude_code.token.usage table in agent", 240)
              [token] = token_tables()
              columns = [r[0] for r in gsql(f"SELECT column_name FROM information_schema.columns WHERE table_schema = 'agent' AND table_name = '{token}'", "agent")]
              points = gsql(f"SELECT \"host_name\", \"user_name\", \"model\", \"type\" FROM \"{token}\"", "agent")
              print(f"  {token} columns {columns}; points {points}", flush=True)
              assert {"host_name", "user_name"} <= set(columns), columns
              assert not set(columns) & {"session_id", "prompt_id", "user_email", "organization_id", "user_account_uuid", "terminal_type"}, columns
              assert points == [["pyrite", "cameron", "claude-opus-5-5", "input"]], points

              # What left the host.
              taps = {kind: store.succeed(f"cat /var/lib/agent-session-collector/tap-{kind}.jsonl") for kind in ("logs", "metrics")}
              for kind, text in taps.items():
                  print(f"  tap-{kind}: {len(text)} bytes, nonce {text.count(NONCE)} time(s)", flush=True)
                  for key in ("user.email", "organization.id", "user.account_uuid", "tool_output", "prompt_text", "\"cost_usd\"",
                              "hook_name", "terminal.type", "marker", "canary.scope", "canary-", "deploy_record"):
                      assert key not in text, (kind, key)
              assert taps["logs"].count(NONCE) == taps["logs"].count(ADMITTED) == 1, taps["logs"]
              assert NONCE not in taps["metrics"], taps["metrics"]

              assert nonce_hits(NONCE) == {"agent.session_event.prompt": 1}
              forbidden = gsql(
                  "SELECT table_schema, table_name, column_name FROM information_schema.columns WHERE column_name IN "
                  "('user_email', 'organization_id', 'user_account_uuid', 'user_account_id', 'tool_output', 'prompt_text', "
                  "'cost_usd', 'body', 'terminal_type', 'hook_name', 'marker') OR table_name LIKE 'canary%'", "agent")
              print(f"  forbidden columns: {forbidden}", flush=True)
              assert forbidden == [], forbidden

              # The collector's own drop counters, and no failed send.
              for name in ("otelcol_processor_filter_logs_filtered", "otelcol_processor_filter_datapoints_filtered"):
                  print(f"  {SESSION} {name}: {metric(SESSION_PORT, name)}", flush=True)
              failed = {port: metric(port, r"otelcol_exporter_send_failed_[a-z_]+") for port in (INGRESS_PORT, SESSION_PORT)}
              print(f"  send_failed {failed}", flush=True)
              assert failed == {INGRESS_PORT: 0, SESSION_PORT: 0}, failed
              print("ok: agentSession", flush=True)
            '';

            # omp's spans (design D13): one chat span carrying the history
            # (an older prompt, a tool result, the newest prompt), one after a
            # tool, one tool span, and one from another service, through
            # pyrite's otlp/local, otlp/mesh and the ingress into
            # agent.agent_span, which the schema job created.
            agentSpans = ''
              print("=== case agentSpans", flush=True)
              fresh_start()
              store.succeed(f"systemctl restart {SESSION}.service")
              wait_telemetry(SESSION_PORT)
              NONCE = f"n{time.time_ns()}"
              TRACE = "5b8efff798038103d269b633813fc60c"
              canary = {
                  "prompt": f"canary prompt {NONCE}",
                  "response": f"canary response {NONCE}",
                  "arguments": f"canary arguments {NONCE}",
                  "older prompt": f"canary-oldprompt-{NONCE}",
                  "tool result": f"canary-result-{NONCE}",
                  "history result": f"canary-histresult-{NONCE}",
                  "system": f"canary-system-{NONCE}",
                  "unlisted": f"canary-unlisted-{NONCE}",
                  "event": f"canary-event-{NONCE}",
                  "status": f"canary-status-{NONCE}",
                  "scope": f"canary-scope-{NONCE}",
                  "email": f"canary-email-{NONCE}",
                  "other service": f"canary-other-{NONCE}",
              }
              admitted = ("prompt", "response", "arguments")


              def s(key, value):
                  return {"key": key, "value": {"stringValue": value}}


              now = time.time_ns()
              history = [
                  {"role": "user", "parts": [{"type": "text", "content": canary["older prompt"]}]},
                  {"role": "assistant", "parts": [{"type": "tool_call", "id": "t1", "name": "bash", "arguments": {"command": "ls"}}]},
                  {"role": "tool", "parts": [{"type": "tool_call_response", "id": "t1", "response": canary["history result"]}]},
              ]
              chat = {
                  "traceId": TRACE, "spanId": "eee19b7ec3c1b174", "parentSpanId": "eee19b7ec3c1b173",
                  "name": "chat claude-opus", "kind": 3,
                  "startTimeUnixNano": str(now - 2000000000), "endTimeUnixNano": str(now - 1000000000),
                  "attributes": [
                      s("gen_ai.operation.name", "chat"), s("gen_ai.request.model", "claude-opus"),
                      s("gen_ai.conversation.id", f"session-{NONCE}"),
                      {"key": "gen_ai.usage.input_tokens", "value": {"intValue": "42"}},
                      s("gen_ai.system_instructions", json.dumps([{"type": "text", "content": canary["system"]}])),
                      s("gen_ai.input.messages", json.dumps(history + [{"role": "user", "parts": [{"type": "text", "content": canary["prompt"]}]}])),
                      s("gen_ai.output.messages", json.dumps([{"role": "assistant", "parts": [{"type": "text", "content": canary["response"]}]}])),
                      s("canary.unlisted", canary["unlisted"]),
                  ],
                  "events": [{"name": "exception", "timeUnixNano": str(now - 1500000000),
                              "attributes": [s("exception.message", canary["event"])]}],
                  "status": {"code": 2, "message": canary["status"]},
              }
              after_tool = dict(chat, spanId="eee19b7ec3c1b177", events=[], status={},
                                attributes=[s("gen_ai.operation.name", "chat"), s("gen_ai.input.messages", json.dumps(history))])
              tool = {
                  "traceId": TRACE, "spanId": "eee19b7ec3c1b175", "parentSpanId": "eee19b7ec3c1b173",
                  "name": "execute_tool bash", "kind": 1,
                  "startTimeUnixNano": str(now - 900000000), "endTimeUnixNano": str(now - 800000000),
                  "attributes": [
                      s("gen_ai.operation.name", "execute_tool"), s("gen_ai.tool.name", "bash"),
                      s("gen_ai.conversation.id", f"session-{NONCE}"),
                      s("gen_ai.tool.call.arguments", json.dumps({"command": canary["arguments"]})),
                      s("gen_ai.tool.call.result", canary["tool result"]),
                  ],
              }
              body = {"resourceSpans": [
                  {"resource": {"attributes": [s("service.name", "oh-my-pi"), s("service.version", "19.1.0"), s("user.name", "cameron"),
                                               s("user.email", canary["email"]), s("host.name", f"canary-host-{NONCE}"),
                                               s("vanixiets.database", "fleet")]},
                   "scopeSpans": [{"scope": {"name": "omp", "attributes": [s("canary.scope", canary["scope"])]},
                                   "spans": [chat, after_tool, tool]}]},
                  {"resource": {"attributes": [s("service.name", "canary-other"), s("user.name", "cameron")]},
                   "scopeSpans": [{"spans": [dict(tool, spanId="eee19b7ec3c1b176",
                                                  attributes=[s("gen_ai.input.messages", canary["other service"])])]}]},
              ]}
              store.succeed(f"cat > /tmp/agent-spans.json <<'EOF'\n{json.dumps(body)}\nEOF")
              status = store.succeed(
                  "curl -sS -o /tmp/agent-spans-answer -w '%{http_code}' -H 'Content-Type: application/json' "
                  "--data @/tmp/agent-spans.json http://127.0.0.1:4318/v1/traces"
              ).strip()
              print(f"  POST otlp/local /v1/traces: {status} {store.succeed('cat /tmp/agent-spans-answer')}", flush=True)
              assert status == "200", status


              def stored_spans():
                  status, body = _request("/v1/sql", "agent", [("sql", "SELECT count(*) FROM agent_span WHERE \"resource_attributes.host.name\" = 'pyrite'")])
                  rows = json.loads(body)["output"][0]["records"]["rows"] if status == 200 else None
                  print(f"  agent_span rows from pyrite: {status} {rows}", flush=True)
                  return rows == [[3]]


              wait_for(stored_spans, "pyrite's three spans in agent.agent_span", 240)
              rows = gsql(
                  'SELECT span_name, "span_attributes.prompt", "span_attributes.gen_ai.output.messages", '
                  '"span_attributes.gen_ai.tool.call.arguments", "span_attributes.gen_ai.usage.input_tokens", '
                  '"resource_attributes.user.name", "resource_attributes.host.name", service_name, span_status_message '
                  "FROM agent_span ORDER BY span_id", "agent")
              for row in rows:
                  print(f"  span: {row}", flush=True)
              assert [r[0] for r in rows] == ["chat claude-opus", "execute_tool bash", "chat claude-opus"], rows
              assert all(r[5:9] == ["cameron", "pyrite", "oh-my-pi", ""] for r in rows), rows
              assert rows[0][1] == canary["prompt"] and canary["response"] in rows[0][2] and rows[0][4] == 42, rows
              assert rows[2][1] is None and canary["arguments"] in rows[1][3], rows
              found = gsql(f"SELECT span_name FROM agent_span WHERE matches_term(\"span_attributes.prompt\", '{NONCE}')", "agent")
              print(f"  matches_term(prompt, nonce): {found}", flush=True)
              assert found == [["chat claude-opus"]], found
              create = gsql("SHOW CREATE TABLE agent_span", "agent")[0][1]
              for column in ("span_attributes.prompt", "span_attributes.gen_ai.output.messages"):
                  assert f"\"{column}\" STRING NULL FULLTEXT INDEX WITH(analyzer = 'English', backend = 'bloom', case_sensitive = 'false'" in create, column
              options = gsql("SELECT create_options FROM information_schema.tables WHERE table_schema = 'agent' AND table_name = 'agent_span'", "agent")[0][0]
              print(f"  agent_span create_options: {options}", flush=True)
              assert "table_data_model=greptime_trace_v1" in options and "ttl" not in options, options
              # The Jaeger lookup tables the store fills beside the spans.
              print(f"  agent_span_operations: {gsql('SELECT service_name, span_name, span_kind FROM agent_span_operations ORDER BY span_name', 'agent')}", flush=True)

              # What left the host.
              # The file exporter flushes once a second.
              store.wait_until_succeeds(f"grep -q {NONCE} /var/lib/agent-session-collector/tap-traces.jsonl", timeout=60)
              tap = store.succeed("cat /var/lib/agent-session-collector/tap-traces.jsonl")
              print(f"  tap-traces: {len(tap)} bytes, nonce {tap.count(NONCE)} time(s)", flush=True)
              for what, value in canary.items():
                  assert (value in tap) == (what in admitted), (what, value in tap)
              for key in ("gen_ai.input.messages", "gen_ai.system_instructions", "gen_ai.tool.call.result", "canary.unlisted",
                          "canary.scope", "user.email", "exception", "vanixiets.database\",\"value\":{\"stringValue\":\"fleet"):
                  assert key not in tap, key

              # Every string and JSON column of every database, as regulator.
              assert nonce_hits(NONCE) == {
                  "agent.agent_span.span_attributes.prompt": 1,
                  "agent.agent_span.span_attributes.gen_ai.conversation.id": 2,
                  "agent.agent_span.span_attributes.gen_ai.output.messages": 1,
                  "agent.agent_span.span_attributes.gen_ai.tool.call.arguments": 1,
              }
              failed = {port: metric(port, r"otelcol_exporter_send_failed_[a-z_]+") for port in (INGRESS_PORT, SESSION_PORT)}
              print(f"  send_failed {failed}", flush=True)
              assert failed == {INGRESS_PORT: 0, SESSION_PORT: 0}, failed
              print("ok: agentSpans", flush=True)
            '';

            cases = [
              processName
              refusal
              delivery
              agentSession
              agentSpans
              backPressure
              lossControls
              crashLoop
              longRun
              absentClientCa
              budget
            ];
          in
          pkgs.testers.runNixOSTest {
            name = "fleet-ingress";
            requiredFeatures = {
              nixos-test = true;
              uid-range = true;
            };
            node.pkgs = lib.mkForce nodePkgs;
            containers.store =
              {
                config,
                extendModules,
                pkgs,
                ...
              }:
              let
                collector = config.services.opentelemetry-collector.package;
                envelope = config.systemd.services.otel-envelope.serviceConfig;
                dropIn = execStart: ''
                  [Service]
                  ExecStart=
                  ${lib.concatMapStringsSep "\n" (command: "ExecStart=${command}") (lib.toList execStart)}
                '';
                # The envelope with its unit-state table name replaced by one
                # that does not exist; the budget case requires the run to
                # fail naming it, so a replacement that matched nothing fails
                # the case.
                unitMutants.renamedTable =
                  pkgs.runCommand "otel-envelope-renamedTable" { meta.mainProgram = "otel-envelope"; }
                    ''
                      mkdir -p "$out/bin"
                      sed 's/\bsystemd_unit_state\b/systemd_unit_state_absent/g' ${envelope.ExecStart} > "$out/bin/otel-envelope"
                      chmod +x "$out/bin/otel-envelope"
                    '';
              in
              {
                imports = [
                  self.modules.nixos.greptimedb
                  self.modules.nixos.otel-collector-agent
                  self.modules.nixos.otel-collector-ingress
                ];
                system.stateVersion = lib.trivial.release;
                environment.systemPackages = [ pkgs.curl ];

                services.greptimedb = {
                  enable = true;
                  inherit databases;
                  # The devloop tables and pipelines, so `logs/ingress`
                  # exists and the deploy records have a table.
                  tables.devloop = lib.attrValues devloop.ddl;
                  pipelines.devloop = lib.mapAttrs' (
                    name: pipeline: lib.nameValuePair "devloop_${name}" pipeline
                  ) devloop.pipelines;
                  # agent.session_event and its pipeline as magnetite declares
                  # them, which also routes agent events at the ingress.
                  tables.agent = reference.services.greptimedb.tables.agent;
                  pipelines.agent = reference.services.greptimedb.pipelines.agent;
                };

                # Credentials from magnetite's own generator script, run at
                # boot, so no credential value exists in the repository; the
                # netrc files keep passwords out of the driver's log.
                systemd.services.fleet-ingress-vars = {
                  description = "Test credentials from magnetite's greptimedb-users generator";
                  requiredBy = credentialConsumers;
                  before = credentialConsumers;
                  path = [
                    pkgs.bash
                    pkgs.coreutils
                  ];
                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                  };
                  script = ''
                    install -d -m 0700 ${vars}
                    out=${vars} bash ${usersGenerator.finalScript}
                    for user in admin regulator; do
                      printf 'machine 127.0.0.1 login %s password %s\n' \
                        "$user" "$(cat "${vars}/$user-password")" > "${vars}/$user.netrc"
                    done
                    # The notifier's token; the recording ntfy-send ignores it.
                    printf tk_fleetingress000000000000000000 > ${vars}/alerter-token
                  '';
                };
                systemd.services.greptimedb.serviceConfig.LoadCredential = [ "users:${vars}/users" ];
                systemd.services.greptimedb-schema.serviceConfig.LoadCredential = [
                  "admin-password:${vars}/admin-password"
                ];
                systemd.services.opentelemetry-collector.serviceConfig.LoadCredential = [
                  "collector-password:${vars}/collector-password"
                  "otel-cert:${pki}/ingress.crt"
                  "otel-key:${pki}/ingress.key"
                ];
                systemd.services.otel-envelope.serviceConfig.LoadCredential = [
                  "regulator-password:${vars}/regulator-password"
                ];

                # The budget over this container's store; its two collectors
                # report this container's units as `store` and `electrum`.
                vanixiets.otelCollector.envelopeBudget = {
                  storeUrl = "http://127.0.0.1:4000";
                  notifiedUnits = lib.mapAttrs (_: h: h.notifiedUnits) self.lib.observabilityHosts // {
                    store = config.services.observability-notify.units;
                    electrum = config.services.observability-notify.units;
                  };
                  inherit databases;
                };

                # The ingress receivers on loopback, trusting the test CA.
                vanixiets.otelCollector.caFile = "${pki}/ca.crt";
                services.opentelemetry-collector.settings.receivers."otlp/mesh".protocols.http.endpoint =
                  lib.mkForce "127.0.0.1:4319";
                services.opentelemetry-collector.settings.receivers."otlp/mesh-tincr".protocols.http.endpoint =
                  lib.mkForce "127.0.0.1:4320";
                # The container has no ZFS dataset, so the agent fragment
                # configures no filesystem scraper here (an empty strict list
                # would match every mount: 713 in the nspawn container, which
                # the budget's B2 failed); electrum's rendered scraper on "/"
                # stands in for a host's datasets, so the cases still run it.
                services.opentelemetry-collector.settings.receivers."host_metrics/memory".scrapers.filesystem =
                  lib.recursiveUpdate electrum.receivers."host_metrics/memory".scrapers.filesystem
                    {
                      include_mount_points.mount_points = [ "/" ];
                    };

                services.observability-notify = {
                  units = [
                    "opentelemetry-collector"
                    "otel-envelope"
                    "agent-collector"
                    "agent-envelope"
                  ];
                  tokenFile = "${vars}/alerter-token";
                };

                # The cases start the envelopes; a timer run between two of a
                # case's runs would change the state they compare.
                systemd.timers.otel-envelope.wantedBy = lib.mkForce [ ];

                systemd.services.agent-collector = {
                  description = "electrum's collector configuration, exporting over mTLS to otlp/mesh";
                  wantedBy = [ "multi-user.target" ];
                  after = [ "opentelemetry-collector.service" ];
                  startLimitIntervalSec = 0;
                  serviceConfig = {
                    DynamicUser = true;
                    StateDirectory = "agent-collector";
                    ExecStart = agentExecStart collector agentSettings;
                    Restart = "always";
                    RestartSec = "5s";
                  };
                };

                systemd.services.agent-session-collector = {
                  description = "pyrite's agent-session pipelines, exporting over mTLS to otlp/mesh";
                  wantedBy = [ "multi-user.target" ];
                  after = [ "opentelemetry-collector.service" ];
                  startLimitIntervalSec = 0;
                  serviceConfig = {
                    DynamicUser = true;
                    StateDirectory = "agent-session-collector";
                    ExecStart = agentExecStart collector agentSessionSettings;
                    Restart = "always";
                    RestartSec = "5s";
                  };
                };

                systemd.services.agent-envelope = {
                  description = "Collector delivery envelope for agent-collector";
                  after = [ "agent-collector.service" ];
                  serviceConfig = {
                    inherit (envelope)
                      Type
                      DynamicUser
                      MemoryMax
                      TimeoutStartSec
                      ;
                    StateDirectory = "agent-envelope";
                    ExecStart = lib.getExe (
                      self.lib.otelEnvelope pkgs {
                        hostName = "electrum";
                        telemetryUrl = "http://127.0.0.1:8889/metrics";
                        targets = self.lib.otelEnvelopeTargets agentSettings.receivers;
                        exporters = builtins.attrNames agentSettings.exporters;
                      }
                    );
                  };
                };

                environment.etc = {
                  "fleet-ingress/config.json".text = builtins.toJSON {
                    inherit vars pki agentDeployRecord;
                    deployRecord = self.lib.deployRecordScript {
                      inherit pkgs;
                      hostName = "electrum";
                      file = agentDeployRecord;
                    };
                  };
                }
                // lib.mapAttrs' (
                  name: module:
                  lib.nameValuePair "fleet-ingress/mutants/${name}.conf" {
                    text =
                      dropIn
                        (extendModules { modules = [ module ]; })
                        .config.systemd.services.opentelemetry-collector.serviceConfig.ExecStart;
                  }
                ) ingressMutants
                // lib.mapAttrs' (
                  name: settings:
                  lib.nameValuePair "fleet-ingress/mutants/${name}.conf" {
                    text = dropIn (agentExecStart collector settings);
                  }
                ) agentMutants
                // lib.mapAttrs' (
                  name: drv:
                  lib.nameValuePair "fleet-ingress/mutants/${name}.conf" {
                    text = dropIn (lib.getExe drv);
                  }
                ) unitMutants;
              };
            testScript = builtins.readFile ./fleet-ingress/helpers.py + lib.concatStringsSep "\n" cases;
          };
      };
    };
}
