# flake.lib.otelHostProbe pkgs { labels; devices; ownerAliases; textfileDir;
# launchctl ? "/bin/launchctl"; }: the darwin probe (ADR-003 items 23, 24;
# design D4), run every 60 s as _prometheus-node-exporter. For each label it
# runs exactly `launchctl print system/<label>` and writes launchd_job_state,
# launchd_job_last_exit_code and launchd_job_runs_total (ADR-004:95); for each
# device it runs exactly `smartctl -j -H -A <device>` and writes ADR-004:92's
# eight names under smartctl_exporter's TYPEs, so the store keeps the names
# pyrite's series carry. A job's pid is never written (ADR-004:125). A
# missing `last exit code` line is 0 after a jetsam idle exit, launchd's
# routine reclaim of an idle job, and -1 otherwise, as for a job killed by a
# signal. launchctl's text is not API (launchctl(1)); a format change writes
# no series, which RuleSignalMissing reports. Each file is written to a
# temporary name in the textfile directory and renamed, so node_exporter
# never reads half a file. checks.x86_64-linux.otel-collector-darwin replaces
# each line marked `# mutant: <name>` and requires that mutant's case to fail.
{ lib, ... }:
{
  flake.lib.otelHostProbe =
    pkgs:
    {
      labels,
      devices,
      ownerAliases,
      textfileDir,
      launchctl ? "/bin/launchctl",
    }:
    pkgs.writeShellApplication {
      name = "otel-host-probe";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.gawk
        pkgs.gnugrep
        pkgs.jq
        pkgs.smartmontools
      ];
      text = ''
        dir=${lib.escapeShellArg textfileDir}
        aliases=${
          lib.escapeShellArg (lib.concatStrings (lib.mapAttrsToList (o: a: "${o} ${a}\n") ownerAliases))
        }
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        : > "$tmp/state"; : > "$tmp/exit"; : > "$tmp/runs"
        # A first-level field of `launchctl print`, indented by one tab.
        field() { awk -F' = ' -v k="$1" '$1 == "\t" k { print $2; exit }' "$tmp/out"; }
        # Arrays, so a host with one label or one device passes shellcheck,
        # which rejects a literal single-word `for` list (SC2043).
        labels=(${lib.escapeShellArgs labels})
        devices=(${lib.escapeShellArgs devices})
        for label in "''${labels[@]}"; do
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
            reason=$(field "last exit reason")
            # mutant: idleExitAsFailure
            if [ -z "$code" ] && [ "$reason" = JETSAM_REASON_MEMORY_IDLE_EXIT ]; then code=0; fi
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
        {
          echo "# HELP launchd_job_state 1 for the launchd job's current state, 0 for the others."
          echo "# TYPE launchd_job_state gauge"
          cat "$tmp/state"
          if [ -s "$tmp/exit" ]; then
            echo "# HELP launchd_job_last_exit_code The job's last exit status; 0 if it never exited or was reclaimed idle, -1 if missing otherwise or not an integer."
            echo "# TYPE launchd_job_last_exit_code gauge"
            cat "$tmp/exit"
          fi
          if [ -s "$tmp/runs" ]; then
            echo "# HELP launchd_job_runs_total Launches since the job was loaded."
            echo "# TYPE launchd_job_runs_total counter"
            cat "$tmp/runs"
          fi
        } > "$dir/.launchd.prom.$$"
        mv -f "$dir/.launchd.prom.$$" "$dir/launchd.prom"
        : > "$tmp/smart"
        for device in "''${devices[@]}"; do
          smartctl -j -H -A "$device" > "$tmp/smart.json" || true
          jq -r '
            def g($n; $t; $v): if $v == null then empty else [$n, $t, ($v | tostring)] end;
            (.nvme_smart_health_information_log // {}) as $h
            | g("smartctl_device_smart_status"; "gauge"; (if .smart_status.passed == null then null elif .smart_status.passed then 1 else 0 end)),
              g("smartctl_device_critical_warning"; "counter"; $h.critical_warning),
              g("smartctl_device_media_errors"; "counter"; $h.media_errors),
              g("smartctl_device_percentage_used"; "counter"; $h.percentage_used),
              g("smartctl_device_available_spare"; "counter"; $h.available_spare),
              g("smartctl_device_available_spare_threshold"; "counter"; $h.available_spare_threshold),
              g("smartctl_device_num_err_log_entries"; "counter"; $h.num_err_log_entries),
              g("smartctl_device_temperature"; "gauge"; .temperature.current)
            | @tsv' "$tmp/smart.json" | while IFS=$'\t' read -r name type value; do
              extra=""; [ "$name" = smartctl_device_temperature ] && extra=',temperature_type="current"'
              printf '%s\t%s\t%s{device="%s"%s} %s\n' "$name" "$type" "$name" "$device" "$extra" "$value"
            done >> "$tmp/smart"
        done
        awk -F'\t' '$1 != last { print "# TYPE " $1 " " $2; last = $1 } { print $3 }' < <(sort -s -t$'\t' -k1,1 "$tmp/smart") > "$dir/.smartctl.prom.$$"
        mv -f "$dir/.smartctl.prom.$$" "$dir/smartctl.prom"
      '';
    };
}
