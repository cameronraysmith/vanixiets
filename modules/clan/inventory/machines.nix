# One clan machine per registry host that runs Nix (flake.fleet.hosts,
# modules/lib/hosts.nix), with the record's tags, description and class. A
# NixOS machine's deploy.targetHost is the record's targetHost. Darwin
# machines carry none: with it set, `clan machines update` would skip the
# network peers (tincr) for the darwin login user
# (flake.lib.networkTargetObligations).
{ config, lib, ... }:
{
  flake.clan.inventory.machines = lib.mapAttrs (
    _: host:
    {
      inherit (host) tags description;
      machineClass = host.class;
    }
    // lib.optionalAttrs (host.class == "nixos") {
      deploy.targetHost = host.targetHost;
    }
  ) (lib.filterAttrs (_: host: host.system != null) config.flake.lib.hosts);
}
