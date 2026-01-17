# Networking and containerd configuration for k3s server
#
# Configures firewall rules for Kubernetes component communication,
# containerd settings for CNI compatibility, and CNI plugin installation.
# See docs/notes/development/kubernetes/components/nixos-k3s-server.md for details.
{
  config,
  lib,
  pkgs,
  ...
}:

{
  config = lib.mkIf config.k3s-server.enable {
    # Firewall configuration for Kubernetes components
    #
    # TCP ports:
    #   6443  - kube-apiserver (Kubernetes API server)
    #   10250 - kubelet (metrics and exec API)
    #   2379  - etcd client requests (HA mode)
    #   2380  - etcd peer communication (HA mode)
    #   4240  - Cilium health check
    #   4244  - Hubble observability API
    #
    # UDP ports:
    #   8472 - VXLAN (Cilium overlay network)
    #   4789 - VXLAN fallback (Cilium)
    #
    # Trusted interfaces:
    #   cni+    - CNI-created interfaces (wildcard)
    #   cilium+ - Cilium-created interfaces (wildcard)
    #   lxc+    - LXC container interfaces used by Cilium (wildcard)
    networking.firewall = {
      allowedTCPPorts = [
        6443
        10250
        2379
        2380
        4240
        4244
      ];
      allowedUDPPorts = [
        8472
        4789
      ];
      trustedInterfaces = [
        "cni+"
        "cilium+"
        "lxc+"
      ];
    };

    # containerd configuration for Kubernetes compatibility
    #
    # Settings required for CNI plugins (especially Cilium) and proper
    # cgroup management with systemd.
    virtualisation.containerd.settings = {
      plugins."io.containerd.grpc.v1.cri" = {
        # CNI plugin binary directory
        # MUST be /opt/cni/bin for easykubenix/Cilium compatibility
        # Cilium expects CNI plugins at this standard location
        cni.bin_dir = lib.mkForce "/opt/cni/bin";

        # Workaround for cgroups hugetlb controller issue in some environments
        disable_hugetlb_controller = true;

        # Container runtime settings
        containerd.runtimes.runc.options = {
          # Use systemd cgroups for Kubernetes compatibility
          # Required for kubelet and containerd to agree on resource accounting
          SystemdCgroup = true;
        };
      };

      # Enable systemd (NixOS) support in containers
      plugins."io.containerd.cri.v1.runtime".containerd.runtimes.runc = {
        cgroup_writable = true;
      };
    };

    # CNI plugin installation
    #
    # Copies CNI plugins from nixpkgs to /opt/cni/bin where Cilium expects them.
    # This runs during system activation before k3s starts.
    system.activationScripts.cni-plugins = {
      text = ''
        # Ensure CNI plugin directory exists and copy plugins
        # rsync preserves timestamps and only updates changed files
        ${lib.getExe pkgs.rsync} --mkpath --recursive ${pkgs.cni-plugins}/bin/ /opt/cni/bin/
      '';
      deps = [ ];
    };
  };
}
