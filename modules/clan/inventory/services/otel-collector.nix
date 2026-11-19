# Collector roles. Every host of flake.lib.observabilityHosts whose `collect`
# is true runs the agent; a row with `collect = false` is in no role, so it
# gets no agent and none of the secrets the role wires (the shared
# ntfy-alerter token, its otel-cert), and turning it on must add it as a
# recipient of those shared vars (`clan vars fix <host>`) in the same change
# (CAM-113 F58). magnetite also runs the ingress, joined in-process by
# `forward`. A row's `platform` must equal its machine's machineClass, so the
# rules choose a host's expected signals by the class clan builds it as
# (design D7).
{ config, lib, ... }:
let
  hosts = config.flake.lib.observabilityHosts;
  machines = config.flake.clan.inventory.machines;
  mismatched = lib.filterAttrs (
    name: h: (h.platform or null) != (machines.${name}.machineClass or null)
  ) hosts;
in
{
  flake.clan.inventory.instances.otel-collector = {
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
      lib.mapAttrs (_: _: { }) (lib.filterAttrs (_: h: h.collect) hosts);
    roles.ingress.machines.magnetite = { };
  };
}
