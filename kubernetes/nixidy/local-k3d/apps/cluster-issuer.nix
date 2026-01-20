# ClusterIssuer Application for step-ca ACME integration
#
# Creates ClusterIssuer pointing to step-ca's ACME endpoint.
# Enables automated TLS certificate issuance via ACME protocol.
#
# Sync wave 1: after cert-manager (0), before test certificates (2).
{ lib, ... }:
let
  # step-ca service endpoint in step-ca namespace
  stepCaNamespace = "step-ca";
  stepCaServiceName = "step-ca-step-certificates";
  stepCaAcmeProvisioner = "acme";
  stepCaAcmeUrl = "https://${stepCaServiceName}.${stepCaNamespace}.svc.cluster.local/acme/${stepCaAcmeProvisioner}/directory";
in
{
  applications.cluster-issuer = {
    # ClusterIssuer is cluster-scoped, but Application needs a namespace
    # Use cert-manager namespace for organization
    namespace = "cert-manager";

    # Standard sync policy for Phase 4 native
    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
    };

    # Sync wave 1: after cert-manager at wave 0
    annotations."argocd.argoproj.io/sync-wave" = "1";

    # Raw Kubernetes resources (not Helm)
    resources = {
      # step-ca ACME ClusterIssuer
      "cert-manager.io"."v1".ClusterIssuer.step-ca-acme = {
        spec = {
          acme = {
            # step-ca ACME endpoint
            server = stepCaAcmeUrl;

            # Email for ACME account (required but not used for internal CA)
            email = "admin@local.cluster";

            # Secret to store ACME account private key
            privateKeySecretRef = {
              name = "step-ca-acme-account-key";
            };

            # Skip TLS verification for internal CA
            # step-ca uses self-signed certificates
            skipTLSVerify = true;

            # Solvers for ACME challenges
            # HTTP-01 is simplest for internal cluster use
            solvers = [
              {
                # Default solver: HTTP-01 challenge
                # Works for any certificate request without ingress dependencies
                http01 = {
                  ingress = {
                    # Empty class: use default ingress controller
                    # For local dev, we may not have ingress configured
                  };
                };
              }
            ];
          };
        };
      };

      # Alternative: self-signed issuer for testing without ACME
      # Uncomment if step-ca ACME has issues
      # "cert-manager.io"."v1".ClusterIssuer.self-signed = {
      #   spec = {
      #     selfSigned = {};
      #   };
      # };
    };

    # Ignore status conditions (reconciled by cert-manager)
    ignoreDifferences = {
      ClusterIssuer-step-ca-acme = {
        group = "cert-manager.io";
        kind = "ClusterIssuer";
        name = "step-ca-acme";
        jsonPointers = [
          "/status"
        ];
      };
    };
  };
}
