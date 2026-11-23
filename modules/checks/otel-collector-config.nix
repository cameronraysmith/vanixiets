# R3.1 and R1.2 over magnetite's collector (design D11; tasks.md 4.4, 10.8, 10.9).
#
# R3.1 judges relations in magnetite's evaluated configuration that a
# plausible edit would break silently: every listener and scrape target on
# loopback except the ingress receivers, otlp/mesh on the address ZeroTier
# assigned to magnetite and otlp/mesh-tincr on magnetite's registry mesh
# address with otlp/mesh's TLS, the alias transform in the host pipeline, queue sizes against
# the assumed rate, the validation override's scope, the failure-notifier
# wiring against the failure path's policy, the limiter under the unit's
# ceiling and the collector's order after the schema job. It does not copy
# the module's literals; the process identity attributes, node_exporter's
# firewall, the unit cap and the owner aliases are agent assertions on every
# host (design D6). Since S2 it also judges the devloop logs routes: each
# devloop table's exporter queue, no logs pipeline exporting outside devloop
# and none taking an OTLP receiver but the two ingress receivers. R1.2 requires the exponential-histogram conversion
# while the store is below 1.3.0 (ADR-001). Since agent-session-telemetry
# design D14 it also reads magnetite's agent-session collector, a unit of
# its own: its clauses judge that unit's configuration and unit, its
# hand-off to the ingress's otlp/loopback, and that the host's collector
# runs no agent-session receiver or pipeline. Each mutant edits the
# evaluated input and must produce a non-empty failure list
# (modules/checks/omnigent-environment.nix pattern). The configuration files
# themselves are validated at build when magnetite's toplevel builds.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      magnetite = self.nixosConfigurations.magnetite.config;
      collector = magnetite.services.opentelemetry-collector;

      mib = n: n * 1024 * 1024;

      # The failure path's policy (design "Failure path"): every store unit,
      # every disk-share oneshot, every dev-loop unit (S2 design D11), the
      # collector and its envelope (S4 design D7), and the agent-session
      # collector and its envelope (agent-session-telemetry design D14)
      # notify, so a new unit of these kinds fails the check until it is
      # listed.
      notifiedByPolicy =
        name:
        lib.hasPrefix "greptimedb" name
        || lib.hasPrefix "zfs-set-" name
        || lib.hasPrefix "zfs-assert-" name
        || lib.hasPrefix "devloop-" name
        || name == "opentelemetry-collector"
        || name == "otel-envelope"
        || name == "otel-agent-session"
        || name == "otel-agent-session-envelope";

      isLoopback =
        s:
        builtins.match "(https?://)?(127\\.[0-9]+\\.[0-9]+\\.[0-9]+|\\[::1]|localhost)(:[0-9]+)?(/.*)?" s
        != null;

      # Every `endpoint` string anywhere under a component section; a store
      # path value such as a CA file is a derivation, not a section.
      collectEndpoints =
        value:
        if lib.isDerivation value then
          [ ]
        else if builtins.isAttrs value then
          lib.concatLists (
            lib.mapAttrsToList (
              name: inner:
              if name == "endpoint" && builtins.isString inner then [ inner ] else collectEndpoints inner
            ) value
          )
        else if builtins.isList value then
          lib.concatMap collectEndpoints value
        else
          [ ];

      # A notified unit's hook; with services.observability-notify.tokenFile
      # set it runs under `env NTFY_TOKEN_FILE=<path>`. The last capture is
      # the script.
      resolvedHook =
        mode:
        "-\\+(/nix/store/[a-z0-9]{32}-coreutils-[^/ ]+/bin/env NTFY_TOKEN_FILE=[^ ]+ )?(/nix/store/[a-z0-9]{32}-observability-notify-resolved) ${mode} %n";

      input = {
        settings = collector.settings;
        overrides = collector.validateConfigOverrides;
        collectorService = magnetite.systemd.services.opentelemetry-collector.serviceConfig;
        # The agent-session collector, a unit of its own (agent-session-
        # telemetry design D14).
        agentSettings = magnetite.vanixiets.otelCollector.agentSessionSettings;
        agentService = magnetite.systemd.services.otel-agent-session.serviceConfig;
        fqdn = self.lib.hosts.magnetite.fqdn;
        node = magnetite.services.prometheus.exporters.node;
        services = magnetite.systemd.services;
        notifyUnits = magnetite.services.observability-notify.units;
        schema = self.lib.otelCollectorSchema;
        hosts = self.lib.observabilityHosts;
        ztAddress = lib.trim (
          builtins.readFile "${self}/vars/shared/zerotier-ip-magnetite-zerotier/ip/value"
        );
        meshAddress = self.lib.hosts.magnetite.address;
        storeVersion = magnetite.services.greptimedb.package.version;
        # Both collector units run the host's collector package.
        collectorVersion = magnetite.services.opentelemetry-collector.package.version;
        storeTables = magnetite.services.greptimedb.tables;
        notifierInterval =
          magnetite.systemd.services."observability-notify@".environment.OBSERVABILITY_NOTIFY_MIN_INTERVAL_SEC
            or null;
      };

      # The notifier magnetite deploys, built from the same function the
      # rehearsal below runs.
      deployedNotify = self.lib.observabilityNotifyScripts self.nixosConfigurations.magnetite.pkgs {
        ntfySend = lib.getExe self.nixosConfigurations.magnetite.pkgs.ntfy-send;
        stampDir = "/var/lib/observability-notify";
        hostName = "magnetite";
      };

      # The notifier's scripts against a temporary stamp directory (`$TMPDIR`
      # expands when they run) and an ntfy-send that records each post.
      ntfyStub = pkgs.writeShellScript "ntfy-send-stub" ''
        printf '%s|%s\n' "$1" "$2" >> "$NTFY_STUB_LOG"
      '';
      rehearsedNotify = self.lib.observabilityNotifyScripts pkgs {
        ntfySend = "${ntfyStub}";
        stampDir = "$TMPDIR/notify";
        hostName = "rehearsal";
      };
      notifierRehearsal =
        pkgs.runCommand "observability-notify-rehearsal"
          {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.gnugrep
            ];
            meta.description = "behavioural check: a crash loop yields one FAILED/RESOLVED pair per interval and one failed.log line per posted FAILED";
          }
          ''
            set -euo pipefail
            export NTFY_STUB_LOG="$TMPDIR/posts" OBSERVABILITY_NOTIFY_MIN_INTERVAL_SEC=900
            # systemd gives services UMask 0022; 0077 here shows the script
            # sets failed.log's mode itself.
            umask 077
            unit=opentelemetry-collector.service
            failed="FAILED $unit on rehearsal|fleet-alerts"
            resolved="RESOLVED $unit on rehearsal|fleet-alerts"
            expect() {
              if [ "$(cat "$NTFY_STUB_LOG")" != "$2" ]; then
                echo "FAIL: $1; posts were:" >&2
                cat "$NTFY_STUB_LOG" >&2
                exit 1
              fi
              echo "ok: $1"
            }
            # expectLog DESCRIPTION COUNT: failed.log is mode 0644 and holds
            # exactly COUNT lines `<epoch> <unit> rehearsal`, each epoch within
            # this rehearsal.
            expectLog() {
              local log="$TMPDIR/notify/failed.log" lines epoch rest
              lines=$(grep -cE '^[0-9]+ '"$unit"' rehearsal$' "$log" 2>/dev/null || true)
              if [ ! -e "$log" ] || [ "$(wc -l < "$log")" != "$2" ] || [ "$lines" != "$2" ] || [ "$(stat -c %a "$log")" != 644 ]; then
                echo "FAIL: $1; failed.log was:" >&2
                ls -l "$log" >&2 || true
                cat "$log" >&2 || true
                exit 1
              fi
              while read -r epoch rest; do
                if [ "$epoch" -lt "$t0" ] || [ "$epoch" -gt "$(date +%s)" ]; then
                  echo "FAIL: $1; epoch $epoch is outside the rehearsal" >&2
                  exit 1
                fi
              done < "$log"
              echo "ok: $1"
            }
            # rehearse FAILED: the crash loop against a fresh stamp directory,
            # with FAILED as the notifier's failed script.
            rehearse() {
              local failedScript=$1
              rm -rf "$TMPDIR/notify"
              mkdir "$TMPDIR/notify"
              : > "$NTFY_STUB_LOG"
              t0=$(date +%s)
              # systemd's order for a crash with automatic restart: the stop
              # hook with a failed result, OnFailure's notifier, then the start.
              crash() { SERVICE_RESULT=exit-code ${rehearsedNotify.resolved} stop "$unit"; "$failedScript" "$unit"; }
              start() { ${rehearsedNotify.resolved} start "$unit"; }

              crash; start; crash; start
              expect "crash, start, crash, start within the interval posts one pair" "$failed"$'\n'"$resolved"
              expectLog "one posted FAILED and one suppressed episode log one line" 1

              mkdir -p "$TMPDIR/notify/last-failed"
              echo $(( $(date +%s) - 901 )) > "$TMPDIR/notify/last-failed/$unit"
              crash; "$failedScript" "$unit"; start
              SERVICE_RESULT=success ${rehearsedNotify.resolved} stop "$unit"
              expect "a crash after the interval posts a new pair, once" "$failed"$'\n'"$resolved"$'\n'"$failed"$'\n'"$resolved"
              expectLog "a second posted FAILED logs a second line, a repeated failure none" 2
            }
            # mutant NAME LINE: the failed script without its one line
            # containing LINE must fail the rehearsal.
            mutant() {
              local script="$TMPDIR/failed-$1"
              grep -vF "$2" ${rehearsedNotify.failed} > "$script"
              chmod +x "$script"
              if [ "$(wc -l < "$script")" -ne $(( $(wc -l < ${rehearsedNotify.failed}) - 1 )) ]; then
                echo "FAIL: mutant $1 did not remove exactly one line" >&2
                exit 1
              fi
              if (rehearse "$script"); then
                echo "FAIL: the rehearsal accepted mutant $1" >&2
                exit 1
              fi
              echo "ok: mutant $1 rejected"
            }

            rehearse ${rehearsedNotify.failed}
            mutant drop-append '>> "$log"'
            mutant drop-mode 'install -m 0644'
            touch "$out"
          '';

      failures =
        i:
        let
          s = i.settings;
          r = s.receivers;
          p = s.processors;
          e = s.exporters;
          pipelines = s.service.pipelines;
          # The agent-session collector's own configuration (design D14).
          a = i.agentSettings;
          ar = a.receivers or { };
          ap = a.processors or { };
          ae = a.exporters or { };
          agentPipelines = a.service.pipelines or { };
          # Langfuse Cloud (design D16): its exporter is the one endpoint of
          # the agent-session collector off loopback and outside the
          # hand-off, and traces/langfuse the one pipeline not on otlp/local;
          # the Langfuse clause below judges both.
          lfName = "otlp_http/langfuse";
          lf = i.schema.agentSession.langfuse;
          lfOn = i.hosts.magnetite.langfuse or false;
          lfx = ae.${lfName} or { };
          storeExporters = builtins.removeAttrs ae [ lfName ];
          storePipelines = builtins.removeAttrs agentPipelines [ "traces/langfuse" ];
          handoff = r."otlp/loopback".protocols.http or { };
          check = name: ok: lib.optional (!ok) name;
          dbs = lib.attrNames i.schema.databases;
          devloopTables = lib.attrNames i.schema.devloop.tables;
          exporterNames =
            map (db: "otlp_http/${db}") dbs
            ++ map (table: "otlp_http/devloop_${table}") devloopTables
            ++ [
              "otlp_http/agent_session_event"
              "otlp_http/agent_span"
            ];
          tracesPipelineNames = builtins.filter (lib.hasPrefix "traces") (builtins.attrNames pipelines);
          agentTracesPipelineNames = builtins.filter (lib.hasPrefix "traces") (
            builtins.attrNames agentPipelines
          );
          logsPipelineNames = builtins.filter (lib.hasPrefix "logs/") (builtins.attrNames pipelines);
          # A logs pipeline writes only into devloop or agent.session_event:
          # through the forward and routing connectors, a devloop table's
          # exporter whose database header is devloop, or the agent events
          # exporter whose headers name agent and session_event.
          # Not the metrics exporters otlp_http/devloop and otlp_http/agent,
          # which carry no table or pipeline header, so logs sent there would
          # skip the allow-list pipeline.
          exportsToDevloop =
            name:
            name == "forward"
            || name == "routing/logs"
            || (
              builtins.elem name (map (table: "otlp_http/devloop_${table}") devloopTables)
              && (e.${name}.headers."x-greptime-db-name" or null) == "devloop"
            )
            || (
              name == "otlp_http/agent_session_event"
              && (e.${name}.headers."x-greptime-db-name" or null) == "agent"
              && (e.${name}.headers."x-greptime-log-table-name" or null) == "session_event"
            );

          # The agent-session path (agent-session-telemetry design D3, D5,
          # D10), read back from the rendered OTTL and compared with
          # schema.nix's agentSession.
          session = i.schema.agentSession;
          sorted = lib.sort lib.lessThan;
          sameSet = a: b: sorted (lib.unique a) == sorted (lib.unique b);
          eventStatements = ap."transform/agent-session-events".log_statements or [ ];
          # The transforms' statement lists, whole: one keep_keys per listed
          # event, then the body, resource and scope statements. An added
          # statement (a `set` copying the body, say) fails like a changed one.
          keyList = keys: "[${lib.concatMapStringsSep ", " (key: ''"${key}"'') keys}]";
          expectedEventStatements =
            map (
              event:
              ''keep_keys(log.attributes, ${
                keyList (session.events.correlationKeys ++ session.events.keys.${event})
              }) where log.attributes["event.name"] == "${event}"''
            ) (builtins.attrNames session.events.keys)
            ++ map (
              key:
              ''delete_key(log.attributes, "${key}") where log.attributes["${key}"] != nil and not IsString(log.attributes["${key}"])''
            ) eventStringKeys
            ++ [
              ''set(log.body, "")''
              "truncate_all(log.attributes, 65536)"
              "keep_keys(resource.attributes, ${keyList session.events.resourceKeys})"
              "keep_keys(scope.attributes, [])"
            ];
          expectedMetricStatements = [
            "keep_keys(datapoint.attributes, ${keyList session.metrics.pointKeys})"
            "keep_keys(resource.attributes, ${keyList session.metrics.resourceKeys})"
            "keep_keys(scope.attributes, [])"
          ];
          # The span path's statements, whole (design D13, D15): the copy of
          # the newest user message, only on a step-0 chat span of a
          # top-level, non-oneshot run with native tools, found in the
          # attribute's last 64 KiB without parsing the history, then the
          # span allow-list.
          source = ''span.attributes["${session.spans.promptSource}"]'';
          expectedPromptStatements = [
            ''delete_key(span.attributes, "last_user_message")''
            ''set(span.cache["g"], true) where IsMatch(span.name, "^chat ") and span.attributes["omp.gen_ai.agent.step.number"] == 0 and span.attributes["gen_ai.agent.id"] == nil and span.attributes["omp.gen_ai.oneshot.kind"] == nil and span.attributes["omp.gen_ai.request.available_tools"] != nil''
            ''set(span.cache["t"], ${source}) where span.cache["g"] == true and ${source} != nil and Len(${source}) <= 65536''
            ''set(span.cache["t"], Substring(${source}, Len(${source}) - 65536, 65536)) where span.cache["g"] == true and ${source} != nil and Len(${source}) > 65536''
            # The last text part of the newest user message, the reminder
            # stripped from a single text part's head (design D15, A201).
            ''set(span.cache["x"], ExtractPatterns(span.cache["t"], "\\{\\s*\"role\"\\s*:\\s*\"user\"\\s*,\\s*\"parts\"\\s*:\\s*\\[\\s*(?:\\{\\s*\"type\"\\s*:\\s*\"text\"\\s*,\\s*\"content\"\\s*:\\s*\"(?:[^\"\\\\]|\\\\.)*\"\\s*\\}\\s*,\\s*)*\\{\\s*\"type\"\\s*:\\s*\"text\"\\s*,\\s*\"content\"\\s*:\\s*\"(?P<c>(?:[^\"\\\\]|\\\\.)*)\"\\s*\\}(?:\\s*,\\s*\\{[^\\[\\]]*\\})*\\s*\\]\\s*\\}\\s*\\]\\s*$")) where span.cache["t"] != nil''
            ''set(span.cache["p"], ParseJSON(Concat(["[\"", span.cache["x"]["c"], "\"]"], ""))) where span.cache["x"]["c"] != nil''
            ''set(span.attributes["last_user_message"], span.cache["p"][0]) where span.cache["p"] != nil''
            ''replace_pattern(span.attributes["last_user_message"], "^<system-reminder>[\\s\\S]*?</system-reminder>\\s*", "")''
          ];
          # A string-typed key holding an array or a map is deleted: the cut
          # and the masks act on strings only.
          spanStringKeys = builtins.attrNames (
            lib.filterAttrs (_: type: type == "string") session.spans.keys
          );
          eventStringKeys = map (column: column.source.log) (
            builtins.filter (
              column: column.type == "string" && (column.source.log or null) != null
            ) session.tables.session_event.columns
          );
          expectedSpanStatements = [
            "keep_keys(span.attributes, ${keyList (builtins.attrNames session.spans.keys)})"
          ]
          ++ map (
            key:
            ''delete_key(span.attributes, "${key}") where span.attributes["${key}"] != nil and not IsString(span.attributes["${key}"])''
          ) spanStringKeys
          ++ [
            "truncate_all(span.attributes, 65536)"
            ''set(span.cache["status"], span.status.message)''
            "truncate_all(span.cache, 65536)"
            ''set(span.status.message, span.cache["status"])''
            "keep_keys(resource.attributes, ${keyList session.spans.resourceKeys})"
            "keep_keys(scope.attributes, [])"
          ];
          # Claude's tool output, copied from its `tool.output` event onto
          # the span before every event is dropped (design D15).
          expectedToolOutputStatements = map (
            attribute:
            ''set(span.attributes["${session.spans.toolOutput.key}"], spanevent.attributes["${attribute}"]) where spanevent.name == "${session.spans.toolOutput.event}" and spanevent.attributes["${attribute}"] != nil''
          ) session.spans.toolOutput.attributes;
          # Every one of schema.nix's credential shapes, then its encoded
          # blob net, in every kept string of events and spans and in the
          # status message.
          ottlString = s: ''"${lib.escape [ "\\" "\"" ] s}"'';
          credentials = ottlString (
            lib.concatMapStringsSep "|" (pattern: "(?:${pattern})") (
              builtins.attrValues session.credentialPatterns
            )
          );
          blob = ottlString session.encodedBlobPattern;
          expectedMask = {
            log_statements = [
              ''replace_all_patterns(log.attributes, "value", ${credentials}, "****")''
              ''replace_all_patterns(log.attributes, "value", ${blob}, "****")''
            ];
            trace_statements = [
              ''replace_all_patterns(span.attributes, "value", ${credentials}, "****")''
              ''replace_all_patterns(span.attributes, "value", ${blob}, "****")''
              ''replace_pattern(span.status.message, ${credentials}, "****")''
              ''replace_pattern(span.status.message, ${blob}, "****")''
            ];
          };
          # The shapes by name: a set emptied or thinned in schema.nix
          # renders a mask the statement comparison above would accept.
          credentialPatternNames = [
            "age-secret-key"
            "anthropic"
            "aws-access-key-id"
            "bearer"
            "digitalocean"
            "gcp-api-key"
            "github"
            "gitlab"
            "jwt"
            "langfuse"
            "linear"
            "npm"
            "openai"
            "private-key"
            "pypi"
            "slack"
            "stripe"
          ];
          # omp's tool results stripped of `details` on its spans only,
          # then withheld whole if a `details` key is left (design D15).
          toolResult = session.spans.toolResult;
          resultKey = ''span.attributes["${session.spans.toolOutput.key}"]'';
          ompOnly = ''resource.attributes["service.name"] == "${toolResult.service}"'';
          expectedToolResultStatements = [
            ''replace_pattern(${resultKey}, ${ottlString toolResult.strip}, "]$$1}") where ${ompOnly}''
            "set(${resultKey}, ${ottlString toolResult.withheld}) where ${ompOnly} and IsMatch(${resultKey}, ${ottlString toolResult.detailsKey})"
          ];
          # agent.agent_span's CREATE TABLE as the schema job runs it, and
          # the attribute keys its columns are named after.
          spanTable =
            lib.findFirst (lib.hasInfix ''CREATE TABLE IF NOT EXISTS "${session.spans.table}" ('') null
              (i.storeTables.agent or [ ]);
          columnKeys =
            prefix:
            lib.concatMap (part: if builtins.isList part then part else [ ]) (
              builtins.split ''"${lib.escapeRegex prefix}[.]([^"]+)"'' (
                if spanTable == null then "" else spanTable
              )
            );
          spanTableColumns = {
            span = columnKeys "span_attributes";
            resource = columnKeys "resource_attributes";
          };
          # The schema job's statements that bring an existing agent_span
          # to the same columns and indexes (design D15), after its CREATE.
          spanTableIndex = lib.lists.findFirstIndex (s: s == spanTable) null (i.storeTables.agent or [ ]);
          spanAlterKeys =
            pattern:
            lib.concatMap
              (
                statement:
                let
                  matched = builtins.match ''ALTER TABLE "${session.spans.table}" ${pattern}'' statement;
                in
                if matched == null then [ ] else matched
              )
              (lib.drop (if spanTableIndex == null then 0 else spanTableIndex + 1) (i.storeTables.agent or [ ]));
          spanAlters = {
            added = spanAlterKeys ''ADD COLUMN IF NOT EXISTS "span_attributes[.]([^"]+)" [A-Z]+ NULL'';
            indexed = spanAlterKeys ''MODIFY COLUMN "span_attributes[.]([^"]+)" SET FULLTEXT INDEX WITH[(].*[)]'';
          };
          # The values a filter's conditions compare with.
          conditionValues =
            conditions:
            lib.concatMap (
              condition:
              lib.concatMap (part: if builtins.isList part then part else [ ]) (
                builtins.split ''== "([^"]*)"'' condition
              )
            ) conditions;
          metricStatements = ap."transform/agent-session-metrics".metric_statements or [ ];
          localPipelines = builtins.filter (
            name: builtins.elem "otlp/local" (agentPipelines.${name}.receivers or [ ])
          ) (builtins.attrNames agentPipelines);
          goMemLimit =
            service:
            builtins.match "GOMEMLIMIT=([0-9]+)MiB" (
              lib.findFirst (lib.hasPrefix "GOMEMLIMIT=") "" (lib.toList (service.Environment or [ ]))
            );
          agentMemoryMax = builtins.match "([0-9]+)M" (i.agentService.MemoryMax or "");
          agentTelemetryHosts = builtins.length (
            builtins.attrNames (lib.filterAttrs (_: h: h.agentTelemetry or false) i.hosts)
          );
          agentRoute = builtins.filter (
            route:
            route.condition or null
            == ''attributes["vanixiets.database"] == "agent" and attributes["vanixiets.table"] == "session_event"''
          ) (s.connectors."routing/logs".table or [ ]);
          sharedPromote = lib.concatStringsSep ";" i.schema.promotedResourceAttributes;
          # The OTLP receiver's component type is `otlp`
          # (open-telemetry/opentelemetry-collector@v0.155.0:
          # receiver/otlpreceiver/internal/metadata/generated_status.go:12);
          # an instance is `otlp` or `otlp/<name>`.
          isOtlpReceiver = name: name == "otlp" || lib.hasPrefix "otlp/" name;
          collectorMemoryMax = builtins.match "([0-9]+)M" (i.collectorService.MemoryMax or "");
          promTargets = lib.concatMap (
            name:
            lib.concatMap (
              job: lib.concatMap (sc: sc.targets) job.static_configs
            ) r.${name}.config.scrape_configs
          ) (builtins.filter (lib.hasPrefix "prometheus") (builtins.attrNames r));
          queueSizes = map (n: e.${n}.sending_queue.queue_size or 0) exporterNames;
          hostUnits = builtins.attrNames i.services;
          zerotierJobs = map (job: builtins.removeAttrs job [ "authorization" ]) (
            r."prometheus/zerotier".config.scrape_configs or [ ]
          );
          overrideParts = map (builtins.match "([^=]*)=(.*)") i.overrides;
          unitWired =
            name:
            let
              u =
                i.services.${name} or {
                  unitConfig = { };
                  serviceConfig = { };
                };
            in
            (u.unitConfig.OnFailure or null) == [ "observability-notify@%n.service" ]
            && lib.any (hook: builtins.match (resolvedHook "stop") hook != null) (
              lib.toList (u.serviceConfig.ExecStopPost or [ ])
            );
          hookScripts =
            mode: hooks:
            lib.unique (
              lib.concatMap (
                hook:
                let
                  m = builtins.match (resolvedHook mode) hook;
                in
                lib.optional (m != null) (lib.last m)
              ) (lib.toList hooks)
            );
          # One script removes the one stamp, and systemd runs ExecStartPost
          # before ExecStopPost, so a oneshot's stop hook finds no stamp after
          # its start hook resolved and never posts RESOLVED a second time.
          startResolves =
            name:
            let
              u = i.services.${name} or { serviceConfig = { }; };
              start = hookScripts "start" (u.serviceConfig.ExecStartPost or [ ]);
            in
            start != [ ] && start == hookScripts "stop" (u.serviceConfig.ExecStopPost or [ ]);
          notifier = i.services."observability-notify@".serviceConfig.ExecStart or "";
          exphist = p."transform/exphist".metric_statements or [ ];
        in
        lib.concatLists [
          # Loopback, with exactly two exceptions: otlp/mesh on the address
          # ZeroTier assigned to magnetite (ADR-003 item 9), removed at
          # ZeroTier's retirement, and otlp/mesh-tincr on magnetite's mesh
          # address with the same TLS. The agent-session collector's
          # receiver and exporters count too (design D14).
          (check
            "R3.1: an endpoint off loopback other than the ingress receivers, or an ingress receiver not on magnetite's address or without otlp/mesh's TLS"
            (
              lib.all isLoopback (
                collectEndpoints (
                  builtins.removeAttrs r [
                    "otlp/mesh"
                    "otlp/mesh-tincr"
                  ]
                )
                ++ collectEndpoints e
                ++ collectEndpoints ar
                ++ collectEndpoints storeExporters
                ++ promTargets
                ++ [ i.node.listenAddress ]
              )
              && (r."otlp/mesh".protocols.http.endpoint or null) == "[${i.ztAddress}]:4318"
              && !(r."otlp/mesh".protocols ? grpc)
              && (r."otlp/mesh-tincr".protocols.http.endpoint or null) == "[${i.meshAddress}]:4318"
              && !(r."otlp/mesh-tincr".protocols ? grpc)
              && (r."otlp/mesh".protocols.http.tls.client_ca_file or null) != null
              && (r."otlp/mesh-tincr".protocols.http.tls or null) == r."otlp/mesh".protocols.http.tls
            )
          )
          # The Langfuse counters (darwin-agent-session-telemetry design D9):
          # where langfuse is set, one job reads the agent-session
          # collector's telemetry and keeps Langfuse's sent and failed span
          # counters alone, without the instance id; elsewhere none.
          (check
            "R3.1: the otelcol-agent-session scrape job is missing where langfuse is set or present where it is not, or keeps more than the Langfuse exporter's sent and failed span counters"
            (
              let
                jobs = builtins.filter (job: job.job_name == "otelcol-agent-session") (
                  r.prometheus.config.scrape_configs or [ ]
                );
              in
              if !lfOn then
                jobs == [ ]
              else
                builtins.length jobs == 1
                && (builtins.head jobs).static_configs == [ { targets = [ "127.0.0.1:8890" ]; } ]
                &&
                  (builtins.head jobs).metric_relabel_configs == [
                    {
                      source_labels = [ "__name__" ];
                      regex = "otelcol_exporter_sent_spans|otelcol_exporter_send_failed_spans";
                      action = "keep";
                    }
                    {
                      source_labels = [ "exporter" ];
                      regex = "otlp_http/langfuse";
                      action = "keep";
                    }
                    {
                      regex = "service_instance_id";
                      action = "labeldrop";
                    }
                  ]
            )
          )
          # The hand-off (design D14): the agent-session collector exports
          # only to otlp/loopback, which takes HTTP only, requires otlp/mesh's
          # client certificate, so no local account writes past otlp/local's
          # allow-lists, and feeds exactly the three ingress pipelines; each
          # exporter verifies the ingress against the CA and the name its
          # certificate carries.
          (check
            "R3.1: the agent-session collector does not hand off over mTLS to otlp/loopback, an HTTP-only receiver with otlp/mesh's TLS feeding the ingress pipelines"
            (
              handoff ? endpoint
              && isLoopback handoff.endpoint
              && !(r."otlp/loopback".protocols ? grpc)
              && (handoff.tls or null) == r."otlp/mesh".protocols.http.tls
              &&
                sorted (
                  builtins.filter (n: builtins.elem "otlp/loopback" (pipelines.${n}.receivers or [ ])) (
                    builtins.attrNames pipelines
                  )
                ) == [
                  "logs/ingress"
                  "metrics/ingress"
                  "traces/ingress"
                ]
              && storeExporters != { }
              && lib.all (
                x:
                (x.endpoint or null) == "https://${handoff.endpoint}"
                && (x.tls.ca_file or null) == handoff.tls.client_ca_file
                && (x.tls.server_name_override or null) == i.fqdn
                && (x.sending_queue.num_consumers or null) == 1
              ) (builtins.attrValues storeExporters)
            )
          )

          # Bounds (host-metrics-collection "Series cardinality stays bounded").
          (check "R3.1: the 64 MiB floor is not in the process pipeline" (
            builtins.elem "filter/process-min" pipelines."metrics/process".processors
          ))
          (check "R3.1: the alias transform is not in the host pipeline" (
            builtins.elem "transform/omnigent-alias" pipelines."metrics/host".processors
          ))
          # F64: a process that rewrites its title named by its command line.
          (check
            "R3.1: the process-name transform does not cut the name at its first space before resource/agent"
            (
              let
                processors = pipelines."metrics/process".processors;
                at = name: lib.lists.findFirstIndex (n: n == name) null processors;
              in
              (p."transform/process-name".metric_statements or [ ]) == [
                ''replace_pattern(resource.attributes["process.executable.name"], "^([^ ]{15,}) .*$", "$$1")''
              ]
              && at "transform/process-name" != null
              && at "resource/agent" != null
              && at "transform/process-name" < at "resource/agent"
            )
          )

          # Content: the logs pipelines write only into devloop and
          # agent.session_event (S2 design D4; agent-session-telemetry design
          # D3; S7 adds journald logs behind ADR-008's stages).
          (check "R3.1: a logs pipeline exporting outside devloop and agent.session_event" (
            lib.all (name: lib.all exportsToDevloop pipelines.${name}.exporters) logsPipelineNames
          ))
          # Content: exactly two traces pipelines (agent-session-telemetry
          # design D13, D14), the agent-session collector's on otlp/local
          # into its traces exporter and the ingress's into
          # otlp_http/agent_span, which writes agent.agent_span through
          # greptime_trace_v1 without creating tables or columns; the table's
          # attribute columns are exactly agentSession.spans' keys, so what
          # the host keeps and what the store accepts agree.
          (check
            "R3.1: a traces pipeline other than the agent-session collector's traces/agent-session into otlp_http/ingress-traces and the ingress's traces/ingress, or a span route not into agent.agent_span's declared columns through greptime_trace_v1 with auto_create_table=false, or a span column or index the schema job does not also add to an existing table"
            (
              tracesPipelineNames == [ "traces/ingress" ]
              &&
                sorted agentTracesPipelineNames
                == sorted ([ "traces/agent-session" ] ++ lib.optional lfOn "traces/langfuse")
              &&
                (agentPipelines."traces/agent-session".exporters or null)
                == [ "otlp_http/ingress-traces" ] ++ lib.optional lfOn "forward/langfuse"
              &&
                sorted (pipelines."traces/ingress".receivers or [ ]) == [
                  "otlp/loopback"
                  "otlp/mesh"
                  "otlp/mesh-tincr"
                ]
              &&
                (pipelines."traces/ingress".processors or null) == [
                  "memory_limiter"
                  "filter/agent-spans-only"
                  "resource/strip-database"
                ]
              &&
                (p."filter/agent-spans-only".trace_conditions or null) == [
                  ''not (resource.attributes["vanixiets.database"] == "agent")''
                ]
              && (pipelines."traces/ingress".exporters or null) == [ "otlp_http/agent_span" ]
              && (e."otlp_http/agent_span".endpoint or null) == "http://127.0.0.1:4000/v1/otlp"
              &&
                (e."otlp_http/agent_span".headers or null) == {
                  "x-greptime-db-name" = "agent";
                  "x-greptime-trace-table-name" = session.spans.table;
                  "x-greptime-pipeline-name" = "greptime_trace_v1";
                  "x-greptime-hints" = "auto_create_table=false";
                }
              && spanTable != null
              && sorted spanTableColumns.span == sorted (builtins.attrNames session.spans.keys)
              && sorted spanAlters.added == sorted (builtins.attrNames session.spans.keys)
              && sorted spanAlters.indexed == sorted session.spans.fulltext
              &&
                sorted spanTableColumns.resource
                == sorted (lib.remove "service.name" session.spans.resourceKeys ++ [ "host.name" ])
              && lib.hasInfix "table_data_model = 'greptime_trace_v1'" spanTable
            )
          )
          # otlpInLogsPipeline: no OTLP receiver but the agents' ingress
          # receivers and the agent-session hand-off feeds a logs pipeline of
          # the host's collector (ADR-003:81; S2 design D4; design D3, D14),
          # and in the agent-session collector only otlp/local feeds
          # logs/agent-session.
          (check
            "R3.1: a logs pipeline takes an OTLP receiver other than the ingress receivers, or the agent-session collector's other than logs/agent-session's otlp/local"
            (
              lib.all (
                name:
                !(lib.any (
                  n:
                  isOtlpReceiver n
                  && !(builtins.elem n [
                    "otlp/mesh"
                    "otlp/mesh-tincr"
                    "otlp/loopback"
                  ])
                ) pipelines.${name}.receivers)
              ) logsPipelineNames
              &&
                lib.mapAttrs (_: pipeline: pipeline.receivers) (
                  lib.filterAttrs (name: _: lib.hasPrefix "logs" name) agentPipelines
                ) == {
                  "logs/agent-session" = [ "otlp/local" ];
                }
            )
          )

          # The agent-session path (agent-session-telemetry design D3, D5,
          # D14): the agent-session collector receives on otlp/local alone.
          (check
            "R3.1: otlp/local is not the agent-session collector's only receiver, HTTP-only on 127.0.0.1:4318, feeding exactly its three agent-session pipelines"
            (
              builtins.attrNames ar == [ "otlp/local" ]
              && (ar."otlp/local".protocols.http.endpoint or null) == "127.0.0.1:4318"
              && !(ar."otlp/local".protocols ? grpc)
              &&
                sorted localPipelines == [
                  "logs/agent-session"
                  "metrics/agent-session"
                  "traces/agent-session"
                ]
              && sorted (builtins.attrNames storePipelines) == sorted localPipelines
            )
          )
          # Isolation (design D14): the host's collector runs none of it, so
          # agent traffic can cost only agent telemetry.
          (check
            "R3.1: the host's collector has an otlp/local receiver, a receiver on its address, or an agent-session pipeline"
            (
              !(r ? "otlp/local")
              && !(builtins.elem (ar."otlp/local".protocols.http.endpoint or null) (collectEndpoints r))
              && !(lib.any (pipeline: builtins.elem "otlp/local" (pipeline.receivers or [ ])) (
                builtins.attrValues pipelines
              ))
              && !(lib.any (lib.hasSuffix "/agent-session") (builtins.attrNames pipelines))
            )
          )
          # The agent-session collector fails alone (design D14): its own
          # queue directory, its telemetry on loopback, restarted always,
          # and no dependency that would stop or start the host's collector
          # with it, either way.
          (check
            "R3.1: the agent-session collector shares the host collector's queue directory, serves telemetry off loopback, does not always restart, is bound to the host's collector, or may start before the store's schema job"
            (
              let
                own = a.extensions.file_storage.directory or "";
                shared = s.extensions.file_storage.directory or "";
                deps =
                  u:
                  lib.concatMap (k: u.${k} or [ ]) [
                    "requires"
                    "requisite"
                    "bindsTo"
                    "partOf"
                  ];
                readers = a.service.telemetry.metrics.readers or [ ];
              in
              own != ""
              && !(lib.hasPrefix shared own)
              && !(lib.hasPrefix own shared)
              && readers != [ ]
              && lib.all (reader: isLoopback (reader.pull.exporter.prometheus.host or "")) readers
              && (i.agentService.Restart or null) == "always"
              && !(builtins.elem "opentelemetry-collector.service" (deps (i.services.otel-agent-session or { })))
              && !(builtins.elem "otel-agent-session.service" (deps i.services.opentelemetry-collector))
              # On the store's host the columns for new span keys exist
              # before the unit sends them (design D15): ordered after the
              # schema job and pulling it into its own start, which a switch
              # runs as a transaction of its own.
              && builtins.elem "greptimedb-schema.service" (i.services.otel-agent-session.after or [ ])
              && builtins.elem "greptimedb-schema.service" (i.services.otel-agent-session.wants or [ ])
            )
          )
          (check
            "R3.1: an agent-session pipeline's stages are not the filters and transforms before the stamping"
            (
              (agentPipelines."metrics/agent-session".processors or null) == [
                "memory_limiter"
                "filter/agent-session-service"
                "filter/agent-session-metrics"
                "transform/agent-session-metrics"
                "resource/agent-session"
              ]
              &&
                (agentPipelines."logs/agent-session".processors or null) == [
                  "memory_limiter"
                  "filter/agent-session-service"
                  "filter/agent-session-events"
                  "transform/agent-session-events"
                  "transform/agent-session-mask"
                  "resource/agent-session-events"
                ]
              &&
                (agentPipelines."traces/agent-session".processors or null) == [
                  "memory_limiter"
                  "filter/agent-session-service"
                  "transform/agent-session-span-links"
                  "filter/agent-session-span-links"
                  "transform/agent-session-prompt"
                  "transform/agent-session-tool-output"
                  "filter/agent-session-span-events"
                  "transform/agent-session-tool-result"
                  "transform/agent-session-spans"
                  "transform/agent-session-mask"
                  "resource/agent-session"
                ]
              && lib.all (n: (ap.${n}.error_mode or null) == "propagate") [
                "filter/agent-session-service"
                "filter/agent-session-metrics"
                "filter/agent-session-events"
                "filter/agent-session-span-events"
                "filter/agent-session-span-links"
                "transform/agent-session-metrics"
                "transform/agent-session-events"
                "transform/agent-session-span-links"
                "transform/agent-session-tool-output"
                "transform/agent-session-tool-result"
                "transform/agent-session-spans"
                "transform/agent-session-mask"
              ]
              # The prompt copy alone ignores its errors: what it could not
              # read, transform/agent-session-spans drops next.
              && (ap."transform/agent-session-prompt".error_mode or null) == "ignore"
            )
          )
          # Langfuse Cloud (design D16): where observabilityHosts sets
          # langfuse, and only there, traces/agent-session's spans, after its
          # last stage, fan out through forward/langfuse to traces/langfuse
          # alone, whose stages ignore their errors and include no limiter,
          # so the branch cannot refuse what the store path took.
          (check
            "R3.1: traces/langfuse exists where observabilityHosts does not set langfuse or is missing where it does, or is not fed by forward/langfuse from traces/agent-session alone, after all its stages, through stages that cannot refuse, or sends the fleet's routing attributes, host.name, service.version, tool_use_id, duration_ms, a copied full_command or file_path, omp's startup requests or the oneshot kind"
            (
              (agentPipelines ? "traces/langfuse") == lfOn
              && (ae ? ${lfName}) == lfOn
              && (
                !lfOn
                || (
                  let
                    lp = agentPipelines."traces/langfuse";
                    feeding = builtins.filter (
                      n: builtins.elem "forward/langfuse" (agentPipelines.${n}.exporters or [ ])
                    ) (builtins.attrNames agentPipelines);
                    fed = builtins.filter (n: builtins.elem "forward/langfuse" (agentPipelines.${n}.receivers or [ ])) (
                      builtins.attrNames agentPipelines
                    );
                  in
                  feeding == [ "traces/agent-session" ]
                  && fed == [ "traces/langfuse" ]
                  && (lp.receivers or null) == [ "forward/langfuse" ]
                  && (lp.exporters or null) == [ lfName ]
                  && (a.connectors."forward/langfuse" or null) == { }
                  && !(builtins.elem "memory_limiter" (lp.processors or [ ]))
                  && lib.all (
                    n:
                    (ap.${n}.error_mode or null) == "ignore"
                    && !(lib.hasPrefix "filter/agent-session" n || lib.hasPrefix "transform/agent-session" n)
                  ) (lp.processors or [ ])
                  &&
                    (ap."filter/langfuse".trace_conditions or null) == [
                      (lib.concatMapStringsSep " or " (n: ''span.name == "${n}"'') lf.droppedSpans)
                      (lib.concatMapStringsSep " or " (
                        k: ''span.attributes["omp.gen_ai.oneshot.kind"] == "${k}"''
                      ) lf.droppedOneshotKinds)
                    ]
                  &&
                    lf.droppedOneshotKinds == [
                      "skill_description"
                      "mcp_namespace_hint"
                    ]
                  && lib.all (s: builtins.elem s (ap."transform/langfuse".trace_statements or [ ])) [
                    ''delete_key(span.attributes, "full_command") where span.attributes["full_command"] == span.attributes["langfuse.observation.input"]''
                    ''delete_key(span.attributes, "file_path") where span.attributes["file_path"] == span.attributes["langfuse.observation.input"]''
                    ''delete_key(span.attributes, "tool_use_id")''
                    ''delete_key(span.attributes, "duration_ms")''
                    ''delete_key(span.attributes, "omp.gen_ai.oneshot.kind")''
                    ''delete_key(resource.attributes, "host.name")''
                    ''delete_key(resource.attributes, "service.version")''
                    ''delete_matching_keys(resource.attributes, "^vanixiets\\.")''
                  ]
                )
              )
            )
          )
          (check
            "R3.1: Langfuse's exporter does not send to schema.nix's endpoint, https://cloud.langfuse.com/api/public/otel, with verified TLS, no proxy and a 30 s timeout, with the unit's Langfuse credentials and ingestion version, retry for retryMinutes and no longer, drain faster than spans arrive into a queue of twice a retry window, in batches under the request limit, or a store exporter of the agent-session collector does not retry forever, or its queues reach 512 MiB"
            (
              let
                queue = lfx.sending_queue or { };
                batch = queue.batch or { };
                arrivals = lf.retryMinutes * i.schema.agentSpanBytesPerMinute;
                auth = a.extensions."basicauth/langfuse".client_auth or { };
                credentials = lib.toList (i.agentService.LoadCredential or [ ]);
                loads = name: lib.any (lib.hasPrefix "langfuse-${name}:") credentials;
              in
              lib.all (x: (x.retry_on_failure.max_elapsed_time or null) == "0s") (
                builtins.attrValues storeExporters
              )
              && lib.foldl' (s: x: s + (x.sending_queue.queue_size or 0)) 0 (builtins.attrValues ae) < mib 512
              && (
                !lfOn
                || (
                  (lfx.endpoint or null) == lf.endpoint
                  && lf.endpoint == "https://cloud.langfuse.com/api/public/otel"
                  && !(lfx ? tls)
                  && !(lfx ? proxy_url)
                  && (lfx.timeout or null) == lf.timeout
                  && lf.timeout == "30s"
                  && (lfx.headers or null) == { "x-langfuse-ingestion-version" = lf.ingestionVersion; }
                  && (lfx.auth.authenticator or null) == "basicauth/langfuse"
                  && builtins.elem "basicauth/langfuse" (a.service.extensions or [ ])
                  && (auth.username_file or null) == "/run/credentials/otel-agent-session.service/langfuse-public-key"
                  && (auth.password_file or null) == "/run/credentials/otel-agent-session.service/langfuse-secret-key"
                  && !(auth ? password)
                  && loads "public-key"
                  && loads "secret-key"
                  && (lfx.retry_on_failure.enabled or false)
                  && lf.retryMinutes > 0
                  && (lfx.retry_on_failure.max_elapsed_time or null) == "${toString lf.retryMinutes}m"
                  && (queue.storage or null) == "file_storage"
                  && (queue.sizer or null) == "bytes"
                  && !(queue.block_on_overflow or false)
                  && (queue.queue_size or 0) >= 2 * arrivals
                  && (queue.num_consumers or 0) * (batch.max_size or 0) >= lf.drainMultiple * arrivals
                  && (batch.sizer or null) == "bytes"
                  && (batch.min_size or null) == (batch.max_size or 0)
                  && (batch.max_size or lf.requestLimitBytes) < lf.requestLimitBytes
                )
              )
            )
          )
          (check
            "R3.1: an agent-session filter or transform keeps a service, metric, event or key off schema.nix's agentSession, or the body, or does not cut, copy or mask as schema.nix's agentSession says"
            (
              sameSet (conditionValues (
                ap."filter/agent-session-service".metric_conditions or [ ]
              )) session.metrics.services
              && sameSet (conditionValues (
                ap."filter/agent-session-service".log_conditions or [ ]
              )) session.events.services
              && sameSet (conditionValues (
                ap."filter/agent-session-metrics".metric_conditions or [ ]
              )) session.metrics.names
              && sameSet (conditionValues (ap."filter/agent-session-events".log_conditions or [ ])) (
                builtins.attrNames session.events.keys
              )
              && sameSet (conditionValues (
                ap."filter/agent-session-service".trace_conditions or [ ]
              )) session.spans.services
              && lib.all (condition: lib.hasPrefix "not (" condition) (
                ap."filter/agent-session-service".metric_conditions or [ ]
                ++ ap."filter/agent-session-service".log_conditions or [ ]
                ++ ap."filter/agent-session-service".trace_conditions or [ ]
                ++ ap."filter/agent-session-metrics".metric_conditions or [ ]
                ++ ap."filter/agent-session-events".log_conditions or [ ]
              )
              && eventStatements == expectedEventStatements
              && metricStatements == expectedMetricStatements
              && (ap."transform/agent-session-spans".trace_statements or null) == expectedSpanStatements
              && (ap."transform/agent-session-prompt".trace_statements or null) == expectedPromptStatements
              &&
                (ap."transform/agent-session-tool-output".trace_statements or null) == expectedToolOutputStatements
              &&
                (ap."transform/agent-session-span-links".trace_statements or null)
                == [ "set(span.links, span.links)" ]
              && builtins.removeAttrs (ap."transform/agent-session-mask" or { }) [ "error_mode" ] == expectedMask
              && sorted (builtins.attrNames session.credentialPatterns) == credentialPatternNames
              &&
                builtins.removeAttrs (ap."transform/agent-session-tool-result" or { }) [ "error_mode" ] == {
                  trace_statements = expectedToolResultStatements;
                }
              &&
                (ap."filter/agent-session-span-events".trace_conditions or null) == [
                  ''spanevent.name != "" or spanevent.name == ""''
                ]
              && (ap."filter/agent-session-span-links".trace_conditions or null) == [ "Len(span.links) > 0" ]
            )
          )
          (check
            "R3.1: agent events are not routed through routing/logs to otlp_http/agent_session_event with its four headers"
            (
              map (route: route.pipelines) agentRoute == [ [ "logs/agent-session_event-out" ] ]
              &&
                (pipelines."logs/agent-session_event-out".exporters or null) == [ "otlp_http/agent_session_event" ]
              &&
                (e."otlp_http/agent_session_event".headers or null) == {
                  "x-greptime-db-name" = "agent";
                  "x-greptime-log-table-name" = "session_event";
                  "x-greptime-pipeline-name" = "agent_session_event";
                  "x-greptime-hints" = "auto_create_table=false";
                }
            )
          )
          # Every database's exporter promotes the shared resource attributes,
          # and only `agent`'s also the agent session's person.
          (check
            "R3.1: a database exporter's promote header is not the shared one, or agent's not it plus agentSession's"
            (
              lib.all (
                db:
                (e."otlp_http/${db}".headers."x-greptime-otlp-metric-promote-resource-attrs" or null) == (
                  if db == "agent" then
                    lib.concatStringsSep ";" (
                      i.schema.promotedResourceAttributes ++ session.metrics.promotedResourceAttributes
                    )
                  else
                    sharedPromote
                )
              ) dbs
            )
          )

          # Queue (host-metrics-collection "Collection survives a telemetry store restart").
          (check "R3.1: queue not in file_storage" (
            lib.all (
              n:
              (e.${n}.sending_queue.storage or null) == "file_storage"
              && (e.${n}.sending_queue.sizer or null) == "bytes"
              && (e.${n}.retry_on_failure.max_elapsed_time or null) == "0s"
            ) exporterNames
          ))
          (check "R3.1: fleet queue below 24 h" (
            (e."otlp_http/fleet".sending_queue.queue_size or 0) >= 24 * 60 * i.schema.fleetBytesPerMinute
          ))
          # While the store is down the ingress holds 2 h of every
          # agent-telemetry host's agent metrics and events, and 15 min of
          # their spans (agent-session-telemetry design D10, D13, D15). Its
          # span queue must refuse when full rather than block, so a full
          # queue is a retryable refusal and each host's agent-session
          # collector keeps the spans in its own 3 h queue.
          (check "R3.1: an agent queue below its hold of the agent-telemetry hosts' assumed rates" (
            agentTelemetryHosts > 0
            &&
              (e."otlp_http/agent".sending_queue.queue_size or 0)
              >= 2 * 60 * agentTelemetryHosts * i.schema.agentMetricsBytesPerMinute
            &&
              (e."otlp_http/agent_session_event".sending_queue.queue_size or 0)
              >= 2 * 60 * agentTelemetryHosts * i.schema.agentEventBytesPerMinute
            &&
              (e."otlp_http/agent_span".sending_queue.queue_size or 0)
              >= 15 * agentTelemetryHosts * i.schema.agentSpanBytesPerMinute
            && !(e."otlp_http/agent_span".sending_queue.block_on_overflow or false)
          ))
          (check "R3.1: queues at or above 512 MiB" (lib.foldl' builtins.add 0 queueSizes < mib 512))

          # Envelope: the limiter refuses data before the unit's ceiling kills
          # the collector and its in-memory batches.
          (check "R3.1: memory_limiter at or above the collector's MemoryMax" (
            collectorMemoryMax != null
            && mib (p.memory_limiter.limit_mib or 0) < mib (lib.toInt (builtins.head collectorMemoryMax))
          ))

          # design D14: omp's spans are decoded in the agent-session
          # collector, whose limiter refuses them below the Go runtime's
          # collection target, itself below the unit's ceiling; the host's
          # collector keeps the Go runtime's default.
          (check
            "R3.1: the agent-session collector's limiter is not below its GOMEMLIMIT and that below its MemoryMax, or the host's collector sets GOMEMLIMIT"
            (
              agentMemoryMax != null
              && goMemLimit i.agentService != null
              && (ap.memory_limiter.limit_mib or 0) > 0
              && (ap.memory_limiter.limit_mib or 0) < lib.toInt (builtins.head (goMemLimit i.agentService))
              && lib.toInt (builtins.head (goMemLimit i.agentService)) < lib.toInt (builtins.head agentMemoryMax)
              && goMemLimit i.collectorService == null
            )
          )

          # Validation override: only the zerotierone job's authorization.
          (check "R3.1: validation override beyond the zerotierone authorization" (
            zerotierJobs != [ ]
            && builtins.length overrideParts == 1
            && lib.all (m: m != null) overrideParts
            &&
              builtins.elemAt (builtins.head overrideParts) 0
              == "receivers::prometheus/zerotier::config::scrape_configs"
            && builtins.fromJSON (builtins.elemAt (builtins.head overrideParts) 1) == zerotierJobs
          ))

          # Failure wiring (telemetry-store-interface "Failure notices are posted to one topic").
          (check
            "R3.1: a greptimedb*, zfs-set-*, zfs-assert-*, devloop-*, collector, otel-envelope or agent-session unit is not notified"
            (lib.all (name: builtins.elem name i.notifyUnits) (builtins.filter notifiedByPolicy hostUnits))
          )
          (check "R3.1: a named unit is not wired to the notifier" (lib.all unitWired i.notifyUnits))
          (check "R3.1: a notified unit lacks the start-time RESOLVED hook sharing its stop hook's script" (
            lib.all startResolves i.notifyUnits
          ))
          (check
            "R3.1: notifier is not the rehearsed observability-notify-failed script with a 900 s interval"
            (notifier == "${deployedNotify.failed} %i" && i.notifierInterval == "900")
          )

          # Startup (host-metrics-collection "The collector starts after the databases exist").
          (check "R3.1: collector not ordered after the schema job" (
            builtins.elem "greptimedb-schema.service" i.services.opentelemetry-collector.after
            && builtins.elem "greptimedb-schema.service" i.services.opentelemetry-collector.wants
          ))

          # The collector release the agent-session path was proven at
          # (design D15; A203, A207, A208): the link clearing relies on its
          # links setter, the tool-result strip and the masks on its OTTL,
          # the hand-off cap on its batcher.
          (check
            "R3.1: the collector is not otelcol-contrib 0.155.0; before changing it, rerun fleet-ingress's agentSpans and handoffCap cases, which prove the link clearing, the tool-result strip, the masks and the hand-off cap at a release"
            (i.collectorVersion == "0.155.0")
          )
          # The hand-off (design D15): the ingress queues a span request
          # whole, so one larger than its agent_span queue never fits.
          (check
            "R3.1: the agent-session collector's span exporter does not send one request at a time, batched by bytes to at most a quarter of the ingress's agent_span queue"
            (
              let
                queue = ae."otlp_http/ingress-traces".sending_queue or { };
                batch = queue.batch or { };
              in
              (queue.num_consumers or null) == 1
              && (batch.sizer or null) == "bytes"
              && (batch.max_size or 0) > 0
              && batch.max_size <= (e."otlp_http/agent_span".sending_queue.queue_size or 0) / 4
            )
          )

          # R1.2 (ADR-001): below 1.3.0 the store needs explicit-bucket histograms.
          (lib.optional (
            lib.versionOlder i.storeVersion "1.3.0"
            && !(
              builtins.elem "transform/exphist" pipelines."metrics/ingress".processors
              && lib.any (lib.hasPrefix "convert_exponential_histogram_to_histogram(") exphist
            )
          ) "R1.2: exponential-histogram conversion missing below store 1.3.0")
        ];

      actual = failures input;

      onSettings = update: i: i // { settings = lib.recursiveUpdate i.settings update; };

      mutants = {
        # A3:233: a receiver endpoint of 0.0.0.0:4318.
        receiverEndpointWildcard = onSettings {
          receivers.otlp.protocols.http.endpoint = "0.0.0.0:4318";
        };
        meshWildcard = onSettings { receivers."otlp/mesh".protocols.http.endpoint = "[::]:4318"; };
        secondMeshReceiver =
          i:
          onSettings {
            receivers."otlp/second".protocols.http.endpoint =
              i.settings.receivers."otlp/mesh".protocols.http.endpoint;
          } i;
        ztAddressOther = i: i // { ztAddress = "fddb:4344:343b:14b9:399:930f:39db:40d3"; };
        meshAddressOther = i: i // { meshAddress = self.lib.hosts.cinnabar.address; };
        meshTincrWildcard = onSettings {
          receivers."otlp/mesh-tincr".protocols.http.endpoint = "[::]:4318";
        };
        meshTincrAbsent =
          i:
          i
          // {
            settings = i.settings // {
              receivers = builtins.removeAttrs i.settings.receivers [ "otlp/mesh-tincr" ];
            };
          };
        meshTincrWithoutClientCa = onSettings {
          receivers."otlp/mesh-tincr".protocols.http.tls.client_ca_file = null;
        };
        # A3:233: an exporter listenAddress of 0.0.0.0.
        exporterListenWildcard =
          i:
          i
          // {
            node = i.node // {
              listenAddress = "0.0.0.0";
            };
          };
        scrapeTargetOffLoopback =
          i:
          onSettings {
            receivers.prometheus.config.scrape_configs = map (
              job:
              if job.job_name == "node" then
                job // { static_configs = [ { targets = [ "10.147.17.1:9100" ]; } ]; }
              else
                job
            ) i.settings.receivers.prometheus.config.scrape_configs;
          } i;
        processFloorUnwired =
          i:
          onSettings {
            service.pipelines."metrics/process".processors =
              lib.remove "filter/process-min"
                i.settings.service.pipelines."metrics/process".processors;
          } i;
        limiterOverMemoryMax = onSettings { processors.memory_limiter.limit_mib = 600; };
        aliasTransformUnwired =
          i:
          onSettings {
            service.pipelines."metrics/host".processors =
              lib.remove "transform/omnigent-alias"
                i.settings.service.pipelines."metrics/host".processors;
          } i;
        processNameAfterAgent =
          i:
          onSettings {
            service.pipelines."metrics/process".processors =
              lib.remove "transform/process-name" i.settings.service.pipelines."metrics/process".processors
              ++ [ "transform/process-name" ];
          } i;
        processNameUnwired =
          i:
          onSettings {
            service.pipelines."metrics/process".processors =
              lib.remove "transform/process-name"
                i.settings.service.pipelines."metrics/process".processors;
          } i;
        # `$1` unescaped: the collector expands it as a variable, not a group.
        processNameUnescaped = onSettings {
          processors."transform/process-name".metric_statements = [
            ''replace_pattern(resource.attributes["process.executable.name"], "^([^ ]{15,}) .*$", "$1")''
          ];
        };
        queueInMemory =
          i:
          i
          // {
            settings = i.settings // {
              exporters = i.settings.exporters // {
                "otlp_http/fleet" = i.settings.exporters."otlp_http/fleet" // {
                  sending_queue = builtins.removeAttrs i.settings.exporters."otlp_http/fleet".sending_queue [
                    "storage"
                  ];
                };
              };
            };
          };
        queueUnder24h = onSettings { exporters."otlp_http/fleet".sending_queue.queue_size = mib 64; };
        queueOver512MiB = onSettings { exporters."otlp_http/fleet".sending_queue.queue_size = mib 448; };
        # S2 design D4: a logs exporter without the persistent queue.
        logsQueueNotPersistent =
          i:
          i
          // {
            settings = i.settings // {
              exporters = i.settings.exporters // {
                "otlp_http/devloop_ci_build" = i.settings.exporters."otlp_http/devloop_ci_build" // {
                  sending_queue =
                    builtins.removeAttrs i.settings.exporters."otlp_http/devloop_ci_build".sending_queue
                      [ "storage" ];
                };
              };
            };
          };
        # A devloop logs route writing into fleet.
        logsToFleet = onSettings {
          service.pipelines."logs/devloop-ci_build-out".exporters = [ "otlp_http/fleet" ];
        };
        # A devloop logs route bypassing the table's pipeline through the
        # metrics exporter, whose only header is the database (plan review F3).
        logsToMetricsExporter = onSettings {
          service.pipelines."logs/devloop-ci_build-out".exporters = [ "otlp_http/devloop" ];
        };
        # ADR-003:81: the local OTLP receiver feeding a logs pipeline.
        otlpInLogsPipeline =
          i:
          onSettings {
            receivers.otlp.protocols.http.endpoint = "127.0.0.1:4318";
            service.pipelines."logs/devloop-ci_build".receivers =
              i.settings.service.pipelines."logs/devloop-ci_build".receivers
              ++ [ "otlp" ];
          } i;
        overrideTouchesAnotherReceiver =
          i:
          i // { overrides = i.overrides ++ [ "receivers::host_metrics/memory::collection_interval=1s" ]; };
        onFailureDropped =
          i:
          i
          // {
            services = i.services // {
              opentelemetry-collector = i.services.opentelemetry-collector // {
                unitConfig = builtins.removeAttrs i.services.opentelemetry-collector.unitConfig [ "OnFailure" ];
              };
            };
          };
        startHookDropped =
          i:
          i
          // {
            services = i.services // {
              opentelemetry-collector = lib.recursiveUpdate i.services.opentelemetry-collector {
                serviceConfig.ExecStartPost = builtins.filter (
                  hook: builtins.match (resolvedHook "start") hook == null
                ) (lib.toList (i.services.opentelemetry-collector.serviceConfig.ExecStartPost or [ ]));
              };
            };
          };
        # A oneshot whose start hook is another script could post RESOLVED twice.
        oneshotStartHookOtherScript =
          i:
          i
          // {
            services = i.services // {
              greptimedb-schema = lib.recursiveUpdate i.services.greptimedb-schema {
                serviceConfig.ExecStartPost = [
                  "-+/nix/store/${lib.fixedWidthString 32 "0" ""}-observability-notify-resolved start %n"
                ];
              };
            };
          };
        # A new disk unit that is not listed.
        unlistedDiskUnit =
          i:
          i
          // {
            services = i.services // {
              zfs-set-root-foo-quota = {
                unitConfig = { };
                serviceConfig.ExecStart = "/run/current-system/sw/bin/zfs set quota=1G zroot/root/foo";
              };
            };
          };
        # S2 design D11: the dev-loop reconcile drops out of the notified units.
        reconcileNotNotified = i: i // { notifyUnits = lib.remove "devloop-reconcile" i.notifyUnits; };
        envelopeNotNotified = i: i // { notifyUnits = lib.remove "otel-envelope" i.notifyUnits; };
        schemaOrderDropped =
          i:
          i
          // {
            services = i.services // {
              opentelemetry-collector = i.services.opentelemetry-collector // {
                after = lib.remove "greptimedb-schema.service" i.services.opentelemetry-collector.after;
              };
            };
          };
        # R1.2's mutant.
        conversionRemoved = onSettings { processors."transform/exphist".metric_statements = [ ]; };
      };

      # The agent-session path's mutants (agent-session-telemetry design D3,
      # D5, D10, D14), each with the clause it must fail; the build log
      # lists each with its failures.
      clause = {
        loopback = "R3.1: an endpoint off loopback other than the ingress receivers, or an ingress receiver not on magnetite's address or without otlp/mesh's TLS";
        handoff = "R3.1: the agent-session collector does not hand off over mTLS to otlp/loopback, an HTTP-only receiver with otlp/mesh's TLS feeding the ingress pipelines";
        local = "R3.1: otlp/local is not the agent-session collector's only receiver, HTTP-only on 127.0.0.1:4318, feeding exactly its three agent-session pipelines";
        isolation = "R3.1: the host's collector has an otlp/local receiver, a receiver on its address, or an agent-session pipeline";
        logsReceiver = "R3.1: a logs pipeline takes an OTLP receiver other than the ingress receivers, or the agent-session collector's other than logs/agent-session's otlp/local";
        traces = "R3.1: a traces pipeline other than the agent-session collector's traces/agent-session into otlp_http/ingress-traces and the ingress's traces/ingress, or a span route not into agent.agent_span's declared columns through greptime_trace_v1 with auto_create_table=false, or a span column or index the schema job does not also add to an existing table";
        stages = "R3.1: an agent-session pipeline's stages are not the filters and transforms before the stamping";
        keys = "R3.1: an agent-session filter or transform keeps a service, metric, event or key off schema.nix's agentSession, or the body, or does not cut, copy or mask as schema.nix's agentSession says";
        route = "R3.1: agent events are not routed through routing/logs to otlp_http/agent_session_event with its four headers";
        promote = "R3.1: a database exporter's promote header is not the shared one, or agent's not it plus agentSession's";
        agentQueue = "R3.1: an agent queue below its hold of the agent-telemetry hosts' assumed rates";
        agentLimiter = "R3.1: the agent-session collector's limiter is not below its GOMEMLIMIT and that below its MemoryMax, or the host's collector sets GOMEMLIMIT";
        notified = "R3.1: a greptimedb*, zfs-set-*, zfs-assert-*, devloop-*, collector, otel-envelope or agent-session unit is not notified";
        unit = "R3.1: the agent-session collector shares the host collector's queue directory, serves telemetry off loopback, does not always restart, is bound to the host's collector, or may start before the store's schema job";
        langfusePath = "R3.1: traces/langfuse exists where observabilityHosts does not set langfuse or is missing where it does, or is not fed by forward/langfuse from traces/agent-session alone, after all its stages, through stages that cannot refuse, or sends the fleet's routing attributes, host.name, service.version, tool_use_id, duration_ms, a copied full_command or file_path, omp's startup requests or the oneshot kind";
        langfuseScrape = "R3.1: the otelcol-agent-session scrape job is missing where langfuse is set or present where it is not, or keeps more than the Langfuse exporter's sent and failed span counters";
        langfuseExporter = "R3.1: Langfuse's exporter does not send to schema.nix's endpoint, https://cloud.langfuse.com/api/public/otel, with verified TLS, no proxy and a 30 s timeout, with the unit's Langfuse credentials and ingestion version, retry for retryMinutes and no longer, drain faster than spans arrive into a queue of twice a retry window, in batches under the request limit, or a store exporter of the agent-session collector does not retry forever, or its queues reach 512 MiB";
        collectorVersion = "R3.1: the collector is not otelcol-contrib 0.155.0; before changing it, rerun fleet-ingress's agentSpans and handoffCap cases, which prove the link clearing, the tool-result strip, the masks and the hand-off cap at a release";
        handoffCap = "R3.1: the agent-session collector's span exporter does not send one request at a time, batched by bytes to at most a quarter of the ingress's agent_span queue";
      };
      onAgent = update: i: i // { agentSettings = lib.recursiveUpdate i.agentSettings update; };
      withReceiver =
        pipeline: receiver: i:
        onSettings {
          service.pipelines.${pipeline}.receivers = i.settings.service.pipelines.${pipeline}.receivers ++ [
            receiver
          ];
        } i;
      replaceStatement =
        processor: kind: from: to: i:
        onAgent {
          processors.${processor}.${kind} = map (
            statement: if statement == from then to else statement
          ) i.agentSettings.processors.${processor}.${kind};
        } i;
      # The prompt copy with one condition cut out of its statements; a
      # condition that is absent leaves the configuration as it was, and
      # the mutant is then not rejected.
      promptGateWithout = condition: {
        clauses = [ clause.keys ];
        mutate =
          i:
          onAgent {
            processors."transform/agent-session-prompt".trace_statements = map (lib.replaceStrings
              [ condition ]
              [ "" ]
            ) i.agentSettings.processors."transform/agent-session-prompt".trace_statements;
          } i;
      };
      agentStages =
        pipeline: f: i:
        onAgent {
          service.pipelines.${pipeline}.processors =
            f
              i.agentSettings.service.pipelines.${pipeline}.processors;
        } i;
      # The agent-session collector's otlp/local and one of its pipelines
      # back in the host's collector.
      backInShared =
        pipeline: i:
        onSettings {
          receivers."otlp/local" = i.agentSettings.receivers."otlp/local";
          service.pipelines.${pipeline} = i.agentSettings.service.pipelines.${pipeline};
        } i;
      session = self.lib.otelCollectorSchema.agentSession;
      quotedList = keys: "[${lib.concatMapStringsSep ", " (key: ''"${key}"'') keys}]";
      agentMutants = {
        # The ingress's agent queues before the re-budget, at the host
        # table's three agent-telemetry hosts (magnetite, pyrite, stibnite).
        agentQueueShortThreeHosts = {
          clauses = [ clause.agentQueue ];
          mutate = onSettings {
            exporters."otlp_http/agent_session_event".sending_queue.queue_size = mib 32;
            exporters."otlp_http/agent_span".sending_queue.queue_size = mib 8;
          };
        };
        # A third series of the agent-session collector reaches fleet
        # (darwin-agent-session-telemetry design D9).
        agentSessionKeepWidened = {
          clauses = [ clause.langfuseScrape ];
          mutate =
            i:
            onSettings {
              receivers.prometheus.config.scrape_configs = map (
                job:
                if job.job_name == "otelcol-agent-session" then
                  job
                  // {
                    metric_relabel_configs = [
                      (
                        builtins.head job.metric_relabel_configs
                        // {
                          regex = "${(builtins.head job.metric_relabel_configs).regex}|otelcol_exporter_queue_size";
                        }
                      )
                    ]
                    ++ builtins.tail job.metric_relabel_configs;
                  }
                else
                  job
              ) i.settings.receivers.prometheus.config.scrape_configs;
            } i;
        };
        # Isolation (design D14).
        localFeedsDevloop = {
          clauses = [
            clause.isolation
            clause.logsReceiver
          ];
          mutate = withReceiver "logs/devloop-deploy_record" "otlp/local";
        };
        localFeedsFleet = {
          clauses = [ clause.isolation ];
          mutate =
            i:
            withReceiver "metrics/host" "otlp/local" (
              onSettings { receivers."otlp/local" = i.agentSettings.receivers."otlp/local"; } i
            );
        };
        metricsBackInShared = {
          clauses = [ clause.isolation ];
          mutate = backInShared "metrics/agent-session";
        };
        spansBackInShared = {
          clauses = [
            clause.isolation
            clause.traces
          ];
          mutate = backInShared "traces/agent-session";
        };
        # The agent-session collector's receiver.
        localWildcard = {
          clauses = [
            clause.loopback
            clause.local
          ];
          mutate = onAgent { receivers."otlp/local".protocols.http.endpoint = "0.0.0.0:4318"; };
        };
        localSecondReceiver = {
          clauses = [
            clause.local
            clause.logsReceiver
          ];
          mutate =
            i:
            onAgent {
              receivers."otlp/other".protocols.http.endpoint = "127.0.0.1:4319";
              service.pipelines."logs/agent-session".receivers =
                i.agentSettings.service.pipelines."logs/agent-session".receivers
                ++ [ "otlp/other" ];
            } i;
        };
        # The hand-off to the ingress (design D14).
        handoffWithoutClientCa = {
          clauses = [ clause.handoff ];
          mutate = onSettings { receivers."otlp/loopback".protocols.http.tls.client_ca_file = null; };
        };
        handoffWildcard = {
          clauses = [
            clause.loopback
            clause.handoff
          ];
          mutate = onSettings { receivers."otlp/loopback".protocols.http.endpoint = "0.0.0.0:4321"; };
        };
        handoffAroundIngress = {
          clauses = [ clause.handoff ];
          mutate = onAgent {
            exporters."otlp_http/ingress-agent".endpoint = "http://127.0.0.1:4000/v1/otlp";
          };
        };
        handoffNameUnverified = {
          clauses = [ clause.handoff ];
          mutate = onAgent {
            exporters."otlp_http/ingress-traces".tls.server_name_override = "localhost";
          };
        };
        # The span path (design D13). omp's whole history, the system prompt
        # included, kept on the span; it stays dropped for size (design D15).
        spanInputMessagesKept = {
          clauses = [ clause.keys ];
          mutate =
            replaceStatement "transform/agent-session-spans" "trace_statements"
              "keep_keys(span.attributes, ${quotedList (builtins.attrNames session.spans.keys)})"
              "keep_keys(span.attributes, ${
                quotedList (builtins.attrNames session.spans.keys ++ [ session.spans.promptSource ])
              })";
        };
        spanEventsKept = {
          clauses = [ clause.stages ];
          mutate = agentStages "traces/agent-session" (lib.remove "filter/agent-session-span-events");
        };
        # Tool output (design D15): Claude's never reaches its span, because
        # the copy is gone or runs after every event is dropped.
        toolOutputCopyRemoved = {
          clauses = [ clause.stages ];
          mutate = agentStages "traces/agent-session" (lib.remove "transform/agent-session-tool-output");
        };
        toolOutputCopyAfterEventsDropped = {
          clauses = [ clause.stages ];
          mutate = agentStages "traces/agent-session" (
            processors:
            lib.concatMap (
              n:
              if n == "transform/agent-session-tool-output" then
                [ ]
              else if n == "filter/agent-session-span-events" then
                [
                  n
                  "transform/agent-session-tool-output"
                ]
              else
                [ n ]
            ) processors
          );
        };
        # Claude's Read output, one of the three attributes, not copied.
        toolOutputAttributeDropped = {
          clauses = [ clause.keys ];
          mutate =
            i:
            onAgent {
              processors."transform/agent-session-tool-output".trace_statements = lib.filter (
                s: !lib.hasInfix ''spanevent.attributes["content"]'' s
              ) i.agentSettings.processors."transform/agent-session-tool-output".trace_statements;
            } i;
        };
        # The status message, a failed tool's output, no longer cut.
        statusMessageUncut = {
          clauses = [ clause.keys ];
          mutate =
            i:
            onAgent {
              processors."transform/agent-session-spans".trace_statements =
                lib.remove "truncate_all(span.cache, 65536)"
                  i.agentSettings.processors."transform/agent-session-spans".trace_statements;
            } i;
        };
        # Masking (design D15): gone from either pipeline, run before the
        # cut that bounds its scan, one shape dropped, or the status message
        # left unmasked.
        maskRemovedFromSpans = {
          clauses = [ clause.stages ];
          mutate = agentStages "traces/agent-session" (lib.remove "transform/agent-session-mask");
        };
        maskRemovedFromEvents = {
          clauses = [ clause.stages ];
          mutate = agentStages "logs/agent-session" (lib.remove "transform/agent-session-mask");
        };
        maskBeforeCut = {
          clauses = [ clause.stages ];
          mutate = agentStages "traces/agent-session" (
            processors:
            lib.concatMap (
              n:
              if n == "transform/agent-session-mask" then
                [ ]
              else if n == "transform/agent-session-spans" then
                [
                  "transform/agent-session-mask"
                  n
                ]
              else
                [ n ]
            ) processors
          );
        };
        maskShapeDropped = {
          clauses = [ clause.keys ];
          mutate =
            i:
            onAgent {
              processors."transform/agent-session-mask".trace_statements = map (lib.replaceStrings
                [ "(?:${session.credentialPatterns.github})|" ]
                [ "" ]
              ) i.agentSettings.processors."transform/agent-session-mask".trace_statements;
            } i;
        };
        statusMessageUnmasked = {
          clauses = [ clause.keys ];
          mutate =
            i:
            onAgent {
              processors."transform/agent-session-mask".trace_statements = lib.filter (
                s: !lib.hasPrefix "replace_pattern(span.status.message" s
              ) i.agentSettings.processors."transform/agent-session-mask".trace_statements;
            } i;
        };
        # The copy after the allow-list reads an attribute already dropped,
        # so no prompt is stored.
        promptAfterAllowList = {
          clauses = [ clause.stages ];
          mutate = agentStages "traces/agent-session" (
            processors:
            lib.remove "transform/agent-session-prompt" (lib.remove "resource/agent-session" processors)
            ++ [
              "transform/agent-session-prompt"
              "resource/agent-session"
            ]
          );
        };
        # omp's spans decoded with no limiter in front of them.
        traceLimiterDropped = {
          clauses = [ clause.stages ];
          mutate = agentStages "traces/agent-session" (lib.remove "memory_limiter");
        };
        # An emitter's own `last_user_message` survives a copy that finds no
        # match.
        promptNotCleared = {
          clauses = [ clause.keys ];
          mutate =
            i:
            onAgent {
              processors."transform/agent-session-prompt".trace_statements =
                lib.remove ''delete_key(span.attributes, "last_user_message")''
                  i.agentSettings.processors."transform/agent-session-prompt".trace_statements;
            } i;
        };
        # The copy's gate loses one condition (design D15), so it runs on a
        # span whose newest user message can be a tool result or injected
        # context: any span, a step after a tool, an advisor's or subagent's,
        # a oneshot's, or one under an in-band tool dialect.
        promptGateNoChat = promptGateWithout ''IsMatch(span.name, "^chat ") and '';
        promptGateNoStep = promptGateWithout ''and span.attributes["omp.gen_ai.agent.step.number"] == 0'';
        promptGateNoAgentId = promptGateWithout ''and span.attributes["gen_ai.agent.id"] == nil'';
        promptGateNoOneshot = promptGateWithout ''and span.attributes["omp.gen_ai.oneshot.kind"] == nil'';
        promptGateNoTools = promptGateWithout ''and span.attributes["omp.gen_ai.request.available_tools"] != nil'';
        # The first-text-part rule the deploy showed wrong: omp's reminder
        # part, not the person's prompt, becomes `last_user_message`.
        promptFirstTextPart = promptGateWithout ''(?:\\{\\s*\"type\"\\s*:\\s*\"text\"\\s*,\\s*\"content\"\\s*:\\s*\"(?:[^\"\\\\]|\\\\.)*\"\\s*\\}\\s*,\\s*)*'';
        # A string-content message's reminder kept at the prompt's head.
        promptReminderKept = {
          clauses = [ clause.keys ];
          mutate =
            i:
            onAgent {
              processors."transform/agent-session-prompt".trace_statements = lib.filter (
                s: !lib.hasPrefix "replace_pattern(" s
              ) i.agentSettings.processors."transform/agent-session-prompt".trace_statements;
            } i;
        };
        # Span links, whose attributes the store writes: not cleared, and
        # the fail-closed filter behind the clearing gone.
        spanLinksNotCleared = {
          clauses = [ clause.stages ];
          mutate = agentStages "traces/agent-session" (lib.remove "transform/agent-session-span-links");
        };
        spanLinksKept = {
          clauses = [ clause.stages ];
          mutate = agentStages "traces/agent-session" (lib.remove "filter/agent-session-span-links");
        };
        # A kept value is no longer bounded at 64 KiB.
        spanTruncationRemoved = {
          clauses = [ clause.keys ];
          mutate =
            i:
            onAgent {
              processors."transform/agent-session-spans".trace_statements =
                lib.remove "truncate_all(span.attributes, 65536)"
                  i.agentSettings.processors."transform/agent-session-spans".trace_statements;
            } i;
        };
        eventTruncationRemoved = {
          clauses = [ clause.keys ];
          mutate =
            i:
            onAgent {
              processors."transform/agent-session-events".log_statements =
                lib.remove "truncate_all(log.attributes, 65536)"
                  i.agentSettings.processors."transform/agent-session-events".log_statements;
            } i;
        };
        handoffConsumersDefault = {
          clauses = [ clause.handoff ];
          mutate = onAgent { exporters."otlp_http/ingress-agent".sending_queue.num_consumers = 10; };
        };
        sharedQueueDirectory = {
          clauses = [ clause.unit ];
          mutate =
            i: onAgent { extensions.file_storage.directory = i.settings.extensions.file_storage.directory; } i;
        };
        agentTelemetryWildcard = {
          clauses = [ clause.unit ];
          mutate =
            i:
            onAgent {
              service.telemetry.metrics.readers = [
                {
                  pull.exporter.prometheus = {
                    host = "0.0.0.0";
                    port = 8890;
                  };
                }
              ];
            } i;
        };
        agentRestartOnFailure = {
          clauses = [ clause.unit ];
          mutate =
            i:
            i
            // {
              agentService = i.agentService // {
                Restart = "on-failure";
              };
            };
        };
        agentBoundToShared = {
          clauses = [ clause.unit ];
          mutate =
            i:
            i
            // {
              services = i.services // {
                otel-agent-session = i.services.otel-agent-session // {
                  bindsTo = [ "opentelemetry-collector.service" ];
                };
              };
            };
        };
        # A switch that adds span keys may start the unit before the schema
        # job has added their columns (design D15).
        agentBeforeSchema = {
          clauses = [ clause.unit ];
          mutate =
            i:
            i
            // {
              services = i.services // {
                otel-agent-session = i.services.otel-agent-session // {
                  after = lib.remove "greptimedb-schema.service" i.services.otel-agent-session.after;
                };
              };
            };
        };
        # A switch starts the unit in a transaction of its own, so After=
        # alone does not order it after a schema job started in another
        # (magnetite, 2026-11-22: 20 ms before it, two spans refused).
        agentSchemaNotWanted = {
          clauses = [ clause.unit ];
          mutate =
            i:
            i
            // {
              services = i.services // {
                otel-agent-session = i.services.otel-agent-session // {
                  wants = lib.remove "greptimedb-schema.service" (i.services.otel-agent-session.wants or [ ]);
                };
              };
            };
        };
        agentLimiterOverGoMemLimit = {
          clauses = [ clause.agentLimiter ];
          mutate = onAgent { processors.memory_limiter.limit_mib = 420; };
        };
        goMemLimitUnset = {
          clauses = [ clause.agentLimiter ];
          mutate = i: i // { agentService = builtins.removeAttrs i.agentService [ "Environment" ]; };
        };
        # The chain's earlier mitigation back on the host's collector.
        sharedGoMemLimit = {
          clauses = [ clause.agentLimiter ];
          mutate =
            i:
            i
            // {
              collectorService = i.collectorService // {
                Environment = [ "GOMEMLIMIT=409MiB" ];
              };
            };
        };
        spansToFleet = {
          clauses = [ clause.traces ];
          mutate = onSettings { service.pipelines."traces/ingress".exporters = [ "otlp_http/fleet" ]; };
        };
        spanTableAutoCreated = {
          clauses = [ clause.traces ];
          mutate = onSettings {
            exporters."otlp_http/agent_span".headers."x-greptime-hints" = "auto_create_table=true";
          };
        };
        # An existing agent_span is no longer brought to the declared
        # columns, or to the content columns' indexes (design D15).
        spanColumnsNotAltered = {
          clauses = [ clause.traces ];
          mutate =
            i:
            i
            // {
              storeTables = i.storeTables // {
                agent = lib.filter (s: !lib.hasInfix "ADD COLUMN IF NOT EXISTS" s) i.storeTables.agent;
              };
            };
        };
        spanIndexesNotAltered = {
          clauses = [ clause.traces ];
          mutate =
            i:
            i
            // {
              storeTables = i.storeTables // {
                agent = lib.filter (s: !lib.hasInfix "SET FULLTEXT INDEX" s) i.storeTables.agent;
              };
            };
        };
        eventFilterDropped = {
          clauses = [ clause.stages ];
          mutate = agentStages "logs/agent-session" (lib.remove "filter/agent-session-events");
        };
        bodyKept = {
          clauses = [ clause.keys ];
          mutate =
            i:
            onAgent {
              processors."transform/agent-session-events".log_statements =
                lib.remove ''set(log.body, "")''
                  i.agentSettings.processors."transform/agent-session-events".log_statements;
            } i;
        };
        sessionIdKept = {
          clauses = [ clause.keys ];
          mutate =
            replaceStatement "transform/agent-session-metrics" "metric_statements"
              "keep_keys(datapoint.attributes, ${quotedList session.metrics.pointKeys})"
              "keep_keys(datapoint.attributes, ${quotedList (session.metrics.pointKeys ++ [ "session.id" ])})";
        };
        # A key off an event's list (here a made-up tool_result key) kept.
        eventUnlistedKeyKept = {
          clauses = [ clause.keys ];
          mutate =
            let
              keys = session.events.correlationKeys ++ session.events.keys.tool_result;
            in
            replaceStatement "transform/agent-session-events" "log_statements"
              ''keep_keys(log.attributes, ${quotedList keys}) where log.attributes["event.name"] == "tool_result"''
              ''keep_keys(log.attributes, ${
                quotedList (keys ++ [ "tool_output" ])
              }) where log.attributes["event.name"] == "tool_result"'';
        };
        # An added statement copying the body into an attribute (review F4).
        bodyCopied = {
          clauses = [ clause.keys ];
          mutate =
            i:
            onAgent {
              processors."transform/agent-session-events".log_statements = [
                ''set(log.attributes["x"], log.body)''
              ]
              ++ i.agentSettings.processors."transform/agent-session-events".log_statements;
            } i;
        };
        scopeKept = {
          clauses = [ clause.keys ];
          mutate =
            i:
            onAgent {
              processors."transform/agent-session-metrics".metric_statements =
                lib.remove "keep_keys(scope.attributes, [])"
                  i.agentSettings.processors."transform/agent-session-metrics".metric_statements;
            } i;
        };
        agentEventsToDevloop = {
          clauses = [ clause.route ];
          mutate = onSettings {
            service.pipelines."logs/agent-session_event-out".exporters = [ "otlp_http/devloop_ci_build" ];
          };
        };
        fleetPromotesPerson = {
          clauses = [ clause.promote ];
          mutate =
            i:
            onSettings {
              exporters."otlp_http/fleet".headers."x-greptime-otlp-metric-promote-resource-attrs" =
                i.settings.exporters."otlp_http/agent".headers."x-greptime-otlp-metric-promote-resource-attrs";
            } i;
        };
        agentQueueShort = {
          clauses = [ clause.agentQueue ];
          mutate = onSettings { exporters."otlp_http/agent_session_event".sending_queue.queue_size = mib 8; };
        };
        # The ingress's span queue below 15 min of both hosts' spans, or
        # blocking when full instead of refusing the hand-off (design D15).
        agentSpanQueueShort = {
          clauses = [ clause.agentQueue ];
          mutate = onSettings { exporters."otlp_http/agent_span".sending_queue.queue_size = mib 6; };
        };
        agentSpanQueueBlocks = {
          clauses = [ clause.agentQueue ];
          mutate = onSettings { exporters."otlp_http/agent_span".sending_queue.block_on_overflow = true; };
        };
        agentUnitNotNotified = {
          clauses = [ clause.notified ];
          mutate = i: i // { notifyUnits = lib.remove "otel-agent-session" i.notifyUnits; };
        };
        agentEnvelopeNotNotified = {
          clauses = [ clause.notified ];
          mutate = i: i // { notifyUnits = lib.remove "otel-agent-session-envelope" i.notifyUnits; };
        };
        # Langfuse Cloud (design D16). The fan-out moved before the mask: a
        # pipeline of its own on otlp/local, without the mask and the
        # stamping, feeds Langfuse, and traces/agent-session only the store.
        langfuseBeforeMask = {
          clauses = [
            clause.langfusePath
            clause.local
          ];
          mutate =
            i:
            let
              spans = i.agentSettings.service.pipelines."traces/agent-session";
            in
            onAgent {
              service.pipelines = {
                "traces/agent-session".exporters = [ "otlp_http/ingress-traces" ];
                "traces/agent-session-unmasked" = spans // {
                  processors = lib.remove "resource/agent-session" (
                    lib.remove "transform/agent-session-mask" spans.processors
                  );
                  exporters = [ "forward/langfuse" ];
                };
              };
            } i;
        };
        langfuseFromLocal = {
          clauses = [ clause.langfusePath ];
          mutate = onAgent { service.pipelines."traces/langfuse".receivers = [ "otlp/local" ]; };
        };
        langfuseWithLimiter = {
          clauses = [ clause.langfusePath ];
          mutate =
            i:
            onAgent {
              service.pipelines."traces/langfuse".processors = [
                "memory_limiter"
              ]
              ++ i.agentSettings.service.pipelines."traces/langfuse".processors;
            } i;
        };
        langfuseTransformPropagates = {
          clauses = [ clause.langfusePath ];
          mutate = onAgent { processors."transform/langfuse".error_mode = "propagate"; };
        };
        # omp's startup requests reach Langfuse (darwin-agent-session-
        # telemetry design D8).
        langfuseOneshotConditionDropped = {
          clauses = [ clause.langfusePath ];
          mutate =
            i:
            onAgent {
              processors."filter/langfuse".trace_conditions =
                lib.take 1
                  i.agentSettings.processors."filter/langfuse".trace_conditions;
            } i;
        };
        # The oneshot kind reaches Langfuse.
        langfuseOneshotKeyKept = {
          clauses = [ clause.langfusePath ];
          mutate =
            i:
            onAgent {
              processors."transform/langfuse".trace_statements =
                lib.remove ''delete_key(span.attributes, "omp.gen_ai.oneshot.kind")''
                  i.agentSettings.processors."transform/langfuse".trace_statements;
            } i;
        };
        langfuseRoutingKept = {
          clauses = [ clause.langfusePath ];
          mutate =
            i:
            onAgent {
              processors."transform/langfuse".trace_statements = builtins.filter (
                s: !lib.hasPrefix "delete_matching_keys(resource.attributes" s
              ) i.agentSettings.processors."transform/langfuse".trace_statements;
            } i;
        };
        langfuseWithoutFlag = {
          clauses = [ clause.langfusePath ];
          mutate =
            i:
            i
            // {
              hosts = i.hosts // {
                magnetite = i.hosts.magnetite // {
                  langfuse = false;
                };
              };
            };
        };
        langfuseRetryForever = {
          clauses = [ clause.langfuseExporter ];
          mutate = onAgent { exporters."otlp_http/langfuse".retry_on_failure.max_elapsed_time = "0s"; };
        };
        storeSpansRetryFinite = {
          clauses = [ clause.langfuseExporter ];
          mutate = onAgent { exporters."otlp_http/ingress-traces".retry_on_failure.max_elapsed_time = "5m"; };
        };
        langfuseQueueShort = {
          clauses = [ clause.langfuseExporter ];
          mutate = onAgent { exporters."otlp_http/langfuse".sending_queue.queue_size = mib 1; };
        };
        langfuseDrainSlow = {
          clauses = [ clause.langfuseExporter ];
          mutate = onAgent { exporters."otlp_http/langfuse".sending_queue.num_consumers = 1; };
        };
        langfuseBatchOverLimit = {
          clauses = [ clause.langfuseExporter ];
          mutate = onAgent {
            exporters."otlp_http/langfuse".sending_queue.batch = {
              min_size = mib 6;
              max_size = mib 6;
            };
          };
        };
        langfuseKeyInline = {
          clauses = [ clause.langfuseExporter ];
          mutate = onAgent { extensions."basicauth/langfuse".client_auth.password = "inline"; };
        };
        agentQueuesOver512 = {
          clauses = [ clause.langfuseExporter ];
          mutate = onAgent { exporters."otlp_http/ingress-agent".sending_queue.queue_size = mib 400; };
        };
        # omp's tool-result strip (design D15): gone, after the cut that it
        # must precede, ignoring its errors, on every service rather than
        # omp's, or without the withholding behind it.
        toolResultStripRemoved = {
          clauses = [ clause.stages ];
          mutate = agentStages "traces/agent-session" (lib.remove "transform/agent-session-tool-result");
        };
        toolResultStripAfterCut = {
          clauses = [ clause.stages ];
          mutate = agentStages "traces/agent-session" (
            processors:
            lib.concatMap (
              n:
              if n == "transform/agent-session-tool-result" then
                [ ]
              else if n == "transform/agent-session-spans" then
                [
                  n
                  "transform/agent-session-tool-result"
                ]
              else
                [ n ]
            ) processors
          );
        };
        toolResultStripIgnoresErrors = {
          clauses = [ clause.stages ];
          mutate = onAgent { processors."transform/agent-session-tool-result".error_mode = "ignore"; };
        };
        toolResultStripUngated = {
          clauses = [ clause.keys ];
          mutate =
            i:
            onAgent {
              processors."transform/agent-session-tool-result".trace_statements = map (lib.replaceStrings
                [ ''where resource.attributes["service.name"] == "${session.spans.toolResult.service}"'' ]
                [ "" ]
              ) i.agentSettings.processors."transform/agent-session-tool-result".trace_statements;
            } i;
        };
        toolResultNotWithheld = {
          clauses = [ clause.keys ];
          mutate =
            i:
            onAgent {
              processors."transform/agent-session-tool-result".trace_statements =
                lib.take 1
                  i.agentSettings.processors."transform/agent-session-tool-result".trace_statements;
            } i;
        };
        # The encoded-blob net (design D15): gone from spans and the status
        # message, gone from events, or run before the credential shapes.
        blobNetRemovedFromSpans = {
          clauses = [ clause.keys ];
          mutate =
            i:
            onAgent {
              processors."transform/agent-session-mask".trace_statements = lib.filter (
                s: !lib.hasInfix session.encodedBlobPattern s
              ) i.agentSettings.processors."transform/agent-session-mask".trace_statements;
            } i;
        };
        blobNetRemovedFromEvents = {
          clauses = [ clause.keys ];
          mutate =
            i:
            onAgent {
              processors."transform/agent-session-mask".log_statements =
                lib.take 1
                  i.agentSettings.processors."transform/agent-session-mask".log_statements;
            } i;
        };
        blobNetBeforeShapes = {
          clauses = [ clause.keys ];
          mutate =
            i:
            onAgent {
              processors."transform/agent-session-mask".log_statements =
                lib.reverseList
                  i.agentSettings.processors."transform/agent-session-mask".log_statements;
            } i;
        };
        # schema.nix's shapes emptied and the mask rendered from the empty
        # set, as the module would: only the names catch it.
        credentialPatternsEmptied = {
          clauses = [ clause.keys ];
          mutate =
            i:
            let
              rendered = map (
                lib.replaceStrings
                  [
                    (lib.escape [ "\\" "\"" ] (
                      lib.concatMapStringsSep "|" (pattern: "(?:${pattern})") (
                        builtins.attrValues session.credentialPatterns
                      )
                    ))
                  ]
                  [ "" ]
              );
              mask = i.agentSettings.processors."transform/agent-session-mask";
            in
            onAgent
              {
                processors."transform/agent-session-mask" = {
                  log_statements = rendered mask.log_statements;
                  trace_statements = rendered mask.trace_statements;
                };
              }
              (
                i
                // {
                  schema = i.schema // {
                    agentSession = i.schema.agentSession // {
                      credentialPatterns = { };
                    };
                  };
                }
              );
        };
        # A collector release other than the one the path was proven at.
        collectorUpgraded = {
          clauses = [ clause.collectorVersion ];
          mutate = i: i // { collectorVersion = "0.156.0"; };
        };
        # A string-typed key holding an array or a map kept whole, uncut
        # and unmasked (review follow-up 2).
        nonStringSpanValueKept = {
          clauses = [ clause.keys ];
          mutate =
            i:
            onAgent {
              processors."transform/agent-session-spans".trace_statements = builtins.filter (
                s: !lib.hasInfix "IsString" s
              ) i.agentSettings.processors."transform/agent-session-spans".trace_statements;
            } i;
        };
        nonStringEventValueKept = {
          clauses = [ clause.keys ];
          mutate =
            i:
            onAgent {
              processors."transform/agent-session-events".log_statements = builtins.filter (
                s: !lib.hasInfix "IsString" s
              ) i.agentSettings.processors."transform/agent-session-events".log_statements;
            } i;
        };
        # What Langfuse need not get (review follow-up 3).
        langfuseHostNameSent = {
          clauses = [ clause.langfusePath ];
          mutate =
            i:
            onAgent {
              processors."transform/langfuse".trace_statements =
                lib.remove ''delete_key(resource.attributes, "host.name")''
                  i.agentSettings.processors."transform/langfuse".trace_statements;
            } i;
        };
        langfuseCommandTwice = {
          clauses = [ clause.langfusePath ];
          mutate =
            i:
            onAgent {
              processors."transform/langfuse".trace_statements = builtins.filter (
                s: !lib.hasPrefix ''delete_key(span.attributes, "full_command")'' s
              ) i.agentSettings.processors."transform/langfuse".trace_statements;
            } i;
        };
        langfuseTlsInsecure = {
          clauses = [ clause.langfuseExporter ];
          mutate = onAgent { exporters."otlp_http/langfuse".tls.insecure_skip_verify = true; };
        };
        langfuseProxied = {
          clauses = [ clause.langfuseExporter ];
          mutate = onAgent { exporters."otlp_http/langfuse".proxy_url = "http://127.0.0.1:3128"; };
        };
        langfuseTimeoutDefault = {
          clauses = [ clause.langfuseExporter ];
          mutate =
            i:
            i
            // {
              agentSettings = i.agentSettings // {
                exporters = i.agentSettings.exporters // {
                  "otlp_http/langfuse" = builtins.removeAttrs i.agentSettings.exporters."otlp_http/langfuse" [
                    "timeout"
                  ];
                };
              };
            };
        };
        # schema.nix and the exporter moved together to another endpoint.
        langfuseEndpointElsewhere = {
          clauses = [ clause.langfuseExporter ];
          mutate =
            i:
            onAgent
              { exporters."otlp_http/langfuse".endpoint = "https://langfuse.example.org/api/public/otel"; }
              (
                i
                // {
                  schema = i.schema // {
                    agentSession = i.schema.agentSession // {
                      langfuse = i.schema.agentSession.langfuse // {
                        endpoint = "https://langfuse.example.org/api/public/otel";
                      };
                    };
                  };
                }
              );
        };
        # The hand-off (design D15): uncapped, capped at the ingress's
        # queue, or several requests at once.
        handoffUncapped = {
          clauses = [ clause.handoffCap ];
          mutate =
            i:
            let
              exporter = i.agentSettings.exporters."otlp_http/ingress-traces";
            in
            i
            // {
              agentSettings = i.agentSettings // {
                exporters = i.agentSettings.exporters // {
                  "otlp_http/ingress-traces" = exporter // {
                    sending_queue = builtins.removeAttrs exporter.sending_queue [ "batch" ];
                  };
                };
              };
            };
        };
        handoffCapAtQueue = {
          clauses = [ clause.handoffCap ];
          mutate = onAgent { exporters."otlp_http/ingress-traces".sending_queue.batch.max_size = mib 8; };
        };
        handoffCapHalfQueue = {
          clauses = [ clause.handoffCap ];
          mutate = onAgent { exporters."otlp_http/ingress-traces".sending_queue.batch.max_size = mib 4; };
        };
        handoffConsumersMany = {
          clauses = [ clause.handoffCap ];
          mutate = onAgent { exporters."otlp_http/ingress-traces".sending_queue.num_consumers = 10; };
        };
      };
      agentRejections = lib.mapAttrs (_: m: failures (m.mutate input)) agentMutants;
      agentAccepted = lib.attrNames (
        lib.filterAttrs (
          name: m: !(lib.all (c: builtins.elem c agentRejections.${name}) m.clauses)
        ) agentMutants
      );
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        otel-collector-config =
          assert lib.assertMsg (actual == [ ]) "otel-collector-config failures: ${builtins.toJSON actual}";
          assert lib.assertMsg (lib.all (mutant: failures (mutant input) != [ ]) (lib.attrValues mutants))
            "otel-collector-config accepted a mutant: ${
              builtins.toJSON (builtins.attrNames (lib.filterAttrs (_: m: failures (m input) == [ ]) mutants))
            }";
          assert lib.assertMsg (agentAccepted == [ ])
            "otel-collector-config: an agent-session mutant did not fail its clauses: ${
              builtins.toJSON (lib.genAttrs agentAccepted (name: agentRejections.${name}))
            }";
          pkgs.runCommand "otel-collector-config" { passthru = { inherit failures; }; } ''
            # The notifier's rate limit (review F1).
            test -e ${notifierRehearsal}
            ${lib.concatStrings (
              lib.mapAttrsToList (name: failed: ''
                echo ${lib.escapeShellArg "mutant ${name} rejected: ${builtins.toJSON failed}"}
              '') agentRejections
            )}
            touch "$out"
          '';
      };
    };
}
