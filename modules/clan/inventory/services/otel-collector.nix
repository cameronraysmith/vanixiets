# Collector roles. Every host of flake.lib.observabilityHosts whose `collect`
# is true runs the agent; a row with `collect = false` is in no role, so it
# gets no agent and none of the secrets the role wires (the shared
# ntfy-alerter token, its otel-cert), and turning it on must add it as a
# recipient of those shared vars (`clan vars fix <host>`) in the same change
# (CAM-113 F58). magnetite also runs the ingress, joined in-process by
# `forward`. A row's `platform` is its host's flake.fleet.hosts class, the
# same class the inventory's machineClass is generated from
# (modules/lib/observability-hosts.nix).
{ config, lib, ... }:
let
  hosts = config.flake.lib.observabilityHosts;
in
{
  flake.clan.inventory.instances.otel-collector = {
    module = {
      name = "otel-collector";
      input = "self";
    };

    roles.agent.machines = lib.mapAttrs (_: _: { }) (lib.filterAttrs (_: h: h.collect) hosts);
    roles.ingress.machines.magnetite = { };
  };
}
