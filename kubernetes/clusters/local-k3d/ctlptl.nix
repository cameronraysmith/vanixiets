# ctlptl cluster configuration for the local k3d development cluster,
# rendered to JSON (a YAML subset ctlptl reads) as packages.k3d-cluster-config.
# Creates a single-node k3d cluster with:
# - Static subnet 192.168.100.0/24 for predictable IPs:
#   - .2 = k3d-serverlb (load balancer container)
#   - .3 = k3d-dev-server-0 (k3s node, where servicelb binds)
#   sslip.io domains use .3: *.192.168.100.3.sslip.io resolves to k3s node
# - Disabled Flannel (for Cilium CNI - pod networking)
# - k3s kube-proxy disabled (Cilium kube-proxy replacement serves Services)
# - Disabled Traefik (using Cilium Gateway API for ingress)
# - ServiceLB enabled (klipper-lb assigns node IPs to LoadBalancer services)
# - Ports 80/443 exposed for Gateway API ingress via servicelb
# - K3D_FIX_MOUNTS=1 environment variable for OrbStack compatibility
# - Host volume mount at /manifests for CI ArgoCD file:// repo access
{ lib, k3s }:
let
  servers = [ "server:*" ];
in
{
  apiVersion = "ctlptl.dev/v1alpha1";
  kind = "Cluster";
  name = "k3d-dev";
  product = "k3d";
  k3d.v1alpha5Simple = {
    servers = 1;
    subnet = "192.168.100.0/24";
    # nixpkgs' k3s is the single source of the node version, as it is for
    # services.k3s.package; OCI tags cannot contain `+`, so the upstream
    # image tags spell k3s's `+k3sN` build suffix as `-k3sN`.
    image = "rancher/k3s:v" + lib.replaceStrings [ "+" ] [ "-" ] k3s.version;
    volumes = [
      {
        volume = "/tmp/k3d-manifests:/manifests";
        nodeFilters = servers;
      }
    ];
    env = [
      {
        envVar = "K3D_FIX_MOUNTS=1";
        nodeFilters = servers ++ [ "agent:*" ];
      }
    ];
    ports =
      map
        (port: {
          inherit port;
          nodeFilters = [ "loadbalancer" ];
        })
        [
          "80:80"
          "443:443"
        ];
    options.k3s.extraArgs =
      map
        (arg: {
          inherit arg;
          nodeFilters = servers;
        })
        [
          "--flannel-backend=none"
          "--disable-network-policy"
          "--disable=traefik"
          "--disable-kube-proxy"
        ];
  };
}
