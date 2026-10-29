# The fleet alert rule table (ADR-009 Decision items 2, 5, 7, 14; design
# D10, D14, D16; tasks.md 4.1).
#
# One Nix source for the evaluator and for promtool. fleetAlertRules returns
# `rules`; `json`, the evaluator's rule list with `for` in seconds; and
# `yaml`, a Prometheus rules file of the `promql` rules, written as
# JSON (which YAML accepts) and read only by checks.x86_64-linux.fleet-alert's
# promtool pass. The expressions are ADR-009's rule table as amended
# (ADR-009-alerting.md:102-119), measured on magnetite on 2026-10-18
# (logs/s3/series-labels.md): each carries its threshold, because an instant
# query returns every input series otherwise, and SystemdUnitFailed writes
# its literal dot as `[.]`, because GreptimeDB 1.2.1 rejects `\.` in
# double-quoted and backtick strings, so no expression may contain a
# backslash. SystemdUnitFailed excludes the union of every host's
# notifiedUnits in `hosts`, flake.lib.observabilityHosts by default, so the
# notifier and the rule never report one failure twice on any host (S4
# design D9).
#
# StoreQueryFailing and RuleSignalMissing have no expression: transition.jq
# raises them, and they are listed so their `for` lives in this one table.
# The expected host is magnetite alone until S4 brings other hosts' series.
# RuleSignalMissing's `alwaysOn` lists the hosts whose own silence it
# reports: one absent from system_memory_usage_bytes for 10 min while the
# store answers raises it with that host_name and no `for` (ADR-009 item 16,
# charter v20).
#
# Every rule but StoreQueryFailing carries `database` (default "fleet") and
# `language` ("promql", the default, or "sql"); the evaluator sends a promql
# rule to the PromQL API with x-greptime-db-name and an sql rule as POST
# /v1/sql?db=<database> (stand-up-devloop-collection design D2).
# StoreQueryFailing has no database of its own: transition.jq raises one
# instance per failing database (review F7). RuleSignalMissing's `database`
# is the one the evaluator reads system_memory_usage_bytes from, the
# selector `reporting` comes from. PullRequestQueueWaitBurn (design D1)
# reads devloop's ci_build in SQL, which promtool cannot parse;
# vmTests.x86_64-linux.devloop-ingest's burnRule case runs it on GreptimeDB
# 1.2.1.
{ config, ... }:
{
  flake.lib.fleetAlertRules =
    {
      lib,
      hosts ? config.flake.lib.observabilityHosts,
    }:
    let
      presence = selector: {
        inherit selector;
        expectedHosts = [ "magnetite" ];
      };

      # Appended to HostMemoryPressure and HostOOMKill messages (ADR-009 item
      # 5); the evaluator substitutes the firing host for <host>.
      memoryAttribution = [
        {
          name = "top 3 executables by resident memory, which omits swapped-out pages";
          query = ''topk(3, process_memory_usage_bytes{host_name="<host>"})'';
          label = "process_executable_name";
        }
        {
          name = "ZFS ARC size";
          query = ''node_zfs_arc_size{host_name="<host>"}'';
          label = null;
        }
        {
          name = "swap used";
          query = ''sum(system_paging_usage_bytes{host_name="<host>", state="used"})'';
          label = null;
        }
      ];

      units = lib.unique (
        lib.naturalSort (lib.concatMap (h: h.notifiedUnits) (builtins.attrValues hosts))
      );
      notifiedRegex =
        assert lib.assertMsg (lib.all (unit: builtins.match "[A-Za-z0-9_-]+" unit != null) units)
          "fleetAlertRules: notified unit names must match [A-Za-z0-9_-]+, so the exclusion needs no escape; got ${builtins.toJSON units}";
        "(${lib.concatStringsSep "|" units})[.]service";

      rule =
        r:
        {
          presence = [ ];
          attribution = [ ];
        }
        // lib.optionalAttrs (r.alert != "StoreQueryFailing") {
          database = "fleet";
          language = "promql";
        }
        // r;

      rules = map rule [
        {
          alert = "HostMemoryPressure";
          expr = ''((sum by (host_name) (system_linux_memory_available_bytes) + sum by (host_name) (node_zfs_arc_size - node_zfs_arc_c_min)) / (sum by (host_name) (system_memory_usage_bytes{state="used"}) + sum by (host_name) (system_linux_memory_available_bytes)) < 0.10) or (sum by (host_name) (system_paging_usage_bytes{state="used"}) / sum by (host_name) (system_paging_usage_bytes) > 0.85)'';
          for = "5m";
          severity = "warning";
          annotations.summary = "Available memory, counting the ZFS ARC above its minimum, is below 10 % of total, or swap use is above 85 %";
          presence = map presence [
            "system_linux_memory_available_bytes"
            "node_zfs_arc_size"
            "system_memory_usage_bytes"
            "system_paging_usage_bytes"
          ];
          attribution = memoryAttribution;
        }
        {
          alert = "HostOOMKill";
          expr = "increase(node_vmstat_oom_kill[10m]) > 0";
          for = "0s";
          severity = "critical";
          annotations.summary = "The kernel killed a process for memory in the last 10 min";
          presence = [ (presence "node_vmstat_oom_kill") ];
          attribution = memoryAttribution;
        }
        {
          alert = "ZfsPoolUnhealthy";
          expr = ''node_zfs_zpool_state{state!="online"} == 1'';
          for = "1m";
          severity = "critical";
          annotations.summary = "A ZFS pool is not online";
          presence = [ (presence "node_zfs_zpool_state") ];
        }
        {
          alert = "SystemdUnitRestartLoop";
          expr = "increase(systemd_service_restarts_total[15m]) > 5";
          for = "0s";
          severity = "warning";
          annotations.summary = "A unit restarted more than 5 times in 15 min";
          presence = [ (presence "systemd_service_restarts_total") ];
        }
        {
          alert = "SystemdUnitFailed";
          expr = ''systemd_unit_state{systemd_unit_active_state="failed", systemd_unit_name!~"${notifiedRegex}"} == 1'';
          for = "5m";
          severity = "warning";
          annotations.summary = "A unit the failure notifier does not report has failed";
          presence = [ (presence "systemd_unit_state") ];
        }
        {
          alert = "LocalExporterDown";
          expr = ''up{job=~"node|smartctl"} == 0'';
          for = "10m";
          severity = "warning";
          annotations.summary = "A loopback exporter the collector scrapes is down";
          presence = [ (presence ''up{job="node"}'') ];
        }
        {
          alert = "WeeklyPipelineTest";
          expr = "count(count by (host_name) (system_memory_usage_bytes))";
          for = "0s";
          severity = "info";
          annotations.summary = "Weekly test of the alert path: the value is the number of hosts reporting host memory";
          presence = [ (presence "system_memory_usage_bytes") ];
          window = {
            zone = "America/New_York";
            weekday = 1;
            start = "09:00";
            end = "09:05";
          };
        }
        {
          alert = "PullRequestQueueWaitBurn";
          database = "devloop";
          language = "sql";
          expr = "SELECT CAST(sum(CASE WHEN c.started_at > c.created_at + INTERVAL '1 hour' THEN 1 ELSE 0 END) AS DOUBLE) / count(*) AS value FROM ci_build c JOIN (SELECT build_id, min(finished_at) AS first_finished FROM ci_build GROUP BY build_id) f ON c.build_id = f.build_id AND c.finished_at = f.first_finished WHERE c.pr_number IS NOT NULL AND c.started_at IS NOT NULL AND c.finished_at >= now() - INTERVAL '24 hours' HAVING count(*) >= 10 AND sum(CASE WHEN c.started_at > c.created_at + INTERVAL '1 hour' THEN 1 ELSE 0 END) * 10 > count(*)";
          for = "1h";
          severity = "warning";
          annotations.summary = "More than one in ten of the at least 10 pull-request builds whose first attempt finished in the last 24 h waited over an hour to start; the value is that share";
        }
        {
          alert = "StoreQueryFailing";
          for = "3m";
          severity = "critical";
          annotations.summary = "The telemetry store has not answered the evaluator's queries on the database named below for 3 min; the alert instances on that database are frozen, and those on other databases are evaluated as usual";
        }
        {
          alert = "RuleSignalMissing";
          for = "30m";
          severity = "warning";
          annotations.summary = "A rule's presence selector returned no series while an expected host reported host memory, so the rule cannot fire; with host_name, that always-on host has reported no host memory for 10 min while the store answers";
          alwaysOn = [ "magnetite" ];
        }
      ];

      seconds =
        duration:
        let
          m = builtins.match "([0-9]+)([smh])" duration;
        in
        assert lib.assertMsg (
          m != null
        ) "fleetAlertRules: `for` must be <n>s, <n>m or <n>h, got ${duration}";
        lib.toInt (builtins.head m)
        * {
          s = 1;
          m = 60;
          h = 3600;
        }
        .${builtins.elemAt m 1};

      promRule = r: {
        inherit (r)
          alert
          expr
          for
          annotations
          ;
        labels.severity = r.severity;
      };
    in
    {
      inherit rules;
      json = builtins.toJSON (map (r: r // { for = seconds r.for; }) rules);
      yaml = builtins.toJSON {
        groups = [
          {
            name = "fleet-alert";
            rules = map promRule (builtins.filter (r: r ? expr && r.language == "promql") rules);
          }
        ];
      };
    };
}
