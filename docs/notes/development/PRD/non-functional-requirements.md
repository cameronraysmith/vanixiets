# Non-Functional Requirements

## Performance

**Build times**: Configuration evaluation and build times shall not significantly regress from current nixos-unified setup

- Baseline: Measure current `darwin-rebuild switch` time for each host
- Target: Within 20% of baseline (acceptable: 10 seconds build now → 12 seconds after migration)
- Critical: Primary workstation (stibnite) build times must not impact daily workflow

**System responsiveness**: Darwin hosts shall maintain interactive responsiveness

- No perceptible lag in shell, editor, or GUI applications
- Background services shall not consume excessive CPU/memory
- Zerotier network overhead acceptable (non-critical path for daily work)

**Network latency**: Zerotier mesh network latency shall be acceptable for development use

- Inter-machine SSH latency < 100ms on local network
- WAN latency dependent on internet connection (not critical for daily workflow)
- No requirement for low-latency distributed services (out of scope)

## Security

**Secrets encryption**: All secrets shall be encrypted at rest via age encryption

- Clan vars encrypted in `sops/machines/<hostname>/secrets/`
- Age public keys for admins group and per-machine keys
- Decryption only on target machine during deployment
- Private keys only in `/run/secrets/` with restrictive permissions (mode 0600, root or specific user ownership)

**SSH access**: SSH shall use certificate-based authentication

- SSH CA certificates distributed via clan sshd service
- No password-based authentication (disabled in sshd configuration)
- Zerotier network provides VPN security layer (encrypted mesh)

**VPS security**: cinnabar VPS shall be hardened via:

- srvos hardening modules (server security baseline)
- LUKS full-disk encryption
- Firewall configured via NixOS (allow SSH, zerotier, deny all else)
- Regular security updates via nixpkgs tracking

**Emergency access**: Root access recovery via:

- Clan emergency-access service (password-based recovery)
- Only on workstations (not VPS, to prevent remote access)
- Documented procedure for recovery

## Scalability

**Machine count**: Architecture shall support 5 machines (current requirement)

- Extensible to additional machines without architectural changes
- Clan inventory scales to dozens of machines (proven in clan-infra)
- Zerotier supports up to 100 peers on free tier

**Configuration size**: Module organization shall scale as configuration grows

- Flat feature categories (not nested) prevent deep hierarchies
- Clear namespace (`flake.modules.*`) enables discovery
- import-tree auto-discovery scales to hundreds of modules

**Build parallelism**: Configuration evaluation shall remain performant as machines increase

- Per-host evaluation independent (can build multiple hosts in parallel)
- Shared modules evaluated once, reused across hosts

## Integration

**Terraform integration**: VPS provisioning shall integrate with Hetzner Cloud

- Terranix generates terraform configuration from Nix
- Terraform state tracked (manual management acceptable for MVP)
- Idempotent deployment (re-running terraform safe)

**Home-manager integration**: User environment shall integrate with system configuration

- home-manager modules imported in host configurations
- `home-manager.useGlobalPkgs = true` for consistency
- User-level secrets via clan vars accessible in home-manager

**Homebrew integration** (darwin-specific): macOS package manager shall coexist with nix

- nix-darwin homebrew module configures homebrew casks, formulae, taps
- Declarative homebrew management (brewfile generation)
- Nix-managed and Homebrew-managed packages coexist

**SOPS integration** (if hybrid approach): External secrets shall remain in sops-nix

- sops-nix module imported alongside clan
- Age-based encryption (shared age keys)
- Separate secret paths (`/run/secrets-sops/`) to avoid conflicts with clan vars

---

## Post-MVP Expansion NFRs

### GCP Infrastructure (Epic 7)

**Pattern consistency**: Terranix GCP module shall follow patterns established in hetzner.nix:

- Machine definition structure with enabled/disabled toggle
- SSH key generation and registration
- null_resource provisioner for `clan machines install`
- Consistent naming conventions

**Cost management**: Disabled nodes shall incur zero ongoing cost:

- Infrastructure as code defines desired state
- Disabled machines not provisioned (terraform destroy behavior)
- GPU nodes especially costly when idle - toggle critical for cost control

**Deployment consistency**: GCP deployment shall use `clan machines install` pattern:

- Consistent with Hetzner deployment workflow
- Same secrets management via clan vars
- Same zerotier mesh integration

### Documentation (Epic 8)

**Accuracy**: Zero references to deprecated nixos-unified architecture in published docs:

- All architecture references updated to dendritic + clan
- Legacy patterns removed or marked as deprecated
- Current implementation reflected in examples

**Testability**: Documentation shall be testable against actual infrastructure state:

- Commands in docs should work when executed
- Configuration examples should build successfully
- Screenshots/diagrams reflect current implementation

### Release (Epic 9)

**Semantic versioning**: Release shall follow semantic versioning with changelog:

- MAJOR.MINOR.PATCH versioning
- Changelog generated from conventional commits
- Breaking changes documented

**History preservation**: No force-push or history rewriting during merge:

- Clean merge preserving all commit history
- Branch boundaries tagged for reference
- Rollback possible via tag reference

---
