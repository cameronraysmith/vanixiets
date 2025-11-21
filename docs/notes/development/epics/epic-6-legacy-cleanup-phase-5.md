# Epic 6: Legacy Cleanup (Phase 5)

**Goal:** Remove nixos-unified infrastructure and finalize migration

**Strategic Value:** Clean dendritic + clan architecture, improved maintainability, migration complete

**Timeline:** 1 week cleanup + documentation

**Success Criteria:**
- nixos-unified completely removed
- Secrets migration strategy finalized (full or hybrid)
- Documentation updated and accurate
- Clean architecture with no legacy dependencies

---

## Story 6.1: Remove nixos-unified infrastructure

As a system administrator,
I want to remove all nixos-unified infrastructure from nix-config,
So that the codebase reflects clean dendritic + clan architecture.

**Acceptance Criteria:**
1. configurations/ directory deleted (host-specific nixos-unified configs no longer needed)
2. nixos-unified flake input removed from flake.nix
3. nixos-unified flakeModules imports removed from modules
4. All hosts verified building without nixos-unified: `nix flake check`
5. Git history preserved: commits clearly show removal with rationale
6. No references to nixos-unified remain in codebase
7. All 5 machines rebuild successfully after removal

**Prerequisites:** Epic 4 complete + Epic 5 (if executed)

---

## Story 6.2: Finalize secrets migration strategy

As a system administrator,
I want to finalize the secrets migration strategy (full clan vars or hybrid),
So that secrets management is clean and well-documented.

**Acceptance Criteria:**
1. Secrets inventory completed: all secrets categorized (generated vs external)
2. Migration decision made: full clan vars or hybrid sops-nix + clan vars
3. If full migration: all remaining secrets migrated to clan vars, sops-nix removed
4. If hybrid approach: rationale documented, sops-nix configuration cleaned up for only external secrets
5. SECRETS-STRATEGY.md created documenting:
   - What secrets are managed where (clan vars vs sops-nix)
   - Rationale for approach chosen
   - Procedures for adding new secrets
   - Recovery procedures if secrets lost
6. All machines validated with final secrets configuration
7. Secrets management clean and maintainable

**Prerequisites:** Story 6.1 (nixos-unified removed)

---

## Story 6.3: Update documentation and finalize migration

As a system administrator,
I want to update all documentation to reflect completed migration,
So that the repository accurately represents the dendritic + clan architecture.

**Acceptance Criteria:**
1. README.md updated to reflect dendritic + clan architecture (remove nixos-unified references)
2. Migration experience documented in docs/notes/development/MIGRATION-RETROSPECTIVE.md:
   - What went well
   - Challenges encountered
   - Lessons learned
   - Time spent vs. estimates
   - Final assessment of dendritic + clan combination
3. Architectural decisions captured in docs/notes/development/ARCHITECTURE-DECISIONS.md:
   - Why dendritic + clan
   - Compromises made
   - Patterns adopted
   - Future considerations
4. Patterns documented for maintainability (reference for future work)
5. All 5 machines operational with no legacy dependencies
6. Migration declared complete, clan branch merged to main if appropriate
7. Retrospective completed: extract insights for future infrastructure work

**Prerequisites:** Story 6.2 (secrets finalized)

---
