---
title: "Story 1.10: Monitor infrastructure stability and extract deployment patterns"
---

Status: drafted

## Story

As a system administrator,
I want to monitor both VMs for stability over 1 week minimum,
So that I can validate the infrastructure is production-ready before darwin migration.

## Context

Story 1.10 provides the stability gate for Epic 1 - ensuring infrastructure is reliable before proceeding to Phase 1 (cinnabar production deployment) and Phase 2+ (darwin migration).

**Stability Gate**: 1 week minimum monitoring is non-negotiable.
This proves the infrastructure can run reliably without manual intervention and validates patterns for production use.

**Pattern Extraction**: During stability monitoring, document deployment patterns, troubleshooting notes, and operational learnings that will guide Phase 1 (cinnabar) and beyond.

## Acceptance Criteria

1. 1-week stability monitoring completed (minimum 7 days):
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
3. Cost tracking completed: actual monthly costs calculated for Hetzner + GCP
4. Performance baseline established:
   - Build times (nixos-rebuild)
   - Deployment times (terraform + clan install)
   - Network latency (zerotier mesh)
5. Patterns validated as reusable for Phase 1 (cinnabar) deployment
6. Issues log maintained: any problems discovered, workarounds applied
7. Rollback procedure tested: can destroy and recreate infrastructure from configuration

## Tasks / Subtasks

- [ ] Set up 1-week stability monitoring schedule (AC: #1)
  - [ ] Define monitoring schedule: daily checks at consistent time
  - [ ] Create checklist for each monitoring session:
    - SSH access to Hetzner VM
    - SSH access to GCP VM
    - Zerotier mesh connectivity test
    - System log review for errors
    - Service status checks
    - Uptime verification
  - [ ] Set calendar reminders for 7 days

- [ ] Day 1 stability check
  - [ ] Test SSH access: Hetzner + GCP (both direct and via zerotier)
  - [ ] Test zerotier mesh: bidirectional ping
  - [ ] Review system logs: `journalctl -p err --since "24 hours ago"`
  - [ ] Check service status: zerotier, sshd, emergency-access
  - [ ] Record uptime: `uptime`
  - [ ] Document any issues found

- [ ] Day 2-6 stability checks (repeat daily)
  - [ ] Perform same checks as Day 1
  - [ ] Record any changes in behavior
  - [ ] Document any errors or warnings
  - [ ] Track uptime trends
  - [ ] Note any interventions required

- [ ] Day 7 final stability check
  - [ ] Perform comprehensive check (all Day 1 items)
  - [ ] Calculate total uptime percentage
  - [ ] Review complete week of logs for patterns
  - [ ] Summarize stability findings
  - [ ] Determine if stability gate passed (>99% uptime, no critical issues)

- [ ] Document terraform/terranix patterns (AC: #2)
  - [ ] Create docs/notes/clan/DEPLOYMENT-PATTERNS.md
  - [ ] Document Hetzner terraform configuration:
    - hcloud provider setup
    - Server resource configuration
    - SSH key management
    - null_resource provisioner pattern
  - [ ] Document GCP terraform configuration:
    - Google provider setup
    - VPC network configuration
    - Firewall rules
    - Compute instance configuration
    - Differences from Hetzner pattern
  - [ ] Include code examples from modules/terranix/

- [ ] Document clan inventory patterns (AC: #2)
  - [ ] Document machine definitions:
    - Machine tags (nixos, cloud, hetzner/gcp)
    - Machine classes (nixos)
    - Host configurations
  - [ ] Document service instances:
    - emergency-access pattern
    - sshd-clan server/client roles
    - zerotier controller/peer roles
    - users-root pattern
  - [ ] Include code examples from modules/flake-parts/clan.nix

- [ ] Document disko LUKS patterns (AC: #2)
  - [ ] Document partition layout:
    - EFI boot partition
    - LUKS encrypted root
    - Filesystem choices (ext4 vs btrfs)
  - [ ] Document LUKS setup process
  - [ ] Include code examples from modules/hosts/*/disko.nix
  - [ ] Note any cloud-specific differences (GCP vs Hetzner)

- [ ] Document vars generation patterns (AC: #2)
  - [ ] Document vars generation workflow:
    - `clan vars generate <machine>`
    - Secrets vs facts distinction
    - Age encryption setup
  - [ ] Document vars deployment:
    - /run/secrets/ structure
    - Permissions and ownership
    - systemd sops-nix service
  - [ ] Include troubleshooting steps for common issues

- [ ] Document multi-cloud zerotier setup (AC: #2)
  - [ ] Document controller setup (Hetzner):
    - Controller role configuration
    - Network ID generation
    - Always-on requirement
  - [ ] Document peer setup (GCP):
    - Peer role configuration
    - Network ID consumption
    - Connection process
  - [ ] Document mesh validation process

- [ ] Document troubleshooting notes (AC: #2)
  - [ ] Compile all issues encountered during Epic 1
  - [ ] For each issue:
    - Describe problem
    - Root cause identified
    - Solution or workaround applied
    - Prevention strategy for future
  - [ ] Organize by category (terraform, clan install, networking, etc.)

- [ ] Track and document costs (AC: #3)
  - [ ] Check Hetzner billing: actual CX22 cost
  - [ ] Check GCP billing: actual e2-micro cost
  - [ ] Calculate total monthly cost (Hetzner + GCP)
  - [ ] Project Phase 1 costs (cinnabar only, no GCP)
  - [ ] Document cost optimization opportunities

- [ ] Establish performance baselines (AC: #4)
  - [ ] Measure build times:
    - `nixos-rebuild switch` on Hetzner
    - `nixos-rebuild switch` on GCP
    - Average and compare
  - [ ] Measure deployment times:
    - Terraform apply (VM provisioning)
    - Clan install (NixOS installation)
    - Total time to operational
  - [ ] Measure network latency:
    - Hetzner to GCP zerotier ping times
    - Average, min, max latency
  - [ ] Document baselines for future comparison

- [ ] Validate patterns for Phase 1 reuse (AC: #5)
  - [ ] Review all documented patterns
  - [ ] For each pattern, assess:
    - Reusable as-is for cinnabar?
    - Needs adaptation for production?
    - Confidence level (high/medium/low)?
  - [ ] Document recommended patterns for Phase 1
  - [ ] Note any patterns to avoid or revise

- [ ] Maintain issues log (AC: #6)
  - [ ] Create ISSUES-LOG.md tracking all problems
  - [ ] For each issue during stability monitoring:
    - Date discovered
    - Description
    - Severity (critical/major/minor)
    - Resolution status
    - Workaround applied
  - [ ] Summarize issues at end of week

- [ ] Test rollback procedure (AC: #7)
  - [ ] Document current infrastructure state:
    - VM IPs, zerotier IPs
    - Configuration commit hash
    - Vars state
  - [ ] Destroy infrastructure: `nix run .#terranix.terraform -- destroy`
  - [ ] Confirm VMs destroyed in cloud provider consoles
  - [ ] Recreate infrastructure:
    - `terraform apply`
    - `clan vars generate` (may reuse existing)
    - `clan machines install`
  - [ ] Verify infrastructure restored successfully
  - [ ] Document rollback procedure and timing
  - [ ] Decide whether to keep VMs running or destroyed after test

## Dev Notes

### Monitoring Schedule

**Daily check timing:**
- Consistent time each day (e.g., 10 AM local time)
- ~15-30 minutes per check
- Total: 7 days × 30 min = ~3.5 hours spread over week

**Monitoring checklist (per day):**
1. SSH access test (Hetzner, GCP, via zerotier)
2. Zerotier mesh connectivity test
3. System logs review (`journalctl -p err`)
4. Service status checks
5. Uptime recording
6. Issue documentation

### Stability Gate Criteria

**PASS criteria:**
- Uptime > 99% (allows ~1.7 hours downtime over week)
- No critical service failures
- No unexpected reboots
- Zerotier mesh stable throughout week
- SSH access reliable

**FAIL criteria:**
- Uptime < 99%
- Critical service failures requiring intervention
- Frequent disconnections or instability
- Issues preventing reliable operation

If stability gate fails, investigate issues and extend monitoring until stability achieved.

### DEPLOYMENT-PATTERNS.md Structure

**Suggested sections:**
1. Terraform/Terranix Configuration
   - Hetzner patterns
   - GCP patterns
   - Provider configuration
   - null_resource provisioner pattern
2. Clan Inventory Patterns
   - Machine definitions
   - Service instances
   - Role targeting
3. Disko LUKS Patterns
   - Partition layouts
   - Encryption setup
   - Cloud-specific considerations
4. Vars Generation Patterns
   - Workflow
   - Secrets vs facts
   - Deployment mechanism
5. Multi-Cloud Zerotier Setup
   - Controller configuration
   - Peer configuration
   - Mesh validation
6. Troubleshooting Guide
   - Common issues
   - Solutions
   - Prevention strategies

### Cost Tracking

**Expected costs:**
- Hetzner CX22: ~€5.83/month
- GCP e2-micro: ~$7.11/month
- Total: ~$13-15/month

**Phase 1 projection:**
- Cinnabar only (Hetzner CX32 or similar): ~€8-12/month
- No GCP (unless decided otherwise)

### Performance Baselines

**Build times (expected):**
- Initial build: 10-30 minutes (downloading substitutes)
- Subsequent builds: 2-5 minutes (only changed packages)

**Deployment times (expected):**
- Terraform apply: 2-5 minutes
- Clan install: 10-30 minutes
- Total: 15-40 minutes

**Network latency (expected):**
- Hetzner ↔ GCP zerotier: 50-200ms (depends on regions)

### Rollback Testing

**Why test rollback:**
- Validates infrastructure is truly declarative
- Confirms terraform destroy is safe
- Proves can recreate from configuration
- Tests disaster recovery procedure

**Rollback timing:**
- Perform near end of stability monitoring (day 6-7)
- Allows final stability check after recreation
- Validates infrastructure reproducibility

### Solo Operator Workflow

This story is calendar time (1 week minimum) with periodic checks.
Not continuous work - can be done alongside other activities.
Expected total effort: 4-8 hours spread over 1 week (monitoring + documentation).

### Architectural Context

**Why 1-week stability gate:**
- Validates infrastructure reliable without manual intervention
- Catches intermittent issues not visible in short-term testing
- Builds confidence for production deployment (Phase 1)
- Industry standard for infrastructure validation

**Why pattern documentation critical:**
- Phase 1 (cinnabar) will reuse these patterns
- Phase 2+ (darwin migration) builds on this foundation
- Knowledge capture for future infrastructure decisions
- Troubleshooting reference for operations

### References

- [Source: docs/notes/development/epic-1-infrastructure-restructure-proposal.md#Story-1.10]
- [Industry: Infrastructure stability best practices]

### Expected Validation Points

After this story completes:
- 1-week stability validated (>99% uptime)
- Deployment patterns documented comprehensively
- Costs tracked and projected for Phase 1
- Performance baselines established
- Rollback procedure tested and documented
- Ready for Story 1.11 (integration findings)

**What Story 1.10 does NOT validate:**
- Long-term stability beyond 1 week (acceptable for Phase 0)
- Production-scale load or usage patterns
- Disaster recovery beyond rollback test

### Important Constraints

**1-week minimum is non-negotiable:**
- Cannot proceed to Phase 1 without stability validation
- Can extend beyond 1 week if issues discovered
- Stability gate must PASS before go/no-go decision (Story 1.12)

**Calendar time requirement:**
- Cannot compress 1 week into less time
- Periodic checks spread over full week
- Validates time-based stability patterns

**Zero-regression mandate does NOT apply**: Test infrastructure, stability validation phase.

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

<!-- Agent model will be recorded during implementation -->
