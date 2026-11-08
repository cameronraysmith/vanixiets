# caddy-root-check on cinnabar (CAM-87 design D6): weekly, verify the chain
# caddy serves for ntfy.zt against the public value of the clan vars
# caddy-root-ca, and fail 180 days before that root expires. cinnabar's
# notifiedUnits lists it, so a failure posts one FAILED notice per episode
# through observability-notify.
{ config, ... }:
let
  flakeLib = config.flake.lib;
in
{
  flake.modules.nixos."machines/nixos/cinnabar" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      systemd.services.caddy-root-check = {
        description = "Verify the chain caddy serves for ntfy.zt against caddy's root";
        after = [
          "caddy.service"
          "network-online.target"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          DynamicUser = true;
          ExecStart = lib.getExe (
            flakeLib.caddyRootCheck pkgs {
              bundle = "${config.clan.core.vars.generators.caddy-root-ca.files."root.crt".path}";
              connect = "ntfy.zt:443";
              servername = "ntfy.zt";
            }
          );
        };
      };
      systemd.timers.caddy-root-check = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "Mon *-*-* 14:00:00 UTC";
          Persistent = true;
        };
      };
    };
}
