# The failure notifier's posting and episode code, shared by systemd and
# launchd (ADR-009 item 11; S3 design D3, D4, D9; design D6).
#
# flake.lib.observabilityNotifyScripts pkgs { ntfySend; stampDir; hostName;
# topic ? "fleet-alerts"; logFile ? "<stampDir>/failed.log"; } returns the
# `failed` and `resolved` scripts that observability-notify@.service and its
# hooks run on NixOS; with the defaults their text, and so their store paths,
# are what modules/nixos/observability-notify.nix rendered before they moved
# here, so NixOS notices are unchanged. A function, so that
# checks.x86_64-linux.otel-collector-config can rehearse them against a
# temporary stamp directory and a recording ntfy-send.
#
# flake.lib.observabilityNotifyRun pkgs { label; host; topic ? "fleet-alerts";
# tokenFile; stateDir; logFile; minIntervalSec ? 900; } is the launchd
# counterpart of OnFailure plus the RESOLVED hooks, which launchd lacks:
# `observability-notify-run -- <command…>` runs the command, then `resolved
# start <label>` if it exited 0 and `failed <label>` otherwise, and exits with
# the command's code, so launchd records it. One episode per label: FAILED
# when a run fails after a pass or a first run fails, RESOLVED when a run
# passes after a posted FAILED, nothing for a new episode within
# minIntervalSec of the last FAILED. ntfy-send reads the token through
# NTFY_TOKEN_FILE, set only for its calls; on darwin it posts with
# /usr/bin/curl. checks.x86_64-linux.otel-collector-darwin runs it over a
# recording ntfy-send.
{ lib, ... }:
let
  observabilityNotifyScripts =
    pkgs:
    {
      ntfySend,
      stampDir,
      hostName,
      topic ? "fleet-alerts",
      logFile ? "${stampDir}/failed.log",
    }:
    {
      # One post per failure episode: skip while the stamp exists. A unit
      # whose last FAILED was posted less than OBSERVABILITY_NOTIFY_MIN_INTERVAL_SEC
      # ago opens a `suppressed` episode instead, which the resolve hooks end
      # without a post. A persistent crash loop therefore yields one
      # FAILED/RESOLVED pair, then at most one new pair per interval per unit;
      # detecting crash loops by restart rate belongs to S3. A failed post
      # writes no stamp, so the next failure posts again. Each posted FAILED
      # appends `<epoch> <unit> <host>` to failed.log; a suppressed episode
      # and a failed post append nothing.
      failed = pkgs.writeShellScript "observability-notify-failed" ''
        : "''${OBSERVABILITY_NOTIFY_MIN_INTERVAL_SEC:?}"
        unit="$1"
        stamp="${stampDir}/$unit"
        last="${stampDir}/last-failed/$unit"
        if [ -e "$stamp" ]; then
          exit 0
        fi
        now=$(${pkgs.coreutils}/bin/date +%s)
        if [ -s "$last" ] && [ $((now - $(< "$last"))) -lt "$OBSERVABILITY_NOTIFY_MIN_INTERVAL_SEC" ]; then
          echo suppressed > "$stamp"
          exit 0
        fi
        ${ntfySend} "FAILED $unit on ${hostName}" ${topic} || exit 1
        echo posted > "$stamp"
        ${pkgs.coreutils}/bin/mkdir -p "${stampDir}/last-failed"
        echo "$now" > "$last"
        # R9.1 counts these lines (design D9). The evaluator, a DynamicUser,
        # reads the log, so it is created world-readable.
        log="${logFile}"
        [ -e "$log" ] || ${pkgs.coreutils}/bin/install -m 0644 /dev/null "$log"
        printf '%s %s %s\n' "$now" "$unit" "${hostName}" >> "$log"
      '';

      # Runs as root (`+`) after a notified unit starts (`start`) or stops
      # (`stop`); a failed post leaves the stamp for the next chance and never
      # fails the unit.
      resolved = pkgs.writeShellScript "observability-notify-resolved" ''
        mode="$1"
        unit="$2"
        stamp="${stampDir}/$unit"
        if [ -e "$stamp" ] && { [ "$mode" = start ] || [ "''${SERVICE_RESULT:-}" = success ]; }; then
          if [ "$(< "$stamp")" = suppressed ]; then
            ${pkgs.coreutils}/bin/rm -f "$stamp"
          else
            ${ntfySend} "RESOLVED $unit on ${hostName}" ${topic} && ${pkgs.coreutils}/bin/rm -f "$stamp"
          fi
        fi
        exit 0
      '';
    };
in
{
  flake.lib = {
    inherit observabilityNotifyScripts;
    observabilityNotifyRun =
      pkgs:
      {
        label,
        host,
        topic ? "fleet-alerts",
        tokenFile,
        stateDir,
        logFile,
        minIntervalSec ? 900,
      }:
      let
        scripts = observabilityNotifyScripts pkgs {
          ntfySend = lib.getExe pkgs.ntfy-send;
          stampDir = stateDir;
          hostName = host;
          inherit topic logFile;
        };
        token = "NTFY_TOKEN_FILE=${lib.escapeShellArg tokenFile}";
      in
      pkgs.writeShellApplication {
        name = "observability-notify-run";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          [ "''${1:-}" = -- ] && shift
          export OBSERVABILITY_NOTIFY_MIN_INTERVAL_SEC=${toString minIntervalSec}
          mkdir -p "${stateDir}"
          rc=0
          "$@" || rc=$?
          if [ "$rc" = 0 ]; then
            env ${token} ${scripts.resolved} start ${lib.escapeShellArg label}
          else
            env ${token} ${scripts.failed} ${lib.escapeShellArg label} \
              || echo "observability-notify-run: posting FAILED ${label} on ${host} failed; the next failing run posts again" >&2
          fi
          exit "$rc"
        '';
      };
  };
}
