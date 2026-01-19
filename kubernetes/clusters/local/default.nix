# Local development cluster configuration
#
# Minimal Cilium-only configuration for k3s-dev cluster.
# Cluster runs in Colima VM at 192.100.0.10.
{ ... }:
{
  # Cluster identification
  clusterName = "k3s-dev";
  clusterHost = "127.0.0.1"; # k3s API server listens on loopback

  # CIDRs matching k3s-server module defaults
  clusterPodCIDR = "10.42.0.0/16";
  clusterServiceCIDR = "10.43.0.0/16";

  # Enable Cilium CNI
  cilium.enable = true;
  cilium.version = "1.16.5";
}
