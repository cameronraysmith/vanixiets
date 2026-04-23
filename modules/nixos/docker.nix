# Docker runtime for magnetite
#
# Provisions real docker as a second container runtime alongside the existing
# podman stack used by gitea-actions-runner. Required because the
# test-cluster effect drives k3d via ctlptl (~/projects/sciops-workspace/ctlptl)
# which invokes the `docker` binary directly and has no production-quality
# podman support.
#
# Storage: docker's native ZFS storage driver is used (overlay2 does not
# layer cleanly on ZFS). This requires /var/lib/docker to be its own ZFS
# dataset; see modules/machines/nixos/magnetite/disko.nix for the
# zroot/root/docker dataset declaration.
#
# The buildbot-worker user is added to the docker group so effects running
# as that user can talk to /var/run/docker.sock (e.g. the forthcoming
# test-cluster effect invoking k3d via ctlptl).
{
  ...
}:
{
  flake.modules.nixos.docker =
    { ... }:
    {
      # Real docker daemon, additive to the existing podman stack.
      virtualisation.docker = {
        enable = true;
        # Native ZFS storage driver; requires /var/lib/docker to be its own
        # ZFS dataset (declared in disko.nix as zroot/root/docker).
        storageDriver = "zfs";
      };

      # Grant the buildbot-worker runtime user access to the docker socket
      # so effects executed by the worker (e.g. test-cluster via k3d+ctlptl)
      # can drive the docker daemon without sudo.
      users.users.buildbot-worker.extraGroups = [ "docker" ];
    };
}
