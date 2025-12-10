---
title: Terminology mapping and glossary
---

# Terminology mapping and glossary

This document defines precise terminology for the module system, flake-parts framework, and dendritic organizational pattern.
Each term is defined at three tiers (intuitive, computational, formal) to serve both practical users and those seeking deeper understanding.

## Quick reference mapping

Use this table to choose appropriate terminology based on context:

| Current term | Algebraic term | Use current when | Use algebraic when |
|--------------|----------------|------------------|-------------------|
| "flake-parts module" | "deferred module" | Writing practical guides | Explaining why patterns work |
| "dendritic pattern" | "deferred module composition" | Describing organizational convention | Explaining underlying mechanism |
| "flake.modules namespace" | "deferredModule type namespace" | Referencing output structure | Explaining type system behavior |
| "auto-discovery" | "automatic module imports" | Describing import-tree behavior | Explaining evalModules imports list |
| "namespace merging" | "deferredModule monoid composition" | Describing multi-file pattern | Explaining merge semantics |
| "perSystem" | "per-system deferred module evaluation" | Using flake-parts feature | Explaining evaluation strategy |
| "module fixpoint" | "least fixpoint in configuration lattice" | Casual reference | Formal explanation |
| "option merging" | "join-semilattice operation" | Practical documentation | Conceptual foundations |

## Context-specific usage guide

### In conceptual documentation

**Prefer**: "deferred module", "fixpoint", "module composition", "deferredModule type"
**Avoid**: Bare "flake-parts module" without grounding in module system primitives
**Pattern**: Explain mechanism (module system) before implementation (flake-parts)

Example:
> The dendritic pattern uses deferred modules to delay evaluation until the final configuration is computed.
> Flake-parts provides an ergonomic wrapper for evalModules, integrating these deferred modules with the flake output schema.

### In practical guides

**Acceptable**: "flake-parts module", "dendritic pattern", "perSystem"
**Enhance with**: Brief note linking to module system foundations when first introduced
**Pattern**: Use framework terminology, with one-time reference to foundations

Example:
> Create a new flake-parts module in `modules/services/`.
> (These are deferred modules evaluated by flake-parts' module system integration—see [Module System Primitives](/notes/development/modulesystem/primitives.md) for details.)

### In code comments

**Prefer**: Direct reference to what the code does
**Optional**: Brief algebraic note for non-obvious patterns
**Pattern**: Concrete behavior over abstract theory

Example:
```nix
# Export deferred module via flake.modules namespace
# (deferredModule type delays evaluation until consumer calls evalModules)
flake.modules.nixos.my-service = { config, lib, ... }: {
  options.services.my-service.enable = lib.mkEnableOption "my service";
};
```

### In architecture documentation

**Required**: Explicit three-layer model (module system → flake-parts → dendritic)
**Pattern**: Foundation before framework before pattern
**Links**: Reference both nix.dev and local primitives.md

Example:
> Our architecture builds on three layers:
> 1. **Module system foundation**: nixpkgs lib.evalModules with deferred module type
> 2. **Flake-parts framework**: Wraps evalModules for flake outputs, provides perSystem and namespace conventions
> 3. **Dendritic organization**: Auto-discovery via import-tree, aspect-oriented structure

---

## Glossary

### deferred module

**Intuitive**: A module that waits to be evaluated until the final configuration is known.
When you write a module as a function `{ config, ... }: { ... }`, the `config` argument refers to the final merged configuration after all modules have been combined.
This allows modules to make decisions based on what other modules decided, without creating circular dependencies.

**Computational**: A function from configuration to module content.
The module system collects all deferred modules into an imports list, then computes a fixpoint where the `config` argument equals the result of evaluating all modules with that same `config` value.
Nix's lazy evaluation ensures this resolves correctly as long as there are no strict cycles (where evaluating A demands B's value before B is computed, and vice versa).

The type implementation in nixpkgs `lib/types.nix`:
```nix
deferredModuleWith = { staticModules ? [] }: mkOptionType {
  name = "deferredModule";
  check = x: isAttrs x || isFunction x || path.check x;
  merge = loc: defs: {
    imports = staticModules ++ map (def: setDefaultModuleLocation ...) defs;
  };
  # ... functor for type merging
};
```

The `merge` function doesn't evaluate modules—it collects them into an imports list for later fixpoint computation.

**Formal**: A morphism in the Kleisli category $\mathbf{Kl}(T)$ where $T$ is the reader monad over configurations:

$$
m : \mathbf{1} \to T(\text{Module})
$$

More precisely, a deferred module is a function:

$$
\text{deferredModule} : \text{Config} \to \{ \text{options} : \text{Options}, \text{config} : \text{Definitions} \}
$$

suspended until the fixpoint operator provides the actual configuration value:

$$
\text{config}_{\text{final}} = \mu c.\, \bigsqcup_{i} m_i(c)
$$

where $\mu$ denotes the least fixpoint and $\sqcup$ is the join operation in the configuration lattice.

**See also**:
- [nix.dev module system tutorial](https://nix.dev/tutorials/module-system/deep-dive.html) (section 2.9 on option dependencies)
- [nixpkgs lib/types.nix source](https://github.com/NixOS/nixpkgs/blob/master/lib/types.nix#L1138)
- [Module System Primitives](/notes/development/modulesystem/primitives.md#deferredmodule)

---

### evalModules

**Intuitive**: The function that takes a list of modules and produces a final configuration.
It recursively discovers all imported modules, collects option declarations, collects configuration definitions, computes a fixpoint where config values can reference the final merged result, merges all definitions according to option types, and checks that all definitions match declared options.

Think of it as the "main" function of the module system—the evaluator that turns a collection of module fragments into a coherent configuration.

**Computational**: Evaluates modules in phases:

1. **Collection** (`collectModules`): Recursively expands all imports, filters disabledModules, produces flat list of normalized modules
2. **Merging** (`mergeModules`): Traverses option tree, matches definitions to declarations, recurses into submodules
3. **Fixpoint resolution**: Computes least fixpoint via lazy evaluation, where `config` is a self-referential binding

The key signature:
```nix
evalModules {
  modules = [ /* list of modules */ ];
  specialArgs = { /* extra arguments for modules */ };
  class = "string";  # e.g., "nixos", "darwin", "flake"
  prefix = [ /* option path prefix */ ];
}
```

Returns:
```nix
{
  config = /* final configuration */;
  options = /* option declarations */;
  type = /* module system type */;
  _module = /* internal metadata */;
  extendModules = /* function to add more modules */;
}
```

**Formal**: Computes the least fixpoint of a module configuration functor in a domain-theoretic framework.

Let $\mathcal{C}$ be a complete lattice of partial configurations ordered by information content (Smyth order).
Each module $m_i$ defines a monotone function $F_{m_i} : \mathcal{C} \to \mathcal{C}$.

The combined system defines:

$$
F : \mathcal{C} \to \mathcal{C}, \quad F(c) = \bigsqcup_{i=1}^{n} F_{m_i}(c)
$$

where $\sqcup$ is the join operation (type-specific merge with priority handling).

By the Knaster-Tarski theorem, the least fixpoint exists:

$$
\text{evalModules}(m_1, \ldots, m_n) = \mu F = \text{lfp}(F) = \bigsqcup_{k \geq 0} F^k(\bot)
$$

where $\bot$ is the minimal configuration (no definitions).

**See also**:
- [nix.dev basic module tutorial](https://nix.dev/tutorials/module-system/a-basic-module/) (introduction to evalModules)
- [nixpkgs lib/modules.nix source](https://github.com/NixOS/nixpkgs/blob/master/lib/modules.nix#L84)
- [Module System Primitives](/notes/development/modulesystem/primitives.md#evalmodules)

---

### fixpoint computation

**Intuitive**: The process that resolves circular-looking references in the module system.
When modules reference `config` values that are being computed by those same modules, the fixpoint computation finds a consistent solution where all references resolve correctly.

Think of it as solving a system of equations where each module contributes constraints, and the fixpoint is the unique solution that satisfies all constraints simultaneously.

**Computational**: Implemented via Nix's `let rec` bindings and lazy evaluation.

The self-referential structure:
```nix
let
  config = mapAttrs (_: opt: opt.value) options;
  options = /* evaluated from modules with 'config' available */;
in config
```

Nix resolves this by:
1. Allocating thunks (suspended computations) for both `config` and `options`
2. When parts of the configuration are demanded, evaluate those specific thunks
3. If evaluating a thunk demands another thunk, recursively evaluate it
4. Continue until consistent fixpoint is reached (or detect infinite recursion)

The fixpoint succeeds if there are no strict cycles (A needs B's value before B is computed, and B needs A's value before A is computed).

**Formal**: Computes a least fixpoint in a Scott domain via demand-driven iteration.

Nix values form a Scott domain $(\mathcal{D}, \sqsubseteq, \bot)$ where $\bot$ represents "not yet evaluated" and $\sqsubseteq$ is the information ordering.

For continuous function $F : \mathcal{D} \to \mathcal{D}$, the least fixpoint exists and equals:

$$
\mu F = \bigsqcup_{n \geq 0} F^n(\bot)
$$

Lazy evaluation implements demand-driven fixpoint iteration:
- Start with all values as $\bot$ (thunks)
- When a value is demanded, compute one iteration $F(\text{current})$
- If that demands another thunk, recursively evaluate it
- Update configuration with newly computed values

Well-foundedness ensures convergence: $\exists n.\, F^n(\bot) = F^{n+1}(\bot)$

**See also**:
- [nix.dev deep-dive](https://nix.dev/tutorials/module-system/deep-dive.html) (section 2.9 demonstrates config dependencies)
- [Module System Primitives](/notes/development/modulesystem/primitives.md#fixpoint-computation-and-lazy-evaluation)

---

### option merging

**Intuitive**: The rules for combining multiple definitions of the same option into a single value.
When multiple modules define the same option, the module system needs to decide how to combine them.
Lists concatenate, attribute sets recursively merge, and primitives must match (or use priorities).

The module system provides primitives to control merging:
- `mkMerge`: explicitly combine multiple values
- `mkDefault`, `mkForce`: attach priorities (lower wins)
- `mkIf`: conditionally include values
- `mkBefore`, `mkAfter`: control list element ordering

**Computational**: Merging proceeds in stages:

1. **Discharge properties**: Expand `mkMerge`, evaluate `mkIf` conditions
2. **Filter by priority**: Keep only highest-priority definitions (lowest number)
   - `mkOptionDefault`: 1500 (option's own default)
   - `mkDefault`: 1000 (module default)
   - No modifier: 100 (user value)
   - `mkForce`: 50 (force override)
3. **Sort by order**: For lists, apply `mkBefore`/`mkAfter` ordering
4. **Type-specific merge**: Use type's merge function (concat for lists, recursive merge for attrs, equality for primitives)

Implementation:
```nix
mergeDefinitions = loc: type: defs:
  let
    # Expand mkMerge, evaluate mkIf
    defsNormalized = concatMap dischargeProperties defs;
    # Filter by priority
    defsFiltered = filterOverrides' defsNormalized;
    # Sort by order
    defsSorted = sortProperties defsFiltered;
    # Type-specific merge
    merged = type.merge loc defsSorted;
  in merged;
```

**Formal**: Forms a join-semilattice with priority stratification.

For each option of type $\tau$, the merge operation defines a join:

$$
\text{merge}([d_1, d_2, \ldots, d_n]) = d_1 \sqcup d_2 \sqcup \cdots \sqcup d_n
$$

The join operation $\sqcup$ is type-dependent:

**Lists**: $xs \sqcup ys = xs \mathbin{+\!\!+} ys$ (concatenation)

**Attribute sets**: Pointwise join where $(f \sqcup g)(n) = \begin{cases} f(n) \sqcup g(n) & n \in \text{dom}(f) \cap \text{dom}(g) \\ f(n) & n \in \text{dom}(f) \setminus \text{dom}(g) \\ g(n) & n \in \text{dom}(g) \setminus \text{dom}(f) \end{cases}$

**Priority stratification**: Definitions carry priority $p \in \mathbb{N}$ (lower wins).
The stratified lattice:

$$
\mathcal{L}_{\text{withPrio}} = \mathbb{N}^{\text{op}} \times \mathcal{L}
$$

ordered lexicographically: first compare priorities, then merge equal-priority values.

**See also**:
- [nix.dev deep-dive](https://nix.dev/tutorials/module-system/deep-dive.html) (section 2.20 on mkDefault and priorities)
- [nixpkgs lib/modules.nix source](https://github.com/NixOS/nixpkgs/blob/master/lib/modules.nix#L1469) (mkMerge, mkIf, mkOverride)
- [Module System Primitives](/notes/development/modulesystem/primitives.md#option-merging-primitives)

---

### flake-parts (framework)

**Intuitive**: A framework that wraps the Nix module system for creating flakes.
It handles the boilerplate of evaluating modules for flake outputs, provides the `perSystem` abstraction to avoid repetitive system-specific definitions, and enables module discovery through the `flake.modules.*` namespace.

**Important**: Flake-parts is NOT a module system primitive.
It is a framework providing ergonomic access to deferred modules (from nixpkgs `lib.evalModules`) in the flake context.

**Computational**: Evaluates modules in two layers:

**Top-level flake evaluation** (class `"flake"`):
```nix
lib.evalModules {
  modules = [ ./all-modules.nix module ];
  specialArgs = { inherit self inputs flake-parts-lib; };
  class = "flake";
}
```

Defines options like:
- `flake`: accumulates all output attributes
- `perSystem`: holds deferred modules for per-system evaluation
- `systems`: lists architectures to enumerate
- `flake.modules.*`: publishes deferred modules by class and name

**Per-system evaluation** (class `"perSystem"`):
```nix
lib.evalModules {
  modules = config.perSystem;  # deferred modules from perSystem option
  specialArgs = { inherit system; };
  class = "perSystem";
  prefix = [ "perSystem" system ];
}
```

For each system in `systems`, evaluates perSystem modules with that system, producing system-specific configuration.
The transposition module automatically merges results into flake outputs like `packages.<system>.*`.

**Formal**: A functor from flake-parts modules to flake outputs with per-system structure.

Let $\mathcal{C}_{\text{flake}}$ be the category of flake-parts modules (deferred modules with class "flake").
Let $\mathcal{C}_{\text{outputs}}$ be the category of flake output attribute sets.

Then `mkFlake : \mathcal{C}_{\text{flake}} \to \mathcal{C}_{\text{outputs}}` defined by:

$$
\text{mkFlake}(\text{args}, m) = (\text{evalModules}(\text{args}, m)).\text{config}.\text{flake}
$$

The `perSystem` option defines a monoidal action over system set $\mathcal{S}$:

$$
\text{perSystem} : \text{Module}_{\text{perSystem}} \to (\mathcal{S} \to \text{Config}_{\text{perSystem}})
$$

Transposition is a natural transformation:

$$
\text{transpose} : (\mathcal{S} \to \text{Config}_{\text{perSystem}}) \to \text{AttrSet}
$$

satisfying coherence: $(\text{transpose}\, f).a.s = (f\, s).a$

**When to mention**: Practical instructions for using this repository
**When to prefer "deferred module"**: Explaining why patterns compose, architectural foundations

**See also**:
- [Flake-parts documentation](https://flake.parts)
- [Flake-parts as Module System Abstraction](/notes/development/modulesystem/flake-parts-abstraction.md)

---

### dendritic pattern

**Intuitive**: An organizational pattern where every Nix file is a deferred module, auto-discovered via import-tree, and organized by aspect (feature) rather than by host.
Multiple files can export to the same namespace (e.g., `flake.modules.nixos.base`), with the module system automatically merging them.

The name "dendritic" comes from the tree-like auto-discovery structure, inspired by dendrix's implementation.

**Computational**: Combines three mechanisms:

1. **Auto-discovery**: import-tree recursively finds all `.nix` files and adds them to evalModules imports list
2. **Deferred modules**: Each file exports a function `{ config, ... }: { ... }` evaluated during fixpoint computation
3. **Namespace merging**: Multiple files defining the same option path merge via deferredModule monoid composition

Directory structure:
```
modules/
  base/
    nix.nix          → flake.modules.nixos.base (via deferred module)
    users.nix        → flake.modules.nixos.base (merged with nix.nix)
  services/
    nginx.nix        → flake.modules.nixos.nginx
```

When import-tree discovers these files, it adds them all to the imports list:
```nix
imports = [
  ./modules/base/nix.nix
  ./modules/base/users.nix
  ./modules/services/nginx.nix
];
```

evalModules processes these imports, and the deferredModule type's merge function collects modules into namespace-specific lists.

**Formal**: Deferred module composition via import-tree auto-discovery and monoid-based namespace merging.

Let $\mathcal{M}$ be the set of deferred modules.
The deferredModule type forms a monoid $(\mathcal{M}, \oplus, \epsilon)$ where:
- $\oplus$ is module concatenation (imports list append)
- $\epsilon$ is the empty module (no definitions)

Auto-discovery implements a functor from directory trees to module lists:

$$
\text{discover} : \text{Tree}(\text{Path}) \to \text{List}(\mathcal{M})
$$

Namespace merging groups modules by option path and applies monoid composition:

$$
\text{mergeNamespace} : \text{Name} \to \text{List}(\mathcal{M}) \to \mathcal{M}
$$
$$
\text{mergeNamespace}(n, [m_1, \ldots, m_k]) = m_1 \oplus m_2 \oplus \cdots \oplus m_k
$$

The dendritic pattern is the composition:

$$
\text{dendritic} = \text{evalModules} \circ \text{mergeNamespace} \circ \text{groupBy}(\text{name}) \circ \text{discover}
$$

**Important distinction**: "Dendritic" describes the organizational pattern (auto-discovery + aspect-oriented structure), not the underlying mechanism (which is deferred module composition from the module system).

**See also**:
- [Dendritic Architecture](/concepts/dendritic-architecture/) (full pattern explanation)
- [dendritic-flake-parts repository](https://github.com/dendrite-systems/dendritic-flake-parts) (pattern source)
- [Flake-parts as Module System Abstraction](/notes/development/modulesystem/flake-parts-abstraction.md#abstraction-boundaries) (what dendritic adds to flake-parts)

---

### perSystem

**Intuitive**: A flake-parts option that holds deferred modules to be evaluated once for each system architecture.
Instead of manually iterating over systems and writing repetitive per-architecture code, you define configuration once in `perSystem` and flake-parts automatically evaluates it for each system in `systems`.

This is a flake-parts convenience, not a module system primitive.

**Computational**: The `perSystem` option has type `deferredModule` and is evaluated via a nested evalModules call:

```nix
# For each system in config.systems:
allSystems.${system} = (lib.evalModules {
  modules = config.perSystem;  # deferred modules from perSystem option
  specialArgs = { inherit system; };
  class = "perSystem";
  prefix = [ "perSystem" system ];
}).config;
```

Module arguments available in perSystem modules:
- `system`: current system string (e.g., "x86_64-linux")
- `config`: perSystem configuration (not top-level flake config)
- `inputs'`: system-specific view of flake inputs
- `self'`: system-specific view of self outputs

The transposition module merges perSystem results into flake outputs:
```nix
flake.packages = mapAttrs
  (_system: cfg: cfg.packages)
  config.allSystems;
```

**Formal**: Per-system evaluation as a monoidal action over the system set.

Let $\mathcal{S}$ be the set of system strings (e.g., `{"x86_64-linux", "aarch64-darwin", ...}`).
Let $\text{Module}_{\text{perSystem}}$ be deferred modules with class "perSystem".

The `perSystem` option defines:

$$
\text{perSystem} : \text{Module}_{\text{perSystem}}
$$

Evaluation maps this to system-indexed configurations:

$$
\text{allSystems} : \mathcal{S} \to \text{Config}_{\text{perSystem}}
$$

defined by:

$$
\text{allSystems}(s) = \text{evalModules}(\text{perSystem}, \{ \text{system} = s \})
$$

Transposition extracts per-system attributes:

$$
\text{transpose} : (\mathcal{S} \to \text{Config}_{\text{perSystem}}) \to \text{AttrSet}
$$

where for attribute name $a$:

$$
(\text{transpose}\, f).a.s = (f\, s).a
$$

**When to use**: Practical flake-parts documentation
**When to prefer "per-system deferred module evaluation"**: Explaining the underlying mechanism

**See also**:
- [Flake-parts perSystem documentation](https://flake.parts/options/flake-parts#opt-perSystem)
- [Flake-parts as Module System Abstraction](/notes/development/modulesystem/flake-parts-abstraction.md#what-flake-parts-provides-not-module-system-primitives) (perSystem as convenience)

---

### module class

**Intuitive**: A string tag that prevents accidental mixing of modules from different contexts.
For example, a NixOS module (class "nixos") shouldn't be accidentally imported into a home-manager configuration (class "homeManager"), because they have different option namespaces and semantics.

Module classes are a nixpkgs module system feature (introduced in RFC 146), not specific to flake-parts.
Flake-parts uses classes "flake" and "perSystem" for its two evaluation layers.

**Computational**: The `class` parameter to evalModules enables class checking:

```nix
lib.evalModules {
  modules = [ someModule ];
  class = "nixos";
}
```

If `someModule` declares `_class = "homeManager"`, evalModules throws an error preventing the mismatch.

Modules declare their class via the `_class` attribute:
```nix
{
  _class = "nixos";
  config.services.nginx.enable = true;
}
```

Generic modules (no class restriction) omit `_class`:
```nix
{
  # No _class means usable in any context
  config.some.option = true;
}
```

The flake-parts `flake.modules.*` option uses class-based namespacing:
- `flake.modules.nixos.*`: modules with `_class = "nixos"`
- `flake.modules.darwin.*`: modules with `_class = "darwin"`
- `flake.modules.generic.*`: modules with no class restriction

**Formal**: A type constraint in the module category.

Let $\mathbf{Mod}$ be the category of modules, and $\mathcal{C}$ be the set of class tags.

The class constraint defines a functor:

$$
\text{Class} : \mathbf{Mod} \to \mathcal{C}
$$

mapping each module to its class (or $\bot$ for generic modules).

evalModules with class $c$ restricts to the subcategory:

$$
\mathbf{Mod}_c = \{ m \in \mathbf{Mod} \mid \text{Class}(m) = c \vee \text{Class}(m) = \bot \}
$$

Class checking ensures type safety: modules from incompatible classes cannot be composed.

**See also**:
- [Module classes RFC](https://github.com/NixOS/rfcs/pull/146)
- [Flake-parts as Module System Abstraction](/notes/development/modulesystem/flake-parts-abstraction.md#module-classes) (classes in flake-parts)

---

## Recommended text patterns

These patterns show how to apply the glossary terminology in documentation:

### For concepts/dendritic-architecture.md

**Current**:
> Every Nix file is a flake-parts module.

**Recommended**:
> Every Nix file is a deferred module (evaluated via flake-parts' module system integration).
> This means modules can reference the final merged configuration without creating circular dependencies.

**Current**:
> The dendritic flake-parts pattern uses auto-discovery to automatically import modules.

**Recommended**:
> The dendritic pattern uses deferred module composition with auto-discovery.
> Import-tree automatically adds all `.nix` files to the evalModules imports list, and the module system's deferredModule type handles merging.

### For architecture documentation

**Pattern**: Establish three-layer model explicitly

```markdown
## Architectural layers

### Layer 0: Module system foundation

- nixpkgs `lib.evalModules` (fixpoint computation)
- `deferredModule` type (delays evaluation for config references)
- Option merging (type-specific merge functions, priority handling)

See: [Module System Primitives](/notes/development/modulesystem/primitives.md)

### Layer 1: Flake-parts framework

- Wraps evalModules for flake outputs (class "flake")
- Defines `flake.modules.*` namespace convention (deferredModule type)
- Provides `perSystem` abstraction (per-system evaluation with class "perSystem")

See: [Flake-parts as Module System Abstraction](/notes/development/modulesystem/flake-parts-abstraction.md)

### Layer 2: Dendritic organization

- Auto-discovery via import-tree (automatic imports list population)
- Directory-based namespace merging (deferredModule monoid composition)
- Aspect-oriented structure (modules organized by feature, not host)

See: [Dendritic Architecture](/concepts/dendritic-architecture/)
```

### For integration documentation

**Pattern**: Explain WHY integration works via shared module system foundation

```markdown
## Integration with external systems

Dendritic modules can be consumed by NixOS, nix-darwin, and home-manager because all use the same module system foundation:

1. **Published via flake.modules.***
   - Option type: `lazyAttrsOf (lazyAttrsOf deferredModule)`
   - Delays evaluation until consumer calls evalModules

2. **Consumed via imports**
   - Consumer adds to imports list: `imports = [ inputs.our-flake.modules.nixos.base ];`
   - evalModules processes imports during fixpoint computation

3. **Evaluated with consumer's arguments**
   - Deferred module receives consumer's `config`, `pkgs`, etc.
   - Module behavior adapts to consumer's configuration context

This works because deferredModule is a nixpkgs primitive, not a flake-parts invention.
The integration is seamless: our modules are just deferred modules exported via a convenient namespace.
```

### For practical guides

**Pattern**: Use framework terminology with one-time grounding

```markdown
## Creating a new module

Create a file in `modules/services/myservice.nix`:

```nix
# This is a deferred module - it won't be evaluated until the final
# configuration is computed. The `config` argument refers to the merged result.
# See /notes/development/modulesystem/primitives.md for details.

{ config, lib, pkgs, ... }:
{
  options.services.myservice = {
    enable = lib.mkEnableOption "my service";
  };

  config = lib.mkIf config.services.myservice.enable {
    # Configuration here
  };
}
```

The dendritic pattern (via import-tree) will automatically discover this file and add it to the module system's imports list.
No manual registration required.
```

---

## Summary

### Key distinctions

1. **Deferred module** (module system primitive) vs **flake-parts module** (framework usage)
   - Use "deferred module" when explaining mechanisms and composition
   - Use "flake-parts module" when giving practical instructions

2. **Dendritic pattern** (organizational convention) vs **deferred module composition** (underlying mechanism)
   - "Dendritic" describes auto-discovery + aspect-oriented structure
   - "Deferred module composition" describes the module system foundation

3. **evalModules** (module system primitive) vs **flake-parts evaluation** (framework wrapper)
   - evalModules is the core fixpoint computation from nixpkgs
   - Flake-parts wraps it with flake-specific options and conventions

4. **Module class** (module system feature) vs **flake.modules.* namespace** (flake-parts convention)
   - Module classes prevent cross-context mixing (nixpkgs feature)
   - flake.modules.* organizes deferred modules by class (flake-parts convention)

### Documentation strategy

- **Conceptual docs**: Start with module system primitives (deferred module, evalModules, fixpoint), then show how flake-parts uses them, finally present dendritic as organizational pattern
- **Practical docs**: Use flake-parts and dendritic terminology, with one-time link to foundations for interested readers
- **Architecture docs**: Explicit three-layer model (module system → flake-parts → dendritic) with clear boundaries
- **Integration docs**: Explain compatibility via shared module system foundation

### References

- [Module System Primitives](/notes/development/modulesystem/primitives.md) - Detailed algebraic foundations
- [Flake-parts as Module System Abstraction](/notes/development/modulesystem/flake-parts-abstraction.md) - What flake-parts adds
- [Canonical URLs](/notes/development/modulesystem/canonical-urls.md) - Official documentation sources
- [Terminology Inventory](/notes/development/modulesystem/doc-terminology-inventory.md) - Current usage analysis
