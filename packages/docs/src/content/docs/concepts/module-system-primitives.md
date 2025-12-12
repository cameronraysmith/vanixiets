---
title: Module system primitives
description: Understanding deferredModule, evalModules, and fixpoint computation - the foundations that enable Nix configuration composition
sidebar:
  order: 3
---

The Nix module system implements a sophisticated configuration composition mechanism that can be understood through its core algebraic primitives.
This document provides three-tier explanations (intuitive, computational, and formal) for each primitive to illuminate both practical usage and mathematical structure.

Understanding these primitives is essential for working with Nix at scale because they explain why the module system supports complex patterns like conditional imports, priority overrides, and recursive submodules while maintaining predictable semantics.
The algebraic foundations are not merely theoretical—they are the reason NixOS configurations compose reliably.

## deferredModule

**Source reference**: [nixpkgs lib/types.nix:1138-1180](https://github.com/NixOS/nixpkgs/blob/nixos-25.11/lib/types.nix#L1138-L1180)

### Intuitive explanation

A deferred module is a module definition that hasn't been evaluated yet because it needs to wait for the final configuration to be computed.
Think of it as a recipe that says "once you know what the final meal looks like, I'll tell you what ingredients I need."
This is the fundamental mechanism that allows modules to reference the final configuration value without creating infinite loops.

The most common form is a function taking `{ config, ... }` arguments, where `config` refers to the fully-merged configuration after all modules have been combined.
This enables conditional logic like "if some other option is enabled, then enable this feature too" without the evaluator getting stuck in circular dependencies.

### Computational explanation

When you write a module as a function:

```nix
{ config, pkgs, ... }: {
  services.nginx.enable = config.services.web.enable;
}
```

This function is NOT called immediately.
Instead, the module system:

1. Collects all modules (both immediate attribute sets and deferred functions)
2. Computes a fixpoint where `config` becomes the result of evaluating all modules with that same `config` value
3. Only then calls deferred module functions with the fixpoint `config`

The type implementation shows this clearly:

```nix
deferredModuleWith = { staticModules ? [] }: mkOptionType {
  name = "deferredModule";
  check = x: isAttrs x || isFunction x || path.check x;
  merge = loc: defs: {
    imports = staticModules ++ map (def:
      lib.setDefaultModuleLocation "${def.file}, via option ${showOption loc}" def.value
    ) defs;
  };
  # ...
};
```

The `merge` function doesn't evaluate the modules—it just collects them into an `imports` list.
The actual evaluation happens later in `evalModules` via the fixpoint computation.

### Formal characterization

A deferred module is a morphism in a Kleisli category over a reader-like effect that provides access to the final configuration.

$$
\text{deferredModule} : \text{Env} \to \text{Module}
$$

where $\text{Env}$ is the environment containing the fixpoint configuration $c : \text{Config}$, and $\text{Module}$ is a structure defining options and configuration values.

More precisely, modules form a category $\mathbf{Mod}$ where:
- Objects are module interfaces (sets of option declarations)
- Morphisms are module implementations (functions from configurations to definitions)

The deferred module type embeds the Kleisli category $\mathbf{Kl}(T)$ for the reader monad $T = (-) \times \text{Config}$ into $\mathbf{Mod}$.

A module expression of the form:

$$
m : \text{Config} \to \{ \text{options} : \text{Options}, \text{config} : \text{Definitions} \}
$$

is suspended until the fixpoint operator provides the actual configuration value:

$$
\text{config}_{\text{final}} = \mu c.\, \bigsqcup_{i} m_i(c)
$$

where $\mu$ denotes the least fixpoint and $\sqcup$ is the join operation in the configuration lattice.

The module system orchestrates two complementary algebraic structures:

1. **Type-level monoid** (module collection): deferredModule values form a monoid under concatenation of imports lists—identity is the empty list `[]`, operation is list concatenation `++`, and composition happens before fixpoint computation
2. **Semantic-level join-semilattice** (configuration merging): merged configuration values form a join-semilattice with type-specific merge operations, computed after the fixpoint resolves cross-module references

The transition from monoid (module collection) to semilattice (configuration merging) happens via `evalModules` fixpoint computation.
Deferred modules enable a traced monoidal category structure where the trace operation implements the fixpoint that ties the configuration back to itself.

### Connecting formalism to implementation

The Kleisli category characterization directly corresponds to everyday Nix module syntax:

| Kleisli Operation | Module System Primitive | Nix Manifestation |
|-------------------|-------------------------|-------------------|
| `ask` | Config access | `{ config, ... }: config.foo.bar` |
| `fmap` | Option transformation | Defining values in terms of other options |
| `>>=` (bind) | Chained references | Module A reads config set by Module B |
| `trace` | Fixpoint tying | `config = F(config)` recursive binding |

Concretely:

```nix
{ config, lib, ... }: {
  options.paths.base = lib.mkOption { type = lib.types.str; };
  options.paths.processed = lib.mkOption { type = lib.types.str; };

  config.paths.processed = "${config.paths.base}/processed";
}
```

This seemingly circular reference works because it's a suspended reader computation.
The module doesn't immediately evaluate `config.paths.base`—it constructs a function from `config` to definitions.
When `evalModules` computes the fixpoint via demand-driven lazy evaluation, it ties the knot: the final `config` becomes the argument to all module functions, resolving `config.paths.processed` without explicit threading.

## evalModules

**Source reference**: [nixpkgs lib/modules.nix:84-367](https://github.com/NixOS/nixpkgs/blob/nixos-25.11/lib/modules.nix#L84-L367)

### Intuitive explanation

`evalModules` is the function that takes a list of modules and produces a final configuration by:
1. Recursively discovering all imported modules
2. Collecting all option declarations
3. Collecting all configuration definitions
4. Computing a fixpoint where configuration values can reference the final merged result
5. Merging all definitions according to option types and priorities
6. Checking that all definitions match declared options

It's the "main" function of the module system—the evaluator that turns a collection of module fragments into a coherent configuration.

The fixpoint computation is what enables powerful patterns like "enable this service if that service is enabled" without falling into infinite recursion, because all references to `config` are accessing the same final value.

### Computational explanation

The evaluation proceeds in phases:

**Phase 1: Collection** (`collectModules`)
```nix
collectModules class modulesPath (regularModules ++ [internalModule]) args
```
Recursively expands all `imports`, filters `disabledModules`, and produces a flat list of normalized modules.

**Phase 2: Merging** (`mergeModules`)
```nix
merged = mergeModules prefix (reverseList (doCollect {}).modules);
```
Traverses the option tree, matching definitions to declarations and recursing into submodules.

**Phase 3: Fixpoint resolution**
```nix
config = let
  declaredConfig = mapAttrsRecursiveCond (v: !isOption v) (_: v: v.value) options;
  freeformConfig = /* handle unmatched definitions */;
in if declaredConfig._module.freeformType == null
   then declaredConfig
   else recursiveUpdate freeformConfig declaredConfig;
```

The fixpoint is implicit in Nix's lazy evaluation: when a module function is called with `config`, it receives a thunk that will eventually evaluate to the merged result—which may include values produced by that same function.
Nix's laziness ensures this only works if there are no strict cycles (e.g., `a = a + 1` fails, but `a = if b then x else y; b = someCondition` works).

The key implementation detail:
```nix
config = addErrorContext
  "if you get an infinite recursion here, you probably reference `config` in `imports`..."
  config;
```

This shows `config` is a self-referential binding that relies on lazy evaluation to resolve.

### Formal characterization

`evalModules` computes the least fixpoint of a module configuration functor in a domain-theoretic framework via demand-driven lazy evaluation, not classical Kleene iteration.

Let $\mathcal{M}$ be the set of all modules, and define the configuration space $\mathcal{C}$ as a complete lattice of partial configurations ordered by information content (the Smyth order: $c_1 \sqsubseteq c_2$ iff $c_2$ extends $c_1$).

Each module $m_i$ defines a function:

$$
F_{m_i} : \mathcal{C} \to \mathcal{C}
$$

that takes a configuration and produces additional definitions.
The combined module system defines:

$$
F : \mathcal{C} \to \mathcal{C}, \quad F(c) = \bigsqcup_{i=1}^{n} F_{m_i}(c)
$$

where $\sqcup$ is the join operation in the configuration lattice (merging definitions according to type-specific merge functions and priority ordering).

By the Knaster-Tarski theorem, since $F$ is monotone on the complete lattice $\mathcal{C}$, it has a unique least fixpoint:

$$
\text{evalModules}(m_1, \ldots, m_n) = \mu F = \text{lfp}(F)
$$

The classical Kleene characterization $\text{lfp}(F) = \bigsqcup_{k \geq 0} F^k(\bot)$ describes the mathematical object (where $\bot$ is the minimal configuration and $F^k$ denotes $k$ applications of $F$), but Nix does not compute this series directly—it uses demand-driven thunk evaluation instead, computing only the portions of the fixpoint actually demanded.

**Lattice structure**: The configuration lattice is product of per-option lattices:

$$
\mathcal{C} = \prod_{o \in \text{Options}} \mathcal{L}_o
$$

where each option's lattice $\mathcal{L}_o$ is determined by:
- Primitive types (int, string): flat lattice (only $\bot$ and incomparable values)
- `mkMerge`: forms join of sublattices
- `mkOverride`: imposes priority ordering (values with priority $p$ dominate those with priority $p' > p$)
- `submodule`: recursive fixpoint on nested configuration lattice

**Convergence**: Nix reaches the fixpoint without exhaustive iteration because:
1. Lazy evaluation computes only demanded portions of the configuration space
2. Each demand resolves more thunks, monotonically increasing defined values
3. The demanded slice has finite height (no infinite ascending chains in practice)
4. Stabilization happens per-demanded-value, not globally across the entire lattice

Unlike classical Kleene iteration (which computes $F^0(\bot), F^1(\bot), F^2(\bot), \ldots$ until global stabilization), Nix evaluates thunks on demand.
The mathematical result is identical (the least fixpoint), but the computational path is fundamentally different.

**Category theory perspective**: The fixpoint computation implements a trace operation in a traced monoidal category.
The module system forms a compact closed category where:
- Objects are option sets (interfaces)
- Morphisms are modules (implementations)
- The trace of a morphism $f : A \otimes C \to B \otimes C$ is $\text{Tr}_C(f) : A \to B$, which "ties the knot" on the internal state $C$ (the configuration being computed)

The equation `config = F(config)` is precisely the trace operation that connects the output configuration back to the input, relying on domain-theoretic fixpoints for well-definedness.

## Option merging primitives

**Source references**:
- [nixpkgs lib/modules.nix:1469-1509](https://github.com/NixOS/nixpkgs/blob/nixos-25.11/lib/modules.nix#L1469-L1509) (mkIf, mkMerge, mkOverride)
- [nixpkgs lib/modules.nix:1155-1257](https://github.com/NixOS/nixpkgs/blob/nixos-25.11/lib/modules.nix#L1155-L1257) (mergeDefinitions)

### Intuitive explanation

Option merging determines what happens when multiple modules define the same option.
The module system provides several primitives to control this:

**`mkMerge`**: Explicitly combine multiple values. Without this, writing `foo = [a]; foo = [b];` in the same module would be an error (duplicate attribute). `mkMerge [a b]` says "I'm intentionally providing multiple values to be merged."

**`mkOverride`** (and its aliases `mkDefault`, `mkForce`): Attach a priority to a value.
Lower numeric priorities win.
This enables the pattern where modules can set sensible defaults (`mkDefault`) that users can override without conflicts.

**`mkIf`**: Conditionally include a value.
Unlike a plain Nix `if` expression, `mkIf` conditions can reference the final configuration, and `mkIf false` values disappear entirely (don't contribute to merging).

**`mkOrder`** (and `mkBefore`/`mkAfter`): Control the order of list elements when merging.
Useful for ensuring certain items appear first or last in merged lists.

### Computational explanation

The merging process (`mergeDefinitions`) operates in stages:

**Stage 1: Discharge properties**
```nix
defsNormalized = concatMap (m:
  map (value: if value._type or null == "definition" then value else { inherit (m) file; inherit value; })
  (dischargeProperties m.value)
) defs;
```

This expands `mkMerge` (flattens nested merges) and evaluates `mkIf` conditions:
- `mkMerge [a b c]` becomes `[a, b, c]`
- `mkIf true x` becomes `[x]`
- `mkIf false x` becomes `[]`

**Stage 2: Filter by priority**
```nix
defsFiltered = filterOverrides' defsNormalized;
```

Examines all `mkOverride` priorities and keeps only definitions with the highest priority (lowest number):
```nix
getPrio = def: if def.value._type or "" == "override"
               then def.value.priority
               else defaultOverridePriority;  # 100
highestPrio = foldl' (prio: def: min (getPrio def) prio) 9999 defs;
values = filter (def: getPrio def == highestPrio) defs;
```

Default priorities:
- `mkOptionDefault`: 1500 (option's own default)
- `mkDefault`: 1000 (module default)
- No modifier: 100 (user value)
- `mkForce`: 50 (force override)

**Stage 3: Sort by order**
```nix
defsSorted = if any (def: def.value._type or "" == "order") defsFiltered.values
             then sortProperties defsFiltered.values
             else defsFiltered.values;
```

For list-valued options, `mkBefore` (priority 500) items appear before default (1000) before `mkAfter` (1500).

**Stage 4: Type-specific merge**
```nix
mergedValue = if type.merge ? v2
              then checkedAndMerged.value  # new v2 protocol
              else type.merge loc defsFinal;  # classic merge
```

Each type defines its own merge function:
- Lists: concatenate
- Attribute sets: recursive merge
- Integers: must all be equal (or use `mergeEqualOption`)
- Submodules: recursive `evalModules`

### Formal characterization (semantic-level join-semilattice)

Option merging forms a join-semilattice with priority stratification—this is the semantic-level algebraic structure that operates after fixpoint computation resolves cross-module references.

**Join-semilattice structure**: For each option of type $\tau$, the set of possible merged values $M_\tau$ forms a join-semilattice $(\mathcal{L}_\tau, \sqcup)$ where:

$$
\text{merge}([d_1, d_2, \ldots, d_n]) = d_1 \sqcup d_2 \sqcup \cdots \sqcup d_n
$$

The join operation $\sqcup$ is type-dependent:

**Lists**: $\mathcal{L}_{\text{listOf}\, \alpha} = \text{List}(\alpha)$ with join:
$$
xs \sqcup ys = xs \mathbin{+\!\!+} ys
$$
(list concatenation, associative with identity $[]$).

**Attribute sets**: $\mathcal{L}_{\text{attrsOf}\, \alpha} = \text{Name} \to \mathcal{L}_\alpha$ with pointwise join:
$$
(f \sqcup g)(n) = \begin{cases}
f(n) \sqcup g(n) & \text{if } n \in \text{dom}(f) \cap \text{dom}(g) \\
f(n) & \text{if } n \in \text{dom}(f) \setminus \text{dom}(g) \\
g(n) & \text{if } n \in \text{dom}(g) \setminus \text{dom}(f)
\end{cases}
$$

**Submodules**: $\mathcal{L}_{\text{submodule}\, M} = \mu C.\, \text{Eval}(M, C)$ (recursive fixpoint).

**Priority stratification**: Definitions carry a priority $p \in \mathbb{N}$ (lower is higher priority).
The priority-filtered merge is:

$$
\text{mergeWithPrio}([(p_1, d_1), \ldots, (p_n, d_n)]) = \bigsqcup \{ d_i \mid p_i = \min_j p_j \}
$$

This forms a **lexicographic ordering**: first compare priorities, then merge equal-priority values.

Formally, we have a stratified lattice:
$$
\mathcal{L}_{\text{withPrio}} = \mathbb{N}^{\text{op}} \times \mathcal{L}
$$
ordered by $(p_1, v_1) \leq (p_2, v_2)$ iff $p_1 \geq p_2$ and ($p_1 > p_2$ or $v_1 \leq v_2$).

**Conditional merging** (`mkIf`): The condition mechanism extends the lattice with a bottom element representing "not defined":

$$
\mathcal{L}_{\text{conditional}} = \mathcal{L} + \{ \bot_{\text{undef}} \}
$$

with $\bot_{\text{undef}} \sqcup v = v$ and $\bot_{\text{undef}}$ absorbing in the priority ordering.

The `mkIf` operation:
$$
\text{mkIf} : \text{Bool} \to \mathcal{L} \to \mathcal{L}_{\text{conditional}}
$$
$$
\text{mkIf}(b, v) = \begin{cases}
v & \text{if } b = \text{true} \\
\bot_{\text{undef}} & \text{if } b = \text{false}
\end{cases}
$$

**Order control** (`mkBefore`, `mkAfter`): For list-typed options, elements carry an order priority $o \in \mathbb{N}$.
The merge operation first sorts by order priority, then concatenates:

$$
\text{mergeOrdered}([(o_1, xs_1), \ldots, (o_n, xs_n)]) = \text{concat}(\text{sortBy}(\pi_1, [(o_1, xs_1), \ldots, (o_n, xs_n)]))
$$

where $\text{sortBy}(\pi_1, \_)$ sorts tuples by their first component.

**Why this matters**: The algebraic structure ensures:
1. **Associativity**: Order of module evaluation doesn't matter (up to priority ties)
2. **Commutativity**: Module order doesn't matter (except for lists without order annotations)
3. **Idempotence**: Importing a module twice has the same effect as once (if no side effects)
4. **Composability**: Submodules compose cleanly because they use the same merge algebra

The join-semilattice structure is the key to modular reasoning: you can understand each module's contribution independently and combine them without global analysis.

## Type system and constraints

**Source reference**: [nixpkgs lib/types.nix](https://github.com/NixOS/nixpkgs/blob/nixos-25.11/lib/types.nix) (entire file, especially type definitions)

### Intuitive explanation

Option types serve two purposes:
1. **Runtime validation**: Check that defined values match the expected shape (e.g., "is this actually an integer?")
2. **Merge behavior specification**: Define how to combine multiple definitions into a single value

Every option has a type (defaulting to `types.unspecified` if not given).
The type's `check` function validates values, and its `merge` function combines them.

Common types:
- **Primitives** (`int`, `str`, `bool`, `path`): Validate structure, require all definitions to be equal
- **Containers** (`listOf`, `attrsOf`): Recursively validate elements, concatenate or recursively merge
- **Submodules** (`submodule`, `submoduleWith`): Nest entire module evaluations
- **Combinators** (`nullOr`, `either`, `enum`): Logical combinations of types

Types form a little language for describing configuration schemas, similar to JSON Schema or TypeScript types, but with merge semantics baked in.

### Computational explanation

A type is an attribute set with specific attributes:

```nix
mkOptionType {
  name = "descriptive-name";
  description = "human-readable description";
  check = value: /* returns true if value is valid */;
  merge = loc: defs: /* combines list of definitions into single value */;

  # Optional but important:
  getSubOptions = prefix: /* for documentation and submodules */;
  getSubModules = /* list of submodules if this is a submodule type */;
  substSubModules = m: /* rebind submodules for type merging */;
  typeMerge = functor: /* merge two types (e.g., two listOfs) */;
}
```

**Type checking happens during merge**:
```nix
mergedValue =
  if isDefined then
    if type.merge ? v2 then
      if checkedAndMerged.headError or null != null
      then throw "not of type ${type.description}"
      else checkedAndMerged.value
    else if all (def: type.check def.value) defsFinal
    then type.merge loc defsFinal
    else throw "not of type ${type.description}"
  else throw "option has no value defined";
```

**Type merging** allows combining option declarations:
```nix
# Module 1
options.foo = mkOption { type = types.listOf types.int; };

# Module 2
options.foo = mkOption { type = types.listOf types.int; };

# Result: types are merged, option is declared once
```

The `typeMerge` function checks compatibility:
```nix
defaultTypeMerge = f: f':
  if f.name != f'.name then null  # incompatible
  else if hasPayload then
    if mergedPayload == null then null
    else f.type mergedPayload  # e.g., merge elemTypes
  else f.type;
```

**Submodule nesting** creates recursive lattices:
```nix
types.submoduleWith { modules = [...]; }
```
When merged, creates a nested `evalModules` call with the submodule list, creating a recursive fixpoint:
```nix
merge = loc: defs:
  let configuration = base.extendModules {
    modules = allModules defs;
    prefix = loc;
  };
  in configuration.config;
```

### Formal characterization

The type system forms a category $\mathbf{Type}$ with:
- **Objects**: Types $\tau$ (potentially infinite sets equipped with merge operations)
- **Morphisms**: Type refinements (subtyping relations)

Each type $\tau$ defines:

1. **Value space**: $\llbracket \tau \rrbracket \subseteq \text{Value}$ (the set of valid values)
2. **Merge algebra**: $(\mathcal{M}_\tau, \sqcup_\tau)$ where $\mathcal{M}_\tau$ is a join-semilattice
3. **Interpretation function**: $\text{merge}_\tau : \text{List}(\llbracket \tau \rrbracket) \to \llbracket \tau \rrbracket$

**Type constructors** are functors $\mathbf{Type} \to \mathbf{Type}$:

**ListOf functor**:
$$
\text{ListOf} : \mathbf{Type} \to \mathbf{Type}
$$
$$
\llbracket \text{listOf}\, \alpha \rrbracket = \text{List}(\llbracket \alpha \rrbracket)
$$
$$
\sqcup_{\text{listOf}\, \alpha} = \text{concat} : \text{List}(\llbracket \alpha \rrbracket) \times \text{List}(\llbracket \alpha \rrbracket) \to \text{List}(\llbracket \alpha \rrbracket)
$$

**AttrsOf functor**:
$$
\text{AttrsOf} : \mathbf{Type} \to \mathbf{Type}
$$
$$
\llbracket \text{attrsOf}\, \alpha \rrbracket = \text{Name} \to \llbracket \alpha \rrbracket
$$
$$
(f \sqcup_{\text{attrsOf}\, \alpha} g)(n) = \begin{cases}
f(n) \sqcup_\alpha g(n) & n \in \text{dom}(f) \cap \text{dom}(g) \\
f(n) & n \in \text{dom}(f) \setminus \text{dom}(g) \\
g(n) & n \in \text{dom}(g) \setminus \text{dom}(f)
\end{cases}
$$

**Submodule as fixpoint**:
$$
\text{Submodule} : \text{List}(\text{Module}) \to \mathbf{Type}
$$
$$
\llbracket \text{submodule}\, [m_1, \ldots, m_n] \rrbracket = \mu C.\, \text{evalModules}([m_1, \ldots, m_n], C)
$$

This is a recursive type equation: the type of a submodule is defined as the fixpoint of evaluating its modules, which may themselves contain submodules.

**Type merging as coproduct**: When two modules declare the same option with different types, the system attempts to merge the types.
This is a pushout in $\mathbf{Type}$:

$$
\begin{array}{ccc}
\tau_1 & \to & \tau_1 \sqcup \tau_2 \\
\downarrow & & \downarrow \\
\tau_2 & \to & \tau_1 \sqcup \tau_2
\end{array}
$$

For compatible types (e.g., both `listOf int`), the pushout exists.
For incompatible types (e.g., `int` and `string`), it doesn't, and the system throws an error.

**Constraint propagation**: Type checking is interleaved with merging via the v2 merge protocol:

$$
\text{merge}_\tau^{v2} : \text{List}(\llbracket \tau \rrbracket) \to (\llbracket \tau \rrbracket + \text{Error})
$$

returning either the merged value or a type error.
This enables fine-grained error messages pointing to specific problematic definitions.

**Categorical perspective**: The type system implements a **graded monad** where:
- The grade is the type $\tau$
- The functor $T_\tau$ maps values to "typed optional values"
- The join operation $\mu_\tau : T_\tau(T_\tau(A)) \to T_\tau(A)$ is the merge function

The grading ensures type-safe composition: you can only merge values of compatible types.

**Why types matter for composition**: The type constraint lattice ensures:
1. **Local type checking**: Each module's definitions can be checked independently against declared types
2. **Compositional merging**: Merge operations distribute over type constructors (e.g., merging two `listOf int` gives `listOf int`)
3. **Submodule isolation**: Submodules can't violate their parent's type constraints
4. **Documentation generation**: Types provide machine-readable schemas for automatic documentation

The type system transforms the module system from untyped attribute set merging into a typed configuration language with static guarantees.

## Fixpoint computation and lazy evaluation

While not a single primitive, the interaction between Nix's lazy evaluation and the module system's fixpoint computation deserves explicit treatment.

### Intuitive explanation

The module system's "killer feature" is allowing modules to reference the final configuration while that configuration is still being computed.
This works because Nix doesn't evaluate expressions until their values are actually needed.

When you write:
```nix
{ config, ... }: {
  services.foo.enable = config.services.bar.enable;
}
```

Nix doesn't immediately try to look up `config.services.bar.enable`.
Instead, it creates a **thunk** (a suspended computation).
Later, when something needs the value of `services.foo.enable`, Nix evaluates the thunk, which triggers evaluation of `config.services.bar.enable`, which may trigger other evaluations, and so on.

As long as there's no strict cycle (A needs B's value before B is computed, and B needs A's value before A is computed), lazy evaluation finds a consistent solution.

### Computational explanation

The fixpoint is established via Nix's `let rec` binding:

```nix
let
  # Simplified view of evalModules internals
  config = mapAttrs (_: opt: opt.value) options;
  options = /* compute options by evaluating modules with 'config' */;
in config
```

This is a mutually recursive definition.
Nix resolves it by:

1. Allocating thunks for both `config` and `options`
2. When `options` is demanded, evaluate it, which may demand parts of `config`
3. When parts of `config` are demanded, evaluate those specific attributes, which demands parts of `options`
4. Continue until a consistent fixpoint is reached (or detect infinite recursion)

**Infinite recursion detection**: Nix tracks which thunks are currently being evaluated.
If evaluating thunk A demands the value of thunk A (before A has finished), that's infinite recursion:

```nix
# This fails:
{ config, ... }: {
  services.foo.value = config.services.foo.value + 1;
}
```

But conditional recursion works:
```nix
# This works:
{ config, ... }: {
  services.foo.value =
    if config.services.bar.enable
    then config.services.baz.value
    else 42;
}
```

As long as the chain of demands terminates before cycling back, lazy evaluation succeeds.

**The practical implication**: You can write modules that make decisions based on what other modules decided, creating a declarative "logic programming" style configuration where the order of module evaluation doesn't matter.

### Formal characterization

The fixpoint computation implements a **domain-theoretic least fixpoint** via Nix's lazy evaluation strategy.

**Scott domains**: Nix values form a Scott domain—a partially ordered set where:
1. Every directed subset has a least upper bound (join)
2. The ordering represents "information content" ($\bot \sqsubseteq x$ means $\bot$ is "less defined" than $x$)

The bottom element $\bot$ represents "not yet evaluated" (a thunk).
As evaluation proceeds, thunks are replaced with more defined values.

**Continuous functions**: Each module defines a continuous function:
$$
F_m : \mathcal{D}_{\text{Config}} \to \mathcal{D}_{\text{Config}}
$$

where $\mathcal{D}_{\text{Config}}$ is the Scott domain of configurations, and continuity means:
$$
F(\bigsqcup_{i \in I} c_i) = \bigsqcup_{i \in I} F(c_i)
$$

for any directed set $\{c_i\}_{i \in I}$.

**Fixpoint theorem**: For a continuous function $F : \mathcal{D} \to \mathcal{D}$ on a pointed domain $(\mathcal{D}, \sqsubseteq, \bot)$, the least fixpoint exists and equals:

$$
\mu F = \bigsqcup_{n \geq 0} F^n(\bot)
$$

Nix's lazy evaluation implements this via **demand-driven fixpoint iteration**:
- Start with all values as $\bot$ (thunks)
- When a value is demanded, compute one iteration step $F(\text{current})$
- If that demands another thunk, recursively evaluate it
- Update the configuration with newly computed values

**Well-founded recursion**: The domain has finite height in the demanded slice (the portion of the configuration actually needed).
This ensures:
$$
\exists n.\, F^n(\bot) = F^{n+1}(\bot)
$$

meaning iteration converges in finitely many steps.

**Thunk semantics**: A thunk represents a morphism in the Kleisli category for the partiality monad:
$$
\text{Thunk}(A) = \mu X.\, (A + X)
$$

The fixpoint equation $X = A + X$ means a thunk either evaluates to a value ($A$) or to another thunk ($X$), enabling the recursive structure.

**Infinite recursion as non-termination**: A strict cycle creates a non-continuous function where:
$$
F(\bot) = \bot, \quad F(F(\bot)) = \bot, \quad \ldots
$$

The least fixpoint is $\bot$ (undefined), and Nix's evaluator detects this by tracking the call stack.

**Categorical perspective**: The fixpoint construction is a trace operation in the category of domains and continuous functions:
$$
\text{Tr}_C : \mathbf{Dom}(A \otimes C, B \otimes C) \to \mathbf{Dom}(A, B)
$$

For $f : A \otimes C \to B \otimes C$, the trace $\text{Tr}_C(f) : A \to B$ is the fixpoint of the internal state $C$.

In the module system:
- $A$ is the external input (module parameters like `pkgs`)
- $B$ is the output configuration
- $C$ is the internal state (the configuration being computed)
- $f$ is the module evaluation function
- $\text{Tr}_C(f)$ is `evalModules`, which ties the configuration back to itself

The trace operation implements the "knot-tying" that makes self-referential configurations work.

**Why this enables modular reasoning**: The fixpoint is deterministic (least fixpoint is unique) and depends only on the module functions, not evaluation order.
This means:
1. Module composition is order-independent (commutative)
2. Adding modules is monotone (more modules = more defined configuration)
3. Local reasoning is sound (understand each module in isolation, combine via fixpoint)

The domain-theoretic foundation ensures the module system's declarative semantics are mathematically rigorous, not just "it works because Nix is lazy."

## Summary

The Nix module system's algebraic primitives form a coherent mathematical structure:

1. **Deferred modules** embed Kleisli category morphisms, enabling computation to reference fixpoint results; at the type level, they form a monoid under imports list concatenation
2. **evalModules** computes the unique least fixpoint in domain-theoretic configuration lattices via demand-driven lazy evaluation, not classical Kleene iteration
3. **Merging primitives** implement semantic-level join-semilattice operations with priority stratification (after fixpoint resolves references)
4. **Types** define graded monads constraining merge algebras and enabling compositional reasoning
5. **Lazy evaluation** realizes domain-theoretic fixpoints via demand-driven thunk evaluation, computing only demanded portions of the configuration

Together, these primitives transform attribute set merging into a powerful typed functional language for declarative configuration, where:
- Composition is order-independent (associative, commutative)
- Submodules nest cleanly (recursive fixpoints)
- Overrides work predictably (priority lattice)
- Circular dependencies resolve automatically (lazy fixpoint)

Understanding these algebraic foundations explains why the module system supports complex patterns (conditional imports, priority overrides, recursive submodules) while maintaining predictable semantics.
The mathematics isn't just theoretical—it's the reason NixOS configurations compose reliably at scale.

## Further reading

- [nix.dev module system tutorial](https://nix.dev/tutorials/module-system/index.html)
- [nixpkgs lib/modules.nix source](https://github.com/NixOS/nixpkgs/blob/nixos-25.11/lib/modules.nix)
- [nixpkgs lib/types.nix source](https://github.com/NixOS/nixpkgs/blob/nixos-25.11/lib/types.nix)
