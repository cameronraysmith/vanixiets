---
title: "Epic 1 Infrastructure Deployment Restructure Proposal"
author: "Dev"
date: "2025-11-03"
---

## Executive Summary

This proposal restructures Epic 1 (Phase 0) to prioritize **infrastructure deployment** over architectural validation.
The strategic shift recognizes that clan-infra provides a proven pattern for terraform/terranix + clan integration, making architectural validation secondary to getting VMs deployed and operational.

**Key Changes:**

1. **Story 1.1** expanded to include terraform/terranix setup alongside test-clan preparation
2. **Story 1.2** (dendritic pattern) marked OPTIONAL - can skip if conflicts with infrastructure
3. **Story 1.3** modified to use REAL VM inventory (Hetzner + GCP) not just test-vm
4. **Stories 1.4-1.6** added for Hetzner VM deployment (proven pattern from clan-infra)
5. **Stories 1.7-1.9** added for GCP VM deployment (new territory, after Hetzner works)
6. **Stories 1.10-1.11** added for validation and stability monitoring
7. **Story 1.12** remains as go/no-go decision gate

**Total Stories:** 12 (was 6)
**Estimated Timeline:** 2-3 weeks (was 1 week)
**Risk Level:** Medium (infrastructure deployment has operational risk)

---

## Strategic Context

### What Changed

**Original Epic 1 goal:** Validate dendritic + clan in test-clan repository before infrastructure

**Revised Epic 1 goal:** Deploy Hetzner + GCP VMs using clan-infra's proven terranix pattern, with dendritic as optional optimization

**Rationale:**

1. **clan-infra is the expert**: They've proven terraform/terranix + clan works at scale (10+ VMs)
2. **Dendritic is secondary**: Getting infrastructure deployed is more valuable than architectural purity
3. **Progressive validation**: Hetzner first (proven), then GCP (new), then stability before darwin
4. **Real VMs faster**: Deploy actual infrastructure instead of disposable test environment

### What Stayed the Same

- Still Phase 0 (before darwin migration)
- Still has go/no-go decision gate at end
- Still prioritizes stability validation (1 week minimum)
- Still uses test-clan repository for experimentation
- Still captures learnings for Phase 1 (cinnabar) and beyond

---

## Detailed Story Breakdown

### Story 1.1: Setup test-clan repository with terraform/terranix infrastructure

**User Story:**

As a system administrator,
I want to prepare test-clan repository with both clan-core and terranix/terraform infrastructure,
So that I can deploy real VMs (Hetzner + GCP) using proven patterns from clan-infra.

**Acceptance Criteria:**

1. test-clan repository at ~/projects/nix-workspace/test-clan/ has working branch created
2. flake.nix updated with inputs:
   - nixpkgs (unstable)
   - flake-parts
   - clan-core (main branch)
   - terranix (for terraform generation)
   - disko (for declarative disk partitioning)
   - srvos (for server hardening)
3. Terranix flake module imported: `inputs.terranix.flakeModule`
4. modules/ directory structure created:
   - modules/base/
   - modules/hosts/
   - modules/flake-parts/
   - modules/terranix/
5. modules/terranix/base.nix created with provider configuration:
   - Hetzner Cloud provider (hcloud)
   - GCP provider (google)
   - Secrets retrieval via clan secrets (API tokens)
6. modules/flake-parts/clan.nix created with clan.meta.name = "test-clan"
7. Flake evaluates: `nix flake check`
8. Terraform inputs available: `nix eval .#terranix --apply builtins.attrNames`
9. README.md documents Phase 0 infrastructure deployment purpose

**Prerequisites:** None (first story)

**Estimated Effort:** 2-4 hours

**Risk Level:** Low (setup only, no deployment yet)

**Notes:**
- Follow clan-infra pattern closely: flake.nix structure, terranix integration, secrets via clan
- Use minimal specialArgs (only `self` if needed, matching clan-infra)
- This story sets foundation for all subsequent infrastructure deployment

---

### Story 1.2: Implement dendritic flake-parts pattern in test-clan (OPTIONAL)

**User Story:**

As a system administrator,
I want to apply dendritic flake-parts organizational patterns to test-clan,
So that I can evaluate whether dendritic optimization adds value alongside clan functionality.

**⚠️ OPTIONAL STORY - Can skip if conflicts with infrastructure deployment**

**Acceptance Criteria:**

1. import-tree configured in flake.nix for automatic module discovery (if using dendritic)
2. Base module created contributing to flake.modules.nixos.base namespace
3. Test host module using config.flake.modules namespace imports
4. Module namespace evaluates: `nix eval .#flake.modules.nixos --apply builtins.attrNames`
5. No additional specialArgs beyond minimal framework values
6. Dendritic pattern documented in DENDRITIC-NOTES.md (what worked, what didn't)

**Prerequisites:** Story 1.1 (test-clan infrastructure setup)

**Estimated Effort:** 2-4 hours (only if pursuing dendritic)

**Risk Level:** Low (can abandon if conflicts discovered)

**Decision Point:**
- If dendritic conflicts with terranix or clan integration: SKIP and proceed to Story 1.3
- If dendritic works smoothly: COMPLETE and document patterns
- Infrastructure deployment is non-negotiable, dendritic optimization is nice-to-have

---

### Story 1.3: Configure clan inventory with Hetzner and GCP VM definitions

**User Story:**

As a system administrator,
I want to define clan inventory with real VM machine definitions (Hetzner + GCP),
So that I have infrastructure targets for terraform deployment and clan coordination.

**Acceptance Criteria:**

1. modules/flake-parts/clan.nix expanded with inventory.machines:
   - `hetzner-vm`: tags = ["nixos" "cloud" "hetzner"], machineClass = "nixos"
   - `gcp-vm`: tags = ["nixos" "cloud" "gcp"], machineClass = "nixos"
2. Service instances configured:
   - `emergency-access`: roles.default.tags."all" (both VMs)
   - `sshd-clan`: roles.server.tags."all" + roles.client.tags."all"
   - `zerotier-local`: roles.controller.machines.hetzner-vm + roles.peer.machines.gcp-vm
   - `users-root`: roles.default.tags."all" (root access both VMs)
3. Inventory evaluates: `nix eval .#clan.inventory --json | jq .machines`
4. Machine definitions include proper tags for service targeting
5. nixosConfigurations created for both machines (minimal, will expand later)
6. Configurations build: `nix build .#nixosConfigurations.{hetzner-vm,gcp-vm}.config.system.build.toplevel`

**Prerequisites:**
- Story 1.1 (infrastructure setup)
- Story 1.2 OPTIONAL (dendritic pattern, only if completed)

**Estimated Effort:** 2-4 hours

**Risk Level:** Low (configuration only, no deployment)

**Notes:**
- Use vanilla clan + flake-parts pattern (proven in clan-infra) if dendritic skipped
- Real VM names (not test-vm) for actual infrastructure deployment
- Zerotier controller on Hetzner (will be always-on), GCP as peer

---

### Story 1.4: Create Hetzner VM terraform configuration and host modules

**User Story:**

As a system administrator,
I want to create terraform configuration for Hetzner Cloud VM provisioning,
So that I can deploy hetzner-vm using proven patterns from clan-infra.

**Acceptance Criteria:**

1. modules/terranix/hetzner.nix created with:
   - hcloud provider configuration
   - SSH key resource for terraform deployment key
   - Hetzner Cloud server resource (CX22 or CX32, 2-4 vCPU for testing)
   - null_resource for `clan machines install` provisioning
2. modules/hosts/hetzner-vm/default.nix created with:
   - Base NixOS configuration (hostname, state version, nix settings)
   - srvos hardening modules imported
   - Networking configuration
3. modules/hosts/hetzner-vm/disko.nix created with:
   - LUKS encryption for root partition
   - Standard partition layout (EFI + LUKS root)
4. Hetzner API token stored as clan secret: `clan secrets set hetzner-api-token`
5. Terraform configuration generates: `nix build .#terranix.terraform`
6. Generated terraform valid: manual review of terraform.tf.json
7. Host configuration builds: `nix build .#nixosConfigurations.hetzner-vm.config.system.build.toplevel`
8. Disko configuration generates partition commands: `nix eval .#nixosConfigurations.hetzner-vm.config.disko.disks --apply toString`

**Prerequisites:** Story 1.3 (inventory configured)

**Estimated Effort:** 4-6 hours

**Risk Level:** Medium (first terraform configuration, pattern learning)

**Notes:**
- Follow clan-infra terraform-configuration.nix pattern exactly
- Use smaller VM size for testing (CX22 ~€5/month or CX32 ~€8/month)
- Terraform deploy key generation follows clan-infra vultr.nix pattern
- LUKS encryption non-negotiable (security requirement)

---

### Story 1.5: Deploy Hetzner VM and validate infrastructure stack

**User Story:**

As a system administrator,
I want to provision and deploy hetzner-vm to Hetzner Cloud,
So that I can validate the complete infrastructure stack (terraform + clan + disko + NixOS) works end-to-end.

**Acceptance Criteria:**

1. Terraform initialized: `nix run .#terranix.terraform -- init`
2. Terraform plan reviewed: `nix run .#terranix.terraform -- plan` (check resource creation)
3. Hetzner VM provisioned: `nix run .#terranix.terraform -- apply`
4. VM accessible via SSH with terraform deploy key
5. Clan vars generated for hetzner-vm: `clan vars generate hetzner-vm`
6. NixOS installed via clan: `clan machines install hetzner-vm --target-host root@<ip> --update-hardware-config nixos-facter --yes`
7. System boots successfully with LUKS encryption
8. Post-installation SSH access works: `ssh root@<hetzner-ip>` (using clan-managed keys)
9. Zerotier controller operational: `ssh root@<hetzner-ip> "zerotier-cli info"` shows controller
10. Clan vars deployed: `ssh root@<hetzner-ip> "ls -la /run/secrets/"` shows sshd keys
11. No critical errors in journalctl logs

**Prerequisites:** Story 1.4 (Hetzner terraform + host config)

**Estimated Effort:** 4-8 hours (deployment + validation + troubleshooting)

**Risk Level:** High (real infrastructure deployment, costs money, operational risk)

**Decision Point:**
- If deployment fails with critical issues: troubleshoot and resolve before GCP
- If infrastructure works: document patterns and proceed to GCP
- Hetzner must be stable before attempting GCP (progressive validation)

**Cost:** ~€5-8/month for Hetzner CX22/CX32 (acceptable testing cost)

---

### Story 1.6: Initialize clan secrets and test vars deployment on Hetzner

**User Story:**

As a system administrator,
I want to validate clan secrets management and vars deployment on hetzner-vm,
So that I can confirm the secrets infrastructure works correctly before GCP deployment.

**Acceptance Criteria:**

1. Clan secrets initialized in test-clan: age keys generated for admins group
2. User age key added: `clan secrets groups add-user admins <username>`
3. Hetzner API token verified in clan secrets (from Story 1.4)
4. Clan vars for hetzner-vm validated:
   - SSH host keys generated (encrypted in sops/machines/hetzner-vm/secrets/)
   - Zerotier identity generated (if needed)
   - Public facts accessible (unencrypted in sops/machines/hetzner-vm/facts/)
5. Vars deployed correctly: `/run/secrets/` has proper permissions (0600 root-owned)
6. SSH host keys functional: able to SSH without host key warnings after redeployment
7. Zerotier controller uses managed identity (not ephemeral)
8. Vars generation repeatable: can regenerate and redeploy without errors
9. Documentation created: SECRETS-MANAGEMENT.md covering clan vars workflow

**Prerequisites:** Story 1.5 (Hetzner deployed)

**Estimated Effort:** 2-4 hours

**Risk Level:** Low (validation and documentation)

**Notes:**
- This validates the secrets management pattern before GCP complexity
- Essential for multi-machine coordination (Phase 1+)
- Document any deviations from clan-infra pattern

---

### Story 1.7: Create GCP VM terraform configuration and host modules

**User Story:**

As a system administrator,
I want to create terraform configuration for GCP VM provisioning,
So that I can deploy gcp-vm using patterns learned from Hetzner deployment.

**Acceptance Criteria:**

1. modules/terranix/gcp.nix created with:
   - Google Cloud provider configuration
   - SSH key resource for terraform deployment key
   - GCP compute instance resource (e2-micro or e2-small for testing, free tier eligible)
   - null_resource for `clan machines install` provisioning
   - Network configuration (VPC, firewall rules for SSH + zerotier)
2. modules/hosts/gcp-vm/default.nix created with:
   - Base NixOS configuration (hostname, state version, nix settings)
   - srvos hardening modules imported
   - GCP-specific networking configuration
3. modules/hosts/gcp-vm/disko.nix created with:
   - LUKS encryption for root partition
   - GCP-compatible partition layout (considers boot requirements)
4. GCP service account JSON stored as clan secret: `clan secrets set gcp-service-account-json`
5. GCP project ID configured in terraform
6. Terraform configuration generates: `nix build .#terranix.terraform`
7. Host configuration builds: `nix build .#nixosConfigurations.gcp-vm.config.system.build.toplevel`

**Prerequisites:** Story 1.6 (Hetzner stable, secrets validated)

**Estimated Effort:** 4-6 hours

**Risk Level:** Medium-High (GCP is new territory, different from Hetzner/Vultr)

**Notes:**
- GCP networking more complex than Hetzner (VPC, firewall rules required)
- Use e2-micro for cost optimization (~$7-10/month or free tier if available)
- May need GCP-specific disko configuration (boot disk requirements differ)
- Research clan-infra GCP examples if available, otherwise adapt from Hetzner pattern

---

### Story 1.8: Deploy GCP VM and validate multi-cloud infrastructure

**User Story:**

As a system administrator,
I want to provision and deploy gcp-vm to Google Cloud Platform,
So that I can validate multi-cloud infrastructure coordination via clan and zerotier.

**Acceptance Criteria:**

1. Terraform plan reviewed for GCP resources: `nix run .#terranix.terraform -- plan`
2. GCP VM provisioned: `nix run .#terranix.terraform -- apply`
3. VM accessible via SSH with terraform deploy key
4. Clan vars generated for gcp-vm: `clan vars generate gcp-vm`
5. NixOS installed via clan: `clan machines install gcp-vm --target-host root@<gcp-ip> --update-hardware-config nixos-facter --yes`
6. System boots successfully with LUKS encryption
7. Post-installation SSH access works: `ssh root@<gcp-ip>`
8. Zerotier peer connects to Hetzner controller: `ssh root@<gcp-ip> "zerotier-cli status"` shows network membership
9. Zerotier mesh operational: From Hetzner, can ping GCP zerotier IP and vice versa
10. SSH via zerotier works: `ssh root@<gcp-zerotier-ip>` from Hetzner
11. Clan vars deployed correctly on GCP VM

**Prerequisites:** Story 1.7 (GCP terraform + host config)

**Estimated Effort:** 6-8 hours (new cloud provider, troubleshooting expected)

**Risk Level:** High (new cloud provider, networking complexity, cost)

**Decision Point:**
- If GCP deployment too complex: consider dropping GCP from MVP, stick with Hetzner only
- If GCP works but unreliable: document issues, may defer to post-Phase 0
- If GCP works smoothly: celebrate and document patterns

**Cost:** ~$7-10/month for GCP e2-micro (acceptable testing cost)

---

### Story 1.9: Test multi-machine coordination across Hetzner + GCP

**User Story:**

As a system administrator,
I want to validate multi-machine coordination features across Hetzner and GCP VMs,
So that I can confirm clan inventory and service instances work correctly in multi-cloud environment.

**Acceptance Criteria:**

1. 2-machine zerotier network operational:
   - Hetzner VM (controller role) + GCP VM (peer role)
   - Full mesh connectivity: bidirectional ping successful
   - Network latency acceptable (< 200ms, depends on regions)
2. SSH via zerotier works in both directions:
   - From Hetzner to GCP via zerotier IP
   - From GCP to Hetzner via zerotier IP
   - Certificate-based authentication functional
3. Clan service instances deployed correctly:
   - emergency-access on both machines (root access recovery)
   - sshd-clan server + client roles on both machines
   - users-root on both machines
4. Vars shared appropriately (if any configured with share = true)
5. Multi-machine rebuild test: update configuration, rebuild both machines, validate changes
6. Service coordination test: modify service instance setting, verify applied to both machines
7. Network stability: 24-hour monitoring shows no disconnections or errors

**Prerequisites:** Story 1.8 (GCP deployed)

**Estimated Effort:** 2-4 hours

**Risk Level:** Medium (depends on successful deployment from previous stories)

**Notes:**
- This validates patterns for Phase 1 (cinnabar) and Phase 2+ (darwin hosts)
- If multi-machine coordination has issues, troubleshoot before proceeding
- Document any discovered limitations or workarounds

---

### Story 1.10: Monitor infrastructure stability and extract deployment patterns

**User Story:**

As a system administrator,
I want to monitor both VMs for stability over 1 week minimum,
So that I can validate the infrastructure is production-ready before darwin migration.

**Acceptance Criteria:**

1. 1-week stability monitoring (minimum):
   - Daily checks: SSH access, zerotier connectivity, system logs
   - No critical errors or service failures
   - No unexpected reboots or crashes
   - Uptime > 99% (allowing brief maintenance)
2. DEPLOYMENT-PATTERNS.md created documenting:
   - Terraform/terranix configuration patterns (Hetzner + GCP)
   - Clan inventory patterns for cloud VMs
   - Disko patterns for LUKS encryption
   - Vars generation patterns for secrets
   - Multi-cloud zerotier mesh setup
   - Troubleshooting notes from deployment experience
3. Cost tracking: actual monthly costs for Hetzner + GCP (~$15-20/month total)
4. Performance baseline: build times, deployment times, network latency
5. Patterns validated as reusable for Phase 1 (cinnabar) deployment
6. Issues log: any problems discovered, workarounds applied
7. Rollback procedure tested: can destroy and recreate infrastructure from configuration

**Prerequisites:** Story 1.9 (multi-machine coordination validated)

**Estimated Effort:** 1 week calendar time (15-30 min daily monitoring)

**Risk Level:** Low (monitoring only, stability gate)

**Stability Gate:** Infrastructure must be stable for 1 week minimum before go/no-go decision

**Notes:**
- This is a calendar time requirement, not development time
- Daily monitoring can be lightweight (check logs, test connectivity)
- Document everything - these patterns are foundation for entire migration

---

### Story 1.11: Document integration findings and architectural decisions

**User Story:**

As a system administrator,
I want to document all integration findings and architectural decisions from Phase 0,
So that I have comprehensive reference for Phase 1 and beyond.

**Acceptance Criteria:**

1. INTEGRATION-FINDINGS.md created documenting:
   - Terraform/terranix + clan integration (how it works, gotchas)
   - Dendritic pattern evaluation (if attempted in Story 1.2)
   - Acceptable deviations from pure patterns (specialArgs, module organization)
   - Hetzner deployment experience (easy, hard, surprises)
   - GCP deployment experience (comparison to Hetzner, challenges)
   - Multi-cloud coordination findings (what works, what doesn't)
   - Zerotier mesh networking across clouds (latency, reliability)
2. ARCHITECTURAL-DECISIONS.md created with:
   - Why terraform/terranix for infrastructure provisioning
   - Why LUKS encryption (security requirement)
   - Why zerotier mesh (always-on coordination, VPN)
   - Clan inventory patterns chosen
   - Service instance patterns (roles, targeting)
   - Secrets management strategy (clan vars vs sops-nix)
3. Confidence level assessed for each pattern: proven, needs-testing, uncertain
4. Recommendations for Phase 1 cinnabar deployment
5. Known limitations documented (GCP complexity, cost, alternatives)

**Prerequisites:** Story 1.10 (stability validated, patterns extracted)

**Estimated Effort:** 2-4 hours

**Risk Level:** Low (documentation only)

**Notes:**
- This is critical knowledge capture for Phase 1
- Be honest about what didn't work or was harder than expected
- Include code examples, commands, troubleshooting steps

---

### Story 1.12: Execute go/no-go decision framework for Phase 1

**User Story:**

As a system administrator,
I want to evaluate Phase 0 results against go/no-go criteria,
So that I can make an informed decision about proceeding to Phase 1 (cinnabar production deployment).

**Acceptance Criteria:**

1. GO-NO-GO-DECISION.md created with decision framework evaluation:
   - Infrastructure deployment success (Hetzner + GCP operational: PASS/FAIL)
   - Stability validation (1 week stable: PASS/FAIL)
   - Multi-machine coordination (clan inventory + zerotier working: PASS/FAIL)
   - Terraform/terranix integration (proven pattern: PASS/FAIL)
   - Secrets management (clan vars working: PASS/FAIL)
   - Cost acceptability (~$15-20/month for 2 VMs: ACCEPTABLE/EXCESSIVE)
   - Pattern confidence (reusable for Phase 1: HIGH/MEDIUM/LOW)
2. Blockers identified (if any):
   - Critical: must resolve before Phase 1
   - Major: can work around but risky
   - Minor: document and monitor
3. Decision rendered:
   - **GO**: All criteria passed, high confidence, proceed to Phase 1 cinnabar
   - **CONDITIONAL GO**: Some issues but manageable, proceed with caution
   - **NO-GO**: Critical blockers, resolve or pivot strategy
4. If GO/CONDITIONAL GO:
   - Phase 1 cinnabar deployment plan confirmed
   - Patterns ready to apply to production infrastructure
   - Test VMs can be destroyed (or kept for experimentation)
5. If NO-GO:
   - Alternative approaches documented
   - Issues requiring resolution identified
   - Timeline for retry or pivot strategy
6. Next steps clearly defined based on decision outcome

**Prerequisites:** Story 1.11 (findings documented)

**Estimated Effort:** 1-2 hours

**Risk Level:** Low (decision only)

**Decision Criteria:**

**GO if:**
- Both VMs deployed successfully
- 1 week stability achieved
- Multi-machine coordination working
- Patterns documented with confidence
- Cost acceptable for production use

**CONDITIONAL GO if:**
- Minor issues discovered but workarounds available
- GCP more complex than expected but Hetzner solid
- Dendritic pattern skipped (acceptable, not required)
- Stability good but < 1 week (6+ days acceptable)

**NO-GO if:**
- Critical deployment failures
- Stability issues (crashes, service failures)
- Excessive cost or complexity
- Patterns not reusable for production

---

## Story Sequencing Diagram

```
Story 1.1: Setup test-clan + terraform/terranix
    ↓
Story 1.2: [OPTIONAL] Dendritic pattern (can skip)
    ↓
Story 1.3: Configure clan inventory (Hetzner + GCP)
    ↓
Story 1.4: Create Hetzner terraform + host config
    ↓
Story 1.5: Deploy Hetzner VM ⚠️ HIGH RISK
    ↓
Story 1.6: Validate clan secrets/vars on Hetzner
    ↓
Story 1.7: Create GCP terraform + host config
    ↓
Story 1.8: Deploy GCP VM ⚠️ HIGH RISK
    ↓
Story 1.9: Test multi-machine coordination
    ↓
Story 1.10: Monitor stability (1 week minimum) ⏱️
    ↓
Story 1.11: Document findings and patterns
    ↓
Story 1.12: Go/No-Go Decision → Phase 1 if GO
```

**Parallelization Opportunities:**

- Stories 1.1-1.3: Must be sequential (foundation)
- Stories 1.4-1.6: Must be sequential (Hetzner deployment)
- Stories 1.7-1.9: Must be sequential (GCP deployment, depends on Hetzner)
- Story 1.10: Blocks on calendar time (1 week), can do documentation in parallel
- Stories 1.11-1.12: Must be sequential (document then decide)

**Critical Path:** Stories 1.1 → 1.3 → 1.4 → 1.5 (Hetzner deploy) → 1.10 (stability) → 1.12 (decision)

**Optional Path:** Story 1.2 (dendritic) can be skipped without affecting infrastructure

**GCP Can Be Deferred:** If GCP too complex, can skip Stories 1.7-1.9 and proceed with Hetzner-only validation

---

## Epic 1 Timeline Estimates

### Conservative Estimate: 3 weeks

- Week 1: Stories 1.1-1.6 (setup + Hetzner deployment)
  - Days 1-2: Setup (1.1, 1.2 optional, 1.3)
  - Days 3-4: Hetzner config (1.4)
  - Day 5: Hetzner deploy (1.5) - expect troubleshooting
  - Days 6-7: Buffer + secrets validation (1.6)
- Week 2: Stories 1.7-1.9 (GCP deployment + coordination)
  - Days 1-2: GCP config (1.7)
  - Days 3-4: GCP deploy (1.8) - expect troubleshooting
  - Day 5: Multi-machine testing (1.9)
  - Days 6-7: Buffer + troubleshooting
- Week 3: Stories 1.10-1.12 (stability + decision)
  - Days 1-7: Stability monitoring (1.10)
  - Concurrent: Documentation (1.11)
  - Day 7: Go/No-Go decision (1.12)

### Aggressive Estimate: 10 days

- Days 1-2: Setup (1.1, 1.3, skip 1.2)
- Days 3-4: Hetzner deployment (1.4, 1.5, 1.6)
- Days 5-6: GCP deployment (1.7, 1.8, 1.9)
- Days 7-9: Stability monitoring (1.10) + documentation (1.11)
- Day 10: Decision (1.12)

### Realistic Estimate: 2 weeks

- Week 1: Stories 1.1-1.6 (Hetzner) + start GCP
- Week 2: Complete GCP (1.7-1.9) + stability (1.10-1.12)

**Factors:**

- Terraform/terranix learning curve (if unfamiliar)
- Cloud provider API surprises (especially GCP)
- Troubleshooting deployment issues (LUKS, networking)
- Stability monitoring requires calendar time (1 week minimum)
- Documentation quality vs speed tradeoff

**Cost During Epic 1:**

- Hetzner CX22/CX32: ~€5-8/month
- GCP e2-micro: ~$7-10/month
- Total: ~$15-20/month for 2-3 weeks = ~$10-15 total cost

---

## Comparison to Original Epic 1

### What Changed

**Scope:**

- Original: 6 stories, test-clan validation only, no real infrastructure
- Revised: 12 stories, real VM deployment (Hetzner + GCP), infrastructure-first

**Focus:**

- Original: Validate dendritic + clan architectural combination
- Revised: Deploy infrastructure using proven clan-infra patterns, dendritic optional

**Timeline:**

- Original: 1 week
- Revised: 2-3 weeks (infrastructure deployment + stability)

**Risk:**

- Original: Low (test environment only, disposable)
- Revised: Medium-High (real infrastructure, costs money, operational risk)

**Value:**

- Original: Architectural validation, patterns for Phase 1
- Revised: Real infrastructure deployed, proven patterns, ready for darwin

### What Stayed the Same

- Still Phase 0 (before darwin migration)
- Still uses test-clan repository
- Still captures learnings for future phases
- Still has go/no-go decision gate
- Still validates clan functionality
- Still includes stability monitoring

### Strategic Rationale for Changes

**Why infrastructure-first:**

1. **clan-infra proves it works**: Terraform/terranix + clan is production-proven (10+ VMs)
2. **Faster to value**: Real VMs deployed in Phase 0 instead of waiting for Phase 1
3. **Progressive validation**: Hetzner (proven) → GCP (new) → stability before darwin
4. **Dendritic is optimization**: Getting infrastructure working is more important than architectural purity
5. **Brownfield pragmatism**: Follow proven patterns (clan-infra) over theoretical purity (dendritic)

**Why dendritic optional:**

1. **Not required for success**: clan-infra works great without dendritic
2. **Conflicts possible**: specialArgs vs pure dendritic pattern
3. **Secondary goal**: Infrastructure deployment is primary, dendritic is enhancement
4. **Can revisit**: After infrastructure stable, can explore dendritic optimization

**Why Hetzner + GCP:**

1. **Hetzner proven**: clan-infra uses Hetzner, established pattern
2. **GCP learning**: New cloud provider, validates multi-cloud patterns
3. **Progressive risk**: Hetzner first (safe), GCP second (experimental)
4. **Multi-cloud coordination**: Validates clan inventory across cloud providers
5. **GCP can be dropped**: If too complex, Hetzner-only is acceptable

---

## Story Effort Summary

| Story | Title | Effort | Risk |
|-------|-------|--------|------|
| 1.1 | Setup test-clan + terraform/terranix | 2-4h | Low |
| 1.2 | [OPTIONAL] Dendritic pattern | 2-4h | Low |
| 1.3 | Configure clan inventory | 2-4h | Low |
| 1.4 | Create Hetzner terraform + config | 4-6h | Medium |
| 1.5 | Deploy Hetzner VM | 4-8h | High |
| 1.6 | Validate clan secrets/vars | 2-4h | Low |
| 1.7 | Create GCP terraform + config | 4-6h | Medium-High |
| 1.8 | Deploy GCP VM | 6-8h | High |
| 1.9 | Test multi-machine coordination | 2-4h | Medium |
| 1.10 | Monitor stability (1 week) | 1 week | Low |
| 1.11 | Document findings | 2-4h | Low |
| 1.12 | Go/No-Go decision | 1-2h | Low |

**Total Development Hours:** 30-53 hours (excluding 1-week stability monitoring)

**Total Calendar Time:** 2-3 weeks (including stability monitoring)

---

## Risk Assessment

### High Risk Stories

**Story 1.5: Deploy Hetzner VM**

- First real infrastructure deployment
- Terraform apply is irreversible (costs money)
- LUKS encryption adds complexity
- Networking configuration critical
- Mitigation: Follow clan-infra pattern exactly, test in small VM size first

**Story 1.8: Deploy GCP VM**

- New cloud provider (GCP)
- GCP networking more complex (VPC, firewall rules)
- Cost uncertainty (free tier vs paid)
- May have GCP-specific issues
- Mitigation: Research thoroughly, use smallest VM size, can skip if too complex

### Medium Risk Stories

**Story 1.4: Create Hetzner terraform + config**

- First time writing terraform configuration
- Terranix Nix DSL learning curve
- Disko LUKS configuration complexity
- Mitigation: Copy clan-infra patterns, read terranix docs

**Story 1.7: Create GCP terraform + config**

- GCP provider unfamiliar
- VPC networking required
- Boot disk requirements may differ
- Mitigation: Research GCP + Nix/NixOS examples, adapt Hetzner patterns

**Story 1.9: Test multi-machine coordination**

- Depends on both VMs working
- Zerotier mesh across clouds
- Latency/reliability unknowns
- Mitigation: If issues, simplify to Hetzner-only

### Low Risk Stories

- Stories 1.1, 1.2, 1.3: Configuration only, no deployment
- Story 1.6: Validation only, Hetzner already working
- Stories 1.10, 1.11, 1.12: Documentation and monitoring

### Risk Mitigation Strategies

1. **Progressive deployment**: Hetzner first (proven), GCP second (experimental)
2. **Small VM sizes**: Use cheapest/smallest VMs for testing (CX22, e2-micro)
3. **Rollback plan**: Can destroy and recreate from configuration (terraform destroy)
4. **Copy proven patterns**: Follow clan-infra exactly for Hetzner/Vultr patterns
5. **Optional GCP**: Can skip Stories 1.7-1.9 if GCP too complex, Hetzner-only sufficient
6. **Optional dendritic**: Can skip Story 1.2 if conflicts, vanilla clan pattern proven

---

## Success Criteria for Epic 1 (Revised)

**Minimum Success (GO Decision):**

- Hetzner VM deployed successfully (Story 1.5 ✓)
- 1 week stability achieved (Story 1.10 ✓)
- Clan secrets/vars working (Story 1.6 ✓)
- Terraform/terranix patterns documented (Story 1.11 ✓)
- Cost acceptable (~€5-8/month Hetzner)
- Patterns reusable for Phase 1 cinnabar

**Optimal Success (Strong GO Decision):**

- Both Hetzner + GCP deployed (Stories 1.5 + 1.8 ✓)
- Multi-machine coordination working (Story 1.9 ✓)
- 1 week stability both VMs (Story 1.10 ✓)
- Multi-cloud patterns documented (Story 1.11 ✓)
- Cost acceptable (~$15-20/month total)
- High confidence for Phase 1

**Acceptable Compromises:**

- Dendritic pattern skipped (Story 1.2 optional)
- GCP deferred to post-Phase 0 (Stories 1.7-1.9 skipped, Hetzner-only)
- Stability < 1 week but > 5 days (if no issues discovered)
- Using vanilla clan + flake-parts pattern (proven in clan-infra)

**NO-GO Triggers:**

- Hetzner deployment fails with unresolved blockers
- Stability issues (crashes, service failures, networking unreliable)
- Excessive cost (> €20/month for test VMs)
- Terraform/terranix patterns not reusable
- Clan vars/secrets not working reliably

---

## Next Steps After GO Decision

**Immediate (Phase 1 - Week 4):**

1. Apply patterns to nix-config repository on clan branch
2. Create cinnabar host configuration (production Hetzner VPS)
3. Deploy cinnabar using proven terraform/terranix + clan patterns
4. Validate cinnabar stability (1-2 weeks) before darwin migration

**Test VMs Disposition:**

- **Option A**: Destroy test VMs to save costs (~$15-20/month savings)
- **Option B**: Keep test VMs for experimentation (darwin patterns, new services)
- **Option C**: Repurpose test VMs for CI/monitoring roles

**Documentation Handoff:**

- DEPLOYMENT-PATTERNS.md → reference for Phase 1 cinnabar
- INTEGRATION-FINDINGS.md → architectural decisions
- SECRETS-MANAGEMENT.md → clan vars workflow for all machines

---

## Appendix: clan-infra Pattern Reference

### Key Learnings from clan-infra

**Terranix Integration:**

```nix
# From clan-infra/machines/flake-module.nix
perSystem = { pkgs, inputs', ... }: {
  terranix = {
    terranixConfigurations.terraform = {
      workdir = "terraform";
      modules = [
        self.modules.terranix.base
        self.modules.terranix.vultr
        ./jitsi01/terraform-configuration.nix
        # ... more machines
      ];
      terraformWrapper.package = pkgs.opentofu.withPlugins (p: [ ... ]);
      terraformWrapper.prefixText = ''
        TF_VAR_passphrase=$(clan secrets get tf-passphrase)
        export TF_VAR_passphrase
      '';
    };
  };
};
```

**VM Terraform Configuration Pattern:**

```nix
# From clan-infra/machines/jitsi01/terraform-configuration.nix
resource.vultr_instance.jitsi01 = {
  label = "jitsi01";
  region = "sgp";
  plan = "vc2-2c-4gb";
  os_id = 2136; # Debian 12
  enable_ipv6 = true;
  ssh_key_ids = [
    (config.resource.vultr_ssh_key.terraform "id")
  ];
};

resource.null_resource.install-jitsi01 = {
  provisioner.local-exec = {
    command = "clan machines install jitsi01 --target-host root@${...} -i '${...}' --yes";
  };
};
```

**Clan Inventory Pattern:**

```nix
# From clan-infra/machines/flake-module.nix
clan = {
  meta.name = "infra";
  specialArgs = { inherit self; }; # Minimal specialArgs!
  inventory.machines.build02.machineClass = "darwin";
  inventory.instances = {
    zerotier-claninfra = {
      module = { name = "zerotier"; input = "clan-core"; };
      roles.controller.machines.web01 = {};
      roles.peer.tags.all = {};
    };
    sshd-clan = {
      module = { name = "sshd"; input = "clan-core"; };
      roles.server.tags.all = {};
      roles.client.tags.all = {};
    };
  };
};
```

**Key Observations:**

1. **Minimal specialArgs**: Only `{ inherit self; }` - not extensive pass-through
2. **Terranix at perSystem level**: Not in flake-parts modules, in perSystem output
3. **Per-machine terraform configs**: Each machine has terraform-configuration.nix in its directory
4. **Terraform wrapper**: Fetches secrets via `clan secrets get` in prefixText
5. **null_resource provisioner**: Calls `clan machines install` after VM provisioned
6. **Tag-based targeting**: `roles.peer.tags.all` targets all machines with tag

**This is the proven pattern to follow for Stories 1.4-1.5 (Hetzner) and 1.7-1.8 (GCP).**

---

## Conclusion

This restructured Epic 1 prioritizes **infrastructure deployment** over **architectural purity**, following clan-infra's proven terraform/terranix + clan patterns while keeping dendritic optimization as optional.

**Key Benefits:**

1. Real VMs deployed in Phase 0 (faster to value)
2. Proven patterns from clan-infra (lower risk)
3. Progressive validation: Hetzner → GCP → stability
4. Multi-cloud experience before darwin migration
5. Infrastructure-first, optimization second (pragmatic brownfield approach)

**Key Risks:**

1. Infrastructure deployment costs money (~$15-20/month)
2. GCP may be too complex (can defer if needed)
3. More stories = longer timeline (2-3 weeks vs 1 week)
4. Operational risk from real infrastructure

**Recommendation:**

Proceed with restructured Epic 1, with explicit decision points:
- Story 1.2 (dendritic): Skip if conflicts
- Stories 1.7-1.9 (GCP): Skip if too complex, Hetzner-only sufficient
- Story 1.12 (go/no-go): Requires 1 week stability minimum

**Expected Outcome:**

GO decision with Hetzner VM stable, patterns documented, ready for Phase 1 cinnabar production deployment.
GCP may be deferred to post-Phase 0 experimentation if complexity exceeds value.
