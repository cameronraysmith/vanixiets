# Functional Requirements

## FR-1: Architectural Integration (Phase 0 validation)

**FR-1.1**: test-clan repository shall integrate clan-core flakeModules with dendritic flake-parts pattern (or hybrid approach if conflicts discovered)

- Flake shall use `import-tree ./modules` for automatic module discovery
- Clan inventory shall evaluate successfully with test machine definition
- nixosConfiguration shall build for test-vm using dendritic module namespace

**FR-1.2**: Integration findings shall be documented in `INTEGRATION-FINDINGS.md` with:

- List of integration points between dendritic and clan
- Identified conflicts or compromises required
- Acceptable deviations from pure dendritic pattern (if any)
- Rationale for architectural decisions

**FR-1.3**: Reusable patterns shall be extracted to `PATTERNS.md` with:

- Module structure templates for NixOS configurations
- Clan inventory patterns for machine definitions
- Service instance patterns for essential services
- Vars generator patterns for secrets management

**FR-1.4**: Go/no-go decision framework shall evaluate:

- GO: No fundamental conflicts, proceed to infrastructure deployment with confidence
- CONDITIONAL GO: Minor compromises required, proceed with caution and additional monitoring
- NO-GO: Fundamental incompatibilities, pivot to vanilla clan + flake-parts pattern

**FR-1.5**: Infrastructure deployment shall provision multi-cloud VMs with:

- Hetzner Cloud CX53 VPS (cinnabar) via terranix using clan-infra's proven pattern
- GCP e2-micro VM (orb-nixos) for multi-cloud validation
- Disko declarative partitioning with LUKS encryption on both VMs
- Minimal service configuration (SSH access, basic connectivity)
- Terraform state management via encrypted backend

**FR-1.6**: Multi-machine coordination shall be validated with:

- Clan inventory managing 2 machines (cinnabar + orb-nixos) with heterogeneous cloud providers
- Zerotier mesh network between VMs proving service coordination
- SSH access functional on both machines via zerotier network
- Clan vars deployed to `/run/secrets/` on both machines
- Infrastructure stable before Phase 1 production integration

**Acceptance criteria**:

- [ ] test-clan flake evaluates without errors (`nix flake check`)
- [ ] test-vm builds successfully (`nix build .#nixosConfigurations.test-vm.config.system.build.toplevel`)
- [ ] Documentation complete with architectural decision rationale
- [ ] Go/no-go decision made with explicit justification
- [ ] Infrastructure deployed successfully (cinnabar + orb-nixos operational)
- [ ] Multi-machine coordination validated (zerotier mesh, SSH access, clan vars)
- [ ] Infrastructure stable for 1 week minimum before Phase 1

---

## FR-2: Production Integration (Phase 1)

**FR-2.1**: Production services shall be integrated on deployed infrastructure with:

- Zerotier controller operational on cinnabar coordinating mesh network to orb-nixos
- Production-grade configuration applied to both VMs (srvos hardening, security baseline)
- Service deployment patterns validated (multi-VM coordination via clan inventory)
- Infrastructure proven stable under production-like load

**FR-2.2**: Security hardening shall be applied with:

- srvos modules providing security baseline (both cinnabar and orb-nixos)
- Firewall rules configured via NixOS (zerotier mesh access, external SSH only)
- LUKS encryption validated operational on both VMs
- Certificate-based SSH authentication enforced (no password-based auth)
- Principle of least privilege applied to all services

**FR-2.3**: Multi-VM coordination shall be operational with:

- Clan inventory managing 2 machines with different roles
- Zerotier mesh network connecting cinnabar + orb-nixos
- SSH via zerotier functional between VMs
- Clan vars deployed correctly to `/run/secrets/` on both machines with proper permissions
- Service instances with roles proven across heterogeneous infrastructure

**FR-2.4**: Production secrets management shall be validated with:

- Clan vars generators producing all required secrets (SSH host keys, service credentials, API tokens)
- Secrets encrypted at rest via age encryption in `sops/machines/<hostname>/secrets/`
- Automatic deployment to `/run/secrets/` with correct ownership (root or specific user)
- Shared secrets (where `share = true`) accessible across machines as configured
- Rollback procedure for secrets tested (redeploy previous generation)

**FR-2.5**: Infrastructure monitoring and validation:

- System resource utilization within expected parameters (CPU, memory, disk, network)
- Log aggregation functional (journald, clan logging if configured)
- Backup procedures validated (if implemented in Phase 1)
- Disaster recovery procedure documented (rebuild from configuration)

**Acceptance criteria**:

- [ ] Zerotier controller operational with mesh network to orb-nixos
- [ ] Production-grade hardening applied (srvos modules, firewall, LUKS)
- [ ] Multi-VM coordination validated (clan inventory, service instances, SSH via mesh)
- [ ] Clan vars deployed correctly on both machines (`ls /run/secrets/`)
- [ ] Infrastructure stable for 1-2 weeks minimum before darwin migration
- [ ] Production-readiness validated (security, monitoring, disaster recovery)

---

## FR-3: Darwin Host Migration (Phases 2-4)

**FR-3.1**: Darwin modules shall be converted to dendritic pattern with:

- Each darwin module contributing to `flake.modules.darwin.*` namespace
- Home-manager modules contributing to `flake.modules.homeManager.*` namespace
- Host-specific configurations in `modules/hosts/<hostname>/default.nix`
- Imports via `imports = with config.flake.modules; [ darwin.base homeManager.shell ];`

**FR-3.2**: Clan inventory shall define darwin machines with:

- Machine entry for each darwin host (blackphos, rosegold, argentum)
- Tags: `[ "darwin" "workstation" ]` (and `"primary"` for stibnite)
- machineClass: `"darwin"`
- Service instance role assignments (peer for zerotier, server/client for sshd, default for emergency-access and users)

**FR-3.3**: Zerotier peer role shall connect with:

- Peer role configuration via clan zerotier service instance
- Connection to cinnabar controller (always-on VPS zerotier controller)
- Full mesh connectivity (darwin host can reach cinnabar and other darwin hosts)
- Automatic network join on system activation

**FR-3.4**: Clan vars shall generate and deploy darwin secrets with:

- SSH host keys generated for each darwin machine
- User-specific secrets (if configured)
- Secrets deployed to `/run/secrets/` with darwin-compatible permissions
- Home-manager integration for user-level secrets access

**FR-3.5**: Functionality preservation shall be validated with:

- Package comparison: pre-migration vs. post-migration package lists identical
- System services functional: all previously working services operational
- Development workflows intact: editors, languages, tools, shell configuration
- Homebrew integration working (if used): casks, formulae, taps
- System preferences applied: macOS settings via nix-darwin

**FR-3.6**: Multi-machine coordination shall be operational with:

- SSH via zerotier network functional between all hosts
- Clan service instances deployed correctly across machines
- Vars shared appropriately (where `share = true` configured)
- Network latency acceptable for development use (non-critical)

**Acceptance criteria per host**:

- [ ] Host configuration builds (`nix build .#darwinConfigurations.<hostname>.system`)
- [ ] Deployment succeeds (`darwin-rebuild switch --flake .#<hostname>`)
- [ ] All functionality preserved (zero-regression validation)
- [ ] Zerotier peer connected (`zerotier-cli status` shows network membership)
- [ ] SSH via zerotier works (`ssh crs58@<host-zerotier-ip>`)
- [ ] Stable for 1-2 weeks before next host

**Phase sequencing**:

- Phase 2: blackphos (establish patterns)
- Phase 3: rosegold (validate pattern reusability)
- Phase 4: argentum (final validation before stibnite)

---

## FR-4: Primary Workstation Migration (Phase 5)

**FR-4.1**: Pre-migration readiness shall be validated with:

- blackphos stable for 4-6 weeks minimum
- rosegold stable for 2-4 weeks minimum
- argentum stable for 2-4 weeks minimum
- No outstanding critical bugs or issues in patterns
- All workflows tested on other hosts (development environment, tools, system services)
- Full backup of current stibnite configuration created
- Rollback procedure documented and tested
- Low-stakes timing (not before important deadline)

**FR-4.2**: stibnite migration shall apply proven patterns with:

- Configuration in `modules/hosts/stibnite/default.nix` using blackphos patterns
- All daily-use workflows configured: development environment, communication tools, system services, GUI applications
- Enhanced validation before deployment (dry-run, double-check all imports)
- Staged deployment (deploy but don't reboot immediately, test in current session)

**FR-4.3**: Daily workflows shall be validated immediately post-migration:

- Development environment: editors, IDEs, language environments, version control
- Communication tools: if managed via nix (browsers, chat applications)
- System services: essential background services
- Shell configuration: fish, starship, aliases, functions
- Performance: system responsiveness, build times

**FR-4.4**: 5-machine network shall be complete with:

- Zerotier peer role on stibnite connecting to cinnabar controller
- Full mesh connectivity: stibnite can reach all other machines (cinnabar, blackphos, rosegold, argentum)
- SSH via zerotier functional to/from stibnite
- Multi-machine coordination operational (all clan services deployed across 5 machines)

**FR-4.5**: Productivity shall be maintained with:

- No critical regressions in daily workflows
- Performance maintained (build times, system responsiveness)
- All applications and tools functional
- Subjective productivity assessment: maintained or improved

**Acceptance criteria**:

- [ ] Pre-migration checklist 100% complete
- [ ] stibnite configuration builds successfully
- [ ] Deployment succeeds without errors
- [ ] All daily workflows functional (comprehensive validation)
- [ ] 5-machine zerotier network complete
- [ ] Productivity maintained (subjective assessment positive)
- [ ] Stable for 1-2 weeks before Phase 6 cleanup

---

## FR-5: Legacy Cleanup (Phase 6)

**FR-5.1**: nixos-unified infrastructure shall be removed with:

- Delete `configurations/` directory (host-specific nixos-unified configs)
- Remove nixos-unified flake input from `flake.nix`
- Remove nixos-unified flakeModules imports
- Update documentation referencing nixos-unified

**FR-5.2**: Secrets migration completion (if applicable):

- Evaluate remaining sops-nix secrets
- Migrate generated secrets to clan vars (SSH keys, passwords)
- Keep sops-nix for external credentials (API tokens) if hybrid approach chosen
- Remove sops-nix entirely if full migration achieved

**FR-5.3**: Documentation shall be updated with:

- README reflecting dendritic + clan architecture
- Migration experience documented for future reference
- Architectural decisions captured in docs/notes/
- Patterns documented for maintainability

**Acceptance criteria**:

- [ ] nixos-unified completely removed
- [ ] Secrets migration strategy finalized (full or hybrid)
- [ ] Documentation updated and accurate
- [ ] Clean dendritic + clan architecture
- [ ] All 5 machines operational with no legacy dependencies

---
