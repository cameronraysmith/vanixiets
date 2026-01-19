# step-ca ACME server module for easykubenix
#
# Deploys smallstep step-certificates as local ACME server for cert-manager.
# Uses pre-generated CA from sops-encrypted secrets.
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

    # CA certificates are read from cluster-local paths
    # Private keys must be provided at deployment time via sops
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
    in
    lib.mkIf cfg.enable {
      # Create namespace
      kubernetes.objects = [
        {
          apiVersion = "v1";
          kind = "Namespace";
          metadata.name = cfg.namespace;
        }
      ];

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
              # Empty password for local dev (keys are unencrypted)
              ca_password = "";

              x509 = {
                enabled = true;
                # These will be populated from sops secret at deployment time
                # The helm chart expects the raw PEM content here
                # For now, use placeholder that will be overridden
                root_ca_key = "PLACEHOLDER_ROOT_KEY";
                intermediate_ca_key = "PLACEHOLDER_INTERMEDIATE_KEY";
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
