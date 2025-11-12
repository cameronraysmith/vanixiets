# Architectural Decisions

## User Management Decision: Traditional vs Clan Users Service

**Investigation Date:** 2025-11-12

**Question:** Should we use clan-core's native users clanService or traditional NixOS `users.users.*` definitions?

**Clan Users ClanService Analysis:**

Clan-core provides `clanServices/users/` for multi-machine user account coordination via inventory service instances:

```nix
# Clan pattern (NOT used in our architecture)
inventory.instances.user-crs58 = {
  module = { name = "users"; input = "clan-core"; };
  roles.default.tags.all = { };  # Deploy on all machines
  roles.default.settings = {
    user = "crs58";
    groups = [ "wheel" ];
    share = true;  # Same password across machines
  };
};
```

**Features:**
- Automatic password generation and distribution
- Cross-machine password coordination (`share = true`)
- Tag-based deployment to machine subsets
- Built-in vars integration (`user-password-{username}`)

**Real-World Usage Analysis:**

Examined clan-infra and developer repos (qubasa, mic92, pinpox):
- **clan-infra:** Uses users service ONLY for root account, regular users via traditional definitions
- **qubasa-clan-infra:** NO users service usage, all traditional definitions
- **pinpox-clan-nixos:** NO users service usage, all traditional definitions

**Finding:** Real-world clan usage favors traditional `users.users.*` approach for regular users.

**Decision: Use Traditional `users.users.*` Definitions**

**Rationale:**

1. **Darwin Compatibility** (CRITICAL):
   - Users clanService sets `users.mutableUsers = false` (line 150 of `clanServices/users/default.nix`)
   - Darwin requires mutable users for system integration
   - 4 of 5 machines in our fleet are darwin

2. **Explicit UID Control** (IMPORTANT):
   - Users service auto-assigns UIDs
   - Multi-machine consistency requires explicit UID coordination (crs58 = 550, raquel = 551)
   - Traditional definitions provide explicit UID control per machine

3. **Per-Machine Flexibility** (IMPORTANT):
   - SSH keys differ per machine for security
   - Home directories may vary (darwin `/Users/` vs NixOS `/home/`)
   - Traditional definitions allow per-machine customization

4. **Real-World Validation**:
   - Clan-infra (production) uses hybrid: users service for root, traditional for regular users
   - All examined repos favor traditional approach for regular users
   - Pattern proven across heterogeneous fleets

**Trade-offs:**

| Aspect | Traditional Definitions | Users ClanService |
|--------|------------------------|-------------------|
| Darwin Support | ✅ Native | ❌ Incompatible (`users.mutableUsers = false`) |
| UID Control | ✅ Explicit | ❌ Auto-assigned |
| Per-Machine SSH Keys | ✅ Easy | ⚠️ Requires overrides |
| Cross-Machine Password | ⚠️ Manual vars | ✅ Automatic (`share = true`) |
| Service Abstraction | ❌ Manual | ✅ Declarative |
| Complexity | ✅ Simple | ⚠️ Additional layer |

**Conclusion:** Traditional approach is DIVERGENT from clan's native capability but JUSTIFIED by darwin compatibility and UID control requirements. Real-world usage validates this pattern.

**Implementation:** See Pattern 3 (Darwin Multi-User) for per-user vars naming convention (`ssh-key-{username}`) that provides similar organization without clanService dependency.

---

## Home-Manager Pattern Decision: User-Based vs Profile-Based Modules

**Investigation Date:** 2025-11-12

**Question:** How should home-manager configurations be organized for cross-platform reuse?

**Clan Examples Analysis:**

Only 1 of 3 examined clan repositories uses home-manager:

- **pinpox-clan-nixos:** Uses profile-based exports (`flake.homeConfigurations.desktop`)
  ```nix
  homeConfigurations.desktop = { ... }: {
    imports = [ ./home-manager/profiles/desktop ];
  };
  # Machine usage:
  home-manager.users.pinpox = flake-self.homeConfigurations.desktop;
  ```

- **Other repos:** No home-manager integration found (qubasa, mic92, clan-infra)

**Decision: User-Based Modules via Dendritic Namespace**

**Pattern:**
```nix
flake.modules.homeManager."users/crs58" = { config, pkgs, lib, ... }: { ... };
```

**Rationale:**

1. **Multi-User Granularity:**
   - blackphos has 2 users (crs58 admin + raquel non-admin) with different configs
   - User-based modules allow per-user customization naturally
   - Profile-based would require mapping profiles to users

2. **Dendritic Integration:**
   - Uses `flake.modules.*` namespace (dendritic pattern)
   - Auto-discovered via import-tree
   - Self-composable via `config.flake.modules`

3. **Three Integration Modes:**
   - Darwin integrated: `darwinModules.home-manager` + imports
   - NixOS integrated: `nixosModules.home-manager` + imports
   - Standalone: `homeConfigurations.{username}` for `nh home switch`

**Comparison:**

| Aspect | User-Based (Our Approach) | Profile-Based (Pinpox) |
|--------|---------------------------|------------------------|
| Multi-User Support | ✅ Natural | ⚠️ Requires mapping |
| Granularity | Per-user modules | Per-profile configs |
| Dendritic Integration | ✅ Namespace exports | ❌ Direct flake outputs |
| Reusability | Users share modules | Profiles reused |
| Cross-Platform | ✅ Works anywhere | ✅ Works anywhere |

**Conclusion:** User-based approach is DIVERGENT from pinpox pattern but SUPERIOR for multi-user machines. Fills gap in clan ecosystem (no standard home-manager patterns exist).

**Implementation:** See Pattern 2 (Portable Home-Manager Modules) for complete pattern documentation.

**Evidence:** Comprehensive clan-core investigation (2025-11-12) covering:
- Clan-core source analysis (`clanServices/users/`, vars/secrets patterns)
- Clan-infra production usage patterns
- Developer repositories (qubasa, mic92, pinpox)
- Alignment assessment matrix with trade-off analysis

**Validation (Story 1.8A - Complete 2025-11-12):**
- ✅ Extracted crs58 and raquel home modules from blackphos inline configs
- ✅ Exported to dendritic namespace (`flake.modules.homeManager."users/{username}"`)
- ✅ Exposed standalone `homeConfigurations.{crs58,raquel}` for nh CLI
- ✅ Refactored blackphos to import from namespace (46 lines removed, zero regression)
- ✅ Package diff validation: 270 packages preserved exactly (zero functional change)
- ✅ Standalone activation tested (`nh home switch . -c {username}`)
- ✅ Test coverage added (TC-018: home-module-exports, TC-019: home-configurations-exposed)
- ✅ Pattern ready for Story 1.9 (cinnabar NixOS will reuse crs58 module)

**Preservation of infra Features:**
- ✅ Cross-platform user config sharing (darwin + NixOS)
- ✅ DRY principle maintained (single definition, multiple machines)
- ✅ Three integration modes supported (darwin, NixOS, standalone)
- ✅ Modular architecture restored (Story 1.8 inline configs removed)

---
