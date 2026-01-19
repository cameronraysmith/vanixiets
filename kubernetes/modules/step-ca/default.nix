# step-ca ACME server module for easykubenix
#
# Deploys smallstep step-certificates as local ACME server for cert-manager.
# Uses pre-generated CA from sops-encrypted secrets.
#
# This module integrates with sops-secrets-operator for secret management:
# - CA certificates are provided via caCerts options (public, in git)
# - Private keys are provided via sopsSecretFile (encrypted SopsSecret CR)
# - SopsSecret creates Kubernetes Secrets that the helm chart mounts
#
# The SopsSecret must create two secrets:
# - step-ca-step-certificates-ca-password (key: password)
# - step-ca-step-certificates-secrets (keys: root_ca_key, intermediate_ca_key)
#
# Receives step-ca-src from flake inputs via specialArgs to avoid
# impure fetchTree calls during pure evaluation.
{
  config,
  lib,
  pkgs,
  step-ca-src,
  ...
}:
let
  moduleName = "step-ca";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;

    version = lib.mkOption {
      type = lib.types.str;
      default = "1.29.0";
      description = "step-certificates chart version (informational, chart from flake input)";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "step-ca";
      description = "Namespace for step-ca deployment";
    };

    dnsNames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "step-ca.step-ca.svc.cluster.local"
        "step-ca.step-ca.svc"
        "step-ca"
      ];
      description = "DNS names for the step-ca service";
    };

    acme = {
      provisioner = lib.mkOption {
        type = lib.types.str;
        default = "acme";
        description = "Name of the ACME provisioner";
      };
    };

    # CA certificates are read from cluster-local paths (public, committed to git)
    caCerts = {
      rootCert = lib.mkOption {
        type = lib.types.path;
        description = "Path to root CA certificate (PEM)";
      };
      intermediateCert = lib.mkOption {
        type = lib.types.path;
        description = "Path to intermediate CA certificate (PEM)";
      };
    };

    # SopsSecret file containing encrypted private keys
    # The SopsSecret must create secrets matching helm chart expectations:
    # - step-ca-step-certificates-ca-password with 'password' key
    # - step-ca-step-certificates-secrets with 'root_ca_key', 'intermediate_ca_key' keys
    sopsSecretFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to encrypted SopsSecret YAML file for CA private keys";
    };

    helmValues = lib.mkOption {
      type = lib.types.anything;
      default = { };
      description = "Additional Helm values to merge";
    };
  };

  config =
    let
      # Use flake input for chart source
      src = step-ca-src;
      chartPath = "${src}/step-certificates";

      # Read certificates from provided paths
      rootCert = builtins.readFile cfg.caCerts.rootCert;
      intermediateCert = builtins.readFile cfg.caCerts.intermediateCert;

      # Create derivation for SopsSecret file (importyaml requires derivation, not path)
      sopsSecretDrv = lib.mkIf (cfg.sopsSecretFile != null) (
        pkgs.runCommand "step-ca-sopssecret" { } ''
          cp ${cfg.sopsSecretFile} $out
        ''
      );
    in
    lib.mkIf cfg.enable {
      # Create namespace using kubernetes.resources (easykubenix pattern)
      # "none" namespace means cluster-scoped resource
      kubernetes.resources.none.Namespace.${cfg.namespace} = { };

      # Deploy SopsSecret CR for private keys (processed by sops-secrets-operator)
      # This creates the Kubernetes Secrets that the helm chart expects
      importyaml."${moduleName}-secrets" = lib.mkIf (cfg.sopsSecretFile != null) {
        src = sopsSecretDrv;
      };

      helm.releases.${moduleName} = {
        namespace = cfg.namespace;
        chart = chartPath;

        values = lib.recursiveUpdate {
          # Inject pre-generated CA certificates
          inject = {
            enabled = true;

            certificates = {
              root_ca = rootCert;
              intermediate_ca = intermediateCert;
            };

            secrets = {
              # Password for CA key encryption (empty = unencrypted keys)
              # Note: Empty string causes helm to skip creating the ca-password secret.
              # SopsSecret operator creates it instead with the correct `password` key.
              # On fresh deploys, may need `kubectl annotate sopssecret -n step-ca step-ca-secrets reconcile=$(date +%s)`
              # to trigger re-reconciliation after helm-created secrets are cleaned up.
              ca_password = "";

              x509 = {
                enabled = true;
                # Placeholder values - SopsSecret operator will overwrite these
                # secrets with the actual encrypted private keys from the SopsSecret CR.
                # The helm chart creates the secret structure, SopsSecret provides content.
                root_ca_key = "PLACEHOLDER_OVERWRITTEN_BY_SOPSSECRET";
                intermediate_ca_key = "PLACEHOLDER_OVERWRITTEN_BY_SOPSSECRET";
              };

              ssh.enabled = false;
            };

            config = {
              files = {
                "ca.json" = {
                  root = "/home/step/certs/root_ca.crt";
                  federateRoots = [ ];
                  crt = "/home/step/certs/intermediate_ca.crt";
                  key = "/home/step/secrets/intermediate_ca_key";
                  address = ":9000";
                  insecureAddress = "";
                  dnsNames = cfg.dnsNames;

                  logger.format = "json";

                  db = {
                    type = "badgerv2";
                    dataSource = "/home/step/db";
                  };

                  authority = {
                    enableAdmin = false;
                    provisioners = [
                      {
                        type = "ACME";
                        name = cfg.acme.provisioner;
                        forceCN = true;
                        claims = {
                          # Default certificate validity
                          maxTLSCertDuration = "2160h"; # 90 days
                          defaultTLSCertDuration = "720h"; # 30 days
                        };
                      }
                    ];
                  };

                  tls = {
                    cipherSuites = [
                      "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256"
                      "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256"
                    ];
                    minVersion = 1.2;
                    maxVersion = 1.3;
                    renegotiation = false;
                  };
                };

                "defaults.json" = {
                  ca-url = "https://step-ca.${cfg.namespace}.svc.cluster.local";
                  ca-config = "/home/step/config/ca.json";
                  fingerprint = "";
                  root = "/home/step/certs/root_ca.crt";
                };
              };
            };
          };

          # Service configuration
          service = {
            type = "ClusterIP";
            port = 443;
            targetPort = 9000;
          };

          # Persistence for badger database
          ca = {
            db = {
              enabled = true;
              persistent = true;
              accessModes = [ "ReadWriteOnce" ];
              size = "1Gi";
            };
          };

          # Resource limits for local dev
          resources = {
            requests = {
              cpu = "100m";
              memory = "128Mi";
            };
            limits = {
              cpu = "500m";
              memory = "256Mi";
            };
          };

          # Single replica for local dev
          replicaCount = 1;
        } cfg.helmValues;
      };
    };
}
