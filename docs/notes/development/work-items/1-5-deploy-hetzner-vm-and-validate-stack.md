---
title: "Story 1.5: Deploy Hetzner VM and validate infrastructure stack"
---

Status: drafted

## Story

As a system administrator,
I want to provision and deploy hetzner-vm to Hetzner Cloud,
So that I can validate the complete infrastructure stack (terraform + clan + disko + NixOS) works end-to-end.

## Context

Story 1.5 performs the first real infrastructure deployment - provisioning a Hetzner Cloud VM with terraform and installing NixOS via clan.
This is HIGH RISK because it creates real infrastructure that costs money and validates the entire stack integration.

**Critical Validation**: This story proves the terraform/terranix + clan + disko + NixOS stack works end-to-end.
If this fails, the entire migration approach needs re-evaluation.

**Progressive Validation Strategy**: Hetzner deployment must succeed and stabilize before attempting GCP (Story 1.8).
This follows proven patterns from clan-infra and validates the foundation for all future VM deployments.

## Acceptance Criteria

1. Terraform initialized from test-clan repository: enter nix develop shell, then `terraform init` (AC validates terraform workspace initialization)
2. Terraform plan reviewed and validated: `terraform plan` shows cx43 server creation, SSH key, hcloud provider
3. Hetzner VM (cx43, 8 vCPU, 16GB RAM at $9.99/month) provisioned via terraform: `terraform apply`
4. VM accessible via SSH with terraform-generated deployment key (from local_sensitive_file)
5. Clan vars generated for hetzner-vm: `clan vars generate hetzner-vm` (generates zerotier identity, LUKS passphrase via clan vars generators)
6. NixOS installed via clan: `clan machines install hetzner-vm --target-host root@<ip> --update-hardware-config nixos-facter --yes`
7. System boots successfully with LUKS encryption (btrfs subvolumes: /root, /nix, /home)
8. Device path validated: /dev/sda confirmed as boot device (per srvos hardware-hetzner-cloud convention)
9. Post-installation SSH access works with clan-managed keys: `ssh root@<hetzner-ip>`
10. Zerotier controller operational: `ssh root@<hetzner-ip> "zerotier-cli info"` shows controller role
11. Clan vars deployed correctly: `ssh root@<hetzner-ip> "ls -la /run/secrets/"` shows sshd keys, zerotier identity
12. No critical errors in system logs: `ssh root@<hetzner-ip> "journalctl -p err --no-pager"`
13. System survives reboot: reboot VM and verify SSH access + zerotier controller + services restore

## Tasks / Subtasks

- [ ] Navigate to test-clan repository and enter nix develop shell (Prerequisite)
  - [ ] Change directory: `cd ~/projects/nix-workspace/test-clan`
  - [ ] Enter development shell: `nix develop`
  - [ ] Verify terraform available in shell: `which terraform`
  - [ ] All subsequent commands run inside this nix develop shell

- [ ] Initialize terraform (AC: #1)
  - [ ] Run: `terraform init` (inside nix develop shell)
  - [ ] Verify hcloud provider downloaded (version from base.nix required_providers)
  - [ ] Verify terraform workspace initialized (.terraform/ directory created)
  - [ ] Verify state encryption configured (TF_ENCRYPTION env var set by wrapper)

- [ ] Review terraform plan (AC: #2)
  - [ ] Run: `terraform plan`
  - [ ] Review resources to be created:
    - hcloud provider with API token from data.external (fetches via `clan secrets get hetzner-api-token`)
    - tls_private_key.terraform (deployment SSH key generation)
    - local_sensitive_file.terraform (saves private key with 0600 permissions)
    - hcloud_ssh_key.terraform (uploads public key to Hetzner)
    - hcloud_server.hetzner-vm (cx43, debian-12, fsn1 location, /dev/sda device)
    - null_resource.install-hetzner-vm (provisioner calling `clan machines install`)
  - [ ] Verify cx43 server type (8 vCPU, 16GB RAM, $9.99/month)
  - [ ] Verify no unexpected resources
  - [ ] Confirm plan before apply

- [ ] Provision Hetzner VM (AC: #3-4)
  - [ ] Run: `terraform apply`
  - [ ] Confirm apply when prompted
  - [ ] Wait for VM provisioning to complete (~2-5 minutes)
  - [ ] Capture VM IP address from terraform output
  - [ ] Test SSH access with deployment key: `ssh -i <path-to-deploy-key> root@<hetzner-ip>`
  - [ ] Verify VM is Debian 12 (temporary, will be replaced by NixOS)

- [ ] Generate clan vars for hetzner-vm (AC: #5)
  - [ ] Run: `clan vars generate hetzner-vm` (from test-clan repository)
  - [ ] Verify SSH host keys generated in sops/machines/hetzner-vm/secrets/
  - [ ] Verify public facts in sops/machines/hetzner-vm/facts/
  - [ ] Verify zerotier identity generated (identity.secret, identity.public)
  - [ ] Verify LUKS passphrase generated via pwgen (64 char passphrase from disko.nix vars generator)

- [ ] Install NixOS via clan (AC: #6-7-8)
  - [ ] Run: `clan machines install hetzner-vm --target-host root@<hetzner-ip> --update-hardware-config nixos-facter --yes`
  - [ ] Monitor installation progress (disko partitioning, LUKS setup, NixOS installation)
  - [ ] Wait for disko to partition /dev/sda: EFI boot (512MB) + LUKS root
  - [ ] Wait for btrfs subvolumes creation inside LUKS: /root, /nix, /home
  - [ ] Wait for NixOS installation from modules/hosts/hetzner-vm/default.nix
  - [ ] Wait for initial system boot
  - [ ] Verify nixos-facter hardware config generated and applied
  - [ ] Verify /dev/sda device path used (validates Story 1.4 assumption)
  - [ ] Verify installation completes without errors

- [ ] Validate post-installation SSH access (AC: #9)
  - [ ] Test SSH with clan-managed keys: `ssh root@<hetzner-ip>` (no -i flag needed)
  - [ ] Verify SSH works without terraform deployment key
  - [ ] Verify clan-managed SSH host keys deployed from vars
  - [ ] Check srvos hardening applied (firewall, systemd-networkd)

- [ ] Validate zerotier controller (AC: #10)
  - [ ] SSH to VM: `ssh root@<hetzner-ip>`
  - [ ] Check zerotier status: `zerotier-cli info`
  - [ ] Verify zerotier controller role (from service instance configuration)
  - [ ] Verify zerotier identity from clan vars (not ephemeral)
  - [ ] Capture zerotier network ID for GCP peer (Story 1.8): `zerotier-cli listnetworks`

- [ ] Validate clan vars deployment (AC: #11)
  - [ ] SSH to VM: `ssh root@<hetzner-ip>`
  - [ ] List secrets: `ls -la /run/secrets/`
  - [ ] Verify sshd host keys present (ssh_host_ed25519_key, ssh_host_rsa_key)
  - [ ] Verify proper permissions (0600, root-owned)
  - [ ] Verify zerotier identity.secret present
  - [ ] Verify LUKS passphrase NOT visible (encrypted, used at boot only)

- [ ] Validate btrfs filesystem structure (AC: #7)
  - [ ] SSH to VM: `ssh root@<hetzner-ip>`
  - [ ] Check btrfs subvolumes: `btrfs subvolume list /`
  - [ ] Verify subvolumes: /root, /nix, /home
  - [ ] Verify compression enabled: `btrfs filesystem show`
  - [ ] Verify LUKS encryption: `lsblk` shows /dev/sda2 as crypt device

- [ ] Check system logs for errors (AC: #12)
  - [ ] Review error logs: `ssh root@<hetzner-ip> "journalctl -p err --no-pager | head -50"`
  - [ ] Investigate any critical errors
  - [ ] Verify no systemd service failures: `systemctl --failed`
  - [ ] Check dmesg for hardware issues: `ssh root@<hetzner-ip> "dmesg | grep -i error"`
  - [ ] Verify srvos hardening warnings are expected (not errors)

- [ ] Test system reboot (AC: #13)
  - [ ] Reboot VM: `ssh root@<hetzner-ip> "reboot"`
  - [ ] Wait for system to come back online (~2-3 minutes)
  - [ ] Test SSH access after reboot
  - [ ] Verify LUKS encryption unlocked at boot
  - [ ] Verify zerotier controller restored and operational
  - [ ] Verify all services operational: `systemctl status zerotier-one sshd`

- [ ] Document deployment experience
  - [ ] Record actual commands used (with timestamps)
  - [ ] Document any issues encountered and resolutions
  - [ ] Note any deviations from clan-infra pattern
  - [ ] Capture deployment timing: terraform apply, clan install, total time
  - [ ] Document actual VM costs (billing confirmation from Hetzner)
  - [ ] Note any vars errors encountered (should be none after Story 1.4 fixes)

## Dev Notes

### Learnings from Previous Story

**From Story 1.4 (Status: done - APPROVED ✅)**

Story 1.4 successfully created the terraform/terranix configuration and host modules for Hetzner Cloud deployment.
All acceptance criteria were met with comprehensive test evidence documented.

**Critical Findings for Story 1.5 Deployment:**

1. **VM Sizing Decision (IMPLEMENTED):**
   - Configuration uses cx43 (8 vCPU, 16GB RAM) at $9.99/month for performant testing
   - Rationale: Avoid resource-constrained hangs during infrastructure validation
   - Cost: $9.99/month is acceptable for ephemeral testing infrastructure
   - Billing starts when Story 1.5 executes `terraform apply`

2. **Expected Vars Error Behavior (CRITICAL):**
   - Host configuration build fails with zerotier vars error - this is EXPECTED and CORRECT
   - Vars (zerotier identity, LUKS passphrase) generate during deployment via `clan vars generate`
   - Error message: "error: vars.zerotier-identity not found" is NORMAL before vars generation
   - Error resolves automatically during `clan machines install` workflow
   - DO NOT attempt to fix vars errors before running `clan vars generate`

3. **specialArgs Pattern (IMPLEMENTED):**
   - Added `clan.specialArgs = { inherit inputs; }` to modules/flake-parts/clan.nix:19
   - Purpose: Fixes infinite recursion in module evaluation
   - Deviation: clan-infra uses minimal specialArgs approach
   - Impact: Makes inputs globally available to all machines
   - Monitoring: Watch for downstream module system issues in future stories

4. **Device Path Validation (TO VALIDATE):**
   - Disko configuration uses /dev/sda per srvos hardware-hetzner-cloud convention
   - modules/hosts/hetzner-vm/disko.nix:21 hardcodes device = "/dev/sda"
   - Story 1.5 deployment will validate this assumption during NixOS installation
   - If Hetzner uses /dev/vda instead, will need disko.nix update (unlikely based on srvos convention)

5. **Secrets Configuration (COMPLETE):**
   - tf-passphrase: OpenTofu state encryption passphrase configured in Story 1.4
   - hetzner-api-token: Hetzner Cloud API token configured in Story 1.4
   - Both secrets fetched at terraform runtime via data.external calling `clan secrets get`
   - State encryption configured in modules/flake-parts/clan.nix terraformWrapper.prefixText
   - TF_ENCRYPTION environment variable set automatically by wrapper script

6. **Test Results from Story 1.4 (BASELINE):**
   - ✅ Terraform config generates successfully: `nix build .#terraform` → terraform.tf.json created
   - ✅ Generated terraform.tf.json reviewed and validated:
     - hcloud provider with API token from data.external
     - hcloud_server.hetzner-vm (cx43, debian-12, fsn1)
     - hcloud_ssh_key.terraform with tls_private_key
     - null_resource.install-hetzner-vm calling `clan machines install`
     - Required providers: hcloud, external, tls, null, local
   - ✅ Disko evaluates correctly:
     - device="/dev/sda"
     - partitions=["ESP","luks"]
     - btrfs subvolumes: /root, /nix, /home
     - LUKS encryption with 64-char pwgen passphrase

7. **Files Created in Story 1.4 (REFERENCE):**
   - modules/terranix/base.nix - Provider configuration, secrets integration via data.external
   - modules/terranix/hetzner.nix - hcloud_server resource, SSH key generation, clan provisioner
   - modules/hosts/hetzner-vm/disko.nix - LUKS encryption, btrfs subvolumes, vars generator

8. **Files Modified in Story 1.4 (REFERENCE):**
   - modules/hosts/hetzner-vm/default.nix - Enhanced with srvos.nixosModules.server, hardware-hetzner-cloud, networking, firewall
   - modules/flake-parts/clan.nix - Added terranix integration, specialArgs, perSystem.terranix

**Deployment Workflow Expectations:**

Story 1.5 executes the configuration created in Story 1.4. Expected workflow:

1. **Terraform Apply (~2-5 minutes):**
   - Provisions Hetzner Cloud cx43 VM
   - Generates deployment SSH key (tls_private_key)
   - Uploads public key to Hetzner (hcloud_ssh_key)
   - Creates VM with Debian 12 initial image (temporary)
   - Returns VM IP address

2. **Clan Vars Generate (~1-2 minutes):**
   - Generates zerotier identity (identity.secret, identity.public)
   - Generates LUKS passphrase (64 char via pwgen -s 64 1)
   - Generates SSH host keys (encrypted in sops/)
   - Creates public facts (unencrypted in sops/)

3. **Clan Machines Install (~10-30 minutes):**
   - Partitions /dev/sda via disko: EFI boot + LUKS root
   - Creates btrfs subvolumes inside LUKS
   - Installs NixOS from modules/hosts/hetzner-vm/default.nix
   - Deploys clan vars to /run/secrets/
   - Applies srvos hardening (firewall, systemd-networkd)
   - Reboots into NixOS

4. **Post-Install Validation (~15-30 minutes):**
   - SSH access with clan-managed keys
   - Zerotier controller operational
   - System logs check
   - Reboot stability test

**Total Expected Time:** 30-60 minutes (excluding troubleshooting)

**Important Constraints:**

- Story 1.4 secrets (tf-passphrase, hetzner-api-token) MUST be configured before terraform commands will work
- Terraform apply will START BILLING at $9.99/month for cx43 VM
- This is ephemeral testing infrastructure - can destroy after Story 1.6 validation
- Budget approved: ~$20-30 for 2-3 weeks of testing (acceptable cost)

[Source: docs/notes/development/work-items/1-4-create-hetzner-terraform-config-and-host-modules.md#Dev-Agent-Record]
[Source: docs/notes/development/work-items/1-4-create-hetzner-terraform-config-and-host-modules.md#Senior-Developer-Review]

### Prerequisites Validation

**MANDATORY:** Before executing this story, verify Story 1.4 secrets are configured:

```bash
# Verify secrets exist (should not error)
clan secrets get tf-passphrase
clan secrets get hetzner-api-token

# If either command fails, return to Story 1.4 and complete secret setup
```

This story executes actual terraform commands that authenticate with Hetzner Cloud API. Without valid credentials, terraform init/plan/apply will fail with authentication errors.

**Story 1.4 must be fully complete** including the manual secrets setup step before proceeding.

### Deployment Workflow Summary

**Phase 1: Terraform Provisioning**
1. `terraform init` - download providers
2. `terraform plan` - review changes
3. `terraform apply` - provision VM + SSH key
4. Capture VM IP from terraform output

**Phase 2: Clan Installation**
1. `clan vars generate hetzner-vm` - generate secrets
2. `clan machines install hetzner-vm --target-host root@<ip>` - install NixOS
3. Wait for installation + reboot
4. Test SSH with clan-managed keys

**Phase 3: Validation**
1. Check services (zerotier, sshd, etc.)
2. Verify clan vars deployed
3. Check logs for errors
4. Test reboot stability

### Expected Timing

- Terraform apply: ~2-5 minutes (VM provisioning)
- Clan install: ~10-30 minutes (depends on internet speed, Nix builds)
- Validation: ~15-30 minutes (thorough checks)
- Total: ~30-60 minutes (excluding troubleshooting)

### Troubleshooting Scenarios

**If terraform apply fails:**
- Check Hetzner API token: `clan secrets get hetzner-api-token`
- Verify API token has correct permissions
- Check terraform logs for specific error
- May need to `terraform destroy` and retry

**If clan install fails:**
- Check disko partitioning (may fail on disk layout)
- Verify VM network connectivity
- Check NixOS build errors (may need to fix configuration)
- SSH access may need manual intervention

**If LUKS boot fails:**
- Passphrase handling issue (check clan vars)
- May need console access via Hetzner Cloud console
- Check disko configuration for errors

**If services don't start:**
- Check systemd service logs: `journalctl -u <service>`
- Verify clan vars deployed correctly
- Check for NixOS configuration errors

### Cost Tracking

**Hetzner CX43**: $9.99/month (8 vCPU, 16GB RAM)
- Billing starts when Story 1.5 executes `terraform apply`
- Hourly billing: ~$0.014/hour
- Can `terraform destroy` to stop billing when testing complete
- Budget: ~$20-30 for 2-3 weeks of Phase 0 testing (acceptable cost)

**Cost Context:**
- cx43 chosen for performant testing (per explicit user direction in Story 1.4)
- Avoids resource-constrained hangs during infrastructure validation
- Ephemeral testing infrastructure - will be destroyed after Story 1.6 validation
- Larger than minimal cx22 ($3.49/month) but provides reliable performance

**Cost Management:**
- Destroy VM when not actively testing: `cd ~/projects/nix-workspace/test-clan && nix develop -c terraform destroy`
- Can recreate from configuration anytime: Story 1.5 workflow is repeatable
- Monitor actual costs in Hetzner Cloud console

### Solo Operator Workflow

This is the first HIGH RISK story - actual infrastructure deployment with costs.
Take time to review terraform plan carefully before apply.
Expected execution time: 4-8 hours (including troubleshooting).

### Architectural Context

**Why Hetzner first:**
- Proven in clan-infra (Vultr pattern adapts easily)
- Simpler networking than GCP
- Lower cost than GCP for equivalent resources
- Established NixOS community support

**Progressive validation:**
- Hetzner deployment must succeed before GCP (Story 1.8)
- Validates terraform + clan + disko + NixOS integration
- Proves zerotier controller deployment
- Foundation for multi-cloud coordination

### References

- [Prerequisite: docs/notes/development/work-items/1-4-create-hetzner-terraform-config-and-host-modules.md]
- [Source: docs/notes/development/epic-1-infrastructure-restructure-proposal.md#Story-1.5]
- [Upstream: clan-infra deployment workflow]
- [Upstream: Hetzner Cloud documentation]

## Change Log

**2025-11-04 (Story Update - Incorporating Story 1.4 Learnings)**:
- Story reviewed and updated based on Story 1.4 completion
- Updated all 13 acceptance criteria to reflect actual Story 1.4 implementation:
  - AC #1-2: Updated terraform commands (run inside nix develop shell, not nix run)
  - AC #3: Added cx43 VM size specification ($9.99/month per Story 1.4 decision)
  - AC #5: Added detail on vars generation (zerotier, LUKS passphrase via clan vars generators)
  - AC #7: Added btrfs subvolumes detail (/root, /nix, /home from disko.nix)
  - AC #8: Added device path validation as explicit AC
  - AC #11: Added zerotier identity to expected secrets
- Updated Tasks section with actual implementation details:
  - Added prerequisite task: navigate to test-clan and enter nix develop shell
  - Updated terraform commands to run inside nix develop (not nix run wrapper)
  - Added specific file paths from Story 1.4 (base.nix, hetzner.nix, disko.nix)
  - Added terraform resource details (tls_private_key, local_sensitive_file, data.external)
  - Added btrfs subvolumes validation task
  - Added nixos-facter hardware config validation
  - Added explicit vars generation validation (zerotier identity, LUKS passphrase)
  - Updated all commands with context from Story 1.4 test results
- Added "Learnings from Previous Story" section to Dev Notes:
  - Comprehensive Story 1.4 findings (8 critical learnings documented)
  - Expected vars error behavior (CRITICAL - do not fix before vars generation)
  - Deployment workflow expectations with timing estimates
  - Files created/modified reference for Story 1.5 context
  - Citations to Story 1.4 completion notes and review sections
- Updated Cost Tracking section:
  - Changed from cx22 to cx43 pricing ($9.99/month actual)
  - Added cost context (why cx43 chosen for performant testing)
  - Added terraform destroy command for cost management
- Updated References section:
  - Added Story 1.4 as prerequisite reference
- All updates maintain consistency with Story 1.4 approved implementation

### Expected Validation Points

After this story completes:
- Hetzner VM fully operational
- NixOS installed with LUKS encryption
- Zerotier controller running
- Clan vars deployed correctly
- Ready for Story 1.6 (secrets validation)

**What Story 1.5 does NOT validate:**
- Detailed clan secrets workflow (Story 1.6)
- Multi-machine coordination (Story 1.9)
- Long-term stability (Story 1.10)

### Important Constraints

**This is HIGH RISK - irreversible costs:**
- `terraform apply` will create real infrastructure
- Hetzner will start billing immediately
- Budget approved: ~€12-15 for Phase 0 testing
- Can destroy VM to stop costs if needed

**Zero-regression mandate does NOT apply**: Test infrastructure, experimental deployment.

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

<!-- Agent model will be recorded during implementation -->
