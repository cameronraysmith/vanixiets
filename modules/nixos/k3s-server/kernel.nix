{ config, lib, ... }:
{
  config = lib.mkIf config.k3s-server.enable {
    # Kernel modules for container networking and CNI operation
    boot.kernelModules = [
      "br_netfilter" # Bridge netfilter support for iptables rules on bridged traffic
      "nf_conntrack" # Connection tracking for stateful firewalling
      "overlay" # OverlayFS for container image layers
      "ip_tables" # IPv4 firewall rules
      "ip6_tables" # IPv6 firewall rules
      "ip6table_mangle" # IPv6 packet mangling (required by Cilium)
      "ip6table_raw" # IPv6 raw table access (required by Cilium)
      "ip6table_filter" # IPv6 filtering (required by Cilium)
    ];

    # Sysctl settings for Kubernetes networking
    boot.kernel.sysctl = {
      # IPv4 forwarding for pod networking
      "net.ipv4.ip_forward" = 1;

      # IPv6 forwarding for dual-stack support
      "net.ipv6.conf.all.forwarding" = 1;
      "net.ipv6.conf.default.forwarding" = 1;

      # Bridge traffic passes through iptables for CNI operation
      "net.bridge.bridge-nf-call-iptables" = 1;
      "net.bridge.bridge-nf-call-ip6tables" = 1;

      # Cilium-specific: disable reverse path filtering on lxc interfaces
      "net.ipv4.conf.lxc*.rp_filter" = 0;

      # Kubelet stability: commit memory to prevent OOM killer issues
      "vm.overcommit_memory" = 1;

      # Kubelet stability: auto-reboot on kernel panic after 10 seconds
      "kernel.panic" = 10;

      # Kubelet stability: trigger panic on oops to ensure node reboots
      "kernel.panic_on_oops" = 1;
    };
  };
}
