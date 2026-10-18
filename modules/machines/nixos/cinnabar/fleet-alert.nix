# The fleet alert dead-man and its failure notifier on cinnabar (design D4,
# D12; ADR-009 items 9 and 11, R9.4). Both post to fleet-alerts with the
# shared alerter token, loaded by path; cinnabar runs no collector, so it
# imports observability-notify directly and fleet-deadman is its one
# notified unit.
{ ... }:
{
  flake.modules.nixos."machines/nixos/cinnabar" =
    { config, ... }:
    let
      alerterToken = config.clan.core.vars.generators.ntfy-alerter.files.token.path;
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

      # S3 design D3: the dead-man and the failure notifier post with the
      # shared alerter token. A host assertion rather than a check clause,
      # as on magnetite (charter v18).
      assertions = [
        {
          assertion =
            config.services.fleet-alert.deadman.enable
            && config.services.fleet-alert.deadman.tokenFile == alerterToken
            && config.services.observability-notify.tokenFile == alerterToken;
          message = "cinnabar: the fleet alert dead-man must be enabled, and it and the failure notifier must read the ntfy-alerter token ${alerterToken}; deadman enabled = ${builtins.toJSON config.services.fleet-alert.deadman.enable}, deadman.tokenFile = ${builtins.toJSON config.services.fleet-alert.deadman.tokenFile}, observability-notify.tokenFile = ${builtins.toJSON config.services.observability-notify.tokenFile}.";
        }
      ];
    };
}
