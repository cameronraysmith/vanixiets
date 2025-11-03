---
title: "Story 1.11: Document integration findings and architectural decisions"
---

Status: drafted

## Story

As a system administrator,
I want to document all integration findings and architectural decisions from Phase 0,
So that I have comprehensive reference for Phase 1 and beyond.

## Context

Story 1.11 captures the knowledge gained from Epic 1 deployment experience and translates it into actionable documentation for Phase 1 (cinnabar production deployment) and Phase 2+ (darwin migration).

**Knowledge Capture**: This story documents not just what was done, but why decisions were made, what worked well, what was challenging, and what should be done differently.

**Foundation for Future Phases**: The findings documented here directly inform Phase 1 architecture, deployment strategy, and operational procedures.

## Acceptance Criteria

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
4. Recommendations for Phase 1 cinnabar deployment documented
5. Known limitations documented (GCP complexity, cost, alternatives)

## Tasks / Subtasks

- [ ] Document terraform/terranix + clan integration (AC: #1)
  - [ ] Create docs/notes/clan/INTEGRATION-FINDINGS.md
  - [ ] Document how terraform/terranix + clan work together:
    - Terraform provisions VMs (IaaS layer)
    - null_resource provisioner triggers clan install
    - Clan installs NixOS and manages configuration
    - Clean separation of concerns
  - [ ] Document gotchas:
    - Initial OS image doesn't matter (clan replaces)
    - SSH key management (terraform deploy key vs clan keys)
    - Timing: VM must be accessible before clan install
  - [ ] Document integration points:
    - Terraform output → clan install input (IP address)
    - Clan secrets → terraform variables (API tokens)
    - null_resource provisioner command format

- [ ] Document dendritic pattern evaluation (if applicable) (AC: #1)
  - [ ] If Story 1.2 was attempted:
    - Document what parts of dendritic pattern were adopted
    - Document what parts conflicted with clan or terranix
    - Document deviations from pure dendritic pattern
    - Assess whether dendritic added value or complexity
  - [ ] If Story 1.2 was skipped:
    - Document decision to use vanilla clan + flake-parts
    - Note that dendritic pattern can be revisited later
    - Confirm vanilla pattern sufficient for infrastructure

- [ ] Document acceptable pattern deviations (AC: #1)
  - [ ] specialArgs usage:
    - Minimal specialArgs (only `self` if needed)
    - Rationale: Follow clan-infra proven pattern
    - Acceptable deviation from pure dendritic (no specialArgs)
  - [ ] Module organization:
    - modules/terranix/ for infrastructure
    - modules/hosts/ for machine configs
    - modules/flake-parts/ for flake-level config
    - modules/base/ for shared nixos modules
  - [ ] Document why deviations acceptable for brownfield project

- [ ] Document Hetzner deployment experience (AC: #1)
  - [ ] What was easy:
    - Simple networking (no VPC complexity)
    - Clear API and documentation
    - Fast provisioning (2-5 minutes)
    - Adapting from clan-infra Vultr pattern
  - [ ] What was hard:
    - LUKS encryption setup (if issues encountered)
    - Disko configuration (if issues encountered)
    - Any Hetzner-specific quirks
  - [ ] Surprises:
    - Anything unexpected during deployment
    - Performance better or worse than expected
    - Cost variations from estimates
  - [ ] Confidence level: Proven (Hetzner deployment successful)

- [ ] Document GCP deployment experience (AC: #1)
  - [ ] Comparison to Hetzner:
    - Networking more complex (VPC, firewall rules)
    - Provisioning slower (if observed)
    - API more complex (service accounts, project IDs)
    - Boot disk requirements different (if encountered)
  - [ ] Challenges encountered:
    - VPC configuration complexity
    - Firewall rule setup
    - Service account permissions
    - GCP-specific disko requirements (if any)
    - Any blockers or significant troubleshooting
  - [ ] Assessment:
    - Was GCP worth the complexity?
    - Would recommend for production infrastructure?
    - Alternative approach if redoing GCP?
  - [ ] Confidence level: Needs-testing / Uncertain (depending on experience)

- [ ] Document multi-cloud coordination findings (AC: #1)
  - [ ] What works well:
    - Clan inventory abstracts cloud provider differences
    - Service instances coordinate across clouds
    - Zerotier mesh enables cross-cloud connectivity
    - Configuration updates apply consistently
  - [ ] What doesn't work or is challenging:
    - Network latency varies by region
    - Cloud provider outages affect coordination
    - Cost increases with multiple providers
    - Complexity increases with each provider
  - [ ] Recommendations:
    - When multi-cloud makes sense (redundancy, capabilities)
    - When single-cloud is better (simplicity, cost)
    - Phase 1 recommendation (Hetzner-only or multi-cloud?)

- [ ] Document zerotier mesh networking (AC: #1)
  - [ ] Latency measurements:
    - Hetzner ↔ GCP ping times (actual observed)
    - Acceptable for coordination? (<200ms preferred)
    - Impact on performance or operations
  - [ ] Reliability observations:
    - Any disconnections during monitoring?
    - Reconnection time if disconnected
    - Stability over 1-week monitoring period
  - [ ] Advantages:
    - Always-on VPN mesh
    - No port forwarding or NAT traversal
    - Simplifies cross-cloud connectivity
    - Enables SSH via private IPs
  - [ ] Limitations:
    - Additional moving part (controller dependency)
    - Network latency overhead
    - Configuration complexity
    - Zerotier service dependency
  - [ ] Confidence level: Proven (zerotier mesh successful)

- [ ] Document architectural decisions (AC: #2)
  - [ ] Create docs/notes/clan/ARCHITECTURAL-DECISIONS.md
  - [ ] Why terraform/terranix:
    - Declarative infrastructure provisioning
    - Proven in clan-infra at scale
    - Nix DSL via terranix (type-safe, evaluated)
    - Alternative considered: Manual provisioning (rejected - not reproducible)
  - [ ] Why LUKS encryption:
    - Security requirement for cloud VMs
    - Protects data at rest
    - Industry best practice
    - Non-negotiable for production infrastructure
  - [ ] Why zerotier mesh:
    - Always-on coordination between machines
    - VPN mesh without port forwarding
    - Enables darwin ↔ cloud VM connectivity
    - Alternative considered: Tailscale (zerotier chosen for clan-infra proven pattern)
  - [ ] Clan inventory patterns:
    - Tag-based targeting (tags."all")
    - Role-based coordination (controller/peer, server/client)
    - Machine classes (nixos, darwin)
    - Service instances for coordination
  - [ ] Service instance patterns:
    - emergency-access: Root recovery on all machines
    - sshd-clan: SSH coordination (server + client)
    - zerotier: VPN mesh (controller + peers)
    - users-root: Root user management
  - [ ] Secrets management strategy:
    - Clan vars for machine-specific secrets
    - Age encryption via sops-nix
    - Secrets vs facts distinction
    - Alternative considered: Plain sops-nix (clan vars adds conventions, preferred)

- [ ] Assess confidence levels for each pattern (AC: #3)
  - [ ] For each documented pattern, assign confidence:
    - **Proven**: Successfully deployed and stable for 1+ week
      - Hetzner deployment
      - Terraform/terranix + clan integration
      - Zerotier mesh (if stable)
      - Clan vars deployment
    - **Needs-testing**: Deployed successfully but limited validation
      - GCP deployment (if completed)
      - Multi-cloud coordination (if completed)
      - Service instance coordination
    - **Uncertain**: Not fully validated or encountered issues
      - GCP deployment (if problematic)
      - Dendritic pattern (if skipped or incomplete)
      - Specific patterns with unresolved issues
  - [ ] Document rationale for each confidence level
  - [ ] Identify patterns needing more validation in Phase 1

- [ ] Create Phase 1 recommendations (AC: #4)
  - [ ] Recommended approach for cinnabar deployment:
    - Use proven Hetzner terraform pattern
    - Apply clan inventory patterns from Phase 0
    - Use LUKS encryption (non-negotiable)
    - Set up zerotier mesh (cinnabar as controller or peer?)
    - Skip GCP initially (if problematic)
  - [ ] Configuration recommendations:
    - VM size for cinnabar (CX32 or larger for production)
    - Backup strategy (not covered in Phase 0, need to add)
    - Monitoring strategy (not covered in Phase 0, need to add)
  - [ ] Timeline estimates:
    - Cinnabar terraform configuration: 2-4 hours (reuse Hetzner pattern)
    - Cinnabar deployment: 1-2 hours (proven process)
    - Cinnabar stability validation: 1-2 weeks before darwin migration
  - [ ] Risk mitigation:
    - Test rollback procedure before production data
    - Have backup of existing cinnabar (if applicable)
    - Gradual cutover strategy

- [ ] Document known limitations (AC: #5)
  - [ ] GCP complexity:
    - VPC networking more complex than Hetzner
    - Service account permissions learning curve
    - Higher operational complexity
    - Recommendation: Defer unless multi-cloud required
  - [ ] Cost considerations:
    - Multi-cloud increases monthly costs (~$13-15/month for 2 VMs)
    - Hetzner-only more economical (~€5-12/month)
    - Cost/benefit analysis for production infrastructure
  - [ ] Technical limitations:
    - Zerotier adds latency overhead
    - Multi-cloud increases coordination complexity
    - Cloud provider outages affect availability
  - [ ] Operational limitations:
    - Solo operator limits parallelization
    - Terraform state management (not covered in Phase 0)
    - Backup and disaster recovery (not implemented in Phase 0)
  - [ ] Alternatives:
    - Single-cloud (Hetzner-only) for simplicity
    - Different VPN solution (Tailscale, Wireguard)
    - Different infrastructure tool (NixOps, Colmena)
    - Manual provisioning with automation scripts

## Dev Notes

### Documentation Goals

**Primary goals:**
1. Capture knowledge for Phase 1 (cinnabar) deployment
2. Document lessons learned for Phase 2+ (darwin migration)
3. Provide troubleshooting reference for future operations
4. Enable informed architectural decisions going forward

**Target audience:**
- Future self (in Phase 1, Phase 2+)
- Other operators (if project scales)
- Documentation should be actionable and specific

### Integration Findings Structure

**Suggested outline:**
1. Executive Summary (key findings, confidence levels)
2. Terraform/Terranix + Clan Integration
3. Dendritic Pattern Evaluation (if applicable)
4. Hetzner Deployment Experience
5. GCP Deployment Experience (if completed)
6. Multi-Cloud Coordination Findings
7. Zerotier Mesh Networking
8. Patterns and Deviations
9. Recommendations and Next Steps

### Architectural Decisions Structure

**Suggested outline:**
1. Overview (scope of decisions, context)
2. Infrastructure Provisioning (terraform/terranix)
3. Security (LUKS encryption)
4. Networking (zerotier mesh)
5. Configuration Management (clan inventory)
6. Service Coordination (service instances)
7. Secrets Management (clan vars, sops-nix)
8. Alternatives Considered
9. Future Decisions Needed

### Confidence Levels Definition

**Proven:**
- Deployed successfully
- Stable for 1+ week
- No unresolved issues
- Ready for production use (with appropriate testing)

**Needs-testing:**
- Deployed successfully
- Limited stability validation
- Minor issues encountered
- Requires more validation before production

**Uncertain:**
- Not fully validated
- Significant issues encountered
- Not recommended for production without further work
- Alternative approaches should be considered

### Solo Operator Workflow

This story is documentation focused - low operational risk.
Expected execution time: 2-4 hours (writing, organizing, reviewing).
Should be done while Epic 1 experience is fresh (immediately after Story 1.10).

### Architectural Context

**Why documentation critical:**
- Epic 1 was exploration and learning
- Phase 1 is production deployment (cinnabar)
- Cannot afford to repeat mistakes or rediscover solutions
- Documented knowledge is foundation for all future phases

**Comparison to typical development:**
- Typical: Architecture docs created before implementation
- This project: Architecture validated during implementation (Phase 0)
- Documentation captures actual experience, not theoretical design

### References

- [Source: docs/notes/development/epic-1-infrastructure-restructure-proposal.md#Story-1.11]
- [All previous stories in Epic 1 for content]

### Expected Validation Points

After this story completes:
- Integration findings comprehensively documented
- Architectural decisions recorded with rationale
- Confidence levels assessed for all patterns
- Phase 1 recommendations clear and actionable
- Known limitations documented for risk management
- Ready for Story 1.12 (go/no-go decision)

**What Story 1.11 does NOT cover:**
- Go/no-go decision (Story 1.12)
- Phase 1 architecture workflow (deferred until after Phase 0)
- Detailed Phase 1 implementation plan (comes after go decision)

### Important Constraints

**Documentation must be honest:**
- Document what didn't work, not just successes
- Acknowledge limitations and uncertainties
- Provide realistic assessments, not aspirational

**Documentation should be actionable:**
- Specific recommendations, not vague guidance
- Include code examples where helpful
- Reference specific files and configurations

**Zero-regression mandate does NOT apply**: Documentation phase, no infrastructure changes.

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

<!-- Agent model will be recorded during implementation -->
