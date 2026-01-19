# Local development cluster configuration
#
# Cilium CNI and step-ca ACME server for k3s-dev cluster.
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
  cilium.version = "1.18.6";

  # Enable step-ca ACME server for local TLS
  step-ca.enable = true;
  step-ca.caCerts = {
    rootCert = ./pki/root_ca.crt;
    intermediateCert = ./pki/intermediate_ca.crt;
  };
}
