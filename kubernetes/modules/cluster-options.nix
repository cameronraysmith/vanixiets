# Cluster configuration options for easykubenix
#
# Defines cluster-wide settings used by multiple modules.
# Simplified from hetzkube for local dev (IPv4-only, simpler CIDRs).
{ lib, ... }:
{
  options = {
    clusterName = lib.mkOption {
      type = lib.types.nonEmptyStr;
      description = "Cluster name for identification";
    };

    clusterHost = lib.mkOption {
      type = lib.types.nonEmptyStr;
      description = "API server host address";
    };

    clusterDomain = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "cluster.local";
      description = "Cluster DNS domain";
    };

    clusterPodCIDR = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "10.42.0.0/16";
      description = "Pod CIDR range (must match k3s configuration)";
    };

    clusterServiceCIDR = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "10.43.0.0/16";
      description = "Service CIDR range (must match k3s configuration)";
    };
  };
}
