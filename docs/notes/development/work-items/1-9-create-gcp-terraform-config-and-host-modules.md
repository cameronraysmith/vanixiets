---
title: "Story 1.7: Create GCP VM terraform configuration and host modules"
---

Status: drafted

## Story

As a system administrator,
I want to create terraform configuration for GCP VM provisioning,
So that I can deploy gcp-vm using patterns learned from Hetzner deployment.

## Context

Story 1.7 creates terraform/terranix configuration for Google Cloud Platform VM deployment.
This extends the patterns from Hetzner (Story 1.4) to a second cloud provider, validating multi-cloud capabilities.

**New Territory**: GCP is new compared to clan-infra's proven Hetzner/Vultr patterns.
Networking is more complex (VPC, firewall rules required).
May encounter GCP-specific challenges not present in Hetzner.

**Progressive Validation**: This story builds on Hetzner success (Stories 1.4-1.6) and applies learned patterns to GCP.
If GCP proves too complex, can defer to post-Phase 0 and proceed with Hetzner-only infrastructure.

## Acceptance Criteria

1. modules/terranix/gcp.nix created with Google Cloud provider configuration
2. SSH key resource defined for terraform deployment key
3. GCP compute instance resource configured (e2-micro or e2-small, free tier eligible)
4. null_resource configured for `clan machines install` provisioning
5. Network configuration included (VPC, firewall rules for SSH + zerotier)
6. modules/hosts/gcp-vm/default.nix created with base NixOS configuration
7. srvos hardening modules imported in host configuration
8. GCP-specific networking configuration included
9. modules/hosts/gcp-vm/disko.nix created with LUKS encryption and GCP-compatible partition layout
10. GCP service account JSON stored as clan secret: `clan secrets set gcp-service-account-json`
11. GCP project ID configured in terraform
12. Terraform configuration generates: `nix build .#terranix.terraform`
13. Host configuration builds: `nix build .#nixosConfigurations.gcp-vm.config.system.build.toplevel`

## Tasks / Subtasks

- [ ] Research GCP + NixOS integration (before starting)
  - [ ] Search for GCP + NixOS deployment examples
  - [ ] Review GCP compute instance requirements
  - [ ] Understand GCP networking (VPC, firewall rules)
  - [ ] Check GCP boot disk requirements (may differ from Hetzner)
  - [ ] Review clan-infra for any GCP examples (unlikely, but check)

- [ ] Create GCP terranix configuration (AC: #1-5)
  - [ ] Create modules/terranix/gcp.nix file
  - [ ] Configure google provider with credentials from clan secrets
  - [ ] Set GCP project ID (from environment or configuration)
  - [ ] Define VPC network resource (or use default network)
  - [ ] Define firewall rules:
    - Allow SSH (port 22) from anywhere
    - Allow zerotier (UDP port 9993)
  - [ ] Define SSH key resource for terraform deployment
  - [ ] Configure google_compute_instance resource:
    - Machine type: e2-micro or e2-small
    - Zone: us-central1-a (or appropriate zone)
    - Boot disk: initial Debian/Ubuntu image (clan will replace)
    - Network interface: VPC network + external IP
  - [ ] Add null_resource provisioner calling `clan machines install gcp-vm`

- [ ] Create GCP host base configuration (AC: #6-8)
  - [ ] Create modules/hosts/gcp-vm/default.nix
  - [ ] Set hostname = "gcp-vm"
  - [ ] Configure system.stateVersion
  - [ ] Add nix settings (flakes enabled, nixPath, etc.)
  - [ ] Import srvos hardening modules
  - [ ] Configure GCP-specific networking:
    - DHCP configuration for GCP metadata server
    - Cloud-init compatibility (if needed)
    - Firewall basics

- [ ] Create GCP disko configuration (AC: #9)
  - [ ] Create modules/hosts/gcp-vm/disko.nix
  - [ ] Research GCP boot disk requirements:
    - May need specific partition layout
    - EFI vs BIOS boot (GCP supports both)
  - [ ] Configure EFI boot partition (if GCP requires)
  - [ ] Configure LUKS encrypted root partition
  - [ ] Set up filesystem layout (ext4 or btrfs)
  - [ ] Verify disko configuration compatible with GCP

- [ ] Store GCP credentials in clan secrets (AC: #10)
  - [ ] Obtain GCP service account JSON from Google Cloud Console
  - [ ] Store credentials: `clan secrets set gcp-service-account-json < service-account.json`
  - [ ] Verify credentials retrievable: `clan secrets get gcp-service-account-json`
  - [ ] Delete local service-account.json after storing in secrets

- [ ] Configure GCP project ID (AC: #11)
  - [ ] Set project ID in terranix configuration
  - [ ] Option 1: Hard-code in modules/terranix/gcp.nix
  - [ ] Option 2: Pass via environment variable (TF_VAR_gcp_project_id)
  - [ ] Verify project ID accessible in terraform

- [ ] Test terraform configuration generation (AC: #12)
  - [ ] Build terranix output: `nix build .#terranix.terraform`
  - [ ] Review generated terraform.tf.json for GCP resources:
    - google provider configuration
    - VPC network (if created)
    - Firewall rules
    - Compute instance
    - null_resource provisioner
  - [ ] Verify configuration looks correct before deployment

- [ ] Test host configuration build (AC: #13)
  - [ ] Build NixOS configuration: `nix build .#nixosConfigurations.gcp-vm.config.system.build.toplevel`
  - [ ] Verify no build errors
  - [ ] Check output includes expected packages and services

## Dev Notes

### Secrets Management Coordination Required

**CRITICAL PAUSE POINT:** This story requires manual coordination for GCP credentials.

**Pattern Reference:** Same as Story 1.4, adapted for GCP provider

**Secrets to Configure:**
1. **tf-passphrase** - Already configured in Story 1.4 (reused)

2. **gcp-service-account-json** - GCP service account credentials
   - Create service account in GCP Console (IAM & Admin → Service Accounts)
   - Grant Compute Admin role (or Compute Instance Admin v1)
   - Create JSON key and download
   - Store: `clan secrets set gcp-service-account-json < /path/to/service-account-key.json`
   - **Delete local JSON file after storing in clan secrets**
   - Fetched at terraform runtime via data.external in modules/terranix/base.nix

**Developer Workflow:**
1. Implement secret-fetching STRUCTURE in modules/terranix/gcp.nix and modules/terranix/base.nix (data.external pattern for GCP credentials)
2. **PAUSE** - Request user to:
   - Create GCP project (if needed)
   - Create service account with Compute Admin permissions
   - Download JSON key
   - Run: `clan secrets set gcp-service-account-json < service-account-key.json`
   - Delete local JSON file
3. Wait for confirmation that secrets are stored
4. Only after confirmation: proceed to AC #12-13 (terraform generation and validation)

**DO NOT:**
- Generate fake/placeholder service account JSON
- Proceed with terraform commands before secrets are configured
- Assume GCP project or service account exists

**Why This Matters:**
Story 1.8 (GCP deployment) will fail without real GCP credentials. GCP authentication is more complex than Hetzner - requires service account with proper IAM permissions.

### GCP-Specific Considerations

**Networking Complexity:**
- GCP requires explicit VPC network (or use default network)
- Firewall rules are separate resources (not per-instance)
- Need to allow SSH (port 22) and zerotier (UDP 9993)
- External IP address needs explicit configuration

**Machine Types:**
- e2-micro: 2 vCPU, 1GB RAM, ~$7.11/month (may qualify for free tier)
- e2-small: 2 vCPU, 2GB RAM, ~$14.23/month
- Recommend e2-micro for Phase 0 testing (lowest cost)

**Boot Disk:**
- GCP requires initial OS image (Debian/Ubuntu recommended)
- Clan will replace during install, but terraform needs valid image ID
- Boot disk size: 10GB minimum (NixOS needs ~5GB)

**Metadata Server:**
- GCP provides metadata server at 169.254.169.254
- May need to configure DHCP to use metadata server
- Cloud-init may be involved (research needed)

### Terraform Pattern Adaptation

**From Hetzner to GCP:**
- `hcloud_server` → `google_compute_instance`
- `server_type` → `machine_type`
- `location` → `zone`
- `image` → `boot_disk.initialize_params.image`
- Add VPC network configuration
- Add firewall rule configuration

### GCP Authentication

**Service Account JSON:**
- Create service account in Google Cloud Console
- Grant Compute Engine permissions (Compute Admin or equivalent)
- Download JSON key
- Store in clan secrets (never commit to git)
- Reference in terraform provider configuration

**Project ID:**
- GCP resources scoped to project
- Need to specify project ID in terraform
- Can hard-code or pass via environment variable

### Solo Operator Workflow

This story has MEDIUM-HIGH RISK due to GCP complexity.
May need additional research time for GCP-specific quirks.
Expected execution time: 4-6 hours (including research and troubleshooting).

**Decision Point**: If GCP configuration proves too complex (>8 hours), can pause and defer Stories 1.7-1.9 to post-Phase 0.
Hetzner-only infrastructure is acceptable for MVP validation.

### Architectural Context

**Why GCP:**
- Validates multi-cloud patterns
- Demonstrates clan inventory across providers
- Tests zerotier mesh across different cloud networks
- Expands infrastructure options beyond Hetzner

**GCP vs Hetzner complexity:**
- Hetzner: Simpler, fewer moving parts, proven pattern
- GCP: More complex networking, unfamiliar territory, higher risk

**Acceptable to defer**: GCP is enhancement, not requirement.
Core validation can succeed with Hetzner-only deployment.

### References

- [Source: docs/notes/development/epic-1-infrastructure-restructure-proposal.md#Story-1.7]
- [Upstream: GCP Compute Engine documentation]
- [Upstream: Terraform google provider documentation]
- [Community: NixOS + GCP examples (search nixpkgs, discourse)]

### Expected Validation Points

After this story completes:
- GCP terraform configuration generates cleanly
- GCP host configuration builds without errors
- GCP disko configuration evaluates correctly
- Ready for Story 1.8 (GCP deployment)

**What Story 1.7 does NOT include:**
- Actual GCP VM deployment (Story 1.8)
- Multi-cloud coordination testing (Story 1.9)
- GCP-specific troubleshooting (happens in Story 1.8)

### Important Constraints

**GCP complexity is acceptable blocker:**
- If configuration takes >8 hours or hits major blockers, pause
- Hetzner-only infrastructure is sufficient for Phase 0 validation
- GCP can be deferred to post-Phase 0 experimentation

**Cost awareness**: e2-micro ~$7.11/month.
Combined with Hetzner: ~$13-15/month.
Budget ~$20-30 for 2-3 weeks of testing (acceptable).

**Zero-regression mandate does NOT apply**: Test infrastructure, experimental GCP configuration.

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

<!-- Agent model will be recorded during implementation -->
