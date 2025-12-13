---
title: "NixOS Deployment"
description: "Learn how to provision cloud infrastructure and deploy NixOS servers using terranix and clan."
sidebar:
  order: 5
---

This tutorial guides you through deploying NixOS servers to cloud providers.
You'll understand infrastructure provisioning with terranix, deployment orchestration with clan, and how secrets management works on NixOS with clan vars.

## What you will learn

By the end of this tutorial, you will understand:

- How terranix translates Nix expressions into Terraform configurations
- The multi-cloud strategy for Hetzner and GCP deployments
- How clan inventory coordinates service assignment across machines
- The complete deployment flow from infrastructure provisioning to system activation
- Secrets management with clan vars on NixOS

## Prerequisites

Before starting, you should have:

- Completed the [Bootstrap to Activation Tutorial](/tutorials/bootstrap-to-activation)
- Completed the [Secrets Setup Tutorial](/tutorials/secrets-setup)
- Cloud provider credentials (Hetzner API token and/or GCP service account)
- SSH access configured for remote deployment
- The repository cloned with direnv activated

## Estimated time

90-120 minutes for your first deployment including infrastructure provisioning.
Subsequent updates take 15-30 minutes.

## Understanding NixOS in this infrastructure

Before provisioning anything, let's understand what makes NixOS deployment different from darwin.

### NixOS vs darwin deployment models

Darwin machines run darwin-rebuild locally.
You sit at the machine, run a command, and watch it activate.

NixOS servers in this infrastructure use a push model through clan.
You run commands from your workstation, and clan builds and deploys to remote machines over SSH.

This model enables:
- **Central management**: Deploy multiple servers from one workstation
- **Consistent state**: All configuration lives in git, not scattered across machines
- **Coordination**: Services that span machines can be configured together

### The NixOS fleet

The infrastructure includes four NixOS machines across two cloud providers:

**Hetzner Cloud:**
- **cinnabar** - Zerotier controller, always-on coordinator
- **electrum** - Zerotier peer, general-purpose VPS

**Google Cloud Platform:**
- **galena** - CPU-only compute node (e2-standard-8)
- **scheelite** - GPU compute node (n1-standard-8 with Tesla T4)

Each cloud serves different purposes: Hetzner for cost-effective always-on infrastructure, GCP for burst compute and GPU workloads.

### Toggle patterns for cost control

Cloud VMs cost money when running.
The infrastructure uses toggle patterns to enable/disable machines:

```nix
# In modules/terranix/hetzner.nix or gcp.nix
cinnabar.enabled = true;   # Always on - zerotier controller
electrum.enabled = true;   # Usually on
galena.enabled = false;    # Enable when needed
scheelite.enabled = false; # Enable when GPU needed
```

When `enabled = false`, terraform destroys the resource but preserves the configuration.
Enable it again, run terraform, and the machine recreates with the same configuration.

## Step 1: Understand terranix

Terranix bridges Nix and Terraform, letting you write infrastructure as Nix expressions.

### What terranix does

Traditional Terraform uses HCL (HashiCorp Configuration Language).
Terranix lets you write the same infrastructure definitions in Nix:

```nix
# Nix expression (terranix)
resource.hcloud_server.cinnabar = {
  name = "cinnabar";
  server_type = "cx22";
  image = "ubuntu-24.04";
  location = "fsn1";
};
```

This compiles to:

```hcl
# Generated Terraform HCL
resource "hcloud_server" "cinnabar" {
  name        = "cinnabar"
  server_type = "cx22"
  image       = "ubuntu-24.04"
  location    = "fsn1"
}
```

### Why use terranix?

The benefits compound with complexity:
- **Type checking**: Nix catches configuration errors before terraform runs
- **Code reuse**: Define machine patterns once, instantiate them with parameters
- **Integration**: Infrastructure config lives alongside NixOS config in the same repo
- **Consistency**: Same language for infrastructure and system configuration

### Module structure

```bash
ls modules/terranix/
```

You'll see:
- `hetzner.nix` - Hetzner Cloud provider configuration
- `gcp.nix` - Google Cloud Platform configuration
- Related helper modules for networking, firewalls, etc.

## Step 2: Provision infrastructure

Let's provision a machine.
We'll use an existing configuration to understand the flow.

### Check current state

First, see what infrastructure exists:

```bash
nix run .#terraform -- state list
```

This shows resources terraform currently manages.
If you haven't run terraform before, this may be empty or show only existing resources.

### Review the configuration

Look at a machine definition.
For cinnabar (Hetzner):

```bash
# View the terranix configuration
cat modules/terranix/hetzner.nix
```

Key elements:
- **Provider configuration**: Credentials, default settings
- **Server resources**: VM definitions with type, image, location
- **Network resources**: Firewall rules, SSH keys
- **Output values**: IP addresses for later use

### Plan the changes

Before applying, always plan:

```bash
nix run .#terraform -- plan
```

Terraform shows what it will create, modify, or destroy.
Review this carefully, especially for destroy operations.

### Apply infrastructure

If the plan looks correct:

```bash
nix run .#terraform -- apply
```

Terraform prompts for confirmation, then provisions resources.
This takes a few minutes for new VMs.

### Note the outputs

After apply, terraform shows outputs including IP addresses:

```bash
nix run .#terraform -- output
```

You'll need these IPs for the clan deployment step.

## Step 3: Understand clan machine management

Clan orchestrates NixOS deployment across multiple machines.

### What clan manages

Clan provides:
- **Machine registry**: Defines which machines exist and how to reach them
- **Inventory system**: Assigns roles and services to machines
- **Secrets (vars)**: Generates and deploys machine-specific secrets
- **Deployment tooling**: Commands for install, update, and status

### Inventory structure

The clan inventory defines service instances:

```nix
# modules/clan/inventory.nix
{
  services = {
    zerotier = {
      controller.roles.default.machines = [ "cinnabar" ];
      peers.roles.default.machines = [ "electrum" "galena" "scheelite" ];
    };
    users = {
      cameron.roles.default.machines = [ "cinnabar" "electrum" "galena" "scheelite" ];
    };
  };
}
```

This declares:
- cinnabar runs the zerotier controller
- Other machines are zerotier peers
- The cameron user exists on all NixOS machines

### Machine configuration

Each NixOS machine has a configuration in `modules/machines/nixos/`:

```bash
ls modules/machines/nixos/
```

These configurations import deferred module composition modules just like darwin, but include NixOS-specific elements like systemd services and disko disk layouts.

## Step 4: Generate secrets

Before deploying, generate machine-specific secrets.

### What gets generated

Clan vars creates:
- SSH host keys (ed25519)
- Zerotier identity secrets
- Any other service-specific credentials

These secrets are managed automatically by clan.

### Generate vars

```bash
# Generate secrets for a specific machine
clan vars generate cinnabar

# Or generate for all machines
clan vars generate
```

### Verify generation

```bash
# View generated secrets
ls vars/cinnabar/

# Check a specific secret
clan vars get cinnabar ssh.id_ed25519.pub
```

The public keys are safe to view.
Private keys are encrypted and only decrypted during deployment.

## Step 5: Deploy to NixOS

Now deploy the configuration to your provisioned infrastructure.

### First-time installation

For a fresh VM with only the base image, use `clan machines install`:

```bash
# Install NixOS on a new machine
clan machines install cinnabar --target-host root@<IP_ADDRESS>
```

Replace `<IP_ADDRESS>` with the terraform output.

This command:
1. Connects via SSH to the target
2. Partitions disks using disko configuration
3. Installs NixOS with your configuration
4. Reboots into the new system

### Subsequent updates

For machines already running NixOS, use `clan machines update`:

```bash
# Update an existing machine
clan machines update cinnabar
```

This:
1. Builds the new configuration locally
2. Copies closures to the remote machine
3. Activates the new configuration
4. Runs any activation scripts

### Deployment options

Common options:

```bash
# Update multiple machines
clan machines update cinnabar electrum

# Dry run (build but don't deploy)
clan machines update cinnabar --dry-run

# Update all machines in inventory
clan machines update
```

## Step 6: Verify zerotier mesh

After deployment, verify mesh connectivity.

### Check zerotier on the deployed machine

SSH into the deployed machine:

```bash
ssh cinnabar.zt  # If zerotier DNS works
# Or
ssh root@<IP_ADDRESS>
```

Then verify zerotier:

```bash
sudo zerotier-cli status
# Should show "ONLINE"

sudo zerotier-cli listnetworks
# Should show network db4344343b14b903 with status "OK"
```

### Verify mesh connectivity

From the deployed machine, ping other nodes:

```bash
ping electrum.zt
ping stibnite.zt
```

If zerotier DNS isn't configured, use IP addresses:

```bash
# Get peer IPs
sudo zerotier-cli peers
```

### Controller vs peer

If deploying cinnabar (the controller), other machines authorize through it.
If deploying a peer, it needs authorization from cinnabar.

Check controller status:

```bash
# On cinnabar
sudo zerotier-cli listnetworks
# Look for "CONTROLLER" in the output
```

## Step 7: Configure user secrets (legacy sops-nix)

NixOS machines can also use legacy sops-nix for user-specific credentials during the migration.

### Understanding secrets on NixOS

**Clan vars (target)** provides all secrets:
- Generated automatically
- Machine-scoped
- Deployed to `/run/secrets/`

**sops-nix (legacy)** provides user secrets during migration:
- Created manually
- User-scoped
- Deployed to `~/.config/sops-nix/secrets/`

Darwin machines use legacy sops-nix patterns.
NixOS is migrating toward clan vars for all secrets.

### Setting up legacy sops-nix on NixOS

The process mirrors darwin.
On the NixOS machine:

```bash
# Create the sops directory
mkdir -p ~/.config/sops/age

# Either copy your age key from another machine
scp yourworkstation:~/.config/sops/age/keys.txt ~/.config/sops/age/

# Or derive a new one from your SSH key
ssh-to-age -private-key -i ~/.ssh/id_ed25519 > ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
```

After setting up the key, your user's sops secrets will decrypt during home-manager activation.

### Verify secrets

```bash
# Clan vars: System secrets
ls /run/secrets/

# Legacy sops-nix: User secrets (after home-manager activation)
ls ~/.config/sops-nix/secrets/
```

## Step 8: Multi-cloud patterns

Let's understand the multi-cloud strategy.

### Hetzner patterns

Hetzner provides cost-effective European hosting:

```nix
# modules/terranix/hetzner.nix
resource.hcloud_server.cinnabar = {
  server_type = "cx22";  # 2 vCPU, 4GB RAM, ~$5/month
  location = "fsn1";     # Falkenstein, Germany
  image = "ubuntu-24.04";
};
```

Use Hetzner for:
- Always-on infrastructure (zerotier controller)
- General-purpose workloads
- European data residency requirements

### GCP patterns

GCP provides access to GPUs and burst compute:

```nix
# modules/terranix/gcp.nix
resource.google_compute_instance.galena = {
  machine_type = "e2-standard-8";  # 8 vCPU, 32GB RAM
  zone = "us-west1-b";

  # Toggle pattern
  count = var.galena_enabled ? 1 : 0;
};
```

Use GCP for:
- GPU workloads (scheelite with Tesla T4)
- Burst compute capacity
- US-based infrastructure

### Cost management

The toggle pattern prevents surprise bills:

```bash
# Disable expensive resources when not needed
# In gcp.nix, set: scheelite.enabled = false

# Then apply
nix run .#terraform -- apply

# Resources are destroyed but configuration preserved
```

To re-enable:

```bash
# Set: scheelite.enabled = true
nix run .#terraform -- apply
# Resources recreated with same configuration

# Then deploy NixOS config
clan machines update scheelite
```

## What you've learned

You've now deployed NixOS to cloud infrastructure.
Along the way, you learned:

- **Terranix** translates Nix to Terraform for infrastructure provisioning
- **Clan** orchestrates NixOS deployment with inventory-based service assignment
- **Secrets** on NixOS: clan vars for system secrets, legacy sops-nix for user secrets during migration
- **Multi-cloud** patterns for Hetzner (cost-effective) and GCP (burst/GPU)
- **Toggle patterns** manage costs by enabling/disabling resources

## Next steps

Now that you've deployed NixOS:

1. **Add more machines** by creating configurations in `modules/machines/nixos/` and terranix definitions

2. **Explore service patterns** by examining how zerotier and users are assigned via inventory

3. **Review operational procedures** in the guides:
   - [Host Onboarding Guide](/guides/host-onboarding#nixos-host-onboarding-clan-managed) for detailed procedures
   - [Secrets Management Guide](/guides/secrets-management) for secret operations

4. **Understand the architecture** more deeply:
   - [Clan Integration](/concepts/clan-integration) for the full coordination model
   - [Deferred Module Composition](/concepts/deferred-module-composition) for module organization

## Troubleshooting

### Terraform fails to authenticate

Check your cloud credentials:

```bash
# Hetzner
echo $HCLOUD_TOKEN

# GCP
echo $GOOGLE_APPLICATION_CREDENTIALS
ls -la $GOOGLE_APPLICATION_CREDENTIALS
```

Credentials should be set via environment variables or secrets.

### clan machines install fails with SSH error

Verify SSH connectivity:

```bash
# Test basic SSH
ssh root@<IP_ADDRESS> echo "connection works"

# Check SSH key is offered
ssh -v root@<IP_ADDRESS> 2>&1 | grep "Offering"
```

Ensure:
- The terraform-provisioned SSH key matches what you have locally
- Root login is enabled on the fresh VM image
- Firewall allows SSH (port 22)

### Deployment times out

Large deployments may need more time:

```bash
# Increase timeout
clan machines update cinnabar --timeout 3600
```

Or check if the machine is actually reachable:

```bash
ping <IP_ADDRESS>
ssh root@<IP_ADDRESS>
```

### Zerotier not joining network

Check zerotier service status:

```bash
sudo systemctl status zerotier-one
sudo journalctl -u zerotier-one -n 50
```

Common issues:
- Network ID wrong in configuration
- Firewall blocking UDP 9993
- Controller not authorizing the peer

### Clan vars secrets not appearing

Ensure vars were generated:

```bash
# Check vars directory
ls vars/cinnabar/

# Regenerate if needed
clan vars generate cinnabar

# Redeploy
clan machines update cinnabar
```

For comprehensive troubleshooting, see the [Host Onboarding Guide](/guides/host-onboarding#troubleshooting).
