# Gateway Application for Cilium Gateway API integration
#
# Creates Gateway resource for ingress traffic routing.
# Uses Cilium as GatewayClass with explicit per-service listeners.
#
# Each service gets paired HTTP + HTTPS listeners with specific hostnames.
# This explicit pattern ensures declarative routing with no implicit
# precedence rules, mirrors Istio Gateway patterns, and makes service
# exposure GitOps-reviewable.
#
# cert-manager annotation enables automatic TLS certificate provisioning
# via the step-ca ACME ClusterIssuer.
#
# Sync wave 2: after ClusterIssuer (1) to ensure issuer is ready.
{ lib, ... }:
let
  # Gateway configuration
  gatewayNamespace = "gateway-system";
  gatewayName = "main-gateway";
  clusterIssuerName = "step-ca-acme";

  # sslip.io domain for local development
  # k3d server node IP from static subnet (192.168.100.0/24)
  # .2 = k3d-serverlb (load balancer), .3 = k3s node (where servicelb binds)
  localDomain = "192.168.100.3.sslip.io";

  # Service-specific hostnames (add more as services need exposure)
  argoCDHostname = "argocd.${localDomain}";
in
{
  applications.gateway = {
    namespace = gatewayNamespace;

    # Phase 4 native: create namespace
    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        createNamespace = true;
      };
    };

    # Sync wave 2: after ClusterIssuer at wave 1
    annotations."argocd.argoproj.io/sync-wave" = "2";

    # Use yamls for Gateway API resources (no typed options)
    yamls = [
      # Gateway resource
      ''
        apiVersion: gateway.networking.k8s.io/v1
        kind: Gateway
        metadata:
          name: ${gatewayName}
          namespace: ${gatewayNamespace}
          annotations:
            # cert-manager integration: automatically provision TLS certificate
            cert-manager.io/cluster-issuer: ${clusterIssuerName}
        spec:
          # Cilium provides GatewayClass
          gatewayClassName: cilium
          listeners:
            # ArgoCD HTTP listener (ACME HTTP-01 challenges + redirects)
            - name: http-argocd
              protocol: HTTP
              port: 80
              hostname: "${argoCDHostname}"
              allowedRoutes:
                namespaces:
                  from: All
            # ArgoCD HTTPS listener (TLS-terminated traffic)
            - name: https-argocd
              protocol: HTTPS
              port: 443
              hostname: "${argoCDHostname}"
              tls:
                mode: Terminate
                certificateRefs:
                  - name: argocd-tls
              allowedRoutes:
                namespaces:
                  from: All
      ''
    ];
  };
}
