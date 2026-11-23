# Single source of the collector's allow-lists and bounds (ADR-004
# "Implementation surface"; design D8, D9). The otel-collector clan service
# builds its receivers, transforms and exporter headers from it, its agent
# assertions read the unit allow-list, owner aliases, rate assumption and
# unit cap, otel-envelope's hourly clauses read the budget, and
# checks.x86_64-linux.otel-collector-config reads its databases. import-tree loads every .nix file under
# modules/, so this is a flake-parts module exposing the data as
# flake.lib.otelCollectorSchema; nothing imports it by path. S1 carries the
# keys S1 deploys; later slices add theirs here.
{ ... }:
{
  flake.lib.otelCollectorSchema = {
    # ADR-004's systemd unit allow-list, `.service` units only, as systemd
    # unit patterns. At most budget.units of them may match on one host
    # (ADR-004 Q12).
    systemdUnits = [
      "gitea.service"
      "gitea-mq.service"
      "nixbot*.service"
      "niks3*.service"
      "nix-daemon.service"
      "nix-grpc-daemon.service"
      "harmonia-gc.service"
      "postgresql.service"
      "nginx.service"
      "greptimedb.service"
      "opentelemetry-collector.service"
      "zerotierone.service"
      "omnigent-host-*.service"
      "omnigraph.service"
      "otel-envelope.service"
      "devloop-reconcile.service"
      "greptimedb-envelope.service"
      "greptimedb-export.service"
      "greptimedb-schema.service"
      "prometheus-node-exporter.service"
      "prometheus-smartctl-exporter.service"
      "zfs-assert-*.service"
      "zfs-set-*.service"
      # A failed notifier post becomes a SystemdUnitFailed instance, which
      # the evaluator retries until ntfy accepts it (S3 review F2).
      "observability-notify@*.service"
    ];

    # omnigent-host-<owner>.service is stored as omnigent-host-<alias>.service
    # (ADR-003 item 17), so no owner's name becomes a label value. Opaque and
    # stable: a new owner takes the next number and no alias is renumbered.
    ownerAliases = {
      cameron = "owner-1";
      janettesmith = "owner-2";
    };

    # Resource attributes the store promotes to labels (ADR-003 item 15).
    promotedResourceAttributes = [
      "host.name"
      "systemd.unit.name"
      "process.executable.name"
    ];

    # node_exporter series kept; every other is dropped (ADR-004).
    nodeExporterKeep = [
      "node_zfs_zpool_state"
      "node_zfs_arc_size"
      "node_zfs_arc_c"
      "node_zfs_arc_c_min"
      "node_zfs_arc_c_max"
      "node_zfs_arc_hits"
      "node_zfs_arc_misses"
      "node_zfs_arc_memory_throttle_count"
      "node_vmstat_oom_kill"
      # The textfile collector's own series, on hosts with a registered
      # textfile writer (vanixiets.nodeExporter.textfileWriters), which
      # HostProbeStale reads (F76).
      "node_textfile_mtime_seconds"
      "node_textfile_scrape_error"
      # magnetite's memory budget (CAM-111 design D11): its probe's
      # textfile, written by flake.modules.nixos.magnetite-memory-budget.
      # No other host writes these names.
      "vanixiets_unit_memory_current_bytes"
      "vanixiets_unit_memory_peak_bytes"
      "vanixiets_zram_orig_data_bytes"
      "vanixiets_zram_compr_data_bytes"
      "vanixiets_zram_mem_used_bytes"
      "vanixiets_unit_memory_high_events"
      # The last successful PostgreSQL backup (back-up-postgresql-off-host
      # design D11): written to the textfile collector by
      # flake.modules.nixos.postgresql-backup where the backup is on.
      "vanixiets_postgresql_backup_last_success_timestamp_seconds"
      # The account's R2 usage (track-r2-usage design D2): written to the
      # textfile collector by flake.modules.nixos.r2-usage on the one host
      # where the poller is on (flake.lib.r2Usage.seriesNames).
      "vanixiets_r2_bucket_payload_bytes"
      "vanixiets_r2_bucket_metadata_bytes"
      "vanixiets_r2_bucket_objects"
      "vanixiets_r2_bucket_pending_uploads"
      "vanixiets_r2_operations"
      "vanixiets_r2_billing_period_start_timestamp_seconds"
      "vanixiets_r2_billing_period_end_timestamp_seconds"
      "vanixiets_r2_last_success_timestamp_seconds"
    ];

    # The units magnetite's memory budget reports (CAM-111 design D11), as
    # systemctl patterns: those running there on 2026-11-18 that hold memory
    # or compete with nixbot's evaluations. The collector's systemd receiver
    # reports no unit memory at contrib 0.155.0, so a probe reads systemd's
    # MemoryCurrent and MemoryPeak instead; system.slice and user.slice are
    # reported beside them as totals.
    memoryBudgetUnits = [
      "nixbot.service"
      "nix-daemon.service"
      "greptimedb.service"
      "postgresql.service"
      "gitea.service"
      "gitea-mq.service"
      "gitea-runner-*.service"
      "niks3*.service"
      "nginx.service"
      "matrix-synapse.service"
      "docker.service"
      "kanidm.service"
      "livekit.service"
      "coturn.service"
      "perses.service"
      "opentelemetry-collector.service"
      "omnigent.service"
      "omnigent-host-*.service"
      "omnigraph-server.service"
      "tor.service"
      "tincr-*.service"
      "zerotierone.service"
      "systemd-journald.service"
      # The nightly PostgreSQL backup (back-up-postgresql-off-host design
      # D10): the job and the dumps it starts.
      "restic-backups-*.service"
      "postgresqlBackup-*.service"
      "postgresql-dump-globals.service"
    ];

    # The collector's own telemetry kept from 127.0.0.1:8888 (design D4;
    # ADR-003 item 26): queue size and capacity, send and enqueue failures,
    # receiver refusals. At contrib 0.155.0 the counters carry no `_total`
    # suffix (read live on magnetite on 2026-10-29).
    otelcolKeep = [
      "otelcol_exporter_queue_size"
      "otelcol_exporter_queue_capacity"
      "otelcol_exporter_send_failed_metric_points"
      "otelcol_exporter_send_failed_log_records"
      "otelcol_exporter_enqueue_failed_metric_points"
      "otelcol_exporter_enqueue_failed_log_records"
      "otelcol_receiver_refused_metric_points"
      "otelcol_receiver_refused_log_records"
    ];

    # The agent-session collector's own counters the host collector stores,
    # on hosts whose row sets langfuse, for the Langfuse exporter only: its
    # sent and failed spans, which LangfuseSendFailing compares
    # (darwin-agent-session-telemetry design D9). Separate from otelcolKeep,
    # so no other host's scrape changes.
    otelcolAgentSessionKeep = [
      "otelcol_exporter_sent_spans"
      "otelcol_exporter_send_failed_spans"
    ];

    # smartctl_exporter series kept; `smartctl_device` and
    # `smartctl_version` are dropped (ADR-004).
    smartctlKeep = [
      "smartctl_device_smart_status"
      "smartctl_device_critical_warning"
      "smartctl_device_media_errors"
      "smartctl_device_percentage_used"
      "smartctl_device_available_spare"
      "smartctl_device_available_spare_threshold"
      "smartctl_device_num_err_log_entries"
      "smartctl_device_temperature"
    ];

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
    # launchd.daemons defines. org.nixos.otel-envelope is listed so a
    # stopped or unloaded envelope is visible through the store (design D9).
    launchdLabels = [
      "org.nixos.nix-daemon"
      "org.nixos.nix-grpc-daemon"
      "org.nixos.harmonia-gc"
      "org.nixos.nix-cleanup-gcroots"
      "org.nixos.sops-install-secrets"
      "org.nixos.dnscrypt-proxy"
      "org.nixos.otelcol"
      "org.nixos.otelcol-process"
      "org.nixos.otel-envelope"
      "org.nixos.prometheus-node-exporter"
      "org.nixos.omnigent-host-*"
    ];

    # The allow-listed labels whose evaluated KeepAlive is true (ADR-004:123),
    # which LaunchdJobNotRunning expects running; the darwin fragment asserts
    # this list against its host's evaluated launchd.daemons. A job whose
    # KeepAlive is a condition set, as omnigent-host-<owner>'s
    # { SuccessfulExit = false; }, may exit 0 and stay down legitimately, so
    # it is outside the list (design D9).
    launchdKeptAlive = [
      "org.nixos.dnscrypt-proxy"
      "org.nixos.nix-daemon"
      "org.nixos.nix-grpc-daemon"
      "org.nixos.otelcol"
      "org.nixos.otelcol-process"
      "org.nixos.prometheus-node-exporter"
    ];

    # process.memory.usage is stored only for processes holding at least
    # minBytes.<platform>; each point is one process, so an executable is
    # stored when any one of its processes reaches the floor (ADR-003 item 16).
    # ADR-004's per-host bound of 30 distinct names has no collector stage
    # at contrib 0.155.0; S1 records the observed count at deployment and
    # S4's otel-envelope adds its regulator. The scraper reports RSS on both
    # platforms (process_scraper.go:321-326), and on darwin RSS counts each
    # process's mapped share of the dyld shared cache and frameworks, so
    # ordinary daemons hold 65-300 MiB; darwin's floor is the smallest of
    # 128, 192, 256, 384 and 512 MiB that kept stibnite's hourly distinct
    # names at or below 20 from 2026-11-06T05:17Z to 21:14Z (A77).
    process.minBytes = {
      linux = 67108864;
      darwin = 402653184;
    };

    # The darwin executables kept whatever their size, so that a leak in a
    # service the fleet runs shows as a trend: per launchd label glob (dots
    # literal, as launchdLabels), the name the scraper reports, the kernel's
    # p_comm, which follows symlinks and names an interpreter, not a script
    # (gopsutil@v4.26.5:process/process_darwin.go:65-87; `ps -o comm=` on
    # stibnite on 2026-11-06). The darwin fragment asserts that the globs
    # cover the host's long-running org.nixos.* daemons and that omnigent's
    # name is its package's interpreter. `nix` and `python3.x` also name the
    # operator's own processes; each is one series because the store's series
    # key is the name, and same-named points stored in the same millisecond
    # become one row (design D3).
    process.darwinFleetExecutables = {
      "org.nixos.dnscrypt-proxy" = "dnscrypt-proxy";
      "org.nixos.nix-daemon" = "nix";
      "org.nixos.nix-grpc-daemon" = "nix-grpc-daemon";
      "org.nixos.omnigent-host-*" = "python3.14";
      "org.nixos.otelcol" = "otelcol-contrib";
      "org.nixos.otelcol-process" = "otelcol-contrib";
      "org.nixos.prometheus-node-exporter" = "node_exporter";
    };

    # Unmeasured estimate of magnetite's `fleet` export rate: about 2000
    # series (ADR-004's ~800 host-level series per NixOS host plus the
    # scraped service endpoints) at 128 bytes per OTLP number point with its
    # resource and attribute overhead, one point per minute. The deployment
    # measurement (logs/s1-evidence/8.5-queue-rate.log) replaces it. The
    # agents' queue assertion and checks.x86_64-linux.otel-collector-config
    # read it.
    fleetBytesPerMinute = 256000;

    # Unmeasured estimates of one agent-telemetry host's agent output
    # (agent-session-telemetry design D10), replaced by the measurement of
    # its task 5.4. Metrics: 8 concurrent sessions x about 35 series each x
    # 128 bytes per point, one delta export a minute = 35,840. Events: 8
    # sessions x about 1.0 MB per session-hour (about 575 allow-listed events
    # x 0.6 KB plus about 0.5 MB of prompts, responses and tool details) / 60
    # = about 133,000. The agent role's queue assertion and
    # checks.x86_64-linux.otel-collector-config read them.
    agentMetricsBytesPerMinute = 35840;
    agentEventBytesPerMinute = 133000;
    # Agent spans after the host's span allow-list (design D13, D15): 8
    # sessions x about 1.8 MB per session-hour of omp (about 230 spans x 0.6
    # KB of fixed columns, the newest prompt, the assistant output and tool
    # arguments, 0.75 MB, plus about 1.05 MB of tool results, each cut to 64
    # KiB, measured from 1,185 session-hours of omp transcripts) / 60 =
    # 240,000. Claude Code's spans come to about 0.45 MB per session-hour
    # (about 415 spans), so omp bounds the rate.
    agentSpanBytesPerMinute = 240000;

    # observability-notify@ instances pass the unit allow-list, so that
    # SystemdUnitFailed reports a failed post, but are bounded by the host's
    # notified units, not by budget.units (ADR-004 as amended under charter
    # v23).
    systemdUnitsNotifierPattern = "observability-notify@*.service";

    # ADR-004's budget: otel-envelope's hourly clauses B1, B2, B3 and B5
    # judge the store against it on the ingress host, and the agent role
    # asserts `units` against each host's allow-listed services, so the two
    # cannot disagree on the cap.
    budget = {
      activeSeries = 8000;
      # The `agent` database's series (ADR-004's agent-harness row); B1 and
      # B2 judge it beside fleet, with labelValues per label.
      agentActiveSeries = 2000;
      labelValues = 200;
      processNames = 30;
      units = 40;
      launchdLabels = 30;
      devloopRows = 100000;
    };

    # Store databases and their retention, one otlp_http exporter each
    # (design D8). magnetite's services.greptimedb.databases reads this map,
    # and the ingress role asserts the store creates exactly these names.
    databases = {
      fleet = "30d";
      devloop = "365d";
      agent = "30d";
    };

    # The devloop allow-list (design D3; ADR-004 as amended by charter v22):
    # the only declaration of the dev-loop tables' columns, in stored order,
    # their types, primary keys and time indexes. devloop-collection.nix
    # renders from it the table statements, the ingest pipelines and the
    # nixbot queries' output columns; S4's agents read it too. Every column
    # but the time index is nullable.
    devloop.tables =
      let
        column = name: type: {
          inherit name type;
          nullable = true;
        };
        timeIndex = name: {
          inherit name;
          type = "timestamp";
          nullable = false;
        };
      in
      {
        ci_attribute = {
          columns = [
            (column "build_id" "int64")
            (column "attr" "string")
            (column "system" "string")
            (column "status" "string")
            (column "cached" "boolean")
            (column "abandoned" "boolean")
            (column "drv_path" "string")
            (column "outputs_out" "string")
            (column "started_at" "timestamp")
            (timeIndex "finished_at")
            (column "eval_wall_ms" "int64")
            (column "eval_alloc_bytes" "int64")
            (column "commit_sha" "string")
            (column "branch" "string")
            (column "pr_number" "int64")
            (column "project" "string")
          ];
          primaryKey = [
            "build_id"
            "attr"
          ];
          timeIndex = "finished_at";
        };
        ci_build = {
          columns = [
            (column "build_id" "int64")
            (column "created_at" "timestamp")
            (column "started_at" "timestamp")
            (timeIndex "finished_at")
            (column "eval_duration_ms" "int64")
            (column "status" "string")
            (column "pr_number" "int64")
            (column "branch" "string")
          ];
          primaryKey = [ "build_id" ];
          timeIndex = "finished_at";
        };
        batch_event = {
          columns = [
            (column "batch" "int64")
            (column "msg" "string")
            (column "build" "int64")
            (column "sha" "string")
            (column "failed_check" "string")
            (column "members" "int64")
            (column "landed" "int64")
            (column "ejected" "int64")
            (column "builds" "int64")
            (column "flaky" "boolean")
            (timeIndex "ts")
          ];
          primaryKey = [
            "batch"
            "msg"
          ];
          timeIndex = "ts";
        };
        deploy_record = {
          columns = [
            (column "host" "string")
            (column "closure" "string")
            (column "previous_closure" "string")
            (timeIndex "ts")
          ];
          primaryKey = [ "host" ];
          timeIndex = "ts";
        };
        # One row per nixbot evaluation, from its `evaluation finished`
        # journal line (modules/nixos/nixbot-evaluation-record.patch). A
        # build evaluated twice keeps two rows, told apart by ts.
        eval_run = {
          columns = [
            (column "build_id" "int64")
            (column "evaluator" "string")
            (column "evaluator_version" "string")
            (column "workers" "int64")
            (column "max_memory_mib" "int64")
            (column "memory_max_bytes" "int64")
            (column "memory_peak_bytes" "int64")
            (column "oom_kill" "int64")
            (column "wall_ms" "int64")
            (column "user_ms" "int64")
            (column "system_ms" "int64")
            (column "budget_kills" "int64")
            (column "worker_kills" "int64")
            (column "exit_status" "int64")
            (timeIndex "ts")
          ];
          primaryKey = [ "build_id" ];
          timeIndex = "ts";
        };
      };

    # The agent-session allow-list (agent-session-telemetry design D3, D5):
    # the only declaration of what Claude Code and omp sessions may send from
    # an agent-telemetry host's loopback receiver, and of the columns of
    # agent.session_event. The agent role renders from it the collector's
    # service, name and key filters; flake.lib.agentSessionStore renders the
    # table's DDL and ingest pipeline; checks.x86_64-linux.otel-collector-config
    # compares the collector's key lists with it. Anything not listed is
    # dropped on the host, and again by the store's pipeline.
    agentSession =
      let
        # The resource keys both pipelines keep; `user.name` is the person
        # the emitter stamps (design D4). The collector then stamps host.name.
        resourceKeys = [
          "service.name"
          "service.version"
          "host.arch"
          "os.type"
          "user.name"
        ];
        column = name: type: key: {
          inherit name type;
          nullable = true;
          source.log = key;
        };
        resource = name: key: {
          inherit name;
          type = "string";
          nullable = true;
          source.resource = key;
        };
        text = name: (column name "string" name) // { fulltext = true; };
      in
      {
        # Claude Code's events (claude-code-docs monitoring-usage.md:792-1470).
        # Every event keeps the correlation keys and its own keys below, each a
        # column's source; the record body is replaced by "". Dropped by not
        # being listed: api_request_body and api_response_body (raw bodies),
        # the hook, plugin, MCP-connection, auth and settings events, every
        # key a future release adds, `prompt_text` (a copy of `prompt`) and
        # `cost_usd` (a float; `cost_usd_micros` carries it).
        events = {
          services = [ "claude-code" ];
          inherit resourceKeys;
          correlationKeys = [
            "event.name"
            "event.sequence"
            "session.id"
            "prompt.id"
            "message.uuid"
            "request_id"
            "agent_id"
            "parent_agent_id"
          ];
          keys = {
            user_prompt = [
              "prompt"
              "prompt_length"
              "command_name"
              "command_source"
            ];
            assistant_response = [
              "response"
              "response_length"
              "model"
              "query_source"
            ];
            # tool_parameters and tool_input are the call's input (commands,
            # paths, arguments, about 4 K characters at most); Claude puts no
            # tool output on this event (its `tool_result_size_bytes` only):
            # the output is the trace span's tool.output (spans below).
            tool_result = [
              "tool_name"
              "tool_use_id"
              "success"
              "duration_ms"
              "error_type"
              "error"
              "decision_type"
              "decision_source"
              "tool_input_size_bytes"
              "tool_result_size_bytes"
              "tool_parameters"
              "tool_input"
            ];
            tool_decision = [
              "tool_name"
              "tool_use_id"
              "decision"
              "source"
              "tool_parameters"
            ];
            api_request = [
              "model"
              "cost_usd_micros"
              "duration_ms"
              "input_tokens"
              "output_tokens"
              "cache_read_tokens"
              "cache_creation_tokens"
              "query_source"
              "speed"
              "effort"
            ];
            api_error = [
              "model"
              "error"
              "status_code"
              "duration_ms"
              "attempt"
              "query_source"
              "speed"
              "effort"
            ];
            api_refusal = [
              "model"
              "query_source"
              "attempt"
              "speed"
              "effort"
            ];
            api_retries_exhausted = [
              "model"
              "error"
              "status_code"
              "speed"
            ];
            compaction = [
              "success"
              "duration_ms"
              "error"
            ];
            subagent_completed = [
              "model"
              "duration_ms"
            ];
            skill_activated = [ ];
          };
        };

        # Claude Code's eight metrics and omp's two (ADR-004:85), each point
        # keeping only these keys, so no session, prompt or account
        # identifier labels a series. `user.name` stays on the resource,
        # which the ingress promotes for `agent` only.
        metrics = {
          services = [
            "claude-code"
            "oh-my-pi"
          ];
          inherit resourceKeys;
          promotedResourceAttributes = [ "user.name" ];
          names = [
            "claude_code.session.count"
            "claude_code.lines_of_code.count"
            "claude_code.pull_request.count"
            "claude_code.commit.count"
            "claude_code.cost.usage"
            "claude_code.token.usage"
            "claude_code.code_edit_tool.decision"
            "claude_code.active_time.total"
            "omp.agent.tool.calls"
            "omp.agent.errors"
          ];
          pointKeys = [
            "model"
            "type"
            "query_source"
            "speed"
            "effort"
            "agent.name"
            "skill.name"
            "plugin.name"
            "marketplace.name"
            "mcp_server.name"
            "mcp_tool.name"
            "tool_name"
            "decision"
            "source"
            "language"
            "start_type"
            "gen_ai.operation.name"
            "gen_ai.provider.name"
            "gen_ai.request.model"
            "gen_ai.response.service_tier"
            "gen_ai.response.finish_reason"
            "gen_ai.tool.name"
            "omp.tool.status"
            "omp.gen_ai.agent.name"
            "error.type"
          ];
        };

        # Claude Code's and omp's spans (design D13, D15): the services, span
        # keys and resource keys traces/agent-session keeps, each span key
        # with the store type of its agent.agent_span column.
        # `last_user_message` is not sent by omp: on a step-0 chat span of a
        # top-level, non-oneshot run with native tools, the host copies it
        # from the newest user message of `gen_ai.input.messages`
        # (promptSource), which it then drops with every other unlisted key,
        # since that attribute holds the whole history on every request.
        # Tool output is kept (design D15): omp's `gen_ai.tool.call.result`
        # as sent, and Claude's, which exists only as the `tool.output` span
        # event (toolOutput), copied onto its span under the same key before
        # every span event is dropped. Claude's span keys follow
        # monitoring-usage.md's span tables; `success` is a boolean there.
        spans = {
          services = [
            "claude-code"
            "oh-my-pi"
          ];
          resourceKeys = [
            "service.name"
            "service.version"
            "user.name"
          ];
          promptSource = "gen_ai.input.messages";
          toolOutput = {
            event = "tool.output";
            # Read and Write's `content`, Edit's `diff`, Bash, MCP and web
            # tools' `output`: one per event; a later one wins.
            attributes = [
              "diff"
              "content"
              "output"
            ];
            key = "gen_ai.tool.call.result";
          };
          keys = {
            "gen_ai.operation.name" = "string";
            "gen_ai.provider.name" = "string";
            "gen_ai.request.model" = "string";
            "gen_ai.response.model" = "string";
            "gen_ai.conversation.id" = "string";
            "gen_ai.agent.name" = "string";
            "gen_ai.tool.name" = "string";
            "gen_ai.tool.call.id" = "string";
            "gen_ai.tool.call.arguments" = "string";
            "gen_ai.tool.call.result" = "string";
            "gen_ai.usage.input_tokens" = "int64";
            "gen_ai.usage.output_tokens" = "int64";
            "gen_ai.usage.cache_read.input_tokens" = "int64";
            "gen_ai.usage.cache_creation.input_tokens" = "int64";
            "omp.gen_ai.tool.status" = "string";
            # omp's oneshot requests (compaction, handoff, startup
            # summaries): which one a span is (darwin-agent-session-telemetry
            # design D8).
            "omp.gen_ai.oneshot.kind" = "string";
            "error.type" = "string";
            "gen_ai.output.messages" = "string";
            last_user_message = "string";
            # Claude Code's spans.
            "session.id" = "string";
            user_prompt = "string";
            tool_name = "string";
            tool_use_id = "string";
            full_command = "string";
            file_path = "string";
            duration_ms = "int64";
            success = "boolean";
            error = "string";
            input_tokens = "int64";
            output_tokens = "int64";
            cache_read_tokens = "int64";
            cache_creation_tokens = "int64";
          };
          # Claude's commands land in `full_command`, both harnesses' tool
          # arguments in `gen_ai.tool.call.arguments`.
          fulltext = [
            "last_user_message"
            "gen_ai.output.messages"
            "gen_ai.tool.call.result"
            "user_prompt"
            "full_command"
            "gen_ai.tool.call.arguments"
          ];
          # omp's `gen_ai.tool.call.result` is JSON.stringify of the whole
          # tool result: `content` (what the model saw), then `details`, a
          # re-render cache for its TUI the model never sees (bash's shell
          # trace with a base64 copy of the parsed command and the expanded
          # argv, env and stdout; edit's whole-file snapshots; eval's, MCP's
          # and the browser's image and raw-value copies), then `isError`
          # and `useless` when true (omp 19.1.0
          # packages/coding-agent/src/tools/tool-result.ts:104-108,
          # packages/agent/src/telemetry.ts:1132-1138; design D15, A208).
          # On its spans only (Claude Code's plain text lands in the same
          # key), before the cut, `strip` drops everything from the
          # `details` key that follows `content` to the end but a final
          # `isError`, without parsing: an unescaped `],"details":` cannot
          # occur inside a JSON string, so the first one is the key. A
          # result still holding a `details` key after that (`detailsKey`:
          # a key follows `{` or `,`, which no string can hold before an
          # unescaped quote) becomes `withheld` whole, so a changed key
          # order cannot reopen the hole.
          toolResult = {
            service = "oh-my-pi";
            strip = ''\],"details":[\s\S]*?(,"isError":true)?(,"useless":true)?\}$'';
            detailsKey = ''[{,]\s*"details"\s*:'';
            withheld = "[tool result withheld: its details could not be stripped]";
          };
          table = "agent_span";
        };

        # Langfuse Cloud, the second destination of the agent spans
        # (agent-session-telemetry design D16), fed after every allow-list,
        # cut and mask above. Its OTLP contract: traces only, HTTP only, at
        # <endpoint>/v1/traces, with HTTP Basic auth (public key, secret key)
        # and the ingestion-version header, each request under 5 MB (Langfuse
        # docs faq/all/api-limits.mdx:17-19; integrations/native/
        # opentelemetry/index.mdx:28-58). Its exporter retries for
        # retryMinutes and then drops: a consumer holds its batch for the
        # whole retry, so while Langfuse is down the queue drains at
        # consumers x batchBytes per retryMinutes, which the agent role
        # asserts is at least drainMultiple x agentSpanBytesPerMinute, and
        # holds at least twice the arrivals of one retry window. A full
        # queue would refuse at otlp/local and so duplicate the store's
        # spans when the emitters retry.
        langfuse = {
          endpoint = "https://cloud.langfuse.com/api/public/otel";
          # Each request's deadline, set rather than left to the exporter's
          # default, so a hanging server holds a consumer for at most this
          # per try (review follow-up 5).
          timeout = "30s";
          ingestionVersion = "4";
          requestLimitBytes = 5000000;
          retryMinutes = 5;
          consumers = 10;
          batchBytes = 3 * 1024 * 1024;
          queueBytes = 32 * 1024 * 1024;
          drainMultiple = 10;
          # Claude Code's span that, after the allow-list, carries only a
          # duration: one billable unit per tool call and nothing to read.
          droppedSpans = [ "claude_code.tool.blocked_on_user" ];
          # omp's startup requests, which summarise the session's skills
          # and MCP namespaces on a small model: noise in Langfuse, still
          # stored (darwin-agent-session-telemetry design D8). Every other
          # oneshot kind is sent.
          droppedOneshotKinds = [
            "skill_description"
            "mcp_namespace_hint"
          ];
          # Claude Code's bare token counts, under the names Langfuse reads.
          usageKeys = {
            input_tokens = "gen_ai.usage.input_tokens";
            output_tokens = "gen_ai.usage.output_tokens";
            cache_read_tokens = "gen_ai.usage.cache_read.input_tokens";
            cache_creation_tokens = "gen_ai.usage.cache_creation.input_tokens";
          };
        };

        # Credential shapes masked to `****` in every kept string of spans
        # (their status message too) and events, after the allow-lists and
        # the 64 KiB cut (design D15): RE2, one alternative each, from
        # gitleaks 8.30.1's rules for these issuers, loosened to the token's
        # prefix and alphabet. They catch token-shaped strings only, never
        # every secret: a password, an AWS secret access key or any
        # credential without a fixed prefix passes. The `sk-`, `sk_` and
        # `rk_` shapes take no word boundary: in a JSON-encoded value a key
        # at the start of a line follows the letter of `\n` or `\t`, and
        # after a colour code the `m` of `[32m`, so a boundary would leave
        # it. They are precise in the body instead, each at its issuer's
        # length: Anthropic's `sk-ant-<version>-` and 93 characters and
        # `AA` (gitleaks anthropic-api-key, anthropic-admin-api-key), so 95
        # or more after `sk-ant-`; OpenAI's project, service-account and
        # admin keys 58 or 74 characters, `T3BlbkFJ`, then 58 or 74
        # (gitleaks openai-api-key), so 124 or more, and its legacy key 48
        # alphanumerics; Langfuse's `sk-lf-` and a UUID (langfuse
        # packages/shared/src/server/auth/apiKeys.ts:81, `randomUUID()`);
        # Stripe's secret and restricted keys 24 or more alphanumerics
        # (gitleaks stripe-access-token allows 10 to 99). So
        # `task_test_configuration` (13 after `sk_test_`) and
        # `risk-admin-dashboard-components` are stored as written; a word
        # holding `sk-` and 48 alphanumerics, or `sk_test_` and 24, is
        # masked. A private key whose END line
        # is missing (cut at 64 KiB, say) is masked up to the next
        # unescaped double quote or the end of the value: in a JSON-encoded
        # value that is the end of the string holding it, so the JSON stays
        # whole. A length bound cannot cover a key: Go's RE2 refuses any
        # repeat above 1,000, nested ones multiplied, and an RSA key's body
        # is longer.
        credentialPatterns = {
          private-key = "-----BEGIN[ A-Z0-9_-]{0,100}PRIVATE KEY(?: BLOCK)?-----(?:[\\s\\S]*?-----END[ A-Z0-9_-]{0,100}PRIVATE KEY(?: BLOCK)?-----|(?:[^\"\\\\]|\\\\[^\"])*)";
          age-secret-key = "AGE-SECRET-KEY-1[QPZRY9X8GF2TVDW0S3JN54KHCE6MUA7L]{58}";
          anthropic = "sk-ant-[A-Za-z0-9_-]{95,}";
          openai = "sk-(?:proj|svcacct|admin)-[A-Za-z0-9_-]{124,}|sk-[A-Za-z0-9]{48}";
          langfuse = "sk-lf-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
          github = "(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,}";
          gitlab = "glpat-[A-Za-z0-9_-]{20,}";
          npm = "npm_[A-Za-z0-9]{36}";
          pypi = "pypi-AgEIcHlwaS5vcmc[A-Za-z0-9_-]{50,}";
          linear = "lin_api_[A-Za-z0-9]{40}";
          aws-access-key-id = "(?:A3T[A-Z0-9]|AKIA|ASIA|ABIA|ACCA)[A-Z2-7]{16}";
          gcp-api-key = "AIza[A-Za-z0-9_-]{35}";
          digitalocean = "do[opr]_v1_[a-f0-9]{64}";
          slack = "xox[abeoprs]-[A-Za-z0-9-]{10,}|xapp-[0-9]-[A-Za-z0-9-]{10,}|hooks\\.slack\\.com/(?:services|workflows|triggers)/[A-Za-z0-9/_+-]{20,}";
          stripe = "(?:sk|rk)_(?:test|live|prod)_[A-Za-z0-9]{24,}";
          jwt = "eyJ[A-Za-z0-9_-]{8,}\\.eyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]*";
          bearer = "(?i:bearer)\\s+[A-Za-z0-9._~+/=-]{16,}";
        };

        # Encoded blobs, masked to `****` in the same strings after the
        # credential shapes (design D15): a run of 129 or more characters of
        # base64's standard alphabet (`+` and `/`), with its padding, or of
        # its URL-safe alphabet (`-` and `_`). Two alternatives rather than
        # one merged class, so a path or URL (slashes and hyphens) is broken
        # at every hyphen for the first and at every slash for the second
        # and passes. 129 spares a sha512 in hex (128) and everything shorter
        # (git and Nix hashes, UUIDs, sha256), and hides images, encrypted
        # reasoning and any other encoded copy; a shorter blob, or a run the
        # 64 KiB cut ends after fewer than 129 characters, passes. A path
        # segment or dotless identifier of 129 characters in one alphabet is
        # masked too.
        encodedBlobPattern = "[A-Za-z0-9+/]{129,}={0,2}|[A-Za-z0-9_-]{129,}";

        # agent.session_event: one row per admitted event, the time index the
        # record's own Timestamp; non-append, so an exporter's replay of a
        # batch the store already took collapses on the primary key (design
        # D5). No ttl of its own: agent's applies.
        tables.session_event = {
          columns = [
            {
              name = "ts";
              type = "timestamp";
              nullable = false;
              source.record = "Timestamp";
            }
            (resource "host_name" "host.name")
            (resource "user_name" "user.name")
            (resource "service_name" "service.name")
            (resource "service_version" "service.version")
            (column "session_id" "string" "session.id")
            (column "prompt_id" "string" "prompt.id")
            (column "event_name" "string" "event.name")
            (column "event_sequence" "int64" "event.sequence")
            (column "message_uuid" "string" "message.uuid")
            (column "request_id" "string" "request_id")
            (column "agent_id" "string" "agent_id")
            (column "parent_agent_id" "string" "parent_agent_id")
            (column "model" "string" "model")
            (column "query_source" "string" "query_source")
            (text "prompt")
            (column "prompt_length" "int64" "prompt_length")
            (column "command_name" "string" "command_name")
            (column "command_source" "string" "command_source")
            (text "response")
            (column "response_length" "int64" "response_length")
            (column "tool_name" "string" "tool_name")
            (column "tool_use_id" "string" "tool_use_id")
            (column "success" "boolean" "success")
            (column "duration_ms" "int64" "duration_ms")
            (column "error_type" "string" "error_type")
            (column "error" "string" "error")
            (column "decision" "string" "decision")
            (column "decision_type" "string" "decision_type")
            (column "decision_source" "string" "decision_source")
            (column "source" "string" "source")
            (column "tool_input_size_bytes" "int64" "tool_input_size_bytes")
            (column "tool_result_size_bytes" "int64" "tool_result_size_bytes")
            (column "tool_parameters" "string" "tool_parameters")
            (column "tool_input" "string" "tool_input")
            (column "cost_usd_micros" "int64" "cost_usd_micros")
            (column "input_tokens" "int64" "input_tokens")
            (column "output_tokens" "int64" "output_tokens")
            (column "cache_read_tokens" "int64" "cache_read_tokens")
            (column "cache_creation_tokens" "int64" "cache_creation_tokens")
            (column "status_code" "int64" "status_code")
            (column "attempt" "int64" "attempt")
            (column "speed" "string" "speed")
            (column "effort" "string" "effort")
          ];
          primaryKey = [
            "host_name"
            "session_id"
            "event_sequence"
          ];
          timeIndex = "ts";
        };
      };
  };
}
