---
title: GitOps operations
---

# GitOps operations

This document covers day-2 operations for managing Kubernetes clusters using the vanixiets GitOps workflow.
The architecture uses easykubenix for manifest generation from Nix modules and kluctl for deployment with discriminator-based resource ownership.
This approach maintains all cluster state in version control while enabling safe, predictable updates.

## GitOps workflow overview

The vanixiets GitOps workflow follows a linear path from code changes through deployment.

Changes begin in Nix module definitions within the vanixiets repository.
Nix evaluation generates Kubernetes manifests as YAML files.
kluctl applies manifests to the target cluster with discriminator-based tracking.
Orphaned resources (those no longer in manifests) are pruned automatically.

The workflow supports two deployment stages.
The `capi` stage deploys ClusterAPI infrastructure resources that bootstrap and manage the cluster itself.
The `full` stage deploys all resources including application workloads.
Stage separation allows infrastructure-only updates without touching application state.

```text
                                  +-----------------+
                                  | Nix modules in  |
                                  | vanixiets repo  |
                                  +--------+--------+
                                           |
                                           v
                                  +--------+--------+
                                  | nix build       |
                                  | .#kubenix...    |
                                  +--------+--------+
                                           |
                                           v
                                  +--------+--------+
                                  | YAML manifests  |
                                  | in Nix store    |
                                  +--------+--------+
                                           |
                                           v
                                  +--------+--------+
                                  | kluctl deploy   |
                                  | --discriminator |
                                  +--------+--------+
                                           |
                                           v
                                  +--------+--------+
                                  | Kubernetes      |
                                  | cluster         |
                                  +-----------------+
```

### Discriminator-based resource ownership

kluctl applies a discriminator label to all deployed resources, enabling safe multi-tenant deployments and automatic pruning.
The discriminator value corresponds to the deployment stage (`capi` or `full`).

When kluctl deploys with `--prune`, it queries the cluster for resources matching the discriminator label.
Resources in the cluster but absent from current manifests are deleted.
This prevents resource accumulation from renamed or removed definitions.

Resources without the discriminator label remain untouched, allowing manual resources or other deployment tools to coexist.

## Making configuration changes

Configuration changes follow the standard Nix module pattern used throughout vanixiets.

### Editing existing resources

Locate the relevant Nix module in the easykubenix module tree.
The hetzkube reference organizes modules by component (cert-manager.nix, cilium.nix, capi.nix, etc.).

```nix
# Example: Adjusting Cilium configuration
{
  config,
  lib,
  ...
}:
let
  cfg = config.cilium;
in
{
  config = lib.mkIf cfg.enable {
    kubernetes.resources.kube-system.ConfigMap.cilium-config.data = {
      enable-bpf-masquerade = "true";
      ipam = "kubernetes";
    };
  };
}
```

After editing, rebuild manifests and review the diff before deployment.

### Adding new Kubernetes resources

Add resources to the appropriate namespace within a module.
easykubenix uses the pattern `kubernetes.resources.<namespace>.<Kind>.<name>`.

```nix
{
  kubernetes.resources.my-namespace = {
    # Create a ConfigMap
    ConfigMap.app-config.data = {
      "config.yaml" = builtins.toJSON {
        feature.enabled = true;
        database.host = "postgres.database.svc";
      };
    };

    # Create a Deployment
    Deployment.my-app.spec = {
      replicas = 2;
      selector.matchLabels.app = "my-app";
      template = {
        metadata.labels.app = "my-app";
        spec.containers.main = {
          image = "ghcr.io/org/my-app:v1.0.0";
          ports.http.containerPort = 8080;
        };
      };
    };

    # Create a Service
    Service.my-app.spec = {
      selector.app = "my-app";
      ports.http.port = 80;
      ports.http.targetPort = 8080;
    };
  };
}
```

Cluster-scoped resources (ClusterRole, ClusterIssuer, etc.) use the reserved namespace `none`.

```nix
{
  kubernetes.resources.none.ClusterRole.my-cluster-role.rules = [
    {
      apiGroups = [""];
      resources = ["pods"];
      verbs = ["get" "list" "watch"];
    }
  ];
}
```

### Version bumps for Helm charts

easykubenix integrates Helm charts through the `helm` module.
Update chart versions by modifying the chart reference.

```nix
{
  config,
  lib,
  ...
}:
let
  cfg = config.cert-manager;
in
{
  options.cert-manager = {
    enable = lib.mkEnableOption "cert-manager";
    chartVersion = lib.mkOption {
      type = lib.types.str;
      default = "v1.19.1";  # Update version here
      description = "cert-manager Helm chart version";
    };
  };

  config = lib.mkIf cfg.enable {
    # Helm chart rendering or importyaml reference
    importyaml.cert-manager.src =
      "https://github.com/cert-manager/cert-manager/releases/download/${cfg.chartVersion}/cert-manager.yaml";
  };
}
```

For charts rendered via `helm template`, the pattern differs.

```nix
{
  helm.releases.prometheus = {
    chart = pkgs.fetchurl {
      url = "https://github.com/prometheus-community/helm-charts/releases/download/kube-prometheus-stack-45.0.0/kube-prometheus-stack-45.0.0.tgz";
      hash = "sha256-...";
    };
    values = {
      grafana.enabled = true;
      prometheus.prometheusSpec.retention = "30d";
    };
  };
}
```

## Manifest generation

Manifest generation uses Nix evaluation to produce YAML files from module definitions.

### Building manifests

Generate manifests for the desired stage.

```sh
# Generate full deployment manifests
nix build .#kubenix.manifestYAMLFile --argstr stage full

# Generate CAPI-only manifests
nix build .#kubenix.manifestYAMLFile --argstr stage capi

# View the generated file path
ls -la result
```

The output is a single YAML file containing all resources as a Kubernetes List.
kluctl expects this format for deployment.

### Reviewing generated manifests

Inspect the generated YAML before deployment.

```sh
# View full manifest
cat result

# Search for specific resources
grep -A 20 "kind: Deployment" result

# Count resources by kind
grep "^kind:" result | sort | uniq -c
```

For structured inspection, use tools like `yq` or `jq` (after converting YAML to JSON).

```sh
# List all resource names and kinds
yq eval '.items[] | .kind + "/" + .metadata.name' result

# Extract specific resource
yq eval '.items[] | select(.kind == "Deployment" and .metadata.name == "my-app")' result
```

### Diff against running cluster

Compare generated manifests against cluster state before deployment.

```sh
# kluctl dry-run shows planned changes
kluctl deploy \
  --target local \
  --discriminator full \
  --project-dir "$(nix build .#kubenix.projectDir --print-out-paths --argstr stage full)" \
  --dry-run

# kubectl diff shows detailed resource differences
kubectl diff -f result
```

The kluctl dry-run output shows resources to be created, updated, or pruned.
kubectl diff provides line-by-line comparison of resource specifications.

## Deployment with kluctl

kluctl deploys manifests with discriminator-based tracking and optional pruning.

### Standard deployment workflow

Deploy with confirmation prompts.

```sh
# Build the kluctl project directory
PROJECT_DIR=$(nix build .#kubenix.projectDir --print-out-paths --argstr stage full)

# Deploy with interactive confirmation
kluctl deploy \
  --target local \
  --discriminator full \
  --project-dir "$PROJECT_DIR"
```

The deployment pauses before applying changes, displaying a summary of planned operations.
Confirm to proceed or abort to review further.

### Dry-run mode for preview

Preview changes without modifying the cluster.

```sh
kluctl deploy \
  --target local \
  --discriminator full \
  --project-dir "$PROJECT_DIR" \
  --dry-run
```

Dry-run validates manifests against the API server and shows what would change.
Use this before every production deployment.

### Non-interactive deployment

For CI/CD pipelines, use `--yes` to skip confirmation.

```sh
kluctl deploy \
  --target local \
  --discriminator full \
  --project-dir "$PROJECT_DIR" \
  --yes
```

### Pruning orphaned resources

Enable pruning to remove resources no longer in manifests.

```sh
kluctl deploy \
  --target local \
  --discriminator full \
  --project-dir "$PROJECT_DIR" \
  --prune \
  --yes
```

Pruning only affects resources with the matching discriminator label.
Resources deployed by other tools or manually created remain untouched.

Always run with `--dry-run` first to verify which resources will be pruned.

```sh
kluctl deploy \
  --target local \
  --discriminator full \
  --project-dir "$PROJECT_DIR" \
  --prune \
  --dry-run
```

### Rollback strategies

kluctl does not maintain deployment history internally.
Rollback requires reverting Nix module changes in git and redeploying.

```sh
# Revert to previous commit
git revert HEAD

# Rebuild and redeploy
PROJECT_DIR=$(nix build .#kubenix.projectDir --print-out-paths --argstr stage full)
kluctl deploy \
  --target local \
  --discriminator full \
  --project-dir "$PROJECT_DIR" \
  --yes
```

For faster rollback of Deployments, use kubectl directly.

```sh
# View rollout history
kubectl rollout history deployment/my-app -n my-namespace

# Rollback to previous revision
kubectl rollout undo deployment/my-app -n my-namespace

# Rollback to specific revision
kubectl rollout undo deployment/my-app -n my-namespace --to-revision=2
```

Note that kubectl rollback diverges cluster state from git.
Follow up by updating Nix modules to match the rolled-back state.

## Secrets management

Secrets in vanixiets use SOPS encryption with the sops-secrets-operator for Kubernetes-native decryption.
See the [sops-secrets-operator component documentation](../components/sops-secrets-operator.md) for detailed setup.

### Creating new SOPS-encrypted secrets

Create the plaintext SopsSecret resource locally (do not commit).

```yaml
# database-credentials.yaml
apiVersion: isindir.github.com/v1alpha3
kind: SopsSecret
metadata:
  name: database-credentials
  namespace: application
spec:
  secretTemplates:
    - name: postgres-credentials
      stringData:
        username: app_user
        password: super-secret-password
```

Encrypt using SOPS with the appropriate age key.

```sh
sops --encrypt \
  --encrypted-suffix Templates \
  database-credentials.yaml > k8s/secrets/local/database-credentials.enc.yaml
```

Delete the plaintext file.

```sh
rm database-credentials.yaml
```

### SopsSecret resources in Nix

Reference encrypted SopsSecret files in Nix modules.

```nix
{
  # Import pre-encrypted SopsSecret
  kubernetes.resources.application."isindir.github.com/v1alpha3".SopsSecret.database-credentials =
    builtins.fromJSON (builtins.readFile ./secrets/database-credentials.enc.json);
}
```

Alternatively, keep encrypted YAML files separate and apply them alongside easykubenix manifests.

### Updating existing secrets

Edit encrypted secrets in place using SOPS.

```sh
sops k8s/secrets/local/database-credentials.enc.yaml
```

SOPS opens the file in your editor, decrypting values for editing.
Save and exit to re-encrypt with updated values.

After updating, redeploy to sync changes.

```sh
kubectl apply -f k8s/secrets/local/database-credentials.enc.yaml
```

The sops-secrets-operator reconciles the SopsSecret and updates the Kubernetes Secret.

### Key rotation

Rotate age keys by re-encrypting secrets with new keys.

Update `.sops.yaml` with the new key configuration.

```yaml
creation_rules:
  - path_regex: k8s/secrets/local/.*\.yaml$
    key_groups:
      - age:
        - age1newkeyxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
        - age1oldkeybackupxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Re-encrypt existing secrets.

```sh
# Re-encrypt with new key configuration
for f in k8s/secrets/local/*.enc.yaml; do
  sops updatekeys "$f"
done
```

Deploy the new age private key to the cluster.

```sh
kubectl create secret generic sops-age-key-file \
  --namespace sops-secrets-operator \
  --from-file=key=/path/to/new-age-private-key.txt \
  --dry-run=client -o yaml | kubectl apply -f -
```

Restart the operator to pick up the new key.

```sh
kubectl rollout restart deployment/sops-secrets-operator -n sops-secrets-operator
```

## Scaling and node management

ClusterAPI manages node lifecycle through MachineDeployment resources.

### Scaling MachineDeployments

Adjust replica count in the Nix module.

```nix
{
  kubernetes.resources.${clusterName}.MachineDeployment."${clusterName}-workers-x86".spec = {
    replicas = 3;  # Increase from default
    # ... rest of spec
  };
}
```

Rebuild and deploy to apply scaling changes.

```sh
nix build .#kubenix.manifestYAMLFile --argstr stage capi
kluctl deploy --discriminator capi --project-dir result --yes
```

For immediate scaling without full redeploy, use kubectl directly.

```sh
kubectl scale machinedeployment hetzkube-workers-x86 \
  --namespace hetzkube \
  --replicas=5
```

Note that kubectl scaling diverges from git state.
Update Nix modules to match.

### Adding worker node types

Define new MachineDeployment and HCloudMachineTemplate resources.

```nix
{
  kubernetes.resources.${clusterName} = {
    # GPU worker pool
    MachineDeployment."${clusterName}-workers-gpu" = {
      metadata.labels.nodepool = "${clusterName}-workers-gpu";
      spec = {
        inherit clusterName;
        replicas = 1;
        selector = {};
        template = {
          metadata.labels = {
            nodepool = "${clusterName}-workers-gpu";
            "node.kubernetes.io/gpu" = "true";
          };
          spec = {
            bootstrap.configRef = {
              apiVersion = "bootstrap.cluster.x-k8s.io/v1beta1";
              kind = "KubeadmConfigTemplate";
              name = "${clusterName}-workers";
            };
            inherit clusterName;
            failureDomain = "hel1";
            infrastructureRef = {
              apiVersion = "infrastructure.cluster.x-k8s.io/v1beta1";
              kind = "HCloudMachineTemplate";
              name = "${clusterName}-workers-gpu";
            };
            version = "v${pkgs.kubernetes.version}";
          };
        };
      };
    };

    HCloudMachineTemplate."${clusterName}-workers-gpu".spec.template.spec = {
      imageName = "2505-x86";
      placementGroupName = "workers";
      type = "ccx33";  # Hetzner dedicated CPU for GPU workloads
    };
  };
}
```

### Node maintenance and drain

Drain nodes before maintenance.

```sh
# Cordon node to prevent new pods
kubectl cordon <node-name>

# Drain existing pods
kubectl drain <node-name> \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=300
```

For ClusterAPI-managed nodes, delete the Machine resource to trigger replacement.

```sh
# Find the Machine for a node
kubectl get machines -n hetzkube -o wide

# Delete to trigger replacement
kubectl delete machine <machine-name> -n hetzkube
```

ClusterAPI provisions a replacement node automatically based on MachineDeployment spec.

Uncordon after maintenance completes.

```sh
kubectl uncordon <node-name>
```

## Certificate management

cert-manager automates certificate lifecycle.
See the [cert-manager component documentation](../components/cert-manager.md) for setup details.

### Monitoring certificate expiry

List certificates and their status.

```sh
kubectl get certificates -A
kubectl get certificaterequests -A
kubectl get orders -A
kubectl get challenges -A
```

Check specific certificate details.

```sh
kubectl describe certificate <name> -n <namespace>
```

View certificate expiry from the Secret.

```sh
kubectl get secret <secret-name> -n <namespace> \
  -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | \
  openssl x509 -noout -enddate
```

### Manual certificate renewal

cert-manager renews certificates automatically before expiry (default: 15 days).
Force immediate renewal by deleting the Certificate resource.

```sh
kubectl delete certificate <name> -n <namespace>
```

cert-manager recreates the Certificate and issues a new one from the configured Issuer.

Alternatively, delete the Secret to trigger re-issuance.

```sh
kubectl delete secret <tls-secret-name> -n <namespace>
```

### Adding certificates for new services

Add Certificate resources in Nix modules.

```nix
{
  kubernetes.resources.my-namespace.Certificate.my-service-tls.spec = {
    secretName = "my-service-tls";
    issuerRef = {
      name = "letsencrypt-prod";
      kind = "ClusterIssuer";
    };
    dnsNames = [
      "my-service.example.com"
      "api.my-service.example.com"
    ];
    duration = "2160h";    # 90 days
    renewBefore = "360h";  # Renew 15 days before expiry
  };
}
```

For Ingress resources, use annotations for automatic certificate provisioning.

```nix
{
  kubernetes.resources.my-namespace.Ingress.my-service = {
    metadata.annotations = {
      "cert-manager.io/cluster-issuer" = "letsencrypt-prod";
    };
    spec = {
      ingressClassName = "traefik";
      tls = [{
        hosts = ["my-service.example.com"];
        secretName = "my-service-tls";
      }];
      rules = [{
        host = "my-service.example.com";
        http.paths = [{
          path = "/";
          pathType = "Prefix";
          backend.service = {
            name = "my-service";
            port.number = 80;
          };
        }];
      }];
    };
  };
}
```

## Monitoring and observability

### Checking deployment status

Use kluctl status commands for deployment overview.

```sh
# List all deployed resources
kluctl list --target local --discriminator full

# Check resource status
kluctl status --target local --discriminator full
```

### kubectl patterns for resource inspection

Common kubectl commands for cluster state inspection.

```sh
# Overview of all resources in a namespace
kubectl get all -n <namespace>

# Pod status and events
kubectl get pods -n <namespace> -o wide
kubectl describe pod <pod-name> -n <namespace>

# Recent events across cluster
kubectl get events --sort-by='.lastTimestamp' -A | tail -50

# Events for specific namespace
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Resource utilization
kubectl top nodes
kubectl top pods -n <namespace>
```

### Checking ClusterAPI resources

Monitor ClusterAPI-managed infrastructure.

```sh
# Cluster status
kubectl get clusters -A
kubectl describe cluster <name> -n <namespace>

# Machine status
kubectl get machines -A -o wide
kubectl describe machine <name> -n <namespace>

# MachineDeployment rollout status
kubectl get machinedeployments -A
kubectl describe machinedeployment <name> -n <namespace>

# Control plane status
kubectl get kubeadmcontrolplanes -A
kubectl describe kubeadmcontrolplane <name> -n <namespace>
```

### Log aggregation considerations

For production clusters, deploy a log aggregation solution.
Options include Loki (lightweight), Elasticsearch (full-featured), or cloud-provider logging.

Basic pod log access.

```sh
# Follow logs from a pod
kubectl logs -f <pod-name> -n <namespace>

# Logs from all pods with a label
kubectl logs -l app=my-app -n <namespace> --all-containers

# Previous container logs (after restart)
kubectl logs <pod-name> -n <namespace> --previous
```

## Disaster recovery

### Backup strategies

Critical state requiring backup.

*etcd* stores all Kubernetes cluster state.
For ClusterAPI-managed clusters, etcd runs on control plane nodes.
The kubeadmcontrolplane stacked etcd configuration means etcd data lives on the same nodes as the API server.

```sh
# Snapshot etcd on a control plane node
ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key
```

*Persistent volumes* contain application data.
Backup strategy depends on storage provider.
For Hetzner CSI, use Hetzner volume snapshots or application-level backups.

*Secrets* are encrypted in vanixiets git repository via SOPS.
Ensure age private keys are backed up separately (Bitwarden).

### Cluster recreation from Nix definitions

The primary disaster recovery path uses Nix definitions to recreate clusters.

1. Deploy new infrastructure via terranix (VMs, networks).
2. Bootstrap ClusterAPI management cluster.
3. Apply CAPI stage manifests to provision workload cluster.
4. Apply full stage manifests to deploy applications.

```sh
# Rebuild from Nix definitions
nix build .#kubenix.manifestYAMLFile --argstr stage capi
kluctl deploy --discriminator capi --project-dir result --yes

nix build .#kubenix.manifestYAMLFile --argstr stage full
kluctl deploy --discriminator full --project-dir result --yes
```

### State recovery

After cluster recreation, application state requires restoration.

Database restore from backup (application-specific).

```sh
# Example: PostgreSQL restore
kubectl exec -it postgres-0 -n database -- pg_restore -d app /backups/latest.dump
```

Persistent volume recreation depends on whether original volumes are accessible.
If using Hetzner volume snapshots, create volumes from snapshots via Hetzner API or terranix before cluster deployment.

## Future: nixidy/ArgoCD integration

The current architecture uses easykubenix + kluctl for the complete deployment lifecycle.
A future evolution separates concerns between infrastructure and application layers.

### When to transition from kluctl to ArgoCD

Consider ArgoCD when.

*Self-healing* requirements increase.
ArgoCD continuously monitors cluster state and reverts manual changes.
kluctl only reconciles on explicit deployment.

*Drift detection* becomes critical.
ArgoCD's UI shows real-time diff between desired and actual state.

*Multi-cluster deployments* scale beyond manageable manual deploys.
ArgoCD's ApplicationSets generate Applications across clusters.

*Team workflows* require approval gates.
ArgoCD's sync policies and RBAC provide deployment governance.

Retain kluctl for.

*ClusterAPI infrastructure* where control over exact deployment timing matters.

*Bootstrap sequences* where ArgoCD itself is not yet deployed.

*Development iteration* where immediate feedback is preferred over GitOps sync cycles.

### nixidy for Application manifest generation

nixidy generates ArgoCD Application resources from Nix definitions.
The output is plain YAML suitable for ArgoCD's rendered manifests pattern.

```nix
{
  applications.my-app = {
    namespace = "my-app";
    createNamespace = true;

    helm.releases.my-app = {
      chart = charts.myrepo.my-app;
      values = {
        replicas = 3;
        image.tag = "v1.0.0";
      };
    };
  };
}
```

Build produces ArgoCD Application YAML plus rendered manifests.

```sh
nixidy build .#prod
tree result/
# apps/
#   Application-my-app.yaml
# my-app/
#   Deployment-my-app.yaml
#   Service-my-app.yaml
#   ...
```

### Handoff boundary: easykubenix (infra) to nixidy (apps)

The proposed architecture separates deployment concerns.

*easykubenix + kluctl* manages.
- ClusterAPI resources (Cluster, MachineDeployment, etc.)
- CNI (Cilium)
- CSI (nix-csi, Hetzner CSI)
- Core addons (CoreDNS, cert-manager, sops-secrets-operator)
- ArgoCD itself

*nixidy + ArgoCD* manages.
- Application workloads
- Application-specific secrets
- Ingress configurations
- Monitoring and observability stacks

The boundary allows infrastructure updates via kluctl without triggering ArgoCD sync.
Application updates flow through ArgoCD's GitOps workflow with self-healing and drift detection.

### ArgoCD benefits

*Self-healing* reverts manual kubectl changes to match git state.
This enforces GitOps discipline and prevents configuration drift.

*Drift detection* shows exactly what differs between git and cluster.
The UI highlights out-of-sync resources for investigation.

*Sync policies* control when and how changes apply.
Options include automated sync, manual sync, and sync windows.

*RBAC* restricts who can sync which applications.
Integrates with OIDC providers for team-based access control.

*Multi-cluster management* deploys Applications across multiple clusters from a single ArgoCD instance.
ApplicationSets generate Applications dynamically based on cluster metadata.

*Health status* aggregates Kubernetes resource health into Application health.
Custom health checks extend to CRDs.

The transition from kluctl to ArgoCD is incremental.
Begin with non-critical applications and expand as confidence grows.
