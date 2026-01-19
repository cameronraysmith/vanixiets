# step-ca ACME server module for easykubenix
#
# Deploys smallstep step-certificates as local ACME server for cert-manager.
# Uses pre-generated CA from sops-encrypted secrets.
#
# This module uses existingSecrets mode for clean GitOps integration:
# - CA certificates are provided via caCerts options (public, in git)
# - Certificates ConfigMap created by this module via kubernetes.resources
# - Config ConfigMap (ca.json, defaults.json) created by this module
# - Private keys provided via sopsSecretFile (encrypted SopsSecret CR)
# - SopsSecret creates Kubernetes Secrets BEFORE helm deployment
# - Helm chart mounts pre-existing resources, creates nothing
#
# The SopsSecret must create two secrets:
# - step-ca-step-certificates-ca-password (key: password)
# - step-ca-step-certificates-secrets (keys: root_ca_key, intermediate_ca_key)
#
# Resource creation order (via kluctl phases):
# 1. SopsSecret CRD registered (prio-10, easykubenix default)
# 2. SopsSecret CR applied (prio-15, cluster config)
# 3. Default phase: namespace, configmaps, helm release
# 4. sops-secrets-operator reconciles SopsSecret -> Kubernetes Secrets
# 5. step-ca pod starts with pre-existing secrets mounted
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

      # Helm release name determines secret/configmap name prefix
      # "step-ca" release -> "step-ca-step-certificates-*" resources
      fullname = "step-ca-step-certificates";

      # ca.json configuration for step-ca server
      caJson = builtins.toJSON {
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
                maxTLSCertDuration = "2160h";
                defaultTLSCertDuration = "720h";
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

      # defaults.json for step CLI
      defaultsJson = builtins.toJSON {
        ca-url = "https://step-ca.${cfg.namespace}.svc.cluster.local";
        ca-config = "/home/step/config/ca.json";
        fingerprint = "";
        root = "/home/step/certs/root_ca.crt";
      };

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

      # Create ConfigMaps for certificates and config
      kubernetes.resources.${cfg.namespace}.ConfigMap = {
        # Certificates ConfigMap (public certs, not sensitive)
        "${fullname}-certs".data = {
          "root_ca.crt" = rootCert;
          "intermediate_ca.crt" = intermediateCert;
        };
        # Config ConfigMap (ca.json and defaults.json)
        "${fullname}-config".data = {
          "ca.json" = caJson;
          "defaults.json" = defaultsJson;
        };
      };

      helm.releases.${moduleName} = {
        namespace = cfg.namespace;
        chart = chartPath;

        values = lib.recursiveUpdate {
          # Disable bootstrap and inject modes
          bootstrap.enabled = false;
          inject.enabled = false;

          # Use existingSecrets mode - helm creates nothing, mounts pre-existing resources
          existingSecrets = {
            enabled = true;
            ca = true; # Mount ca-password secret for --password-file flag
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
