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
# supplies the token's path. The posting and episode scripts live in
# modules/lib/observability-notify-run.nix, which launchd's wrapper shares.
{ config, ... }:
let
  # Inside the NixOS module `config` is the host's; this is the flake's.
  flakeConfig = config;
in
{
  flake.modules.nixos.observability-notify =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.observability-notify;
      notifyScripts = flakeConfig.flake.lib.observabilityNotifyScripts pkgs {
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

      # Each OnCalendar of a timer that starts a notified unit, with its
      # timer's name, unless its last word is UTC or an Area/Location zone.
      localCalendars = lib.concatLists (
        lib.mapAttrsToList (
          name: timer:
          lib.optionals
            (builtins.elem (timer.timerConfig.Unit or "${name}.service") (map (u: "${u}.service") cfg.units))
            (
              map (calendar: "${name}.timer: ${calendar}") (
                builtins.filter (
                  calendar:
                  calendar != "" && builtins.match ".*[[:space:]](UTC|[A-Za-z_]+(/[A-Za-z0-9_+-]+)+)" calendar == null
                ) (lib.toList (timer.timerConfig.OnCalendar or [ ]))
              )
            )
        ) config.systemd.timers
      );
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

      # A calendar without a zone is local time, and in a daylight-saving
      # zone systemd computes its next elapse across the autumn change as an
      # hour later, so the unit and the post its failure would make skip an
      # hour. With a token, each notified unit's resolve hooks pass tokenFile
      # itself (design D3), which a host overriding a unit's hooks can lose.
      config.assertions = [
        {
          assertion = localCalendars == [ ];
          message = "observability-notify: the timers of notified units must name their zone in OnCalendar, as `UTC` or an Area/Location zone: ${builtins.toJSON localCalendars}.";
        }
      ]
      ++ lib.optional (cfg.tokenFile != null) {
        assertion = unitsWithoutToken == [ ];
        message = "observability-notify: the resolve hooks of ${builtins.toJSON unitsWithoutToken} do not run under `env NTFY_TOKEN_FILE=${cfg.tokenFile}`.";
      };

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
