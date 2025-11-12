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
