# Collector roles. Every host of flake.lib.observabilityHosts runs the agent;
# magnetite also runs the ingress, joined in-process by `forward`.
{ config, lib, ... }:
{
  clan.inventory.instances.otel-collector = {
    module = {
      name = "otel-collector";
      input = "self";
    };

    roles.agent.machines = lib.mapAttrs (_: _: { }) config.flake.lib.observabilityHosts;
    roles.ingress.machines.magnetite = { };
  };
}
