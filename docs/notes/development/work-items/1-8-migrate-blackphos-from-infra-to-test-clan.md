# Story 1.8: Migrate blackphos from infra to test-clan management

**Epic:** Epic 1 - Architectural Validation + Migration Pattern Rehearsal (Phase 0)

**Status:** ready-for-dev

**Dependencies:**
- Story 1.7 (complete): Dendritic flake-parts refactoring complete in test-clan

**Strategic Value:** Rehearses complete nixos-unified → dendritic + clan transformation on real darwin hardware, documenting the migration pattern as a blueprint for Epic 2+ production refactoring of remaining 4 machines

---

## Story Description

As a system administrator,
I want to migrate blackphos nix-darwin configuration from infra's nixos-unified pattern to test-clan's dendritic + clan pattern,
So that I can validate the complete transformation process and document the migration pattern for refactoring infra in Epic 2+.

**Context:**
blackphos is raquel's nix-darwin laptop currently managed by infra repository using nixos-unified pattern. This story migrates it to test-clan's proven dendritic + clan architecture (validated in Stories 1.6-1.7), serving as a migration rehearsal before Epic 2+ production refactoring.

**Transformation:**
- **From:** infra/configurations/darwin/blackphos.nix (nixos-unified + home-manager)
- **To:** test-clan/modules/machines/darwin/blackphos/ (dendritic + clan-core)
- **Users:** crs58 (admin), raquel (primary user with home-manager config)
- **Deployment:** Actual blackphos hardware (validation, not just config creation)

---

## Acceptance Criteria

### AC1: Blackphos Darwin Configuration Migrated to test-clan

- [ ] Darwin host module created at test-clan/modules/machines/darwin/blackphos/default.nix following dendritic pattern
- [ ] Configuration uses namespace imports (with config.flake.modules pattern from Story 1.7)
- [ ] All existing functionality preserved:
  - Homebrew packages and casks (codelayer-nightly, dbeaver-community, docker-desktop, etc.)
  - Desktop profile enabled (isDesktop = true equivalent)
  - TouchID authentication for sudo
  - System state version preserved (stateVersion = 4)
- [ ] Module exports to flake.modules.darwin."machines/darwin/blackphos" namespace
- [ ] Configuration builds: `nix build .#darwinConfigurations.blackphos.system`

**Implementation Notes:**
- Reference infra/configurations/darwin/blackphos.nix for current config
- Reference mic92-clan-dotfiles/machines/evo/ for darwin + clan pattern
- Use dendritic self-composition (namespace imports, not relative paths)
- System primaryUser = "crs58" (admin user for blackphos)

### AC2: Home-Manager Integration for Users

- [ ] Home-manager integrated for both users (crs58, raquel)
- [ ] crs58 (admin user): Minimal admin configuration
- [ ] raquel (primary user): Full home configuration migrated from infra/configurations/home/raquel@blackphos.nix
- [ ] raquel's preferred tools preserved (git, gh, just, ripgrep, fd, bat, eza)
- [ ] raquel's git config preserved (userName, userEmail)
- [ ] LazyVim disabled for raquel (mkForce false as in original)
- [ ] Home-manager integration pattern documented

**Implementation Notes:**
- Investigate clan-core home-manager integration (clan-core supports it but examples limited)
- Reference mic92-clan-dotfiles for home-manager patterns (uses nixosModules.home-manager)
- Option A: Integrated home-manager (via darwin configuration)
- Option B: Standalone home-manager (separate activation)
- Document chosen approach and rationale

### AC3: Blackphos Added to Clan Inventory

- [ ] blackphos added to test-clan clan inventory (modules/clan/inventory/machines.nix)
- [ ] Machine metadata:
  - tags = ["darwin", "workstation", "laptop"]
  - machineClass = "darwin"
  - description = "raquel's laptop (primary user), crs58 admin"
- [ ] Clan machine registration in modules/clan/machines.nix
- [ ] Inventory evaluates: `nix eval .#clan.inventory --json | jq '.machines.blackphos'`

**Implementation Notes:**
- Follow test-clan inventory pattern from Story 1.3-1.5
- blackphos is darwin, not nixos (different machineClass)

### AC4: Secrets Migrated to Clan Vars

- [ ] Existing infra secrets identified and documented (if any exist for blackphos)
- [ ] Secrets migrated to clan vars system:
  - **If existing sops secrets:** Use `clan secrets import-sops` to migrate
  - **If no existing secrets:** Define new generators using `clan.core.vars.generators` pattern
  - **For system-generated values:** Use clan vars generators (SSH host keys, certificates)
- [ ] Clan admin keypair generated: `clan secrets key generate`
- [ ] Admin user added to clan secrets: `clan secrets users add <user> --age-key <public_key>`
- [ ] Vars generated for blackphos: `clan vars generate blackphos`
- [ ] Secrets accessible via `config.clan.core.vars.generators.<name>.files.<file>.path`
- [ ] Migration documented with rationale

**Implementation Notes:**
- **clan vars uses sops-nix** as its default encryption backend (clan-core docs: secrets.md)
- **macOS supports vars** explicitly (clan-core docs: macos.md line 10)
- clan-core docs (secrets.md lines 1-2): "should use Vars directly instead" of raw sops-nix
- Generators pattern: prompts (user input) → script (generation logic) → files (output)
- Age keys stored at `~/.config/sops/age/keys.txt` (or `SOPS_AGE_KEY` env var)
- Reference: clan-core docs vars-backend.md for complete generator examples

### AC5: Configuration Builds and Deploys Successfully

- [ ] Configuration builds without errors: `nix build .#darwinConfigurations.blackphos.system`
- [ ] Deployment to blackphos hardware: `darwin-rebuild switch --flake ~/projects/nix-workspace/test-clan#blackphos`
- [ ] System activates successfully (no activation failures)
- [ ] All services start correctly (homebrew, touchID, etc.)
- [ ] Users can log in (crs58, raquel)
- [ ] Home-manager activations successful for both users

**Implementation Notes:**
- Deploy from blackphos machine itself (local deployment)
- Backup current system before deployment (Time Machine or snapshot)
- Test in VM first if possible (darwin VMs complex, may skip)

### AC6: Zero-Regression Validation

- [ ] Pre-migration package list captured: `darwin-rebuild --flake ~/projects/nix-workspace/infra#blackphos build && nix-store -q --references result | sort > pre-migration-packages.txt`
- [ ] Post-migration package list captured: `darwin-rebuild --flake ~/projects/nix-workspace/test-clan#blackphos build && nix-store -q --references result | sort > post-migration-packages.txt`
- [ ] Package diff analyzed: `diff pre-migration-packages.txt post-migration-packages.txt`
- [ ] All critical packages present in post-migration
- [ ] Any differences documented and justified
- [ ] raquel's daily workflows validated:
  - Terminal (zsh + starship)
  - Git operations
  - Development tools (just, ripgrep, fd, bat, eza)
  - GUI applications (homebrew casks working)

**Implementation Notes:**
- Focus on functional equivalence, not byte-for-byte package identity
- Some package path changes expected (different nix store paths)
- Validate critical functionality, not every package

### AC7: Transformation Pattern Documented

- [ ] Migration process documented (decide location: new doc vs inline notes)
- [ ] Documentation captures:
  - Step-by-step conversion process (nixos-unified → dendritic + clan)
  - Module organization patterns (where to place darwin modules, home configs)
  - Secrets migration approach (sops-nix handling)
  - Home-manager integration pattern chosen
  - Common issues encountered and solutions
  - Differences between nixos and darwin in clan context
- [ ] Documentation valuable for Epic 2+ (refactoring remaining infra machines)

**Implementation Notes:**
- May be inline completion notes rather than separate doc
- Focus on TRANSFORMATION PATTERN, not blackphos-specific details
- Answer: "How do I convert a machine from infra to dendritic + clan?"

---

## Implementation Tasks

### Task 1: Investigate Current blackphos Configuration (1-2 hours)

**Objective:** Understand what needs to be migrated

**Actions:**
1. Read complete infra/configurations/darwin/blackphos.nix
2. Read complete infra/configurations/home/raquel@blackphos.nix
3. Read complete infra/configurations/home/runner@blackphos.nix (if relevant)
4. Identify all darwin modules used: infra/modules/darwin/
5. Identify all home modules used: infra/modules/home/
6. Check for secrets usage (sops-nix, agenix)
7. Document package list and configuration options

**Success Criteria:**
- Complete understanding of blackphos current config
- List of all functionality to preserve
- Identification of secrets/sensitive config

### Task 2: Study Reference Implementations (1-2 hours)

**Objective:** Learn darwin + clan patterns from examples

**Actions:**
1. Study mic92-clan-dotfiles/machines/evo/configuration.nix (darwin + sops-nix pattern)
2. Study mic92-clan-dotfiles/darwinModules/ (darwin module patterns)
3. Study clan-core/machines/test-darwin-machine/ (minimal darwin example)
4. Review test-clan dendritic pattern from Story 1.7 (namespace imports, module organization)
5. Check clan-infra for any darwin patterns
6. Document home-manager integration patterns observed

**Success Criteria:**
- Clear understanding of darwin + clan + dendritic pattern
- Home-manager integration approach identified
- Secrets management strategy chosen

### Task 3: Create blackphos Darwin Module (2-3 hours)

**Objective:** Convert infra darwin config to test-clan dendritic pattern

**Actions:**
1. Create test-clan/modules/machines/darwin/blackphos/default.nix
2. Convert configuration using dendritic flake-parts pattern:
   ```nix
   {
     flake.modules.darwin."machines/darwin/blackphos" = { config, pkgs, ... }: {
       imports = with config.flake.modules.darwin; [
         base  # If darwin base modules exist
         # Other module imports
       ];

       nixpkgs.hostPlatform = "aarch64-darwin";
       networking.hostName = "blackphos";
       system.stateVersion = 4;

       # ... rest of configuration from infra
     };
   }
   ```
3. Migrate all functionality from infra/configurations/darwin/blackphos.nix
4. Preserve homebrew configuration
5. Preserve touchID authentication
6. Preserve desktop profile settings
7. Build test: `nix build .#darwinConfigurations.blackphos.system`

**Success Criteria:**
- blackphos darwin module created following dendritic pattern
- Configuration builds successfully
- All darwin functionality migrated

### Task 4: Integrate Home-Manager for Both Users (2-3 hours)

**Objective:** Set up home-manager for crs58 (admin) and raquel (primary user)

**Actions:**
1. Determine home-manager integration approach:
   - Option A: Integrated via darwin configuration (nixosModules.home-manager pattern)
   - Option B: Standalone home-manager (separate activation)
2. Create home-manager configurations:
   - crs58: Minimal admin config
   - raquel: Full config migrated from infra/configurations/home/raquel@blackphos.nix
3. Integrate home-manager into blackphos darwin module
4. Migrate raquel's packages (git, gh, just, ripgrep, fd, bat, eza)
5. Migrate raquel's git config (userName, userEmail)
6. Migrate raquel's shell config (zsh, starship)
7. Disable LazyVim for raquel (mkForce false)
8. Build test: Verify home-manager evaluation

**Success Criteria:**
- Home-manager working for both users
- raquel's config fully migrated
- Build succeeds with home-manager integration

### Task 5: Add blackphos to Clan Inventory (30 minutes - 1 hour)

**Objective:** Register blackphos in clan inventory

**Actions:**
1. Add to test-clan/modules/clan/inventory/machines.nix:
   ```nix
   blackphos = {
     tags = ["darwin" "workstation" "laptop"];
     machineClass = "darwin";
     description = "raquel's laptop, crs58 admin";
   };
   ```
2. Register in test-clan/modules/clan/machines.nix:
   ```nix
   clan.machines.blackphos = {
     imports = [ config.flake.modules.darwin."machines/darwin/blackphos" ];
   };
   ```
3. Verify inventory: `nix eval .#clan.inventory --json | jq '.machines.blackphos'`
4. Verify darwinConfigurations: `nix eval .#darwinConfigurations --apply builtins.attrNames`

**Success Criteria:**
- blackphos in clan inventory
- darwinConfigurations.blackphos available
- Clan integration working

### Task 6: Migrate Secrets to Clan Vars (1-2 hours)

**Objective:** Migrate blackphos secrets to clan vars system (uses sops-nix underneath)

**Actions:**
1. **Generate clan admin keypair** (if not already done for test-clan):
   ```bash
   clan secrets key generate
   # Output: Public key displayed, private key stored at ~/.config/sops/age/keys.txt
   ```
2. **Add admin user to clan secrets:**
   ```bash
   clan secrets users add <your_username> --age-key <public_key_from_step_1>
   ```
3. **Identify existing infra secrets for blackphos:**
   - Check infra repository for any sops-encrypted secrets
   - Check if blackphos uses any secrets currently
   - Document what needs to be migrated
4. **Choose migration approach:**
   - **If existing sops secrets:** Use `clan secrets import-sops` to migrate from infra
   - **If no existing secrets:** Define new generators using `clan.core.vars.generators` pattern
5. **Define generators for system values** (example SSH host keys):
   ```nix
   clan.core.vars.generators.ssh-host-key = {
     files."ed25519".secret = false;  # Public key can be in git
     files."ed25519_priv".secret = true;  # Private key encrypted
     script = ''
       ssh-keygen -t ed25519 -N "" -f $out/ed25519
       mv $out/ed25519 $out/ed25519_priv
     '';
     runtimeInputs = [ pkgs.openssh ];
   };
   ```
6. **Generate vars for blackphos:**
   ```bash
   clan vars generate blackphos
   # Will prompt for any required inputs, generate files, commit to git
   ```
7. **Reference vars in configuration:**
   ```nix
   services.openssh.hostKeys = [{
     path = config.clan.core.vars.generators.ssh-host-key.files.ed25519_priv.path;
     type = "ed25519";
   }];
   ```
8. **Test vars access:** Build configuration and verify var paths are correct

**Success Criteria:**
- Clan admin keypair generated and backed up
- All necessary secrets/vars defined as generators
- Vars generated for blackphos
- Configuration builds with vars integration
- Secrets accessible via generated file paths

**References:**
- clan-core docs: docs/site/guides/vars/vars-backend.md (generator examples)
- clan-core docs: docs/site/guides/macos.md (macOS vars support)
- clan-core docs: docs/site/guides/secrets.md (underlying sops integration)

### Task 7: Deploy to blackphos Hardware (2-3 hours)

**Objective:** Deploy test-clan configuration to actual blackphos

**Actions:**
1. **Pre-deployment safety:**
   - Ensure Time Machine backup recent
   - Document current system state
   - Capture pre-migration package list (AC6)
   - Have rollback plan ready
2. **Deployment:**
   - On blackphos: `cd ~/projects/nix-workspace/test-clan`
   - Build: `darwin-rebuild build --flake .#blackphos`
   - Review changes
   - Deploy: `darwin-rebuild switch --flake .#blackphos`
3. **Validation:**
   - System activates without errors
   - Services start correctly
   - Users can log in (crs58, raquel)
   - Home-manager activations successful
   - Homebrew apps accessible
   - TouchID sudo works
4. **Post-deployment:**
   - Capture post-migration package list (AC6)
   - Compare package lists
   - Document any differences

**Success Criteria:**
- Deployment successful
- System fully functional
- No critical regressions
- Users can work normally

### Task 8: Zero-Regression Validation (1-2 hours)

**Objective:** Verify all functionality preserved

**Actions:**
1. Compare package lists (pre vs post migration)
2. Test raquel's workflows:
   - Terminal (zsh, starship)
   - Git operations
   - Development tools (just, ripgrep, fd, bat, eza)
   - Homebrew casks (codelayer-nightly, docker-desktop, etc.)
3. Test crs58 admin access
4. Test touchID authentication
5. Verify all services running
6. Check system logs for errors
7. Raquel validates daily workflows
8. Document any issues or differences

**Success Criteria:**
- All critical functionality working
- Package differences justified (if any)
- raquel confirms system usable
- Zero critical regressions

### Task 9: Document Transformation Pattern (1-2 hours)

**Objective:** Create migration blueprint for Epic 2+

**Actions:**
1. Document step-by-step transformation process:
   - nixos-unified pattern → dendritic + clan pattern
   - Configuration location changes
   - Module organization patterns
   - Home-manager integration approach
   - Secrets handling
2. Capture common issues and solutions
3. Note darwin-specific considerations
4. Provide example commands
5. Include lessons learned
6. Format for Epic 2+ reference

**Success Criteria:**
- Transformation pattern documented
- Clear enough for Epic 2+ to follow
- Covers all migration aspects
- Includes troubleshooting notes

---

## Technical Notes

### Dendritic Pattern (from Story 1.7)

test-clan uses pure dendritic flake-parts pattern validated in Story 1.7:
- Pure import-tree auto-discovery (flake.nix:58)
- Base modules exported to namespace (flake.modules.nixos.base)
- Host modules use namespace imports (with config.flake.modules)
- Zero manual imports in flake.nix

**Apply to Darwin:**
- Create flake.modules.darwin namespace for darwin-specific modules
- blackphos exports to flake.modules.darwin."machines/darwin/blackphos"
- Use namespace imports (not relative paths)

### Home-Manager Integration Patterns

**Option A: Integrated (Recommended)**
```nix
# In blackphos darwin module
imports = [
  inputs.home-manager.darwinModules.home-manager
];

home-manager.users.raquel = {
  # home config here
};
```

**Option B: Standalone**
```nix
# Separate homeConfigurations
homeConfigurations."raquel@blackphos" = ...
```

**Recommendation:** Option A (integrated) - simpler activation, proven in mic92 example

### Clan Vars: The Unified Secrets and Generated Values System

**Critical Understanding:**
- **Clan vars IS the standard way to manage both secrets AND generated values** (clan-core docs: secrets.md lines 1-2)
- **Clan vars uses sops-nix as its default encryption backend** (clan-core docs: vars-overview.md lines 100-103, secrets.md lines 12-13)
- **macOS explicitly supports clan vars** (clan-core docs: macos.md line 10)
- **NOT a choice between sops-nix OR clan vars** - clan vars uses sops underneath!

**How Clan Vars Works:**
1. **Declare generators** using `clan.core.vars.generators.<name>` pattern
2. **Define generation logic:**
   - `prompts`: Collect user input (passwords, tokens)
   - `script`: Generation logic (mkpasswd, ssh-keygen, certificate generation)
   - `files`: Output files (marked secret=true/false)
3. **Generate values:** `clan vars generate <machine>` runs generators and encrypts secrets
4. **Deploy automatically:** Secrets decrypted at runtime to /run/secrets/ via sops-nix integration
5. **Access in config:** `config.clan.core.vars.generators.<name>.files.<file>.path`

**Storage Architecture:**
- **Secret files** (secret=true): Encrypted with sops, stored in git, decrypted at activation
- **Public files** (secret=false): Stored in nix store, no encryption needed
- **Encryption backend**: sops (default), or password-store (alternative)
- **Age keys**: `~/.config/sops/age/keys.txt` or `SOPS_AGE_KEY` env var

**Migration from Raw sops-nix:**
- **If existing sops secrets:** Use `clan secrets import-sops` to migrate (secrets.md lines 234-248)
- **If no secrets yet:** Define generators from scratch
- **Result:** Same sops encryption, better declarative interface

**Example Generator (Password Hash):**
```nix
clan.core.vars.generators.root-password = {
  prompts.password.description = "Root password";
  prompts.password.type = "hidden";
  prompts.password.persist = false;
  files.hash.secret = false;  # Hash can be in nix store
  script = ''
    mkpasswd -m sha-512 < $prompts/password > $out/hash
  '';
  runtimeInputs = [ pkgs.mkpasswd ];
};

users.users.root.hashedPasswordFile =
  config.clan.core.vars.generators.root-password.files.hash.path;
```

**Why Use Clan Vars Instead of Raw sops-nix:**
- **Declarative generation:** Define once, regenerate with `clan vars generate --regenerate`
- **User prompts:** Interactive input collection, no manual file creation
- **Cross-machine sharing:** `share = true` for shared secrets across machines
- **Dependency management:** Generators can depend on other generators (e.g., CA → intermediate certs)
- **Type safety:** Separate secret vs public file handling
- **Integrated workflow:** Works seamlessly with `clan machines update`

**References:**
- clan-core docs: guides/vars/vars-overview.md (architecture and benefits)
- clan-core docs: guides/vars/vars-concepts.md (design principles)
- clan-core docs: guides/vars/vars-backend.md (complete generator examples)
- clan-core docs: guides/secrets.md (underlying sops integration)
- clan-core docs: guides/macos.md (macOS vars support confirmation)

### Darwin vs NixOS in Clan Context

**Differences to Handle:**
- machineClass = "darwin" (not "nixos")
- darwinConfigurations (not nixosConfigurations)
- darwin-rebuild (not nixos-rebuild)
- No disko (darwin uses existing APFS)
- No initrd (darwin boot process different)
- Homebrew required for GUI apps
- Different system paths (/Library/ vs /etc/)

### nixos-unified vs Dendritic + Clan

**infra (nixos-unified):**
- Configurations in configurations/ directory
- autoWire automatically creates nixosConfigurations and darwinConfigurations
- Home-manager integrated via nixos-unified
- Modules in modules/ automatically discovered
- flake.nix imports nixos-unified.flakeModules.{default,autoWire}

**test-clan (dendritic + clan):**
- Configurations in modules/machines/
- Manual clan.machines registration
- Home-manager integrated via home-manager.darwinModules or standalone
- Modules auto-discovered via import-tree
- flake.nix uses pure import-tree pattern

**Transformation:**
1. configurations/darwin/blackphos.nix → modules/machines/darwin/blackphos/default.nix
2. Remove nixos-unified autoWire dependency
3. Convert to dendritic flake-parts module pattern
4. Add clan.machines registration
5. Add to clan inventory
6. Convert imports to namespace pattern

---

## References

**test-clan Repository:**
- Pattern source: ~/projects/nix-workspace/test-clan/
- Story 1.7 completion notes: Full dendritic pattern validated
- Pure import-tree pattern: flake.nix:58
- Module organization: modules/{system,machines,clan,terranix}

**Reference Implementations:**
- mic92-clan-dotfiles/machines/evo: Darwin + sops-nix + clan pattern
- mic92-clan-dotfiles/darwinModules: Darwin module examples
- clan-core/machines/test-darwin-machine: Minimal darwin example
- clan-infra/modules/darwin: Limited darwin modules

**infra Repository:**
- Current blackphos config: configurations/darwin/blackphos.nix
- Home config: configurations/home/raquel@blackphos.nix
- Darwin modules: modules/darwin/
- Home modules: modules/home/
- nixos-unified integration: modules/flake-parts/nixos-flake.nix

**Documentation:**
- Story 1.7: docs/notes/development/work-items/1-7-execute-dendritic-refactoring-in-test-clan-using-test-harness.md
- Epic 1: docs/notes/development/epics.md (lines 36-362)
- CLAUDE.md: Machine fleet information

---

## Risk Mitigation

### Deployment Risks

**Risk:** System becomes unusable after deployment
**Mitigation:**
- Time Machine backup before deployment
- Test build before switch
- Keep infra configuration intact (rollback available)
- Deploy during low-criticality time
- Have raquel available for validation

**Risk:** Home-manager activation fails
**Mitigation:**
- Test home-manager separately first
- Validate home config builds before deployment
- Keep existing home-manager config accessible
- Document rollback procedure

**Risk:** Secrets inaccessible after migration
**Mitigation:**
- Keep sops-nix (proven pattern)
- Verify age keyfile exists before deployment
- Test secrets access in build
- Document secrets configuration

### Pattern Risks

**Risk:** Darwin + clan pattern not well-documented
**Mitigation:**
- Study mic92 darwin example thoroughly
- Start with minimal config, add incrementally
- Document all decisions and rationale
- Ask for user guidance if pattern unclear

**Risk:** Dendritic pattern conflicts with darwin
**Mitigation:**
- Story 1.7 validated dendritic works (nixos)
- Pattern is framework-agnostic (should work for darwin)
- Test early, validate builds before deployment

### Data Risks

**Risk:** Data loss during migration
**Mitigation:**
- No data stored in nix configuration (only /nix/store affected)
- User data in /Users unchanged by darwin-rebuild
- Time Machine backup covers user data
- Minimal data risk (configuration-only change)

---

## Definition of Done

- [ ] blackphos darwin configuration created in test-clan following dendritic pattern
- [ ] Home-manager integrated for crs58 (admin) and raquel (primary user)
- [ ] blackphos added to clan inventory with correct tags and machineClass
- [ ] Secrets management configured (sops-nix or clan secrets)
- [ ] Configuration builds successfully
- [ ] Deployed to actual blackphos hardware
- [ ] Zero-regression validation complete (package comparison, functionality testing)
- [ ] raquel confirms system fully functional for daily work
- [ ] Transformation pattern documented for Epic 2+ reference
- [ ] Story completion notes capture lessons learned

---

## Dev Notes

### Previous Story Learnings (from Story 1.7)

**From Story 1.7 (Status: done)**

**Dendritic Pattern - Fully Validated:**
- ✅ Pure import-tree auto-discovery works perfectly
- ✅ Base module namespace merging (multiple modules → single namespace)
- ✅ Host modules use namespace imports (self-composition)
- ✅ Feature tests passing (TC-008, TC-009)
- ✅ Zero regressions in nixos context

**Architectural Decisions from Story 1.7:**
1. **Manual Machine Registration Retained:** clan.machines requires explicit configuration (not auto-discoverable). This is acceptable and pragmatic.
2. **Base Module Merging Pattern:** Multiple modules can export to same namespace attribute (flake.modules.nixos.base merges nix-settings + admins + initrd-networking)
3. **Pure Import-Tree Achievable:** flake.nix reduced to 3 lines of logic, all structure in modules

**Lessons Learned:**
- Test harness essential for confident refactoring (Story 1.6 enabled Story 1.7 success)
- Manual registration can be better than automation for infrastructure
- Incremental atomic commits enable safe refactoring
- Strive for minimal flake.nix - structure belongs in modules

**Application to Story 1.8:**
- Use same dendritic pattern for darwin (namespace exports, import-tree)
- Expect manual machine registration (clan.machines.blackphos)
- Create incremental commits (easier to debug)
- Keep flake.nix minimal (no manual imports)

### Architecture Patterns

**Clan Vars: Unified System for Secrets AND Generated Values**

**Corrected Understanding (from clan-core docs):**
- **Clan vars is THE standard way** to manage both secrets AND generated values
- **Clan vars uses sops-nix** as its default encryption backend (not separate from sops)
- **macOS explicitly supports clan vars** (confirmed in clan-core docs: macos.md)
- **Generators** define how to create files from user prompts and/or generation scripts
- **Both user secrets AND generated values** use the same `clan.core.vars.generators` pattern

**Unified Pattern for All Managed Files:**
```nix
# User secret (password hash)
clan.core.vars.generators.root-password = {
  prompts.password.description = "Root password";
  prompts.password.type = "hidden";
  files.hash.secret = false;  # Hash not sensitive
  script = ''
    mkpasswd -m sha-512 < $prompts/password > $out/hash
  '';
  runtimeInputs = [ pkgs.mkpasswd ];
};

# Generated value (SSH host key)
clan.core.vars.generators.ssh-host-key = {
  files."ed25519_priv".secret = true;  # Private key encrypted
  files."ed25519".secret = false;       # Public key in git
  script = ''
    ssh-keygen -t ed25519 -N "" -f $out/ed25519
    mv $out/ed25519 $out/ed25519_priv
  '';
  runtimeInputs = [ pkgs.openssh ];
};
```

**Why mic92 Uses Raw sops-nix:**
The mic92 darwin example uses raw `sops.secrets` because it predates the clan vars system or is using legacy patterns. The clan-core docs explicitly recommend using vars instead (secrets.md lines 1-2: "should use Vars directly instead").

**Migration Approach:**
- **Don't replicate mic92's raw sops-nix usage** - it's the old way
- **Use clan vars generators** - it's the modern, declarative clan-core pattern
- **Still uses sops encryption** - just with better interface
- **Migration tool available:** `clan secrets import-sops` for existing sops secrets

### Project Structure Alignment

**infra (nixos-unified) Structure:**
```
configurations/
  darwin/blackphos.nix
  home/raquel@blackphos.nix
modules/
  darwin/{all,default.nix,colima.nix}
  home/{all,darwin-only,default.nix,standalone.nix,modules/}
```

**test-clan (dendritic + clan) Target Structure:**
```
modules/
  machines/
    darwin/
      blackphos/
        default.nix  # Dendritic module exporting to namespace
  clan/
    inventory/machines.nix  # Add blackphos entry
    machines.nix  # Register blackphos
  system/  # Darwin base modules (if needed)
  home/  # Home-manager modules (if separate)
```

**Transformation Mapping:**
- configurations/darwin/blackphos.nix → modules/machines/darwin/blackphos/default.nix (convert to dendritic module)
- configurations/home/raquel@blackphos.nix → Integrated into blackphos/default.nix OR separate home modules
- modules/darwin/* → May need to recreate as dendritic darwin base modules
- nixos-unified autoWire → Manual clan.machines registration

---

## Dev Agent Record

### Context Reference

- `docs/notes/development/work-items/1-8-migrate-blackphos-from-infra-to-test-clan.context.xml`

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List
