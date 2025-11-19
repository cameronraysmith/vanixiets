# Dendritic Flake-Parts Research Index

This directory contains comprehensive research into dendritic flake-parts patterns for managing multi-machine Nix configurations.

## Documents

### 1. dendritic-machine-modules-pattern.md
**Comprehensive research document with code examples and reference implementations**

Main findings:
- Your current test-clan approach (direct import of machine-local sub-modules) is correct
- Three-level module hierarchy: Shared (Level 1) → Machine Root (Level 2) → Machine-Local (Level 3)
- Never wrap machine-local sub-modules in flake.modules
- Three design patterns based on complexity

Sections:
- Key findings and your current approach correctness
- Three levels of module organization
- Evidence from 4 reference implementations (test-clan, drupol, gaetanlepage, dendrix)
- Three design patterns (inline, sibling files, subdirectories)
- import-tree auto-discovery rules
- Special cases (disko.nix pattern)
- Comprehensive code examples

**Read this for**: Complete understanding of the pattern with examples

### 2. module-hierarchy-diagram.txt
**ASCII diagrams showing the three-level module hierarchy and discovery flow**

Contents:
- Visual representation of all three levels
- import-tree auto-discovery mechanism
- Pattern B (current test-clan): Sibling files for 3-10 services
- Pattern C: Subdirectories for 10+ services
- Critical rule (what NOT to do)
- Detailed explanation of why direct import for Level 3
- Module discovery flow from flake.nix to machine configuration
- Complete architecture summary

**Read this for**: Quick visual understanding of the structure

## Quick Reference

### Your Current Approach (test-clan) - CORRECT ✓

```
modules/machines/darwin/blackphos/
├── default.nix          → exports: flake.modules.darwin."machines/darwin/blackphos"
└── zerotier.nix        → imported: ./zerotier.nix (NOT flake.modules)
```

### The Rule

- **Level 1 (Shared)**: Auto-discovered, export to flake.modules
- **Level 2 (Machine Root)**: Auto-discovered, export to flake.modules
- **Level 3 (Machine-Local)**: Manually imported, direct paths ONLY

### Never Do This

```nix
# WRONG - Don't wrap machine-local modules in flake.modules
flake.modules.darwin."machines/darwin/blackphos/zerotier" = { ... };
```

### Why Direct Import?

1. Composition control (machine maintainers choose what to import)
2. Locality (sub-modules only relevant to their parent)
3. Simplicity (avoids namespace pollution)
4. Merge semantics (flake.modules is for discovery, not composition)
5. import-tree design (ignores /_/ paths anyway)

## Research Methodology

Examined multiple dendritic implementations:

1. **test-clan** (`~/projects/nix-workspace/test-clan/`)
   - Current working repository
   - blackphos (darwin) with zerotier.nix sub-module
   - cinnabar (nixos) with disko.nix sub-module

2. **drupol-dendritic-infra** (`~/projects/nix-workspace/drupol-dendritic-infra/`)
   - Complex infrastructure with 8+ machines
   - Hosts pattern with machine-specific configuration
   - Shows flake-parts orchestration layer

3. **gaetanlepage-dendritic-nix-config** (`~/projects/nix-workspace/gaetanlepage-dendritic-nix-config/`)
   - Large-scale infrastructure with 30+ services per machine
   - Demonstrates Pattern C (_services/ subdirectory)
   - Shows how to organize complex machines

4. **dendrix-dendritic-nix** and **mightyiam-dendritic-infra**
   - Reference implementations showing various patterns
   - Community examples of dendritic architecture

## Key Insights

### Three Design Patterns by Complexity

| Machines | Pattern | Example |
|----------|---------|---------|
| Simple (1-2 features) | Inline in default.nix | All config in one file |
| Medium (3-10 services) | Sibling files with direct import | **YOUR CURRENT APPROACH** |
| Complex (10+ services) | _services/ subdirectory | gaetanlepage tank machine |

### import-tree Rules

- Recursively discovers all .nix files under modules/
- Ignores paths containing /_/ (underscore as directory component)
- Files exporting flake.modules.* are registered in the module system
- Machine root modules become part of flake.modules.<os>

### Module Export Patterns

**Level 1 (Shared)**: Export to flat namespace
```nix
flake.modules.darwin.base = { ... };
```

**Level 2 (Machine Root)**: Export to path namespace
```nix
flake.modules.darwin."machines/darwin/blackphos" = { ... };
```

**Level 3 (Machine-Local)**: Direct import, no export
```nix
{ system.activationScripts... }  # Plain module
```

## When to Use Each Pattern

### Pattern A: Inline (Simple Machines)
- Pros: Minimal structure, everything in one place
- Cons: Gets unwieldy with 5+ distinct concerns
- Use when: Machine has basic configuration

### Pattern B: Sibling Files (Medium Machines)
- Pros: Clear separation of concerns, readable
- Cons: Hard to organize beyond 10 files
- Use when: 3-10 distinct features (zerotier, hardware, services)
- **RECOMMENDED FOR infra**

### Pattern C: _services/ Subdirectory (Complex Machines)
- Pros: Scalable to 30+ services
- Cons: Additional indirection
- Use when: 10+ services per machine (database, web, backup, etc.)

## Transition Path for infra

**Current status**: Using Pattern B in test-clan (correct)

**Future growth**:
1. Machines up to 5-10 sub-modules → Keep Pattern B
2. If growing beyond 10 sub-modules → Adopt Pattern C with _services/ directory

## Related Files

- CLAUDE.md (project context)
- docs/notes/development/architecture/ (architecture documentation)
- docs/notes/development/PRD/ (product requirements)

## References

- import-tree: https://github.com/vic/import-tree
- Dendritic Pattern: https://github.com/mightyiam/dendritic
- flake-parts: https://github.com/hercules-ci/flake-parts

## Questions Answered

Q: Should machine-local modules wrap in flake.modules?
A: No. Direct import only. See dendritic-machine-modules-pattern.md

Q: How does import-tree discover modules?
A: Recursively finds .nix files, skips /_/ paths. See module-hierarchy-diagram.txt

Q: What's the difference between disko pattern and sibling modules?
A: disko.nix exports to flake.modules for auto-merge; others import directly. Both valid.

Q: When should I use _services/ pattern?
A: When machine has 10+ sub-modules. See dendritic-machine-modules-pattern.md Pattern C.

Q: Is the current test-clan approach correct?
A: Yes, absolutely. It follows dendritic patterns perfectly.
