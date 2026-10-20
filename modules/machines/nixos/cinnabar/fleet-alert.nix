# The fleet alert dead-man and its failure notifier on cinnabar (design D4,
# D12; ADR-009 items 9 and 11, R9.4). Both post to fleet-alerts with the
# shared alerter token, loaded by path; cinnabar runs no collector, so it
# imports observability-notify directly and fleet-deadman is its one
# notified unit.
{ ... }:
{
  flake.modules.nixos."machines/nixos/cinnabar" =
    { config, lib, ... }:
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
      services.observability-notify = {
        units = [ "fleet-deadman" ];
        tokenFile = alerterToken;
      };

      services.fleet-alert.deadman = {
        enable = true;
        tokenFile = alerterToken;
      };

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
