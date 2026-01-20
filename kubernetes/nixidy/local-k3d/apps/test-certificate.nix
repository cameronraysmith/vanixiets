# Test Certificate Application for verification
#
# Creates a test Certificate to verify cert-manager and ClusterIssuer work correctly.
# Issues a TLS certificate using the step-ca ACME ClusterIssuer.
#
# Sync wave 2: after ClusterIssuer (1).
{ lib, ... }:
let
  # Test namespace for certificate verification
  testNamespace = "cert-manager-test";
in
{
  applications.test-certificate = {
    namespace = testNamespace;

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

    # Raw Kubernetes resources
    resources = {
      # Test Certificate requesting TLS cert from step-ca ACME
      "cert-manager.io"."v1".Certificate.test-cert = {
        metadata.namespace = testNamespace;
        spec = {
          # Secret to store the issued certificate
          secretName = "test-cert-tls";

          # Certificate duration and renewal
          duration = "24h";
          renewBefore = "8h";

          # Reference to ClusterIssuer
          issuerRef = {
            name = "step-ca-acme";
            kind = "ClusterIssuer";
          };

          # Certificate subject
          commonName = "test.local.cluster";

          # DNS SANs
          dnsNames = [
            "test.local.cluster"
            "test.${testNamespace}.svc.cluster.local"
          ];

          # Private key configuration
          privateKey = {
            algorithm = "ECDSA";
            size = 256;
          };

          # Usages for TLS
          usages = [
            "server auth"
            "client auth"
          ];
        };
      };
    };

    # Ignore status conditions (reconciled by cert-manager)
    ignoreDifferences = {
      Certificate-test-cert = {
        group = "cert-manager.io";
        kind = "Certificate";
        name = "test-cert";
        namespace = testNamespace;
        jsonPointers = [
          "/status"
        ];
      };
      # The TLS secret is managed by cert-manager, not ArgoCD
      Secret-test-cert-tls = {
        group = "";
        kind = "Secret";
        name = "test-cert-tls";
        namespace = testNamespace;
        jsonPointers = [ "/data" ];
      };
    };
  };
}
