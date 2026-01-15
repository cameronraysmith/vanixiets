---
title: Local development workflow
---

# Local development workflow

This workflow covers day-to-day Kubernetes development using the k3s-dev Colima profile.
The k3s-dev profile provides a persistent local cluster with production-parity configuration for iterating on applications, testing deployments, and validating configurations before promoting to production.

## Starting the development cluster

The k3s-dev Colima profile runs a NixOS VM via Rosetta on aarch64-darwin hosts.
Start the profile and verify cluster health before beginning work.

### Starting Colima

```bash
# Start the k3s-dev profile
colima start --profile k3s-dev

# Verify the VM is running
colima status --profile k3s-dev
```

The profile configuration lives in `~/.colima/k3s-dev/colima.yaml`.
On first start, the NixOS system builds and k3s initializes, which may take several minutes.

### Verifying cluster health

```bash
# Check node status
kubectl get nodes

# Verify system pods are running (before Cilium deployment, pods may be Pending)
kubectl get pods -n kube-system

# View cluster info
kubectl cluster-info
```

The node should show `Ready` status once k3s has fully initialized.
System pods will remain `Pending` or `ContainerCreating` until Cilium CNI is deployed.

### Accessing kubeconfig

The k3s kubeconfig is automatically merged into your default kubeconfig via Colima.
Set the context explicitly if you have multiple clusters configured.

```bash
# List available contexts
kubectl config get-contexts

# Set k3s-dev as current context
kubectl config use-context colima-k3s-dev

# Verify current context
kubectl config current-context
```

For troubleshooting, you can also SSH into the VM and access the kubeconfig directly at `/etc/rancher/k3s/k3s.yaml`.

```bash
# SSH into the VM
colima ssh --profile k3s-dev

# Inside the VM, check k3s status
sudo k3s kubectl get nodes
```

## Deploying core infrastructure

After cluster startup, deploy the core infrastructure components in order.
Cilium must be deployed first since it provides pod networking.

### Cilium CNI deployment

Cilium provides eBPF-based networking, replacing flannel and kube-proxy.
Deploy Cilium immediately after k3s starts, as pods cannot schedule without a CNI.

For local development, use the easykubenix Helm release with local configuration.

```nix
# infrastructure/cilium/default.nix
{ config, lib, ... }:
{
  helm.releases.cilium = {
    namespace = "kube-system";
    chart = "${ciliumSrc}/install/kubernetes/cilium";

    values = {
      # Core networking
      kubeProxyReplacement = true;
      routingMode = "tunnel";
      tunnelProtocol = "geneve";
      ipam.mode = "kubernetes";
      bpf.masquerade = true;

      # Local development settings
      k8sServiceHost = "127.0.0.1";
      k8sServicePort = 6443;

      # Single-replica for local
      operator.replicas = 1;

      # Minimal Hubble for local
      hubble.enabled = true;
      hubble.relay.enabled = false;
      hubble.ui.enabled = false;

      # Gateway API
      gatewayAPI.enabled = true;
    };
  };
}
```

Generate and apply the manifests.

```bash
# Generate Cilium manifests
nix build .#clusters.local.cilium

# Apply to cluster
kluctl deploy -t local --yes

# Verify Cilium status
kubectl get pods -n kube-system -l k8s-app=cilium
kubectl exec -n kube-system ds/cilium -- cilium status
```

Once Cilium is running, previously pending pods should transition to `Running`.

### step-ca deployment for local TLS

step-ca provides a local ACME certificate authority for issuing TLS certificates.
This enables HTTPS for local services without external CA dependencies.

```nix
# infrastructure/step-ca/default.nix
{ config, lib, ... }:
{
  helm.releases.step-certificates = {
    namespace = "step-ca";
    chart = charts.smallstep.step-certificates;

    values = {
      # Local provisioner configuration
      inject.config.address = ":9000";
      inject.config.db.type = "badger";
      inject.config.db.dataSource = "/home/step/db";

      # ACME provisioner for cert-manager
      inject.config.authority.provisioners = [
        {
          type = "ACME";
          name = "acme";
        }
      ];
    };
  };
}
```

### cert-manager with step-ca ClusterIssuer

cert-manager automates certificate provisioning via the step-ca ACME endpoint.

```nix
# infrastructure/cert-manager/default.nix
{ config, lib, ... }:
{
  helm.releases.cert-manager = {
    namespace = "cert-manager";
    chart = charts.jetstack.cert-manager;

    values = {
      installCRDs = true;
    };
  };

  # ClusterIssuer for step-ca
  kubernetes.resources.none.ClusterIssuer.step-ca-acme = {
    spec = {
      acme = {
        server = "https://step-certificates.step-ca.svc.cluster.local:9000/acme/acme/directory";
        privateKeySecretRef.name = "step-ca-acme-account";
        solvers = [
          {
            http01.ingress.ingressClassName = "cilium";
          }
        ];
      };
    };
  };
}
```

### sops-secrets-operator for secrets

sops-secrets-operator decrypts sops-encrypted secrets in the cluster.

```nix
# infrastructure/sops-secrets-operator/default.nix
{ config, lib, ... }:
{
  helm.releases.sops-secrets-operator = {
    namespace = "sops-system";
    chart = charts.isindir.sops-secrets-operator;

    values = {
      # Local development typically uses age keys
      # Configure your age key path here
    };
  };
}
```

## Working with easykubenix

easykubenix generates Kubernetes manifests from Nix expressions using the kubenix library.
The kluctl deployment tool applies these manifests with diff preview and rollback capabilities.

### Project structure for local development

Organize your cluster configuration with environment-specific stages.

```
clusters/
  local/
    default.nix      # Local stage configuration
    cilium.nix       # Cilium with local overrides
    apps/
      myapp.nix      # Application deployments
  production/
    default.nix      # Production stage configuration
    cilium.nix       # Cilium with production settings
```

### Stage configuration

Define stages for local and production environments.

```nix
# clusters/local/default.nix
{ inputs, ... }:
{
  imports = [
    ./cilium.nix
    ./apps
  ];

  # Local stage settings
  stage = "local";
  clusterHost = "127.0.0.1";

  # Enable development features
  cilium.isLocal = true;
}
```

### Generating manifests

Build manifests using the flake output.

```bash
# Build local stage manifests
nix build .#clusters.local

# Inspect generated manifests
ls -la result/

# View a specific manifest
cat result/kube-system/cilium.yaml
```

### kluctl deployment workflow

kluctl provides diff-based deployment with approval workflow.

```bash
# Preview changes (diff against cluster state)
kluctl diff -t local

# Deploy with confirmation
kluctl deploy -t local

# Deploy without confirmation (for automation)
kluctl deploy -t local --yes

# Rollback to previous state
kluctl rollback -t local
```

The target `-t local` corresponds to a kluctl target configuration referencing your local cluster context.

```yaml
# .kluctl.yaml
targets:
  - name: local
    context: colima-k3s-dev
    args:
      stage: local
```

## DNS and ingress

Local services use sslip.io for automatic DNS resolution without modifying `/etc/hosts`.
sslip.io returns the embedded IP address for any subdomain query.

### sslip.io pattern explanation

sslip.io is a DNS service that resolves hostnames containing IP addresses to those addresses.
The pattern `<name>.<ip>.sslip.io` resolves to `<ip>`.

```bash
# Examples
myapp.10.0.2.15.sslip.io  -> 10.0.2.15
api.192.168.5.1.sslip.io  -> 192.168.5.1
```

First, find your cluster's ingress IP address.

```bash
# Get the node IP (for single-node clusters)
kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'

# Or get the LoadBalancer IP if using Cilium LB
kubectl get svc -n kube-system cilium-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### Creating Ingress resources

Use the node IP in your Ingress host field.

```nix
# apps/myapp/default.nix
{ config, lib, ... }:
let
  nodeIP = "10.0.2.15";  # Replace with actual IP
in
{
  kubernetes.resources.default.Ingress.myapp = {
    metadata.annotations = {
      "cert-manager.io/cluster-issuer" = "step-ca-acme";
    };
    spec = {
      ingressClassName = "cilium";
      tls = [
        {
          hosts = [ "myapp.${nodeIP}.sslip.io" ];
          secretName = "myapp-tls";
        }
      ];
      rules = [
        {
          host = "myapp.${nodeIP}.sslip.io";
          http.paths = [
            {
              path = "/";
              pathType = "Prefix";
              backend.service = {
                name = "myapp";
                port.number = 8080;
              };
            }
          ];
        }
      ];
    };
  };
}
```

### Accessing services via browser

After deploying the Ingress, access your service.

```bash
# Get the ingress host
kubectl get ingress myapp -o jsonpath='{.spec.rules[0].host}'

# Open in browser (with HTTP until TLS is configured)
open http://myapp.10.0.2.15.sslip.io

# Or with HTTPS after certificates are issued
open https://myapp.10.0.2.15.sslip.io
```

### Cilium Gateway API alternative

Gateway API provides more expressive routing than Ingress.
Use this for complex routing requirements.

```nix
# Gateway resource
kubernetes.resources.default.Gateway.main-gateway = {
  spec = {
    gatewayClassName = "cilium";
    listeners = [
      {
        name = "http";
        port = 80;
        protocol = "HTTP";
      }
      {
        name = "https";
        port = 443;
        protocol = "HTTPS";
        tls = {
          mode = "Terminate";
          certificateRefs = [
            {
              name = "gateway-tls";
            }
          ];
        };
      }
    ];
  };
};

# HTTPRoute for application
kubernetes.resources.default.HTTPRoute.myapp-route = {
  spec = {
    parentRefs = [
      { name = "main-gateway"; }
    ];
    hostnames = [ "myapp.${nodeIP}.sslip.io" ];
    rules = [
      {
        matches = [
          { path = { type = "PathPrefix"; value = "/"; }; }
        ];
        backendRefs = [
          { name = "myapp"; port = 8080; }
        ];
      }
    ];
  };
};
```

## TLS certificate workflow

cert-manager with step-ca provides automated TLS certificate provisioning for local development.
Certificates are issued via the ACME protocol, matching production workflows.

### Requesting certificates via cert-manager

Annotate Ingress resources to trigger certificate provisioning.

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: step-ca-acme
spec:
  tls:
    - hosts:
        - myapp.10.0.2.15.sslip.io
      secretName: myapp-tls
```

cert-manager creates a Certificate resource, initiates the ACME challenge, and stores the issued certificate in the specified Secret.

### step-ca ACME flow

The ACME flow for local development follows these steps.

1. cert-manager creates an Order with step-ca
2. step-ca issues an HTTP-01 challenge
3. cert-manager creates a temporary Ingress to serve the challenge
4. step-ca validates the challenge response
5. step-ca issues the certificate
6. cert-manager stores the certificate in the TLS Secret

Monitor the certificate request.

```bash
# Check Certificate status
kubectl get certificates

# Check CertificateRequest
kubectl get certificaterequests

# View challenge status
kubectl get challenges

# Describe for detailed events
kubectl describe certificate myapp-tls
```

### Trusting root CA in browser

To avoid browser security warnings, trust the step-ca root certificate.

```bash
# SSH into the VM to get the root CA
colima ssh --profile k3s-dev

# Inside VM, find the root CA
cat /home/step/certs/root_ca.crt

# Exit VM and save root CA locally
colima ssh --profile k3s-dev -- cat /home/step/certs/root_ca.crt > ~/step-ca-root.crt
```

Add the root CA to your system keychain.

```bash
# macOS: Add to system keychain
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/step-ca-root.crt

# Alternatively, use the step CLI
step certificate install ~/step-ca-root.crt
```

Restart your browser to pick up the new root CA.

## Deploying applications

With core infrastructure running, deploy your applications.

### Example application deployment

A minimal web application deployment.

```nix
# apps/hello/default.nix
{ config, lib, pkgs, ... }:
let
  nodeIP = config.clusterHost or "10.0.2.15";
in
{
  kubernetes.resources.default = {
    Deployment.hello = {
      spec = {
        replicas = 1;
        selector.matchLabels.app = "hello";
        template = {
          metadata.labels.app = "hello";
          spec.containers = lib.mkNamedList {
            hello = {
              image = "hashicorp/http-echo";
              args = [ "-text=Hello from Kubernetes" "-listen=:8080" ];
              ports = lib.mkNamedList {
                http.containerPort = 8080;
              };
            };
          };
        };
      };
    };

    Service.hello = {
      spec = {
        selector.app = "hello";
        ports = [
          { port = 8080; targetPort = 8080; }
        ];
      };
    };

    Ingress.hello = {
      spec = {
        ingressClassName = "cilium";
        rules = [
          {
            host = "hello.${nodeIP}.sslip.io";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "hello";
                  port.number = 8080;
                };
              }
            ];
          }
        ];
      };
    };
  };
}
```

Deploy and verify.

```bash
# Generate and deploy
nix build .#clusters.local
kluctl deploy -t local --yes

# Verify deployment
kubectl get pods -l app=hello
kubectl get svc hello
kubectl get ingress hello

# Test the endpoint
curl http://hello.10.0.2.15.sslip.io
```

### Iterating on changes

The edit-build-deploy cycle for local development.

```bash
# Edit your Nix configuration
$EDITOR apps/hello/default.nix

# Rebuild manifests
nix build .#clusters.local

# Preview changes
kluctl diff -t local

# Apply changes
kluctl deploy -t local --yes

# Verify the update
kubectl rollout status deployment/hello
```

For faster iteration, consider watching for changes.

```bash
# Watch and rebuild (requires entr or similar)
fd -e nix | entr -s 'nix build .#clusters.local && kluctl deploy -t local --yes'
```

### Hot reload strategies

For applications that support hot reload, use file sync or image rebuild workflows.

Skaffold or Tilt can provide automatic rebuilds, though they add complexity.
For Nix-based workflows, consider using nix-csi with flakeRef volumes that rebuild on source changes.

A simpler approach uses kubectl with port-forwarding during active development.

```bash
# Forward local port to pod
kubectl port-forward deployment/hello 8080:8080

# Access at localhost:8080
curl http://localhost:8080
```

## nix-csi usage (optional)

nix-csi enables mounting Nix store closures into pods as ephemeral volumes.
This is useful when you need Nix packages inside containers without baking them into images.

### When to use nix-csi locally

Use nix-csi when you need to run Nix-built binaries in pods or provide development tools from the Nix store to containerized workloads.
For most local development, standard container images suffice.

nix-csi adds overhead for volume mounting and potential builds.
Enable it selectively for workloads that benefit from declarative Nix dependencies.

### Example pod with Nix store mount

```nix
# apps/nix-example/default.nix
{ config, lib, pkgs, ... }:
{
  kubernetes.resources.default.Job.nix-example = {
    spec.template.spec = {
      restartPolicy = "Never";
      containers = lib.mkNamedList {
        main = {
          image = "ghcr.io/lillecarl/nix-csi/scratch:1.0.1";
          command = [ "hello" ];
          volumeMounts = lib.mkNamedList {
            nix-csi.mountPath = "/nix";
          };
        };
      };
      volumes = lib.mkNamedList {
        nix-csi.csi = {
          driver = "nix.csi.store";
          volumeAttributes = {
            x86_64-linux = pkgs.pkgsCross.gnu64.hello;
            aarch64-linux = pkgs.hello;
          };
        };
      };
    };
  };
}
```

For flake-based dependencies that rebuild on changes.

```nix
volumes = lib.mkNamedList {
  nix-csi.csi = {
    driver = "nix.csi.store";
    volumeAttributes.flakeRef = "github:nixos/nixpkgs/nixos-unstable#hello";
  };
};
```

### Troubleshooting mount failures

Common issues with nix-csi on local clusters.

Check DaemonSet status.

```bash
kubectl get pods -n nix-csi -l app.kubernetes.io/name=nix-node
kubectl logs -n nix-csi daemonset/nix-node -c nix-node
```

Verify CSI driver registration.

```bash
kubectl get csinodes
kubectl describe csinode <node-name>
```

Check for mount propagation issues.

```bash
# SSH into the VM
colima ssh --profile k3s-dev

# Verify nix-csi host path exists
ls -la /var/lib/nix-csi

# Check kubelet logs for CSI errors
journalctl -u k3s -f | grep -i csi
```

If builds fail, verify network connectivity from the VM.

```bash
colima ssh --profile k3s-dev -- curl -I https://cache.nixos.org
```

## Troubleshooting

### kubectl commands for debugging

Essential commands for diagnosing cluster issues.

```bash
# Node status and capacity
kubectl describe node

# Pod status across all namespaces
kubectl get pods -A

# Events for recent activity
kubectl get events --sort-by='.lastTimestamp'

# Resource usage
kubectl top nodes
kubectl top pods -A

# Detailed pod information
kubectl describe pod <pod-name>

# Container logs
kubectl logs <pod-name> -c <container-name>
kubectl logs <pod-name> --previous  # Previous container instance
```

### Cilium status checks

Verify Cilium networking health.

```bash
# Overall Cilium status
kubectl exec -n kube-system ds/cilium -- cilium status

# Endpoint list (managed pods)
kubectl exec -n kube-system ds/cilium -- cilium endpoint list

# Service routing table
kubectl exec -n kube-system ds/cilium -- cilium service list

# BPF map status
kubectl exec -n kube-system ds/cilium -- cilium bpf lb list

# Health status
kubectl exec -n kube-system ds/cilium -- cilium-health status

# Run connectivity test (creates test pods)
cilium connectivity test
```

For network policy debugging.

```bash
# If Hubble is enabled
kubectl port-forward -n kube-system svc/hubble-relay 4245:80
hubble observe --verdict DROPPED
```

### Log inspection

Inspect component logs for errors.

```bash
# k3s server logs (inside VM)
colima ssh --profile k3s-dev -- journalctl -u k3s -f

# Cilium agent logs
kubectl logs -n kube-system -l k8s-app=cilium --tail=100

# Cilium operator logs
kubectl logs -n kube-system -l name=cilium-operator --tail=100

# cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager --tail=100

# step-ca logs
kubectl logs -n step-ca -l app.kubernetes.io/name=step-certificates --tail=100
```

### Common issues

*Pods stuck in Pending*

Check for resource constraints or scheduling issues.

```bash
kubectl describe pod <pod-name>
kubectl get events --field-selector involvedObject.name=<pod-name>
```

*Pods stuck in ContainerCreating*

Usually CNI-related.
Verify Cilium is running and CNI configuration exists.

```bash
kubectl get pods -n kube-system -l k8s-app=cilium
colima ssh --profile k3s-dev -- ls /etc/cni/net.d/
```

*Service unreachable*

Check service and endpoint configuration.

```bash
kubectl get svc <service-name>
kubectl get endpoints <service-name>
kubectl exec -n kube-system ds/cilium -- cilium service list | grep <service-name>
```

*Ingress not working*

Verify Ingress class and controller status.

```bash
kubectl get ingressclass
kubectl get ingress <ingress-name> -o yaml
kubectl describe ingress <ingress-name>
```

## Stopping and resuming

The k3s-dev profile maintains state between sessions.
Stop the cluster when not in use to free resources.

### colima stop

```bash
# Stop the VM (preserves state)
colima stop --profile k3s-dev

# Verify stopped
colima list
```

### Data persistence

The following data persists across restarts.

- k3s cluster state in `/var/lib/rancher/k3s/`
- etcd data (if using HA mode)
- Container images in containerd storage
- PersistentVolumeClaims bound to local storage

Pod workloads will be restarted when the cluster resumes.
StatefulSet pods may need manual intervention if storage is corrupted.

### Clean restart

To restart the cluster from scratch without destroying configuration.

```bash
# Stop the profile
colima stop --profile k3s-dev

# Start fresh
colima start --profile k3s-dev
```

To fully reset the cluster state.

```bash
# Delete the profile entirely
colima delete --profile k3s-dev

# Recreate from configuration
colima start --profile k3s-dev
```

This destroys all cluster data including persistent volumes.
Use this only when you need a completely fresh environment.

## Related documentation

- NixOS k3s server module: `./components/nixos-k3s-server.md`
- Cilium CNI: `./components/cilium-cni.md`
- nix-csi: `./components/nix-csi.md`
- easykubenix documentation: `~/projects/sciops-workspace/easykubenix`
- kluctl documentation: https://kluctl.io/docs/
- step-ca documentation: https://smallstep.com/docs/step-ca/
