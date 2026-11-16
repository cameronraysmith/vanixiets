# Containers and VMs on pyrite: Incus for system containers and VMs, Podman for
# OCI images behind a Docker-compatible socket (compose, devcontainers,
# testcontainers). No Docker daemon, since podman's docker socket and dockerd
# cannot both serve /run/docker.sock, and no libvirt, since Incus already drives
# QEMU/KVM here.
{ ... }:
{
  # Sibling-file auto-merge into the pyrite host module, as disko.nix does.
  flake.modules.nixos."machines/nixos/pyrite" =
    { pkgs, ... }:
    {
      # Incus refuses the iptables firewall, and podman 6 dropped iptables as a
      # netavark firewall driver. The ZeroTier MSS clamp follows the backend
      # (modules/nixos/zerotier-mss-clamp.nix).
      networking.nftables.enable = true;

      virtualisation.incus = {
        enable = true;
        # Re-applied on every incus start; it creates or updates these entities
        # and never deletes. Incus creates the zroot/incus dataset itself on the
        # first apply (zfs driver, source naming an absent dataset), as a
        # sibling of disko's zroot/root so no disko-declared dataset can collide.
        preseed = {
          storage_pools = [
            {
              name = "default";
              driver = "zfs";
              config.source = "zroot/incus";
            }
          ];
          networks = [
            {
              name = "incusbr0";
              type = "bridge";
              # A fixed subnet rather than "auto", which incus would resolve
              # afresh whenever the preseed is re-applied. Clear of the LAN
              # (192.168.50.0/24), ZeroTier (10.147.17.0/24) and podman's
              # default 10.88.0.0/16.
              config = {
                "ipv4.address" = "10.0.100.1/24";
                "ipv4.nat" = "true";
                "ipv6.address" = "none";
              };
            }
          ];
          profiles = [
            {
              name = "default";
              devices = {
                eth0 = {
                  name = "eth0";
                  network = "incusbr0";
                  type = "nic";
                };
                root = {
                  path = "/";
                  pool = "default";
                  type = "disk";
                };
              };
            }
          ];
        };
      };

      # incus adds its own nftables table for the bridge, but the host firewall's
      # input chain is a separate base chain whose drop still applies, so guest
      # DHCP and DNS to incus's dnsmasq need the bridge trusted.
      networking.firewall.trustedInterfaces = [ "incusbr0" ];

      virtualisation.podman = {
        enable = true;
        dockerCompat = true;
        dockerSocket.enable = true;
        defaultNetwork.settings.dns_enabled = true;
      };

      # The compose provider podman's `docker compose`/`podman compose` delegates to.
      environment.systemPackages = [ pkgs.docker-compose ];

      # Host-local groups, kept beside the services that create them rather than in
      # the fleet-wide clan users settings for cameron.
      users.users.cameron.extraGroups = [
        "incus-admin"
        "podman"
      ];
    };
}
