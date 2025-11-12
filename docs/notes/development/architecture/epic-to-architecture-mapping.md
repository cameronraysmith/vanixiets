# Epic to Architecture Mapping

| Epic | Architecture Components | Key Modules | Clan Services Used | Test Coverage |
| ---- | ----------------------- | ----------- | ------------------ | ------------- |
| **Epic 1: Architectural Validation** (Phase 0, test-clan) | Dendritic + clan integration, NixOS VMs (cinnabar/electrum), terraform/terranix, disko/ZFS, zerotier mesh, comprehensive test harness | modules/clan/core.nix, modules/system/*.nix, modules/machines/nixos/*, modules/terranix/*.nix, modules/checks/*.nix | zerotier (controller on cinnabar), emergency-access, tor, users | 17 test cases (nix-unit + integration + validation) |
| **Epic 2: VPS Infrastructure Foundation** (Phase 1, production nix-config + blackphos) | Apply validated patterns to infra repo, migrate blackphos darwin (multi-user), heterogeneous networking (nixos ↔ darwin) | modules/darwin/base.nix, modules/darwin/users.nix, modules/home/users/{crs58,raquel}/, modules/machines/darwin/blackphos/ | zerotier (peer role, darwin workaround), sshd-clan, users-crs58, users-raquel | Existing test-clan tests + darwin-specific validation |
| **Epic 3: First Darwin Migration** (Phase 2, rosegold) | Validate darwin pattern reusability, multi-machine coordination (3 machines), 3-user fleet (crs58 + raquel + janettesmith) | modules/machines/darwin/rosegold/, modules/home/users/janettesmith/ | Same as blackphos (reuse patterns) | Pattern reusability validation, 3-machine network tests |
| **Epic 4: Multi-Darwin Validation** (Phase 3, argentum) | 4-machine network validation, 4-user fleet, final validation before primary workstation | modules/machines/darwin/argentum/, modules/home/users/christophersmith/ | Same patterns (3rd iteration validation) | 4-machine mesh network validation, coordination tests |
| **Epic 5: Primary Workstation Migration** (Phase 4, stibnite) | 5-machine complete fleet, primary workstation with all productivity workflows, cumulative stability (4-6 weeks) | modules/machines/darwin/stibnite/ | Complete fleet coordination | Comprehensive workflow validation, productivity assessment |
| **Epic 6: Legacy Cleanup** (Phase 5) | Remove nixos-unified, finalize secrets migration (full clan vars or hybrid), clean architecture | Remove configurations/ directory, nixos-unified flake input | Finalize secret management strategy | Architecture coherence validation |

**Cross-Epic Dependencies**:
- Epic 1 → Epic 2: Validated patterns (dendritic + clan) applied to production
- Epic 2 → Epic 3-5: Darwin patterns established, replicated with minimal customization
- Epic 3-4 → Epic 5: Cumulative stability (4-6 weeks) required before stibnite
- All Epics → Epic 6: Complete migration enables cleanup
