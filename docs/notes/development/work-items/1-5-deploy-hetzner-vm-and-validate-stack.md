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

1. Terraform initialized in terranix workdir: `nix run .#terranix.terraform -- init`
2. Terraform plan reviewed and validated: `nix run .#terranix.terraform -- plan`
3. Hetzner VM provisioned via terraform: `nix run .#terranix.terraform -- apply`
4. VM accessible via SSH with terraform deployment key
5. Clan vars generated for hetzner-vm: `clan vars generate hetzner-vm`
6. NixOS installed via clan: `clan machines install hetzner-vm --target-host root@<ip> --update-hardware-config nixos-facter --yes`
7. System boots successfully with LUKS encryption
8. Post-installation SSH access works with clan-managed keys: `ssh root@<hetzner-ip>`
9. Zerotier controller operational: `ssh root@<hetzner-ip> "zerotier-cli info"` shows controller
10. Clan vars deployed correctly: `ssh root@<hetzner-ip> "ls -la /run/secrets/"` shows sshd keys
11. No critical errors in system logs: `ssh root@<hetzner-ip> "journalctl -p err --no-pager"`
12. System survives reboot: reboot VM and verify SSH access + services restore

## Tasks / Subtasks

- [ ] Initialize terraform (AC: #1)
  - [ ] Run: `nix run .#terranix.terraform -- init`
  - [ ] Verify hcloud provider downloaded
  - [ ] Verify terraform workspace initialized

- [ ] Review terraform plan (AC: #2)
  - [ ] Run: `nix run .#terranix.terraform -- plan`
  - [ ] Review resources to be created:
    - hcloud_ssh_key resource
    - hcloud_server resource (hetzner-vm)
    - null_resource provisioner
  - [ ] Verify no unexpected resources
  - [ ] Confirm plan before apply

- [ ] Provision Hetzner VM (AC: #3-4)
  - [ ] Run: `nix run .#terranix.terraform -- apply`
  - [ ] Confirm apply when prompted
  - [ ] Wait for VM provisioning to complete
  - [ ] Capture VM IP address from terraform output
  - [ ] Test SSH access: `ssh -i <deploy-key> root@<hetzner-ip>`

- [ ] Generate clan vars for hetzner-vm (AC: #5)
  - [ ] Run: `clan vars generate hetzner-vm`
  - [ ] Verify SSH host keys generated in sops/machines/hetzner-vm/secrets/
  - [ ] Verify public facts in sops/machines/hetzner-vm/facts/
  - [ ] Check zerotier identity generated (if configured)

- [ ] Install NixOS via clan (AC: #6-7)
  - [ ] Run: `clan machines install hetzner-vm --target-host root@<hetzner-ip> --update-hardware-config nixos-facter --yes`
  - [ ] Monitor installation progress
  - [ ] Wait for disko partitioning and LUKS setup
  - [ ] Wait for NixOS installation
  - [ ] Wait for initial system boot
  - [ ] Verify installation completes without errors

- [ ] Validate post-installation SSH access (AC: #8)
  - [ ] Test SSH with clan-managed keys: `ssh root@<hetzner-ip>`
  - [ ] Verify SSH works without deployment key
  - [ ] Check clan-managed SSH host keys deployed

- [ ] Validate zerotier controller (AC: #9)
  - [ ] SSH to VM: `ssh root@<hetzner-ip>`
  - [ ] Check zerotier status: `zerotier-cli info`
  - [ ] Verify zerotier controller role
  - [ ] Capture zerotier network ID for GCP peer (Story 1.8)

- [ ] Validate clan vars deployment (AC: #10)
  - [ ] SSH to VM: `ssh root@<hetzner-ip>`
  - [ ] List secrets: `ls -la /run/secrets/`
  - [ ] Verify sshd host keys present (ssh_host_ed25519_key, etc.)
  - [ ] Verify proper permissions (0600, root-owned)
  - [ ] Verify zerotier identity present (if configured)

- [ ] Check system logs for errors (AC: #11)
  - [ ] Review error logs: `ssh root@<hetzner-ip> "journalctl -p err --no-pager | head -50"`
  - [ ] Investigate any critical errors
  - [ ] Verify no systemd service failures
  - [ ] Check dmesg for hardware issues: `ssh root@<hetzner-ip> "dmesg | grep -i error"`

- [ ] Test system reboot (AC: #12)
  - [ ] Reboot VM: `ssh root@<hetzner-ip> "reboot"`
  - [ ] Wait for system to come back online (~2-3 minutes)
  - [ ] Test SSH access after reboot
  - [ ] Verify zerotier controller restored
  - [ ] Verify services operational

- [ ] Document deployment experience
  - [ ] Record actual commands used
  - [ ] Document any issues encountered and resolutions
  - [ ] Note any deviations from clan-infra pattern
  - [ ] Capture deployment timing (for future estimates)

## Dev Notes

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

**Hetzner CX22**: ~€5.83/month (~€0.008/hour)
- Billing starts when VM is running
- Can `terraform destroy` to stop billing
- Budget ~€12-15 for 2-3 weeks of testing

**Cost optimization:**
- Use smallest VM size (CX22)
- Destroy VM when not actively testing
- Can recreate from configuration anytime

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

- [Source: docs/notes/development/epic-1-infrastructure-restructure-proposal.md#Story-1.5]
- [Upstream: clan-infra deployment workflow]
- [Upstream: Hetzner Cloud documentation]

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
