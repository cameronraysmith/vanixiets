# Every host with a system composes its machine module under
# machines/<class>/<name> (ADR-0018, ADR-0020) and is built for the system its
# flake.fleet.hosts record declares; no host module sets nixpkgs.hostPlatform.
{ config, lib, ... }:
{
  flake.clan.machines = lib.mapAttrs (name: h: {
    imports = [ config.flake.modules.${h.class}."machines/${h.class}/${name}" ];
    nixpkgs.hostPlatform = h.system;
  }) (lib.filterAttrs (_: h: h.system != null) config.flake.fleet.hosts);
}
