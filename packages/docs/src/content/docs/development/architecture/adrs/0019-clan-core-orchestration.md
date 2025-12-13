---
title: "ADR-0019: Clan-Core Orchestration"
---

- **Status**: Accepted
- **Date**: 2024-11-20
- **Scope**: Multi-machine coordination and deployment
- **Related**: [ADR-0011: SOPS secrets management](0011-sops-secrets-management/), [ADR-0018: Deferred module composition architecture](0018-deferred-module-composition-architecture/)

## Context

This infrastructure manages a heterogeneous fleet of 8 machines across 2 platforms (4 darwin laptops, 4 nixos servers) with 5 users.
Multi-machine coordination requires unified deployment, secrets management, and service orchestration.

### Coordination requirements

Machine fleet composition:
- 4 darwin laptops: stibnite, blackphos, rosegold, argentum
- 2 Hetzner VPS: cinnabar (zerotier controller), electrum
- 2 GCP instances: galena (CPU), scheelite (GPU)
- Cross-platform: darwin (aarch64-darwin) and linux (x86_64-linux)

Deployment needs:
- Unified command interface for all machines
- Initial installation (bare metal or VM)
- Configuration updates across fleet
- Rollback capability

Secrets management needs:
- SSH host key generation per machine
- Zerotier network identities
- LUKS/ZFS encryption passphrases
- Service-specific credentials
- Multi-user secrets isolation

Service coordination needs:
- Zerotier VPN mesh (controller + peers)
- User accounts across machines
- SSH known hosts synchronization
- Emergency access patterns

### Prior approach limitations

Before clan, multi-machine coordination required:
- Manual deployment scripts per machine
- Separate secrets management (sops-nix only, no generated secrets)
- Ad-hoc service coordination
- No inventory abstraction

## Decision

Adopt **clan** for multi-machine orchestration, secrets generation, and service coordination.

### Mental model: Kubernetes for NixOS

Understanding clan's role requires drawing an analogy to Kubernetes in the container ecosystem.
Kubernetes orchestrates containers across a cluster but doesn't replace Docker - it uses Docker (or other runtimes) to actually run the containers.
Similarly, clan orchestrates NixOS deployments across machines but doesn't replace the NixOS module system or home-manager - it uses these tools to actually build and activate configurations.
This separation of concerns means clan handles the coordination layer (which machine gets which configuration, how secrets are distributed, how services discover each other) while the underlying module system handles the configuration layer (what packages are installed, which services are enabled, how they're configured).
The distinction becomes clearer when considering that clan's inventory system answers "which machines run the zerotier controller versus peers" while NixOS modules answer "what zerotier configuration does each role need."

### What clan manages

Machine registry via `clan.machines.*`:

```nix
# modules/clan/machines.nix
clan.machines = {
  stibnite = {
    nixpkgs.hostPlatform = "aarch64-darwin";
    imports = [ config.flake.modules.darwin."machines/darwin/stibnite" ];
  };
  cinnabar = {
    nixpkgs.hostPlatform = "x86_64-linux";
    imports = [ config.flake.modules.nixos."machines/nixos/cinnabar" ];
  };
};
```

**Module system integration**:
The clan machine registry imports deferred modules from the `flake.modules.*` namespaces.
These are deferredModule type (nixpkgs `lib/types.nix` primitive) that delay evaluation until the configuration is computed.
When clan calls nixosSystem or darwinSystem for a machine, it triggers evalModules with the imported modules from the machine's imports list.
The deferred evaluation resolves at that point with system-specific arguments—the final configuration, pkgs, lib, and other module arguments become available.
This explains the seamless integration: dendritic exports deferred modules to namespaces, clan imports those modules into machine configurations, and the module system's fixpoint computation handles evaluation with the appropriate context for each platform.

Inventory system via `clan.inventory.*`:

```nix
# modules/clan/inventory/services/zerotier.nix
inventory.instances.zerotier = {
  roles.controller.machines."cinnabar" = { };
  roles.peer.machines = {
    "electrum" = { };
    "stibnite" = { };
    "blackphos" = { };
  };
};
```

Vars and generators (clan vars):
- SSH host keys
- Zerotier network identities
- LUKS/ZFS encryption passphrases
- Service-specific credentials

Generated via `clan vars generate`, stored encrypted in `vars/` directory.

Deployment tooling:
- `clan machines install <machine>` - Initial installation
- `clan machines update <machine>` - Configuration updates
- `clan vars generate` - Generate/regenerate secrets

### What clan does NOT manage

| Capability | Managed by | Relationship to clan |
|------------|------------|---------------------|
| Cloud infrastructure provisioning | **Terranix/Terraform** | Clan deploys TO infrastructure that terranix creates |
| User environment configuration | **Home-Manager** | Deployed WITH clan, not BY clan |
| User-level secrets | **sops-nix (legacy)** | User secrets during migration to clan vars |
| NixOS/darwin system configuration | **NixOS modules** | Clan imports and deploys configs, doesn't define them |
| Nixpkgs overlays and config | **Flake-level** | Outside clan scope entirely |

### Secrets management with clan vars

This infrastructure uses clan vars for all secrets with legacy sops-nix during migration.
Clan vars handles machine-level secrets that are generated automatically and tied to specific machines - these are the foundational identities like SSH host keys and zerotier network membership tokens that a machine needs to participate in the fleet.
When you run `clan vars generate`, clan's generator system creates these secrets deterministically based on templates, then encrypts them using age keys and stores them in the `vars/` directory.
This automation eliminates the manual key management burden for foundational secrets that would be tedious and error-prone to create by hand across 8 machines.

Legacy sops-nix handles user-level secrets that are manually created via sops and represent human-controlled credentials like GitHub personal access tokens, API keys, and signing keys.
These secrets live in the `secrets/` directory and are managed through the standard sops workflow - you edit `secrets/users/username.sops.yaml` with the sops CLI, which handles encryption using the same age keys.
The separation between clan vars and sops-nix prevents lifecycle conflicts (clan won't regenerate your API keys, and sops won't try to template-generate machine identities) and keeps concerns separated (machine infrastructure versus user identity).

See [ADR-0011](0011-sops-secrets-management/) for sops-nix implementation details.

### Service orchestration pattern

Services coordinated via inventory instances:

```nix
# Zerotier with controller/peer roles
inventory.instances.zerotier = {
  roles.controller.machines."cinnabar" = { };
  roles.peer.machines."stibnite" = { };
};

# User with default role across machines
inventory.instances.user-cameron = {
  roles.default.machines = {
    "cinnabar" = { };
    "galena" = { };
    "scheelite" = { };
  };
};
```

Each service instance can have multiple roles assigned to different machines.
Clan modules handle the coordination logic.

## Alternatives considered

### colmena

Colmena provides robust deployment orchestration and was a serious contender, but its architecture required maintaining two separate systems for concerns that clan-core unifies.
Colmena handles deployment well but doesn't provide an inventory abstraction for service coordination - we would need to manually track which machines run the zerotier controller versus peers, and ensure that peer configurations know how to discover the controller.
For an 8-machine fleet with services like zerotier VPN spanning darwin laptops and nixos servers, this bookkeeping burden would be significant.
Colmena's secrets management also requires fully separate sops-nix setup rather than integrating generated secrets (SSH host keys, machine identities) into the deployment workflow.
The lack of a vars/generators system means we'd be manually creating and distributing machine identities, which doesn't scale well to 8 machines and introduces opportunities for human error.

### deploy-rs

Deploy-rs focuses narrowly on the deployment mechanics - it excels at reliably pushing configurations to machines and activating them, but stops there.
For this fleet's coordination needs, we would need to build the orchestration layer ourselves on top of deploy-rs.
The zerotier network coordination requires machines to discover each other's roles and configure themselves accordingly, and deploy-rs provides no inventory concept to express "cinnabar is the controller, these 7 other machines are peers."
Secret management would also require a completely separate system, and we'd still need to solve the generated secrets problem (SSH host keys for 8 machines) through some other mechanism.
While deploy-rs is simpler than clan in some ways, that simplicity comes from not solving problems we actually have.

### morph

Morph was eliminated primarily due to its lack of darwin support - with 4 darwin laptops in the fleet, requiring a separate deployment mechanism for half the machines would fragment the operational model.
Beyond the cross-platform issue, morph doesn't provide the inventory abstraction that this fleet needs for service coordination.
The project also sees less active development compared to clan, and while that doesn't automatically disqualify a tool, it matters when you need ecosystem support for integration with newer tools like dendritic flake-parts patterns.
Unlike the clan ecosystem with documented production deployments (clan-infra coordinating multiple Hetzner VPS, qubasa's dotfiles managing personal infrastructure, mic92's multi-machine research environment, pinpox's homelab setup), morph lacks examples of darwin + nixos fleet coordination that this infrastructure requires.
The clan examples demonstrate proven patterns for exactly this use case - heterogeneous fleets with cross-platform coordination - while morph examples focus primarily on homogeneous NixOS deployments.

### Manual coordination

Manual deployment scripts worked adequately when the fleet consisted of 2 machines, but scaling to 8 machines exposed the coordination complexity.
Keeping zerotier network configuration synchronized across machines meant manually editing configuration files to ensure peers knew the controller's identity and the controller's config included all peer public keys.
Adding a new machine to the VPN required touching multiple configuration files across multiple machines, and mistakes were only discovered at deployment time.
Secret management became particularly problematic - generating SSH host keys for each machine, distributing zerotier identity files, managing LUKS passphrases - all required manual workflows that were tedious and error-prone.
The lack of declarative service coordination meant no single source of truth for "which services run on which machines," making it difficult to reason about the fleet's intended state versus its actual state.

### NixOps

NixOps was not evaluated deeply because its stateful deployment model conflicts with this infrastructure's preference for stateless, git-tracked configuration.
NixOps maintains deployment state in a database that must be carefully preserved and backed up, introducing an additional failure mode and coordination burden.
The project has also seen reduced development activity compared to newer alternatives like clan and deploy-rs, and its architecture predates many modern NixOS patterns like flakes and flake-parts.
Clan-core's stateless approach - where all configuration lives in git and deployment state is ephemeral - aligns better with the infrastructure's goal of maintaining a single source of truth in version control.

## Consequences

### Positive

Clan-core provides a unified deployment interface that treats all machines identically regardless of platform or location.
Running `clan machines update stibnite` to deploy to a darwin laptop on the local network uses the same command structure and workflow as `clan machines update cinnabar` to deploy to a remote nixos VPS.
This uniformity eliminates the cognitive overhead of remembering different deployment procedures for different machine types, and ensures that operational knowledge transfers cleanly across the entire fleet.
The operational simplification becomes particularly valuable during incident response - there's one deployment pattern to remember under pressure, not eight different approaches for eight different machines.

The generated secrets system eliminates the manual key management burden that plagued the pre-clan architecture.
When adding a new machine to the fleet, `clan vars generate` creates the SSH host keys, zerotier network identity, and other foundational secrets automatically based on templates defined in the clan configuration.
This automation prevents the common mistake of forgetting to generate a required secret until deployment fails, and ensures secrets follow a consistent format across all machines.
The secrets architecture complements this automation by keeping machine-generated secrets clearly separated from human-managed credentials during the migration from legacy sops-nix.
Clan vars handles the machine identity lifecycle while sops-nix handles user credentials, and this separation prevents lifecycle conflicts - clan won't regenerate your API keys, and sops won't try to auto-generate machine identities.
Each system is optimized for its use case, and there's no ambiguity about which system manages which secrets.

Service inventory provides the abstraction layer this fleet needs for multi-machine coordination.
The zerotier VPN configuration demonstrates the pattern clearly - the inventory declaratively defines "cinnabar is the controller, these 7 machines are peers," and the clan zerotier module consumes that declaration to generate the appropriate configuration for each machine.
Adding a new machine to the VPN requires one line in the inventory file rather than editing configuration on multiple machines to update peer lists and controller assignments.
This declarative coordination scales naturally - the complexity of adding machine 9 is identical to the complexity of adding machine 2, whereas manual coordination complexity grows quadratically with fleet size.

The architecture benefits from clan's active development by Chaos Computer Club members and the growing ecosystem of clan modules.
Regular releases provide new features and bug fixes, and the responsive issue handling means blockers can be resolved quickly.
More importantly, clan is built as a flake-parts module, which means it integrates naturally with the dendritic pattern this infrastructure uses.
The clan machine registry consumes the same namespace exports (`flake.modules.darwin.*`, `flake.modules.nixos.*`) that the dendritic organization produces, creating seamless architectural coherence without impedance mismatch between layers.

### Negative

Darwin support requires workarounds because clan's zerotier module assumes systemd, which doesn't exist on darwin platforms.
The 4 darwin laptops in this fleet (stibnite, blackphos, rosegold, argentum) cannot use clan's native zerotier module and instead rely on a custom 101-line workaround that combines homebrew package installation with activation scripts to start the zerotier daemon.
This workaround functions reliably in practice - all darwin machines maintain stable zerotier connections - but it represents platform-specific complexity that wouldn't exist if clan provided darwin-native modules.
More problematically, the workaround requires maintenance when clan updates its zerotier abstractions, and contributors working on darwin configurations must understand both the standard clan patterns and the darwin-specific deviations.

The clan abstractions (inventory, vars, generators) impose a learning curve that compounds the flake-parts learning investment required by the dendritic pattern.
Contributors must understand how the inventory system maps services to machines (`roles.controller.machines."cinnabar"`), how vars generators create secrets from templates, and how the secrets architecture divides responsibilities between clan vars (machine identities) and sops-nix (user credentials during migration).
While clan documentation has improved substantially during 2024, it remains less comprehensive than NixOS module documentation - many patterns are documented primarily through example configurations rather than thorough conceptual guides.
This means new contributors face a steeper ramp-up period before they can confidently modify clan configurations or add new machines to the inventory.

Vars encryption ties secret lifecycle to age key management, which introduces operational risk if keys are lost or compromised.
The vars system encrypts all generated secrets using age keys that are stored in `vars/` and must be carefully backed up.
These are the same age keys used by sops-nix for user-level secrets, which provides consistency but also means a single key management failure affects both the clan vars and legacy sops-nix systems.
If age keys are lost, all vars-managed secrets must be regenerated, which for this fleet means recreating SSH host keys (breaking known_hosts), regenerating zerotier network identities (breaking VPN connectivity), and potentially recreating LUKS/ZFS passphrases (preventing disk access).
The vars system provides no key recovery mechanism - the encryption is designed to be unbreakable, which is exactly what makes key loss catastrophic.

Deployment requires network access to target machines, which creates operational dependencies that can block urgent updates.
Running `clan machines update cinnabar` requires SSH connectivity to cinnabar, and if the zerotier VPN is down or the target machine is unreachable, deployment cannot proceed.
This contrasts with alternative deployment models where configurations could be prepared offline and applied later when connectivity is restored.
For this fleet's remote VPS infrastructure (cinnabar and electrum on Hetzner, galena and scheelite on GCP), the zerotier network must be operational to reach machines, which creates a bootstrapping challenge - if zerotier configuration breaks, deploying the fix requires zerotier to be working.
The solution requires maintaining out-of-band SSH access through cloud provider consoles, but this represents an additional operational burden and potential failure mode.

### Neutral

Terranix continues to handle cloud infrastructure provisioning, operating at a layer below clan's orchestration concerns.
Clan deploys configurations to VMs but doesn't create those VMs - terranix/terraform handles the infrastructure provisioning (Hetzner VPS creation, GCP instance configuration, network setup), and clan treats the resulting machines as deployment targets.
This separation of concerns is architecturally clean - terranix answers "what infrastructure exists" while clan answers "what configuration does each machine run."
The boundary is well-defined and creates no impedance mismatch - terranix creates machines and outputs their SSH connection details, clan consumes those details to deploy configurations.
However, this does mean contributors need to understand both systems and their interaction, as adding a new machine requires terranix changes (create the infrastructure) followed by clan changes (add to inventory and deploy configuration).

Home-manager configurations remain unchanged in their definition and authoring - they're still standard home-manager modules defined in the dendritic module structure.
Clan's role is purely deployment - it imports and deploys the full system configuration including home-manager, but provides no home-manager-specific abstractions or integration beyond that.
User environment configuration continues to be written using standard home-manager patterns, and clan simply ensures those configurations are activated on the appropriate machines.
This means home-manager expertise remains directly applicable - contributors don't need to learn clan-specific approaches to home-manager configuration, they just write normal home-manager modules in the dendritic structure and clan handles the deployment mechanics.

NixOS modules similarly remain standard NixOS modules in their implementation, with clan providing deployment orchestration rather than configuration abstraction.
System configuration continues to use the NixOS module system with its familiar option declarations, configuration merging, and module composition patterns.
Clan imports these modules (via the dendritic namespace exports) and deploys the resulting configurations, but the modules themselves are written using pure NixOS module patterns.
This architectural separation means NixOS module authoring skills transfer directly - a contributor who understands NixOS modules can immediately work on this infrastructure's system configurations without learning clan-specific configuration patterns.
Clan's contribution is the inventory abstraction for coordinating which machines receive which modules, not in how those modules are written.

## Validation evidence

### Initial validation (November 2024)

Clan validated in test-clan repository:

- Clan inventory configured for Hetzner VMs
- VM deployment via clan (`clan machines install hetzner-vm`)
- Zerotier network coordination (controller + peer roles)
- User management via clan inventory pattern
- Heterogeneous deployment (darwin + nixos)

Validation metrics:
- 3 machines operational (cinnabar, electrum, blackphos)
- Zerotier network db4344343b14b903 coordinated

### Production deployment (November 2024)

Production deployment:

- Darwin workstations deployed via clan
- VPS deployment switched to clan
- New machines added to inventory

### GCP infrastructure (December 2024)

GCP infrastructure:

- GCP nodes integrated into clan inventory
- GPU compute (scheelite) orchestrated via clan

Result: 8-machine fleet fully operational under clan orchestration.

## References

### Internal

- [Clan Integration concept documentation](/concepts/clan-integration)
- [ADR-0011: SOPS secrets management](0011-sops-secrets-management/)
- [ADR-0018: Deferred module composition architecture](0018-deferred-module-composition-architecture/)
- [ADR-0020: Deferred module composition + Clan integration](0020-deferred-module-composition-clan-integration/)
- [Module System Primitives](/concepts/module-system-primitives/) - deferredModule and evalModules foundations
- [Terminology Glossary](/development/context/glossary/) - Module system terminology guide

### External

- [Clan documentation](https://clan.lol/) - Official clan docs
- [clan-core repository](https://github.com/clan-lol/clan-core) - Source code
- [clan-infra](https://git.clan.lol/clan/clan-infra) - Production reference
- [qubasa-clan-infra](https://github.com/qubasa/dotfiles) - Developer personal clan
- [mic92-clan-dotfiles](https://github.com/Mic92/dotfiles) - Developer personal clan
- [pinpox-clan-nixos](https://github.com/pinpox/nixos) - Developer personal clan
