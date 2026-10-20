# Failure notifier for systemd units (ADR-009 item 11; S3 design D3, D4, D9).
#
# observability-notify@.service posts `FAILED <unit> on <host>` once per
# failure episode to ntfy's fleet-alerts topic through the one ntfy-send
# package, guarded by a stamp per unit. Every unit listed in
# services.observability-notify.units gets OnFailure= and two root hooks that
# post RESOLVED and remove the stamp: ExecStartPost= on the unit's next
# successful start, which ends an episode across automatic restarts, and
# ExecStopPost= on its next successful exit.
#
# With services.observability-notify.tokenFile set, the template loads that
# file as the `alerter-token` credential and ntfy-send reads it through
# NTFY_TOKEN_FILE; the hooks run as root inside each notified unit, where the
# template's credential is not visible, so they pass the file's path itself
# (design D3). Each posted FAILED is also appended to failed.log (design D9).
#
# Hosts import this module directly or through the otel-collector agent role;
# the key makes a host doing both load it once. It reads no clan var: the host
# supplies the token's path.
{ ... }:
let
  # The notifier's two scripts, a function so that
  # checks.x86_64-linux.otel-collector-config can rehearse them against a
  # temporary stamp directory and a recording ntfy-send.
  observabilityNotifyScripts =
    pkgs:
    {
      ntfySend,
      stampDir,
      hostName,
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
        ${ntfySend} "FAILED $unit on ${hostName}" fleet-alerts || exit 1
        echo posted > "$stamp"
        ${pkgs.coreutils}/bin/mkdir -p "${stampDir}/last-failed"
        echo "$now" > "$last"
        # R9.1 counts these lines (design D9). The evaluator, a DynamicUser,
        # reads the log, so it is created world-readable.
        log="${stampDir}/failed.log"
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
            ${ntfySend} "RESOLVED $unit on ${hostName}" fleet-alerts && ${pkgs.coreutils}/bin/rm -f "$stamp"
          fi
        fi
        exit 0
      '';
    };
in
{
  flake.lib = { inherit observabilityNotifyScripts; };

  flake.modules.nixos.observability-notify =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.observability-notify;
      notifyScripts = observabilityNotifyScripts pkgs {
        ntfySend = lib.getExe pkgs.ntfy-send;
        stampDir = "/var/lib/observability-notify";
        hostName = config.networking.hostName;
      };
      tokenEnv = lib.optionalString (
        cfg.tokenFile != null
      ) "${pkgs.coreutils}/bin/env NTFY_TOKEN_FILE=${cfg.tokenFile} ";
      hook = mode: "-+${tokenEnv}${notifyScripts.resolved} ${mode} %n";

      exportsToken =
        mode: hooks:
        lib.any (
          hook:
          builtins.match "-\\+/nix/store/[^ ]+/bin/env NTFY_TOKEN_FILE=${lib.escapeRegex cfg.tokenFile} /nix/store/[^ ]+-observability-notify-resolved ${mode} %n" hook
          != null
        ) (lib.toList hooks);
      unitsWithoutToken = builtins.filter (
        name:
        let
          unit = config.systemd.services.${name}.serviceConfig;
        in
        !(
          exportsToken "start" (unit.ExecStartPost or [ ]) && exportsToken "stop" (unit.ExecStopPost or [ ])
        )
      ) cfg.units;
    in
    {
      key = "vanixiets#observability-notify";

      options.services.observability-notify = {
        units = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            systemd.services attribute names (without `.service`) whose failure
            posts a notice to ntfy's fleet-alerts topic through
            observability-notify@.service, and whose next successful start or
            exit after a notice posts RESOLVED.
          '';
        };
        tokenFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Path of the file holding the `alerter` ntfy token, or null to post
            anonymously. When set, observability-notify@.service loads it as
            the credential `alerter-token` and sets
            NTFY_TOKEN_FILE=%d/alerter-token, and the resolve hooks run under
            `env NTFY_TOKEN_FILE=<this path>`.
          '';
        };
      };

      # With a token, each notified unit's resolve hooks pass tokenFile
      # itself (design D3), which a host overriding a unit's hooks can lose.
      config.assertions = lib.mkIf (cfg.tokenFile != null) [
        {
          assertion = unitsWithoutToken == [ ];
          message = "observability-notify: the resolve hooks of ${builtins.toJSON unitsWithoutToken} do not run under `env NTFY_TOKEN_FILE=${cfg.tokenFile}`.";
        }
      ];

      config.systemd.services = lib.mkMerge [
        (lib.genAttrs cfg.units (_: {
          unitConfig.OnFailure = [ "observability-notify@%n.service" ];
          serviceConfig = {
            # An automatic restart's stop is never a success, so the
            # episode ends at the next start. systemd runs ExecStartPost
            # before ExecStopPost and both run the one script, so a
            # oneshot's stop hook finds the stamp gone and posts no second
            # RESOLVED.
            ExecStartPost = [ (hook "start") ];
            ExecStopPost = [ (hook "stop") ];
          };
        }))
        {
          "observability-notify@" = {
            environment.OBSERVABILITY_NOTIFY_MIN_INTERVAL_SEC = "900";
            description = "Post a failure notice for %i to ntfy";
            serviceConfig = {
              Type = "oneshot";
              StateDirectory = "observability-notify";
              ExecStart = "${notifyScripts.failed} %i";
            };
          };
        }
        (lib.mkIf (cfg.tokenFile != null) {
          "observability-notify@" = {
            environment.NTFY_TOKEN_FILE = "%d/alerter-token";
            serviceConfig.LoadCredential = [ "alerter-token:${cfg.tokenFile}" ];
          };
        })
      ];
    };
}
