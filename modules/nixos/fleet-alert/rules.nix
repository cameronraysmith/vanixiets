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
# Every rule's expected hosts and RuleSignalMissing's `alwaysOn` come from
# `hosts`, flake.lib.observabilityHosts by default (S4 design D9), among the
# hosts that collect, by each host's `platform`: HostMemoryPressure,
# HostOOMKill, ZfsPoolUnhealthy, SystemdUnitRestartLoop and
# SystemdUnitFailed expect the NixOS hosts, whose selectors darwin never
# writes; the file-system rules, LocalExporterDown and WeeklyPipelineTest
# expect every collecting host; the NVMe rules expect the hosts with SMART
# devices; the three launchd rules expect the darwin hosts (S5 design D9),
# and HostProbeStale the hosts with a textfile writer, every collecting
# darwin host and each NixOS host whose row's `textfile` is set (F76);
# GarbageCollectionOverrun expects its launchd arm's selector
# on the darwin hosts and its systemd arm's on the NixOS hosts
# (bound-fleet-garbage-collection D7). LaunchdJobNotRunning expects running the kept-alive labels of
# flake.lib.otelCollectorSchema.launchdKeptAlive and reports any other
# allow-listed label unloaded; its two arms select disjoint labels, because
# the probe writes all four states for every label, so a kept-alive label
# unloaded, running 0 and unloaded 1, is one instance, not two (tasks.md
# 8.3a). LaunchdJobFailed excludes the darwin hosts'
# notifiedUnits as org.nixos.<unit>, which post their own notices, so one
# failure is reported once; a kept-alive job's abnormal last exit stays
# launchd's last exit while the relaunched job runs, so its arm counts it
# only while the job's run count rose in the last 30 min, and the instance
# resolves once the job has run that long (CAM-92). `alwaysOn` lists the
# collecting hosts marked always-on, whose own silence it reports: one absent from
# system_memory_usage_bytes for 10 min while the store answers raises it
# with that host_name and no `for` (ADR-009 item 16, charter v20).
#
# Every rule but StoreQueryFailing carries `database` (default "fleet") and
# `language` ("promql", the default, or "sql"); the evaluator sends a promql
# rule to the PromQL API with x-greptime-db-name and an sql rule as POST
# /v1/sql?db=<database> (stand-up-devloop-collection design D2).
# StoreQueryFailing has no database of its own: transition.jq raises one
# instance per failing database (review F7). RuleSignalMissing's `database`
# is the one the evaluator reads system_memory_usage_bytes from, the
# selector `reporting` comes from. PullRequestQueueWaitBurn (design D1)
# and IetsEvaluationUnhealthy read devloop's ci_build and eval_run in SQL,
# which promtool cannot parse; vmTests.x86_64-linux.devloop-ingest's
# burnRule and ietsHealthRule cases run them on GreptimeDB 1.2.1.
{ config, ... }:
{
  flake.lib.fleetAlertRules =
    {
      lib,
      hosts ? config.flake.lib.observabilityHosts,
      # A parameter so checks.x86_64-linux.fleet-alert can render the rule
      # with a fixture bucket listed (track-r2-usage design D8).
      r2ExternalBuckets ? config.flake.lib.r2Usage.externalBuckets,
    }:
    let
      # A host is expected, or always-on, only once it collects (S4 design
      # D6, D9), and only for the selectors its platform writes (design D9):
      # darwin writes no available memory, paging, ZFS, OOM or systemd series.
      collecting = lib.filterAttrs (_: h: h.collect) hosts;
      onPlatform = p: builtins.attrNames (lib.filterAttrs (_: h: h.platform == p) collecting);
      agentHosts = builtins.attrNames collecting;
      nixosHosts = onPlatform "nixos";
      darwinHosts = onPlatform "darwin";
      smartHosts = builtins.attrNames (lib.filterAttrs (_: h: h.smartDevices != [ ]) collecting);
      # Every collecting darwin host's probe writes a textfile; a NixOS host
      # does where its row's `textfile` says so, which
      # modules/nixos/node-exporter-textfile.nix asserts against the host's
      # registered textfile writers (F76).
      textfileHosts = builtins.attrNames (
        lib.filterAttrs (_: h: h.platform == "darwin" || h.textfile) collecting
      );
      presence = expectedHosts: selector: { inherit selector expectedHosts; };
      fsRatio = ''sum by (host_name, mountpoint) (system_filesystem_usage_bytes{state="used"}) / sum by (host_name, mountpoint) (system_filesystem_usage_bytes)'';
      # Each dot written [.], as notifiedRegex below.
      launchdRegex =
        labels: lib.concatMapStringsSep "|" (builtins.replaceStrings [ "." ] [ "[.]" ]) labels;
      keptAlive = launchdRegex config.flake.lib.otelCollectorSchema.launchdKeptAlive;
      selfNotified = launchdRegex (
        map (unit: "org.nixos.${unit}") (
          lib.unique (
            lib.naturalSort (
              lib.concatMap (h: h.notifiedUnits) (
                builtins.attrValues (lib.filterAttrs (_: h: h.platform == "darwin") hosts)
              )
            )
          )
        )
      );
      r2 = config.flake.lib.r2Usage;
      # Billing-period projection (track-r2-usage design D4): the operations
      # so far times the period's length over the time elapsed, the elapsed
      # time at least a day, so the first hours of a period do not multiply
      # a handful of operations into a warning.
      r2Projection = "scalar(max(vanixiets_r2_billing_period_end_timestamp_seconds) - max(vanixiets_r2_billing_period_start_timestamp_seconds)) / scalar(clamp_min(time() - max(vanixiets_r2_billing_period_start_timestamp_seconds), 86400))";
      r2ClassProjected =
        class: limit:
        ''sum by (class) (vanixiets_r2_operations{class="${class}"}) * ${r2Projection} > ${toString limit}'';

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
          presence = map (presence nixosHosts) [
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
          presence = [ (presence nixosHosts "node_vmstat_oom_kill") ];
          attribution = memoryAttribution;
        }
        {
          alert = "ZfsPoolUnhealthy";
          expr = ''node_zfs_zpool_state{state!="online"} == 1'';
          for = "1m";
          severity = "critical";
          annotations.summary = "A ZFS pool is not online";
          presence = [ (presence nixosHosts "node_zfs_zpool_state") ];
        }
        {
          alert = "FilesystemFillingWarn";
          expr = fsRatio + " > 0.85";
          for = "15m";
          severity = "warning";
          annotations.summary = "A file system is more than 85 % full";
          presence = [ (presence agentHosts "system_filesystem_usage_bytes") ];
        }
        {
          alert = "FilesystemFull";
          expr = fsRatio + " > 0.95";
          for = "5m";
          severity = "critical";
          annotations.summary = "A file system is more than 95 % full";
          presence = [ (presence agentHosts "system_filesystem_usage_bytes") ];
        }
        # smartctl_exporter declares these fields counters, and the store
        # names an OTLP Sum with `_total`.
        {
          alert = "NvmeCriticalWarning";
          expr = "smartctl_device_critical_warning_total != 0";
          for = "0s";
          severity = "critical";
          annotations.summary = "A laptop's NVMe controller reports a critical warning";
          presence = [ (presence smartHosts "smartctl_device_critical_warning_total") ];
        }
        {
          alert = "NvmeWearHigh";
          expr = "smartctl_device_percentage_used_total > 90";
          for = "1h";
          severity = "warning";
          annotations.summary = "A laptop's SSD has used more than 90 % of its rated endurance";
          presence = [ (presence smartHosts "smartctl_device_percentage_used_total") ];
        }
        {
          alert = "LaunchdJobNotRunning";
          expr = ''launchd_job_state{launchd_state="running", launchd_label=~"${keptAlive}"} == 0 or launchd_job_state{launchd_state="unloaded", launchd_label!~"${keptAlive}"} == 1'';
          for = "10m";
          severity = "warning";
          annotations.summary = "A kept-alive launchd job is not running, or an allow-listed job is not loaded";
          presence = [ (presence darwinHosts "launchd_job_state") ];
        }
        {
          alert = "LaunchdJobFailed";
          expr = ''launchd_job_last_exit_code{launchd_label!~"${selfNotified}|${keptAlive}"} != 0 or (launchd_job_last_exit_code{launchd_label=~"${keptAlive}", launchd_label!~"${selfNotified}"} != 0 and on (host_name, launchd_label) increase(launchd_job_runs_total[30m]) > 0)'';
          for = "5m";
          severity = "warning";
          annotations.summary = "A launchd job's last exit was not clean";
          presence = [ (presence darwinHosts "launchd_job_last_exit_code") ];
        }
        {
          alert = "LaunchdJobRestartLoop";
          expr = "increase(launchd_job_runs_total[15m]) > 5";
          for = "0s";
          severity = "warning";
          annotations.summary = "A launchd job relaunched more than five times in 15 minutes";
          presence = [ (presence darwinHosts "launchd_job_runs_total") ];
        }
        # bound-fleet-garbage-collection D7: harmonia-gc still running an
        # hour after it started, which a wait on gc.lock causes; its 2 h
        # bound then ends it and LaunchdJobFailed or SystemdUnitFailed reports
        # that. A oneshot unit is `activating` while it runs.
        {
          alert = "GarbageCollectionOverrun";
          expr = ''launchd_job_state{launchd_label="org.nixos.harmonia-gc", launchd_state="running"} == 1 or systemd_unit_state{systemd_unit_name="harmonia-gc.service", systemd_unit_active_state="activating"} == 1'';
          for = "60m";
          severity = "warning";
          annotations.summary = "harmonia-gc has been running for over an hour, likely waiting for the store lock; its 2 h bound will end it";
          presence = [
            (presence darwinHosts "launchd_job_state")
            (presence nixosHosts "systemd_unit_state")
          ];
        }
        # F76: every host with a textfile writer, the darwin probe's and the
        # NixOS probes' named in vanixiets.nodeExporter.textfileWriters.
        {
          alert = "HostProbeStale";
          expr = "time() - node_textfile_mtime_seconds > 300 or node_textfile_scrape_error == 1";
          for = "10m";
          severity = "warning";
          annotations.summary = "A host's textfile probe has stopped writing its textfile, or node_exporter cannot read it";
          presence = [ (presence textfileHosts "node_textfile_mtime_seconds") ];
        }
        # F77: systemd's restart counter (NRestarts) holds its value while
        # the unit stays failed and resets when it is next started by hand,
        # so the second arm keeps a looping unit that systemd gave up on
        # firing until it is started again. On 2026-11-18 node_exporter
        # restarted from 22:05 to 22:15 and stayed failed until 22:38, and
        # the first arm alone sent RESOLVED at 22:28, when its 15 min window
        # emptied. Both arms keep only host_name and systemd_unit_name, so
        # the instance is the same while either holds.
        {
          alert = "SystemdUnitRestartLoop";
          expr = ''max by (host_name, systemd_unit_name) (increase(systemd_service_restarts_total[15m])) > 5 or on (host_name, systemd_unit_name) max by (host_name, systemd_unit_name) (systemd_unit_state{systemd_unit_active_state="failed"} == 1 and on (host_name, systemd_unit_name) systemd_service_restarts_total > 5)'';
          for = "0s";
          severity = "warning";
          annotations.summary = "A unit restarted more than 5 times in 15 min, or did so and is still failed";
          presence = [ (presence nixosHosts "systemd_service_restarts_total") ];
        }
        {
          alert = "SystemdUnitFailed";
          expr = ''systemd_unit_state{systemd_unit_active_state="failed", systemd_unit_name!~"${notifiedRegex}"} == 1'';
          for = "5m";
          severity = "warning";
          annotations.summary = "A unit the failure notifier does not report has failed";
          presence = [ (presence nixosHosts "systemd_unit_state") ];
        }
        {
          alert = "LocalExporterDown";
          expr = ''up{job=~"node|smartctl"} == 0'';
          for = "10m";
          severity = "warning";
          annotations.summary = "A loopback exporter the collector scrapes is down";
          presence = [ (presence agentHosts ''up{job="node"}'') ];
        }
        # F61: on 2026-11-19 every database on magnetite recorded glibc
        # collation version 2.42 under glibc 2.44, its text indexes stale, and
        # nothing noticed until pg_dump warned. The collector's
        # sqlquery/postgresql-collation receiver (flake.lib.postgresqlCollation,
        # Q68a) emits 1 for a database whose recorded datcollversion is not null
        # and IS DISTINCT FROM pg_database_collation_actual_version(oid),
        # PostgreSQL's own connection-time check, which skips a database
        # with no recorded version, since a null is never comparable
        # (template0 has none); a deploy that bumps glibc restarts
        # PostgreSQL on the new library, so the drift shows from the deploy
        # that causes it. A parked service's database is left out by the
        # receiver (vanixiets.postgresqlCollation.parkedDatabases). One
        # instance per database; the message names it as datname, with
        # both versions. No presence selector: the host table does not say
        # which hosts run PostgreSQL; a receiver that cannot query logs its
        # error in the collector's journal and writes no series.
        #
        # Runbook: on the host, for each named database <db>, as postgres:
        #   sudo -u postgres psql -d <db> -c 'REINDEX DATABASE "<db>"' \
        #     -c 'ALTER DATABASE "<db>" REFRESH COLLATION VERSION'
        # The refresh alone hides the drift without repairing the indexes,
        # so reindex first. The instance resolves 5 min after the receiver
        # reports 0. Reviving cognee needs pgvector in PostgreSQL's
        # extensions first (F63), then this reindex.
        {
          alert = "PostgresqlCollationDrift";
          expr = "vanixiets_postgresql_collation_drift == 1";
          for = "10m";
          severity = "warning";
          annotations.summary = "A PostgreSQL database's recorded collation version differs from the system library's, so its text indexes may be stale; on the host run, as postgres, psql -d <datname> -c 'REINDEX DATABASE \"<datname>\"' -c 'ALTER DATABASE \"<datname>\" REFRESH COLLATION VERSION' (runbook in modules/nixos/fleet-alert/rules.nix)";
        }
        # back-up-postgresql-off-host design D11: restic-backups-postgresql
        # (flake.modules.nixos.postgresql-backup) records the time of each run
        # whose backup, prune and check all succeeded, and
        # postgresql-backup-metric publishes it to the textfile collector
        # every minute, seeding it with its first run's time when no record
        # exists, so a host that never completes a backup ages too. 36 h is
        # one missed night plus margin for the 15 min randomized delay and a
        # slow run. A failed run is reported by its unit's notice; this rule
        # reports runs that do not happen. No presence selector: the host
        # table does not say which hosts back up PostgreSQL.
        #
        # Runbook: packages/docs/src/content/docs/development/operations/postgresql-backup.md.
        {
          alert = "PostgresqlBackupStale";
          expr = "time() - vanixiets_postgresql_backup_last_success_timestamp_seconds > 129600";
          for = "10m";
          severity = "warning";
          annotations.summary = "No PostgreSQL backup has succeeded on this host for over 36 h; check restic-backups-postgresql's journal and timer (runbook in packages/docs/src/content/docs/development/operations/postgresql-backup.md)";
        }
        # track-r2-usage (F74, design D7): R2 keeps a multipart upload that is
        # never completed or aborted, and bills its parts as storage, until
        # a lifecycle rule aborts it; sciexp's aborts at 7 days. A day of
        # pending uploads in any bucket is a client that died mid-upload.
        # The poller writes the latest storage sample's uploadCount hourly.
        {
          alert = "R2MultipartUploadPending";
          expr = "vanixiets_r2_bucket_pending_uploads > 0";
          for = "24h";
          severity = "warning";
          annotations.summary = "An R2 bucket has held a pending multipart upload for over 24 h; list them with `aws s3api list-multipart-uploads` against the R2 endpoint and abort the stale ones, or add an abort rule to the bucket's lifecycle";
        }
        # track-r2-usage design D4: Class A and Class B projected past their
        # free tier by the end of the billing period, each a whole-million
        # step in the bill ($4.50 and $0.36) because Cloudflare rounds up,
        # and storage past flake.lib.r2Usage.storageBudgetGBMonth, holding
        # today's level for the period. One instance per class.
        {
          alert = "R2CostProjected";
          expr = "${r2ClassProjected "A" r2.freeTier.classA} or ${r2ClassProjected "B" r2.freeTier.classB} or label_replace(sum(vanixiets_r2_bucket_payload_bytes + vanixiets_r2_bucket_metadata_bytes), \"class\", \"storage\", \"\", \"\") > ${
            toString (r2.storageBudgetGBMonth * 1000000000)
          }";
          for = "1h";
          severity = "info";
          annotations.summary = "R2 usage is projected past a cost edge this billing period: class A or B operations past the free tier (${toString r2.freeTier.classA} and ${toString r2.freeTier.classB}; each further million costs \$${builtins.toJSON r2.pricing.classAPerMillion} or \$${builtins.toJSON r2.pricing.classBPerMillion}), or storage past the ${toString r2.storageBudgetGBMonth} GB-month budget; see the R2 usage dashboard";
        }
        # track-r2-usage design D7: a bucket's least-squares growth over the
        # last 7 days, as bytes a week, above 1 GB and above three times its
        # least-squares growth over the last 30 days. deriv() fits whatever
        # samples each window holds, so the rule is defined from the second
        # sample on and one odd sample moves it little; with under 7 days of
        # history both windows hold the same samples and compare equal, so
        # it stays silent rather than guessing, and it discriminates fully
        # from 30 days on. Payload only: metadata is under 0.1 % of it.
        {
          alert = "R2BucketGrowthAnomalous";
          expr = "deriv(vanixiets_r2_bucket_payload_bytes[7d]) * 604800 > 1000000000 and deriv(vanixiets_r2_bucket_payload_bytes[7d]) > 3 * deriv(vanixiets_r2_bucket_payload_bytes[30d])";
          for = "2h";
          severity = "warning";
          annotations.summary = "An R2 bucket grew by more than 1 GB in the last week, over three times its 30-day rate; see the bucket's panels on the R2 usage dashboard";
        }
        # F87: a bucket in the account that terranix does not declare
        # (flake.lib.r2Usage.declaredBuckets, read from
        # modules/terranix/cloudflare.nix) and that is not listed as managed
        # elsewhere (flake.lib.r2Usage.externalBuckets), or a listed external
        # bucket that holds an object or a byte, whose entry says it is empty.
        # Storage series only: a deleted bucket's operations stay, labelled
        # gone, and are not read. A deleted bucket's storage series vanish
        # within storageFreshSeconds of its last sample plus one hourly poll,
        # so `for` is that plus an hour: a bucket first seen after its
        # deletion never fires (omicsberg, deleted 15:55Z 2026-11-20, last
        # sampled 16:00Z, first polled 16:28Z), and one deleted while firing
        # resolves within that time.
        {
          alert = "R2BucketUndeclared";
          expr =
            let
              names = r2.declaredBuckets ++ lib.attrNames r2ExternalBuckets;
              known =
                assert lib.assertMsg (lib.all (n: builtins.match "[a-z0-9][a-z0-9-]*" n != null) names)
                  "fleetAlertRules: R2 bucket names must match [a-z0-9][a-z0-9-]*, so the exclusion needs no escape; got ${builtins.toJSON names}";
                lib.concatStringsSep "|" names;
              external = lib.concatStringsSep "|" (lib.attrNames r2ExternalBuckets);
            in
            ''count by (bucket) (vanixiets_r2_bucket_payload_bytes{bucket!~"${known}"}) > 0 or count by (bucket) (vanixiets_r2_bucket_payload_bytes{bucket=~"${external}"} > 0 or vanixiets_r2_bucket_objects{bucket=~"${external}"} > 0) > 0'';
          for = "${toString ((r2.storageFreshSeconds + 7200) / 3600)}h";
          severity = "warning";
          annotations.summary = "The R2 account holds a bucket that modules/terranix/cloudflare.nix does not declare, or a bucket listed in flake.lib.r2Usage.externalBuckets as empty now holds data; declare it in terranix (an import block, prevent_destroy), or record or correct its entry in externalBuckets";
        }
        # track-r2-usage design D7: r2-usage-publish republishes the record
        # every minute, so HostProbeStale sees the file fresh; this rule
        # reads the poll's own time, which ages from the publisher's first
        # run when no poll has succeeded. Two hourly polls missed.
        {
          alert = "R2UsageStale";
          expr = "time() - vanixiets_r2_last_success_timestamp_seconds > 7200";
          for = "10m";
          severity = "warning";
          annotations.summary = "No R2 usage poll has succeeded for over 2 h; check r2-usage.service's journal on the host, and that its cloudflare-analytics token still has Account Analytics Read";
        }
        {
          alert = "WeeklyPipelineTest";
          expr = "count(count by (host_name) (system_memory_usage_bytes))";
          for = "0s";
          severity = "info";
          annotations.summary = "Weekly test of the alert path: the value is the number of hosts reporting host memory";
          presence = [ (presence agentHosts "system_memory_usage_bytes") ];
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
        # CAM-111 6.1: the safety valve's detector. Each production nixbot
        # evaluation writes one `evaluation finished` record
        # (nixbot-evaluation-record.patch), which the collector's
        # journald/nixbot-eval receiver copies into devloop.eval_run
        # (modules/nixos/devloop-collection.nix), so the rule is SQL. One
        # instance per iets record of the last 12 h with a kill or a
        # non-zero exit_status, the asyncio returncode of the process nixbot
        # spawns, bwrap (Mic92/nixbot@171a8c77 nixbot/nixbot/nix_eval.py:
        # 94-101, 659-670, with the patch's `outcome.exit_status`):
        # - 0: a clean run, attribute errors included; nix-eval-jobs and iets
        #   report those per attribute and exit 0 unless one is fatal, which
        #   only a stack overflow is (numtide/iets@bd3dea00
        #   src/cli/jobs.rs:371, src/jobs/mod.rs:224). The record carries no
        #   attribute-error count, so such a run is a healthy record.
        # - 1: the evaluator failed: a worker iets lost (killed, crashed or
        #   exited), which aborts the whole run (src/jobs/collector.rs:
        #   215-239, 408-435; worker_kills stays 0, since iets does not print
        #   the message the patch counts), or an error iets reports, which
        #   the classic name always exits 1 for (src/log.rs:751-761); a
        #   flake whose root does not evaluate also exits 1.
        # - 128+n: the evaluator died of signal n inside bwrap, which exits
        #   bash-style (bubblewrap 0.13.1 bubblewrap.c:426-438): 137 for
        #   SIGKILL, the kernel's OOM kill included (nixbot's
        #   OOM_RETURN_CODES, nix_eval.py:46), and 134 for an iets panic,
        #   since its release profile aborts (Cargo.toml:73).
        # - -9: nixbot SIGKILLed bwrap's process group itself (nix_eval.py:
        #   551-558, 665-673): the evaluation's wall-clock timeout, also
        #   when the host evaluation lock's wrapper was still waiting, since
        #   the wrapper waits without a limit (modules/lib/nix-eval-lock.sh),
        #   or a cancellation.
        # Every non-zero status is therefore unhealthy. A record falls out
        # of the window 12 h after its evaluation, which resolves its
        # instance whether or not the cause is fixed; a critical instance
        # is re-posted only after 24 h, so it posts once.
        #
        # Runbook, an escalation ladder (tasks.md 6.1; operator Q88,
        # 2026-11-21), from the build named by build_id:
        # 1. Rebuild the build in nixbot. If it passes, record it in
        #    verify.md as transient and stop.
        # 2. If the same commit fails again, classify it from the labels.
        #    Memory (worker_kills, oom_kill or budget_kills above 0) is a
        #    capacity problem: take design D9's ladder, tuning
        #    evalWorkerCount or evalMaxMemorySize first, not a revert.
        #    Evaluator (a crash exit, a derivation difference, or errors
        #    stock nix-eval-jobs does not produce on that commit, compared
        #    with the paired-replay driver, as root on magnetite `replay.py
        #    run COMMITS_TSV OUTDIR` with one row for the build, verify.md
        #    4.2-4.3): fix forward, most cheaply by pinning the iets input
        #    in flake.nix to its last good revision.
        # 3. Revert to stock nix-eval-jobs (task 7.3's change) only if the
        #    failure blocks merges and no fix or pin is quick, as a
        #    deliberate decision recorded in verify.md.
        {
          alert = "IetsEvaluationUnhealthy";
          database = "devloop";
          language = "sql";
          expr = "SELECT build_id, ts, evaluator_version, worker_kills, oom_kill, budget_kills, exit_status AS value FROM eval_run WHERE evaluator = 'iets' AND ts >= now() - INTERVAL '12 hours' AND (worker_kills > 0 OR oom_kill > 0 OR budget_kills > 0 OR exit_status <> 0)";
          for = "0s";
          severity = "critical";
          annotations.summary = "A production nixbot evaluation by iets lost a worker, was killed or crashed; the value is its exit status. 1. Rebuild build_id in nixbot; if it passes, record it in verify.md as transient. 2. If it fails again: kills above 0 are capacity, so tune evalWorkerCount or evalMaxMemorySize (D9); a crash or a stock-only success (paired replay, verify.md 4.2-4.3) is fixed forward, e.g. by pinning iets to its last good revision. 3. Revert to stock (task 7.3) only if merges are blocked and no quick fix exists, recorded in verify.md (runbook in modules/nixos/fleet-alert/rules.nix). Resolves 12 h after the evaluation, not when fixed";
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
          alwaysOn = builtins.attrNames (lib.filterAttrs (_: h: h.alwaysOn) collecting);
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
