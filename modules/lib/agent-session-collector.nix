# flake.lib.agentSessionCollector: the agent-session collector's
# configuration as a plain attrset of host facts, so the NixOS agent role and
# a darwin fragment render the same settings from one place
# (darwin-agent-session-telemetry design D1). Only the credential paths and
# the queue directory differ by platform; the unit or daemon running it, its
# hardening, its credentials' delivery and its memory ceiling stay with the
# caller. flake.lib.agentSessionAssertions judges the settings without
# reference to systemd.
{ config, lib, ... }:
let
  flakeLib = config.flake.lib;
  schema = flakeLib.otelCollectorSchema;
  mib = n: n * 1024 * 1024;
  handoff = flakeLib.agentSessionHandoff;
  langfuseExporter = "otlp_http/langfuse";
  spanExporter = "otlp_http/ingress-traces";
in
{
  # The ingress host's agent-session collector hands its output to that
  # host's collector on this loopback address, whose agent_span queue takes
  # each span request whole or not at all (agent-session-telemetry design
  # D14, D15); 12 MiB holds 15 min of three agent-telemetry hosts' assumed
  # spans, and the span exporter's batch is a quarter of it
  # (darwin-agent-session-telemetry design D7).
  flake.lib.agentSessionHandoff = {
    address = "127.0.0.1:4321";
    spanQueueBytes = mib 12;
  };

  # An otlp_http exporter over mTLS, presenting certFile and keyFile, with a
  # persistent queue of queueSize bytes.
  flake.lib.otelMtlsExporter =
    {
      endpoint,
      caFile,
      certFile,
      keyFile,
      serverName ? null,
      consumers ? null,
    }:
    queueSize: {
      inherit endpoint;
      tls = {
        ca_file = caFile;
        cert_file = certFile;
        key_file = keyFile;
        min_version = "1.3";
      }
      // lib.optionalAttrs (serverName != null) { server_name_override = serverName; };
      sending_queue = {
        storage = "file_storage";
        sizer = "bytes";
        queue_size = queueSize;
      }
      // lib.optionalAttrs (consumers != null) { num_consumers = consumers; };
      # A persistent queue drops an item whose retries run out, so
      # retries never stop while the ingress is unreachable.
      retry_on_failure = {
        enabled = true;
        max_interval = "60s";
        max_elapsed_time = "0s";
      };
    };

  # Every filter and transform but the prompt copy propagates its errors, so
  # a statement that cannot run refuses the batch rather than passing it on;
  # the prompt copy ignores its own, since the span allow-list after it drops
  # what it would have read. The collector exports over mTLS: on the ingress
  # host to its loopback receiver otlp/loopback, elsewhere to otlp/mesh.
  flake.lib.agentSessionCollector =
    {
      hostName,
      # Whether the host runs the ingress.
      ingress ? false,
      caFile,
      certFile,
      keyFile,
      # The file_storage directory of the exporters' persistent queues.
      queueDirectory,
      # One exporter per signal, each with its own persistent queue: 24 h of
      # agent metrics, 8 h of agent events and 3 h of spans at schema.nix's
      # rates while the ingress is unreachable (design D10, D14, D15);
      # flake.lib.agentSessionAssertions judges them.
      queueBytes ? {
        "otlp_http/ingress-metrics" = mib 52;
        "otlp_http/ingress-agent" = mib 64;
        "otlp_http/ingress-traces" = mib 44;
      },
      # Its own telemetry port, beside the host's collector on 8888.
      telemetryPort ? 8890,
      # Langfuse Cloud's project keys as files, { publicKeyFile;
      # secretKeyFile; }, where the host sends its spans there too; null
      # elsewhere.
      langfuse ? null,
    }:
    let
      # The ceiling (ADR-003 envelope as amended, design D14): omp's chat
      # spans arrive several MiB at a time and are decoded at ten to
      # fourteen times their size, so the collector gets the ingress's 512M
      # and 384 MiB limiter, and the Go runtime collects at 80 % of the
      # ceiling rather than letting garbage reach it.
      ceilingMib = 512;
      goMemLimitMib = ceilingMib * 4 / 5;
      limiterMib = 384;
      withLangfuse = langfuse != null;
      session = schema.agentSession;
      eventNames = builtins.attrNames session.events.keys;
      # The keys whose column is a string: of each span key, by its
      # declared type; of each event key, by its session_event column.
      spanStringKeys = builtins.attrNames (
        lib.filterAttrs (_: type: type == "string") session.spans.keys
      );
      eventStringKeys = map (column: column.source.log) (
        builtins.filter (
          column: column.type == "string" && (column.source.log or null) != null
        ) session.tables.session_event.columns
      );
      list = keys: "[${lib.concatMapStringsSep ", " (key: ''"${key}"'') keys}]";
      oneOf = path: values: lib.concatMapStringsSep " or " (value: ''${path} == "${value}"'') values;
      # schema.nix's credential shapes as one RE2 alternation, quoted
      # as an OTTL string.
      credentials = ''"${
        lib.escape [ "\\" "\"" ] (
          lib.concatMapStringsSep "|" (pattern: "(?:${pattern})") (
            builtins.attrValues session.credentialPatterns
          )
        )
      }"'';
      # A regex or a literal as an OTTL string.
      ottlString = s: ''"${lib.escape [ "\\" "\"" ] s}"'';
      encodedBlob = ottlString session.encodedBlobPattern;
      toolResult = session.spans.toolResult;
      serviceName = ''resource.attributes["service.name"]'';
      eventName = ''log.attributes["event.name"]'';
      stamp =
        extra:
        [
          {
            key = "host.name";
            value = hostName;
            action = "upsert";
          }
          {
            key = "vanixiets.database";
            value = "agent";
            action = "upsert";
          }
        ]
        ++ extra;

      # The ingress queues each span request whole in its agent_span queue,
      # so a larger one could never be queued and, retried forever, would
      # hold the hand-off: the span exporter sends one request at a time,
      # split to a quarter of that queue (design D15).
      handoffBatch = {
        sizer = "bytes";
        min_size = 0;
        max_size = handoff.spanQueueBytes / 4;
        flush_timeout = "1s";
      };
      sessionExporter =
        name: queueSize:
        lib.recursiveUpdate (flakeLib.otelMtlsExporter (
          {
            inherit caFile certFile keyFile;
          }
          // (
            if ingress then
              {
                endpoint = "https://${handoff.address}";
                # The ingress's certificate names the host, not loopback.
                serverName = flakeLib.hosts.magnetite.fqdn;
                # One request per signal in flight into the ingress's
                # shared limiter (design D14).
                consumers = 1;
              }
            else
              {
                endpoint = "https://[${flakeLib.hosts.magnetite.zerotier.address}]:4318";
                consumers = if name == spanExporter then 1 else null;
              }
          )
        ) queueSize) (lib.optionalAttrs (name == spanExporter) { sending_queue.batch = handoffBatch; });
      # Langfuse Cloud (design D16): the spans traces/agent-session exports
      # also go, through forward/langfuse, to traces/langfuse. That branch
      # must never refuse: a refusal there reaches otlp/local through the
      # fan-out, the emitters retry, and the store gets the batch twice. So
      # it has no limiter, its processors ignore their errors, and its queue
      # drains faster than spans arrive even while Langfuse is down
      # (schema.nix's agentSession.langfuse; flake.lib.agentSessionAssertions).
      lf = session.langfuse;
      attr = key: ''span.attributes["${key}"]'';
      # Langfuse stops looking for an output once an input is set, and
      # the reverse, so each source that sets one sets both where it
      # has both (Langfuse OtelIngestionProcessor.ts:2025-2037).
      setFrom =
        target: source: condition:
        "set(${attr "langfuse.observation.${target}"}, ${attr source}) where ${
          lib.optionalString (condition != "") "${condition} and "
        }${attr source} != nil";
      claudeTool = ''span.name == "claude_code.tool"'';
      langfuseStatements = [
        # omp's step-0 chat span: the person's message and the reply.
        (setFrom "input" "last_user_message" "")
        (setFrom "output" "gen_ai.output.messages" "${attr "last_user_message"} != nil")
        # Claude Code's turn: the prompt.
        (setFrom "input" "user_prompt" ''span.name == "claude_code.interaction"'')
        # Claude Code's tool: the command or the path, and its output.
        (setFrom "input" "full_command" claudeTool)
        (setFrom "input" "file_path" "${claudeTool} and ${attr "langfuse.observation.input"} == nil")
        (setFrom "output" "gen_ai.tool.call.result" claudeTool)
        # Each copied value once.
        ''delete_key(span.attributes, "last_user_message")''
        ''delete_key(span.attributes, "user_prompt")''
        ''delete_key(span.attributes, "gen_ai.output.messages") where ${attr "langfuse.observation.output"} != nil''
        ''delete_key(span.attributes, "gen_ai.tool.call.result") where ${attr "langfuse.observation.output"} != nil''
      ]
      ++ lib.concatLists (
        lib.mapAttrsToList (from: to: [
          "set(${attr to}, ${attr from}) where ${attr from} != nil"
          ''delete_key(span.attributes, "${from}")''
        ]) lf.usageKeys
      )
      ++ [
        # The copies above once more, and what Langfuse shows nothing
        # for (review follow-up 3).
        ''delete_key(span.attributes, "full_command") where ${attr "full_command"} == ${attr "langfuse.observation.input"}''
        ''delete_key(span.attributes, "file_path") where ${attr "file_path"} == ${attr "langfuse.observation.input"}''
        ''delete_key(span.attributes, "tool_use_id")''
        ''delete_key(span.attributes, "duration_ms")''
        # The store's oneshot kind (design D8), which Langfuse shows nothing
        # for.
        ''delete_key(span.attributes, "omp.gen_ai.oneshot.kind")''
        ''delete_key(resource.attributes, "host.name")''
        ''delete_key(resource.attributes, "service.version")''
        # The fleet's routing attributes are not Langfuse's.
        ''delete_matching_keys(resource.attributes, "^vanixiets\\.")''
      ];
    in
    {
      inherit
        queueBytes
        limiterMib
        goMemLimitMib
        ceilingMib
        ;
      settings = {
        extensions = {
          file_storage = {
            directory = queueDirectory;
            create_directory = true;
          };
        }
        // lib.optionalAttrs withLangfuse {
          # The project's keys; the extension reads each file and trims it.
          "basicauth/langfuse".client_auth = {
            username_file = langfuse.publicKeyFile;
            password_file = langfuse.secretKeyFile;
          };
        };

        receivers."otlp/local".protocols.http.endpoint = "127.0.0.1:4318";

        processors = {
          memory_limiter = {
            check_interval = "1s";
            limit_mib = limiterMib;
          };
          "filter/agent-session-service" = {
            error_mode = "propagate";
            metric_conditions = [ "not (${oneOf serviceName session.metrics.services})" ];
            log_conditions = [ "not (${oneOf serviceName session.events.services})" ];
            trace_conditions = [ "not (${oneOf serviceName session.spans.services})" ];
          };
          "filter/agent-session-metrics" = {
            error_mode = "propagate";
            metric_conditions = [ "not (${oneOf "metric.name" session.metrics.names})" ];
          };
          "filter/agent-session-events" = {
            error_mode = "propagate";
            log_conditions = [ "not (${oneOf eventName eventNames})" ];
          };
          "transform/agent-session-metrics" = {
            error_mode = "propagate";
            metric_statements = [
              "keep_keys(datapoint.attributes, ${list session.metrics.pointKeys})"
              "keep_keys(resource.attributes, ${list session.metrics.resourceKeys})"
              "keep_keys(scope.attributes, [])"
            ];
          };
          # Per event, its own keys and the correlation keys; the body,
          # which ADR-008:42's redaction cannot protect, is replaced.
          "transform/agent-session-events" = {
            error_mode = "propagate";
            log_statements =
              map (
                event:
                ''keep_keys(log.attributes, ${
                  list (session.events.correlationKeys ++ session.events.keys.${event})
                }) where ${eventName} == "${event}"''
              ) eventNames
              # A value the store types as a string that is not one (an
              # array or map) goes: the cut and the masks act on strings
              # only, so it would pass whole and unmasked.
              ++ map (
                key:
                ''delete_key(log.attributes, "${key}") where log.attributes["${key}"] != nil and not IsString(log.attributes["${key}"])''
              ) eventStringKeys
              ++ [
                ''set(log.body, "")''
                # Every kept value at most 64 KiB (design D14).
                "truncate_all(log.attributes, 65536)"
                "keep_keys(resource.attributes, ${list session.events.resourceKeys})"
                "keep_keys(scope.attributes, [])"
              ];
          };
          "resource/agent-session".attributes = stamp [ ];
          "resource/agent-session-events".attributes = stamp [
            {
              key = "vanixiets.table";
              value = "session_event";
              action = "upsert";
            }
          ];
          # omp's gen_ai.input.messages holds the whole conversation,
          # earlier tool results included (design D13): the text of its
          # newest message, when that is a user text message, becomes
          # `last_user_message`, and the allow-list below drops the
          # attribute itself. The copy runs only on a chat span at step
          # 0 of a top-level run (no agent identity: no advisor or
          # subagent), not a oneshot, with native tools (an in-band
          # dialect sends tool results as user messages and lists no
          # tools), so a tool result is never the message copied
          # (design D15). Only the attribute's last 64 KiB is searched
          # and only the matched text is parsed: parsing the whole
          # history, often several MiB, held about ten times its size
          # on the heap. A newest message longer than that yields none.
          "transform/agent-session-prompt" =
            let
              source = ''span.attributes["${session.spans.promptSource}"]'';
            in
            {
              error_mode = "ignore";
              trace_statements = [
                # An emitter's own `last_user_message` never survives a
                # copy that finds no match or does not run.
                ''delete_key(span.attributes, "last_user_message")''
                ''set(span.cache["g"], true) where IsMatch(span.name, "^chat ") and span.attributes["omp.gen_ai.agent.step.number"] == 0 and span.attributes["gen_ai.agent.id"] == nil and span.attributes["omp.gen_ai.oneshot.kind"] == nil and span.attributes["omp.gen_ai.request.available_tools"] != nil''
                ''set(span.cache["t"], ${source}) where span.cache["g"] == true and ${source} != nil and Len(${source}) <= 65536''
                ''set(span.cache["t"], Substring(${source}, Len(${source}) - 65536, 65536)) where span.cache["g"] == true and ${source} != nil and Len(${source}) > 65536''
                # The newest user message's LAST text part: omp 19.1.0
                # prepends its date and working-directory reminder as
                # a text part of its own before the person's (design
                # D15, A201); attachments follow as non-text parts.
                ''set(span.cache["x"], ExtractPatterns(span.cache["t"], "\\{\\s*\"role\"\\s*:\\s*\"user\"\\s*,\\s*\"parts\"\\s*:\\s*\\[\\s*(?:\\{\\s*\"type\"\\s*:\\s*\"text\"\\s*,\\s*\"content\"\\s*:\\s*\"(?:[^\"\\\\]|\\\\.)*\"\\s*\\}\\s*,\\s*)*\\{\\s*\"type\"\\s*:\\s*\"text\"\\s*,\\s*\"content\"\\s*:\\s*\"(?P<c>(?:[^\"\\\\]|\\\\.)*)\"\\s*\\}(?:\\s*,\\s*\\{[^\\[\\]]*\\})*\\s*\\]\\s*\\}\\s*\\]\\s*$")) where span.cache["t"] != nil''
                ''set(span.cache["p"], ParseJSON(Concat(["[\"", span.cache["x"]["c"], "\"]"], ""))) where span.cache["x"]["c"] != nil''
                ''set(span.attributes["last_user_message"], span.cache["p"][0]) where span.cache["p"] != nil''
                # A string-content message carries the reminder at the
                # head of its one text part.
                ''replace_pattern(span.attributes["last_user_message"], "^<system-reminder>[\\s\\S]*?</system-reminder>\\s*", "")''
              ];
            };
          # Claude Code's tool output exists only as its `tool.output`
          # span event (design D15): each listed attribute is copied
          # onto the event's span as schema.nix's toolOutput key, before
          # the filter below drops every event.
          "transform/agent-session-tool-output" = {
            error_mode = "propagate";
            trace_statements = map (
              attribute:
              ''set(span.attributes["${session.spans.toolOutput.key}"], spanevent.attributes["${attribute}"]) where spanevent.name == "${session.spans.toolOutput.event}" and spanevent.attributes["${attribute}"] != nil''
            ) session.spans.toolOutput.attributes;
          };
          # Every span event, exceptions included, whatever its name.
          "filter/agent-session-span-events" = {
            error_mode = "propagate";
            trace_conditions = [ ''spanevent.name != "" or spanevent.name == ""'' ];
          };
          # Links are never stored (design D14, D15), but the span is:
          # Claude's `llm_request` carries one on a direct Anthropic
          # connection. OTTL 0.155.0 has no value to clear them with;
          # assigning the links to themselves does, because its setter
          # empties the span's slice, which is the value it then copies
          # (pkg/ottl contexts/internal/ctxspan/span.go:524-540; pdata
          # 1.61.0 SpanLinkSlice.CopyTo returns on the same slice).
          "transform/agent-session-span-links" = {
            error_mode = "propagate";
            trace_statements = [ "set(span.links, span.links)" ];
          };
          # Fail-closed behind it: a span still carrying links is
          # dropped whole, since the store would write their attributes.
          "filter/agent-session-span-links" = {
            error_mode = "propagate";
            trace_conditions = [ "Len(span.links) > 0" ];
          };
          # omp's tool results without their `details` (design D15):
          # before the cut, so the 64 KiB keep `content`; then any
          # result still holding a `details` key is withheld whole.
          # schema.nix's agentSession.spans.toolResult says why the
          # text rule is exact.
          "transform/agent-session-tool-result" =
            let
              result = ''span.attributes["${session.spans.toolOutput.key}"]'';
              omp = ''${serviceName} == "${toolResult.service}"'';
            in
            {
              error_mode = "propagate";
              trace_statements = [
                ''replace_pattern(${result}, ${ottlString toolResult.strip}, "]$$1}") where ${omp}''
                "set(${result}, ${ottlString toolResult.withheld}) where ${omp} and IsMatch(${result}, ${ottlString toolResult.detailsKey})"
              ];
            };
          "transform/agent-session-spans" = {
            error_mode = "propagate";
            trace_statements = [
              "keep_keys(span.attributes, ${list (builtins.attrNames session.spans.keys)})"
            ]
            # A kept value schema.nix types as a string that is not one
            # (an array or map) goes: the cut and the masks act on
            # strings only, and Langfuse has no typed column to refuse
            # it.
            ++ map (
              key:
              ''delete_key(span.attributes, "${key}") where span.attributes["${key}"] != nil and not IsString(span.attributes["${key}"])''
            ) spanStringKeys
            ++ [
              # Every kept value at most 64 KiB (design D14), the
              # status message too (design D15): it holds a failed
              # tool's output or error text. truncate_all cuts at a
              # UTF-8 boundary, so the message goes through the cache.
              "truncate_all(span.attributes, 65536)"
              ''set(span.cache["status"], span.status.message)''
              "truncate_all(span.cache, 65536)"
              ''set(span.status.message, span.cache["status"])''
              "keep_keys(resource.attributes, ${list session.spans.resourceKeys})"
              "keep_keys(scope.attributes, [])"
            ];
          };
          # Credential shapes, then encoded blobs, in every kept string,
          # after the cut that bounds the scan (design D15). Shapes
          # first: a JWT, a key block, a bearer token or a Slack URL
          # spans several runs, and is masked whole before the blob
          # net could mask one of its runs and leave the others. What
          # the cut leaves of a run is masked at 129 characters or more
          # and passes below, as any shorter run does. In addition to
          # the key allow-lists, never instead: it masks token-shaped
          # and encoded strings, not every secret. OTTL rather than the
          # redaction processor, which does not reach the status
          # message.
          "transform/agent-session-mask" = {
            error_mode = "propagate";
            log_statements = [
              ''replace_all_patterns(log.attributes, "value", ${credentials}, "****")''
              ''replace_all_patterns(log.attributes, "value", ${encodedBlob}, "****")''
            ];
            trace_statements = [
              ''replace_all_patterns(span.attributes, "value", ${credentials}, "****")''
              ''replace_all_patterns(span.attributes, "value", ${encodedBlob}, "****")''
              ''replace_pattern(span.status.message, ${credentials}, "****")''
              ''replace_pattern(span.status.message, ${encodedBlob}, "****")''
            ];
          };
        }
        // lib.optionalAttrs withLangfuse {
          # Claude Code's spans that carry nothing after the allow-list, and
          # omp's startup requests (darwin-agent-session-telemetry design
          # D8).
          "filter/langfuse" = {
            error_mode = "ignore";
            trace_conditions = [
              (oneOf "span.name" lf.droppedSpans)
              (oneOf (attr "omp.gen_ai.oneshot.kind") lf.droppedOneshotKinds)
            ];
          };
          # Langfuse's names for what the store keeps under ours.
          "transform/langfuse" = {
            error_mode = "ignore";
            trace_statements = langfuseStatements;
          };
        };

        exporters =
          lib.mapAttrs sessionExporter queueBytes
          // lib.optionalAttrs withLangfuse {
            ${langfuseExporter} = {
              inherit (lf) endpoint;
              inherit (lf) timeout;
              auth.authenticator = "basicauth/langfuse";
              headers."x-langfuse-ingestion-version" = lf.ingestionVersion;
              sending_queue = {
                storage = "file_storage";
                sizer = "bytes";
                queue_size = lf.queueBytes;
                num_consumers = lf.consumers;
                # A batch leaves at its size or after the timeout; while
                # every consumer waits on Langfuse, batches fill to
                # max_size, which is what bounds the queue.
                batch = {
                  sizer = "bytes";
                  min_size = lf.batchBytes;
                  max_size = lf.batchBytes;
                  flush_timeout = "10s";
                };
              };
              retry_on_failure = {
                enabled = true;
                max_interval = "60s";
                max_elapsed_time = "${toString lf.retryMinutes}m";
              };
            };
          };

        service = {
          extensions = [ "file_storage" ] ++ lib.optional withLangfuse "basicauth/langfuse";
          telemetry.metrics.readers = [
            {
              pull.exporter.prometheus = {
                host = "127.0.0.1";
                port = telemetryPort;
              };
            }
          ];
          pipelines = {
            "metrics/agent-session" = {
              receivers = [ "otlp/local" ];
              processors = [
                "memory_limiter"
                "filter/agent-session-service"
                "filter/agent-session-metrics"
                "transform/agent-session-metrics"
                "resource/agent-session"
              ];
              exporters = [ "otlp_http/ingress-metrics" ];
            };
            "logs/agent-session" = {
              receivers = [ "otlp/local" ];
              processors = [
                "memory_limiter"
                "filter/agent-session-service"
                "filter/agent-session-events"
                "transform/agent-session-events"
                "transform/agent-session-mask"
                "resource/agent-session-events"
              ];
              exporters = [ "otlp_http/ingress-agent" ];
            };
            "traces/agent-session" = {
              receivers = [ "otlp/local" ];
              processors = [
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
              ];
              exporters = [ spanExporter ] ++ lib.optional withLangfuse "forward/langfuse";
            };
          }
          // lib.optionalAttrs withLangfuse {
            # After every stage above, so Langfuse gets exactly what
            # the store gets; its renames never reach the store.
            "traces/langfuse" = {
              receivers = [ "forward/langfuse" ];
              processors = [
                "filter/langfuse"
                "transform/langfuse"
              ];
              exporters = [ langfuseExporter ];
            };
          };
        };
      }
      // lib.optionalAttrs withLangfuse {
        connectors."forward/langfuse" = { };
      };
    };

  # The settings-only assertions over an agent-session collector's evaluated
  # settings, with no reference to systemd or launchd: the caller passes its
  # GOMEMLIMIT and, where the platform enforces one, its memory ceiling, both
  # in MiB, or null where it declares none.
  flake.lib.agentSessionAssertions =
    {
      hostName,
      settings,
      langfuse,
      goMemLimitMib,
      ceilingMib ? null,
    }:
    let
      lf = schema.agentSession.langfuse;
    in
    [
      # The collector's own envelope (ADR-003 envelope as amended; design
      # D10, D14). An exporter keeps one persistent queue per signal
      # (exporter_otlp_http_<name>_<signal>), so each exporter serves one
      # pipeline and the sum sees every queue.
      (
        let
          e = settings.exporters;
          exporterNames = builtins.attrNames e;
          q = n: e.${n}.sending_queue or { };
          size = n: (q n).queue_size or 0;
          pipelinesWith =
            n:
            builtins.filter (p: builtins.elem n p.exporters) (builtins.attrValues settings.service.pipelines);
          limit = settings.processors.memory_limiter.limit_mib or 0;
        in
        {
          assertion =
            lib.all (
              n:
              (q n).storage or null == "file_storage"
              && (q n).sizer or null == "bytes"
              # Every store exporter retries forever; only Langfuse's
              # gives up, judged below (design D16).
              && (n == langfuseExporter || (e.${n}.retry_on_failure.max_elapsed_time or null) == "0s")
              && builtins.length (pipelinesWith n) == 1
            ) exporterNames
            && size "otlp_http/ingress-metrics" >= 24 * 60 * schema.agentMetricsBytesPerMinute
            && size "otlp_http/ingress-agent" >= 8 * 60 * schema.agentEventBytesPerMinute
            && size "otlp_http/ingress-traces" >= 3 * 60 * schema.agentSpanBytesPerMinute
            && lib.foldl' (s: n: s + size n) 0 exporterNames < mib 512
            && goMemLimitMib != null
            && limit < goMemLimitMib
            && (ceilingMib == null || goMemLimitMib < ceilingMib);
          message = "otel-collector agent on ${hostName}: every exporter of the agent-session collector must serve one pipeline and queue in file_storage by bytes, every one but ${langfuseExporter} with unlimited retry, otlp_http/ingress-metrics must hold 24 h at agentMetricsBytesPerMinute, otlp_http/ingress-agent 8 h at agentEventBytesPerMinute and otlp_http/ingress-traces 3 h at agentSpanBytesPerMinute, the queues must sum below 512 MiB, and its limiter must be below GOMEMLIMIT and GOMEMLIMIT below any memory ceiling (ADR-003 envelope; agent-session-telemetry design D10, D14, D16); queues ${builtins.toJSON (lib.genAttrs exporterNames size)}, limiter ${toString limit}, GOMEMLIMIT ${builtins.toJSON goMemLimitMib} MiB, ceiling ${builtins.toJSON ceilingMib} MiB.";
        }
      )
      # Langfuse's exporter gives up after retryMinutes and, while Langfuse
      # is down, drains drainMultiple times faster than spans arrive, into a
      # queue holding twice one retry window's arrivals, in requests under
      # Langfuse's limit; so its queue does not fill and the fan-out never
      # refuses (design D16). Nothing else exports there, and nothing in its
      # pipeline can refuse.
      (
        let
          x = settings.exporters.${langfuseExporter} or { };
          queue = x.sending_queue or { };
          batch = queue.batch or { };
          arrivals = lf.retryMinutes * schema.agentSpanBytesPerMinute;
          pipeline = settings.service.pipelines."traces/langfuse" or { };
          processors = pipeline.processors or [ ];
        in
        {
          assertion =
            !langfuse
            || (
              (x.retry_on_failure.enabled or false)
              && lf.retryMinutes > 0
              && (x.retry_on_failure.max_elapsed_time or null) == "${toString lf.retryMinutes}m"
              && (queue.queue_size or 0) >= 2 * arrivals
              && (queue.num_consumers or 0) * (batch.max_size or 0) >= lf.drainMultiple * arrivals
              && (batch.sizer or null) == "bytes"
              && (batch.min_size or null) == (batch.max_size or 0)
              && (batch.max_size or 0) < lf.requestLimitBytes
              && (pipeline.receivers or null) == [ "forward/langfuse" ]
              && (pipeline.exporters or null) == [ langfuseExporter ]
              && !(builtins.elem "memory_limiter" processors)
              && lib.all (n: (settings.processors.${n}.error_mode or null) == "ignore") processors
            );
          message = "otel-collector agent on ${hostName}: ${langfuseExporter} must retry for schema.nix's agentSession.langfuse.retryMinutes and no longer, queue at least twice a retry window's agentSpanBytesPerMinute, drain consumers x batch max_size per retry window at least drainMultiple times that, batch by bytes with min_size equal to max_size under requestLimitBytes, and be fed by traces/langfuse alone, from forward/langfuse, through processors that ignore their errors and no limiter (agent-session-telemetry design D16); exporter ${builtins.toJSON x}, pipeline ${builtins.toJSON pipeline}.";
        }
      )
      # The hand-off (design D15): one span request at a time, each under
      # the ingress's agent_span queue, which takes a request whole or not
      # at all.
      (
        let
          queue = settings.exporters.${spanExporter}.sending_queue or { };
          batch = queue.batch or { };
        in
        {
          assertion =
            (queue.num_consumers or null) == 1
            && (batch.sizer or null) == "bytes"
            && (batch.max_size or 0) > 0
            && batch.max_size <= handoff.spanQueueBytes / 4;
          message = "otel-collector agent on ${hostName}: ${spanExporter} must send one request at a time (num_consumers 1), batched by bytes to a max_size of at most a quarter of the ingress's agent_span queue of ${toString handoff.spanQueueBytes} B, which can never queue a larger request and refuses one that does not fit its free space (agent-session-telemetry design D15); sending_queue ${builtins.toJSON queue}.";
        }
      )
    ];
}
