# Collector roles. Every host of flake.lib.observabilityHosts runs the agent;
# magnetite also runs the ingress, joined in-process by `forward`. A row's
# `platform` must equal its machine's machineClass, so the rules choose a
# host's expected signals by the class clan builds it as (design D7).
{ config, lib, ... }:
let
  hosts = config.flake.lib.observabilityHosts;
  machines = config.clan.inventory.machines;
  mismatched = lib.filterAttrs (
    name: h: (h.platform or null) != (machines.${name}.machineClass or null)
  ) hosts;
in
{
  clan.inventory.instances.otel-collector = {
    module = {
      name = "otel-collector";
      input = "self";
    };

    roles.agent.machines =
      assert lib.assertMsg (mismatched == { })
        "otel-collector: flake.lib.observabilityHosts rows whose platform differs from the inventory's machineClass: ${
          builtins.toJSON (
            lib.mapAttrs (n: h: {
              platform = h.platform or null;
              machineClass = machines.${n}.machineClass or null;
            }) mismatched
          )
        }";
      lib.mapAttrs (_: _: { }) hosts;
    roles.ingress.machines.magnetite = { };
  };
}
