# The agent hosts and what each reports (design D6). The inventory's agent
# machines, whether each collects, each host's notified units, its SMART
# devices and the alert rules' always-on hosts, expected hosts and
# SystemdUnitFailed exclusion are read from here. `collect = false` keeps
# the agent role off a host until its watched first deploy; a host joins
# alwaysOn only by an edit here when it becomes permanently provisioned
# (ADR-009 item 16).
{ ... }:
{
  flake.lib.observabilityHosts =
    let
      agent = extra: {
        collect = true;
        alwaysOn = false;
        smartDevices = [ ];
        notifiedUnits = [
          "opentelemetry-collector"
          "otel-envelope"
        ]
        ++ extra;
      };
    in
    {
      magnetite =
        agent [
          "devloop-pg-grants"
          "devloop-reconcile"
          "fleet-alert"
          "greptimedb"
          "greptimedb-envelope"
          "greptimedb-schema"
          "zfs-assert-root-docker-noautosnap"
          "zfs-assert-root-greptimedb-noautosnap"
          "zfs-assert-root-nix-noautosnap"
          "zfs-assert-root-podman-noautosnap"
          "zfs-set-root-greptimedb-quota"
          "zfs-set-root-greptimedb-reservation"
          "zfs-set-root-home-reservation"
          "zfs-set-root-nix-quota"
          "zfs-set-root-nixos-reservation"
        ]
        // {
          alwaysOn = true;
        };
      cinnabar = agent [ "fleet-deadman" ] // {
        collect = true;
        alwaysOn = true;
      };
      pyrite = agent [ ] // {
        collect = false;
        smartDevices = [ "/dev/nvme0" ];
      };
      electrum = agent [ ];
      galena = agent [ ];
      scheelite = agent [ ];
    };
}
