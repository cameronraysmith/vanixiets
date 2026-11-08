# caddy's local root on cinnabar as clan vars (CAM-87 design D10): the root
# and key caddy generated on 2026-01-27, imported once by the operator with
# `clan vars set` (runbook "caddy's root"), never generated: the script only
# fails, and a generator without `validation` whose files exist counts as
# current, so no clan command mints a root that the fleet's clients and the
# operator's phone would not trust.
{ ... }:
{
  flake.modules.nixos."machines/nixos/cinnabar" =
    { ... }:
    {
      clan.core.vars.generators.caddy-root-ca = {
        files."root.key" = {
          owner = "caddy";
          group = "caddy";
          mode = "0400";
          restartUnits = [ "caddy.service" ];
        };
        files."root.crt".secret = false;
        script = ''
          echo "caddy-root-ca is imported from cinnabar's caddy storage with clan vars set, never generated; see the fleet observability runbook, \"caddy's root\"" >&2
          exit 1
        '';
      };
    };
}
