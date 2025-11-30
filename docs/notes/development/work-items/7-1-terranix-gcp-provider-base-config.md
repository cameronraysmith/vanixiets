# Story 7.1: Terranix GCP Provider and Base Configuration

Status: drafted

## Story

As a system administrator,
I want to create a terranix GCP module following the patterns established in hetzner.nix,
so that I can provision GCP compute instances with the same declarative approach used for Hetzner Cloud.

## Context

Story 7.1 is the foundation story for Epic 7 (GCP Multi-Node Infrastructure), the first post-migration infrastructure expansion epic following completion of Epics 1-6.

**Business Drivers:**
- GCP contract obligations
- GPU availability for ML workloads
- Multi-cloud infrastructure redundancy
- Cost management via toggle mechanism (disabled nodes = zero cost)

**Prerequisites:** Epic 6 complete (dendritic+clan architecture stable, legacy cleanup done)

**Pattern Template:** `modules/terranix/hetzner.nix` (76 lines) provides the structural reference for GCP implementation.

## Acceptance Criteria

1. `modules/terranix/gcp.nix` created following dendritic flake-parts namespace (`flake.modules.terranix.gcp`)
2. GCP provider configured using `hashicorp/google` (NOT google-beta) with version constraint `~> 5.0`
3. Service account credentials integration via clan secrets (similar to Hetzner API token pattern)
4. ED25519 SSH key generation using `tls_private_key` resource (matching hetzner.nix pattern)
5. Private key stored locally via `local_sensitive_file` for `clan machines install`
6. SSH key configured as instance metadata (NOT `google_compute_ssh_key` resource - GCP uses `metadata.ssh-keys` field)
7. `google_compute_firewall` rules created for SSH (tcp/22) and ZeroTier (udp/51820)
8. Base `google_compute_instance` resource structure defined with configurable zone and machine type
9. Network interface configured with `access_config` for external IP assignment
10. Module evaluates successfully: `nix eval .#terranixConfigurations.gcp`
11. GCP project ID, region, and zone configurable via module options

## Tasks / Subtasks

- [ ] Task 1: Create GCP terranix module structure (AC: #1, #2, #3)
  - [ ] Create `modules/terranix/gcp.nix` file
  - [ ] Define `flake.modules.terranix.gcp` export following dendritic pattern
  - [ ] Configure `hashicorp/google` provider with version `~> 5.0`
  - [ ] Add `data.external` pattern for service account JSON credentials (adapt from hetzner API token pattern)
  - [ ] Define GCP project ID variable

- [ ] Task 2: Implement SSH key generation (AC: #4, #5, #6)
  - [ ] Add `tls_private_key.gcp_deploy_key` resource with `algorithm = "ED25519"`
  - [ ] Add `local_sensitive_file.gcp_deploy_key` with `file_permission = "600"`
  - [ ] Document metadata.ssh-keys format: `"root:ssh-ed25519 AAAAC3... comment"`
  - [ ] Note: GCP uses instance metadata, NOT separate SSH key resource

- [ ] Task 3: Create firewall rules (AC: #7)
  - [ ] Add `google_compute_firewall.allow_ssh` for tcp/22 from any source
  - [ ] Add `google_compute_firewall.allow_zerotier` for udp/51820 from any source
  - [ ] Configure appropriate target tags for firewall rule application

- [ ] Task 4: Define base instance configuration (AC: #8, #9, #11)
  - [ ] Create `google_compute_instance` resource structure
  - [ ] Configure `machine_type` option (default: `n1-standard-4`)
  - [ ] Configure `zone` option (e.g., `us-central1-a`)
  - [ ] Add `boot_disk` block with debian-12 image for NixOS installation
  - [ ] Configure `network_interface` with `access_config` for external IP
  - [ ] Add `metadata.ssh-keys` with generated public key
  - [ ] Note: `null_resource.install-*` provisioner pattern same as Hetzner

- [ ] Task 5: Validate module evaluation (AC: #10)
  - [ ] Run `nix eval .#terranixConfigurations.gcp` and verify no errors
  - [ ] Review generated terraform.tf.json for correctness
  - [ ] Verify provider configuration present
  - [ ] Verify firewall rules present
  - [ ] Verify instance resource structure present

- [ ] Task 6: Document GCP-specific patterns (for Stories 7.2-7.4)
  - [ ] Document critical differences from Hetzner pattern in Dev Notes
  - [ ] Note GPU support preparation (`guest_accelerator` block, zone constraints)
  - [ ] Document toggle pattern for cost control (enabled/disabled machines)

## Dev Notes

### GCP vs Hetzner Pattern Differences

The following table summarizes critical differences between GCP and Hetzner terraform patterns that must be addressed in this implementation:

| Aspect | Hetzner Pattern (hetzner.nix) | GCP Pattern (gcp.nix) |
|--------|------------------------------|----------------------|
| SSH Keys | `hcloud_ssh_key` resource | `metadata.ssh-keys` field on instance |
| Firewall | Implicit SSH allowed | Explicit `google_compute_firewall` rules required |
| Network | Implicit default | Explicit `network_interface` with `access_config` |
| Location | `location` (region code) | `zone` required (e.g., `us-central1-a`) |
| Machine Types | `serverType = "cx43"` | `machineType = "n1-standard-4"` |
| Provider | `hetznercloud/hcloud` | `hashicorp/google` (NOT google-beta) |

### Provider Selection Rationale

**Selected:** `hashicorp/google` version `~> 5.0`

**Rationale:**
- GA (Generally Available) provider - stable for compute resources
- Maintained by HashiCorp + Google partnership
- NOT google-beta: We don't need beta features for basic compute resources
- Version 5.x provides all necessary features (compute, firewall, networking)

### SSH Key Metadata Format

GCP instances receive SSH keys via instance metadata, not a separate resource. The format is:

```
metadata.ssh-keys = "root:ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... terraform-deploy-key"
```

This differs significantly from Hetzner's `hcloud_ssh_key` resource approach.

### Firewall Configuration

GCP requires explicit firewall rules for all ingress traffic. Required rules:

1. **SSH (tcp/22):** Essential for `clan machines install` deployment
2. **ZeroTier (udp/51820):** Required for mesh network connectivity

Firewall rules use `target_tags` to scope application to specific instances.

### Authentication Pattern

Service account credentials follow the same clan secrets pattern as Hetzner API token:

```nix
# Similar to hetzner base.nix data.external pattern
data.external.gcp_credentials = {
  program = [ "clan" "secrets" "get" "gcp-service-account-json" ];
};

provider.google = {
  project = var.gcp_project_id;
  region = var.gcp_region;
  credentials = data.external.gcp_credentials.result.value;
};
```

### GPU Support (Story 7.3 Preparation)

Story 7.3 will add GPU-capable nodes. Key considerations for this foundation story:

- `guest_accelerator` block on `google_compute_instance`
- Requires compatible machine types: `n1-*`, `a2-*`, `g2-*` families
- Zone must have GPU quota available
- Not all zones support all GPU types

### Toggle Mechanism for Cost Control

Following the Hetzner pattern (`machines = { name = { enabled = true; ... }; }`):

```nix
enabledMachines = lib.filterAttrs (_name: cfg: cfg.enabled) machines;
```

Disabled machines (`enabled = false`) are not provisioned, incurring zero ongoing cost.

### Project Structure Notes

**Expected file location:** `modules/terranix/gcp.nix`

**Module organization:** Parallel to existing terranix modules:
```
modules/terranix/
├── base.nix      # Provider config (hcloud, google)
├── config.nix    # Global terraform config
├── hetzner.nix   # Hetzner resources (existing)
└── gcp.nix       # GCP resources (NEW - this story)
```

**Namespace:** `flake.modules.terranix.gcp` following dendritic flake-parts pattern.

### Learnings from Hetzner Implementation (Story 1.4)

**From Story 1.4 (Status: done - APPROVED)**

Story 1.4 established the terranix pattern for Hetzner Cloud that this story replicates for GCP.

**Key Patterns to Reuse:**

1. **SSH Key Generation Pattern:**
   - `tls_private_key.ssh_deploy_key` with `algorithm = "ED25519"`
   - `local_sensitive_file.ssh_deploy_key` for `clan machines install` access
   - File permission `600` for private key security

2. **Provisioner Pattern:**
   - `null_resource.install-<name>` with `local-exec` provisioner
   - Command: `clan machines install <name> --update-hardware-config nixos-facter --target-host root@<ip> -i '<key_file>' --yes`

3. **Secrets Integration:**
   - `data.external` calling `clan secrets get <secret-name>`
   - Provider credentials fetched at terraform runtime

4. **Machine Toggle Pattern:**
   - `machines = { name = { enabled = true; ... }; };`
   - `enabledMachines = lib.filterAttrs (_name: cfg: cfg.enabled) machines;`
   - Resources only created for enabled machines

**GCP-Specific Adaptations Required:**
- Replace `hcloud_ssh_key` with `metadata.ssh-keys` on instance
- Add explicit `google_compute_firewall` rules (Hetzner allows SSH by default)
- Configure `network_interface.access_config` for external IP
- Use `zone` instead of `location` (more specific)

[Source: docs/notes/development/work-items/1-4-create-hetzner-terraform-config-and-host-modules.md]

### References

- [Pattern Template: modules/terranix/hetzner.nix]
- [Source: docs/notes/development/epics/epic-7-gcp-multi-node-infrastructure.md#Story-7.1]
- [Architecture: docs/notes/development/architecture/deployment-architecture.md#Terraform-Deployment]
- [Architecture: docs/notes/development/architecture/project-structure.md]
- [Upstream: Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Upstream: GCP Compute Instance Resource](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance)

### NFR Coverage

| NFR | Coverage |
|-----|----------|
| NFR-7.1 (Pattern consistency) | Module follows dendritic namespace, mirrors hetzner.nix structure |
| NFR-7.3 (Deployment consistency) | Uses same clan machines install provisioner pattern |

### Estimated Effort

**4-6 hours** (configuration creation and validation)

- Module structure and provider setup: 1-2 hours
- SSH key and firewall configuration: 1-2 hours
- Instance resource and validation: 1-2 hours
- Documentation and cleanup: 0.5-1 hour

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

<!-- To be filled during implementation -->

### Debug Log References

### Completion Notes List

### File List

## Change Log

**2025-11-30 (Story Drafted)**:
- Story file created from Epic 7, Story 7.1 specification
- Acceptance criteria expanded with research findings from Party Mode team
- Dev Notes include comprehensive GCP vs Hetzner pattern comparison
- Task breakdown aligned with hetzner.nix reference pattern
- References to Story 1.4 learnings incorporated
- NFR coverage mapping added
- Estimated effort: 4-6 hours
