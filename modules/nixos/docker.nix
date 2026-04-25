# Docker runtime for magnetite, additive to the existing podman stack used by
# gitea-actions-runner. Required by the test-cluster effect, which drives k3d
# via ctlptl invoking the `docker` binary directly (no podman support).
#
# Storage: docker's native ZFS storage driver (overlay2 does not layer cleanly
# on ZFS); requires /var/lib/docker to be its own ZFS dataset, declared as
# zroot/root/docker in modules/machines/nixos/magnetite/disko.nix.
#
# buildbot-worker joins the docker group so effects can reach the docker
# socket without sudo.
{
  ...
}:
{
  flake.modules.nixos.docker =
    { ... }:
    {
      virtualisation.docker = {
        enable = true;
        # Native ZFS storage driver; requires /var/lib/docker to be its own ZFS dataset (disko.nix zroot/root/docker).
        storageDriver = "zfs";
      };

      # Grant buildbot-worker docker socket access so effects can drive the daemon without sudo.
      users.users.buildbot-worker.extraGroups = [ "docker" ];
    };
}
