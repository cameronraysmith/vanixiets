---
title: System Specification
---

Comprehensive architecture specification for the vanixiets multi-machine infrastructure following AMDiRE methodology.

## Scope and Boundaries

This infrastructure manages a heterogeneous fleet of 6 permanent machines plus ephemeral cloud instances across 2 platforms with 5 users through declarative Nix configuration.
The system provides unified deployment, configuration management, secrets distribution, and cloud infrastructure provisioning for both personal workstations and cloud servers.

### System boundary

Within scope: Machine configuration management, cloud infrastructure provisioning, deployment orchestration, secrets management, package composition, and home environment configuration.

Outside scope: Application development, data processing pipelines, container orchestration, and end-user application logic.
These capabilities may run ON the infrastructure but are not managed BY the infrastructure configuration.

### Machine fleet

The infrastructure coordinates 6 permanent machines plus ephemeral cloud instances:

- 4 nix-darwin laptops: stibnite (crs58), blackphos (raquel), argentum (christophersmith), rosegold (janettesmith)
- 1 permanent nixos server: cinnabar (Hetzner VPS, zerotier coordinator)
- 1 ephemeral nixos server: electrum (Hetzner VPS, usually disabled in terranix)

Note that galena (GCP CPU) and scheelite (GCP GPU) were added as GCP infrastructure expansion, not part of the initial November 2024 validation.
All machines managed through single configuration repository with cross-platform module sharing.

### User management

The infrastructure manages 5 users across the fleet.
The crs58 user serves as global admin on machines stibnite and blackphos.
The cameron user operates as an admin alias on new machines.
The raquel user is the primary user on blackphos.
The christophersmith user is the primary user on argentum.
The janettesmith user is the primary user on rosegold.

User configurations defined once in home-manager modules, deployed across relevant machines.

### Architectural principles

Feature-based organization means defining capabilities once in aspect directories and importing them in machine configurations.
Adding AI tooling across all machines requires creating a single module, not editing multiple host files.

Explicit dependencies ensure no implicit wiring through specialArgs or hidden autowiring.
Module imports show exactly what each configuration depends on.

Separation of concerns means infrastructure provisioning (terranix), deployment orchestration (clan), system configuration (nixos/nix-darwin), and user environment (home-manager) are distinct layers with clear boundaries.

Declarative infrastructure stores all configuration in Nix expressions under version control.
Infrastructure state is derivable from repository content, not manual procedures.

Surgical fixes over system-wide rollbacks leverage multi-channel overlay architecture.
This enables stable fallbacks for broken packages without rolling back the entire nixpkgs flake.lock.

## Component Model

The infrastructure composes four major subsystems that integrate through well-defined interfaces.
These subsystems build on a three-layer foundation.

### Layer 0: Module system foundation

The nixpkgs module system provides the foundational primitives for configuration composition.
Every module in the infrastructure is a deferred module that delays evaluation until the final configuration is computed.

**Core primitives:**

- **lib.evalModules**: Fixpoint computation that resolves module definitions into final configuration
- **deferredModule type**: Delayed evaluation enabling modules to reference the final merged result
- **Option merging**: Type-specific merge functions with priority handling

This foundation explains why the deferred module composition works: deferred modules compose cleanly because they form a monoid under concatenation, and auto-discovery works because import-tree simply adds modules to the imports list without changing evaluation semantics.

See [Module System Primitives](/concepts/module-system-primitives/) for detailed explanation of deferredModule and evalModules.

### Layer 1: Flake-parts framework

Flake-parts wraps nixpkgs' evalModules for flake composition, providing ergonomic access to the module system in the flake context.

**What it provides:**

- Wraps evalModules for flake outputs (class "flake")
- Defines flake.modules.* namespace convention (deferredModule type)
- Provides perSystem abstraction (per-system evaluation with class "perSystem")

Flake-parts is NOT a module system primitive—it is a framework that makes the module system convenient for flake outputs.

### Layer 2: Deferred module composition organization

The deferred module composition organizes deferred modules by aspect rather than by host.

**What it provides:**

- Auto-discovery via import-tree (automatic imports list population)
- Directory-based namespace merging (deferredModule monoid composition)
- Aspect-oriented structure (modules organized by feature, not host)

### Deferred module composition subsystem

The module organization subsystem provides module organization and auto-discovery through deferred module composition.
Every nix file under modules/ is a flake-parts module that exports to flake.modules.* namespaces.
The import-tree mechanism by Victor Borja auto-discovers modules without manual registration.

**Directory structure**:

```
modules/
├── clan/              # Clan integration layer
├── darwin/            # nix-darwin modules (per-aspect)
├── home/              # home-manager modules (per-aspect)
├── machines/          # Machine-specific configurations
├── nixos/             # NixOS modules (per-aspect)
├── nixpkgs/           # Overlay architecture
├── system/            # Cross-platform system modules
├── terranix/          # Cloud infrastructure
└── checks/            # Validation and testing
```

**Namespace exports**: Modules export to namespaces for consumption by other modules.
Files in modules/home/ai/ export to flake.modules.homeManager.ai.
Multiple files in the same directory auto-merge into aggregates.

**Machine configuration pattern**: Machine configurations import aggregates from namespaces rather than individual files.
This enables feature-based organization where capabilities are defined once and consumed everywhere.

### Clan subsystem

The clan subsystem orchestrates deployment across the machine fleet and manages system-level secrets.
Clan provides machine registry, inventory system for service coordination, vars/generators for secret generation, and deployment tooling.

**Machine registry**: All machines registered in clan.machines.* with platform specification and configuration imports.
Registry serves as authoritative list of infrastructure members.

**Inventory system**: Service instances defined with roles assigned to specific machines.
Zerotier instance has controller role (cinnabar) and peer roles (all other machines).
User instances assign user accounts to relevant machines.

**Vars and generators (clan vars)**: System-level generated secrets including SSH host keys, zerotier network identities, LUKS/ZFS encryption passphrases, and service credentials.
Generated via clan vars generate, stored encrypted in vars/ directory with age encryption.

**Deployment tooling**: Unified command interface for installation (clan machines install), updates (clan machines update), and secret management (clan vars generate).
Same commands work across darwin and nixos platforms.

### Terranix subsystem

The terranix subsystem provisions cloud infrastructure by converting Nix module configuration to Terraform JSON.
It manages VM creation on Hetzner Cloud and GCP with toggle mechanism for cost control.

**Provider modules**: Separate modules for each cloud provider (modules/terranix/hetzner.nix, modules/terranix/gcp.nix) with shared base configuration.
Each provider defines resources, networking, and provisioning logic in Nix expressions.

**Toggle mechanism**: Boolean options control resource creation (machines.scheelite.enabled).
Disabling expensive GPU instances removes them from Terraform state without destroying configuration.
Re-enabling recreates resources from same Nix expressions.

**Clan handoff**: Terranix creates VMs with base images, clan installs NixOS and deploys configuration.
Clear separation between infrastructure provisioning and system deployment.

### Overlay composition subsystem

The overlay composition subsystem implements a five-layer nixpkgs overlay architecture.
This architecture enables surgical package fixes without system-wide flake.lock rollbacks.

**Layer 1 - Multi-channel access (modules/nixpkgs/overlays/channels.nix)**: The first layer provides pkgs.stable (OS-specific stable nixpkgs), pkgs.unstable (explicit unstable), pkgs.patched (unstable with upstream patches applied), and pkgs.nixpkgs (main unstable).

**Layer 2 - Platform-specific stable fallbacks (modules/nixpkgs/overlays/stable-fallbacks.nix)**: The second layer selectively uses stable versions for completely broken unstable packages.
Platform conditionals isolate fixes to affected systems (isDarwin, isLinux, specific architecture).

**Layer 3 - Custom packages (pkgs/by-name/)**: The third layer provides custom derivations organized in flat pkgs-by-name structure following nixpkgs RFC 140.
Packages like atuin-format, markdown-tree-parser, starship-jj auto-discovered via pkgs-by-name-for-flake-parts.

**Layer 4 - Per-package overrides (modules/nixpkgs/overlays/overrides.nix)**: The fourth layer applies build modifications using overrideAttrs for test disabling, flag changes, and compilation fixes.

**Layer 5 - External flake overlays (wrapper modules)**: The fifth layer integrates overlays from flake inputs through wrapper modules in modules/nixpkgs/overlays/.
Each wrapper module (nuenv.nix, nvim-treesitter.nix) appends external overlays to the flake.nixpkgsOverlays list for uniform composition.

**Composition order**: All overlays (internal and external) compose via lib.composeManyExtensions on the flake.nixpkgsOverlays list: channels → stable-fallbacks → overrides → external (nuenv, nvim-treesitter) → custom packages.
Later layers can reference packages from earlier layers.

## Function Model

Each subsystem provides distinct capabilities that compose to deliver the complete infrastructure.

### Deferred module composition functions

**Module auto-discovery**: The import-tree mechanism scans modules/ recursively and imports every .nix file as flake-parts module.
Adding new module requires only creating file, no flake.nix updates.

**Namespace aggregation**: Multiple files in same directory export to same namespace and auto-merge.
The files modules/home/ai/claude-code.nix + modules/home/ai/mcp-servers.nix merge into flake.modules.homeManager.ai.

**Cross-platform module sharing**: Home-manager modules work on both darwin and nixos through namespace imports.
Same flakeModulesHome.ai imported in darwin (stibnite) and nixos (cinnabar) machine configurations.

**Feature composition**: Machine configurations import aggregates rather than individual modules.
Changes to feature modules propagate automatically to all consuming machines.

### Clan-core functions

**Unified deployment**: Single command interface deploys to any machine regardless of platform.
The command clan machines update stibnite deploys to darwin laptop.
The command clan machines update cinnabar deploys to nixos server.

**Service coordination**: Inventory instances coordinate multi-machine services.
Zerotier controller on cinnabar, peers on all other machines, configured through single inventory definition.

**Secret generation**: Vars system generates machine-specific secrets automatically.
SSH host keys, zerotier identities, encryption passphrases created by clan vars generate.

**Secret distribution**: Generated secrets encrypted with age keys and distributed to machines during deployment.

**Rollback capability**: Deployment failures can roll back to previous configuration.

### Terranix functions

**Infrastructure provisioning**: Creates cloud VMs with networking, storage, and base OS.

**Cost control**: Toggle mechanism enables/disables expensive resources without destroying configuration.
Setting machines.scheelite.enabled = false removes GPU instance from terraform state.

**Multi-cloud abstraction**: Same Nix patterns work across Hetzner and GCP.
Provider differences isolated in provider modules.

**State management**: Terraform state persisted and encrypted for infrastructure tracking.

### Overlay composition functions

**Stable fallback**: Broken unstable packages use stable versions without rolling back entire nixpkgs.
Layer 2 stable fallbacks enable per-package channel selection.

**Upstream patch application**: Layer 1 patched channel applies upstream PR patches before they reach nixpkgs channel.

**Platform-specific fixes**: Conditionals in Layer 2 isolate fixes to affected systems.
Darwin-only issues don't affect linux builds.

**Custom package distribution**: Layer 3 provides packages unavailable in nixpkgs.

**Build customization**: Layer 4 modifies package builds without forking nixpkgs.

## Behavior Model

Key workflows that demonstrate how the subsystems interact to accomplish infrastructure operations.

### Machine deployment workflow

Initial machine installation from bare metal or cloud VM to fully configured system.

**Terranix provisioning (cloud machines only)**:

1. Define machine in modules/terranix/\{hetzner,gcp\}.nix with resource specification
2. Run nix build .#terraform to generate terraform JSON
3. Execute terraform apply to create cloud VM with base OS
4. Terraform provisioner waits for SSH availability
5. Handoff to clan installation

**Clan installation (all machines)**:

1. Machine registered in modules/clan/machines.nix importing configuration from namespace
2. Run clan machines install \<machine\> --target-host root@\<ip\>
3. Clan builds system configuration for target platform
4. Clan partitions disks and installs NixOS/nix-darwin
5. Clan deploys initial configuration with generated secrets
6. Machine boots into configured system

**Ongoing updates**:

1. Edit configuration in modules/
2. Commit changes to git
3. Run clan machines update \<machine\>
4. Clan builds new system configuration
5. Clan deploys to target machine
6. System switches to new configuration

### Secret distribution workflow

Managing secrets with clan vars for machine-level secrets and sops-nix for user-level secrets.

**Clan vars (machine secrets)**:

1. Define secret generators in clan vars configuration
2. Run clan vars generate to create/update secrets
3. Secrets encrypted with age keys derived from machine SSH host keys
4. Encrypted secrets stored in vars/\<machine\>/\<service\>/
5. Clan deployment decrypts and installs secrets on target machine
6. Services access secrets through standard nixos/darwin secret paths

**sops-nix (user secrets)**:

1. Create secrets/users/\<username\>.sops.yaml file
2. Edit with sops secrets/users/\<username\>.sops.yaml
3. Add secret keys and values in editor
4. Secrets encrypted with user age keys from ~/.config/sops/age/keys.txt
5. Reference secrets in home-manager modules via sops.secrets
6. Deployment decrypts secrets to home directory

**Age key management**: Both systems use age key infrastructure.
Machine keys derived from SSH host keys.
User keys stored in standard age location.

### Package fix workflow

Handling broken nixpkgs packages through overlay composition without system-wide rollbacks.

**Decision tree**: When package breaks after nixpkgs update:

1. Multiple packages affected → Consider flake.lock rollback, then selective stable fallbacks
2. Upstream fix exists in PR → Use Layer 1 patches (infra/patches.nix)
3. Package completely broken → Use Layer 2 stable fallbacks (stable fallback)
4. Package builds but has issues → Use Layer 4 overrides (build modifications)

**Stable fallback (Layer 2)**:

1. Edit modules/nixpkgs/overlays/stable-fallbacks.nix
2. Add package to appropriate platform conditional (isDarwin, isLinux)
3. Document with hydra link and removal condition
4. Test with nix eval .#legacyPackages.\<system\>.\<package\>.name
5. Commit change
6. Remove when upstream fix lands in unstable

**Upstream patch (Layer 1)**:

1. Identify upstream PR with fix
2. Add patch URL to modules/nixpkgs/overlays/channels.nix patches list
3. Get hash from nix build failure output
4. Reference patched package in stable-fallbacks: inherit (final.patched) packageX;
5. Test with nix build
6. Commit change
7. Remove when PR merges and reaches channel

**Build modification (Layer 4)**:

1. Edit modules/nixpkgs/overlays/overrides.nix
2. Add package = prev.package.overrideAttrs customization
3. Document issue, reference, TODO, date added
4. Test with nix build
5. Commit change
6. Remove when upstream fixes build issues

### Service coordination workflow

Deploying multi-machine services through clan inventory.

**Zerotier VPN mesh**:

1. Define inventory instance in modules/clan/inventory/services/zerotier.nix
2. Assign controller role to cinnabar
3. Assign peer roles to all other machines
4. Deploy clan configuration to all machines
5. Controller generates zerotier network
6. Peers join network using generated identities
7. VPN mesh operational across fleet

**User account distribution**:

1. Create user module in modules/home/users/\<username\>.nix
2. Define inventory instance in modules/clan/inventory/services/user-\<username\>.nix
3. Assign user to relevant machines
4. Deploy configuration updates
5. User accounts created with home directories and SSH access
6. User home-manager configuration applied

### Infrastructure scaling workflow

Adding new machines to the fleet.

**Cloud machine**:

1. Add resource definition to modules/terranix/\{hetzner,gcp\}.nix
2. Run terraform apply to provision VM
3. Create machine module at modules/machines/nixos/\<hostname\>/default.nix
4. Export to namespace: flake.modules.nixos."machines/nixos/\<hostname\>"
5. Register in modules/clan/machines.nix importing from namespace
6. Add to relevant inventory services (zerotier, ssh-known-hosts, users)
7. Run clan machines install \<hostname\> --target-host root@\<ip\>
8. Machine joins fleet with full configuration

**Local machine (darwin laptop)**:

1. Create machine module at modules/machines/darwin/\<hostname\>/default.nix
2. Export to namespace: flake.modules.darwin."machines/darwin/\<hostname\>"
3. Register in modules/clan/machines.nix importing from namespace
4. Add to relevant inventory services
5. Bootstrap with nix-darwin on local machine
6. Run clan machines update \<hostname\> for subsequent updates
7. Machine integrated into fleet management

## Interface Model

Integration points where subsystems exchange data and coordinate behavior.

### Deferred module composition to clan interface

**Namespace export → clan import pattern**: Machine modules export to flake.modules.\{darwin,nixos\}.* namespaces.
Clan registry (modules/clan/machines.nix) imports from these namespaces.

Integration point: config.flake.modules.\{darwin,nixos\}."machines/\{darwin,nixos\}/\<hostname\>"

This two-step registration enables auto-discovery while maintaining explicit clan registry control.

**ClanModules importing modules**: Clan inventory instances can import shared configuration from namespaces.
Service modules reference config.flake.modules.common.* for cross-machine shared configuration.

Integration point: clan.inventory.instances.\<service\>.module imports from namespaces.

### Terranix to clan interface

**Infrastructure provisioning to deployment handoff**: Terranix provisions cloud VMs with base OS (Ubuntu).
Terraform provisioner waits for SSH availability.
Clan installation deploys NixOS over base OS.

Integration point: Terraform provisioner.local-exec executes clan machines install.

**Output coordination**: Terranix outputs (IP addresses, resource IDs) available for clan configuration.
Machine networking configured using terraform output values.

Integration point: Terraform output variables consumed in nix configuration.

### Overlay to system interface

**Composed overlay to machine configuration**: The file modules/nixpkgs/compose.nix composes all overlays from the flake.nixpkgsOverlays list (populated by wrapper modules in overlays/*.nix) into flake.overlays.default.
Machine configurations import inputs.self.overlays.default.

Integration point: Machine nixpkgs.overlays = [ inputs.self.overlays.default ];

**perSystem packages to overlay**: Custom packages from Layer 3 (pkgs/by-name/) flow through perSystem.packages.
The file compose.nix integrates custom packages using withSystem pattern.

Integration point: customPackages = withSystem prev.stdenv.hostPlatform.system ({ config, ... }: config.packages or {});

### Secrets interfaces

**Clan vars to machine deployment**: Vars system generates secrets during clan vars generate.
Secrets encrypted with machine age keys derived from SSH host keys.
Deployment decrypts secrets to machine paths.

Integration point: clan.core.facts and age decryption during activation.

**sops-nix to home-manager**: User secrets defined in secrets/users/\<username\>.sops.yaml.
Home-manager modules reference sops.secrets."\<path\>".
Deployment decrypts secrets to home directory.

Integration point: sops.secrets configuration in home-manager modules.

**Age key infrastructure**: Both clan vars and sops-nix use age encryption with shared key infrastructure.
Machine keys: Derived from SSH host keys via ssh-to-age.
User keys: Stored in ~/.config/sops/age/keys.txt.

Integration point: .sops.yaml defines age keys for both systems.

## Data Model

Configuration flow from Nix expressions through evaluation to deployed system state.

### Configuration layers

**Source layer (git repository)**: Nix expressions in modules/, pkgs/, and configuration files.
Version controlled, human-editable, declarative specifications.

**Evaluation layer (nix evaluation)**: Nix expressions evaluated to attribute sets.
Auto-discovery imports modules.
Flake-parts composition merges configurations.
Overlays compose packages.

**Build layer (nix build)**: Evaluated configurations build derivations.
System closures assembled with all dependencies.
Packages built with overlay modifications applied.

**Deployment layer (clan/nix-darwin)**: Built system closures deployed to target machines.
Secrets decrypted and installed.
System activation switches to new configuration.

**Runtime layer (running system)**: Deployed configuration active on machine.
Services running, packages available, secrets accessible.

### Configuration flow

Nix expressions → import-tree auto-discovery → flake-parts composition → overlay application → system build → clan deployment → runtime activation.

Each layer transforms data: Source (text) → Evaluation (attribute sets) → Build (derivations) → Deployment (system closure) → Runtime (active system).

### Namespace data structure

**Modules export to structured namespaces**:

```nix
flake.modules = {
  darwin = {
    base = { ... };
    ssh-known-hosts = { ... };
    "machines/darwin/stibnite" = { ... };
  };
  nixos = {
    core = { ... };
    services = { ... };
    "machines/nixos/cinnabar" = { ... };
  };
  homeManager = {
    ai = { ... };
    core = { ... };
    development = { ... };
    "users/crs58" = { ... };
  };
};
```

Machine configurations traverse this structure via config.flake.modules.* to access aggregates.

### Overlay composition data flow

```
inputs (flake inputs)
  ↓
overlays/*.nix wrapper modules append to flake.nixpkgsOverlays list:
  ├─ channels.nix (Layer 1): Export stable/unstable/patched nixpkgs
  ├─ stable-fallbacks.nix (Layer 2): Selective stable fallbacks
  ├─ overrides.nix (Layer 4): Package build modifications
  ├─ nuenv.nix (Layer 5): External nuenv overlay
  └─ nvim-treesitter.nix (Layer 5): External nvim-treesitter overlay
  ↓
compose.nix: lib.composeManyExtensions config.flake.nixpkgsOverlays
  ↓
custom packages (Layer 3): pkgs/by-name/ derivations merged via //
  ↓
composed overlay (flake.overlays.default)
  ↓
machine nixpkgs (final package set)
```

Internal and external overlays compose uniformly via lib.composeManyExtensions on flake.nixpkgsOverlays.
Custom packages merge last using attribute set merge (//).

### Secrets data flow

**Clan vars**:

```
Generator specification (nix)
  ↓
clan vars generate
  ↓
Generated secrets (plaintext)
  ↓
Age encryption (machine keys)
  ↓
Encrypted storage (vars/<machine>/<service>/)
  ↓
clan deployment
  ↓
Age decryption (on target)
  ↓
Secret installation (/run/secrets/*)
  ↓
Service access (via paths)
```

**Legacy sops-nix**:

```
Manual secret creation (sops editor)
  ↓
Age encryption (user keys)
  ↓
Encrypted storage (secrets/users/<username>.sops.yaml)
  ↓
home-manager deployment
  ↓
sops-nix decryption (on target)
  ↓
Secret installation (home directory)
  ↓
User access (via sops.secrets paths)
```

## Architecture Decisions

Summary of major architectural decisions with links to detailed ADRs.

### Development environment

| Decision | ADR | Status | Impact |
|----------|-----|--------|--------|
| Claude Code multi-profile system | [ADR-0001](/development/architecture/adrs/0001-claude-code-multi-profile-system/) | Accepted | AI-assisted development workflow |
| Generic just recipes | [ADR-0002](/development/architecture/adrs/0002-use-generic-just-recipes/) | Accepted | Task automation patterns |
| Nix flake-based development | [ADR-0009](/development/architecture/adrs/0009-nix-development-environment/) | Accepted | Reproducible dev environment |

### Nix configuration

| Decision | ADR | Status | Impact |
|----------|-----|--------|--------|
| Dendritic overlay patterns | [ADR-0017](/development/architecture/adrs/0017-dendritic-overlay-patterns/) | Accepted | Five-layer overlay composition |
| Overlay composition patterns | [ADR-0003](/development/architecture/adrs/0003-overlay-composition-patterns/) | Superseded | Replaced by ADR-0017 |

### Fleet architecture

| Decision | ADR | Status | Impact |
|----------|-----|--------|--------|
| Dendritic flake-parts | [ADR-0018](/development/architecture/adrs/0018-dendritic-flake-parts-architecture/) | Accepted | Feature-based module organization |
| Clan-core orchestration | [ADR-0019](/development/architecture/adrs/0019-clan-core-orchestration/) | Accepted | Multi-machine deployment |
| Dendritic + Clan integration | [ADR-0020](/development/architecture/adrs/0020-dendritic-clan-integration/) | Accepted | Namespace export → clan import pattern |
| Terranix provisioning | [ADR-0021](/development/architecture/adrs/0021-terranix-infrastructure-provisioning/) | Accepted | Cloud infrastructure in Nix |

### Security

| Decision | ADR | Status | Impact |
|----------|-----|--------|--------|
| SOPS secrets management | [ADR-0011](/development/architecture/adrs/0011-sops-secrets-management/) | Accepted | User-level secrets (legacy) |

### Testing

| Decision | ADR | Status | Impact |
|----------|-----|--------|--------|
| Testing architecture | [ADR-0010](/development/architecture/adrs/0010-testing-architecture/) | Accepted | Validation approach |

### CI/CD

| Decision | ADR | Status | Impact |
|----------|-----|--------|--------|
| GitHub Actions pipeline | [ADR-0012](/development/architecture/adrs/0012-github-actions-pipeline/) | Accepted | Continuous integration |
| Per-job content-addressed caching | [ADR-0016](/development/architecture/adrs/0016-per-job-content-addressed-caching/) | Accepted | CI optimization |
| CI caching optimization | [ADR-0015](/development/architecture/adrs/0015-ci-caching-optimization/) | Superseded | Replaced by ADR-0016 |

### Monorepo

| Decision | ADR | Status | Impact |
|----------|-----|--------|--------|
| Monorepo structure | [ADR-0004](/development/architecture/adrs/0004-monorepo-structure/) | Accepted | Repository organization |
| Semantic versioning | [ADR-0005](/development/architecture/adrs/0005-semantic-versioning/) | Accepted | Release management |
| Monorepo tag strategy | [ADR-0006](/development/architecture/adrs/0006-monorepo-tag-strategy/) | Accepted | Git tagging conventions |
| Bun workspaces | [ADR-0007](/development/architecture/adrs/0007-bun-workspaces/) | Accepted | TypeScript monorepo |
| TypeScript configuration | [ADR-0008](/development/architecture/adrs/0008-typescript-configuration/) | Accepted | Type safety patterns |

### Deployment

| Decision | ADR | Status | Impact |
|----------|-----|--------|--------|
| Cloudflare Workers | [ADR-0013](/development/architecture/adrs/0013-cloudflare-workers-deployment/) | Accepted | Serverless deployment |

### Philosophy

| Decision | ADR | Status | Impact |
|----------|-----|--------|--------|
| Design principles | [ADR-0014](/development/architecture/adrs/0014-design-principles/) | Accepted | Architectural philosophy |

## Traceability

Links to implementation artifacts demonstrating how architectural decisions manifest in code.

### Module organization implementation

Module auto-discovery: flake.nix imports inputs.import-tree.flakeModule and configures flake.autoImport.

Namespace exports: All modules/ files define flake.modules.* exports.

Machine configurations: modules/machines/darwin/ and modules/machines/nixos/ export to namespaces.

Home aggregates: modules/home/ organized by aspect with auto-merging exports.

### Clan implementation

Machine registry: modules/clan/machines.nix defines clan.machines.* with imports from namespaces.

Inventory instances: modules/clan/inventory/services/ defines service coordination.

Vars configuration: clan vars definitions in machine modules and inventory.

Deployment scripts: justfile contains clan machines install/update wrappers.

### Terranix implementation

Provider modules: modules/terranix/hetzner.nix and modules/terranix/gcp.nix define cloud resources.

Toggle options: machines.\<hostname\>.enabled options control resource creation.

Terraform output: perSystem.packages.terraform generates terraform JSON.

### Overlay implementation

Layer 1 channels: modules/nixpkgs/overlays/channels.nix exports stable/unstable/patched.

Layer 2 stable fallbacks: modules/nixpkgs/overlays/stable-fallbacks.nix with platform conditionals.

Layer 3 custom packages: pkgs/by-name/ with pkgs-by-name-for-flake-parts integration.

Layer 4 overrides: modules/nixpkgs/overlays/overrides.nix with overrideAttrs patterns.

Layer 5 external: modules/nixpkgs/overlays/nuenv.nix and nvim-treesitter.nix wrapper modules append external overlays to flake.nixpkgsOverlays.

Composition: modules/nixpkgs/compose.nix defines flake.overlays.default.

### Secrets implementation

Clan vars: vars/ directory with encrypted generated secrets.

sops-nix: secrets/users/ with encrypted user credentials.

Age keys: .sops.yaml defines machine and user age keys.

Home-manager secrets: modules/home/ modules reference sops.secrets.

## Architectural Foundation

The architecture rests on patterns validated through phased implementation.

### Pattern validation (November 2024)

Pattern validation in test-clan repository established viability before production adoption.

Validated module organization structure, clan integration, cross-platform modules, secrets distribution, and physical deployment.

Metrics: 83 auto-discovered modules, 23-line minimal flake.nix, 270 packages preserved across migration, all 7 patterns rated HIGH confidence in validation decision.

### Production adoption (November 2024)

Production infrastructure implemented using validated patterns.

All machines deployed with deferred module composition + clan architecture.
Darwin workstations (stibnite, blackphos) and NixOS VPS (cinnabar, electrum) operational.
New machines (rosegold, argentum) created using established patterns.

Result: 6-machine permanent fleet operational under unified architecture (galena and scheelite added December 2024).

### GCP infrastructure expansion (December 2024)

GCP infrastructure integration extended the architecture.

Terranix GCP support deployed CPU (galena) and GPU (scheelite) instances.
Toggle mechanism validated with expensive GPU resources.

Metrics: 172-line GCP terranix module, GPU instance operational, 10 patterns established for GCP integration.

### Continuous validation

CI/CD pipeline validates nix flake check, builds, and tests on every commit.
Per-job content-addressed caching optimizes CI without sacrificing validation.

## Architecture Evolution

### From nixos-unified to deferred module composition + clan

November 2024 architectural evolution addressing scalability and composability.

**Previous limitations**: specialArgs anti-pattern created implicit dependencies.
Host-centric organization led to duplication across machines.
Limited module composition for cross-cutting concerns.

**Current architecture**: Feature-based organization eliminates duplication.
Explicit imports make dependencies visible.
Auto-discovery scales gracefully to 100+ modules.
Cross-platform consistency across darwin and nixos.

**Transition approach**: Patterns validated in test-clan repository.
Production infrastructure adopted patterns November 2024.
Zero downtime for critical services (zerotier, VPN).

### From three-layer to five-layer overlays

December 2024 overlay architecture enhancement for improved composability.

**Previous architecture (ADR-0003)**: The file inputs.nix provided multi-channel access.
The file infra/stable-fallbacks.nix provided platform fixes.
The directory packages/ contained custom derivations.
All nested in overlays/ directory.

**Current architecture (ADR-0017)**: Overlays organized in modules/nixpkgs/overlays/.
pkgs-by-name pattern for custom packages.
List concatenation pattern for external overlays.
Layer 4 overrides for build modifications.
Explicit Layer 5 external overlay composition.

**Preserved patterns**: Multi-channel stable fallback mechanism.
Hydra documentation conventions.
Platform-specific conditionals.

## Future Directions

### Test coverage expansion

Validation currently relies on nix flake check and manual deployment testing.
ADR-0010 testing architecture provides foundation for expanded coverage.

Planned: nix-unit integration for pure function testing, per-module validation in CI, deployment dry-run testing, cross-platform build verification.

### Darwin clan support

Current limitation: clan zerotier module is NixOS-specific with systemd dependencies.
Darwin machines use homebrew + activation script workaround (101-line module).

Future: Upstream darwin support in clan zerotier module, native clan deployment for darwin machines, unified service patterns across platforms.

### Documentation generation

Current documentation manually maintained in packages/docs/.
Opportunity for automation from module structure.

Future: Auto-generated module documentation from namespace exports, dependency graph visualization from imports, architectural diagrams from code structure, API reference from option definitions.

### Secrets management evolution

Current architecture uses clan vars for machine secrets and sops-nix for user secrets.

Future: Automated secret rotation, secrets validation in CI, emergency access patterns for disaster recovery.

## References

### Internal documentation

- [Deferred Module Composition concept documentation](/concepts/deferred-module-composition)
- [Clan Integration concept documentation](/concepts/clan-integration)
- [Architecture Decision Records](/development/architecture/adrs/)
- [Handling Broken Packages guide](/guides/handling-broken-packages)

### External references

- [dendritic pattern](https://github.com/mightyiam/dendritic) - Organizational pattern
- [import-tree](https://github.com/vic/import-tree) - Auto-discovery mechanism
- [dendrix documentation](https://vic.github.io/dendrix/Dendritic.html) - Pattern documentation
- [flake.parts](https://flake.parts) - Foundation framework
- [clan](https://github.com/clan-lol/clan-core) - Orchestration system
- [Clan documentation](https://clan.lol/) - Official clan docs
- [terranix](https://terranix.org/) - Infrastructure provisioning
- [nixpkgs RFC 140](https://github.com/NixOS/rfcs/pull/140) - pkgs-by-name pattern
- [pkgs-by-name-for-flake-parts](https://github.com/drupol/pkgs-by-name-for-flake-parts) - Integration library

### Reference implementations

- [drupol-dendritic-infra](https://github.com/drupol/nixos-config) - Dendritic reference
- [mightyiam-dendritic-infra](https://github.com/mightyiam/nix-config) - Pattern creator config
- [gaetanlepage-dendritic-nix-config](https://github.com/GaetanLepage/nix-config) - Reference implementation
- [clan-infra](https://git.clan.lol/clan/clan-infra) - Production clan reference
- [nixpkgs.molybdenum.software-dendritic-clan](https://github.com/nixpkgs-community/nixpkgs.molybdenum.software) - Dendritic + clan combination

### Related specifications

- [Context](/development/context/) - Problem domain and objectives
- [Requirements](/development/requirements/) - System requirements
