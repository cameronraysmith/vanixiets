# Documentation terminology inventory

This document inventories how module system, flake-parts, and dendritic terminology is used across the 74 documentation files in `packages/docs/src/content/docs/`.
It classifies usage as conceptual (explaining WHY patterns work) vs practical (explaining HOW to use them) to guide terminology refinement during Phase 3.

## Summary statistics

- **Total documentation files**: 74
- **Files with relevant terminology**: 46 unique files
- **Total occurrences**:
  - "flake-parts": 180 occurrences across 36 files
  - "dendritic": 289 occurrences across 42 files
  - "module system": 48 occurrences across 16 files
  - "deferredModule": 0 occurrences
  - "evalModules": 0 occurrences

### Key findings

1. **No current usage of module system primitives terminology**: The documentation doesn't currently use "deferredModule" or "evalModules" anywhere, meaning all conceptual explanations implicitly assume flake-parts without grounding in underlying module system.

2. **Heavy dendritic usage**: 289 occurrences show "dendritic" is the primary conceptual frame, often conflating the organizational pattern with the underlying mechanism.

3. **Flake-parts used both conceptually and practically**: "flake-parts" appears in both "why this works" and "how to use" contexts without clear distinction.

4. **Module system terminology isolated**: "module system" appears 48 times but mostly in requirements/context docs, rarely in conceptual explanations of patterns.

## Classification criteria

- **Should lift to module system**: Term used to explain WHY a pattern works (conceptual/foundational)
- **Keep flake-parts**: Term used for HOW to do something (practical/implementation)
- **Add module system alongside**: Add algebraic term while keeping practical flake-parts term
- **Update dendritic → deferred module composition**: When dendritic describes the underlying mechanism rather than the organizational convention

## High priority files (conceptual documentation)

These files explain core concepts and should ground explanations in module system primitives.

### concepts/dendritic-architecture.md

**Context**: Primary conceptual explanation of the dendritic pattern
**Line count**: 347 lines
**Occurrences**: 13 "dendritic", 9 "flake-parts"

| Line | Term | Context | Classification |
|------|------|---------|----------------|
| 2 | "dendritic flake-parts pattern" | Title/description | Update: "deferred module composition pattern (dendritic architecture)" |
| 6 | "dendritic flake-parts pattern" | Core definition | Update: Explain as deferred module composition first, then dendritic as organizational convention |
| 10 | "dendritic flake-parts pattern" | Attribution | Keep: historical attribution |
| 14 | "flake-parts" | Foundation project | Keep: accurate attribution |
| 16 | "dendritic" | Pattern attribution | Keep: historical |
| 20 | "dendrix" | Ecosystem | Keep: accurate |
| 24 | "flake-parts module" | Core principle statement | Add alongside: "Every Nix file is a deferred module (evaluated as a flake-parts module)" |
| 62 | "flake.modules.*" | Namespace merging | Add context: "flake.modules is a flake-parts convention for organizing deferred modules" |
| 142 | "dendritic pattern" | Auto-discovery section | Keep: accurate for organizational pattern |
| 220 | "dendritic" | vs nixos-unified | Keep: organizational comparison |
| 228 | "dendritic" | vs pure flake-parts | Update: "Dendritic adds import-tree auto-discovery to flake-parts' module system foundation" |

**Recommended changes**:

Line 6: Add new section "Understanding the mechanism" after line 21:
```markdown
## Understanding the mechanism

The dendritic pattern works because of three layers:

1. **Module system foundation** (nixpkgs `lib.evalModules`): Deferred modules delay evaluation until import time, enabling composition via fixpoint resolution
2. **Flake-parts framework**: Wraps module system for flake outputs, provides `perSystem` convenience, defines `flake.modules.*` namespace convention
3. **Dendritic organization**: Auto-discovery via import-tree + directory-based namespace merging

The key insight: dendritic is an organizational pattern for deferred modules, not a fundamentally different abstraction.
See [Module System Primitives](/notes/development/modulesystem/primitives.md) for detailed explanation of deferredModule and evalModules.
```

Line 24: Change from:
```markdown
Every Nix file in the repository is a flake-parts module.
```

To:
```markdown
Every Nix file in the repository is a deferred module, evaluated by flake-parts' module system integration.
This means modules can reference the final merged configuration without creating circular dependencies.
```

### development/architecture/adrs/0018-dendritic-flake-parts-architecture.md

**Context**: Architectural decision record for pattern adoption
**Line count**: 323 lines
**Occurrences**: 28 "dendritic", 12 "flake-parts", 3 "module system"

| Line | Term | Context | Classification |
|------|------|---------|----------------|
| 2 | "Dendritic Flake-Parts Architecture" | Title | Keep: accurate ADR title |
| 47 | "dendritic flake-parts pattern" | Decision statement | Add module system context in following paragraph |
| 51 | "flake-parts module" | Pattern overview | Add: "Every .nix file is a deferred module (flake-parts integrates the module system)" |
| 84 | "flake-parts module" | import-tree description | Keep: accurate implementation detail |
| 90 | "flake.modules.*" | Namespace exports | Add: "flake.modules is flake-parts' convention for publishing deferred modules" |
| 166 | "Module discovery" | Table comparison | Add "deferred module" to terminology |
| 244 | "understanding flake.modules.*" | Learning curve discussion | Add: "namespace exports are flake-parts' way of organizing deferred modules" |

**Recommended changes**:

After line 48, add new paragraph:
```markdown
### Module system foundation

The pattern builds on nixpkgs' module system primitives:
- **deferredModule**: Type that delays evaluation, enabling modules to reference the final configuration
- **evalModules**: Fixpoint computation that resolves module definitions into final configuration
- **Flake-parts integration**: Wraps evalModules for flake outputs, adding perSystem and namespace conventions

This foundation explains WHY the pattern works: deferred modules compose cleanly because they form a monoid under concatenation, and auto-discovery works because import-tree simply adds modules to the imports list without changing evaluation semantics.
```

Update line 51 from:
```markdown
Every `.nix` file in the `modules/` directory is a flake-parts module.
```

To:
```markdown
Every `.nix` file in the `modules/` directory is a deferred module.
Flake-parts evaluates these modules with class "flake", providing access to the final flake output configuration during evaluation.
```

### development/architecture/adrs/0020-dendritic-clan-integration.md

**Context**: Integration patterns between dendritic and clan
**Line count**: 374 lines
**Occurrences**: 29 "dendritic", 8 "flake-parts"

| Line | Term | Context | Classification |
|------|------|---------|----------------|
| 7 | "dendritic flake-parts" | Synthesis statement | Keep: accurate cross-reference |
| 18 | "Dendritic exports to flake.modules.*" | Integration challenge | Add: "flake.modules is a deferredModule type that delays evaluation" |
| 23 | "import-tree auto-discovers all *.nix files as flake-parts modules" | Integration challenge | Add: "as deferred modules evaluated by flake-parts" |
| 45 | "modules/ (dendritic)" | Architecture diagram | Keep: organizational label |
| 61 | "namespace export → clan import pattern" | Decision statement | Keep: accurate integration description |

**Recommended changes**:

After line 17 "Namespace boundaries", add clarification:
```markdown
**Module system integration**:
- Dendritic modules are deferredModule type (nixpkgs module system primitive)
- flake.modules.* is a flake-parts option of type `lazyAttrsOf deferredModule`
- Clan machines import these deferred modules, triggering evaluation with clan's module arguments
```

This explains WHY the integration works: both systems use the same underlying module system primitives, just with different evaluation contexts (flake-parts class "flake" vs clan's nixosSystem/darwinSystem).

### concepts/architecture-overview.md

**Context**: High-level architecture overview
**Line count**: ~210 lines
**Occurrences**: 7 "dendritic", 7 "flake-parts"

| Line | Term | Context | Classification |
|------|------|---------|----------------|
| 10 | "flake-parts" | Layer 1 foundation | Keep: accurate layering |
| 12 | "flake-parts" | Foundation description | Add: "flake-parts wraps nixpkgs' evalModules for flake composition" |
| 20 | "dendritic flake-parts pattern" | Layer 2 header | Update: "Deferred module composition (dendritic pattern)" |
| 22 | "dendritic flake-parts pattern" | Layer 2 description | Add module system foundation context |
| 23 | "flake-parts module" | Organization description | Update: "deferred module" with flake-parts context |

**Recommended changes**:

Update line 20-23 section from:
```markdown
### Layer 2: Module organization (dendritic pattern)

Uses the [dendritic flake-parts pattern](/concepts/dendritic-architecture/) for module organization.
Every Nix file is a flake-parts module, organized by *aspect* (feature) rather than by *host*.
```

To:
```markdown
### Layer 2: Deferred module composition (dendritic pattern)

Uses deferred modules (nixpkgs module system primitive) for configuration composition.
Every Nix file is a deferred module that delays evaluation until the final configuration is computed, enabling cross-cutting concerns to reference the merged result.

The [dendritic pattern](/concepts/dendritic-architecture/) organizes these modules by *aspect* (feature) rather than by *host*, with flake-parts providing the evaluation context and namespace conventions.
```

### development/context/glossary.md

**Context**: Terminology reference
**Line count**: ~350 lines
**Occurrences**: 13 "dendritic", 8 "flake-parts", 5 "module system"

| Line | Term | Context | Classification |
|------|------|---------|----------------|
| 38 | "module system" | Definition entry | Expand: add deferredModule and evalModules |
| 142 | "dendritic flake-parts pattern" | Definition entry | Update: reference module system foundation |
| 150 | "flake.modules" | Definition entry | Add: "namespace using deferredModule type" |

**Recommended changes**:

Update line 38 entry from:
```markdown
**module system**: Nix's type-safe configuration composition system with options, types, and validation.
```

To:
```markdown
**module system**: Nix's configuration composition system (nixpkgs `lib.evalModules`) with options, types, and validation.
Core primitives: deferredModule (delays evaluation for fixpoint resolution), evalModules (computes configuration fixpoint), option merging (type-specific merge functions).
See [Module System Primitives](/notes/development/modulesystem/primitives.md).
```

Add new entries after line 38:
```markdown
**deferredModule**: Module system type that delays evaluation until configuration is computed.
Enables modules to reference final merged configuration via fixpoint resolution.
Foundation of dendritic pattern and flake-parts module composition.
Related: evalModules, module system, flake-parts.

**evalModules**: Core function that evaluates modules via fixpoint computation.
Takes modules and specialArgs, returns configuration with options and type checking.
Used by NixOS, nix-darwin, home-manager, and flake-parts.
Related: deferredModule, module system.
```

Update line 142 from:
```markdown
**dendritic flake-parts pattern**: Organizational pattern where every file is a flake-parts module.
```

To:
```markdown
**dendritic flake-parts pattern**: Organizational pattern where every file is a deferred module.
Foundation: nixpkgs module system (deferredModule type, evalModules fixpoint).
Implementation: flake-parts evaluation + import-tree auto-discovery.
Convention: directory-based namespace merging via flake.modules.*.
```

## Medium priority files (guides and tutorials)

These files explain HOW to use the architecture practically. Keep flake-parts terminology but optionally add brief module system context.

### guides/getting-started.md

**Context**: Initial setup guide
**Occurrences**: 2 "flake-parts", 2 "dendritic"

**Classification**: Keep as-is (practical guide)
**Optional addition**: In architecture overview section, add note "Built on nixpkgs module system for type-safe composition"

### guides/adding-custom-packages.md

**Context**: Package customization guide
**Occurrences**: 2 "flake-parts", 3 "dendritic"

**Classification**: Keep as-is (practical instructions)

### guides/host-onboarding.md

**Context**: Machine setup guide
**Occurrences**: 3 "dendritic"

**Classification**: Keep as-is (operational guide)

### tutorials/bootstrap-to-activation.md

**Context**: Development workflow tutorial
**Occurrences**: 7 "dendritic"

**Classification**: Keep as-is (step-by-step tutorial)

**Optional addition**: In "Understanding the architecture" section, add brief note about module system foundation

### tutorials/nixos-deployment.md, tutorials/darwin-deployment.md

**Context**: Deployment tutorials
**Occurrences**: 2 "dendritic" (nixos), 1 "dendritic" (darwin)

**Classification**: Keep as-is (deployment procedures)

## Low priority files (incidental references)

These files have 1-3 casual references in context that doesn't require terminology updates.

### Files with incidental flake-parts references (keep as-is):

- about/contributing/testing.md (2 occurrences)
- about/contributing/multi-arch-containers.md (2 occurrences)
- about/credits.md (3 occurrences)
- reference/repository-structure.md (4 occurrences)
- reference/index.md (1 occurrence)

### Files with incidental dendritic references (keep as-is):

- guides/handling-broken-packages.md (1 occurrence)
- guides/index.md (1 occurrence)
- concepts/index.md (2 occurrences)
- concepts/clan-integration.md (5 occurrences - mostly describes integration, not mechanism)

### Context/requirements docs (neutral - keep existing module system references):

Files in `development/context/` and `development/requirements/` mention "module system" in requirements/constraints context.
These don't explain HOW the module system works, just that it's a requirement.
Keep as-is.

## Additional ADRs and architecture docs

### development/architecture/adrs/0017-dendritic-overlay-patterns.md

**Occurrences**: 10 "dendritic", 9 "flake-parts"

**Classification**: Mostly organizational pattern (dendritic overlay composition)

**Recommended change**: In "Context" section, add note about list concatenation being module system merge semantics:
```markdown
Overlay composition uses the module system's list merge semantics: multiple definitions of the same option merge via concatenation (for list-typed options like nixpkgs.overlays).
This is why dendritic's multiple files exporting to the same namespace work - the module system merges them automatically.
```

### development/architecture/adrs/0019-clan-core-orchestration.md

**Occurrences**: 10 "dendritic", 6 "flake-parts", 3 "module system"

**Classification**: Integration architecture (how clan uses flake-parts modules)

**Recommended change**: In "Integration with dendritic" section, clarify that clan consumes deferred modules:
```markdown
Clan machine configurations import deferred modules from flake.modules.* namespaces.
When clan calls nixosSystem or darwinSystem, it triggers evalModules with those imported modules, resolving the deferred evaluation with system-specific arguments.
```

### development/architecture/adrs/0003-overlay-composition-patterns.md

**Occurrences**: 2 "dendritic", 2 "flake-parts"

**Classification**: Keep as-is (historical ADR, pre-dendritic migration)

### development/architecture/architecture.md

**Occurrences**: 22 "dendritic", 9 "flake-parts"

**Classification**: Architecture synthesis document

**Recommended change**: Add module system layer to "Architectural layers" section:
```markdown
### Layer 0: Module system foundation

- nixpkgs lib.evalModules (fixpoint computation)
- deferredModule type (delayed evaluation)
- Option merging (type-specific merge functions)

### Layer 1: Flake-parts framework

- Wraps evalModules for flake outputs
- Defines flake.modules.* namespace convention
- Provides perSystem abstraction for multi-architecture

### Layer 2: Dendritic organization

- Auto-discovery via import-tree
- Directory-based namespace merging
- Aspect-oriented module structure
```

## Terminology usage patterns

### Current patterns (before Phase 3)

1. **"dendritic flake-parts pattern"**: Used 40+ times as compound term describing organizational approach
2. **"flake-parts module"**: Used 30+ times to describe individual .nix files
3. **"flake.modules.*"**: Used 20+ times as namespace without explaining underlying type
4. **"module system"**: Used 48 times but rarely connected to dendritic/flake-parts

### Target patterns (after Phase 3)

1. **Conceptual docs**: "deferred module composition" with "dendritic organization" as implementation detail
2. **Practical docs**: "flake-parts module" with optional note "(deferred module evaluated by flake-parts)"
3. **Architecture docs**: Explicit three-layer model (module system → flake-parts → dendritic)
4. **Integration docs**: Explain WHY integration works via shared module system foundation

### Key terminology mappings

| Current term | Context | Target term (conceptual) | Target term (practical) |
|--------------|---------|-------------------------|------------------------|
| "dendritic flake-parts pattern" | Explaining why | "deferred module composition pattern (dendritic architecture)" | "dendritic pattern" |
| "flake-parts module" | Core concept | "deferred module (evaluated via flake-parts)" | "flake-parts module" |
| "flake.modules.*" | Namespace | "deferred module namespace (flake-parts convention)" | "flake.modules.*" |
| "auto-discovery" | import-tree | "automatic module import (adds to evalModules imports list)" | "auto-discovery via import-tree" |
| "namespace merging" | Multiple files | "module system merge semantics (deferredModule monoid)" | "namespace merging" |
| "every file is a module" | Organization | "every file exports a deferred module" | "every file is a flake-parts module" |

## Phase 3 implementation priority

### Tier 1: Must update (conceptual foundation)

These explain WHY patterns work and should ground in module system:

1. concepts/dendritic-architecture.md - Primary pattern explanation
2. development/architecture/adrs/0018-dendritic-flake-parts-architecture.md - Architectural rationale
3. concepts/architecture-overview.md - High-level layering
4. development/context/glossary.md - Terminology reference
5. development/architecture/architecture.md - Synthesis document

### Tier 2: Should update (integration explanation)

These explain how patterns integrate and benefit from module system context:

1. development/architecture/adrs/0020-dendritic-clan-integration.md - Integration patterns
2. development/architecture/adrs/0017-dendritic-overlay-patterns.md - Overlay composition
3. development/architecture/adrs/0019-clan-core-orchestration.md - Clan integration

### Tier 3: Optional update (practical guides)

Add brief module system notes in architecture overview sections:

1. guides/getting-started.md - Initial orientation
2. tutorials/bootstrap-to-activation.md - Development workflow
3. index.mdx - Landing page

### Tier 4: Keep as-is (operational/reference)

No changes needed:

- All other guides/* files (purely practical)
- All other tutorials/* files (step-by-step procedures)
- Most context/* and requirements/* files (requirements, not explanations)
- reference/* files (structure documentation)
- about/* files (credits, contributing)

## Validation approach

After Phase 3 terminology updates:

1. **Grep for mixing**: Search for sentences using both "flake-parts module" and "deferred module" to ensure clear distinction
2. **Conceptual clarity**: Verify high-priority docs explain mechanism (deferred modules) before implementation (flake-parts)
3. **Practical clarity**: Verify guides use flake-parts terminology without requiring module system knowledge
4. **Link structure**: Verify conceptual docs link to primitives.md and flake-parts-abstraction.md for deeper understanding

## References

- [Module System Primitives](/notes/development/modulesystem/primitives.md) - Detailed deferredModule and evalModules explanation
- [Flake-parts as Module System Abstraction](/notes/development/modulesystem/flake-parts-abstraction.md) - What flake-parts adds to module system
- Phase 1 and Phase 2 output from modulesystem documentation project

## Notes

- Search performed 2025-12-10 on doc-modules branch
- Total 74 markdown files in packages/docs/src/content/docs/
- No occurrences of "deferredModule" or "evalModules" found (opportunity for Phase 3)
- Heavy dendritic usage (289) vs lighter module system usage (48) shows conceptual gap
- Most practical guides appropriately use dendritic/flake-parts terminology
- Conceptual docs need module system foundation to explain WHY patterns work
