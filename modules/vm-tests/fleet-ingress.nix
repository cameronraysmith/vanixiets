# Runtime tests of the fleet's certificate-authenticated ingest
# (openspec/changes/stand-up-linux-fleet-collection, design D7, D11, D12;
# tasks.md 3.4), built as two tests from the one container below
# (declare-test-size-classes design D7):
#   - fleet-ingress, the medium test of what the ingress filters, routes,
#     stamps, refuses and keeps out of storage: processName, refusal,
#     delivery, agentSession, agentSpans, schemaOrder, handoffCap, budget;
#   - fleet-ingress-outage, the enormous test of behaviour that needs real
#     time to occur: langfuse, backPressure, lossControls, crashLoop,
#     longRun, absentClientCa. Run weekly or on demand after a run notice.
#
# One systemd-nspawn container `store`, on a builder that advertises
# uid-range (pyrite or magnetite), holds:
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
#   - otel-agent-session.service, pyrite's agent-session collector: its
#     evaluated configuration and unit (ceiling, GOMEMLIMIT, hardening),
#     with otlp/local the one listener here on the harnesses'
#     127.0.0.1:4318, its exporters pointed at otlp/mesh under the test CA
#     and its telemetry on 127.0.0.1:8890 (agent-session-telemetry design
#     D12, D14);
#   - langfuse-sink.service, fleet-ingress/langfuse_sink.py, standing in for
#     Langfuse Cloud on 127.0.0.1:4330: pyrite's Langfuse exporter points
#     there with a test key pair and a 20 s retry limit, so the agentSpans
#     and langfuse cases see what Langfuse would receive and the branch's
#     failures (agent-session-telemetry design D16);
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
      # Size classes (declare-test-size-classes stages 1 and 3): fleet-ingress
      # is medium. Its script measured 252.56, 280.74 and 216.61 s on pyrite on
      # 2026-11-24 (logs/tsc-1-fleet-ingress-pyrite-*.log), so its margin under
      # the 300 s timeout has been as small as 19 s. A timeout failure here is
      # the regulator saying the test has outgrown medium; the response is the
      # trimming options of design D7 first, then the operator's answer to the
      # design's Open Question 1.
      # fleet-ingress-outage measured 1,660.34 s of script, 1,676 s whole
      # (logs/tsc-1-fleet-ingress-outage-20261124-114719.log).
      testSizes.vmTests = lib.optionalAttrs (system == "x86_64-linux") {
        fleet-ingress.class = "medium";
        fleet-ingress-outage = {
          class = "enormous";
          reason = "its outage, queue, crash-loop, long-run and Langfuse-timer cases wait out real time, which is what they prove";
        };
      };
      vmTests =
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
            "otel-agent-session.service"
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

          # pyrite's agent-session collector as the agent role renders it on
          # a host whose agentTelemetry is true (agent-session-telemetry
          # design D12, D14): its evaluated configuration whole, with only
          # its exporters pointed at this container's otlp/mesh under the
          # test CA, and a tap beside each pipeline's exporter; its queue
          # and telemetry stay where the module puts them.
          pyriteConfig = self.nixosConfigurations.pyrite.config;
          pyriteSession = pyriteConfig.vanixiets.otelCollector.agentSessionSettings;
          pyriteSessionUnit = pyriteConfig.systemd.services.otel-agent-session.serviceConfig;
          # agent.agent_span as main created it before design D15 (72f782b8,
          # the table magnetite holds): the span keys D15 and the oneshot
          # kind (darwin-agent-session-telemetry design D8) add removed and
          # the two content indexes of then, its CREATE pinned by hash.
          oldSpanTable =
            let
              table = self.lib.agentSessionStore.spanTableFor {
                keys = builtins.removeAttrs self.lib.otelCollectorSchema.agentSession.spans.keys [
                  "gen_ai.tool.call.result"
                  "omp.gen_ai.tool.status"
                  "omp.gen_ai.oneshot.kind"
                  "session.id"
                  "user_prompt"
                  "tool_name"
                  "tool_use_id"
                  "full_command"
                  "file_path"
                  "duration_ms"
                  "success"
                  "error"
                  "input_tokens"
                  "output_tokens"
                  "cache_read_tokens"
                  "cache_creation_tokens"
                ];
                fulltext = [
                  "last_user_message"
                  "gen_ai.output.messages"
                ];
                inherit resourceKeys;
              };
            in
            assert lib.assertMsg (
              builtins.hashString "sha256" table
              == "babb610506252a20f240d2d3d8c8b424b22481eab5bfdc9e96242fe3e9497b1e"
            ) "fleet-ingress: the pre-D15 agent_span is not main's (72f782b8) CREATE";
            table;
          # agent.agent_span as the D15 deploy left it on magnetite
          # (2c7ee83f): every span key but the oneshot kind, the four
          # content indexes of then; the schema job adds the oneshot
          # column and the indexes on full_command and
          # gen_ai.tool.call.arguments.
          d15SpanTable =
            let
              table = self.lib.agentSessionStore.spanTableFor {
                keys = builtins.removeAttrs self.lib.otelCollectorSchema.agentSession.spans.keys [
                  "omp.gen_ai.oneshot.kind"
                ];
                fulltext = [
                  "last_user_message"
                  "gen_ai.output.messages"
                  "gen_ai.tool.call.result"
                  "user_prompt"
                ];
                inherit resourceKeys;
              };
            in
            assert lib.assertMsg (
              builtins.hashString "sha256" table
              == "7d647ff8027f36b2f0766332712b68e821f84e89bd5f5f12f73702a63de1333d"
            ) "fleet-ingress: the D15 agent_span is not 2c7ee83f's CREATE";
            table;
          # The span resource keys of both generations above: neither had
          # the harness host's (darwin-agent-session-telemetry design D15).
          resourceKeys = [
            "service.name"
            "service.version"
            "user.name"
          ];
          # agent.session_event as 55c644f6 created it on magnetite, before
          # the harness host's column (darwin-agent-session-telemetry design
          # D15), its CREATE pinned by hash.
          oldEventTable =
            let
              table = self.lib.otelCollectorSchema.agentSession.tables.session_event;
              inherit
                (self.lib.greptimedbLogTable {
                  name = "session_event";
                  table = table // {
                    columns = builtins.filter (column: column.name != "harness_host") table.columns;
                  };
                })
                ddl
                ;
            in
            assert lib.assertMsg (
              builtins.hashString "sha256" ddl
              == "7ba25aefca51d569324455e05cdb05f4e286f1d3f2f58d031d00dad8e74c8d3f"
            ) "fleet-ingress: the pre-marker session_event is not 55c644f6's CREATE";
            ddl;
          agentSessionState = "/var/lib/otel-agent-session";
          # Langfuse Cloud's stand-in (agent-session-telemetry design D16):
          # fleet-ingress/langfuse_sink.py on loopback, answering as the
          # case sets its mode, and recording what it received.
          sinkPort = 4330;
          sinkDir = "/run/langfuse-sink";
          # The test shortens Langfuse's retry limit so that the drop at the
          # limit is observed within the case; everything else of the
          # exporter is pyrite's.
          langfuseTestRetry = "20s";
          agentSessionSettings =
            let
              pipelines = pyriteSession.service.pipelines;
              storePipelines = builtins.removeAttrs pipelines [ "traces/langfuse" ];
              storeExporters = builtins.removeAttrs pyriteSession.exporters [ "otlp_http/langfuse" ];
              langfuse = pyriteSession.exporters."otlp_http/langfuse";
            in
            assert lib.assertMsg
              (
                lib.attrNames pipelines == [
                  "logs/agent-session"
                  "metrics/agent-session"
                  "traces/agent-session"
                  "traces/langfuse"
                ]
                && lib.all (pipeline: pipeline.receivers == [ "otlp/local" ]) (lib.attrValues storePipelines)
                && pipelines."traces/langfuse".receivers == [ "forward/langfuse" ]
                && pyriteSession.receivers == { "otlp/local".protocols.http.endpoint = "127.0.0.1:4318"; }
                && pyriteSession.extensions.file_storage.directory == "${agentSessionState}/queue"
              )
              "fleet-ingress: pyrite's agent-session collector is not otlp/local alone on 127.0.0.1:4318 feeding its three pipelines and forward/langfuse traces/langfuse, with its queue under ${agentSessionState}";
            pyriteSession
            // {
              exporters =
                lib.mapAttrs (
                  _: exporter:
                  exporter
                  // {
                    endpoint = "https://127.0.0.1:4319";
                    tls = exporter.tls // {
                      ca_file = "${pki}/ca.crt";
                    };
                  }
                ) storeExporters
                // {
                  "otlp_http/langfuse" = langfuse // {
                    endpoint = "http://127.0.0.1:${toString sinkPort}/api/public/otel";
                    retry_on_failure = langfuse.retry_on_failure // {
                      max_elapsed_time = langfuseTestRetry;
                      # The collector refuses a limit below the interval.
                      max_interval = "5s";
                    };
                  };
                }
                # What leaves the host for the store, beside each store
                # pipeline's own exporter, one JSON export per line, so the
                # canary reads it before the store's pipeline closes the
                # columns again.
                // lib.mapAttrs' (
                  name: _:
                  lib.nameValuePair "file/tap-${lib.removeSuffix "/agent-session" name}" {
                    path = "${agentSessionState}/tap-${lib.removeSuffix "/agent-session" name}.jsonl";
                  }
                ) storePipelines;
              service = pyriteSession.service // {
                pipelines =
                  lib.mapAttrs (
                    name: pipeline:
                    pipeline
                    // {
                      exporters = pipeline.exporters ++ [ "file/tap-${lib.removeSuffix "/agent-session" name}" ];
                    }
                  ) storePipelines
                  // {
                    inherit (pipelines) "traces/langfuse";
                  };
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
          # every canary: an unlisted key, a raw API body, an unlisted event,
          # a record body, account identifiers, a foreign service, an
          # unlisted metric, session labels on a metric, a forged host and
          # route. What left the host (the unit's file taps) and every string
          # column of every table of every database may hold the nonce only
          # in that prompt. A bearer token in the tool parameters is stored
          # masked (design D15). Posted as OTLP/JSON: the receiver decodes it
          # to the same records as protobuf, and the exporters send protobuf
          # onward.
          agentSession = ''
            print("=== case agentSession", flush=True)
            fresh_start()
            # session_event as 55c644f6 created it on magnetite, before the
            # harness host's column (darwin-agent-session-telemetry design
            # D15), with a row: the schema job adds the column, which the
            # pipeline's write of it needs (1.2.1 refuses unknown columns
            # under auto_create_table=false), and the table ends as a
            # fresh one is, its row kept.
            def event_lines():
                create = gsql("SHOW CREATE TABLE session_event", "agent")[0][1]
                return sorted(line.strip().rstrip(",") for line in create.splitlines())


            def admin(sql):
                status = store.succeed(
                    f"curl -sS -o /tmp/agent-admin -w '%{{http_code}}' --netrc-file {config()['vars']}/admin.netrc "
                    f"--data-urlencode {shlex.quote('sql=' + sql)} 'http://127.0.0.1:4000/v1/sql?db=agent'"
                ).strip()
                assert status == "200", (sql, status, store.succeed("cat /tmp/agent-admin"))


            fresh_events = event_lines()
            admin("DROP TABLE session_event")
            admin(config()["oldEventTable"])
            admin("INSERT INTO session_event (ts, host_name, session_id, event_sequence, event_name) "
                  "VALUES (now(), 'old', 'old-session', 1, 'pre-marker row')")
            missing = sorted(set(fresh_events) - set(event_lines()))
            print(f"  pre-marker session_event lacks {len(missing)} lines: {missing}", flush=True)
            assert missing == ['"harness_host" STRING NULL'], missing
            store.succeed("systemctl restart greptimedb-schema.service")
            assert event_lines() == fresh_events, ("the upgraded session_event differs from a fresh one",
                                                   sorted(set(event_lines()) ^ set(fresh_events)))
            store.succeed("systemctl restart greptimedb-schema.service")
            assert event_lines() == fresh_events, "a second schema run on the upgraded session_event changed it"
            assert gsql("SELECT count(*) FROM session_event WHERE event_name = 'pre-marker row'", "agent") == [[1]]
            store.succeed(f"systemctl restart {INGRESS}.service")
            wait_telemetry(INGRESS_PORT)
            store.succeed(f"systemctl restart {SESSION}.service")
            wait_telemetry(SESSION_PORT)
            NONCE = f"n{time.time_ns()}"
            ADMITTED = f"canary admitted prompt {NONCE}"
            now = time.time_ns()
            # Assembled here from pieces, so no credential-shaped string
            # exists in the repository (checks.gitleaks).
            BEARER = "Authorization: " + "Bear" + "er " + "c4n4ryB34r3r" + "T0k3nAbCdEf9"
            # An encoded blob in a kept event attribute, masked whole
            # (design D15).
            EVENT_BLOB = base64.b64encode(bytes(range(200))).decode()


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
                                              s("tool_parameters", json.dumps({"bash_command": f"curl -H '{BEARER}' x", "data": EVENT_BLOB})),
                                              s("tool_input", json.dumps({"command": "ls"})),
                                              s("tool_output", f"canary-output-{NONCE}")]),
                    record(5, "api_request_body", [s("body", f"canary-raw-{NONCE}")]),
                    record(6, "hook_execution_complete", [s("hook_name", f"canary-unlisted-{NONCE}")]),
                ]}]},
                {"resource": {"attributes": other}, "scopeLogs": [{"logRecords": [
                    record(1, "user_prompt", [s("prompt", f"canary-other-{NONCE}")]),
                ]}]},
                # A worker home's session (darwin-agent-session-telemetry
                # design D15).
                {"resource": {"attributes": [s("service.name", "claude-code"), s("service.version", "2.1.330"), s("user.name", "cameron"),
                                             s("vanixiets.harness_host", "omnigent")]}, "scopeLogs": [{"logRecords": [
                    record(7, "user_prompt", [s("prompt", "worker prompt")]),
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
                return rows == [[5]]


            wait_for(stored_events, "pyrite's five admitted events in agent.session_event", 240)
            marked = gsql("SELECT event_sequence, user_name, harness_host FROM session_event "
                          "WHERE host_name = 'pyrite' AND harness_host IS NOT NULL", "agent")
            print(f"  harness_host rows: {marked}", flush=True)
            assert marked == [[7, "cameron", "omnigent"]], marked
            rows = gsql(
                "SELECT event_name, host_name, user_name, service_name, prompt, response, input_tokens, output_tokens, "
                "cost_usd_micros, duration_ms, success, tool_name, tool_parameters, speed FROM session_event "
                "WHERE host_name = 'pyrite' AND harness_host IS NULL ORDER BY event_sequence", "agent")
            for row in rows:
                print(f"  admitted: {row}", flush=True)
            assert [r[0] for r in rows] == ["user_prompt", "assistant_response", "api_request", "tool_result"], rows
            assert all(r[1:4] == ["pyrite", "cameron", "claude-code"] for r in rows), rows
            assert rows[0][4] == ADMITTED and rows[1][5] == "admitted response zebrafish", rows
            assert rows[2][6:9] == [100, 50, 1234] and rows[2][13] == "normal", rows
            assert rows[3][9] == 12 and rows[3][10] is True and rows[3][11] == "Bash", rows
            assert "****" in rows[3][12] and "T0k3nAbCdEf9" not in rows[3][12], rows[3][12]
            assert rows[3][12].count("****") == 2 and EVENT_BLOB[100:140] not in rows[3][12], rows[3][12]
            found = gsql(f"SELECT event_name, host_name FROM session_event WHERE matches_term(prompt, '{NONCE}')", "agent")
            print(f"  matches_term(prompt, nonce): {found}", flush=True)
            assert found == [["user_prompt", "pyrite"]], found

            create = gsql("SHOW CREATE TABLE session_event", "agent")[0][1]
            print("  " + create.replace("\n", "\n  "), flush=True)
            assert event_lines() == fresh_events, ("the written pre-marker session_event differs from a fresh one",
                                                   sorted(set(event_lines()) ^ set(fresh_events)))
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
            taps = {kind: store.succeed(f"cat /var/lib/otel-agent-session/tap-{kind}.jsonl") for kind in ("logs", "metrics")}
            for kind, text in taps.items():
                print(f"  tap-{kind}: {len(text)} bytes, nonce {text.count(NONCE)} time(s)", flush=True)
                for key in ("user.email", "organization.id", "user.account_uuid", "tool_output", "prompt_text", "\"cost_usd\"",
                            "hook_name", "terminal.type", "marker", "canary.scope", "canary-", "deploy_record", "T0k3nAbCdEf9"):
                    assert key not in text, (kind, key)
            assert taps["logs"].count(NONCE) == taps["logs"].count(ADMITTED) == 1, taps["logs"]
            assert NONCE not in taps["metrics"], taps["metrics"]

            assert nonce_hits(NONCE) == {"agent.session_event.prompt": 1}
            assert nonce_hits("T0k3nAbCdEf9", EVENT_BLOB[100:140]) == {}
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

          # omp's and Claude Code's spans (design D13, D15), through
          # pyrite's otlp/local, otlp/mesh and the ingress into
          # agent.agent_span. First the schema job's upgrade path on 1.2.1:
          # agent_span as main created it (before D15), and as the D15
          # deploy left it, is brought by the job to the table a fresh
          # store has, and a second run changes nothing.
          # Then omp: a chat span carrying the history (an older prompt, a
          # tool result, the newest prompt), one after a tool, a tool span
          # whose result is stored, cut to 64 KiB and masked, a span with a
          # link (kept, the link not), four spans the prompt copy's gate
          # excludes (design D15's narrowing), one from another service,
          # and six tool results as omp serialises them: bash's with its
          # shell trace (a GitHub token only in its base64 `syntax`),
          # edit's, a failed one, one with every credential shape, an
          # encoded blob, a sha512 in hex and two words the old shapes
          # took, one whose text holds `],"details":`, and one with
          # `details` first; `details` is stripped or the result withheld.
          # Then Claude Code: an interaction, an llm_request with a link,
          # retry events and a detailed-tracing attribute, Bash and Read
          # tool spans whose `tool.output` events become
          # gen_ai.tool.call.result (one of them JSON with a `details`
          # key, left alone), and a failed tool.execution whose status
          # message is stored, cut and masked; account identifiers on every
          # span are not.
          agentSpans = ''
            print("=== case agentSpans", flush=True)
            fresh_start()


            def admin(sql):
                status = store.succeed(
                    f"curl -sS -o /tmp/agent-admin -w '%{{http_code}}' --netrc-file {config()['vars']}/admin.netrc "
                    f"--data-urlencode {shlex.quote('sql=' + sql)} 'http://127.0.0.1:4000/v1/sql?db=agent'"
                ).strip()
                assert status == "200", (sql, status, store.succeed("cat /tmp/agent-admin"))


            def table_lines():
                create = gsql("SHOW CREATE TABLE agent_span", "agent")[0][1]
                return sorted(line.strip().rstrip(",") for line in create.splitlines())


            def schema_job():
                store.succeed("systemctl restart greptimedb-schema.service")
                print("  " + store.succeed("systemctl show -p Result -p ExecMainStatus greptimedb-schema.service").replace("\n", " "), flush=True)


            # The upgrade (design D15), the column order aside: ADD COLUMN
            # appends, so the comparison is of the table's lines, sorted.
            # From main's table before D15, and from the D15 deploy's,
            # which lacks only the full_command and arguments indexes.
            fresh = table_lines()
            schema_job()
            assert table_lines() == fresh, "a second schema run on a fresh store changed agent_span"
            for generation, statement in (("pre-D15", config()["oldSpanTable"]), ("D15", config()["d15SpanTable"])):
                admin("DROP TABLE agent_span")
                admin(statement)
                admin(f"INSERT INTO agent_span (\"timestamp\", service_name, span_name) VALUES (now(), 'old', '{generation} row')")
                old = table_lines()
                missing = sorted(set(fresh) - set(old))
                print(f"  {generation} agent_span lacks {len(missing)} lines: {missing}", flush=True)
                # Each generation also lacks the harness host's column
                # (darwin-agent-session-telemetry design D15).
                marker_column = '"resource_attributes.vanixiets.harness_host" STRING NULL'
                assert missing[0] == marker_column, missing
                assert missing[1:] and all("span_attributes" in line for line in missing[1:]), missing
                if generation == "D15":
                    # The two indexes of then, and the oneshot kind's
                    # column (darwin-agent-session-telemetry design D8).
                    assert [line.split('"')[1] for line in missing[1:]] == [
                        "span_attributes.full_command", "span_attributes.gen_ai.tool.call.arguments",
                        "span_attributes.omp.gen_ai.oneshot.kind"], missing
                    assert all("FULLTEXT INDEX" in line for line in missing[1:3]), missing
                    assert missing[3].endswith("STRING NULL") or missing[3].endswith("STRING NULL,"), missing
                schema_job()
                upgraded = table_lines()
                assert upgraded == fresh, (f"the upgraded {generation} agent_span differs from a fresh one", sorted(set(upgraded) ^ set(fresh)))
                schema_job()
                assert table_lines() == fresh, f"a second schema run on the upgraded {generation} agent_span changed it"
                assert gsql(f"SELECT count(*) FROM agent_span WHERE span_name = '{generation} row'", "agent") == [[1]]
                print(f"  agent_span: {generation} table upgraded to the fresh one, its row kept; the second run changed nothing", flush=True)

            store.succeed(f"systemctl restart {SESSION}.service")
            wait_telemetry(SESSION_PORT)
            NONCE = f"n{time.time_ns()}"
            TRACE = "5b8efff798038103d269b633813fc60c"
            CLAUDE_TRACE = "6c9f00a8a91492143e37c744924ad71d"
            # Assembled here from pieces, so no credential-shaped string
            # exists in the repository (checks.gitleaks); each one's tail
            # is what the store and the tap must never hold.
            planted = {
                "github": "gh" + "p_" + "Zq7Xw3Rt9Lk2Mn5Bv8Cx1Jh4" + "Gf6Ds0Pa3Yu7E",
                "anthropic": "sk-" + "ant-" + "api03-" + ("Xy9Qw8Er7Ty6Ui5Op4As3Df2" * 4)[:85] + "Gh1Jk0Lz" + "AA",
                "pem": "-----BEGIN " + "OPENSSH PRIVATE KEY-----\n" + "b3BlbnNzaC1yZGF0YQ" * 4
                               + "\n-----END " + "OPENSSH PRIVATE KEY-----",
                "bearer": "Authorization: " + "Bear" + "er " + "c4n4ryB34r3r" + "T0k3nGhIjKl8",
                "jwt": "ey" + "JhbGciOiJIUzI1NiJ9." + "ey" + "JzdWIiOiJjYW5hcnkifQ." + "c4n4ryS1gn4tur3QrStUv",
            }
            tails = {
                "github": "Gf6Ds0Pa3Yu7E",
                "anthropic": "Gh1Jk0Lz",
                "pem": "b3BlbnNzaC1yZGF0YQ",
                "bearer": "T0k3nGhIjKl8",
                "jwt": "c4n4ryS1gn4tur3",
            }
            # Every one of schema.nix's credential shapes, each exactly its
            # pattern's match, assembled from pieces likewise (review
            # follow-up 5); then the words the old `sk-`, `sk_` and `rk_`
            # shapes took for keys (follow-up 1).
            shapes = {
                "private-key": planted["pem"],
                "age-secret-key": "AGE-" + "SECRET-KEY-1" + ("QPZRY9X8GF2TVDW0S3JN54KHCE6MUA7L" * 2)[:58],
                "anthropic": planted["anthropic"],
                "openai": "sk-" + "admin-" + ("c4n4ry0p3n4i" + "Adm1nK3y0123") * 6,
                "langfuse": "sk-" + "lf-" + "c4a7e1f0-" + "4b2d-4e6f-8a9c-" + "0d1e2f3a4b5c",
                "github": planted["github"],
                "gitlab": "glp" + "at-" + "c4n4ryG1tL4b" + "T0k3nAbCd",
                "npm": "np" + "m_" + "c4n4ryNpm" * 4,
                "pypi": "pypi-" + "AgEIcHlwaS5vcmc" + "c4n4ryPyP1" * 6,
                "linear": "lin_" + "api_" + ("c4n4ryL1n" * 5)[:40],
                "aws-access-key-id": "AK" + "IA" + "C4N4RYAWSKEYID23",
                "gcp-api-key": "AI" + "za" + ("c4n4ryGcp" * 4)[:35],
                "digitalocean": "do" + "p_v1_" + "0123456789abcdef" * 4,
                "slack": "xo" + "xb-" + "c4n4ry-sl4ck-" + "t0k3n",
                "stripe": "sk" + "_live_" + ("c4n4ryStr1p3" + "K3y0123") * 2,
                "jwt": planted["jwt"],
                "bearer": "Bear" + "er " + "c4n4ryB34r3r" + "T0k3nGhIjKl8",
            }
            assert sorted(shapes) == config()["credentialPatternNames"], sorted(shapes)
            tails.update({f"shape {name}": token[len(token) // 2 - 6:len(token) // 2 + 6] for name, token in shapes.items()})
            WORDS = ["task_test_configuration", "risk-admin-dashboard-components"]
            # The `sk-`, `sk_` and `rk_` keys at the start of a line, after a
            # tab and after a colour code: in omp's JSON the character
            # before each is a letter (`\n`, `\t`, `[32m`), so a word
            # boundary would miss them (review R1).
            OPENAI_LEGACY = "sk-" + "c4n4ryL3g4cy" + "K3y0" * 9
            STRIPE_RESTRICTED = "rk" + "_test_" + ("c4n4ryR3str1ct" + "3d0123") * 2
            LINE_KEYS = [shapes["anthropic"], shapes["openai"], OPENAI_LEGACY, shapes["langfuse"], shapes["stripe"], STRIPE_RESTRICTED]
            LEADS = ["\n", "\t", "\x1b[32m"]
            LINE_INITIAL = "".join(lead + key for lead in LEADS for key in LINE_KEYS)
            LINE_INITIAL_MASKED = "".join(lead + "****" for lead in LEADS for _ in LINE_KEYS)
            tails.update({"openai legacy": OPENAI_LEGACY[-16:], "stripe restricted": STRIPE_RESTRICTED[-16:]})
            # String-typed keys sent as an array and as a map, a token in
            # each: deleted, never stored or sent (review follow-up 2).
            FORGED_TOKEN = "gh" + "p_" + "F0rg3dArr4yT0k3n" + "Zq7Xw3Rt9Lk2Mn5Bv8Cx"
            tails["forged value"] = FORGED_TOKEN[-12:]
            # A GitHub-shaped token only inside the base64 `syntax` of
            # omp's shell trace, as magnetite stored one (design D15).
            TRACE_TOKEN = "gh" + "o_" + "Wq3Er5Ty7Ui9Op1As3Df5" + "Gh7Jk9Lz2Xc4Vb6N"
            SYNTAX = base64.b64encode(f"echo {TRACE_TOKEN}".encode()).decode()
            tails.update({"trace token": TRACE_TOKEN[-12:], "trace syntax": SYNTAX[8:40]})
            # An encoded blob of 268 characters, masked; a sha512 in hex,
            # 128, kept.
            BLOB = base64.b64encode(bytes(range(200))).decode()
            HEX = hashlib.sha512(f"hex {time.time_ns()}".encode()).hexdigest()
            # Two blob-net canaries: a 160-character path of hyphens and
            # slashes, no run of either base64 alphabet 129 long, is kept;
            # a 200-character URL-safe base64 run (it holds `-`) is masked.
            LONG_PATH = ("/" + "/".join(["srv-agent-session-telemetry-run"] * 6))[:160]
            URLSAFE_BLOB = base64.urlsafe_b64encode(bytes(range(150))).decode()
            assert len(URLSAFE_BLOB) == 200 and ("-" in URLSAFE_BLOB or "_" in URLSAFE_BLOB), URLSAFE_BLOB
            tails.update({"blob": BLOB[100:140], "urlsafe blob": URLSAFE_BLOB[100:140]})
            # A key block whose END line is missing, then quoted text: masked
            # up to the quote, so the JSON holding it stays whole.
            ENDLESS = "-----BEGIN " + "EC PRIVATE KEY-----\n" + "MHcCAQEE" * 3 + " "
            QUOTED = '"quoted tail" after it'
            tails["endless key"] = "MHcCAQEEMHcCAQEE"
            WITHHELD = config()["toolResultWithheld"]
            canary = {
                "prompt": f"canary prompt {NONCE}",
                "response": f"canary response {NONCE}",
                "arguments": f"canary arguments {NONCE}",
                "older prompt": f"canary-oldprompt-{NONCE}",
                # Tool output is stored (design D15): omp's result as sent,
                # Claude's from its tool.output event.
                "tool result": f"canary-result-{NONCE}",
                "history result": f"canary-histresult-{NONCE}",
                "system": f"canary-system-{NONCE}",
                "unlisted": f"canary-unlisted-{NONCE}",
                "event": f"canary-event-{NONCE}",
                "status": f"canary-status-{NONCE}",
                "scope": f"canary-scope-{NONCE}",
                "email": f"canary-email-{NONCE}",
                "other service": f"canary-other-{NONCE}",
                # A span with a link is kept; the link's attributes are not
                # (design D15).
                "link": f"canary-link-{NONCE}",
                "linked span": f"canary-linkedspan-{NONCE}",
                # An emitter's own `last_user_message` on a span whose
                # history ends in no user text.
                "forged prompt": f"canary-forgedprompt-{NONCE}",
                # Newest user messages the copy's gate must not take: a
                # step after a tool (a tool result under an in-band
                # dialect), an advisor's, a oneshot's, and a request
                # listing no tools.
                "step 1": f"canary-step1-{NONCE}",
                "advisor": f"canary-advisor-{NONCE}",
                "oneshot": f"canary-oneshot-{NONCE}",
                "no tools": f"canary-notools-{NONCE}",
                # omp 19.1.0 prepends its date and directory reminder as a
                # text part of its own before the person's (design D15).
                "reminder": f"<system-reminder>\nToday: 2026-11-22; current working directory: '/tmp/canary-reminder-{NONCE}'.\n</system-reminder>",
                # Claude Code's spans.
                "claude session": f"canary-claudesession-{NONCE}",
                "user prompt": f"canary user prompt {NONCE}",
                "bash output": f"canary-bashoutput-{NONCE}",
                "read content": f"canary-readcontent-{NONCE}",
                "command": f"canary-command-{NONCE}",
                "path": f"/tmp/canary-path-{NONCE}.txt",
                "claude status": f"canary-claudestatus-{NONCE}",
                "claude link": f"canary-claudelink-{NONCE}",
                "new context": f"canary-newcontext-{NONCE}",
                "attempt": f"canary-attempt-{NONCE}",
                "account": f"canary-account-{NONCE}",
                # omp's tool results (design D15): `content` kept, the
                # `details` re-render cache never.
                "bash content": f"canary-bashcontent-{NONCE}",
                "trace script": f"canary-tracescript-{NONCE}",
                "trace history": f"canary-tracehistory-{NONCE}",
                "edit content": f"canary-editcontent-{NONCE}",
                "edit snapshot": f"canary-editsnapshot-{NONCE}",
                "error content": f"canary-errorcontent-{NONCE}",
                "shapes content": f"canary-shapescontent-{NONCE}",
                "escaped content": f"canary-escapedcontent-{NONCE}",
                "escaped details": f"canary-escapeddetails-{NONCE}",
                "reordered content": f"canary-reorderedcontent-{NONCE}",
                "reordered details": f"canary-reordereddetails-{NONCE}",
                # Claude Code's output is plain text, a `details` key in it
                # its own.
                "claude json": f"canary-claudejson-{NONCE}",
            }
            admitted = ("prompt", "response", "arguments", "tool result", "status", "linked span", "claude session",
                        "user prompt", "bash output", "read content", "command", "path", "claude status",
                        "bash content", "edit content", "error content", "shapes content", "escaped content", "claude json")


            def s(key, value):
                return {"key": key, "value": {"stringValue": value}}


            def iv(key, value):
                return {"key": key, "value": {"intValue": str(value)}}


            def bv(key, value):
                return {"key": key, "value": {"boolValue": value}}


            tools = {"key": "omp.gen_ai.request.available_tools",
                     "value": {"arrayValue": {"values": [{"stringValue": "bash"}, {"stringValue": "read"}]}}}


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
                    iv("omp.gen_ai.agent.step.number", 0), tools,
                    {"key": "gen_ai.usage.input_tokens", "value": {"intValue": "42"}},
                    s("gen_ai.system_instructions", json.dumps([{"type": "text", "content": canary["system"]}])),
                    s("gen_ai.input.messages", json.dumps(history + [{"role": "user", "parts": [
                        {"type": "text", "content": canary["reminder"]}, {"type": "text", "content": canary["prompt"]}]}])),
                    # Past the 64 KiB every kept value is cut to.
                    s("gen_ai.output.messages", json.dumps([{"role": "assistant", "parts": [{"type": "text", "content": canary["response"] + " " + "x " * 35000}]}])),
                    s("canary.unlisted", canary["unlisted"]),
                ],
                "events": [{"name": "exception", "timeUnixNano": str(now - 1500000000),
                            "attributes": [s("exception.message", canary["event"])]}],
                # A failed request's status message is kept and masked.
                "status": {"code": 2, "message": f"{canary['status']} {planted['anthropic']}"},
            }
            after_tool = dict(chat, spanId="eee19b7ec3c1b177", events=[], status={},
                              attributes=[s("gen_ai.operation.name", "chat"), s("gen_ai.input.messages", json.dumps(history)),
                                          iv("omp.gen_ai.agent.step.number", 0), tools,
                                          s("last_user_message", canary["forged prompt"])])
            linked = dict(chat, spanId="eee19b7ec3c1b178", events=[], status={},
                          attributes=[s("gen_ai.operation.name", "chat"), s("gen_ai.conversation.id", canary["linked span"])],
                          links=[{"traceId": TRACE, "spanId": "eee19b7ec3c1b179", "attributes": [s("canary.link", canary["link"])]}])


            def gated(span_id, marker, *attributes):
                messages = history + [{"role": "user", "parts": [{"type": "text", "content": canary[marker]}]}]
                return dict(chat, spanId=span_id, events=[], status={},
                            attributes=[s("gen_ai.operation.name", "chat"), s("gen_ai.input.messages", json.dumps(messages)),
                                        *attributes])


            excluded = [
                gated("eee19b7ec3c1b17a", "step 1", iv("omp.gen_ai.agent.step.number", 1), tools),
                gated("eee19b7ec3c1b17b", "advisor", iv("omp.gen_ai.agent.step.number", 0), tools,
                      s("gen_ai.agent.id", "session-advisor")),
                gated("eee19b7ec3c1b17c", "oneshot", iv("omp.gen_ai.agent.step.number", 0), tools,
                      s("omp.gen_ai.oneshot.kind", "compaction_summary")),
                gated("eee19b7ec3c1b17d", "no tools", iv("omp.gen_ai.agent.step.number", 0)),
            ]
            # omp serialises a tool result with JSON.stringify: no spaces,
            # `content` first, `isError` only when true (design D15).
            def compact(value):
                return json.dumps(value, separators=(",", ":"))


            def text_result(text, **rest):
                return {"content": [{"type": "text", "text": text}], **rest}


            tool = {
                "traceId": TRACE, "spanId": "eee19b7ec3c1b175", "parentSpanId": "eee19b7ec3c1b173",
                "name": "execute_tool bash", "kind": 1,
                "startTimeUnixNano": str(now - 900000000), "endTimeUnixNano": str(now - 800000000),
                "attributes": [
                    s("gen_ai.operation.name", "execute_tool"), s("gen_ai.tool.name", "bash"),
                    s("gen_ai.conversation.id", f"session-{NONCE}"),
                    s("gen_ai.tool.call.arguments", json.dumps({"command": canary["arguments"]})),
                    # Past the 64 KiB cut, two credentials inside it; the
                    # filler in words, so the blob net leaves it.
                    s("gen_ai.tool.call.result", compact(text_result("\n".join(
                        [canary["tool result"], planted["github"], planted["pem"], "y " * 35000])))),
                    s("omp.gen_ai.tool.status", "ok"),
                ],
            }


            def omp_tool(span_id, name, result, tool_status="ok", **extra):
                span = {
                    "traceId": TRACE, "spanId": span_id, "parentSpanId": "eee19b7ec3c1b173",
                    "name": f"execute_tool {name}", "kind": 1,
                    "startTimeUnixNano": str(now - 900000000), "endTimeUnixNano": str(now - 800000000),
                    "attributes": [s("gen_ai.operation.name", "execute_tool"), s("gen_ai.tool.name", name),
                                   s("gen_ai.tool.call.result", compact(result)), s("omp.gen_ai.tool.status", tool_status)],
                }
                span.update(extra)
                return span


            # bash's `details` as omp 19.1.0 sends it (key shapes read on
            # magnetite, logs/d15-magnetite-extra-20261122T2015Z.log), its
            # shell trace holding the token in base64 only.
            shell_trace = {"v": 1, "seq": 1, "status": "ok", "rootVpid": 1073742212, "t_ns": 956341,
                           "script": f"echo {canary['trace script']}", "units": [{"syntax": SYNTAX}],
                           "history": [{"text": canary["trace history"], "argv": ["echo", canary["trace history"]]}]}
            bash_details = {"wallTimeNoticeEmitted": False, "timeoutSeconds": 300, "wallTimeMs": 12.5, "trace": shell_trace}
            SHAPES_TEXT = " | ".join([canary["shapes content"], *shapes.values(), BLOB, HEX, LONG_PATH, URLSAFE_BLOB, *WORDS, ENDLESS + QUOTED, LINE_INITIAL])
            ESCAPED_TEXT = f"{canary['escaped content']} ],\"details\":{{\"x\":1}}"
            CLAUDE_JSON = compact({"content": [canary["claude json"]], "details": {"note": "kept"}})
            # Each span id with its result as sent and as it must be
            # stored and reach Langfuse.
            results = {
                "eee19b7ec3c1b180": (
                    text_result(canary["bash content"], details=bash_details),
                    compact(text_result(canary["bash content"]))),
                "eee19b7ec3c1b181": (
                    text_result(canary["edit content"], details={
                        "diff": f"-old\n+{canary['edit snapshot']}", "oldText": "old", "newText": canary["edit snapshot"],
                        "diagnostics": {"summary": "ok", "messages": []}, "perFileResults": []}),
                    compact(text_result(canary["edit content"]))),
                "eee19b7ec3c1b182": (
                    text_result(canary["error content"], details=bash_details, isError=True),
                    compact(text_result(canary["error content"], isError=True))),
                "eee19b7ec3c1b183": (
                    text_result(SHAPES_TEXT),
                    compact(text_result(" | ".join([canary["shapes content"], *["****"] * len(shapes), "****", HEX, LONG_PATH, "****", *WORDS, "****" + QUOTED, LINE_INITIAL_MASKED])))),
                "eee19b7ec3c1b184": (
                    text_result(ESCAPED_TEXT, details={"history": [{"text": canary["escaped details"]}]}),
                    compact(text_result(ESCAPED_TEXT))),
                # `details` before `content`: the strip finds no
                # `],"details":`, so the whole result is withheld.
                "eee19b7ec3c1b185": (
                    {"details": {"history": [{"text": canary["reordered details"]}], "trace": shell_trace},
                     "content": [{"type": "text", "text": canary["reordered content"]}]},
                    WITHHELD),
            }
            result_spans = [omp_tool(span_id, "edit" if span_id.endswith("81") else "bash", sent)
                         for span_id, (sent, _) in results.items() if not span_id.endswith("82")]
            result_spans.append(omp_tool("eee19b7ec3c1b182", "bash", results["eee19b7ec3c1b182"][0], tool_status="error",
                                      status={"code": 2, "message": canary["error content"]}))
            next(span for span in result_spans if span["spanId"] == "eee19b7ec3c1b183")["attributes"].append(
                {"key": "gen_ai.tool.call.arguments",
                 "value": {"kvlistValue": {"values": [{"key": "command", "value": {"stringValue": f"echo {FORGED_TOKEN}"}}]}}})


            def claude_span(span_id, parent, name, attributes, **extra):
                span = {
                    "traceId": CLAUDE_TRACE, "spanId": span_id, "name": name, "kind": 1,
                    "startTimeUnixNano": str(now - 700000000), "endTimeUnixNano": str(now - 600000000),
                    # Claude Code's standard attributes, on every span.
                    "attributes": [s("span.type", name.removeprefix("claude_code.")), s("session.id", canary["claude session"]),
                                   s("user.email", f"{canary['account']}@example.com"), s("organization.id", canary["account"]),
                                   s("user.account_uuid", canary["account"]), s("user.account_id", canary["account"]),
                                   s("user.id", canary["account"]), s("terminal.type", "tmux")] + attributes,
                }
                if parent:
                    span["parentSpanId"] = parent
                span.update(extra)
                return span


            claude_spans = [
                claude_span("aaa19b7ec3c1b101", None, "claude_code.interaction", [
                    s("user_prompt", canary["user prompt"]), iv("user_prompt_length", 24), iv("interaction.sequence", 1)]),
                claude_span("aaa19b7ec3c1b102", "aaa19b7ec3c1b101", "claude_code.llm_request", [
                    s("model", "claude-opus-5-5"), s("gen_ai.request.model", "claude-opus-5-5"), iv("input_tokens", 100),
                    iv("output_tokens", 50), iv("cache_read_tokens", 7), iv("cache_creation_tokens", 3), iv("duration_ms", 900),
                    bv("success", True), s("request_id", "req_claude_1"), s("new_context", canary["new context"])],
                    events=[{"name": "gen_ai.request.attempt", "timeUnixNano": str(now - 650000000),
                             "attributes": [iv("attempt", 1), s("client_request_id", canary["attempt"])]}],
                    links=[{"traceId": "7d0e11b9ba25a3254f48d855a35be82e", "spanId": "fff19b7ec3c1b101",
                            "attributes": [s("canary.link", canary["claude link"])]}]),
                claude_span("aaa19b7ec3c1b103", "aaa19b7ec3c1b101", "claude_code.tool", [
                    s("tool_name", "Bash"), s("tool_use_id", "toolu_claude_1"), s("gen_ai.tool.call.id", "toolu_claude_1"),
                    s("full_command", f"echo {canary['command']}"), iv("duration_ms", 12)],
                    events=[{"name": "tool.output", "timeUnixNano": str(now - 650000000),
                             "attributes": [s("output", "\n".join([canary["bash output"], planted["bearer"], planted["jwt"]])),
                                            s("bash_command", f"echo {canary['command']}")]}]),
                claude_span("aaa19b7ec3c1b104", "aaa19b7ec3c1b101", "claude_code.tool", [
                    s("tool_name", "Read"), s("tool_use_id", "toolu_claude_2"), s("file_path", canary["path"])],
                    events=[{"name": "tool.output", "timeUnixNano": str(now - 650000000),
                             "attributes": [s("content", "\n".join([canary["read content"], planted["pem"]])),
                                            s("file_path", canary["path"])]}]),
                claude_span("aaa19b7ec3c1b105", "aaa19b7ec3c1b103", "claude_code.tool.execution", [
                    s("tool_use_id", "toolu_claude_1"), bv("success", False), s("error", "ShellError"),
                    s("error.type", "tool_error"),
                    {"key": "gen_ai.tool.call.result", "value": {"arrayValue": {"values": [{"stringValue": f"forged {FORGED_TOKEN}"}]}}}],
                    # Past the 64 KiB cut, a credential inside it.
                    status={"code": 2, "message": " ".join([canary["claude status"], planted["github"], "z " * 35000])}),
                # Output holding JSON with `content` and `details` keys: the
                # strip and the withholding touch omp's spans only.
                claude_span("aaa19b7ec3c1b106", "aaa19b7ec3c1b101", "claude_code.tool", [
                    s("tool_name", "Read"), s("tool_use_id", "toolu_claude_3")],
                    events=[{"name": "tool.output", "timeUnixNano": str(now - 650000000),
                             "attributes": [s("content", CLAUDE_JSON)]}]),
            ]
            body = {"resourceSpans": [
                {"resource": {"attributes": [s("service.name", "oh-my-pi"), s("service.version", "19.1.0"), s("user.name", "cameron"),
                                             s("user.email", canary["email"]), s("host.name", f"canary-host-{NONCE}"),
                                             s("vanixiets.database", "fleet")]},
                 "scopeSpans": [{"scope": {"name": "omp", "attributes": [s("canary.scope", canary["scope"])]},
                                 "spans": [chat, after_tool, tool, linked] + excluded + result_spans}]},
                {"resource": {"attributes": [s("service.name", "claude-code"), s("service.version", "2.1.330"), s("user.name", "cameron"),
                                             s("os.type", "linux"), s("host.arch", "amd64"), s("vanixiets.harness_host", "omnigent")]},
                 "scopeSpans": [{"scope": {"name": "com.anthropic.claude_code.tracing"}, "spans": claude_spans}]},
                {"resource": {"attributes": [s("service.name", "canary-other"), s("user.name", "cameron")]},
                 "scopeSpans": [{"spans": [dict(tool, spanId="eee19b7ec3c1b176",
                                                attributes=[s("gen_ai.input.messages", canary["other service"])])]}]},
            ]}
            # Past one argument's 128 KiB limit, so in base64 chunks.
            encoded = base64.b64encode(json.dumps(body).encode()).decode()
            store.succeed("rm -f /tmp/agent-spans.b64")
            for i in range(0, len(encoded), 65536):
                store.succeed(f"printf %s {encoded[i:i + 65536]} >> /tmp/agent-spans.b64")
            store.succeed("base64 -d /tmp/agent-spans.b64 > /tmp/agent-spans.json")
            status = store.succeed(
                "curl -sS -o /tmp/agent-spans-answer -w '%{http_code}' -H 'Content-Type: application/json' "
                "--data @/tmp/agent-spans.json http://127.0.0.1:4318/v1/traces"
            ).strip()
            print(f"  POST otlp/local /v1/traces: {status} {store.succeed('cat /tmp/agent-spans-answer')}", flush=True)
            assert status == "200", status

            # What left the host, before the store is asked: both linked
            # spans, neither link. The file exporter flushes once a second.
            store.wait_until_succeeds(f"grep -q {NONCE} /var/lib/otel-agent-session/tap-traces.jsonl", timeout=60)
            tap = store.succeed("cat /var/lib/otel-agent-session/tap-traces.jsonl")
            assert canary["link"] not in tap and canary["claude link"] not in tap, "a link left the host"
            assert '"links"' not in tap, "a span left the host with links"
            for what, tail in tails.items():
                assert tail not in tap, f"{what} left the host unmasked"
            for what, needle in (("trace token", TRACE_TOKEN), ("trace syntax", SYNTAX), ("blob", BLOB)):
                assert needle not in tap, f"{what} left the host"


            def stored_spans():
                status, body = _request("/v1/sql", "agent", [("sql", "SELECT count(*) FROM agent_span WHERE \"resource_attributes.host.name\" = 'pyrite'")])
                rows = json.loads(body)["output"][0]["records"]["rows"] if status == 200 else None
                print(f"  agent_span rows from pyrite: {status} {rows}", flush=True)
                return rows == [[20]]


            wait_for(stored_spans, "pyrite's twenty spans in agent.agent_span", 240)
            columns = ["span_id", "span_name", "span_attributes.last_user_message", "span_attributes.gen_ai.output.messages",
                       "span_attributes.gen_ai.tool.call.arguments", "span_attributes.gen_ai.usage.input_tokens",
                       "resource_attributes.user.name", "resource_attributes.host.name", "service_name", "span_status_message",
                       "span_attributes.gen_ai.tool.call.result", "span_attributes.omp.gen_ai.tool.status",
                       "span_attributes.session.id", "span_attributes.user_prompt", "span_attributes.tool_name",
                       "span_attributes.tool_use_id", "span_attributes.full_command", "span_attributes.file_path",
                       "span_attributes.duration_ms", "span_attributes.success", "span_attributes.error",
                       "span_attributes.input_tokens", "span_attributes.output_tokens", "span_attributes.cache_read_tokens",
                       "span_attributes.cache_creation_tokens", "span_attributes.gen_ai.request.model", "span_attributes.error.type",
                       "resource_attributes.vanixiets.harness_host"]
            found_rows = gsql("SELECT " + ", ".join(f'"{c}"' for c in columns)
                              + " FROM agent_span WHERE \"resource_attributes.host.name\" = 'pyrite' ORDER BY span_id", "agent")
            spans = {row[0]: dict(zip(columns, row)) for row in found_rows}
            for row in spans.values():
                shown = {k: (v[:120] + "…" if isinstance(v, str) and len(v) > 120 else v) for k, v in row.items() if v not in (None, "")}
                print(f"  span: {json.dumps(shown)}", flush=True)
            omp = [spans[i] for i in ("eee19b7ec3c1b174", "eee19b7ec3c1b175", "eee19b7ec3c1b177", "eee19b7ec3c1b178",
                                      "eee19b7ec3c1b17a", "eee19b7ec3c1b17b", "eee19b7ec3c1b17c", "eee19b7ec3c1b17d")]
            assert [r["service_name"] for r in spans.values()].count("claude-code") == 6, spans.keys()
            assert all(r["resource_attributes.user.name"] == "cameron" and r["resource_attributes.host.name"] == "pyrite"
                       for r in spans.values()), spans
            # Claude Code's resource carries a worker home's harness host,
            # omp's none (darwin-agent-session-telemetry design D15).
            assert all(r["resource_attributes.vanixiets.harness_host"] == ("omnigent" if r["service_name"] == "claude-code" else None)
                       for r in spans.values()), spans
            chat_row, tool_row = omp[0], omp[1]
            assert chat_row["span_attributes.last_user_message"] == canary["prompt"], chat_row
            assert canary["response"] in chat_row["span_attributes.gen_ai.output.messages"], chat_row
            assert chat_row["span_attributes.gen_ai.usage.input_tokens"] == 42, chat_row
            assert len(chat_row["span_attributes.gen_ai.output.messages"].encode()) <= 65536
            # Absent on the span after a tool and on each of the four the
            # gate excludes.
            assert all(r["span_attributes.last_user_message"] is None for r in omp[2:]), omp
            assert canary["arguments"] in tool_row["span_attributes.gen_ai.tool.call.arguments"], tool_row
            # The tool result stored, cut and masked (design D15).
            result = tool_row["span_attributes.gen_ai.tool.call.result"]
            print(f"  omp tool result: {len(result.encode())} bytes, masked {result.count('****')} time(s)", flush=True)
            assert canary["tool result"] in result and 65000 < len(result.encode()) <= 65536, len(result.encode())
            assert result.count("****") == 2 and tool_row["span_attributes.omp.gen_ai.tool.status"] == "ok", result[:400]
            # The status message kept and masked; elsewhere empty.
            assert chat_row["span_status_message"] == f"{canary['status']} ****", chat_row
            assert all(r["span_status_message"] == "" for r in omp[1:]), omp
            # The linked span kept.
            assert omp[3]["span_name"] == "chat claude-opus", omp[3]
            # omp's tool results without `details` (design D15): bash's
            # shell trace, edit's snapshots and a failed result's trace
            # gone, `isError` kept; a `],"details":` inside the content's
            # text left alone; a result with `details` first withheld
            # whole. Every credential shape and the blob masked, the hex
            # and the two words kept.
            for span_id, (_, expected) in results.items():
                stored = spans[span_id]["span_attributes.gen_ai.tool.call.result"]
                print(f"  {span_id} result: {stored[:300]}", flush=True)
                assert stored == expected, (span_id, stored[:600], expected[:600])
            failed_tool = spans["eee19b7ec3c1b182"]
            assert failed_tool["span_attributes.omp.gen_ai.tool.status"] == "error", failed_tool
            assert failed_tool["span_status_message"] == canary["error content"], failed_tool
            shapes_result = spans["eee19b7ec3c1b183"]["span_attributes.gen_ai.tool.call.result"]
            assert HEX in shapes_result and LONG_PATH in shapes_result and all(word in shapes_result for word in WORDS), shapes_result
            assert shapes_result.count("****") == len(shapes) + 3 + len(LEADS) * len(LINE_KEYS) and URLSAFE_BLOB[60:120] not in shapes_result and json.loads(shapes_result), shapes_result
            print(f"  {len(shapes)} credential shapes, {len(LEADS) * len(LINE_KEYS)} line-initial keys, a {len(BLOB)}-character blob and a {len(URLSAFE_BLOB)}-character URL-safe run masked; the 128-character hex, the {len(LONG_PATH)}-character path, {WORDS} kept", flush=True)
            assert spans["eee19b7ec3c1b183"]["span_attributes.gen_ai.tool.call.arguments"] is None, spans["eee19b7ec3c1b183"]

            # Claude Code's spans (design D15).
            interaction, llm, bash, read, execution, claude_json = (spans[f"aaa19b7ec3c1b10{n}"] for n in range(1, 7))
            assert all(r["span_attributes.session.id"] == canary["claude session"]
                       for r in (interaction, llm, bash, read, execution, claude_json)), spans
            # Claude Code's output untouched by omp's strip.
            assert claude_json["span_attributes.gen_ai.tool.call.result"] == CLAUDE_JSON, claude_json
            assert interaction["span_attributes.user_prompt"] == canary["user prompt"], interaction
            assert [llm[c] for c in ("span_attributes.input_tokens", "span_attributes.output_tokens",
                                     "span_attributes.cache_read_tokens", "span_attributes.cache_creation_tokens",
                                     "span_attributes.duration_ms", "span_attributes.success",
                                     "span_attributes.gen_ai.request.model")] == [100, 50, 7, 3, 900, True, "claude-opus-5-5"], llm
            assert bash["span_attributes.tool_name"] == "Bash" and bash["span_attributes.tool_use_id"] == "toolu_claude_1", bash
            assert bash["span_attributes.full_command"] == f"echo {canary['command']}", bash
            assert bash["span_attributes.gen_ai.tool.call.result"] == f"{canary['bash output']}\nAuthorization: ****\n****", bash
            assert read["span_attributes.file_path"] == canary["path"], read
            assert read["span_attributes.gen_ai.tool.call.result"] == f"{canary['read content']}\n****", read
            assert execution["span_attributes.success"] is False and execution["span_attributes.error"] == "ShellError", execution
            assert execution["span_attributes.error.type"] == "tool_error", execution
            assert execution["span_attributes.gen_ai.tool.call.result"] is None, execution
            message = execution["span_status_message"]
            assert message.startswith(f"{canary['claude status']} **** z") and 65000 < len(message.encode()) <= 65536, message[:200]

            found = gsql(f"SELECT span_name FROM agent_span WHERE matches_term(\"span_attributes.last_user_message\", '{NONCE}')", "agent")
            print(f"  matches_term(last_user_message, nonce): {found}", flush=True)
            assert found == [["chat claude-opus"]], found
            found = gsql(f"SELECT span_id FROM agent_span WHERE matches_term(\"span_attributes.gen_ai.tool.call.result\", '{NONCE}') ORDER BY span_id", "agent")
            print(f"  matches_term(gen_ai.tool.call.result, nonce): {found}", flush=True)
            assert found == [[i] for i in ("aaa19b7ec3c1b103", "aaa19b7ec3c1b104", "aaa19b7ec3c1b106", "eee19b7ec3c1b175",
                                           "eee19b7ec3c1b180", "eee19b7ec3c1b181", "eee19b7ec3c1b182", "eee19b7ec3c1b183",
                                           "eee19b7ec3c1b184")], found
            # Claude's commands and both harnesses' arguments searchable
            # (review follow-up 8).
            for column, span_id in (("full_command", "aaa19b7ec3c1b103"), ("gen_ai.tool.call.arguments", "eee19b7ec3c1b175")):
                found = gsql(f"SELECT span_id FROM agent_span WHERE matches_term(\"span_attributes.{column}\", '{NONCE}')", "agent")
                print(f"  matches_term({column}, nonce): {found}", flush=True)
                assert found == [[span_id]], (column, found)
            create = gsql("SHOW CREATE TABLE agent_span", "agent")[0][1]
            for column in ("last_user_message", "gen_ai.output.messages", "gen_ai.tool.call.result", "user_prompt",
                           "full_command", "gen_ai.tool.call.arguments"):
                assert f"\"span_attributes.{column}\" STRING NULL FULLTEXT INDEX WITH(analyzer = 'English', backend = 'bloom', case_sensitive = 'false'" in create, column
            assert "\"span_attributes.success\" BOOLEAN NULL" in create, create
            options = gsql("SELECT create_options FROM information_schema.tables WHERE table_schema = 'agent' AND table_name = 'agent_span'", "agent")[0][0]
            print(f"  agent_span create_options: {options}", flush=True)
            assert "table_data_model=greptime_trace_v1" in options and "ttl" not in options, options
            # The Jaeger lookup tables the store fills beside the spans.
            print(f"  agent_span_operations: {gsql('SELECT service_name, span_name, span_kind FROM agent_span_operations ORDER BY span_name', 'agent')}", flush=True)

            # Everything that left the host.
            tap = store.succeed("cat /var/lib/otel-agent-session/tap-traces.jsonl")
            print(f"  tap-traces: {len(tap)} bytes, nonce {tap.count(NONCE)} time(s)", flush=True)
            for what, value in canary.items():
                assert (value in tap) == (what in admitted), (what, value in tap)
            for key in ("gen_ai.input.messages", "gen_ai.system_instructions", "canary.unlisted", "canary.scope", "user.email",
                        "organization.id", "user.account_uuid", "user.account_id", "\"user.id\"", "terminal.type", "new_context",
                        "exception", "gen_ai.request.attempt", "tool.output", "os.type",
                        "vanixiets.database\",\"value\":{\"stringValue\":\"fleet"):
                assert key not in tap, key

            # Every string and JSON column of every database, as regulator.
            assert nonce_hits(NONCE) == {
                "agent.agent_span.span_attributes.last_user_message": 1,
                "agent.agent_span.span_attributes.gen_ai.conversation.id": 3,
                "agent.agent_span.span_attributes.gen_ai.output.messages": 1,
                "agent.agent_span.span_attributes.gen_ai.tool.call.arguments": 1,
                "agent.agent_span.span_attributes.gen_ai.tool.call.result": 9,
                "agent.agent_span.span_status_message": 3,
                "agent.agent_span.span_attributes.session.id": 6,
                "agent.agent_span.span_attributes.user_prompt": 1,
                "agent.agent_span.span_attributes.full_command": 1,
                "agent.agent_span.span_attributes.file_path": 1,
            }
            # Every credential, the token inside the base64 syntax, decoded
            # or not, and the blob: in no column.
            assert nonce_hits(*tails.values(), TRACE_TOKEN, SYNTAX, BLOB) == {}, "a credential, the trace token or the blob stored"
            failed = {port: metric(port, r"otelcol_exporter_send_failed_[a-z_]+") for port in (INGRESS_PORT, SESSION_PORT)}
            print(f"  send_failed {failed}", flush=True)
            assert failed == {INGRESS_PORT: 0, SESSION_PORT: 0}, failed

            # Langfuse (design D16): the same twenty spans, after the same
            # stages, with the test key pair and the ingestion version, and
            # Langfuse's names; none of them reaches the store.
            assert "langfuse." not in tap, "a Langfuse attribute reached the store's exporter"
            wait_for(lambda: set(sink_spans(sink_records(NONCE))) >= set(spans), "the twenty spans at the Langfuse sink", 120)
            records = sink_records(NONCE)
            basic = langfuse_basic()
            for r in records:
                assert (r["path"], r["authorization"] == basic, r["ingestion_version"], r["content_type"]) == (
                    "/api/public/otel/v1/traces", True, "4", "application/x-protobuf"), (r["path"], r["ingestion_version"], r["content_type"])
            lf = sink_spans(records)
            print(f"  Langfuse sink: {len(records)} request(s), {len(lf)} spans, {sum(r['bytes'] for r in records)} bytes", flush=True)
            assert set(lf) == set(spans), sorted(set(lf) ^ set(spans))
            blob = json.dumps(records)
            for what, tail in tails.items():
                assert tail not in blob, f"{what} reached Langfuse unmasked"
            for what, needle in (("trace token", TRACE_TOKEN), ("trace syntax", SYNTAX), ("blob", BLOB)):
                assert needle not in blob, f"{what} reached Langfuse"
            for what, value in canary.items():
                assert (value in blob) == (what in admitted), (what, value in blob)
            for key in ("vanixiets.", "last_user_message", "user_prompt", "\"input_tokens\"", "\"cache_read_tokens\"", "links", "canary.link",
                        "omp.gen_ai.oneshot.kind"):
                assert key not in blob, key


            def text(attributes, key):
                return attributes.get(key, {}).get("stringValue")


            for span_id, (resource, attributes, span) in lf.items():
                assert text(resource, "user.name") == "cameron", (span_id, resource)
                # Not Langfuse's (review follow-up 3).
                assert "host.name" not in resource and "service.version" not in resource, (span_id, resource)
                assert not {"tool_use_id", "duration_ms"} & attributes.keys(), (span_id, attributes.keys())
                for key, value in attributes.items():
                    assert len((value.get("stringValue") or "").encode()) <= 65536, (span_id, key)
            chat_lf, tool_lf = lf["eee19b7ec3c1b174"][1], lf["eee19b7ec3c1b175"][1]
            assert text(chat_lf, "langfuse.observation.input") == canary["prompt"], chat_lf.keys()
            assert canary["response"] in text(chat_lf, "langfuse.observation.output") and "gen_ai.output.messages" not in chat_lf
            assert chat_lf["gen_ai.usage.input_tokens"] == {"intValue": "42"} and text(chat_lf, "gen_ai.conversation.id") == f"session-{NONCE}"
            # omp's tool span: Langfuse reads its arguments and result.
            assert not any(k.startswith("langfuse.") for k in tool_lf), tool_lf.keys()
            assert text(tool_lf, "gen_ai.tool.call.result").count("****") == 2 and canary["arguments"] in text(tool_lf, "gen_ai.tool.call.arguments")
            interaction_lf, llm_lf, bash_lf, read_lf = (lf[f"aaa19b7ec3c1b10{n}"][1] for n in range(1, 5))
            assert text(interaction_lf, "langfuse.observation.input") == canary["user prompt"], interaction_lf.keys()
            assert text(interaction_lf, "session.id") == canary["claude session"]
            assert [llm_lf.get(k) for k in ("gen_ai.usage.input_tokens", "gen_ai.usage.output_tokens", "gen_ai.usage.cache_read.input_tokens",
                                            "gen_ai.usage.cache_creation.input_tokens")] == [{"intValue": v} for v in ("100", "50", "7", "3")], llm_lf
            assert text(bash_lf, "langfuse.observation.input") == f"echo {canary['command']}", bash_lf.keys()
            assert text(bash_lf, "langfuse.observation.output") == f"{canary['bash output']}\nAuthorization: ****\n****", bash_lf.keys()
            assert "gen_ai.tool.call.result" not in bash_lf
            assert text(read_lf, "langfuse.observation.input") == canary["path"] and text(read_lf, "langfuse.observation.output") == f"{canary['read content']}\n****"
            # omp's results as the store holds them: stripped, withheld,
            # masked; Claude's JSON output untouched.
            for span_id, (_, expected) in results.items():
                assert text(lf[span_id][1], "gen_ai.tool.call.result") == expected, (span_id, text(lf[span_id][1], "gen_ai.tool.call.result"))
            assert text(lf["aaa19b7ec3c1b106"][1], "langfuse.observation.output") == CLAUDE_JSON
            print("  Langfuse: the store's spans, masked and cut, under Langfuse's names; none reached the store", flush=True)
            print("ok: agentSpans", flush=True)
          '';

          # Langfuse's branch cannot cost the store anything (design D16).
          # With the sink down, then answering 403, 429 and 413: the
          # emitter's POST succeeds, otlp/local refuses nothing, the store
          # holds each batch exactly once, Langfuse's queue never refuses,
          # and the exporter drops the batch: at once for a permanent answer,
          # at the test's retry limit for a retryable one, after retrying
          # within it. Claude's blocked_on_user span reaches the store, not
          # Langfuse.
          langfuse = ''
            print("=== case langfuse", flush=True)
            fresh_start()
            store.succeed("systemctl start langfuse-sink.service")
            sink_mode("ok")
            store.succeed(f"systemctl restart {SESSION}.service")
            wait_telemetry(SESSION_PORT)
            RETRY = int(config()["langfuseTestRetry"].removesuffix("s"))
            CAPACITY = 32 * 1024 * 1024


            def lf_metric(name):
                return metric(SESSION_PORT, name, {"exporter": "otlp_http/langfuse"})


            def counters():
                return {
                    "refused": metric(SESSION_PORT, r"otelcol_receiver_refused_[a-z_]+", {"receiver": "otlp/local"}),
                    "enqueue_failed": metric(SESSION_PORT, r"otelcol_exporter_enqueue_failed_[a-z_]+"),
                    "store_send_failed": metric(SESSION_PORT, r"otelcol_exporter_send_failed_[a-z_]+", {"exporter": "otlp_http/ingress-traces"}),
                    "langfuse_send_failed": lf_metric("otelcol_exporter_send_failed_spans"),
                    "langfuse_sent": lf_metric("otelcol_exporter_sent_spans"),
                }


            def a(key, value):
                return {"key": key, "value": {"stringValue": value}}


            def lf_post(nonce, spans, service="oh-my-pi"):
                body = {"resourceSpans": [{"resource": {"attributes": [a("service.name", service), a("user.name", "cameron")]},
                                           "scopeSpans": [{"spans": spans}]}]}
                store.succeed(f"cat > /tmp/langfuse-{nonce}.json <<'EOF'\n{json.dumps(body)}\nEOF")
                return store.succeed(
                    "curl -sS -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' "
                    f"--data @/tmp/langfuse-{nonce}.json http://127.0.0.1:4318/v1/traces"
                ).strip()


            def omp_tools(nonce, n):
                now = time.time_ns()
                trace = os.urandom(16).hex()
                return [{"traceId": trace, "spanId": os.urandom(8).hex(), "name": "execute_tool bash", "kind": 1,
                         "startTimeUnixNano": str(now - 1000000), "endTimeUnixNano": str(now),
                         "attributes": [a("gen_ai.operation.name", "execute_tool"), a("gen_ai.conversation.id", nonce),
                                        a("gen_ai.tool.call.arguments", json.dumps({"command": f"echo {nonce} {i}"})),
                                        a("gen_ai.tool.call.result", f"{nonce} result {i}")]} for i in range(n)]


            def lf_stored(nonce, column="gen_ai.conversation.id"):
                return gsql(f"SELECT count(*) FROM agent_span WHERE \"span_attributes.{column}\" = '{nonce}'", "agent")[0][0]


            # ok: a Claude tool and its blocked_on_user child; the child
            # reaches the store but not Langfuse.
            nonce = f"lfok{time.time_ns()}"
            now = time.time_ns()
            trace = os.urandom(16).hex()
            claude = [
                {"traceId": trace, "spanId": "bbb19b7ec3c1b101", "name": "claude_code.tool", "kind": 1,
                 "startTimeUnixNano": str(now - 3000000), "endTimeUnixNano": str(now),
                 "attributes": [a("session.id", nonce), a("tool_name", "Bash"), a("full_command", f"echo {nonce}")]},
                {"traceId": trace, "spanId": "bbb19b7ec3c1b102", "parentSpanId": "bbb19b7ec3c1b101",
                 "name": "claude_code.tool.blocked_on_user", "kind": 1,
                 "startTimeUnixNano": str(now - 3000000), "endTimeUnixNano": str(now - 2000000),
                 "attributes": [a("session.id", nonce), a("decision", "accept")]},
            ]
            assert lf_post(nonce, claude, "claude-code") == "200"
            wait_for(lambda: lf_stored(nonce, "session.id") == 2, "both Claude spans in the store", 120)
            wait_for(lambda: "bbb19b7ec3c1b101" in sink_spans(sink_records(nonce)), "the Claude tool span at the sink", 120)
            time.sleep(12)
            assert set(sink_spans(sink_records(nonce))) == {"bbb19b7ec3c1b101"}, sink_spans(sink_records(nonce)).keys()
            print("  ok: blocked_on_user stored, not sent to Langfuse", flush=True)

            # omp's helper requests (darwin-agent-session-telemetry design
            # D8): chat spans of one completion each, the startup requests
            # and a job caption as roots, a job widget inside a session's
            # trace as omp also sends it. All five reach the store with
            # their kind; Langfuse gets the compaction alone, without the
            # kind.
            nonce = f"lfoneshot{time.time_ns()}"
            now = time.time_ns()
            kinds = {"ccc19b7ec3c1b101": "skill_description", "ccc19b7ec3c1b102": "mcp_namespace_hint",
                     "ccc19b7ec3c1b103": "compaction_summary", "ccc19b7ec3c1b104": "job_caption",
                     "ccc19b7ec3c1b105": "job_widget"}
            parents = {"ccc19b7ec3c1b105": "ccc19b7ec3c1b1ff"}
            oneshots = [{"traceId": os.urandom(16).hex(), "spanId": span_id, "name": "chat claude-haiku-4-5", "kind": 3,
                         "startTimeUnixNano": str(now - 2000000), "endTimeUnixNano": str(now),
                         **({"parentSpanId": parents[span_id]} if span_id in parents else {}),
                         "attributes": [a("gen_ai.operation.name", "chat"), a("gen_ai.conversation.id", nonce),
                                        a("omp.gen_ai.oneshot.kind", kind)]} for span_id, kind in kinds.items()]
            assert lf_post(nonce, oneshots) == "200"
            wait_for(lambda: lf_stored(nonce) == len(kinds), "the five oneshot spans in the store", 120)
            stored = gsql(f"SELECT \"span_attributes.omp.gen_ai.oneshot.kind\" FROM agent_span WHERE \"span_attributes.gen_ai.conversation.id\" = '{nonce}' ORDER BY 1", "agent")
            assert [row[0] for row in stored] == sorted(kinds.values()), stored
            wait_for(lambda: "ccc19b7ec3c1b103" in sink_spans(sink_records(nonce)), "the compaction span at the sink", 120)
            time.sleep(12)
            sent = sink_spans(sink_records(nonce))
            assert set(sent) == {"ccc19b7ec3c1b103"}, sent.keys()
            assert "omp.gen_ai.oneshot.kind" not in sent["ccc19b7ec3c1b103"][1], sent["ccc19b7ec3c1b103"][1].keys()
            print("  ok: helper requests stored with their kind, not sent to Langfuse; the compaction sent without it", flush=True)

            results = {}
            for mode in ("down", "403", "429", "413"):
                if mode == "down":
                    store.succeed("systemctl stop langfuse-sink.service")
                else:
                    sink_mode(mode)
                    store.succeed("systemctl start langfuse-sink.service")
                    store.wait_until_succeeds(f"bash -c 'echo > /dev/tcp/127.0.0.1/{config()['sinkPort']}'", timeout=30)
                before = counters()
                nonce = f"lf{mode}{time.time_ns()}"
                status = lf_post(nonce, omp_tools(nonce, 5))
                posted = time.monotonic()
                assert status == "200", (mode, status)
                wait_for(lambda: lf_stored(nonce) == 5, f"the {mode} batch in the store", 120)
                peak = 0
                while True:
                    current = counters()
                    peak = max(peak, lf_metric("otelcol_exporter_queue_size"))
                    if current["langfuse_send_failed"] - before["langfuse_send_failed"] >= 5:
                        break
                    assert time.monotonic() - posted < 180, (mode, current, before)
                    time.sleep(1)
                dropped_after = time.monotonic() - posted
                wait_for(lambda: lf_metric("otelcol_exporter_queue_size") == 0, f"Langfuse's queue empty after {mode}", 60)
                time.sleep(10)
                after = counters()
                attempts = len(sink_records(nonce))
                r = {"status": status, "stored": lf_stored(nonce), "dropped_after_s": round(dropped_after, 1),
                     "attempts": attempts, "queue_peak_bytes": peak, **{k: after[k] - before[k] for k in after}}
                results[mode] = r
                print(f"  {mode}: {json.dumps(r)}", flush=True)
                # The store's path untouched: once each, nothing refused.
                assert r["stored"] == 5 and r["refused"] == 0 and r["enqueue_failed"] == 0 and r["store_send_failed"] == 0, (mode, r)
                assert r["langfuse_send_failed"] == 5 and r["langfuse_sent"] == 0 and 0 <= peak < CAPACITY, (mode, r)
                if mode in ("403", "413"):
                    # Permanent: one attempt, dropped at once (the batch
                    # leaves within its 10 s flush timeout).
                    assert attempts == 1 and dropped_after < RETRY, (mode, r)
                else:
                    # Retryable: retried, then dropped at the limit.
                    assert dropped_after >= RETRY and (mode == "down" or attempts >= 2), (mode, r)

            sink_mode("ok")
            store.succeed("systemctl start langfuse-sink.service")
            nonce = f"lfback{time.time_ns()}"
            assert lf_post(nonce, omp_tools(nonce, 2)) == "200"
            wait_for(lambda: len(sink_spans(sink_records(nonce))) == 2, "Langfuse again after the failures", 120)
            wait_for(lambda: lf_stored(nonce) == 2, "the store again", 120)
            print(f"  langfuse isolation: {json.dumps(results)}", flush=True)
            print("ok: langfuse", flush=True)
          '';

          # The agent unit and the store's schema job in a switch (design
          # D15): switch-to-configuration starts each unit in a transaction
          # of its own, on magnetite (2026-11-22) the agent unit's 20 ms
          # before the job's, so After= alone ordered nothing. With the
          # unit wanting the job, the unit's start pulls the job's start in
          # and waits for it to end, the agent unit's queued first as on
          # magnetite; and a failed job leaves the unit starting anyway.
          schemaOrder = ''
            print("=== case schemaOrder", flush=True)
            fresh_start()


            def monotonic(unit, prop):
                return int(store.succeed(f"systemctl show -P {prop} {unit}.service").strip())


            store.succeed(f"systemctl stop {SESSION}.service greptimedb-schema.service")
            store.succeed(f"systemctl start --no-block {SESSION}.service", "systemctl start --no-block greptimedb-schema.service")
            store.wait_until_succeeds(f"systemctl is-active {SESSION}.service", timeout=300)
            store.wait_until_succeeds("systemctl is-active greptimedb-schema.service", timeout=300)
            finished = monotonic("greptimedb-schema", "ActiveEnterTimestampMonotonic")
            started = monotonic(SESSION, "ExecMainStartTimestampMonotonic")
            print(f"  schema job active at {finished} us, the agent unit's process started at {started} us", flush=True)
            assert 0 < finished <= started, ("the agent unit started before the schema job ended", finished, started)

            drop_in = "/run/systemd/system/greptimedb-schema.service.d/zz-fail.conf"
            store.succeed(f"mkdir -p {os.path.dirname(drop_in)}",
                          f"printf '[Service]\\nExecStart=\\nExecStart=/run/current-system/sw/bin/false\\n' > {drop_in}",
                          "systemctl daemon-reload",
                          f"systemctl stop {SESSION}.service greptimedb-schema.service")
            code, out = store.execute(f"systemctl start {SESSION}.service")
            print(f"  with the schema job failing: systemctl start {SESSION} exited {code} {out.strip()}", flush=True)
            assert code == 0, out
            store.succeed(f"systemctl is-active {SESSION}.service")
            assert store.execute("systemctl is-failed greptimedb-schema.service")[0] == 0, "the schema job did not fail"
            print("  a failed schema job: the agent unit started anyway", flush=True)
            store.succeed(f"rm {drop_in}", "systemctl daemon-reload", "systemctl reset-failed greptimedb-schema.service",
                          "systemctl start greptimedb-schema.service")
            print("ok: schemaOrder", flush=True)
          '';

          # The hand-off cap (design D15): one request of 240 omp tool
          # spans of 60 KiB, about 14.7 MB, past the ingress's 12 MiB
          # agent_span queue (darwin-agent-session-telemetry design D7),
          # which takes a request whole or not at all. The span exporter
          # splits it to a quarter of that queue, so the store gets every
          # span and the ingress refuses none.
          handoffCap = ''
            print("=== case handoffCap", flush=True)
            fresh_start()
            store.succeed(f"systemctl restart {SESSION}.service")
            wait_telemetry(SESSION_PORT)
            nonce = f"cap{time.time_ns()}"
            generator = "\n".join([
                "import json, os, sys, time",
                "nonce, now = sys.argv[1], time.time_ns()",
                "text = ('lorem ipsum ' * 5200)[:61440]",
                "def s(k, v): return {'key': k, 'value': {'stringValue': v}}",
                "spans = [{'traceId': os.urandom(16).hex(), 'spanId': os.urandom(8).hex(), 'name': 'execute_tool bash', 'kind': 1,",
                "          'startTimeUnixNano': str(now - 1000000), 'endTimeUnixNano': str(now),",
                "          'attributes': [s('gen_ai.operation.name', 'execute_tool'), s('gen_ai.conversation.id', nonce),",
                "                         s('gen_ai.tool.call.result', json.dumps({'content': [{'type': 'text', 'text': str(i) + ' ' + text}]}, separators=(',', ':')))]}",
                "         for i in range(240)]",
                "print(json.dumps({'resourceSpans': [{'resource': {'attributes': [s('service.name', 'oh-my-pi'), s('user.name', 'cameron')]}, 'scopeSpans': [{'spans': spans}]}]}))",
            ])
            store.succeed(f"python3 - {nonce} > /tmp/handoff.json <<'EOF'\n{generator}\nEOF")
            size = int(store.succeed("stat -c %s /tmp/handoff.json"))
            refused = {"refused": ("otelcol_receiver_refused_spans", {"receiver": "otlp/mesh"}),
                       "enqueue_failed": ("otelcol_exporter_enqueue_failed_spans", {"exporter": "otlp_http/agent_span"})}
            before = {k: metric(INGRESS_PORT, name, labels) for k, (name, labels) in refused.items()}
            status = store.succeed(
                "curl -sS -o /tmp/handoff-answer -w '%{http_code}' -H 'Content-Type: application/json' "
                "--data @/tmp/handoff.json http://127.0.0.1:4318/v1/traces"
            ).strip()
            print(f"  POST otlp/local /v1/traces, {size} bytes: {status}", flush=True)
            assert status == "200", status


            def stored():
                rows = gsql(f"SELECT count(*) FROM agent_span WHERE \"span_attributes.gen_ai.conversation.id\" = '{nonce}'", "agent")
                print(f"  {nonce}: {rows} of 240 stored", flush=True)
                return rows == [[240]]


            wait_for(stored, "the 240 spans in the store", 300)
            after = {k: metric(INGRESS_PORT, name, labels) for k, (name, labels) in refused.items()}
            print(f"  ingress, before and after: {before} {after}", flush=True)
            assert after == before, (before, after)
            print("ok: handoffCap", flush=True)
          '';

          # The cases that assert filtering, routing, refusal and the
          # absence of forbidden values: a medium run, for every change to
          # the collectors (declare-test-size-classes design D7).
          routingCases = [
            processName
            refusal
            delivery
            agentSession
            agentSpans
            schemaOrder
            handoffCap
            budget
          ];
          # The cases whose behaviour needs real time to occur (an outage
          # window, a filling queue, a crash loop, repeated runs, the
          # Langfuse exporter's retry and flush timers): an enormous run,
          # weekly or on demand after a run notice.
          outageCases = [
            langfuse
            backPressure
            lossControls
            crashLoop
            longRun
            absentClientCa
          ];

          # One container definition and one helper file; the two tests
          # differ only in their name and their cases.
          fleetIngress =
            name: cases:
            pkgs.testers.runNixOSTest {
              inherit name;
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
                  # python3 writes the handoffCap case's request.
                  environment.systemPackages = [
                    pkgs.curl
                    pkgs.python3
                  ];

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
                      # A Langfuse key pair of the right shape for this test
                      # only, generated at boot: the sink checks the collector's
                      # Basic credential against it, never against the real one.
                      printf 'pk-lf-test-%s' "$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')" > ${vars}/langfuse-public-key
                      printf 'sk-lf-test-%s' "$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')" > ${vars}/langfuse-secret-key
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

                  # pyrite's unit itself, its ceiling, GOMEMLIMIT and hardening,
                  # with the configuration above and the test certificate.
                  systemd.services.otel-agent-session = {
                    description = "pyrite's agent-session collector, exporting over mTLS to otlp/mesh";
                    wantedBy = [ "multi-user.target" ];
                    # magnetite's ordering: after the host's collector and the
                    # store's schema job, which it also wants (design D15).
                    inherit (reference.systemd.services.otel-agent-session) after wants;
                    startLimitIntervalSec = 0;
                    serviceConfig =
                      builtins.removeAttrs pyriteSessionUnit [
                        "ExecStartPost"
                        "ExecStopPost"
                      ]
                      // {
                        ExecStart = agentExecStart collector agentSessionSettings;
                        LoadCredential = [
                          "otel-cert:${pki}/agent.crt"
                          "otel-key:${pki}/agent.key"
                          "langfuse-public-key:${vars}/langfuse-public-key"
                          "langfuse-secret-key:${vars}/langfuse-secret-key"
                        ];
                      };
                  };

                  # Langfuse Cloud's stand-in (design D16), up from boot so that
                  # every case's spans reach it; the langfuse case stops it and
                  # sets its mode.
                  systemd.services.langfuse-sink = {
                    description = "Stand-in for Langfuse Cloud's OTLP endpoint";
                    wantedBy = [ "multi-user.target" ];
                    before = [ "otel-agent-session.service" ];
                    environment = {
                      SINK_DIR = sinkDir;
                      SINK_PORT = toString sinkPort;
                    };
                    serviceConfig = {
                      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${sinkDir}";
                      ExecStart = "${
                        pkgs.python3.withPackages (p: [
                          p.opentelemetry-proto
                          p.protobuf
                        ])
                      }/bin/python3 ${./fleet-ingress/langfuse_sink.py}";
                      Restart = "on-failure";
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
                    "fleet-ingress/nonce_scan.py".source = ./fleet-ingress/nonce_scan.py;
                    "fleet-ingress/config.json".text = builtins.toJSON {
                      inherit
                        vars
                        pki
                        agentDeployRecord
                        oldSpanTable
                        d15SpanTable
                        oldEventTable
                        sinkDir
                        sinkPort
                        langfuseTestRetry
                        ;
                      toolResultWithheld = self.lib.otelCollectorSchema.agentSession.spans.toolResult.withheld;
                      credentialPatternNames = builtins.attrNames self.lib.otelCollectorSchema.agentSession.credentialPatterns;
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
        in
        lib.optionalAttrs (system == "x86_64-linux") {
          fleet-ingress = fleetIngress "fleet-ingress" routingCases;
          fleet-ingress-outage = fleetIngress "fleet-ingress-outage" outageCases;
        };
    };
}
