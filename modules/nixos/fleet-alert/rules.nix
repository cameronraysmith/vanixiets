# The fleet alert rule table (ADR-009 Decision items 2, 5, 7, 14; design
# D10, D14, D16; tasks.md 4.1).
#
# One Nix source for the evaluator and for promtool. fleetAlertRules returns
# `rules`; `json`, the evaluator's rule list with `for` in seconds; and
# `yaml`, a Prometheus rules file of the rules with an expression, written as
# JSON (which YAML accepts) and read only by checks.x86_64-linux.fleet-alert's
# promtool pass. The expressions are ADR-009's rule table as amended
# (ADR-009-alerting.md:102-119), measured on magnetite on 2026-10-18
# (logs/s3/series-labels.md): each carries its threshold, because an instant
# query returns every input series otherwise, and SystemdUnitFailed writes
# its literal dot as `[.]`, because GreptimeDB 1.2.1 rejects `\.` in
# double-quoted and backtick strings, so no expression may contain a
# backslash. SystemdUnitFailed excludes `notifiedUnits`, the evaluating
# host's services.observability-notify.units, so the notifier and the rule
# never report one failure twice (D10); when S4 adds notified units on other
# hosts, this must become their union (design D10, "Later slices").
#
# StoreQueryFailing and RuleSignalMissing have no expression: transition.jq
# raises them, and they are listed so their `for` lives in this one table.
# The expected host is magnetite alone until S4 brings other hosts' series.
{
  flake.lib.fleetAlertRules =
    { lib, notifiedUnits }:
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

      units = lib.unique (lib.naturalSort notifiedUnits);
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
          alert = "StoreQueryFailing";
          for = "3m";
          severity = "critical";
          annotations.summary = "The telemetry store has not answered the evaluator's queries; every other alert instance is frozen";
        }
        {
          alert = "RuleSignalMissing";
          for = "30m";
          severity = "warning";
          annotations.summary = "A rule's presence selector returned no series while an expected host reported host memory, so the rule cannot fire";
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
            rules = map promRule (builtins.filter (r: r ? expr) rules);
          }
        ];
      };
    };
}
