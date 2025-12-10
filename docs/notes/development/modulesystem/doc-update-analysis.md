---
title: Documentation update analysis
---

# Documentation update analysis

## Executive summary

- Files analyzed: 2 (Tier 1 conceptual foundation documents)
- Total recommended changes: 12 edits across both files
- Complexity: Mix of simple terminology swaps and structural additions
- Impact: High - these files are primary conceptual explanations of the architecture

Both files currently explain the dendritic pattern using flake-parts terminology without grounding in the underlying module system primitives.
The recommended edits add three-tier explanations that start with the module system foundation, explain how flake-parts uses it, and position dendritic as organizational convention built on top.

## File 1: concepts/dendritic-architecture.md

**Current path**: `/Users/crs58/projects/nix-workspace/infra/packages/docs/src/content/docs/concepts/dendritic-architecture.md`

**Purpose**: Primary conceptual explanation of the dendritic pattern

**Current state**: 347 lines, 13 "dendritic" occurrences, 9 "flake-parts" occurrences, 0 "module system" conceptual explanations

### Current state analysis

This file serves as the primary introduction to the dendritic pattern, but it conflates the organizational pattern (dendritic) with the underlying mechanism (deferred module composition via the module system).
Readers learn WHAT dendritic is and HOW to use it, but not WHY it works.
The explanation jumps directly to flake-parts modules and import-tree auto-discovery without establishing the module system foundation that makes composition possible.

Key gap: No explanation of deferredModule type, evalModules fixpoint computation, or module merging semantics.
These are the algebraic primitives that enable the pattern's core capabilities (namespace merging, auto-discovery, fixpoint resolution).

### Specific edits

#### Edit 1: Update title and description

**Location**: Lines 2-3 (frontmatter)

**Current**:
```yaml
title: Dendritic Flake-Parts Architecture
description: Understanding the dendritic pattern where every Nix file is a flake-parts module organized by aspect
```

**Recommended**:
```yaml
title: Dendritic architecture
description: Understanding deferred module composition where every Nix file is a module organized by aspect
```

**Rationale**: Lift from framework-specific "flake-parts" to the underlying pattern.
The architecture is about module composition; flake-parts is the framework used to implement it.
This aligns with the terminology mapping: prefer "dendritic architecture" over "dendritic flake-parts" in conceptual contexts.

---

#### Edit 2: Update opening statement

**Location**: Line 6

**Current**:
```markdown
This infrastructure uses the **dendritic flake-parts pattern**, a module organization approach where every Nix file is a flake-parts module and configuration is organized by *aspect* (feature) rather than by *host*.
```

**Recommended**:
```markdown
This infrastructure uses **deferred module composition** (the dendritic pattern), where every Nix file is a deferred module evaluated via flake-parts, and configuration is organized by *aspect* (feature) rather than by *host*.
The pattern leverages the Nix module system's fixpoint semantics to enable compositional configuration across platforms.
```

**Rationale**: Ground immediately in module system primitives (deferred modules, fixpoint semantics) before introducing implementation details (flake-parts, dendritic organization).
Positions dendritic as organizational convention built on compositional foundations.

---

#### Edit 3: Update core principle section

**Location**: Lines 22-25

**Current**:
```markdown
## Core principle

Every Nix file in the repository is a flake-parts module.
Files are organized by **aspect** (feature) rather than by **host**, enabling cross-cutting configuration that spans NixOS, nix-darwin, and home-manager from a single location.
```

**Recommended**:
```markdown
## Core principle

Every Nix file in the repository is a deferred module exported via the flake-parts framework.
This means modules delay evaluation until the final configuration is computed, enabling them to reference merged results without circular dependencies.

Files are organized by **aspect** (feature) rather than by **host**, enabling cross-cutting configuration that spans NixOS, nix-darwin, and home-manager from a single location.
The module system's fixpoint computation resolves these cross-cutting references into a coherent configuration.
```

**Rationale**: Explain the computational mechanism (deferred evaluation, fixpoint) that enables cross-cutting concerns.
Currently the document says "this enables" without explaining WHY it enables.
The fixpoint computation is the key - it's what makes modules organized by aspect compose correctly.

---

#### Edit 4: Add "Understanding the mechanism" section

**Location**: After line 25 (after core principle section, before "Traditional vs dendritic organization")

**Add new section**:
```markdown
### Understanding the mechanism

The dendritic pattern works because of three compositional layers:

**Layer 0: Module system foundation** (nixpkgs `lib.evalModules`)

Deferred modules are functions from configuration to module content, suspended until the fixpoint is computed.
When you write `{ config, ... }: { ... }`, the `config` argument refers to the final merged configuration after all modules have been evaluated together.
The module system computes this fixpoint via lazy evaluation, resolving cross-module dependencies without infinite recursion as long as there are no strict cycles.

**Layer 1: Flake-parts framework**

Flake-parts wraps `evalModules` for flake outputs, providing:
- The `flake.modules.*` namespace convention for organizing deferred modules by class (darwin, nixos, homeManager)
- The `perSystem` abstraction for per-architecture evaluation
- Integration with flake schema (packages, apps, devShells, etc.)

**Layer 2: Dendritic organization**

The dendritic pattern adds organizational conventions to flake-parts:
- Auto-discovery via import-tree (automatically populate evalModules imports list from directory tree)
- Directory-based namespace merging (multiple files → single aggregate via deferredModule composition)
- Aspect-oriented structure (organize by feature, not by host)

The key insight: dendritic is an organizational pattern for deferred modules, not a fundamentally different abstraction.
The composition works because the module system provides deferredModule as a compositional primitive that forms a monoid under concatenation.

For detailed explanation of module system primitives, see [Module System Primitives](/notes/development/modulesystem/primitives.md).
For how flake-parts uses these primitives, see [Flake-parts as Module System Abstraction](/notes/development/modulesystem/flake-parts-abstraction.md).
```

**Rationale**: Provide the missing "WHY" explanation.
This three-layer model appears consistently in the terminology glossary and primitives document.
Readers need to understand that dendritic builds on a solid algebraic foundation (deferredModule monoid, fixpoint computation) rather than being framework magic.

The explanation uses three-tier structure: intuitive (what happens), computational (how it's implemented), and references to formal details for deeper understanding.

---

#### Edit 5: Update module structure introduction

**Location**: Line 58 (section header)

**Current**:
```markdown
## Module structure
```

**Recommended**:
```markdown
## Module structure and composition

The module system's deferredModule type enables namespace merging: multiple files can export to the same namespace, and the module system automatically composes them via its merge semantics.
```

**Rationale**: Explain that namespace merging is a module system feature, not a dendritic invention.
The deferredModule type's merge function collects modules into imports lists, which evalModules then processes.

---

#### Edit 6: Update namespace merging explanation

**Location**: Lines 88-94 (the "key insight" paragraph)

**Current**:
```markdown
The key insight:
- Both files live in `modules/home/tools/`
- Both export to the same namespace: `flake.modules.homeManager.tools`
- import-tree auto-merges them into a single `tools` aggregate
- No manual aggregate definition needed - directory structure creates the namespace
- Each file contributes different programs to the same aggregate module
```

**Recommended**:
```markdown
The key insight:
- Both files live in `modules/home/tools/`
- Both export to the same namespace: `flake.modules.homeManager.tools`
- The module system's deferredModule type merges them into a single aggregate (deferredModule forms a monoid under concatenation)
- import-tree auto-discovers files and adds them to evalModules imports list
- No manual aggregate definition needed - directory structure + module system merging creates the namespace
- Each file contributes different programs to the same aggregate module
```

**Rationale**: Credit the mechanism correctly.
It's not import-tree that "merges" modules - import-tree discovers files.
The module system's deferredModule merge function performs the composition.
This distinction matters because it explains why the pattern is compositional: it leverages proven algebraic structure (monoid) rather than ad-hoc directory scanning.

---

#### Edit 7: Update auto-discovery section title

**Location**: Line 153 (section header)

**Current**:
```markdown
## Auto-discovery via import-tree
```

**Recommended**:
```markdown
## Auto-discovery via import-tree

The [import-tree](https://github.com/vic/import-tree) mechanism automatically discovers modules and adds them to the module system's imports list.
This leverages the module system's recursive import expansion: evalModules processes the `imports` option to discover all modules transitively.
```

**Rationale**: Clarify that import-tree is a discovery mechanism that feeds the module system, not a separate composition mechanism.
The module system's `imports` option and recursive collection is what makes auto-discovery work - import-tree just populates that list automatically.

---

#### Edit 8: Add module system context to "How it works"

**Location**: Lines 157-175 (the "How it works" subsection under auto-discovery)

**Current** (after line 174, before "Benefits over manual registration"):

**Add**:
```markdown

**Module system integration**:

What import-tree does:
1. Recursively scans `./modules` for all `.nix` files
2. Adds them to a top-level `imports` list passed to evalModules

What the module system does:
1. Processes the imports list via `collectModules` (recursive expansion, disabledModules filtering)
2. Merges modules via `mergeModules` (option declarations + definitions)
3. Computes fixpoint where `config` refers to final merged result
4. Returns configuration with all modules composed

The composition is lazy: modules are only evaluated when their values are demanded, enabling circular-looking references (module A references config set by module B, which references config set by module A) to resolve via fixpoint as long as there are no strict cycles.
```

**Rationale**: Explain the handoff between import-tree (discovery) and the module system (composition).
Currently readers might think import-tree does the composition, when actually it just populates the imports list that evalModules then processes.

---

#### Edit 9: Update comparison with nixos-unified

**Location**: Lines 213-224 (comparison section)

**Current** (lines 220-224):
```markdown
Dendritic uses aspect-based organization with explicit module exports:
- Any file can export any module type
- Feature-centric organization
- Directory names are semantic, not required
```

**Recommended**:
```markdown
Dendritic uses deferred module composition with aspect-based organization:
- Any file can export deferred modules to any namespace (flake-parts convention)
- Feature-centric organization enabled by module system's compositional semantics
- Directory names are semantic, not required (import-tree discovers based on file existence)
- Composition works via deferredModule monoid structure, not directory autowiring
```

**Rationale**: Highlight that the compositional difference is fundamental (deferred modules with algebraic structure) not just organizational convention.
The "aspect-based" organization works BECAUSE deferred modules compose via monoid structure, making it safe to split features across files.

---

#### Edit 10: Update "vs pure flake-parts" comparison

**Location**: Lines 226-228

**Current**:
```markdown
### vs pure flake-parts

Pure flake-parts requires manual imports in `flake.nix`.
Dendritic adds import-tree for automatic discovery, making it practical for large configurations.
```

**Recommended**:
```markdown
### vs pure flake-parts

Pure flake-parts requires manual imports in `flake.nix` to populate the module system's imports list.
Dendritic adds import-tree for automatic discovery of modules, making it practical for large configurations.

Both use the same underlying module system primitives (deferredModule type, evalModules fixpoint).
Dendritic adds organizational conventions (directory-based namespace merging, auto-discovery) on top of flake-parts' module system integration.
```

**Rationale**: Clarify that the difference is convenience/organization, not fundamentals.
Both ultimately call evalModules with a list of deferred modules.
Dendritic automates list population and establishes namespace conventions.

---

#### Edit 11: Update clan integration note

**Location**: Lines 236-240

**Current**:
```markdown
## Integration with clan

Clan coordinates multi-machine deployments while dendritic organizes the modules being deployed.
They're orthogonal patterns that work together.

See [Clan Integration](/concepts/clan-integration/) for how clan orchestrates deployments of dendritic-organized configurations.
```

**Recommended**:
```markdown
## Integration with clan

Clan coordinates multi-machine deployments while dendritic organizes the modules being deployed.
The integration works because both use the same module system foundation: clan calls nixosSystem or darwinSystem (which call evalModules), importing deferred modules from `flake.modules.*` namespaces.

Dendritic exports deferred modules → clan imports them → evalModules resolves fixpoint with clan's arguments (system, config, pkgs, etc.).

See [Clan Integration](/concepts/clan-integration/) for how clan orchestrates deployments of dendritic-organized configurations.
```

**Rationale**: Explain WHY the integration is seamless.
It's not just "orthogonal patterns" - they share the same algebraic foundation.
Clan consumes deferredModule type exports, triggering evaluation with system-specific arguments.

---

#### Edit 12: Add references to new module system documentation

**Location**: Lines 332-347 (External resources and See also sections)

**Add after line 337 (after external resources, before "See also")**:

```markdown

## Module system foundations

Understanding the algebraic primitives that enable the dendritic pattern:

- [Module System Primitives](/notes/development/modulesystem/primitives.md) - Detailed deferredModule and evalModules explanation with three-tier (intuitive/computational/formal) treatment
- [Flake-parts as Module System Abstraction](/notes/development/modulesystem/flake-parts-abstraction.md) - What flake-parts adds to the module system (perSystem, namespace conventions, class-based organization)
- [Terminology Glossary](/notes/development/modulesystem/terminology-glossary.md) - Quick reference for module system vs flake-parts vs dendritic terminology
```

**Rationale**: Provide clear navigation to deeper understanding.
Readers who want to know WHY the pattern works (beyond HOW to use it) need these references.
The three-tier structure in primitives.md provides escalating depth.

---

## File 2: development/architecture/adrs/0018-dendritic-flake-parts-architecture.md

**Current path**: `/Users/crs58/projects/nix-workspace/infra/packages/docs/src/content/docs/development/architecture/adrs/0018-dendritic-flake-parts-architecture.md`

**Purpose**: Architectural decision record explaining why dendritic pattern was adopted

**Current state**: 323 lines, 28 "dendritic" occurrences, 12 "flake-parts" occurrences, 3 "module system" occurrences (all in comparison table, none conceptual)

### Current state analysis

This ADR documents the architectural decision to adopt dendritic pattern, comparing it to alternatives (nixos-unified, raw flake-parts, snowfall lib, nixos modules only).
It explains WHAT was decided and WHY alternatives were rejected, but lacks explanation of HOW the chosen pattern works at a foundational level.

The comparison table (line 166) mentions "module system" but only as a label, not explaining what module system primitives enable.
The "Pattern overview" section describes namespace exports and auto-discovery but doesn't ground these in deferredModule type and evalModules fixpoint.

ADRs should explain architectural decisions with enough depth that future maintainers understand the reasoning.
Adding module system foundation context strengthens the "why this pattern works" argument.

### Specific edits

#### Edit 13: Add module system foundation section

**Location**: After line 47 (after decision statement, before "Pattern overview")

**Add new section**:
```markdown
### Module system foundation

The dendritic pattern builds on nixpkgs module system primitives, which explains why composition works reliably:

**deferredModule type**: A module that delays evaluation until the final configuration is computed.
The type signature is `Config → Module`, meaning modules are functions from configurations to option declarations and definitions.
This enables modules to reference the final merged configuration without creating circular dependencies.

**evalModules fixpoint**: The function that evaluates a list of modules by computing a least fixpoint.
It collects all option declarations, collects all configuration definitions, computes a fixpoint where the `config` argument equals the merged result, merges definitions according to type-specific merge functions, and validates that definitions match declared options.

**Flake-parts integration**: Flake-parts wraps evalModules for flake outputs, defining:
- Class-based module organization (darwin, nixos, homeManager via module classes)
- `flake.modules.*` namespace (type: `lazyAttrsOf (lazyAttrsOf deferredModule)`)
- `perSystem` abstraction (per-architecture evaluation with nested evalModules call)

**Why this matters**: The pattern's compositional properties (namespace merging, auto-discovery, cross-cutting concerns) emerge from module system semantics, not from dendritic-specific logic.
Deferred modules form a monoid under concatenation, which is why multiple files can export to the same namespace and merge correctly.
Fixpoint computation is why modules can reference each other's configuration decisions without evaluation order mattering.

For detailed treatment, see [Module System Primitives](/notes/development/modulesystem/primitives.md).
```

**Rationale**: Establish the foundational argument for why the pattern was adopted.
The ADR argues dendritic is better than alternatives, but doesn't explain the mathematical/computational reasons WHY it composes well.
The module system foundation provides that explanation.

This addition strengthens the "positive consequences" section by pre-emptively explaining why cross-platform consistency and explicit dependencies work.

---

#### Edit 14: Update pattern overview

**Location**: Lines 49-52

**Current**:
```markdown
### Pattern overview

Every `.nix` file in the `modules/` directory is a flake-parts module.
Files export to namespaces under `flake.modules.*` and are auto-discovered by import-tree.
```

**Recommended**:
```markdown
### Pattern overview

Every `.nix` file in the `modules/` directory is a deferred module (type: `Config → Module`).
Files export to namespaces under `flake.modules.*` (type: `lazyAttrsOf deferredModule`) and are auto-discovered by import-tree, which populates the module system's imports list.
Flake-parts evaluates these modules with class "flake", providing access to the final flake output configuration.
```

**Rationale**: Add type information and explain the evaluation context.
Currently says "is a flake-parts module" which is vague.
More precise: "is a deferred module evaluated by flake-parts" explains the relationship between the primitive (deferredModule) and the framework (flake-parts).

---

#### Edit 15: Update namespace exports explanation

**Location**: Lines 88-106

**Current** (lines 90-92):
```markdown
Modules export to `flake.modules.*` namespaces for consumption:
```

**Recommended** (replace lines 90-92):
```markdown
Modules export to `flake.modules.*` namespaces for consumption.
These namespaces have type `lazyAttrsOf deferredModule`, meaning they are attribute sets of deferred modules that delay evaluation until imported by a consumer.
```

**Add after line 106** (after the example showing multiple files merging):
```markdown

**Module system semantics**: The deferredModule type's merge function collects modules into imports lists rather than evaluating them immediately.
When multiple files export to the same namespace (`flake.modules.homeManager.ai`), the module system merges them via monoid composition (concatenation of imports lists).
Later, when a machine configuration imports `flake.modules.homeManager.ai`, it triggers evalModules with all collected modules, resolving the fixpoint with that machine's configuration context.

This deferred evaluation is what enables the pattern's composability: modules don't need to know who will import them or in what order they'll be evaluated.
```

**Rationale**: Explain the handoff between export (deferred) and import (evaluation).
Many developers assume exports evaluate immediately, but deferredModule type specifically prevents that.
Understanding deferral explains why the pattern is compositional.

---

#### Edit 16: Update comparison table

**Location**: Line 166 (comparison table)

**Current**:
```markdown
| Aspect | nixos-unified | Dendritic flake-parts |
|--------|---------------|----------------------|
| Module discovery | Path-based autowiring | import-tree auto-discovery |
| Configuration passing | specialArgs (implicit) | Namespace exports (explicit) |
| Organization | By host | By aspect/feature |
| Module registration | Required specific paths | Any path under modules/ |
| flake.nix size | 50-100+ lines | 23 lines |
| Adding features | Edit multiple host files | Create single aspect file |
```

**Recommended** (add row at end):
```markdown
| Aspect | nixos-unified | Dendritic flake-parts |
|--------|---------------|----------------------|
| Module discovery | Path-based autowiring | import-tree auto-discovery |
| Configuration passing | specialArgs (implicit) | Namespace exports (explicit) |
| Organization | By host | By aspect/feature |
| Module registration | Required specific paths | Any path under modules/ |
| Module type | Immediate attribute sets | Deferred modules (Config → Module) |
| Composition mechanism | Directory autowiring rules | deferredModule monoid + fixpoint |
| flake.nix size | 50-100+ lines | 23 lines |
| Adding features | Edit multiple host files | Create single aspect file |
```

**Rationale**: Add rows highlighting the fundamental computational difference.
The comparison currently focuses on organizational aspects (host vs aspect, registration).
Missing: the underlying compositional difference (deferred modules with algebraic structure vs immediate evaluation with autowiring).

---

#### Edit 17: Update "Stay with nixos-unified" alternative

**Location**: Lines 178-183 (end of this alternative's paragraph)

**Add after line 183** (after "implicit mapping from filesystem paths to flake outputs"):
```markdown
More fundamentally, nixos-unified doesn't use deferred modules - it evaluates configuration immediately based on file paths.
This prevents the kind of cross-module references that dendritic enables, where modules can reference the final merged configuration via fixpoint computation.
The lack of deferredModule type meant cross-cutting concerns (features that span multiple hosts) had to be duplicated rather than composed from shared modules.
```

**Rationale**: Strengthen the architectural argument against nixos-unified.
The ADR currently focuses on organizational problems (duplication, specialArgs complexity).
Missing: the fundamental compositional limitation (no deferred evaluation).
This explains WHY duplication was necessary - the module system features that enable composition weren't being used.

---

#### Edit 18: Update "Raw flake-parts without dendritic pattern" alternative

**Location**: Lines 185-192 (paragraph explaining this alternative)

**Current** (ending at line 192):
```markdown
The dendritic pattern brings a proven structure that works across multiple production implementations, reducing cognitive load when switching contexts.
```

**Add after line 192**:
```markdown

More importantly, both use identical module system primitives (deferredModule type, evalModules fixpoint, option merging).
The difference is purely organizational: raw flake-parts requires manual imports list maintenance, while dendritic automates discovery via import-tree and establishes namespace conventions.
The underlying composition mechanism (module system) is identical, so both have the same compositional properties - dendritic just reduces registration burden.
```

**Rationale**: Clarify that raw flake-parts isn't architecturally different - it's organizationally less convenient.
Both evaluate the same deferredModule type via the same evalModules function.
This strengthens the decision argument: dendritic adds value (auto-discovery, conventions) without changing fundamentals.

---

#### Edit 19: Update "NixOS modules only" alternative

**Location**: Lines 202-207 (paragraph explaining this alternative)

**Current** (ending at line 207):
```markdown
Additionally, the standard NixOS module approach lacks the namespace export pattern that dendritic uses to create composable aggregates - machine configurations would need to import every individual module rather than importing high-level aggregates like `flakeModulesHome.ai` that bundle related functionality.
```

**Recommended** (replace ending from "Additionally, the standard..." onward):
```markdown
Additionally, the standard NixOS module approach lacks the namespace export conventions that flake-parts provides.
While NixOS modules use the same underlying primitives (deferredModule, evalModules), they don't have flake-parts' `flake.modules.*` namespace or perSystem abstraction.
Without these namespace conventions, creating composable aggregates requires manually maintaining imports lists, and cross-platform modules require duplication for darwin vs nixos contexts.
Flake-parts provides the namespace organization and evaluation strategy that makes dendritic's aspect-based aggregation practical.
```

**Rationale**: Distinguish between module system primitives (which NixOS modules have) and flake-parts conventions (which provide organization).
The current phrasing implies NixOS modules can't do aggregates.
More accurate: NixOS modules use the same deferredModule composition, but lack organizational conventions that make aggregates convenient.

---

#### Edit 20: Strengthen "Positive consequences" introduction

**Location**: Lines 210-216 (beginning of positive consequences section)

**Current**:
```markdown
### Positive

The dendritic pattern's feature-based organization eliminates the duplication problem that plagued the nixos-unified architecture.
When we define AI tooling once in `modules/home/ai/`, every machine configuration can import that aggregate and receive the entire suite of tools consistently.
```

**Recommended** (insert before current text):
```markdown
### Positive

**Compositional semantics**: The pattern's benefits derive from module system algebraic structure, not organizational convention alone.
Deferred modules form a monoid under concatenation, which guarantees composition is associative and has identity.
This means module evaluation order doesn't matter (associativity), and empty modules don't affect results (identity).
The fixpoint computation ensures cross-module references resolve consistently regardless of import order.
These algebraic properties make the pattern's composition reliable at scale.

**Feature-based organization**: The dendritic pattern's aspect-based organization eliminates the duplication problem that plagued the nixos-unified architecture.
When we define AI tooling once in `modules/home/ai/`, every machine configuration can import that aggregate and receive the entire suite of tools consistently.
```

**Rationale**: Lead with the fundamental architectural strength - compositional semantics from module system.
Currently positive consequences focus on organizational benefits (less duplication, explicit imports).
Missing: WHY those benefits are reliable (algebraic structure ensures composition works predictably).

Starting with algebraic properties establishes that the pattern's advantages aren't just convenience - they're mathematically guaranteed.

---

#### Edit 21: Add module system references

**Location**: Lines 305-323 (references section)

**Add after line 313** (after internal references, before external references):
```markdown

#### Module system foundations

- [Module System Primitives](/notes/development/modulesystem/primitives.md) - deferredModule and evalModules with three-tier explanations
- [Flake-parts as Module System Abstraction](/notes/development/modulesystem/flake-parts-abstraction.md) - What flake-parts adds to module system
- [Terminology Glossary](/notes/development/modulesystem/terminology-glossary.md) - Module system vs flake-parts vs dendritic terminology
```

**Rationale**: Provide navigation to deeper understanding.
The ADR explains the architectural decision but doesn't provide references for readers who want to understand the module system foundation.
These links enable "learn more" paths for interested readers.

---

## Implementation priority

Ordered by impact and logical dependency:

### Phase 1: Foundation sections (adds WHY explanations)

1. **Edit 4** - Add "Understanding the mechanism" section to dendritic-architecture.md
   - Impact: High - provides missing foundational explanation
   - Dependency: None - can be added independently
   - Establishes three-layer model used throughout other edits

2. **Edit 13** - Add "Module system foundation" section to ADR-0018
   - Impact: High - strengthens architectural decision rationale
   - Dependency: None - can be added independently
   - Provides algebraic argument for why pattern works

### Phase 2: Terminology precision (updates WHAT language)

3. **Edit 1** - Update title and description (dendritic-architecture.md frontmatter)
4. **Edit 2** - Update opening statement (dendritic-architecture.md line 6)
5. **Edit 3** - Update core principle (dendritic-architecture.md lines 22-25)
6. **Edit 14** - Update pattern overview (ADR-0018 lines 49-52)

These are simple terminology swaps grounded in the foundation sections added in Phase 1.

### Phase 3: Mechanism explanations (clarifies HOW it works)

7. **Edit 5** - Update module structure introduction (dendritic-architecture.md line 58)
8. **Edit 6** - Update namespace merging explanation (dendritic-architecture.md lines 88-94)
9. **Edit 7** - Update auto-discovery section (dendritic-architecture.md line 153)
10. **Edit 8** - Add module system context to auto-discovery (dendritic-architecture.md after line 174)
11. **Edit 15** - Update namespace exports explanation (ADR-0018 lines 88-106)

These edits explain the handoff between framework features (import-tree, namespaces) and module system primitives (evalModules, deferredModule merging).

### Phase 4: Comparisons and integration (strengthens architectural arguments)

12. **Edit 9** - Update nixos-unified comparison (dendritic-architecture.md lines 220-224)
13. **Edit 10** - Update pure flake-parts comparison (dendritic-architecture.md lines 226-228)
14. **Edit 11** - Update clan integration note (dendritic-architecture.md lines 236-240)
15. **Edit 16** - Update comparison table (ADR-0018 line 166)
16. **Edit 17** - Update "Stay with nixos-unified" alternative (ADR-0018 after line 183)
17. **Edit 18** - Update "Raw flake-parts" alternative (ADR-0018 after line 192)
18. **Edit 19** - Update "NixOS modules only" alternative (ADR-0018 lines 202-207)
19. **Edit 20** - Strengthen positive consequences (ADR-0018 lines 210-216)

### Phase 5: Navigation (adds references)

20. **Edit 12** - Add module system foundations references (dendritic-architecture.md after line 337)
21. **Edit 21** - Add module system references to ADR (ADR-0018 after line 313)

Final polish providing navigation to deeper understanding.

## Validation approach

After implementing edits, verify correctness and clarity:

### 1. Build documentation site

```bash
cd /Users/crs58/projects/nix-workspace/infra/packages/docs
npm run build
```

Ensure no broken links, rendering issues, or build failures.
The new links to `/notes/development/modulesystem/primitives.md` and related documents must resolve correctly.

### 2. Verify mathematical/computational claims

Cross-reference terminology and claims against source documents:

- All references to "deferredModule type" should match usage in `primitives.md`
- All references to "evalModules fixpoint" should align with explanation in `primitives.md`
- All references to "monoid composition" should match terminology in `terminology-glossary.md`
- All type signatures (e.g., `Config → Module`, `lazyAttrsOf deferredModule`) should be accurate

### 3. Check three-tier consistency

The edits introduce module system foundations to conceptual docs.
Verify the explanations stay at appropriate depth:

- Conceptual docs (dendritic-architecture.md): intuitive + computational, with links to formal
- ADRs (0018): computational focus with algebraic grounding, links to detailed formal treatment
- Neither should duplicate content from primitives.md - they should reference it

### 4. Test comprehension paths

Simulate reader journeys to verify navigation works:

**Path 1: New user learning dendritic**
- Start at dendritic-architecture.md (updated with Edit 1-12)
- Should understand WHAT (organizational pattern), HOW (flake-parts + import-tree), WHY (module system primitives)
- Can follow links to primitives.md for deeper understanding
- Doesn't need to understand category theory to use the pattern

**Path 2: Maintainer evaluating architectural decisions**
- Start at ADR-0018 (updated with Edit 13-21)
- Should understand decision rationale with module system foundation
- Can see why alternatives were rejected based on compositional properties
- Can reference terminology-glossary.md for quick lookups

**Path 3: Developer debugging composition issues**
- Knows practical flake-parts usage, needs to understand "why isn't this composing?"
- Can read "Understanding the mechanism" section (Edit 4) for conceptual model
- Can reference primitives.md section on deferredModule merging
- Terminology-glossary.md provides quick mapping between practical terms and algebraic terms

### 5. Review for practical clarity

The edits add significant module system content.
Ensure practical guidance remains clear:

- Can a user still follow "Adding a new tool to all users" example (dendritic-architecture.md lines 243-263) without understanding fixpoint computation?
- Do the edits make the pattern seem more complex to use than it actually is?
- Is there clear separation between "what you need to know to use this" vs "what explains why it works"?

If conceptual explanations obscure practical usage, consider moving some material to dedicated "Advanced: Module System Details" subsections.

### 6. Grep for terminology consistency

After edits, verify terminology usage is consistent:

```bash
cd /Users/crs58/projects/nix-workspace/infra/packages/docs/src/content/docs

# Should find "deferred module" in conceptual contexts
rg "deferred module" concepts/dendritic-architecture.md

# Should still have "flake-parts module" in practical examples
rg "flake-parts module" concepts/dendritic-architecture.md

# Should have "module system" with conceptual explanations
rg -A 2 "module system" concepts/dendritic-architecture.md

# Verify ADR uses algebraic terminology
rg "deferredModule|evalModules|fixpoint" development/architecture/adrs/0018-dendritic-flake-parts-architecture.md
```

### 7. Check for unintended consequences

These edits change foundational conceptual documents.
Verify no unintended effects:

- Do other docs reference dendritic-architecture.md in ways that assume old structure?
- Are there guides that say "see dendritic-architecture for overview" expecting quick practical summary?
- Does ADR-0018 still serve its purpose as decision record, or has it become too tutorial-like?

Search for cross-references:

```bash
rg "dendritic-architecture" packages/docs/src/content/docs/ -l
rg "ADR-0018|0018-dendritic" packages/docs/src/content/docs/ -l
```

Review each referencing file to ensure edits don't break expectations.

## Notes

### Scope limitation

This analysis covers only Tier 1 (conceptual foundation) files.
Remaining work:

- **Tier 2** (integration explanations): ADR-0020 (clan integration), ADR-0017 (overlay patterns), ADR-0019 (clan orchestration)
- **Tier 3** (practical guides): getting-started.md, bootstrap-to-activation.md
- **Tier 4** (keep as-is): operational guides, reference docs, contributing docs

The terminology inventory document provides analysis and recommendations for these files.

### Edit numbering

Edits numbered 1-21 for tracking and implementation.
The implementation priority orders them differently (by impact and dependency) than their sequential numbering in the document.

### Terminology mapping reference

For implementers, quick reference from terminology-glossary.md:

| Current term | Algebraic term | Use algebraic when |
|--------------|----------------|-------------------|
| "flake-parts module" | "deferred module" | Explaining why patterns work |
| "dendritic pattern" | "deferred module composition" | Explaining underlying mechanism |
| "namespace merging" | "deferredModule monoid composition" | Explaining merge semantics |
| "auto-discovery" | "automatic module imports" | Explaining evalModules imports list |

These edits apply this mapping to conceptual documentation.

### Link validation

New internal links added by edits:

- `/notes/development/modulesystem/primitives.md` (Edit 4, 12, 13, 21)
- `/notes/development/modulesystem/flake-parts-abstraction.md` (Edit 4, 12, 21)
- `/notes/development/modulesystem/terminology-glossary.md` (Edit 12, 21)

All three files exist in the repository at time of analysis (doc-modules branch).
Verify they remain at these paths and are included in documentation site build.
