---
title: "Story 1.6: Initialize clan secrets and test vars deployment on Hetzner"
---

Status: drafted

## Story

As a system administrator,
I want to validate clan secrets management and vars deployment on hetzner-vm,
So that I can confirm the secrets infrastructure works correctly before GCP deployment.

## Context

Story 1.6 validates the clan secrets management infrastructure after successful Hetzner deployment.
This ensures the secrets workflow is understood and operational before adding GCP complexity.

**Secrets Management Strategy**: Clan uses age encryption for secrets (sops backend), with vars generation creating machine-specific secrets encrypted for admins group.
Understanding this workflow is critical for multi-machine coordination in Phase 1+.

**Validation Focus**: Verify clan vars generation, deployment, and access patterns work correctly on hetzner-vm before proceeding to GCP.

## Acceptance Criteria

1. Clan secrets initialized in test-clan repository with age keys generated for admins group
2. User age key added to admins group: `clan secrets groups add-user admins <username>`
3. Hetzner API token verified in clan secrets (from Story 1.4)
4. Clan vars for hetzner-vm validated:
   - SSH host keys generated and encrypted in sops/machines/hetzner-vm/secrets/
   - Public facts accessible in sops/machines/hetzner-vm/facts/
   - Zerotier identity generated and encrypted (if configured)
5. Vars deployed correctly on hetzner-vm:
   - /run/secrets/ directory has proper structure
   - Secret files have correct permissions (0600, root-owned)
   - SSH host keys functional
6. SSH host keys persistent across redeployments: no host key warnings after `nixos-rebuild`
7. Zerotier controller uses managed identity (not ephemeral)
8. Vars generation is repeatable: can regenerate and redeploy without errors
9. Documentation created: SECRETS-MANAGEMENT.md covering clan vars workflow

## Tasks / Subtasks

- [ ] Verify clan secrets initialization (AC: #1-2)
  - [ ] Check age keys exist: `ls -la sops/`
  - [ ] Verify admins group configured
  - [ ] Add user age key if not already: `clan secrets groups add-user admins <username>`
  - [ ] Test secret retrieval: `clan secrets get hetzner-api-token`

- [ ] Validate Hetzner API token secret (AC: #3)
  - [ ] Verify token stored: `clan secrets get hetzner-api-token`
  - [ ] Confirm token used by terraform (from Story 1.4)
  - [ ] Test token is encrypted (check sops/ directory)

- [ ] Inspect hetzner-vm vars structure (AC: #4)
  - [ ] Review secrets directory: `ls -la sops/machines/hetzner-vm/secrets/`
  - [ ] Verify SSH host key secrets present:
    - ssh_host_ed25519_key
    - ssh_host_rsa_key (if generated)
  - [ ] Review facts directory: `ls -la sops/machines/hetzner-vm/facts/`
  - [ ] Verify public facts (SSH public keys, zerotier network ID)
  - [ ] Check zerotier identity secret (if configured)

- [ ] Validate vars deployment on VM (AC: #5)
  - [ ] SSH to VM: `ssh root@<hetzner-ip>`
  - [ ] List deployed secrets: `ls -la /run/secrets/`
  - [ ] Verify directory structure matches expected layout
  - [ ] Check secret file permissions: `stat /run/secrets/ssh_host_ed25519_key`
  - [ ] Confirm ownership: root-owned, 0600 permissions
  - [ ] Verify symlinks or direct files as appropriate

- [ ] Test SSH host key functionality (AC: #6)
  - [ ] Record current SSH host key fingerprint: `ssh-keyscan <hetzner-ip>`
  - [ ] Rebuild system: `ssh root@<hetzner-ip> "nixos-rebuild switch"`
  - [ ] Verify SSH connection works without host key warning
  - [ ] Confirm host key fingerprint unchanged
  - [ ] Test persistent across reboots (already tested in Story 1.5)

- [ ] Validate zerotier identity persistence (AC: #7)
  - [ ] SSH to VM: `ssh root@<hetzner-ip>`
  - [ ] Check zerotier identity: `zerotier-cli info`
  - [ ] Record zerotier node ID
  - [ ] Rebuild system: `nixos-rebuild switch`
  - [ ] Verify zerotier node ID unchanged (using managed identity)

- [ ] Test vars regeneration workflow (AC: #8)
  - [ ] Backup current vars: `cp -r sops/machines/hetzner-vm sops/machines/hetzner-vm.bak`
  - [ ] Regenerate vars: `clan vars generate hetzner-vm`
  - [ ] Verify new secrets created
  - [ ] Compare to backup (should differ if regenerated)
  - [ ] Test deployment still works after regeneration
  - [ ] Restore backup if needed: `rm -rf sops/machines/hetzner-vm && mv sops/machines/hetzner-vm.bak sops/machines/hetzner-vm`

- [ ] Document secrets management workflow (AC: #9)
  - [ ] Create docs/notes/clan/SECRETS-MANAGEMENT.md
  - [ ] Document age key setup for admins
  - [ ] Document vars generation workflow
  - [ ] Document secret vs fact distinction
  - [ ] Document deployment mechanism (/run/secrets/)
  - [ ] Document troubleshooting steps
  - [ ] Include examples from hetzner-vm validation

## Dev Notes

### Clan Secrets Architecture

**Age Encryption:**
- Clan uses age for encryption (via sops-nix)
- Admins group has age keys that can decrypt secrets
- Each machine has vars encrypted for admins group + machine's age key (if generated)

**Vars vs Facts:**
- **Secrets (vars)**: Encrypted files in sops/machines/<machine>/secrets/
  - SSH host private keys
  - Zerotier identity secrets
  - Service credentials
- **Facts**: Unencrypted files in sops/machines/<machine>/facts/
  - SSH public keys
  - Zerotier network IDs
  - Public identifiers

**Deployment Mechanism:**
- Vars deployed to /run/secrets/ at runtime (tmpfs)
- systemd services configured to read from /run/secrets/
- Proper permissions enforced (0600, root-owned)

### Expected Vars for hetzner-vm

**Secrets:**
- ssh_host_ed25519_key (private key)
- ssh_host_rsa_key (private key, if generated)
- zerotier-identity.secret (controller identity)

**Facts:**
- ssh_host_ed25519_key.pub (public key)
- ssh_host_rsa_key.pub (public key, if generated)
- zerotier-network-id (controller network ID)

### Troubleshooting Scenarios

**If vars generation fails:**
- Check age keys initialized: `ls -la sops/`
- Verify user age key added to admins group
- Check clan-core vars module configuration

**If vars not deployed on VM:**
- Check sops-nix module imported in configuration
- Verify secrets paths match expected locations
- Check systemd sops service: `systemctl status sops-nix`

**If permissions incorrect:**
- Check sops-nix configuration for owner/mode settings
- Verify systemd service activates before dependent services

**If SSH host keys ephemeral:**
- Vars not being deployed correctly
- Check /run/secrets/ exists and populated
- Verify sshd configured to use /run/secrets/ keys

### Solo Operator Workflow

This story is validation and documentation focused - low operational risk.
Expected execution time: 2-4 hours (including documentation).
Validates patterns essential for Phase 1 multi-machine coordination.

### Architectural Context

**Why clan vars important:**
- Enables declarative secrets management
- Critical for multi-machine coordination
- Allows machine recreation without losing identity
- Foundation for service coordination (zerotier, SSH, etc.)

**Comparison to sops-nix:**
- Clan vars builds on sops-nix
- Adds clan-specific conventions (vars/facts distinction)
- Integrates with clan inventory and service instances

### References

- [Source: docs/notes/development/epic-1-infrastructure-restructure-proposal.md#Story-1.6]
- [Upstream: clan-core vars documentation]
- [Upstream: sops-nix documentation]

### Expected Validation Points

After this story completes:
- Clan secrets workflow understood
- Vars generation and deployment validated
- SSH host key persistence confirmed
- Zerotier identity persistence confirmed
- Documentation created for future reference
- Ready for Story 1.7 (GCP configuration)

**What Story 1.6 does NOT validate:**
- Vars sharing between machines (Story 1.9)
- GCP-specific secrets handling (Story 1.7-1.8)
- Long-term secrets management at scale

### Important Constraints

**Secrets are sensitive:**
- Never commit unencrypted secrets to git
- Verify age encryption working before committing
- Back up age keys securely (outside repository)

**Zero-regression mandate does NOT apply**: Test infrastructure, experimental secrets.

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

<!-- Agent model will be recorded during implementation -->
