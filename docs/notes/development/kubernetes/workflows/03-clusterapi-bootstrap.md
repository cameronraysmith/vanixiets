---
title: ClusterAPI bootstrap workflow
---

# ClusterAPI bootstrap workflow

This workflow covers bootstrapping a Hetzner Kubernetes cluster using ClusterAPI with the Hetzner provider (CAPH).
The local k3s-capi Colima profile serves as a temporary management cluster.
After ClusterAPI provisions the Hetzner cluster, a pivot operation transfers management to the cloud cluster, which then becomes self-managing.

## Architecture overview

The ClusterAPI bootstrap follows a temporary management cluster pattern:

1. Local k3s-capi cluster (Colima) provides the initial management plane
2. ClusterAPI controllers deploy to the local cluster
3. ClusterAPI provisions Hetzner VMs and orchestrates kubeadm bootstrap
4. Pivot operation moves ClusterAPI resources to the cloud cluster
5. Cloud cluster assumes self-management responsibility
6. Local k3s-capi cluster becomes disposable

This architecture avoids external dependencies for cluster lifecycle management.
The cloud cluster owns its own ClusterAPI resources after pivot, enabling infrastructure changes without an external management plane.

## Prerequisites

### Hetzner Cloud account

Create a Hetzner Cloud project and generate an API token with read/write permissions.
Store the token securely using SOPS or your preferred secrets management tool.

```bash
# Verify token validity
HCLOUD_TOKEN=<your-token> hcloud server-type list
```

### NixOS image snapshot

Create a NixOS snapshot in Hetzner Cloud with k3s prerequisites installed.
The hetzkube project provides nixos-anywhere automation for image creation.

```bash
# From hetzkube repository: build and deploy NixOS image
nix run --file . nixosConfigurations.image-x86_64-linux.config.lib.anywhereScript

# Clean the VM before snapshotting
sudo cloud-init clean
sudo journalctl --flush --rotate --vacuum-time=1s
```

After cleaning and shutting down the VM, create a snapshot through the Hetzner console or API.
Tag the snapshot with CAPH's expected format.

```bash
# Tag format expected by cluster-api-provider-hetzner
caph-image-name=2505-x86
caph-image-name=2505-arm  # For arm64 workers
```

The image name (2505-x86) is referenced in HCloudMachineTemplate resources and can be customized in easykubenix configuration.

### DNS configuration

ClusterAPI provisions control plane nodes that need a stable endpoint.
Create a DNS A record pointing to your intended control plane address before cluster creation.

```bash
# Example: create DNS record for control plane endpoint
# Domain: hetzkube.example.com
# Type: A
# Value: (will be updated with first control plane node IP)
```

The hetzkube pattern avoids external load balancers by using DNS directly.
When the first control plane node provisions, update the DNS record to point to its public IP.
External-dns can automate this after initial bootstrap.

### Age keys for SOPS

Generate age keys for SOPS encryption of cluster secrets.

```bash
# Generate key pair
age-keygen -o ~/.config/sops/age/keys.txt

# Extract public key for .sops.yaml
age-keygen -y ~/.config/sops/age/keys.txt
```

Configure `.sops.yaml` in your repository with the public key.
The node decryption key deploys to `/etc/nodekey` during image creation.

## Step 1: Start the bootstrap cluster

Start the k3s-capi Colima profile to provide a temporary management cluster.
This cluster exists solely for ClusterAPI bootstrapping and will be destroyed after pivot.

```bash
colima start --profile k3s-capi
```

Verify the cluster is ready.

```bash
# Check colima status
colima status --profile k3s-capi

# Verify kubectl connectivity
kubectl cluster-info
kubectl get nodes
```

Expected output shows a single-node k3s cluster ready to accept ClusterAPI controllers.

```
NAME                   STATUS   ROLES                  AGE   VERSION
lima-k3s-capi          Ready    control-plane,master   1m    v1.31.x
```

## Step 2: Install ClusterAPI

Initialize ClusterAPI with the required providers using clusterctl.
Version pinning prevents compatibility issues between CAPI core and infrastructure providers.

Check the CAPH compatibility matrix before selecting versions: https://github.com/syself/cluster-api-provider-hetzner#compatibility-with-cluster-api-and-kubernetes-versions

```bash
clusterctl init \
  --core cluster-api:v1.10.7 \
  --bootstrap kubeadm:v1.10.7 \
  --control-plane kubeadm:v1.10.7 \
  --infrastructure hetzner:v1.0.7
```

This installs four provider components:

| Provider | Purpose | Namespace |
|----------|---------|-----------|
| cluster-api | Core CRDs and controllers | capi-system |
| kubeadm bootstrap | Machine bootstrap configuration | capi-kubeadm-bootstrap-system |
| kubeadm control-plane | Control plane lifecycle | capi-kubeadm-control-plane-system |
| hetzner | Hetzner infrastructure provisioning | caph-system |

Verify all controllers are running.

```bash
kubectl get pods -A | grep -E '(capi|caph)'
```

Expected output shows all controller pods in Running state.

```
capi-kubeadm-bootstrap-system       capi-kubeadm-bootstrap-controller-manager-xxx       1/1     Running
capi-kubeadm-control-plane-system   capi-kubeadm-control-plane-controller-manager-xxx   1/1     Running
capi-system                         capi-controller-manager-xxx                         1/1     Running
caph-system                         caph-controller-manager-xxx                         1/1     Running
```

## Step 3: Deploy ClusterAPI resources via easykubenix

Deploy the cluster definition using easykubenix with the capi stage.
The stage separation ensures only ClusterAPI resources deploy during bootstrap.

```bash
# From easykubenix repository root
nix run --file . kubenix.deploymentScript --argstr stage capi
```

### kluctl discriminator

easykubenix uses kluctl for deployments, which applies a discriminator label to track resource ownership.

```yaml
kluctl.io/discriminator: capi
```

The discriminator prevents kluctl from pruning resources belonging to different stages.
Using the stage name as discriminator maintains clear ownership boundaries.

### Resources deployed

The capi stage deploys these ClusterAPI resources:

| Resource Kind | Name Pattern | Purpose |
|---------------|--------------|---------|
| Namespace | `<cluster-name>` | Resource boundary |
| Secret | hetzner | Hetzner API token |
| Cluster | `<cluster-name>` | Cluster specification |
| HetznerCluster | `<cluster-name>` | Hetzner-specific config |
| KubeadmControlPlane | `<cluster-name>-control-plane` | Control plane lifecycle |
| HCloudMachineTemplate | `<cluster-name>-control-plane` | Control plane VM template |
| MachineDeployment | `<cluster-name>-workers-x86` | Worker pool x86 |
| MachineDeployment | `<cluster-name>-workers-arm64` | Worker pool arm64 |
| HCloudMachineTemplate | `<cluster-name>-workers-x86` | Worker VM template x86 |
| HCloudMachineTemplate | `<cluster-name>-workers-arm64` | Worker VM template arm64 |
| KubeadmConfigTemplate | `<cluster-name>-workers` | Worker bootstrap config |
| MachineHealthCheck | Various | Node health monitoring |
| HCloudRemediationTemplate | Various | Failed node remediation |

Verify resources deployed correctly.

```bash
kubectl get clusters,hetznercluster,kubeadmcontrolplane -n <cluster-namespace>
```

## Step 4: Monitor cluster creation

Watch ClusterAPI reconcile the cluster resources and provision Hetzner infrastructure.

### Cluster status

```bash
# Watch cluster provisioning status
kubectl get cluster -n <cluster-namespace> -w

# Detailed cluster status
clusterctl describe cluster <cluster-name> -n <cluster-namespace>
```

### Machine provisioning

```bash
# Watch machine creation
kubectl get machines -n <cluster-namespace> -w

# Control plane machine status
kubectl get kubeadmcontrolplane -n <cluster-namespace>
```

Expected machine progression:

1. Pending: Machine resource created
2. Provisioning: Hetzner VM being created
3. Provisioned: VM created, waiting for bootstrap
4. Running: Node joined cluster successfully

### Control plane health

```bash
# Control plane replica status
kubectl get kubeadmcontrolplane -n <cluster-namespace> -o wide

# Example output showing 3/3 replicas ready
NAME                         CLUSTER     INITIALIZED   API SERVER AVAILABLE   REPLICAS   READY   UPDATED   UNAVAILABLE
hetzkube-control-plane       hetzkube    true          true                   3          3       3         0
```

### DNS record update

When the first control plane node reaches Provisioned state, update your DNS record to point to its public IP.
Without this update, kubeadm bootstrap will fail to reach the API server.

```bash
# Get the first control plane machine's IP from Hetzner console or API
hcloud server list
```

## Step 5: Troubleshooting machine provisioning

### Common issues

#### Machine stuck in Provisioning

Check the CAPH controller logs for Hetzner API errors.

```bash
kubectl logs -n caph-system deployment/caph-controller-manager -f
```

Common causes:
- Invalid Hetzner token in secret
- Missing or incorrectly tagged snapshot
- Hetzner API quota limits
- Invalid machine type for region

#### Machine stuck in Provisioned

The VM exists but kubeadm bootstrap failed.
SSH to the machine and check cloud-init logs.

```bash
# SSH to the provisioned VM
ssh root@<machine-ip>

# Check cloud-init status
cloud-init status --long

# Check kubeadm bootstrap logs
journalctl -u kubelet
cat /var/log/cloud-init-output.log
```

Common causes:
- DNS not resolving control plane endpoint
- Network connectivity issues
- Pre-kubeadm script failures

#### DNS resolution problems

Verify the control plane endpoint resolves from the provisioned node.

```bash
# From provisioned VM
nslookup <control-plane-hostname>
curl -k https://<control-plane-hostname>:6443/healthz
```

If DNS fails, update your DNS record with the correct control plane IP.

#### Image not found

Verify snapshot exists and is tagged correctly.

```bash
hcloud image list --type snapshot
# Check for caph-image-name label
hcloud image describe <image-id>
```

## Step 6: Extract cloud cluster kubeconfig

Once the cluster reports API Server Available, extract the kubeconfig.

```bash
# Create directory for kubeconfig
mkdir -p ./tmp

# Extract kubeconfig
clusterctl get kubeconfig <cluster-name> --namespace <cluster-namespace> > ./tmp/<cluster-name>.kubeconfig

# Verify connectivity to cloud cluster
KUBECONFIG=./tmp/<cluster-name>.kubeconfig kubectl get nodes
```

Expected output shows control plane and worker nodes.

```
NAME                         STATUS   ROLES           AGE   VERSION
<cluster-name>-control-plane-xxx   Ready    control-plane   10m   v1.31.x
<cluster-name>-workers-x86-xxx     Ready    <none>          5m    v1.31.x
```

Store the kubeconfig securely.
After pivot, this becomes the primary access method for the self-managing cluster.

## Step 7: Pivot ClusterAPI to cloud cluster

The pivot operation transfers ClusterAPI resource ownership from the local bootstrap cluster to the cloud cluster.
After pivot, the cloud cluster manages its own infrastructure lifecycle.

### Install ClusterAPI on cloud cluster

Initialize ClusterAPI on the cloud cluster with identical provider versions.

```bash
KUBECONFIG=./tmp/<cluster-name>.kubeconfig clusterctl init \
  --core cluster-api:v1.10.7 \
  --bootstrap kubeadm:v1.10.7 \
  --control-plane kubeadm:v1.10.7 \
  --infrastructure hetzner:v1.0.7
```

Verify controllers are running on cloud cluster.

```bash
KUBECONFIG=./tmp/<cluster-name>.kubeconfig kubectl get pods -A | grep -E '(capi|caph)'
```

### Execute pivot

Move ClusterAPI resources from local to cloud cluster.

```bash
clusterctl move --to-kubeconfig ./tmp/<cluster-name>.kubeconfig --namespace <cluster-namespace>
```

The move operation:
1. Pauses reconciliation on source cluster
2. Copies all ClusterAPI resources to target cluster
3. Deletes resources from source cluster
4. Resumes reconciliation on target cluster

### Verify pivot success

Confirm resources exist on cloud cluster and reconciliation works.

```bash
# List clusters on cloud cluster
KUBECONFIG=./tmp/<cluster-name>.kubeconfig kubectl get clusters -A

# Verify machines are still managed
KUBECONFIG=./tmp/<cluster-name>.kubeconfig kubectl get machines -A

# Verify local cluster no longer has ClusterAPI resources
kubectl get clusters -A
# Should return "No resources found"
```

The cloud cluster now manages its own infrastructure.
Scaling, upgrades, and node replacement operate without the bootstrap cluster.

## Step 8: Post-pivot cleanup

### Destroy local bootstrap cluster

The k3s-capi cluster is no longer needed after successful pivot.

```bash
# Delete the colima profile
colima delete --profile k3s-capi
```

Verify deletion.

```bash
colima list
# k3s-capi should not appear
```

### Archive bootstrap state (optional)

For audit purposes, archive the bootstrap cluster state before deletion.

```bash
# Export all ClusterAPI resources (before pivot)
kubectl get clusters,machines,hetznercluster -A -o yaml > ./tmp/bootstrap-state.yaml
```

### Update kubeconfig context

Add the cloud cluster kubeconfig to your default configuration.

```bash
# Merge with default kubeconfig
KUBECONFIG=~/.kube/config:./tmp/<cluster-name>.kubeconfig kubectl config view --flatten > ~/.kube/config.new
mv ~/.kube/config.new ~/.kube/config

# Set default context
kubectl config use-context <cluster-name>-admin@<cluster-name>
```

## Step 9: Troubleshooting

### Pivot failures

#### Resources stuck on source cluster

If pivot fails partway, resources may exist on both clusters.

```bash
# Check source cluster for remaining resources
kubectl get clusters,machines -A

# Check target cluster
KUBECONFIG=./tmp/<cluster-name>.kubeconfig kubectl get clusters,machines -A
```

Resolution: Manually delete duplicate resources from the source cluster after confirming they exist on target.

#### Target cluster unreachable

If the target cluster API server is unreachable during pivot, the operation fails.

```bash
# Verify target cluster connectivity
KUBECONFIG=./tmp/<cluster-name>.kubeconfig kubectl cluster-info
```

Ensure DNS resolves correctly and network allows API server access.

### ClusterAPI controller issues

#### Controller crash loops

Check controller logs and events.

```bash
kubectl describe deployment -n capi-system capi-controller-manager
kubectl logs -n capi-system deployment/capi-controller-manager --previous
```

Common causes:
- Resource quota limits
- CRD version mismatches
- Secret access issues

### Node replacement after pivot

After pivot, the cloud cluster manages node lifecycle.
To replace a failed node:

```bash
# Delete the failed machine (ClusterAPI will create replacement)
KUBECONFIG=./tmp/<cluster-name>.kubeconfig kubectl delete machine <machine-name> -n <cluster-namespace>

# Watch replacement provisioning
KUBECONFIG=./tmp/<cluster-name>.kubeconfig kubectl get machines -n <cluster-namespace> -w
```

### Scaling the cluster

Adjust MachineDeployment replicas for worker scaling.

```bash
KUBECONFIG=./tmp/<cluster-name>.kubeconfig kubectl scale machinedeployment <cluster-name>-workers-x86 \
  --replicas=3 -n <cluster-namespace>
```

Control plane scaling requires careful coordination.
Adjust KubeadmControlPlane replicas and ensure odd numbers for etcd quorum.

## Related components

- Colima profile setup: See [01-environment-setup.md](./01-environment-setup.md) for k3s-capi profile creation
- NixOS k3s module: See [nixos-k3s-server.md](../components/nixos-k3s-server.md)
- Cilium CNI deployment: Deploy after ClusterAPI bootstrap via easykubenix full stage
- External-dns: Takes over DNS management after initial bootstrap

## References

- ClusterAPI documentation: https://cluster-api.sigs.k8s.io/
- Hetzner provider (CAPH): https://github.com/syself/cluster-api-provider-hetzner
- hetzkube reference: `/Users/crs58/projects/sciops-workspace/hetzkube/README.md`
- easykubenix capi module: `/Users/crs58/projects/sciops-workspace/hetzkube/kubenix/modules/capi.nix`
