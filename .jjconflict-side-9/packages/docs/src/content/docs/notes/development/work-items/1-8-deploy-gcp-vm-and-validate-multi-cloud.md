---
title: "Story 1.8: Deploy GCP VM and validate multi-cloud infrastructure"
---

Status: drafted

## Story

As a system administrator,
I want to provision and deploy gcp-vm to Google Cloud Platform,
So that I can validate multi-cloud infrastructure coordination via clan and zerotier.

## Context

Story 1.8 performs GCP VM deployment - the second cloud provider deployment validating multi-cloud capabilities.
This is HIGH RISK due to GCP complexity and networking challenges.

**Multi-Cloud Validation**: This story proves clan inventory and zerotier mesh can coordinate VMs across different cloud providers (Hetzner + GCP).
Success here demonstrates the migration approach works for heterogeneous infrastructure.

**Decision Point**: If GCP deployment encounters critical blockers, can abort and defer GCP to post-Phase 0.
Hetzner-only infrastructure is sufficient for Phase 0 validation.

## Acceptance Criteria

1. Terraform plan reviewed for GCP resources: `nix run .#terranix.terraform -- plan`
2. GCP VM provisioned via terraform: `nix run .#terranix.terraform -- apply`
3. VM accessible via SSH with terraform deployment key
4. Clan vars generated for gcp-vm: `clan vars generate gcp-vm`
5. NixOS installed via clan: `clan machines install gcp-vm --target-host root@<gcp-ip> --update-hardware-config nixos-facter --yes`
6. System boots successfully with LUKS encryption
7. Post-installation SSH access works with clan-managed keys: `ssh root@<gcp-ip>`
8. Zerotier peer connects to Hetzner controller: `ssh root@<gcp-ip> "zerotier-cli status"` shows network membership
9. Zerotier mesh operational: bidirectional ping between Hetzner and GCP zerotier IPs
10. SSH via zerotier works from Hetzner to GCP: `ssh root@<gcp-zerotier-ip>` (from hetzner-vm)
11. Clan vars deployed correctly on GCP VM: `/run/secrets/` populated
12. System survives reboot: reboot VM and verify services restore

## Tasks / Subtasks

- [ ] Review terraform plan for GCP (AC: #1)
  - [ ] Run: `nix run .#terranix.terraform -- plan`
  - [ ] Review GCP resources to be created:
    - VPC network (if creating new)
    - Firewall rules (SSH, zerotier)
    - google_compute_instance (gcp-vm)
    - null_resource provisioner
  - [ ] Verify no unexpected resources
  - [ ] Confirm plan before apply

- [ ] Provision GCP VM (AC: #2-3)
  - [ ] Run: `nix run .#terranix.terraform -- apply`
  - [ ] Confirm apply when prompted
  - [ ] Wait for VM provisioning to complete (~2-5 minutes)
  - [ ] Capture VM external IP from terraform output
  - [ ] Test SSH access: `ssh -i <deploy-key> root@<gcp-ip>`
  - [ ] If SSH fails, troubleshoot GCP firewall rules

- [ ] Generate clan vars for gcp-vm (AC: #4)
  - [ ] Run: `clan vars generate gcp-vm`
  - [ ] Verify SSH host keys generated
  - [ ] Verify zerotier peer identity generated
  - [ ] Check vars encrypted in sops/machines/gcp-vm/secrets/

- [ ] Install NixOS via clan (AC: #5-6)
  - [ ] Run: `clan machines install gcp-vm --target-host root@<gcp-ip> --update-hardware-config nixos-facter --yes`
  - [ ] Monitor installation progress
  - [ ] Wait for disko partitioning and LUKS setup
  - [ ] Wait for NixOS installation
  - [ ] Wait for initial system boot
  - [ ] If installation fails, troubleshoot:
    - GCP boot disk requirements
    - Disko configuration compatibility
    - Network connectivity issues

- [ ] Validate post-installation SSH access (AC: #7)
  - [ ] Test SSH with clan-managed keys: `ssh root@<gcp-ip>`
  - [ ] Verify SSH works without deployment key
  - [ ] Check clan-managed SSH host keys deployed

- [ ] Validate zerotier peer connectivity (AC: #8-9)
  - [ ] SSH to GCP VM: `ssh root@<gcp-ip>`
  - [ ] Check zerotier status: `zerotier-cli status`
  - [ ] Verify zerotier peer connected to Hetzner controller
  - [ ] Check network membership: `zerotier-cli listnetworks`
  - [ ] Capture GCP zerotier IP address
  - [ ] From GCP, ping Hetzner zerotier IP: `ping <hetzner-zerotier-ip>`
  - [ ] From Hetzner, ping GCP zerotier IP: `ssh root@<hetzner-ip> "ping <gcp-zerotier-ip>"`
  - [ ] Verify bidirectional connectivity successful

- [ ] Test SSH via zerotier mesh (AC: #10)
  - [ ] From Hetzner VM, SSH to GCP via zerotier: `ssh root@<hetzner-ip> "ssh root@<gcp-zerotier-ip>"`
  - [ ] Verify SSH connection successful
  - [ ] Test reverse direction (GCP to Hetzner via zerotier)
  - [ ] Confirm zerotier mesh enables cross-cloud communication

- [ ] Validate clan vars deployment (AC: #11)
  - [ ] SSH to GCP VM: `ssh root@<gcp-ip>`
  - [ ] List secrets: `ls -la /run/secrets/`
  - [ ] Verify sshd host keys present
  - [ ] Verify zerotier identity present
  - [ ] Check permissions (0600, root-owned)

- [ ] Test system reboot (AC: #12)
  - [ ] Reboot GCP VM: `ssh root@<gcp-ip> "reboot"`
  - [ ] Wait for system to come back online (~2-3 minutes)
  - [ ] Test SSH access after reboot
  - [ ] Verify zerotier peer reconnects to Hetzner controller
  - [ ] Verify services operational

- [ ] Document GCP deployment experience
  - [ ] Record actual commands used
  - [ ] Document GCP-specific challenges and resolutions
  - [ ] Compare to Hetzner deployment (what was harder/easier)
  - [ ] Note any deviations from expected patterns
  - [ ] Capture deployment timing

## Dev Notes

### Deployment Workflow Summary

**Phase 1: Terraform Provisioning (GCP)**
1. `terraform plan` - review GCP resources
2. `terraform apply` - provision VM + network + firewall
3. Capture VM external IP
4. Test SSH access with deployment key

**Phase 2: Clan Installation (Same as Hetzner)**
1. `clan vars generate gcp-vm`
2. `clan machines install gcp-vm --target-host root@<gcp-ip>`
3. Wait for installation + reboot
4. Test SSH with clan-managed keys

**Phase 3: Multi-Cloud Validation**
1. Verify zerotier peer connects to Hetzner controller
2. Test zerotier mesh connectivity (bidirectional ping)
3. Test SSH via zerotier between clouds
4. Validate clan vars deployed correctly

### Expected Timing

- Terraform apply: ~3-7 minutes (GCP provisioning may be slower)
- Clan install: ~10-30 minutes (depends on internet speed, Nix builds)
- Multi-cloud validation: ~20-30 minutes (zerotier connectivity testing)
- Total: ~40-80 minutes (excluding troubleshooting)

### GCP-Specific Troubleshooting

**If terraform apply fails:**
- Check GCP service account credentials: `clan secrets get gcp-service-account-json`
- Verify service account has Compute Admin permissions
- Check GCP project ID configured correctly
- Review terraform logs for specific error

**If SSH access fails:**
- Check GCP firewall rules allow SSH (port 22)
- Verify external IP address assigned to instance
- Check SSH key added to instance metadata
- May need to use GCP console for first SSH access

**If clan install fails:**
- GCP boot disk may have specific requirements
- Disko configuration may need GCP-specific adaptations
- Check NixOS build errors (may need to fix configuration)
- GCP metadata server may interfere with networking

**If zerotier peer fails to connect:**
- Check GCP firewall allows UDP port 9993
- Verify zerotier controller running on Hetzner
- Check zerotier network ID configured correctly
- May need to authorize peer from Hetzner controller

**If LUKS boot fails:**
- GCP boot requirements may differ from Hetzner
- May need console access via GCP console
- Check disko configuration for GCP compatibility

### Cost Tracking

**GCP e2-micro**: ~$7.11/month (~$0.010/hour)
- Billing starts when VM is running
- Can `terraform destroy` to stop billing
- Free tier may apply (check GCP free tier eligibility)

**Combined cost (Hetzner + GCP)**: ~$13-15/month
- Budget ~$20-30 for 2-3 weeks of testing
- Acceptable cost for multi-cloud validation

### Solo Operator Workflow

This is HIGH RISK - GCP complexity and costs.
Expected execution time: 6-8 hours (including troubleshooting).
May encounter GCP-specific issues not present in Hetzner.

**Decision Point**: If GCP deployment takes >10 hours or hits critical blockers:
- Pause and evaluate if GCP worth the complexity
- Option to defer GCP to post-Phase 0
- Hetzner-only infrastructure sufficient for core validation

### Architectural Context

**Why multi-cloud validation important:**
- Demonstrates clan inventory works across providers
- Validates zerotier mesh across different cloud networks
- Proves infrastructure approach is provider-agnostic
- Expands options for future infrastructure decisions

**GCP vs Hetzner comparison:**
- Hetzner: Simple, proven, low complexity
- GCP: Complex networking, unfamiliar, higher risk
- GCP validates pattern generalization beyond Hetzner

**Acceptable to defer**: If GCP too complex, Hetzner-only validates core patterns.
Multi-cloud can be revisited post-Phase 0 with lessons learned.

### References

- [Source: docs/notes/development/epic-1-infrastructure-restructure-proposal.md#Story-1.8]
- [Upstream: clan-infra multi-cloud patterns]
- [Upstream: GCP Compute Engine documentation]

### Expected Validation Points

After this story completes:
- GCP VM fully operational
- NixOS installed with LUKS encryption
- Zerotier mesh connects Hetzner + GCP
- Multi-cloud coordination validated
- Ready for Story 1.9 (multi-machine coordination testing)

**What Story 1.8 does NOT validate:**
- Detailed multi-machine coordination features (Story 1.9)
- Service instance coordination across clouds (Story 1.9)
- Long-term stability (Story 1.10)

### Important Constraints

**This is HIGH RISK - GCP complexity:**
- GCP networking more complex than Hetzner
- Unfamiliar territory, may encounter unexpected issues
- Budget approved: ~$20-30 for Phase 0 testing
- Can abort if blockers too severe

**Decision point at 10 hours**: If GCP deployment exceeds 10 hours or hits critical blockers, pause and evaluate.
Hetzner-only infrastructure is acceptable fallback.

**Zero-regression mandate does NOT apply**: Test infrastructure, experimental deployment.

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

<!-- Agent model will be recorded during implementation -->
