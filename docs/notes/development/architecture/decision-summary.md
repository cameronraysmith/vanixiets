# Decision Summary

| Category | Decision | Version | Affects Epics | Rationale | Provided by |
| -------- | -------- | ------- | ------------- | --------- | ----------- |
| **Architectural Pattern** | Dendritic flake-parts + clan-core | flake-parts 7.1.1, clan-core main | All (Epic 1-7) | Maximizes type safety via module system, proven in test-clan Stories 1.1-1.7 with zero regressions | Pattern research + validation |
| **Module Discovery** | import-tree automatic | import-tree latest | All | Eliminates manual imports, auto-discovers all .nix files in modules/ | Dendritic pattern requirement |
| **Infrastructure Provisioning** | terraform via terranix | terranix 2.9.0 | Epic 1 (VPS deployment) | Declarative cloud deployment, proven in clan-infra production | clan-infra reference |
| **Disk Management** | disko with ZFS | disko main, ZFS native | Epic 1-2 (NixOS hosts) | Declarative partitioning, unencrypted ZFS (LUKS deferred), automatic dataset creation | Test-clan validation (Stories 1.4-1.5) |
| **Networking** | Zerotier mesh VPN | zerotier-one 1.14.2 | Epic 1-7 | Always-on coordination independent of darwin host power state, controller on cinnabar VPS | Clan zerotier service |
| **Networking (darwin)** | Multiple options | Varies | Epic 2-6 (darwin hosts) | Zerotier clan service is NixOS-only; darwin requires alternative (see Darwin Networking Options section) | Source code analysis |
| **Secrets Management** | Clan vars generators | clan-core vars system | Epic 1-7 | Declarative secret generation, automatic deployment to /run/secrets/, replaces manual sops-nix | Clan vars architecture |
| **Multi-User Pattern** | Standard NixOS users.users (not clan users service) | NixOS module system | Epic 2-6 (darwin multi-user) | Clan users clanService exists but NOT used; traditional users.users chosen for darwin compatibility + explicit UID control. Per-user vars use naming convention. See "User Management Decision" below. | clan-core analysis + real-world usage (clan-infra, qubasa, pinpox) |
| **Home-Manager** | Portable user-based modules | home-manager 25.05 | All epics | User-based modules (`flake.modules.homeManager."users/{username}"`) support three integration modes (darwin, NixOS, standalone). See Pattern 2 and "Home-Manager Pattern Decision" below. | Test-clan validation + pinpox pattern divergence |
| **Base Module Auto-Merge** | Automatic via import-tree | import-tree feature | All | System-wide modules (nix-settings, admins, initrd-networking) auto-merge to flake.modules.nixos.base | Test-clan proven pattern |
| **Test Framework** | nix-unit + runNixOSTest | nix-unit 2.28.1 | Epic 1 (validation) | Fast expression tests + VM integration tests, 17 test cases in test-clan | Test-clan validation infrastructure |
| **Migration Strategy** | Progressive with stability gates | N/A | Epic 1-7 | 1-2 week validation between hosts, explicit rollback procedures, primary workstation last | Risk mitigation for brownfield |
| **Legacy Elimination** | Remove nixos-unified | Post-migration | Epic 7 (cleanup) | Incompatible with dendritic pattern (specialArgs vs config.flake.*), remove after all hosts migrated | Architectural incompatibility |

**Version Verification** (as of 2025-11-11):
- flake-parts: 7.1.1 (stable)
- clan-core: main branch (git+https://git.clan.lol/clan/clan-core)
- import-tree: latest (github:vic/import-tree)
- terranix: 2.9.0 (github:terranix/terranix)
- disko: main (github:nix-community/disko)
- zerotier-one: 1.14.2 (nixpkgs#zerotierone)
- nix-unit: 2.28.1 (nixpkgs#nix-unit)
- home-manager: 25.05 (follows nixpkgs unstable)

**Dendritic Pattern Compromises**:
- **Minimal specialArgs acceptable**: Clan requires `specialArgs = { inherit inputs; inherit self; }` for flakeModules integration (framework values only, not extensive pass-through)
- **Auto-merge replaces pure exports**: Base modules auto-merge via import-tree instead of explicit exports (pragmatic dendritic adaptation)
- **Clan coordination over pure dendritic**: When clan functionality conflicts with dendritic purity, clan takes precedence (documented deviations)
