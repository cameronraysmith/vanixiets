# Story 1.10C Code Review Prompt

**COPY EVERYTHING BELOW THIS LINE for fresh Claude Code session:**

---

Code Review: Story 1.10C - Establish sops-nix Secrets for Home-Manager

**Repository:** ~/projects/nix-workspace/test-clan/

**Work Item:** ~/projects/nix-workspace/infra/docs/notes/development/work-items/1-10c-establish-sops-nix-secrets-home-manager.md

**Context XML:** ~/projects/nix-workspace/infra/docs/notes/development/work-items/1-10c-establish-sops-nix-secrets-home-manager.context.xml

**Epic Definition:** ~/projects/nix-workspace/infra/docs/notes/development/epics/epic-1-architectural-validation-migration-pattern-rehearsal-phase-0.md (Story 1.10C: lines 894-1127)

## Review Context

### Story Objective

Establish sops-nix secrets management for home-manager user configurations in test-clan, validating the user-level secrets tier of the two-tier architecture discovered during Epic 1 architectural validation.

### Architectural Significance

**Critical Discovery:** Clan vars requires NixOS-specific `_class` parameter, incompatible with nix-darwin home-manager. Story 1.10C validates sops-nix as the correct pattern for user-level secrets across Epic 2-6 (6 machines, 4+ users).

**Two-Tier Secrets Architecture:**
- **System-Level (Future, Epic 2+):** clan vars for NixOS/darwin system configs
- **User-Level (Current, Story 1.10C):** sops-nix for home-manager user configs

**Age Key Pattern:** SSH-derived age keys reused across infra sops-nix, clan users, and test-clan sops-nix. One SSH keypair → one age keypair → three usage contexts.

### Reference Implementation

**Proven Pattern:** ~/projects/nix-workspace/infra/
- Working sops-nix home-manager: modules/home/all/core/sops.nix
- Multi-user encryption: .sops.yaml with &admin-user, &raquel-user anchors
- Age key management: justfile (`just sops-sync-keys`), scripts/sops/sync-age-keys.sh

## Review Scope

### Acceptance Criteria (24 ACs across 7 sections)

**Section A: Configuration (AC1-AC3)**
- AC1: .sops.yaml creation with multi-user age keys
- AC2: Creation rules for user secrets paths
- AC3: YAML anchor/alias structure for key reuse

**Section B: User Secrets (AC4-AC8)**
- AC4: crs58 secrets.yaml with API keys
- AC5: raquel secrets.yaml with API keys
- AC6: Multi-user encryption (both users can decrypt own secrets)
- AC7: Secret value import from infra
- AC8: Proper YAML structure and sops metadata

**Section C: Module Integration (AC9-AC12)**
- AC9: home-manager sops-nix module for crs58
- AC10: home-manager sops-nix module for raquel
- AC11: sops.secrets attributes (file, owner, mode)
- AC12: Age key configuration (sops.age.keyFile or sops.age.generateKey)

**Section D: Build Validation (AC13-AC16)**
- AC13: crs58 homeConfiguration builds without errors
- AC14: raquel homeConfiguration builds without errors
- AC15: No evaluation errors, no infinite recursion
- AC16: Activation packages generate successfully

**Section E: Multi-User Isolation (AC17-AC19)**
- AC17: crs58 cannot decrypt raquel's secrets
- AC18: raquel cannot decrypt crs58's secrets
- AC19: Private age keys properly isolated

**Section F: Key Management (AC20-AC22)**
- AC20: Age keys match infra .sops.yaml references
- AC21: Age keys match clan user keys (sops/users/*/key.json)
- AC22: SSH-to-age conversion pattern documented

**Section G: Documentation (AC23-AC24)**
- AC23: age-key-management.md guide complete (SSH-to-age lifecycle)
- AC24: Section 12 in test-clan-validated-architecture.md (two-tier secrets)

### Implementation Tasks

- Task 1: SKIPPED (infra reference exists) ✓
- Task 2: Create test-clan .sops.yaml (1h)
- Task 3: Import secret values from infra (45m)
- Task 4: Create sops-nix home-manager modules (1h)
- Task 5: Build validation (30m)
- Task 6: Integration testing (30m)
- Task 7: Documentation (60m)

**Estimated Effort:** 4.75 hours

## Three Quality Gates (MUST ALL PASS)

### Gate 1: Configuration Validation

**1.1 .sops.yaml Structure**
```bash
cd ~/projects/nix-workspace/test-clan

# Verify .sops.yaml exists
test -f .sops.yaml && echo "✓ .sops.yaml exists" || echo "✗ .sops.yaml missing"

# Check structure
cat .sops.yaml
```

**Expected:**
- YAML anchors for age keys (&crs58-user, &raquel-user)
- Creation rules for sops/secrets/crs58/** and sops/secrets/raquel/**
- Age key references match infra .sops.yaml

**1.2 Age Key Correspondence**
```bash
# Extract age keys from test-clan .sops.yaml
grep -A1 '&crs58-user' .sops.yaml
grep -A1 '&raquel-user' .sops.yaml

# Compare with infra .sops.yaml
grep -A1 '&admin-user' ~/projects/nix-workspace/infra/.sops.yaml
grep -A1 '&raquel-user' ~/projects/nix-workspace/infra/.sops.yaml

# Compare with clan user keys
jq -r '.publickey' sops/users/crs58/key.json
jq -r '.publickey' sops/users/raquel/key.json
```

**Expected:** All three sources (test-clan .sops.yaml, infra .sops.yaml, clan user keys) must have matching age public keys for each user.

**1.3 Encryption Test**
```bash
# Test encryption with crs58 key
echo "test secret" | sops --encrypt --age $(jq -r '.publickey' sops/users/crs58/key.json) /dev/stdin > /tmp/test-crs58.yaml

# Test encryption with raquel key
echo "test secret" | sops --encrypt --age $(jq -r '.publickey' sops/users/raquel/key.json) /dev/stdin > /tmp/test-raquel.yaml

# Verify encrypted files are valid YAML
sops --decrypt /tmp/test-crs58.yaml
sops --decrypt /tmp/test-raquel.yaml
```

**Expected:** Both encryption/decryption operations succeed without errors.

**1.4 User Secrets Files**
```bash
# Verify user secrets files exist
test -f sops/secrets/crs58/secrets.yaml && echo "✓ crs58 secrets exist" || echo "✗ crs58 secrets missing"
test -f sops/secrets/raquel/secrets.yaml && echo "✓ raquel secrets exist" || echo "✗ raquel secrets missing"

# Decrypt and inspect (verify no plaintext committed)
sops --decrypt sops/secrets/crs58/secrets.yaml | head -20
sops --decrypt sops/secrets/raquel/secrets.yaml | head -20
```

**Expected:**
- Both files exist and are properly encrypted
- Decryption succeeds with valid YAML structure
- Files contain API keys, tokens, or other user secrets
- Files contain sops metadata (mac, encrypted_suffix, version)

### Gate 2: Build Validation

**2.1 Home-Manager Module Structure**
```bash
# Verify sops modules exist
fd -t f sops.nix modules/home/

# Expected pattern (following Pattern A):
# modules/home/all/core/sops.nix (if shared)
# OR modules/home/crs58/sops.nix + modules/home/raquel/sops.nix (if per-user)
```

**Expected:**
- sops-nix home-manager modules exist following Pattern A dendritic structure
- Modules define sops.secrets.* attributes
- Modules reference user-specific secrets paths
- Age key configuration (sops.age.keyFile or sops.age.generateKey)

**2.2 Build Success**
```bash
cd ~/projects/nix-workspace/test-clan

# Build crs58 home configuration
nix build .#homeConfigurations.crs58.activationPackage --show-trace 2>&1 | tee /tmp/build-crs58.log

# Build raquel home configuration
nix build .#homeConfigurations.raquel.activationPackage --show-trace 2>&1 | tee /tmp/build-raquel.log

# Check exit codes
echo "crs58 build: $?"
echo "raquel build: $?"
```

**Expected:**
- Both builds succeed (exit code 0)
- No evaluation errors
- No infinite recursion
- No missing attribute errors
- Activation packages generated in result/

**2.3 Build Output Inspection**
```bash
# Inspect activation package structure
ls -la result/
ls -la result/activate
ls -la result/home-files/

# Check for sops-related files
find result/ -name "*sops*" -o -name "*secrets*"
```

**Expected:**
- Activation package contains home-manager files
- sops-nix integration files present
- No errors in activation script

### Gate 3: Integration Validation

**3.1 Multi-User Isolation**
```bash
# Verify crs58 CANNOT decrypt raquel's secrets
# (should fail with permission/key error)
sops --decrypt sops/secrets/raquel/secrets.yaml 2>&1 | grep -i "no key" && echo "✓ Isolation verified" || echo "✗ Isolation broken"

# Verify raquel CANNOT decrypt crs58's secrets (if raquel's key is in ~/.config/sops/age/keys.txt)
# This test assumes only crs58's private key is in keys.txt
# If raquel's key is also present, this test is N/A
```

**Expected:**
- Users cannot decrypt each other's secrets
- Encryption uses user-specific age keys
- Private keys properly isolated

**3.2 Age Key File Configuration**
```bash
# Check sops module configuration
rg -A 5 "sops\.age\." modules/home/ --type nix

# Expected patterns:
# sops.age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
# OR sops.age.generateKey = true; (generates per-user key)
```

**Expected:**
- Age key configuration present
- Path references valid location
- OR generateKey enabled for per-user keys

**3.3 Secret Attribute Validation**
```bash
# Inspect sops.secrets attributes
rg "sops\.secrets\." modules/home/ --type nix -A 3

# Expected attributes:
# sops.secrets.<name>.file = path-to-encrypted-file
# sops.secrets.<name>.mode = "0600" (or appropriate permissions)
# sops.secrets.<name>.owner = config.home.username (or appropriate user)
```

**Expected:**
- Secret attributes properly defined
- File paths reference sops/secrets/*/secrets.yaml
- Permissions appropriate (0600 for sensitive files)
- Owner matches user

### Gate 4: Documentation Review (AC23-AC24)

**4.1 age-key-management.md Guide**
```bash
# Verify guide exists
test -f docs/guides/age-key-management.md && echo "✓ Guide exists" || echo "✗ Guide missing"

# Check structure
grep -E "^#{1,3}" docs/guides/age-key-management.md

# Expected sections:
# - Overview
# - Prerequisites
# - Key Generation
# - Verification
# - Multi-Context Usage
# - Security Considerations
# - Troubleshooting
# - Reference
```

**Content Review:**
- Explains SSH-to-age conversion lifecycle
- Documents ssh-to-age tool usage
- Includes validation commands (age-keygen -y, jq)
- Covers multi-context reuse (infra, clan, test-clan)
- Addresses security (private key storage, Bitwarden backup)
- Provides troubleshooting guidance

**4.2 Section 12: Secrets Architecture**
```bash
# Verify Section 12 exists in architecture doc
grep -A 50 "^## 12\." ~/projects/nix-workspace/infra/docs/notes/development/test-clan-validated-architecture.md
```

**Expected Content:**
- Two-tier secrets model documented (system vs user)
- Age key derivation pattern (SSH → age via ssh-to-age)
- Key correspondence validation (infra ↔ clan ↔ test-clan)
- Multi-context reuse architecture
- sops-nix home-manager integration patterns

## Security Checklist

**Critical Security Validations:**

1. **No Private Keys Committed**
```bash
# Check for accidentally committed private keys
rg -i "AGE-SECRET-KEY" . --type yaml --type nix
rg -i "BEGIN.*PRIVATE KEY" . --type yaml --type nix

# Expected: No matches (only public keys should be present)
```

2. **Secrets Properly Encrypted**
```bash
# Verify secrets files are encrypted (not plaintext)
head -5 sops/secrets/crs58/secrets.yaml | grep "sops:" && echo "✓ Encrypted" || echo "✗ PLAINTEXT!"
head -5 sops/secrets/raquel/secrets.yaml | grep "sops:" && echo "✓ Encrypted" || echo "✗ PLAINTEXT!"
```

3. **Gitignore Coverage**
```bash
# Verify sensitive paths in .gitignore
grep -E "(keys\.txt|\.age|secrets\.yaml$)" .gitignore
```

**Expected:**
- Private key paths ignored
- Decrypted secrets ignored
- Only encrypted .yaml files tracked

4. **File Permissions**
```bash
# Check permissions on encrypted files
ls -la sops/secrets/crs58/secrets.yaml
ls -la sops/secrets/raquel/secrets.yaml

# Should be 0600 or 0644 (encrypted files can be world-readable)
```

## Code Quality Review

**Pattern Alignment:**

1. **Dendritic Pattern A Compliance**
   - Modules in modules/home/{all,crs58,raquel}/ structure
   - Following existing test-clan Pattern A conventions
   - Consistent with Stories 1.1-1.10BA refactoring

2. **Reference Implementation Fidelity**
   - Compare with infra modules/home/all/core/sops.nix
   - Verify similar attribute structure
   - Check for cargo-culted code without understanding

3. **Nix Code Quality**
   - No hardcoded paths (use config.home.homeDirectory)
   - Proper string interpolation
   - Attribute sets properly structured
   - No eval warnings or deprecation notices

## Commit History Review

**Expected Atomic Commits:**

1. Task 2: Create .sops.yaml configuration
2. Task 3: Import user secrets (crs58, raquel)
3. Task 4a: Create sops-nix module (crs58)
4. Task 4b: Create sops-nix module (raquel)
5. Task 5: Build validation fixes (if needed)
6. Task 6: Integration testing fixes (if needed)
7. Task 7a: Create age-key-management.md
8. Task 7b: Add Section 12 to architecture doc

**Review Each Commit:**
```bash
# List story commits
git log --oneline --grep="1.10C" -i

# Review each commit individually
git show <commit-hash>
```

**Quality Checks:**
- One logical change per commit
- Conventional commit messages
- No mixed concerns
- No fixup commits (should be squashed)

## Epic 1 Alignment Review

**Strategic Validation:**

1. **Epic 1 Mission:** Does this implementation validate the sops-nix pattern for Epic 2-6 migration (6 machines, 4+ users)?

2. **Pattern Reusability:** Can these modules be copied to infra with minimal changes?

3. **Documentation Completeness:** Do age-key-management.md and Section 12 provide sufficient guidance for Epic 2-6 implementation?

4. **Architectural Consistency:** Does the implementation align with the two-tier secrets model?

## Review Deliverable

**Provide Structured Review with:**

1. **Quality Gates Status**
   - Gate 1: Configuration Validation [PASS/FAIL]
   - Gate 2: Build Validation [PASS/FAIL]
   - Gate 3: Integration Validation [PASS/FAIL]
   - Gate 4: Documentation [PASS/FAIL]

2. **Acceptance Criteria Coverage**
   - List any failing ACs with specific details
   - Highlight any missing functionality

3. **Security Findings**
   - Critical: Any private keys committed, plaintext secrets
   - High: Missing encryption, permission issues
   - Medium: Documentation gaps, unclear patterns

4. **Code Quality Assessment**
   - Pattern alignment (dendritic Pattern A)
   - Reference implementation fidelity
   - Nix code quality

5. **Commit History Assessment**
   - Atomic commit compliance
   - Commit message quality
   - Logical change grouping

6. **Recommendations**
   - Required changes (blocking DoD)
   - Suggested improvements (optional)
   - Epic 2-6 preparation notes

7. **DoD Verdict**
   - **APPROVED:** All gates pass, ready for Story 1.10D
   - **CONDITIONAL:** Minor issues, can proceed with fixes
   - **REJECTED:** Major issues, requires rework

## SlashCommand Invocation

After reviewing this context, execute:

```
/bmad:bmm:workflows:code-review
```

Provide the work item path when prompted:
```
docs/notes/development/work-items/1-10c-establish-sops-nix-secrets-home-manager.md
```

**Review Duration:** Expect 45-90 minutes for comprehensive review including all quality gates, security validation, and documentation assessment.

---

**END OF CODE REVIEW PROMPT**
