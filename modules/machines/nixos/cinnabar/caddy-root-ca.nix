# caddy's local root on cinnabar as clan vars (CAM-87 design D10): the root
# and key caddy generated on 2026-01-27, imported once by the operator with
# `clan vars set` (runbook "caddy's root"), never generated: the script only
# fails, and a generator without `validation` whose files exist counts as
# current, so no clan command mints a root that the fleet's clients and the
# operator's phone would not trust. caddy loads its local root from these
# vars through flake.modules.nixos.caddy-local-root (design D11).
{ config, ... }:
let
  caddyLocalRoot = config.flake.modules.nixos.caddy-local-root;
in
{
  flake.modules.nixos."machines/nixos/cinnabar" =
    { config, ... }:
    let
      files = config.clan.core.vars.generators.caddy-root-ca.files;
    in
    {
      imports = [ caddyLocalRoot ];
      vanixiets.caddyLocalRoot = {
        certFile = "${files."root.crt".path}";
        keyFile = files."root.key".path;
        # Recorded from cinnabar's caddy storage on 2026-11-06; a rotation changes it with the vars.
        fingerprint = "7E:78:F6:7C:83:BD:DC:81:51:FF:EB:8F:82:1A:68:5D:02:89:9F:93:27:33:7F:9B:F2:41:9B:F9:3B:AA:2E:82";
      };
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
