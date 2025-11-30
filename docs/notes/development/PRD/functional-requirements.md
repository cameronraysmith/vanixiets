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

## FR-2: Infrastructure Architecture Migration (Phase 1 - Epic 2)

Apply test-clan validated patterns to production infra repository using "rip the band-aid" wholesale replacement strategy.

**Four Phases:**
1. **Home-Manager Migration Foundation** (3-4 stories) - Affects ALL hosts, foundational for everything else
2. **Active Darwin Workstations** (4-5 stories) - blackphos + stibnite migration, activate from infra (blackphos switches test-clan → infra)
3. **VPS Config Migration** (2-3 stories) - cinnabar + electrum config migration from test-clan → infra (infrastructure already deployed in Epic 1)
4. **Future Machines** (3-4 stories) - rosegold + argentum configuration creation

**Migration Strategy:** "Rip the band-aid" approach - create `clan-01` branch, wholesale nix config replacement from test-clan, preserve infra-specific components (GitHub Actions, TypeScript monorepo, Cloudflare deployment).

**Epic 1 Foundation:** Infrastructure deployed and operational in Epic 1 (cinnabar IP 49.13.68.78, electrum operational, blackphos physically deployed with 270 packages preserved).

**FR-2.1**: Home-manager migration foundation shall migrate shared home-manager configuration:

- Migrate home-manager configuration from infra to dendritic+clan pattern
- Affects ALL hosts (stibnite, blackphos, cinnabar, electrum, rosegold, argentum)
- Includes LazyVim-module → lazyvim-nix migration (apply Epic 1 improvement)
- Cross-platform modules proven (same code works nixos + darwin)
- Foundation complete before host-specific migrations

**FR-2.2**: Active darwin workstations shall migrate blackphos + stibnite configurations:

- Migrate blackphos config in infra to match test-clan version (feature parity)
- Migrate stibnite config in infra (apply architecture, preserve differences)
- Both proceed together (shared home-manager foundation)
- Activate both from infra (blackphos switches test-clan → infra)
- Cleanup: Remove unused configs (blackphos-nixos, stibnite-nixos, rosegold-old)
- SSH configuration (server + client) migrated to match blackphos pattern

**FR-2.3**: VPS configuration migration shall migrate cinnabar + electrum configs:

- Migrate cinnabar + electrum configs from test-clan → infra
- Infrastructure already deployed and operational in test-clan (Epic 1)
- Config migration only (no infrastructure redeployment required)
- Preserve zerotier controller configuration (cinnabar)
- Multi-machine coordination maintained

**FR-2.4**: Future machine configurations shall be created:

- Create rosegold configuration in infra (new)
- Create argentum configuration in infra (new)
- Apply proven patterns from blackphos/stibnite migrations
- Prepare for Epic 3-4 deployments

**Acceptance criteria**:

- [ ] Home-manager foundation migrated (affects all hosts)
- [ ] Blackphos config migrated to infra (feature parity with test-clan)
- [ ] Stibnite config migrated to infra (architecture applied, differences preserved)
- [ ] Both active darwin workstations activated from infra
- [ ] Cinnabar + electrum configs migrated from test-clan → infra
- [ ] Rosegold + argentum configurations created
- [ ] All builds passing, zero regressions
- [ ] Infrastructure stable for 1-2 weeks before Epic 3

---

## FR-3: Rosegold Deployment (Phase 2 - Epic 3, formerly Epic 4)

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

**Note:** blackphos migration already complete in Epic 2. This epic focuses on rosegold deployment using proven patterns.

---

## FR-4: Argentum Deployment (Phase 3 - Epic 4, formerly Epic 5)

**FR-4.1**: argentum deployment shall apply proven patterns:

- Configuration in `modules/hosts/argentum/default.nix` using patterns from Epic 2-3
- Clan inventory integration with appropriate tags and service instances
- Zerotier peer role connecting to cinnabar controller
- Home-manager configuration from shared foundation (Epic 2 Phase 1)
- User-specific customization for christophersmith

**FR-4.2**: All functionality shall be validated:

- Host configuration builds successfully
- Deployment succeeds without errors
- All packages functional (zero-regression validation)
- Zerotier peer connected and mesh network operational
- SSH via zerotier functional

**Acceptance criteria**:

- [ ] argentum configuration builds successfully
- [ ] Deployment succeeds without errors
- [ ] All functionality preserved (zero-regression validation)
- [ ] Zerotier peer connected
- [ ] SSH via zerotier works
- [ ] Stable for 1-2 weeks before Epic 5

---

## FR-5: Stibnite Extended Validation (Phase 4 - Epic 5, formerly Epic 6, CONDITIONAL)

**CONDITIONAL Epic:** Only execute if Epic 2 Phase 2 shows instability requiring additional validation before primary workstation migration.

**FR-5.1**: Extended validation shall be performed if needed:

- Stibnite configuration validation using proven patterns from Epic 2-4
- Additional stability testing if Epic 2 Phase 2 revealed issues
- Pattern refinement based on multi-host experience
- Pre-migration checklist comprehensive validation

**Acceptance criteria (if executed)**:

- [ ] All previous hosts stable for cumulative 4-6 weeks
- [ ] Stibnite configuration validated
- [ ] No outstanding critical bugs or issues
- [ ] Ready for legacy cleanup

**Note:** This epic may be skipped if Epic 2 Phase 2 proves stable and no additional validation required.

---

## FR-6: Legacy Cleanup (Phase 5 - Epic 6, formerly Epic 7)

**FR-6.1**: nixos-unified infrastructure shall be removed with:

- Delete `configurations/` directory (host-specific nixos-unified configs)
- Remove nixos-unified flake input from `flake.nix`
- Remove nixos-unified flakeModules imports
- Update documentation referencing nixos-unified

**FR-6.2**: Secrets migration completion (if applicable):

- Evaluate remaining sops-nix secrets
- Migrate generated secrets to clan vars (SSH keys, passwords)
- Keep sops-nix for external credentials (API tokens) if hybrid approach chosen
- Remove sops-nix entirely if full migration achieved

**FR-6.3**: Documentation shall be updated with:

- README reflecting dendritic + clan architecture
- Migration experience documented for future reference
- Architectural decisions captured in docs/notes/
- Patterns documented for maintainability

**Acceptance criteria**:

- [ ] nixos-unified completely removed
- [ ] Secrets migration strategy finalized (full or hybrid)
- [ ] Documentation updated and accurate
- [ ] Clean dendritic + clan architecture
- [ ] All machines operational with no legacy dependencies

---

## FR-7: GCP Multi-Node Infrastructure (Post-MVP Phase 6 - Epic 7)

GCP compute infrastructure expansion for contract obligations and GPU availability using proven terranix patterns.

**FR-7.1**: System shall provision GCP compute instances via terranix with enabled/disabled toggle:

- Terranix GCP module following patterns established in `modules/terranix/hetzner.nix`
- Machine definitions with `enabled = true/false` toggle for cost control
- Terraform state management consistent with Hetzner deployment

**FR-7.2**: CPU-only nodes shall use cost-effective machine types:

- e2-standard or n2-standard machine families for general compute
- Location selection based on cost and latency requirements
- Debian base image for NixOS installation consistency

**FR-7.3**: GPU-capable nodes shall support NVIDIA accelerators for ML workloads:

- T4 and A100 GPU accelerator options
- GPU-specific machine types (n1-standard with GPU attachment)
- CUDA/driver configuration via NixOS modules

**FR-7.4**: GCP nodes shall join clan inventory with zerotier mesh integration:

- Machine entries in clan inventory with appropriate tags ("nixos", "vps", "cloud", "gcp")
- Zerotier peer role connecting to cinnabar controller
- Clan vars deployment for secrets
- `clan machines install` deployment consistent with Hetzner pattern

**Acceptance criteria**:

- [ ] Terranix GCP module builds (`nix eval .#terranixConfigurations.gcp`)
- [ ] CPU-only node deploys successfully with toggle enabled
- [ ] GPU-capable node deploys successfully with toggle enabled
- [ ] Both node types join zerotier mesh and clan inventory
- [ ] Disabled nodes incur zero ongoing cost

---

## FR-8: Documentation Alignment (Post-MVP Phase 7 - Epic 8)

Comprehensive documentation update to reflect dendritic + clan architecture after GCP infrastructure deployment.

**FR-8.1**: Starlight docs site shall be updated for dendritic + clan architecture:

- packages/docs/src/content/docs/ updated with current patterns
- Architecture diagrams reflecting implemented patterns (not legacy nixos-unified)
- Module organization documentation for dendritic flake-parts

**FR-8.2**: Architecture documentation shall reflect implemented patterns:

- docs/notes/development/architecture/ sections updated
- ADRs added for GCP infrastructure decisions
- Deployment patterns documented for multi-cloud (Hetzner + GCP)

**FR-8.3**: Host onboarding guides shall differentiate darwin vs nixos deployment:

- Darwin deployment path: `darwin-rebuild switch --flake`
- NixOS VPS deployment path: `clan machines install`
- Prerequisites and environment setup for each path

**FR-8.4**: Secrets management documentation shall cover two-tier pattern:

- Clan vars for generated secrets (SSH keys, service passwords)
- sops-nix for external credentials (API tokens, if hybrid approach)
- Migration path from pure sops-nix to clan vars

**Acceptance criteria**:

- [ ] Starlight docs site builds without errors
- [ ] Zero references to deprecated nixos-unified architecture
- [ ] Host onboarding guides accurate for both darwin and nixos
- [ ] Secrets management docs cover implemented two-tier pattern
- [ ] Documentation testable against actual infrastructure state

---

## FR-9: Branch Consolidation and Release (Post-MVP Phase 8 - Epic 9)

Merge clan-01 branch to main with proper tagging and CI/CD validation.

**FR-9.1**: Bookmark tags shall be created at key branch boundaries:

- Tag at docs branch merge point
- Tag at clan branch merge point
- Tag at clan-01 branch merge point
- Semantic versioning for release tag

**FR-9.2**: CI/CD workflows shall pass on clan-01 before merge authorization:

- All GitHub Actions workflows green
- `nix flake check` passing
- All host configurations building successfully

**FR-9.3**: clan-01 shall be merged to main with full history preservation:

- Fast-forward merge if possible
- No force-push or history rewriting
- Changelog generated from commit history

**Acceptance criteria**:

- [ ] Bookmark tags created at branch boundaries
- [ ] All CI/CD workflows passing on clan-01
- [ ] clan-01 merged to main successfully
- [ ] Release tag with semantic version applied
- [ ] Changelog published with release

---
