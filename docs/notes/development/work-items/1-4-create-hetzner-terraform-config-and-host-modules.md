---
title: "Story 1.4: Create Hetzner VM terraform configuration and host modules"
---

Status: drafted

## Story

As a system administrator,
I want to create terraform configuration for Hetzner Cloud VM provisioning,
So that I can deploy hetzner-vm using proven patterns from clan-infra.

## Context

Story 1.4 creates the terraform/terranix configuration for Hetzner Cloud VM deployment alongside the NixOS host modules.
This follows clan-infra's proven pattern for infrastructure provisioning with terraform + clan integration.
Hetzner is the first deployment target (proven pattern) before attempting GCP (new territory).

**Prerequisites**: Story 1.3 completed successfully - inventory machines (hetzner-vm, gcp-vm) are defined and ready to be referenced.
The hetzner-vm machine already exists in inventory with tags ["nixos" "cloud" "hetzner"] and minimal NixOS configuration at modules/hosts/hetzner-vm/default.nix.

**Infrastructure Pattern**: Use terranix (Nix DSL for terraform) to generate terraform configuration, with clan secrets for API tokens and null_resource provisioner calling `clan machines install` for NixOS deployment.

**Security Requirement**: LUKS encryption is non-negotiable for all cloud VMs.
Disko configuration handles declarative disk partitioning with encryption.

## Acceptance Criteria

1. modules/terranix/hetzner.nix created with Hetzner Cloud provider configuration
2. SSH key resource defined for terraform deployment key
3. Hetzner Cloud server resource configured (CX22 or CX32, 2-4 vCPU for testing)
4. null_resource configured for `clan machines install hetzner-vm` provisioning (referencing inventory machine)
5. modules/hosts/hetzner-vm/default.nix enhanced with srvos hardening and production-ready base configuration
6. srvos hardening modules imported in host configuration
7. modules/hosts/hetzner-vm/disko.nix created with LUKS encryption and standard partition layout
8. Hetzner API token stored as clan secret: `clan secrets set hetzner-api-token`
9. Terraform configuration generates: `nix build .#terranix.terraform`
10. Generated terraform.tf.json manually reviewed for correctness
11. Host configuration builds: `nix build .#nixosConfigurations.hetzner-vm.config.system.build.toplevel`
12. Disko partition commands generate: `nix eval .#nixosConfigurations.hetzner-vm.config.disko.disks --apply toString`
13. Boot device path validation: Verify /dev/sda or /dev/vda device naming during disko configuration

## Tasks / Subtasks

- [ ] Create Hetzner terranix configuration (AC: #1-4)
  - [ ] Create modules/terranix/hetzner.nix file
  - [ ] Configure hcloud provider with API token from clan secrets
  - [ ] Define SSH key resource for terraform deployment
  - [ ] Configure hcloud_server resource (CX22 or CX32 size)
  - [ ] Add null_resource provisioner calling `clan machines install hetzner-vm`
  - [ ] Follow clan-infra vultr.nix pattern as reference

- [ ] Enhance Hetzner host base configuration (AC: #5-6)
  - [ ] Enhance existing modules/hosts/hetzner-vm/default.nix (created in Story 1.3)
  - [ ] Verify hostname = "hetzner-vm" (set in Story 1.3)
  - [ ] Verify system.stateVersion = "25.05" (set in Story 1.3)
  - [ ] Verify nix-settings.nix import (base module imported in Story 1.3)
  - [ ] Import srvos hardening modules (NEW for Story 1.4)
  - [ ] Configure networking (DHCP, firewall basics - NEW for Story 1.4)
  - [ ] Verify nixpkgs.hostPlatform = "x86_64-linux" (set in Story 1.3)

- [ ] Create Hetzner disko configuration (AC: #7, #13)
  - [ ] Create modules/hosts/hetzner-vm/disko.nix
  - [ ] Configure EFI boot partition
  - [ ] Configure LUKS encrypted root partition
  - [ ] Set up filesystem layout (ext4 or btrfs)
  - [ ] Verify disko configuration follows clan-infra patterns
  - [ ] IMPORTANT: Validate boot device path (/dev/sda vs /dev/vda) - Hetzner may use either depending on virtualization (AC: #13)

- [ ] Store Hetzner API token in clan secrets (AC: #8)
  - [ ] Ensure clan secrets initialized (age keys)
  - [ ] Store token: `clan secrets set hetzner-api-token`
  - [ ] Verify token retrievable: `clan secrets get hetzner-api-token`

- [ ] Test terraform configuration generation (AC: #9-10)
  - [ ] Build terranix output: `nix build .#terranix.terraform`
  - [ ] Review generated terraform.tf.json for correctness
  - [ ] Verify hcloud provider configuration present
  - [ ] Verify server resource configuration present
  - [ ] Verify null_resource provisioner present

- [ ] Test host configuration build (AC: #11)
  - [ ] Build NixOS configuration: `nix build .#nixosConfigurations.hetzner-vm.config.system.build.toplevel`
  - [ ] Verify no build errors
  - [ ] Check output includes expected packages and services

- [ ] Test disko configuration evaluation (AC: #12)
  - [ ] Evaluate disko disks: `nix eval .#nixosConfigurations.hetzner-vm.config.disko.disks --apply toString`
  - [ ] Verify LUKS configuration present
  - [ ] Verify partition layout correct

## Dev Notes

### Learnings from Previous Story

**From Story 1.3 (Status: review - APPROVED ✅)**

Story 1.3 successfully configured clan inventory and service instances, defining hetzner-vm and gcp-vm machines ready for terraform deployment.

**Critical Findings for Story 1.4:**

1. **Inventory Machine Definition**:
   - hetzner-vm already exists at modules/hosts/hetzner-vm/default.nix (created in Story 1.3)
   - Base configuration includes: nixpkgs.hostPlatform = "x86_64-linux", networking.hostName = "hetzner-vm", system.stateVersion = "25.05"
   - Base nix-settings.nix module already imported
   - Story 1.4 should ENHANCE this existing file, not recreate it

2. **Clan-Core API Migration**:
   - All service instances now require explicit module declarations (module.name, module.input)
   - emergency-access service replaced deprecated admin service
   - Pattern: Each service must declare `module.name = "service-name"` and `module.input = "clan-core"`
   - Reference clan.nix:34-45 for emergency-access pattern

3. **Expected Vars Error During nix flake check**:
   - `nix flake check --all-systems` will fail on missing zerotier vars - **this is EXPECTED and CORRECT for Phase 0**
   - Vars (secrets/generated values) are generated during deployment via `clan vars generate`
   - Story 1.5 deployment workflow will generate these vars as part of terraform provisioning
   - DO NOT attempt to fix vars errors before deployment - they resolve automatically during `clan machines install`

4. **Boot Device Path Validation** (from Story 1.3 review - MEDIUM severity):
   - Story 1.3 hardcoded boot device paths to `/dev/sda` in minimal config
   - Hetzner may use `/dev/sda` or `/dev/vda` depending on virtualization backend
   - Disko configuration (Story 1.4) will override minimal config device paths
   - Validate actual device naming during Story 1.5 deployment
   - Use disko's device auto-detection or query Hetzner API for VM disk device naming

5. **Files Created in Story 1.3** (DO NOT RECREATE):
   - modules/hosts/hetzner-vm/default.nix - EXISTS (enhance with srvos, networking, firewall)
   - modules/hosts/gcp-vm/default.nix - EXISTS (Story 1.7 will enhance)
   - modules/flake-parts/clan.nix - Inventory machines configured with emergency-access, zerotier, tor services

6. **Service Instance Pattern** (reuse in future stories):
   - Tags-based service targeting: tags.all, tags.nixos, tags.cloud
   - Role-based configuration: controller (hetzner-vm zerotier), peer (gcp-vm zerotier), server (tor)
   - Zerotier topology: hetzner-vm is controller, gcp-vm is peer

7. **Validation Approach**:
   - Use `nix develop -c clan machines list` to verify machine registration
   - Use `nix flake show` to verify nixosConfigurations structure
   - Ignore missing vars errors during build - they resolve during deployment

[Source: docs/notes/development/work-items/1-3-configure-clan-inventory-and-service-instances-for-test-vm.md#Dev-Agent-Record]

### Secrets Management Coordination Required

**CRITICAL PAUSE POINT:** This story requires manual coordination for cloud provider credentials.

**Pattern Reference:** ~/projects/nix-workspace/clan-infra (Step 6: Setup clan secrets in docs/notes/implementation/clan-infra-terranix-pattern.md)

**Secrets to Configure:**
1. **tf-passphrase** - OpenTofu state encryption
   - Generate: `openssl rand -base64 32 | clan secrets set tf-passphrase`
   - Used in terraformWrapper.prefixText for state encryption

2. **hetzner-api-token** - Hetzner Cloud API authentication
   - Obtain from Hetzner Cloud console (Project → Security → API Tokens)
   - Store: `clan secrets set hetzner-api-token` (paste token when prompted)
   - Fetched at terraform runtime via data.external in modules/terranix/base.nix

**Developer Workflow:**
1. Implement secret-fetching STRUCTURE in modules/terranix/base.nix (data.external pattern)
2. **PAUSE** - Request user to configure secrets with real cloud provider credentials
3. Wait for confirmation that secrets are stored via `clan secrets set`
4. Only after confirmation: proceed to AC #9-12 (terraform generation and validation)

**DO NOT:**
- Generate fake/placeholder secrets
- Proceed with terraform commands before secrets are configured
- Assume cloud provider accounts exist

**Why This Matters:**
Story 1.5 (terraform deployment) will fail without real credentials. The data.external pattern fetches secrets at runtime - terraform init/plan/apply require valid authentication.

### Terraform Pattern Reference

**clan-infra vultr.nix pattern** (adapt for Hetzner):
```nix
resource.vultr_instance.machine-name = {
  label = "machine-name";
  region = "region";
  plan = "plan-id";
  os_id = 2136; # Debian 12
  enable_ipv6 = true;
  ssh_key_ids = [
    (config.resource.vultr_ssh_key.terraform "id")
  ];
};

resource.null_resource.install-machine-name = {
  provisioner.local-exec = {
    command = "clan machines install machine-name --target-host root@${...} -i '${...}' --yes";
  };
};
```

**Hetzner adaptation**:
- Use `hcloud_server` resource instead of `vultr_instance`
- Use `server_type` instead of `plan` (e.g., "cx22", "cx32")
- Use `location` instead of `region` (e.g., "fsn1", "nbg1", "hel1")
- Hetzner uses `image` instead of `os_id` (but clan installs NixOS, so initial image doesn't matter much - use Debian or Ubuntu)

### VM Size Selection

**Hetzner Cloud Plans:**
- CX22: 2 vCPU, 4GB RAM, ~€5.83/month (good for testing)
- CX32: 4 vCPU, 8GB RAM, ~€11.66/month (more headroom)

Recommend CX22 for Phase 0 testing (lowest cost), can scale up for production.

### Disko LUKS Pattern

**Standard LUKS layout**:
- EFI boot partition (512MB, unencrypted, FAT32)
- LUKS encrypted root partition (remaining space)
- Root filesystem inside LUKS (ext4 or btrfs)

**Passphrase handling**: Clan vars should handle LUKS passphrase as secret.
Check clan-infra examples for exact pattern.

### Solo Operator Workflow

This story prepares configuration but does NOT deploy yet.
Story 1.5 will perform actual deployment (terraform apply + clan install).
Expected execution time: 4-6 hours (including pattern research and testing).

### Architectural Context

**Prerequisites from Story 1.3**:
- Inventory machines (hetzner-vm, gcp-vm) defined with tags for service targeting
- Service instances configured: emergency-access (replaces deprecated admin), zerotier (controller on hetzner-vm), tor
- Tags-based assignment (tags.all, tags.nixos) for bulk machine selection
- Zerotier topology: hetzner-vm = controller, gcp-vm = peer
- All service instances use module declarations (module.name, module.input) per new clan-core API

**Why terraform/terranix:**
- Proven in clan-infra (10+ VMs)
- Declarative infrastructure provisioning
- Integration with clan machines install

**Why srvos:**
- Server hardening best practices
- Used in clan-infra for security baseline
- Minimal opinionated configuration

**Why LUKS:**
- Security requirement for cloud VMs
- Protects data at rest
- Standard practice for sensitive infrastructure

### References

- [Prerequisite: docs/notes/development/work-items/1-3-configure-clan-inventory-and-service-instances-for-test-vm.md]
- [Source: docs/notes/development/epic-1-infrastructure-restructure-proposal.md#Story-1.4]
- [Upstream: clan-infra/machines/*/terraform-configuration.nix]
- [Upstream: clan-infra/modules/terranix/vultr.nix]
- [Upstream: Hetzner Cloud API documentation]

### Expected Validation Points

After this story completes:
- Terraform configuration should generate cleanly
- Host configuration should build without errors
- Disko configuration should evaluate correctly
- Ready for Story 1.5 (actual deployment)

**What Story 1.4 does NOT include:**
- Actual VM deployment (Story 1.5)
- Clan vars generation (Story 1.6 validates this)
- Multi-machine coordination (Story 1.9)

### Important Constraints

**Zero-regression mandate does NOT apply to test-clan**: This is experimental infrastructure.
Hetzner VM is for Phase 0 validation only.

**Cost awareness**: CX22 costs ~€5.83/month.
Will start billing when deployed in Story 1.5.
Budget ~€12-15 for 2-3 weeks of testing (acceptable for validation).

## Change Log

**2025-11-04**:
- Story reviewed and updated based on Story 1.3 completion
- Added "Learnings from Previous Story" section documenting Story 1.3 findings
- Updated Context section to reference Story 1.3 prerequisite and existing inventory machines
- Updated AC #4 to clarify inventory machine reference (hetzner-vm)
- Updated AC #5 to clarify enhancement of existing configuration (not creation)
- Added AC #13 for boot device path validation (/dev/sda vs /dev/vda)
- Updated Tasks section to reference existing files from Story 1.3
- Added boot device validation subtask to disko configuration
- Updated Architectural Context to reference Story 1.3 service instances and API migration
- Added References entry for Story 1.3 as prerequisite

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

<!-- Agent model will be recorded during implementation -->
