---
title: "ADR-0021: Terranix Infrastructure Provisioning"
---

**Status**: Accepted
**Date**: 2024-12-01
**Scope**: Cloud infrastructure provisioning
**Related**: [ADR-0019: Clan-core orchestration](0019-clan-core-orchestration/)

## Context

This infrastructure requires cloud VM provisioning across multiple providers (Hetzner, GCP) with togglable resources for cost control.
The provisioning approach needed to integrate with the dendritic flake-parts + clan-core architecture while maintaining infrastructure-as-code principles.

### Requirements

**Multi-cloud support**:
- Hetzner Cloud: Cost-effective VPS (cinnabar, electrum)
- GCP: GPU-capable instances for ML workloads (galena CPU, scheelite GPU)
- Potential for additional providers

**Cost management**:
- Toggle mechanism to enable/disable expensive resources
- Avoid paying for GPU instances when not in use
- Infrastructure state persisted but resources destroyable

**Nix integration**:
- Configuration in Nix expressions, not HCL
- Leverage flake inputs and dendritic patterns
- Type checking and composition from Nix ecosystem

**Clan deployment integration**:
- Provisioned VMs deployed via clan
- Infrastructure provisioning separate from NixOS installation
- Clear handoff: terraform creates VM, clan installs NixOS

### Prior approaches considered

**Raw Terraform/OpenTofu**:
- HCL configuration files
- Separate configuration language from Nix
- No type checking integration
- State management independent of flake

**Pulumi**:
- Programming language SDKs
- Richer type system
- Heavier weight, larger dependency
- Less Nix ecosystem integration

## Decision

Adopt **terranix** for infrastructure provisioning, generating Terraform JSON from Nix expressions within the flake-parts structure.

### Core pattern

Terranix converts Nix module configuration to Terraform JSON:

```nix
# modules/terranix/hetzner.nix
{ config, lib, ... }:
{
  # Hetzner Cloud provider
  terraform.required_providers.hcloud = {
    source = "hetznercloud/hcloud";
    version = "~> 1.45";
  };

  provider.hcloud.token = "\${var.hcloud_token}";

  # VM resource
  resource.hcloud_server.cinnabar = {
    name = "cinnabar";
    server_type = "cx22";
    image = "ubuntu-24.04";
    location = "nbg1";
    # ... configuration
  };
}
```

Generated via: `nix build .#terraform && cat result/config.tf.json`

### Toggle mechanism

Resources enabled/disabled via Nix boolean options:

```nix
# modules/terranix/gcp.nix
{
  options.machines = {
    galena.enabled = lib.mkEnableOption "GCP CPU instance galena";
    scheelite.enabled = lib.mkEnableOption "GCP GPU instance scheelite";
  };

  config = lib.mkMerge [
    (lib.mkIf config.machines.galena.enabled {
      resource.google_compute_instance.galena = { ... };
    })
    (lib.mkIf config.machines.scheelite.enabled {
      resource.google_compute_instance.scheelite = { ... };
    })
  ];
}
```

Disable expensive GPU: Set `machines.scheelite.enabled = false`, run terraform apply.
Resource removed from state, no charges incurred.

### Provider module organization

```
modules/terranix/
├── default.nix      # Main integration, flake output definition
├── base.nix         # Shared configuration (variables, outputs)
├── hetzner.nix      # Hetzner Cloud provider and resources
└── gcp.nix          # GCP provider and resources
```

Each provider in separate module, composed via standard Nix imports.

### Flake integration

Terranix output defined in flake-parts:

```nix
# modules/terranix/default.nix
{ inputs, ... }:
{
  perSystem = { system, ... }: {
    packages.terraform = inputs.terranix.lib.terranixConfiguration {
      inherit system;
      modules = [
        ./base.nix
        ./hetzner.nix
        ./gcp.nix
      ];
    };
  };
}
```

Build and apply: `nix run .#terraform -- apply`

### Clan handoff pattern

Terranix provisions infrastructure, clan deploys NixOS:

```nix
# In terranix module
resource.hcloud_server.cinnabar = {
  # ... VM configuration

  provisioner.local-exec = {
    command = ''
      # Wait for SSH
      until ssh -o StrictHostKeyChecking=no root@''${self.ipv4_address} true 2>/dev/null; do
        sleep 5
      done
      # Install NixOS via clan
      clan machines install cinnabar --target-host root@''${self.ipv4_address}
    '';
  };
};
```

Separation of concerns:
- Terranix: Create VM with base image (Ubuntu)
- Clan: Install NixOS and deploy configuration

## Alternatives considered

### Raw Terraform/OpenTofu

**Rejected**.

While industry standard, raw Terraform:
- Requires maintaining HCL alongside Nix
- No composition with flake ecosystem
- Separate configuration language to learn
- State management outside Nix control

Terranix provides same Terraform providers via Nix expressions.

### Pulumi

**Not evaluated in depth**.

Pulumi offers:
- Programming language SDKs (Python, TypeScript, Go)
- Rich type systems
- State management

But:
- Larger dependency footprint
- Less Nix ecosystem integration
- Overkill for this infrastructure's needs

### NixOps

**Rejected**.

NixOps is a NixOS-native deployment tool but:
- Complex stateful model
- Less active development
- Heavier than needed for VM provisioning
- Overlaps with clan's deployment role

Terranix for provisioning + clan for deployment is cleaner separation.

### Manual provisioning

**Rejected**.

Manual VM creation:
- Not reproducible
- No version control
- Error-prone
- Doesn't scale

Infrastructure-as-code is non-negotiable for this fleet.

## Consequences

### Positive

**Nix expression benefits**:
- Type checking via Nix evaluation
- Composition with other Nix modules
- Same language as rest of configuration
- Flake inputs available (e.g., nixpkgs versions)

**Toggle mechanism for cost control**:
- GPU instance costs $200+/month
- Toggle off when not in use
- State preserved, resource destroyed
- Re-enable with single option change

**Clean separation from clan**:
- Terranix creates infrastructure
- Clan deploys to infrastructure
- Each tool does one thing well
- Clear handoff point

**Provider flexibility**:
- Hetzner and GCP in production
- Additional providers addable via same pattern
- Terraform provider ecosystem available

**Reproducible infrastructure**:
- Configuration in version control
- Same expressions, same infrastructure
- Auditable changes via git history

### Negative

**Terraform state management**:
- State file requires secure storage
- State encryption via age key
- Lost state requires import or recreation
- State conflicts possible with multiple operators

**Two-phase provisioning**:
- terraform apply creates VM
- clan install deploys NixOS
- More steps than monolithic tool
- Failure between phases requires manual recovery

**Terraform provider dependencies**:
- External providers (hcloud, google) required
- Provider version pinning needed
- Provider bugs affect provisioning

**HCL debugging sometimes needed**:
- Terranix generates JSON, not HCL
- Some Terraform errors reference HCL concepts
- Occasional translation debugging required

### Neutral

**Standard Terraform patterns apply**:
- Terraform plan/apply workflow unchanged
- Same provider documentation applies
- Skills transfer from Terraform experience

**State encryption via existing keys**:
- Uses same age keys as sops-nix
- No additional key management
- Integrated with existing secrets workflow

## Validation evidence

### Epic 1 (November 2024)

Hetzner provisioning validated:

- **Story 1.4**: Terranix Hetzner module created
- **Story 1.5**: cinnabar VPS provisioned and deployed
- **Story 1.9**: electrum VPS added to fleet

**Metrics**:
- CX22 instance provisioned
- NixOS installed via clan
- Zerotier controller operational

### Epic 7 (December 2024)

GCP provisioning validated:

- **Story 7.1**: Terranix GCP module created (172 lines)
- **Story 7.2**: galena CPU instance deployed
- **Story 7.3**: Zerotier integration for GCP nodes
- **Story 7.4**: scheelite GPU instance with Tesla T4

**Metrics**:
- GCP provider functional
- Toggle mechanism validated
- GPU instance operational
- 10 patterns established for GCP integration

## References

### Internal

- [ADR-0019: Clan-core orchestration](0019-clan-core-orchestration/)
- [ADR-0020: Dendritic + Clan Integration](0020-dendritic-clan-integration/) - How terranix integrates with the dendritic+clan architecture
- Epic 7 retrospective: `docs/notes/development/retrospectives/epic-7-gcp-multi-node-infrastructure.md`
- Terranix modules: `modules/terranix/`

### External

- [Terranix documentation](https://terranix.org/)
- [Terranix repository](https://github.com/terranix/terranix)
- [Hetzner Cloud Terraform provider](https://registry.terraform.io/providers/hetznercloud/hcloud)
- [Google Cloud Terraform provider](https://registry.terraform.io/providers/hashicorp/google)
