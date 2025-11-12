# Infrastructure / Configuration Management Specific Requirements

## Declarative Infrastructure

**Infrastructure-as-code via Nix ecosystem**:

- All infrastructure configuration version-controlled in git (nix-config repository on `clan` branch)
- Declarative VPS provisioning via terraform/terranix (Hetzner Cloud API integration)
- Declarative disk partitioning via disko (LUKS encryption, filesystem layouts)
- Declarative system configuration via NixOS (cinnabar) and nix-darwin (workstations)
- Declarative user environment via home-manager (shell, development tools, applications)
- Declarative multi-machine coordination via clan inventory (machines, service instances, roles)
- Declarative secrets management via clan vars generators (automatic generation, encrypted storage, deployment)

**Evaluation and build separation**:

- Configuration evaluation must succeed before deployment (type checking via module system catches errors early)
- Build outputs are deterministic and reproducible (Nix content-addressed store)
- Deployment is atomic (activate new generation or rollback to previous)

**Rollback capability**:

- NixOS/nix-darwin generation rollback (boot menu or `darwin-rebuild switch --rollback`)
- Per-host rollback to nixos-unified configurations (preserved during migration, deleted in Phase 6)
- Terraform state rollback via `terraform destroy` (VPS disposable, redeploy from configuration)
- Git-based configuration rollback (revert commits, rebuild from earlier state)

## Module Organization

**Dendritic flake-parts pattern** (or validated hybrid from Phase 0):

**Flat feature categories** (not nested by platform):

```
modules/
├── base/              # Foundation modules (nix settings, system state)
├── nixos/             # NixOS-specific modules
├── darwin/            # Darwin-specific modules
├── shell/             # Shell tools (fish, starship, direnv)
├── dev/               # Development tools (git, jj, editors)
├── hosts/             # Machine-specific configurations
│   ├── cinnabar/
│   ├── blackphos/
│   ├── rosegold/
│   ├── argentum/
│   └── stibnite/
├── flake-parts/       # Flake-level configuration
│   ├── nixpkgs.nix
│   ├── darwin-machines.nix
│   ├── nixos-machines.nix
│   ├── terranix.nix
│   └── clan.nix
├── terranix/          # Terraform modules
└── users/             # User configurations
```

**Module namespace**: Every module contributes to `flake.modules.{nixos,darwin,homeManager}.*` namespace
**Host composition**: Hosts import modules via `imports = with config.flake.modules; [ darwin.base darwin.system homeManager.shell ];`
**Metadata sharing**: User/system metadata via `config.flake.meta.*` (email, SSH keys, etc.)
**Cross-cutting concerns**: Single module can target multiple systems (e.g., `flake.modules.darwin.shell` + `flake.modules.homeManager.shell`)

## Multi-Machine Coordination

**Clan inventory system**:

**Machine definitions**:

```nix
inventory.machines = {
  cinnabar = {
    tags = [ "nixos" "vps" "cloud" ];
    machineClass = "nixos";
  };
  blackphos = {
    tags = [ "darwin" "workstation" ];
    machineClass = "darwin";
  };
  # ... other hosts
};
```

**Service instances with roles**:

```nix
inventory.instances = {
  zerotier-local = {
    module = { name = "zerotier"; input = "clan-core"; };
    roles.controller.machines.cinnabar = {};
    roles.peer.tags."all" = {};  # All machines are peers
  };
  sshd-clan = {
    module = { name = "sshd"; input = "clan-core"; };
    roles.server.tags."all" = {};
    roles.client.tags."all" = {};
  };
};
```

**Configuration hierarchy**: instance-wide settings → role-wide settings → machine-specific settings
**Tag-based targeting**: Assign services to multiple machines via tags (e.g., `tags."workstation"` targets all darwin hosts)

## Secrets Management

**Clan vars system** (replaces manual sops-nix):

**Generators**: Declarative functions producing secrets (SSH keys, passwords, API keys)
**Storage**: Encrypted per-machine in `sops/machines/<hostname>/secrets/` via age encryption
**Deployment**: Automatic deployment to `/run/secrets/` with proper permissions
**Sharing**: `share = true` for secrets used across multiple machines (e.g., user SSH keys)
**DAG composition**: Dependencies between generators via `dependencies` attribute

**Hybrid approach acceptable**: Keep sops-nix for external credentials (API tokens from providers), use clan vars for generated secrets (SSH host keys, passwords)

**Example generator**:

```nix
clan.core.vars.generators.sshd = {
  script = ''
    ssh-keygen -t ed25519 -f $out/id_ed25519 -N ""
  '';
  files = {
    id_ed25519 = { secret = true; };      # Private key: /run/secrets/sshd.id_ed25519
    "id_ed25519.pub" = { secret = false; }; # Public key: accessible in nix store
  };
};
```

## Network Topology

**Zerotier mesh VPN**:

- **Controller**: cinnabar VPS (always-on, independent of darwin host power state)
- **Peers**: All machines (cinnabar + 4 darwin hosts)
- **Network ID**: Shared across all machines via clan zerotier service configuration
- **Certificate-based SSH**: SSH daemon uses certificates distributed via clan sshd service
- **Full mesh connectivity**: Any machine can reach any other machine via zerotier IP

**Topology rationale**:

- Always-on controller ensures network availability independent of workstation power state
- VPS provides stable public entry point for remote access
- Mesh topology enables direct machine-to-machine communication without routing through controller

## Type Safety

**Module system type checking**:

- All configuration values declared as options with explicit types (`types.bool`, `types.int`, `types.str`, `types.listOf`, `types.attrsOf`)
- Type checking at evaluation time catches errors before deployment
- Clear error messages reference specific options and expected types

**Dendritic optimization** (if feasible per Phase 0):

- Minimize specialArgs pass-through (only framework values: `inputs`, `self`)
- Prefer `config.flake.*` for application/user-defined values (type-checked access)
- Explicit interfaces between modules via option declarations

**Compromise acceptable**: If clan requires extensive specialArgs for flakeModules integration, document rationale and accept deviation from pure dendritic pattern.
Clan functionality is non-negotiable, dendritic optimization applied where feasible.

## CI/CD Integration

**Justfile as universal command interface**:

```justfile
# Evaluation and syntax
check:
  nix flake check

# System configuration builds
verify:
  nix build .#darwinConfigurations.blackphos.system

# Code quality
lint:
  statix check .

# Activation dry-run
activate-darwin host:
  darwin-rebuild switch --flake .#{{host}} --dry-run
```

**Local-CI parity**: CI workflows execute `nix develop -c just <command>` matching local development, ensuring reproducibility and enabling local CI failure reproduction.

---
