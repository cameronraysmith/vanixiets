---
title: Risks catalog
sidebar:
  order: 8
---

This document catalogs migration risks with likelihood, impact, risk factors, and mitigation strategies.

## Overview

This document catalogs risks from the migration from nixos-unified to dendritic + clan architecture completed in November 2024.
Each risk includes original assessment, migration timeline relevance, mitigation strategies, and final status.

The migration successfully addressed all critical risks through initial validation, incremental deployment across 8 machines, and comprehensive testing.
These risks are now primarily historical, documenting how challenges were anticipated and mitigated during the architectural transition.

## R-001: Dendritic + clan integration complexity

### Description

No production examples exist of dendritic flake-parts combined with clan, creating uncertainty about integration challenges and edge cases.

### Risk factors

- Novel architecture combination (pioneering integration)
- No reference implementations to follow
- Potential undiscovered incompatibilities
- Learning curve for both patterns simultaneously
- Documentation gaps for combined usage

### Likelihood

**Medium** - While both technologies are mature independently, their integration is untested.

### Impact

**High** - Integration failures could block migration entirely or require significant rework.

### Migration timeline relevance

- Initial validation (primary impact - this phase exists to catch this risk)
- All subsequent phases depend on successful validation

### Mitigation strategies

**Initial validation environment**:
- Create test-clan/ workspace isolated from production
- Validate integration patterns before infrastructure investment
- Test all expected features (secrets, services, cross-platform modules)
- Document integration approach comprehensively
- Identify and resolve issues before VPS deployment

**Incremental validation**:
- Test one feature at a time
- Build confidence through small successes
- Document discovered patterns immediately
- Create reference examples for future use

**De-risk before commitment**:
- Initial validation has no infrastructure costs
- Can abandon or redesign without losing production capability
- Preserves ability to stay on nixos-unified if integration fails

**Fallback position**:
- nixos-unified remains operational throughout validation
- Can abort migration if fundamental incompatibilities found
- Alternative: use clan without dendritic, or dendritic without clan

### Status

**Mitigated** - Initial validation completed (November 2024).
Integration patterns validated in test-clan workspace, comprehensive documentation created, and patterns successfully applied across 8-machine production fleet.

### References

- Phase 0 validation plan: docs/notes/clan/phase-0-validation.md
- [Project scope](../context/project-scope/) - De-risk rationale

## R-002: VPS infrastructure costs and management overhead

### Description

Deploying cinnabar VPS introduces ongoing costs and operational responsibilities not present in current darwin-only setup.

### Risk factors

- Monthly Hetzner costs (small but permanent)
- Server maintenance responsibilities
- Security update cadence
- Monitoring requirements
- Backup strategy needs
- Additional attack surface

### Likelihood

**High** - VPS deployment is certain if migration proceeds.

### Impact

**Medium** - Manageable costs and effort, but permanent ongoing commitment.

### Migration timeline relevance

- VPS deployment phase (introduces risk)
- All subsequent phases depend on VPS stability
- Long-term operational phase after migration

### Mitigation strategies

**Cost management**:
- Choose smallest viable VPS instance
- Document baseline costs in project notes
- Evaluate cost vs. benefit periodically
- Plan for cost increase if usage grows

**Operational efficiency**:
- Automate security updates via NixOS configuration
- Use unattended-upgrades for critical security patches
- Monitoring via simple systemd-based health checks
- Backup strategy: automated via NixOS modules

**Security hardening**:
- Minimal service exposure (SSH, zerotier only)
- SSH key authentication only (no passwords)
- Firewall configured via NixOS (declarative)
- Regular security audit via nix flake check + statix

**Effort bounds**:
- Target: <2 hours/month maintenance
- Automate everything possible
- Document procedures for rare operations
- Keep configuration simple

**Exit strategy**:
- Document VPS teardown procedure
- Zerotier can migrate to different controller if needed
- No vendor lock-in (Hetzner-agnostic configuration)

### Status

**Mitigated** - VPS infrastructure deployed and operational (November 2024).
Cinnabar VPS successfully deployed on Hetzner, zerotier controller operational, costs and management overhead within acceptable bounds.

### References

- Phase 1 VPS deployment: docs/notes/clan/phase-1-vps.md
- [Goals](../context/goals-and-objectives/) - G-B02: Reasonable time and cost investment

## R-003: Darwin host migration breaking daily workflows

### Description

Configuration changes during migration could break critical development workflows, impacting productivity.

### Risk factors

- Complex host configurations (accumulated over time)
- Undocumented dependencies between components
- Subtle behavior changes between architectures
- Testing limitations (can't fully test until activation)
- User muscle memory and expectations

### Likelihood

**High** - Some workflow disruption almost certain during migration.

### Impact

**Variable by host**:
- blackphos, rosegold, argentum: **Medium** (secondary workstations, can tolerate issues)
- stibnite: **High** (primary workstation, productivity-critical)

### Migration timeline relevance

- Blackphos migration (first darwin, highest migration risk)
- Rosegold migration (validation of pattern reusability)
- Argentum migration (final validation before primary)
- Stibnite migration (highest impact if issues occur)

### Mitigation strategies

**Pre-migration validation**:
- Comprehensive dry-run review
- Compare current vs new configuration outputs
- Test in guest user account first (if feasible)
- Document rollback procedure per host

**Migration order optimization**:
- blackphos first (secondary workstation, lowest impact)
- Validate pattern works before next host
- stibnite last (maximize learning before highest-risk host)
- 1-2 week stability validation between hosts

**Workflow preservation checklist**:
- Development tools (editors, shells, languages)
- SSH access and configurations
- Git and version control workflows
- Network connectivity (wifi, VPN)
- Homebrew applications
- Keyboard shortcuts and system preferences

**Rapid rollback capability**:
- Test rollback before migration (dry-run)
- Keep previous generation accessible
- Document exact rollback commands per host
- Time allocation for troubleshooting

**Incremental migration within host**:
- Convert core modules first (shell, dev tools)
- Keep optional features in nixos-unified initially
- Migrate additional features after stability confirmed
- Progressive conversion reduces risk

### Status

**Mitigated** - All darwin hosts successfully migrated (November 2024).
Blackphos, rosegold, argentum, and stibnite all migrated to dendritic + clan architecture with minimal workflow disruption.
Incremental migration strategy and rollback procedures validated across entire fleet.

### References

- Migration assessment: docs/notes/clan/migration-assessment.md
- [Usage model](/development/requirements/usage-model/) - UC-007: Migration use case

## R-004: Primary workstation (stibnite) migration risk

### Description

Migration of stibnite (primary workstation) has highest impact if problems occur, potentially blocking all work.

### Risk factors

- Most complex configuration of all hosts
- Daily productivity dependency
- Highest cognitive load (most familiarity required)
- Most accumulated customizations
- Less tolerance for experimentation

### Likelihood

**Medium** - Previous migrations provide validation, but stibnite is most complex.

### Impact

**Critical** - Work disruption could be severe if migration fails or causes instability.

### Migration timeline relevance

- Stibnite migration (primary risk event)
- Post-migration stability monitoring

### Mitigation strategies

**Maximum preparation**:
- Wait until all other hosts migrated successfully
- Learn from issues encountered on earlier hosts
- Comprehensive testing on secondary hosts first
- Full backup before migration

**Timing strategy**:
- Choose low-pressure time window (not before deadline)
- Allocate full day for migration + troubleshooting
- Have backup device available (rosegold or blackphos)
- Don't migrate on Friday (weekend debugging less appealing)

**Incremental approach**:
- Migrate minimal configuration first
- Validate core workflows before adding features
- Keep optional features in nixos-unified initially
- Progressive addition of customizations

**Rollback readiness**:
- Test rollback procedure on secondary host first
- Document exact rollback commands
- Verify previous generation accessible and working
- Have git rollback procedure ready (checkout previous commit)

**Safety nets**:
- Keep secondary workstation (blackphos) fully operational
- SSH access to other hosts for remote work if needed
- Cloud-based development as emergency fallback
- Pair with time for recovery (not before critical deliverables)

**Success criteria before attempting**:
- All other darwin hosts migrated successfully
- All hosts stable 1-2 weeks post-migration
- No unresolved issues from earlier migrations
- Clear understanding of dendritic + clan patterns
- Rollback tested and verified

### Status

**Mitigated** - Stibnite successfully migrated (November 2024).
Migration completed as final phase with minimal disruption.
Prior validation on blackphos, rosegold, and argentum enabled confident migration of primary workstation.

### References

- [Project scope](../context/project-scope/) - Migration order rationale
- [Stakeholders](../context/stakeholders/) - Risk tolerance considerations

## R-005: Secrets migration from sops-nix to clan vars

### Description

Transitioning from manual sops-nix secrets to declarative clan vars generation could expose secrets or break services.

### Risk factors

- Two secrets management systems during migration
- Risk of secrets committed unencrypted
- Service downtime if secrets missing
- Generator script bugs
- Key rotation complexity
- Unclear migration path for certain secret types

### Likelihood

**Medium** - Careful execution can manage risk, but complexity is significant.

### Impact

**High** - Secret exposure is critical security issue; service failures impact functionality.

### Migration timeline relevance

- VPS deployment (first clan vars usage)
- Progressive secrets migration during host migrations
- Post-migration: Hybrid sops-nix + clan vars operation

### Mitigation strategies

**Hybrid approach** (recommended):
- Generated secrets → clan vars (SSH keys, service credentials, etc.)
- External secrets → remain in sops-nix (API tokens, passwords)
- Both systems coexist long-term
- No forced migration of external secrets

**Incremental migration**:
- Migrate one generator at a time
- Validate generation works before removing sops-nix secret
- Test service with generated secret before committing
- Keep sops-nix version as backup initially

**Pre-commit validation**:
- Use git pre-commit hooks to detect unencrypted secrets
- gitleaks prevents secret leakage
- Review diffs carefully before commit
- Test generation in separate branch first

**Generator testing**:
- Test generator script in isolation
- Verify output format before integration
- Check encryption occurs correctly
- Validate service can read generated secret

**Key management**:
- Age keys generated and backed up before vars generation
- Test decryption works on target host
- Document key recovery procedure
- Backup encrypted secrets separately

**Rollback strategy**:
- Keep sops-nix secrets until clan vars validated
- Dual configuration (can switch back to sops-nix)
- Document transition per secret type
- No deletion of sops-nix secrets until fully replaced

### Status

**Partially mitigated** - Hybrid approach implemented (November 2024).
Generated secrets successfully migrated to clan vars across 8-machine fleet.
External secrets remain in sops-nix as planned.
Both systems coexist as designed.

### References

- Migration plan: Appendix on secrets migration strategy
- [Usage model](/development/requirements/usage-model/) - UC-003: Declarative secrets management
- [Security](/development/requirements/quality-requirements/) - QR-005: Secrets encryption requirements

## R-006: Breaking changes in upstream dependencies

### Description

Updates to nixpkgs, dendritic-flake-parts, or clan could introduce breaking changes during migration.

### Risk factors

- Dendritic and clan both actively developed
- nixpkgs-unstable inherently unstable
- API changes between versions
- Documentation lag behind implementation
- Multiple dependency updates during multi-month migration

### Likelihood

**High** - Breaking changes are common in unstable channel and evolving projects.

### Impact

**Medium** - Can delay migration or require rework, but not catastrophic.

### Migration timeline relevance

- Ongoing risk throughout migration
- Particularly relevant during initial validation (validation against current versions)
- Risk increases with migration duration

### Mitigation strategies

**Input locking discipline**:
- Lock all inputs at migration start
- Only update inputs intentionally
- Document reason for each update
- Test thoroughly after updates

**Conservative update policy**:
- Don't update inputs during active migration work
- Update between major milestones only
- Read changelogs before updating
- Test in validation environment before production

**Multi-channel resilience** (already implemented):
- Stable fallback for broken packages
- Surgical fixes without system rollback
- Overlay infrastructure operational
- Package-specific workarounds

**Version pinning strategy**:
- Pin critical inputs to specific commits
- Use follows for input consistency
- Document known-good versions
- Maintain working flake.lock in git

**Monitoring and awareness**:
- Subscribe to clan and dendritic releases
- Review nixpkgs weekly summary
- Track upstream issues affecting our use case
- Participate in community discussions

**Contingency planning**:
- Document workaround procedures
- Maintain patches directory for upstream fixes
- Plan time buffer for unexpected breakage
- Can delay migration if dependencies unstable

### Status

**Ongoing** - Risk exists throughout migration and beyond

### References

- [Handling broken packages](/guides/handling-broken-packages) - Multi-channel resilience
- [System constraints](/development/requirements/system-constraints/) - SC-003: Input locking

## R-007: Initial validation revealing architectural incompatibility

### Description

Test-clan validation could uncover fundamental incompatibilities requiring architecture redesign.

### Risk factors

- Novel integration (dendritic + clan)
- No reference implementations
- Possible fundamental conflicts
- Late discovery of limitations
- Investment in approach that doesn't work

### Likelihood

**Low-Medium** - Both technologies mature, but integration untested.

### Impact

**Very High** - Could force complete architecture redesign or migration abandonment.

### Migration timeline relevance

- Initial validation (discovery phase)
- If discovered: all subsequent work blocked pending redesign

### Mitigation strategies

**Purpose of initial validation**:
- Exists specifically to catch this risk
- Isolated validation before infrastructure investment
- No production impact if issues found
- Time investment only (no financial cost)

**Early validation approach**:
- Test integration basics first (can dendritic + clan coexist?)
- Validate core use cases before complex scenarios
- Document blockers immediately
- Engage community if issues found

**Fallback options if incompatibility found**:
1. **Clan without dendritic**: Use clan with standard flake-parts
2. **Dendritic without clan**: Use dendritic with enhanced sops-nix
3. **Hybrid approach**: Dendritic for modules, traditional flake for clan
4. **Stay on nixos-unified**: Abort migration, enhance current architecture
5. **Custom integration layer**: Build compatibility wrapper

**Decision criteria**:
- Severity of incompatibility
- Workaround feasibility
- Benefit vs. complexity trade-off
- Time investment required
- Alternative architecture viability

**Community engagement**:
- Open issues on relevant repositories
- Discuss in Matrix/Discord channels
- Share findings publicly
- Contribute fixes upstream if possible

### Status

**Mitigated** - Initial validation confirmed compatibility (November 2024).
No fundamental incompatibilities discovered.
Dendritic + clan integration successful across 8-machine production deployment.

### References

- Phase 0 validation: docs/notes/clan/phase-0-validation.md
- [Project scope](../context/project-scope/) - Validation rationale

## R-008: Zerotier network reliability and connectivity issues

### Description

Overlay network dependency introduces new failure modes: controller outages, peer connectivity problems, or network instability.

### Risk factors

- Single controller (VPS) as point of failure
- Network configuration complexity
- Firewall / NAT traversal issues
- Zerotier service bugs or breaking changes
- Dependency on external zerotier.com infrastructure

### Likelihood

**Medium** - Zerotier is mature, but any network dependency adds complexity.

### Impact

**Low-Medium** - Degrades multi-host coordination but doesn't break individual hosts.

### Migration timeline relevance

- VPS deployment (controller setup)
- Peer additions during host migrations
- Post-migration: Ongoing operational risk

### Mitigation strategies

**Controller reliability**:
- VPS on reliable infrastructure (Hetzner)
- Monitoring via simple health checks
- Automatic restart via systemd
- Backup/restore procedure documented

**Graceful degradation**:
- Hosts functional without zerotier
- Network coordination optional, not required
- Critical workflows not zerotier-dependent
- Can operate disconnected temporarily

**Peer resilience**:
- Peers cache credentials and reconnect automatically
- Network survives peer restarts
- No peer dependencies (all peer-controller, not peer-peer-critical)
- Temporary disconnection acceptable

**Connectivity validation**:
- Test zerotier before depending on it
- Validate NAT traversal works
- Firewall configuration documented
- Troubleshooting procedures prepared

**Alternative approaches**:
- Tailscale as alternative overlay network
- Direct WireGuard if needed
- SSH port forwarding as fallback
- Can operate without overlay network initially

**Monitoring**:
- Periodic connectivity checks
- Log zerotier status
- Alert on prolonged disconnection
- Dashboard for network state (future enhancement)

### Status

**Mitigated** - Zerotier network deployed and operational (November 2024).
Cinnabar controller stable, all 8 machines connected via overlay network.
NAT traversal functioning, connectivity reliable across fleet.

### References

- [Usage model](/development/requirements/usage-model/) - UC-006: Overlay network use case
- [System constraints](/development/requirements/system-constraints/) - SC-009: Network constraints

## R-009: Multi-host synchronization failures

### Description

Service instances spanning multiple hosts could have inconsistent configuration or deployment timing issues.

### Risk factors

- No atomic multi-host deployment
- Configuration drift if hosts updated separately
- Role assignment errors
- Partial deployment failures
- Timing dependencies between roles

### Likelihood

**Low-Medium** - Clan-core handles coordination, but complexity remains.

### Impact

**Medium** - Service malfunction but individual hosts remain operational.

### Migration timeline relevance

- VPS deployment (first multi-host service - zerotier)
- Additional hosts joining services
- Post-migration: Ongoing coordination

### Mitigation strategies

**Deployment order discipline**:
- Deploy controller role first (establishes service)
- Deploy dependent roles after controller operational
- Validate each deployment before next
- Document deployment order per service

**Configuration validation**:
- Use nix flake check to validate configuration
- Test service definitions before deployment
- Verify role assignments correct
- Check tag-based assignments match expectations

**Idempotent deployment**:
- Re-running deployment safe (clan property)
- Can re-deploy host without affecting others
- Incremental convergence to desired state
- No harm from repeated deployment

**Health checks**:
- Validate service operational after each deployment
- Test inter-host communication
- Verify role-appropriate behavior
- Document expected state per role

**Rollback strategy**:
- Each host independently rollback-able
- Service instance configuration in git (revertable)
- Can remove host from service instance if problematic
- No cascading failures from single host rollback

**Graceful failure**:
- Service degradation acceptable vs. all-or-nothing
- Hosts functional even if coordination fails
- Can re-deploy to fix synchronization
- Manual coordination as fallback

### Status

**Mitigated** - Multi-host services deployed successfully (November 2024).
Zerotier and other multi-host services operational across 8-machine fleet.
Deployment coordination and role-based configuration validated.

### References

- [Usage model](/development/requirements/usage-model/) - UC-004: Multi-host services
- [Domain model](../context/domain-model/) - Clan service instances

## R-010: Learning curve for dendritic + clan patterns

### Description

Mastering new patterns requires time investment and could lead to suboptimal early implementations.

### Risk factors

- Two new patterns simultaneously
- Limited documentation for combination
- No mentors or existing team knowledge
- Trial-and-error learning
- Refactoring needs as understanding deepens

### Likelihood

**High** - Learning curve is certain for new patterns.

### Impact

**Low-Medium** - Time investment and potential rework, but not blocking.

### Migration timeline relevance

- Initial validation (steepest learning)
- Ongoing learning and refinement throughout migration
- Post-migration: Consolidation and optimization

### Mitigation strategies

**Structured learning**:
- Initial validation dedicated to experimentation
- Document learnings immediately
- Create reference examples
- Build pattern library

**Iterative refinement**:
- Accept early implementations may be suboptimal
- Plan for refactoring as understanding grows
- Incremental improvement over perfection
- Learning investment pays off long-term

**Documentation discipline**:
- Document patterns as discovered
- Capture rationale for decisions
- Create examples for future reference
- AMDiRE documentation captures architecture

**Community engagement**:
- Ask questions in dendritic/clan channels
- Share findings publicly
- Contribute documentation improvements
- Learn from others' experience

**Time allocation**:
- Budget learning time in migration schedule
- Don't rush early work
- Allow experimentation time
- Patience with learning process

**Quality over speed**:
- Thorough understanding > rapid migration
- Deep learning prevents future issues
- Investment in learning reduces future rework
- Build confidence through mastery

### Status

**Mitigated** - Learning curve successfully navigated (November 2024).
Dendritic + clan patterns mastered through migration.
Comprehensive documentation created, patterns validated across 8-machine production deployment.

### References

- [Goals](../context/goals-and-objectives/) - G-S03: Reasonable time investment
- [Context: Project scope](../context/project-scope/) - Migration rationale

## Risk summary matrix

| Risk | Likelihood | Impact | Timeline Relevance | Priority | Status (Nov 2024) |
|------|-----------|--------|-------------------|----------|-------------------|
| R-001: Integration complexity | Medium | High | Initial validation | Critical | **Mitigated** |
| R-002: VPS costs | High | Medium | VPS deployment | Medium | **Mitigated** |
| R-003: Workflow breakage | High | Variable | Darwin migrations | High | **Mitigated** |
| R-004: Stibnite migration | Medium | Critical | Stibnite migration | Critical | **Mitigated** |
| R-005: Secrets migration | Medium | High | Progressive | High | **Partially mitigated** |
| R-006: Dependency breakage | High | Medium | Ongoing | Medium | **Ongoing** |
| R-007: Architecture incompatibility | Low-Medium | Very High | Initial validation | Critical | **Mitigated** |
| R-008: Network issues | Medium | Low-Medium | VPS + migrations | Low | **Mitigated** |
| R-009: Multi-host sync | Low-Medium | Medium | VPS + migrations | Low | **Mitigated** |
| R-010: Learning curve | High | Low-Medium | Ongoing | Low | **Mitigated** |

## Risk response strategy

### Historical risks (successfully mitigated, November 2024)

- **R-001**: Integration complexity mitigated through initial validation in test-clan
- **R-002**: VPS costs managed, cinnabar operational with minimal overhead
- **R-003**: Workflow preservation achieved across all 4 darwin hosts
- **R-004**: Stibnite migration successful as final host
- **R-005**: Hybrid secrets approach implemented (generated→clan vars, external→sops-nix)
- **R-007**: Architecture compatibility confirmed, no fundamental issues found
- **R-008**: Zerotier network stable across 8-machine fleet
- **R-009**: Multi-host coordination working reliably
- **R-010**: Learning curve navigated, comprehensive documentation created

### Ongoing risks (active monitoring)

- **R-006**: Dependency breakage - continues to require input locking discipline and conservative update policy

## References

**Context layer**:
- [Project scope](../context/project-scope/) - Migration strategy and risk management
- [Goals and objectives](../context/goals-and-objectives/) - Risk tolerance considerations
- [Stakeholders](../context/stakeholders/) - Risk decision authority

**Requirements**:
- [Usage model](/development/requirements/usage-model/) - Use cases affected by risks
- [Quality requirements](/development/requirements/quality-requirements/) - Quality attributes at risk
- [Deployment requirements](/development/requirements/deployment-requirements/) - Deployment failure risks

**Migration planning** (internal):
- docs/notes/clan/integration-plan.md - Complete migration strategy
- docs/notes/clan/phase-0-validation.md - R-001, R-007 mitigation
- docs/notes/clan/migration-assessment.md - Per-host risk assessment
