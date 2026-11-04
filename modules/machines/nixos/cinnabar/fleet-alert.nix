# The fleet alert dead-man and its failure notifier on cinnabar (design D4,
# D12; ADR-009 items 9 and 11, R9.4). Both post to fleet-alerts with the
# shared alerter token, loaded by path. The otel-collector agent role lists
# fleet-deadman among cinnabar's notified units from
# flake.lib.observabilityHosts.
{
  flake.modules.nixos."machines/nixos/cinnabar" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      alerterToken = config.clan.core.vars.generators.ntfy-alerter.files.token.path;
      deadmanUnit = config.systemd.services.fleet-deadman;
      # The units a dead-man run needs on cinnabar: the probe and poll reach
      # ntfy, and every post goes through caddy on cinnabar's ZeroTier
      # address (caddy.nix, zt-dns.nix).
      pathUnits = [
        "ntfy-sh.service"
        "caddy.service"
        "zerotierone.service"
      ];
    in
    {
      services.observability-notify.tokenFile = alerterToken;

      services.fleet-alert.deadman = {
        enable = true;
        tokenFile = alerterToken;
      };

      # The external watch's ping URL (CAM-76, design D5): a bearer
      # credential, entered once by the operator at a hidden prompt, kept as
      # a curl configuration that fleet-deadman loads as external-ping and
      # curl reads on stdin.
      clan.core.vars.generators.fleet-deadman-ping = {
        prompts.ping-url = {
          description = ''
            healthchecks.io ping URL of the check that watches fleet-deadman,
            in its UUID form https://hc-ping.com/<uuid>. Anyone holding it can
            keep the check up, so it is entered here and nowhere else.
          '';
          type = "hidden";
          persist = true;
          display = {
            group = "fleet-alert";
            label = "healthchecks.io ping URL";
          };
        };
        files.ping-url.deploy = false;
        files.curl-config = { };
        runtimeInputs = [ pkgs.gnugrep ];
        script = ''
          url=$(cat "$prompts/ping-url")
          if ! printf '%s' "$url" | grep -Eqx 'https://hc-ping\.com/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}'; then
            echo "fleet-deadman-ping: the value is not a healthchecks.io ping URL of the form https://hc-ping.com/<uuid>" >&2
            exit 1
          fi
          printf 'url = "%s"\n' "$url" > "$out/curl-config"
        '';
      };

      services.fleet-alert.deadman.pingConfigFile =
        config.clan.core.vars.generators.fleet-deadman-ping.files.curl-config.path;

      # Design D12: ordered after every unit on its path, and never starting
      # one, so a boot neither probes a half-started path nor starts a unit
      # the operator stopped.
      assertions = [
        {
          assertion =
            lib.all (u: builtins.elem u deadmanUnit.after) pathUnits
            && !(lib.any (u: builtins.elem u deadmanUnit.wants) pathUnits);
          message = "cinnabar: fleet-deadman.service must be ordered after ${builtins.toJSON pathUnits} and want none of them; it has after = ${builtins.toJSON deadmanUnit.after}, wants = ${builtins.toJSON deadmanUnit.wants}.";
        }
      ];
    };
}
