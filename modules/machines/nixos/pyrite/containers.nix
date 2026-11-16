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
    let
      # Each login's runtime directory, /run/user/<uid>, set by pam_systemd at login
      # (podman.socket uses the same directory as %t); it can only be referenced, not
      # resolved at evaluation, for users whose uids are allocated dynamically.
      rootlessDockerHost = "unix://\${XDG_RUNTIME_DIR}/podman/podman.sock";
    in
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

      # Docker-API clients (docker-compose, devcontainers, testcontainers) default
      # to the logged-in user's rootless socket, which the podman module enables
      # for every login, so each user's images and containers stay in that user's
      # own store rather than root's. The rootful socket and /run/docker.sock stay
      # for jobs that need root, reached with an explicit DOCKER_HOST. podman's own
      # CLI, `docker` included through dockerCompat, ignores DOCKER_HOST.
      # extraInit reaches login shells, only where the session has a runtime
      # directory (su, cron and service-run shells have none, and an empty one
      # would yield a broken socket path); environment.d reaches each user's
      # systemd manager, so session-launched applications see it too.
      environment.extraInit = ''
        if [ -n "''${XDG_RUNTIME_DIR-}" ]; then
          export DOCKER_HOST="${rootlessDockerHost}"
        fi
      '';
      environment.etc."environment.d/60-docker-host.conf".text = ''
        DOCKER_HOST=${rootlessDockerHost}
      '';
    };
}
