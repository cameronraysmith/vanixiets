---
title: "ADR-0019: Clan-Core Orchestration"
---

- **Status**: Accepted
- **Date**: 2024-11-20
- **Scope**: Multi-machine coordination and deployment
- **Related**: [ADR-0011: SOPS secrets management](0011-sops-secrets-management/), [ADR-0018: Dendritic flake-parts architecture](0018-dendritic-flake-parts-architecture/)

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

Before clan-core, multi-machine coordination required:
- Manual deployment scripts per machine
- Separate secrets management (sops-nix only, no generated secrets)
- Ad-hoc service coordination
- No inventory abstraction

## Decision

Adopt **clan-core** for multi-machine orchestration, secrets generation, and service coordination.

### Mental model: Kubernetes for NixOS

Understanding clan-core's role requires drawing an analogy to Kubernetes in the container ecosystem.
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

Vars and generators (Tier 1 secrets):
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
| User-level secrets | **sops-nix** | Tier 2 secrets, parallel to clan vars |
| NixOS/darwin system configuration | **NixOS modules** | Clan imports and deploys configs, doesn't define them |
| Nixpkgs overlays and config | **Flake-level** | Outside clan scope entirely |

### Two-tier secrets architecture

This infrastructure uses a two-tier secrets system that divides responsibilities based on the lifecycle and purpose of secrets.
Tier 1 handles machine-level secrets that are generated automatically by clan and tied to specific machines - these are the foundational identities like SSH host keys and zerotier network membership tokens that a machine needs to participate in the fleet.
When you run `clan vars generate`, clan's generator system creates these secrets deterministically based on templates, then encrypts them using age keys and stores them in the `vars/` directory.
This automation eliminates the manual key management burden for foundational secrets that would be tedious and error-prone to create by hand across 8 machines.

Tier 2 handles user-level secrets that are manually created via sops and represent human-controlled credentials like GitHub personal access tokens, API keys, and signing keys.
These secrets live in the `secrets/` directory and are managed through the standard sops workflow - you edit `secrets/users/username.sops.yaml` with the sops CLI, which handles encryption using the same age keys.
The separation between tiers prevents lifecycle conflicts (clan won't regenerate your API keys, and sops won't try to template-generate machine identities) and keeps concerns separated (machine infrastructure versus user identity).

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
While deploy-rs is simpler than clan-core in some ways, that simplicity comes from not solving problems we actually have.

### morph

Morph was eliminated primarily due to its lack of darwin support - with 4 darwin laptops in the fleet, requiring a separate deployment mechanism for half the machines would fragment the operational model.
Beyond the cross-platform issue, morph doesn't provide the inventory abstraction that this fleet needs for service coordination.
The project also sees less active development compared to clan-core, and while that doesn't automatically disqualify a tool, it matters when you need ecosystem support for integration with newer tools like dendritic flake-parts patterns.
The smaller community means fewer examples of morph integration with the architectural patterns this infrastructure uses.

### Manual coordination

Manual deployment scripts worked adequately when the fleet consisted of 2 machines, but scaling to 8 machines exposed the coordination complexity.
Keeping zerotier network configuration synchronized across machines meant manually editing configuration files to ensure peers knew the controller's identity and the controller's config included all peer public keys.
Adding a new machine to the VPN required touching multiple configuration files across multiple machines, and mistakes were only discovered at deployment time.
Secret management became particularly problematic - generating SSH host keys for each machine, distributing zerotier identity files, managing LUKS passphrases - all required manual workflows that were tedious and error-prone.
The lack of declarative service coordination meant no single source of truth for "which services run on which machines," making it difficult to reason about the fleet's intended state versus its actual state.

### NixOps

NixOps was not evaluated deeply because its stateful deployment model conflicts with this infrastructure's preference for stateless, git-tracked configuration.
NixOps maintains deployment state in a database that must be carefully preserved and backed up, introducing an additional failure mode and coordination burden.
The project has also seen reduced development activity compared to newer alternatives like clan-core and deploy-rs, and its architecture predates many modern NixOS patterns like flakes and flake-parts.
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
The two-tier secrets architecture complements this automation by keeping machine-generated secrets (Tier 1) clearly separated from human-managed credentials (Tier 2).
Clan vars handles the machine identity lifecycle while sops-nix handles user credentials, and this separation prevents lifecycle conflicts - clan won't regenerate your API keys, and sops won't try to auto-generate machine identities.
Each tier is optimized for its use case, and there's no ambiguity about which system manages which secrets.

Service inventory provides the abstraction layer this fleet needs for multi-machine coordination.
The zerotier VPN configuration demonstrates the pattern clearly - the inventory declaratively defines "cinnabar is the controller, these 7 machines are peers," and the clan zerotier module consumes that declaration to generate the appropriate configuration for each machine.
Adding a new machine to the VPN requires one line in the inventory file rather than editing configuration on multiple machines to update peer lists and controller assignments.
This declarative coordination scales naturally - the complexity of adding machine 9 is identical to the complexity of adding machine 2, whereas manual coordination complexity grows quadratically with fleet size.

The architecture benefits from clan-core's active development by Chaos Computer Club members and the growing ecosystem of clan modules.
Regular releases provide new features and bug fixes, and the responsive issue handling means blockers can be resolved quickly.
More importantly, clan is built as a flake-parts module, which means it integrates naturally with the dendritic pattern this infrastructure uses.
The clan machine registry consumes the same namespace exports (`flake.modules.darwin.*`, `flake.modules.nixos.*`) that the dendritic organization produces, creating seamless architectural coherence without impedance mismatch between layers.

### Negative

darwin support requires workarounds:
clan-core zerotier module is NixOS-specific (systemd dependencies).
Darwin machines use homebrew + activation script pattern.
Documented workaround (101-line module) but not native.

Learning curve for clan concepts:
Inventory, vars, generators are new abstractions.
Documentation improving but not as comprehensive as NixOS.
Contributors need to understand clan patterns.

Vars encryption tied to age keys:
Vars system uses age encryption.
Key management required (same keys as sops-nix).
Lost keys require secret regeneration.

Deployment requires network access:
`clan machines update` requires SSH to target.
No offline deployment capability.
VPN (zerotier) must be operational for remote machines.

### Neutral

Terranix still handles infrastructure:
Clan deploys to VMs, doesn't create them.
Terranix/terraform provisioning unchanged.
Clear separation of concerns.

Home-manager unchanged:
Home-manager configurations defined in dendritic modules.
Clan deploys full system config including home-manager.
No home-manager-specific clan integration.

NixOS modules unchanged:
System configuration still uses standard NixOS modules.
Clan imports and deploys configs.
Module authoring skills transfer directly.

## Validation evidence

### Epic 1 (November 2024)

Clan validated in test-clan repository:

- Story 1.3: Clan inventory configured for Hetzner VMs
- Story 1.5: VM deployment via clan (`clan machines install hetzner-vm`)
- Story 1.9: Zerotier network coordination (controller + peer roles)
- Story 1.10A: User management via clan inventory pattern
- Story 1.12: Heterogeneous deployment (darwin + nixos)

Metrics from GO/NO-GO decision:
- 3 machines operational (cinnabar, electrum, blackphos)
- Zerotier network db4344343b14b903 coordinated
- Pattern confidence: HIGH

### Epic 2 (November 2024)

Production deployment:

- Stories 2.5-2.7: Darwin workstations deployed via clan
- Stories 2.9-2.10: VPS deployment switched to clan
- Stories 2.13-2.14: New machines added to inventory

### Epic 7 (December 2024)

GCP infrastructure:

- Story 7.3: GCP nodes integrated into clan inventory
- Story 7.4: GPU compute (scheelite) orchestrated via clan

Result: 8-machine fleet fully operational under clan orchestration.

## References

### Internal

- [Clan Integration concept documentation](/concepts/clan-integration)
- [ADR-0011: SOPS secrets management](0011-sops-secrets-management/)
- [ADR-0018: Dendritic flake-parts architecture](0018-dendritic-flake-parts-architecture/)
- [ADR-0020: Dendritic + Clan integration](0020-dendritic-clan-integration/)
- Epic 1 GO/NO-GO decision: `docs/notes/development/go-no-go-decision.md`

### External

- [Clan documentation](https://clan.lol/) - Official clan-core docs
- [clan-core repository](https://github.com/clan-lol/clan-core) - Source code
- [clan-infra](https://git.clan.lol/clan/clan-infra) - Production reference
- [qubasa-clan-infra](https://github.com/qubasa/dotfiles) - Developer personal clan
- [mic92-clan-dotfiles](https://github.com/Mic92/dotfiles) - Developer personal clan
- [pinpox-clan-nixos](https://github.com/pinpox/nixos) - Developer personal clan
