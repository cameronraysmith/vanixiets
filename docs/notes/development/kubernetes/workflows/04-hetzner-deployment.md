---
title: Hetzner production deployment workflow
---

# Hetzner production deployment workflow

This workflow covers deploying the full production Kubernetes stack to Hetzner infrastructure.
The deployment follows a four-phase pattern: terranix provisions base VMs, clan configures NixOS with k3s prerequisites, easykubenix generates ClusterAPI manifests for cluster lifecycle management, then easykubenix generates the full application stack deployed via kluctl.

## Prerequisites

Complete the following before beginning this workflow.

Cluster foundation must be ready.
The ClusterAPI bootstrap (workflow 03) should be complete with the cloud cluster self-managing.
Verify cluster accessibility via kubeconfig by running `kubectl get nodes` and confirming all nodes are Ready.

DNS configuration for production services requires Cloudflare zone access.
Ensure the Cloudflare API token has `Zone:DNS:Edit` permissions for the target domain.
External-DNS will create records automatically once deployed.

SOPS decryption keys must be available for cluster bootstrap.
The `&ci` age key from `.sops.yaml` serves as the production decryption key.
Source this from Bitwarden or secure storage; never commit to git.

Local tooling requirements include `tofu` (OpenTofu), `clan`, `kluctl`, `kubectl`, `sops`, and `age`.
All are available via the repository's Nix flake.

## Phase 1: base infrastructure (terranix)

terranix provisions the base Hetzner Cloud VMs that will run k3s.
The existing cinnabar pattern in `modules/terranix/hetzner.nix` demonstrates the approach.

### terranix configuration

The hetzner.nix module defines machine specifications with an enable flag pattern.
Add a new machine definition for the k3s control plane.

```nix
# modules/terranix/hetzner.nix
machines = {
  # Existing cinnabar (zerotier coordinator)
  cinnabar = {
    enabled = true;
    serverType = "cx43";
    location = "fsn1";
    image = "debian-12";
    comment = "8 vCPU, 16GB RAM, 160GB SSD, legacy BIOS";
  };

  # k3s control plane
  kube-control = {
    enabled = true;
    serverType = "cpx31";  # 4 vCPU, 8GB RAM
    location = "fsn1";
    image = "debian-12";
    comment = "k3s control plane node";
  };

  # k3s worker nodes (optional, ClusterAPI manages scaling)
  kube-worker-01 = {
    enabled = false;  # ClusterAPI provisions workers
    serverType = "cpx21";
    location = "fsn1";
    image = "debian-12";
    comment = "k3s worker node template";
  };
};
```

### OpenTofu apply workflow

Generate and apply the terraform configuration.

```sh
# Generate terraform JSON from terranix
nix run .#terraform-generate

# Initialize terraform providers
cd terraform
tofu init

# Preview changes
tofu plan

# Apply infrastructure changes
tofu apply
```

### Verify VM provisioned

After `tofu apply` completes, verify the VM exists in Hetzner Cloud.

```sh
# Check terraform outputs
tofu output

# Verify SSH access (terranix generates ephemeral deploy key)
ssh -i .terraform-deploy-key root@<ip-from-output> 'hostname'

# Verify in Hetzner Cloud console
hcloud server list
```

The terraform configuration automatically triggers `clan machines install` via the `null_resource.install-*` provisioner.
Monitor the clan installation output for completion.

## Phase 2: NixOS configuration (clan)

Clan configures the NixOS base system with k3s prerequisites.
The machine module follows the cinnabar pattern in `modules/machines/nixos/`.

### Machine module structure

Create a k3s-ready NixOS machine module.

```nix
# modules/machines/nixos/kube-control/default.nix
{
  config,
  inputs,
  ...
}:
let
  flakeModules = config.flake.modules.nixos;
in
{
  flake.modules.nixos."machines/nixos/kube-control" =
    { config, pkgs, lib, ... }:
    {
      imports = [
        inputs.srvos.nixosModules.server
        inputs.srvos.nixosModules.hardware-hetzner-cloud
        inputs.home-manager.nixosModules.home-manager
      ]
      ++ (with flakeModules; [
        base
        ssh-known-hosts
        k3s-server  # k3s server module with Cilium prerequisites
      ]);

      _module.args.flake = inputs.self;
      nixpkgs.hostPlatform = "x86_64-linux";
      nixpkgs.config.allowUnfree = true;
      nixpkgs.overlays = [ inputs.self.overlays.default ];

      boot.zfs.devNodes = "/dev/disk/by-path";

      networking.hostName = "kube-control";
      system.stateVersion = "25.05";

      security.sudo.wheelNeedsPassword = false;

      systemd.network.networks."10-uplink" = {
        matchConfig.Name = "en*";
        networkConfig = {
          DHCP = "yes";
          IPv6AcceptRA = true;
        };
        dhcpV4Config.UseDNS = true;
        dhcpV6Config.UseDNS = true;
      };
    };
}
```

### k3s server module with Cilium prerequisites

The k3s server module configures kernel requirements, containerd, and k3s with bundled components disabled.
See `docs/notes/development/kubernetes/components/nixos-k3s-server.md` for the complete reference.

```nix
# modules/nixos/k3s-server/default.nix
{ config, lib, pkgs, ... }:
{
  # Kernel modules for Kubernetes networking
  boot.kernelModules = [
    "br_netfilter"
    "nf_conntrack"
    "overlay"
    "ip_tables"
    "ip6_tables"
    "ip6table_mangle"
    "ip6table_raw"
    "ip6table_filter"
  ];

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
    "net.ipv6.conf.default.forwarding" = 1;
    "net.bridge.bridge-nf-call-iptables" = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;
    "net.ipv4.conf.lxc*.rp_filter" = 0;
    "vm.overcommit_memory" = 1;
    "kernel.panic" = 10;
    "kernel.panic_on_oops" = 1;
  };

  # Firewall for Kubernetes
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 6443 10250 2379 2380 4240 4244 ];
    allowedUDPPorts = [ 8472 4789 ];
    trustedInterfaces = [ "cni+" "cilium+" "lxc+" ];
  };

  # k3s with Cilium prerequisites
  services.k3s = {
    enable = true;
    role = "server";
    clusterInit = true;  # First server initializes etcd
    tokenFile = config.sops.secrets.k3s-token.path;

    disable = [
      "flannel"
      "local-storage"
      "metrics-server"
      "servicelb"
      "traefik"
    ];

    extraFlags = [
      "--flannel-backend=none"
      "--disable-network-policy"
      "--disable-kube-proxy"
      "--disable-cloud-controller"
      "--tls-san=${config.networking.fqdn}"
      "--tls-san=${config.networking.hostName}"
      "--write-kubeconfig-mode=644"
    ];

    gracefulNodeShutdown = {
      enable = true;
      shutdownGracePeriod = "30s";
      shutdownGracePeriodCriticalPods = "10s";
    };
  };

  # System packages
  environment.systemPackages = with pkgs; [
    k3s
    kubectl
    k9s
    cilium-cli
  ];
}
```

### Clan deployment

Deploy the NixOS configuration via clan.

```sh
# Build the machine configuration
clan machines build kube-control

# Deploy to the provisioned VM
clan machines install kube-control \
  --update-hardware-config nixos-facter \
  --target-host root@<vm-ip> \
  --yes

# For subsequent updates
clan machines update kube-control
```

### Verify k3s running

After clan deployment completes, verify k3s is operational.

```sh
# SSH to the control plane
ssh cameron@kube-control

# Check k3s service status
systemctl status k3s

# Verify API server accessible
kubectl get nodes

# Copy kubeconfig to local machine
scp cameron@kube-control:/etc/rancher/k3s/k3s.yaml ~/.kube/config-kube-control

# Update server URL in kubeconfig to external IP
# Edit ~/.kube/config-kube-control, change server: https://127.0.0.1:6443
# to server: https://<external-ip>:6443

export KUBECONFIG=~/.kube/config-kube-control
kubectl get nodes
```

## Phase 3: cluster infrastructure (easykubenix full stage via kluctl)

With k3s running but no CNI, deploy the full infrastructure stack via easykubenix and kluctl.
The hetzkube pattern at `kubenix/full/default.nix` shows the enabled components.

### easykubenix configuration

Configure the full stage with all production components.

```nix
# modules/k8s/full/default.nix
{ config, lib, ... }:
{
  config = lib.mkIf (config.stage == "full") {
    # CNI (must be first)
    cilium.enable = true;

    # DNS
    coredns.enable = true;

    # Certificate management
    cert-manager.enable = true;
    cert-manager.bare = false;  # Include ClusterIssuer resources

    # Secrets management
    sops-secrets-operator.enable = true;  # If using sops-secrets-operator
    # OR
    # sealed-secrets.enable = true;  # If using sealed-secrets

    # Storage
    local-path-provisioner.enable = true;
    nix-csi.enable = true;

    # Ingress / Gateway
    # Cilium handles Gateway API natively when gatewayAPI.enabled = true

    # DNS automation
    external-dns.enable = true;

    # Observability
    metrics-server.enable = true;

    # Optional components
    cnpg.enable = true;  # CloudNative PostgreSQL
    vertical-pod-autoscaler.enable = true;
  };
}
```

### Component deployment order

Components have dependencies that dictate deployment order.
Cilium must deploy first because pods cannot schedule without a CNI.

The deployment sequence:

1. Cilium CNI - enables pod networking, pods transition from Pending to Running
2. CoreDNS - provides cluster DNS resolution
3. cert-manager - certificate lifecycle management
4. ClusterIssuer resources - Let's Encrypt production and staging issuers
5. sops-secrets-operator + age key bootstrap - enables encrypted secrets
6. local-path-provisioner - dynamic PV provisioning
7. nix-csi (optional) - Nix store volumes for pods
8. external-dns - automatic DNS record management
9. metrics-server - resource metrics for HPA/VPA

### kluctl deployment

Generate manifests and deploy via kluctl.

```sh
# Generate manifests from easykubenix
nix build .#k8s-manifests-full

# The build output contains kluctl-compatible structure
ls result/

# Deploy with kluctl
kluctl deploy \
  --context kube-control \
  --discriminator vanixiets-full \
  -y

# Or deploy incrementally for debugging
kluctl deploy \
  --context kube-control \
  --discriminator vanixiets-full \
  --include-tag cilium \
  -y

# Then add more components
kluctl deploy \
  --context kube-control \
  --discriminator vanixiets-full \
  --include-tag coredns \
  --include-tag cert-manager \
  -y
```

### Cilium deployment verification

After Cilium deploys, verify CNI functionality.

```sh
# Check Cilium pods
kubectl get pods -n kube-system -l k8s-app=cilium

# Verify Cilium status
kubectl exec -n kube-system ds/cilium -- cilium status

# Check kube-proxy replacement
kubectl exec -n kube-system ds/cilium -- cilium status | grep KubeProxyReplacement

# Verify endpoints
kubectl exec -n kube-system ds/cilium -- cilium endpoint list

# Run connectivity test
cilium connectivity test
```

See `docs/notes/development/kubernetes/components/cilium-cni.md` for detailed troubleshooting.

## Production TLS configuration

cert-manager with Let's Encrypt provides production TLS.
DNS01 challenges via Cloudflare enable wildcard certificates.

### Cloudflare credentials secret

Bootstrap the Cloudflare API token as a Kubernetes secret.
This is a chicken-and-egg problem: the secret must exist before sops-secrets-operator can decrypt other secrets.

```sh
# Create cert-manager namespace if not exists
kubectl create namespace cert-manager

# Create Cloudflare token secret (token from Bitwarden)
kubectl create secret generic cloudflare-api-token \
  --namespace cert-manager \
  --from-literal=token="$(bw get item cloudflare-dns-api-token --field notes)"
```

For GitOps workflows, this secret should be managed via SopsSecret after the operator is running.

### ClusterIssuer resources

Configure both staging (for testing) and production issuers.

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-staging-account-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token
              key: token
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token
              key: token
```

### Test certificate issuance

Verify Let's Encrypt integration before deploying applications.

```sh
# Create test certificate using staging issuer first
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-wildcard
  namespace: default
spec:
  secretName: test-wildcard-tls
  issuerRef:
    name: letsencrypt-staging
    kind: ClusterIssuer
  dnsNames:
    - "*.example.com"
    - example.com
  duration: 2160h
  renewBefore: 360h
EOF

# Watch certificate progress
kubectl describe certificate test-wildcard
kubectl get certificaterequest
kubectl get orders
kubectl get challenges

# After staging works, delete and recreate with production issuer
kubectl delete certificate test-wildcard
# Modify issuerRef.name to letsencrypt-prod and reapply
```

See `docs/notes/development/kubernetes/components/cert-manager.md` for detailed configuration.

## Secrets distribution

The sops-secrets-operator requires an age decryption key before it can process SopsSecret resources.

### Bootstrap age key

Create the age key secret in the operator namespace.
This is the only secret that must be created manually; all others can use SopsSecret resources.

```sh
# Create operator namespace
kubectl create namespace sops-secrets-operator

# Source age key from Bitwarden (never store in git)
bw get item "sops-ci-age-key" --field notes > /tmp/age-key.txt

# Create the secret
kubectl create secret generic sops-age-key-file \
  --namespace sops-secrets-operator \
  --from-file=key=/tmp/age-key.txt

# Clean up
rm /tmp/age-key.txt
```

### Deploy sops-secrets-operator

With the age key in place, deploy the operator via the full stage kluctl deployment or separately.

```sh
# If deploying separately
kluctl deploy \
  --context kube-control \
  --discriminator vanixiets-full \
  --include-tag sops-secrets-operator \
  -y
```

### SopsSecret resources

After the operator runs, create SopsSecret resources for application secrets.
See `docs/notes/development/kubernetes/components/sops-secrets-operator.md` for the complete workflow.

```sh
# Create plaintext SopsSecret
cat > /tmp/db-creds.yaml <<EOF
apiVersion: isindir.github.com/v1alpha3
kind: SopsSecret
metadata:
  name: database-credentials
  namespace: production
spec:
  secretTemplates:
    - name: postgres-credentials
      stringData:
        username: app_user
        password: super-secret-password
EOF

# Encrypt with SOPS
sops --encrypt \
  --encrypted-suffix Templates \
  /tmp/db-creds.yaml > k8s/secrets/production/database-credentials.enc.yaml

# Clean up plaintext
rm /tmp/db-creds.yaml

# Apply encrypted SopsSecret
kubectl apply -f k8s/secrets/production/database-credentials.enc.yaml

# Verify Secret created
kubectl get secret postgres-credentials -n production
```

## Verification

After full deployment, verify all components are operational.

### All pods running

```sh
# Check all namespaces for non-Running pods
kubectl get pods -A | grep -v Running | grep -v Completed

# System namespaces should be healthy
kubectl get pods -n kube-system
kubectl get pods -n cert-manager
kubectl get pods -n sops-secrets-operator
```

### Certificates issued

```sh
# List all certificates
kubectl get certificates -A

# Verify certificates are Ready
kubectl get certificates -A -o custom-columns=\
NAME:.metadata.name,\
NAMESPACE:.metadata.namespace,\
READY:.status.conditions[0].status,\
SECRET:.spec.secretName

# Check specific certificate
kubectl describe certificate <name> -n <namespace>
```

### DNS resolving

```sh
# Verify external-dns created records (check Cloudflare)
# Use dig or nslookup
dig app.example.com

# Verify in-cluster DNS
kubectl run -it --rm debug --image=busybox -- nslookup kubernetes.default.svc.cluster.local
```

### Services accessible

```sh
# Test Gateway/Ingress externally
curl -v https://app.example.com

# Port-forward for internal services
kubectl port-forward svc/internal-service 8080:80
curl localhost:8080
```

## Troubleshooting

### terranix/OpenTofu issues

The VM fails to provision when Hetzner API credentials are invalid or quota exceeded.

```sh
# Check terraform state
cd terraform
tofu show

# Verify Hetzner API token
export HCLOUD_TOKEN=$(bw get item hetzner-api-token --field notes)
hcloud server list

# Force resource recreation
tofu taint hcloud_server.kube-control
tofu apply
```

The clan install provisioner fails when SSH key is not properly generated.

```sh
# Check the deploy key exists
ls -la terraform/.terraform-deploy-key

# Test SSH manually
ssh -i terraform/.terraform-deploy-key root@<ip> 'echo success'

# Run clan install manually
clan machines install kube-control \
  --update-hardware-config nixos-facter \
  --target-host root@<ip> \
  -i terraform/.terraform-deploy-key \
  --yes
```

### Clan deployment failures

Build failures indicate Nix evaluation errors in the machine configuration.

```sh
# Build locally first to catch errors
clan machines build kube-control

# Check evaluation with verbose output
nix build .#nixosConfigurations.kube-control.config.system.build.toplevel --show-trace
```

Deployment failures indicate network or SSH issues.

```sh
# Test SSH access
ssh cameron@kube-control

# Check deployment logs
clan machines install kube-control --verbose

# If partial deployment, update instead
clan machines update kube-control
```

### Cilium networking problems

Pods stuck in Pending with CNI errors indicate Cilium is not running.

```sh
# Check Cilium pods
kubectl get pods -n kube-system -l k8s-app=cilium

# Check Cilium agent logs
kubectl logs -n kube-system -l k8s-app=cilium --tail=100

# Verify CNI configuration
kubectl exec -n kube-system ds/cilium -- ls /etc/cni/net.d/
```

Pod-to-pod connectivity failures indicate tunnel or routing issues.

```sh
# Check Cilium health
kubectl exec -n kube-system ds/cilium -- cilium-health status

# Check tunnel status
kubectl exec -n kube-system ds/cilium -- cilium bpf tunnel list

# Run connectivity test
cilium connectivity test --test pod-to-pod
```

See `docs/notes/development/kubernetes/components/cilium-cni.md` for comprehensive troubleshooting.

### Certificate issuance failures

Certificates stuck in pending state indicate issuer or challenge problems.

```sh
# Check certificate status
kubectl describe certificate <name> -n <namespace>

# Check CertificateRequest
kubectl get certificaterequest -n <namespace>
kubectl describe certificaterequest <name> -n <namespace>

# Check ACME Orders and Challenges
kubectl get orders -A
kubectl get challenges -A
kubectl describe challenge <name> -n <namespace>
```

DNS01 challenge failures indicate Cloudflare API issues.

```sh
# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager --tail=100

# Verify Cloudflare token secret
kubectl get secret cloudflare-api-token -n cert-manager -o yaml

# Test Cloudflare API manually
curl -X GET "https://api.cloudflare.com/client/v4/zones" \
  -H "Authorization: Bearer $(kubectl get secret cloudflare-api-token -n cert-manager -o jsonpath='{.data.token}' | base64 -d)"
```

See `docs/notes/development/kubernetes/components/cert-manager.md` for detailed troubleshooting.

### sops-secrets-operator issues

SopsSecret resources not creating Secrets indicate decryption failures.

```sh
# Check operator logs
kubectl logs -n sops-secrets-operator deployment/sops-secrets-operator --tail=100

# Verify age key secret
kubectl get secret sops-age-key-file -n sops-secrets-operator

# Check SopsSecret status
kubectl get sopssecret -A -o wide
kubectl describe sopssecret <name> -n <namespace>
```

See `docs/notes/development/kubernetes/components/sops-secrets-operator.md` for detailed troubleshooting.

## Related documentation

- `docs/notes/development/kubernetes/components/nixos-k3s-server.md` - k3s NixOS module configuration
- `docs/notes/development/kubernetes/components/cilium-cni.md` - Cilium CNI deployment and configuration
- `docs/notes/development/kubernetes/components/cert-manager.md` - Certificate management with cert-manager
- `docs/notes/development/kubernetes/components/sops-secrets-operator.md` - Secrets management workflow
- `docs/notes/development/kubernetes/components/nix-csi.md` - Nix store volumes for Kubernetes
- `modules/terranix/hetzner.nix` - terranix Hetzner Cloud configuration
- `modules/machines/nixos/cinnabar/` - Reference NixOS machine module pattern
