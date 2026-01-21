# Gateway Application for Cilium Gateway API integration
#
# Creates Gateway resource for ingress traffic routing.
# Uses Cilium as GatewayClass with HTTP and HTTPS listeners.
#
# HTTP listener uses wildcard hostname to accept ACME HTTP-01 challenges
# for any service. HTTPS listeners use service-specific hostnames to
# trigger non-wildcard certificate requests (HTTP-01 compatible).
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
  localDomain = "192.168.100.2.sslip.io";
  wildcardDomain = "*.${localDomain}";

  # Service-specific hostnames (add more as services need HTTPS)
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
            # HTTP listener for ACME HTTP-01 challenges and HTTP traffic
            # Hostname required for Cilium to attach hostname-matching HTTPRoutes
            - name: http
              protocol: HTTP
              port: 80
              hostname: "${wildcardDomain}"
              allowedRoutes:
                namespaces:
                  from: All
            # HTTPS listener for ArgoCD (add more listeners as services need HTTPS)
            # Service-specific hostname triggers non-wildcard cert (HTTP-01 compatible)
            - name: https-argocd
              protocol: HTTPS
              port: 443
              hostname: "${argoCDHostname}"
              tls:
                mode: Terminate
                certificateRefs:
                  # cert-manager creates this secret via annotation
                  - name: argocd-tls
              allowedRoutes:
                namespaces:
                  from: All
      ''
    ];
  };
}
