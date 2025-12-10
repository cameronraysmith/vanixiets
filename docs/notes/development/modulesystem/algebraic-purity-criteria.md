---
title: Algebraic purity criteria for Nix configurations
---

# Algebraic purity criteria for Nix configurations

Algebraic purity in Nix configurations means patterns that respect the mathematical structures underlying the module system: deferred evaluation, fixpoint composition, and lattice-theoretic merging.
These criteria provide a framework for auditing configurations to ensure they preserve the compositional properties that make the module system reliable at scale.

## Overview

The module system implements a domain-theoretic configuration language where modules are morphisms in a Kleisli category, evaluation computes least fixpoints on configuration lattices, and merging implements join-semilattice operations with priority stratification.
Algebraic purity ensures our patterns align with these underlying structures rather than working against them.

This document defines five core criteria for auditing module configurations, ranked by severity and supported by both intuitive explanations and formal mathematical characterizations.
Each criterion includes computational checks (grep patterns or build tests) and practical examples of violations and fixes.

## Criteria

### 1. Deferred module purity

**Severity**: HIGH (breaks fixpoint semantics)

**Principle**: Module exports should be properly deferred (functions, not immediate attrsets).

**Intuitive**: The module doesn't "run" until it knows what the final config looks like.
When you export a module as a function `{ config, ... }: { ... }`, you're saying "call me later, after the fixpoint is computed, so I can reference config values".
If you export an immediate attrset `{ some.option = "value"; }`, you're computing values before the module system has a chance to establish the fixpoint.

**Why it matters**: While the module system will wrap immediate attrsets in deferred modules during merge, using functions explicitly makes the deferred nature visible and prevents accidentally referencing values that don't exist yet.

**Computational check**:
```nix
# CORRECT (deferred function)
flake.modules.nixos.foo = { config, lib, pkgs, ... }: {
  services.bar.enable = config.services.baz.enable;
};

# ACCEPTABLE (immediate attrset, will be wrapped)
flake.modules.nixos.foo = {
  services.bar.enable = true;  # Static value only
};

# VIOLATION (immediate attrset referencing config)
# This won't work because config doesn't exist at assignment time
flake.modules.nixos.foo = {
  services.bar.enable = config.services.baz.enable;  # ERROR
};
```

**Formal basis**: Deferred modules are morphisms in the Kleisli category $\mathbf{Kl}(T)$ for the reader monad $T = (-) \times \text{Config}$.
Immediate attrsets collapse the Kleisli structure by evaluating before the monad's bind operation can thread the configuration context through.
The deferredModule type's merge function preserves the Kleisli structure by collecting functions into an imports list without calling them.

**Detection**:
```bash
# Find immediate attrset assignments that might reference config
rg 'flake\.modules\.[^=]+ = \{' --glob '!*.md'

# Then manually inspect for config references
# (Automated detection is hard because static attrsets are acceptable)
```

**Recommendation**: Prefer explicit function syntax for all module exports.
This makes the deferred nature self-documenting and prevents future edits from accidentally introducing config references in non-function context.

---

### 2. Fixpoint safety

**Severity**: HIGH (prevents evaluation)

**Principle**: No circular dependencies that prevent fixpoint convergence.

**Intuitive**: Module A shouldn't need Module B's final value to compute something that Module B needs from A.
This creates a strict cycle where neither module can finish until the other finishes, which is impossible.
The fixpoint computation works by iteratively refining values from "undefined" to "defined", but strict cycles block this process.

**Computational check**:
```nix
# VIOLATION (strict cycle)
{ config, ... }: {
  services.foo.value = config.services.bar.value + 1;
  services.bar.value = config.services.foo.value + 1;
}
# ERROR: infinite recursion detected

# CORRECT (conditional dependency)
{ config, ... }: {
  services.foo.enable = config.services.bar.enable;
  services.bar.enable = lib.mkDefault false;
}
# Works because mkDefault establishes base case

# CORRECT (lazy dependency)
{ config, lib, ... }: {
  services.foo.extraConfig =
    lib.optionalString config.services.bar.enable
      "bar_host = ${config.services.bar.host}";
}
# Works because optionalString is lazy in condition
```

**Formal basis**: The fixpoint computation requires Scott-continuous functions on pointed complete partial orders (dcpos).
A strict cycle creates a function $F$ where $F(\bot) = \bot$, $F(F(\bot)) = \bot$, ad infinitum.
The least fixpoint is $\bot$ (undefined), which manifests as infinite recursion during evaluation.
The domain-theoretic foundation ensures that acyclic lazy references converge via the Knaster-Tarski fixpoint theorem: for monotone $F$ on complete lattice $\mathcal{C}$, $\mu F = \bigsqcup_{k \geq 0} F^k(\bot)$ exists and is unique.

**Detection**:
```bash
# Build failures reveal fixpoint violations
nix flake check
# Look for "infinite recursion" errors
```

**Common causes**:
1. Two modules each using the other's computed value without a base case
2. Referencing config in option default values (use mkDefault instead)
3. Referencing config in imports list (use conditional imports carefully)

**Fix strategy**:
- Establish base cases using mkDefault or mkOptionDefault
- Use lib.mkIf to make dependencies conditional
- Restructure modules to break dependency cycles
- Consider whether one module should just set a static value

---

### 3. Explicit imports vs specialArgs threading

**Severity**: MEDIUM (maintainability, not correctness)

**Principle**: Dependencies should be explicit via imports, not implicit via specialArgs.

**Intuitive**: Reading a module should show what it depends on without knowing what specialArgs provides.
When you write `imports = [ config.flake.modules.nixos.base ]`, it's clear the module needs base.
When you write `{ specialArg, ... }: { ... }`, you have to grep the entire codebase to find where specialArg comes from.

**Computational check**:
```nix
# CORRECT (explicit imports)
{ config, lib, pkgs, ... }: {
  imports = [
    config.flake.modules.nixos.base
    config.flake.modules.nixos.networking
  ];

  services.foo.enable = true;
}

# AVOID (implicit specialArgs)
# Somewhere in evalModules call:
# specialArgs = { mySharedConfig = ...; };

# Then in module:
{ mySharedConfig, ... }: {  # Where does this come from?
  services.foo = mySharedConfig.foo;
}
```

**Why avoid specialArgs**: While specialArgs is sometimes necessary (like passing inputs flake attribute), overuse creates hidden dependencies.
The module system's imports mechanism is designed for explicit dependency declaration and works better with tooling (dead code detection, documentation generation, dependency graphs).

**Formal basis**: Explicit imports preserve categorical composition—modules are morphisms that compose via imports, maintaining the category laws (identity, associativity).
Implicit specialArgs breaks referential transparency by introducing ambient context that isn't reflected in the module's type signature.
From a type theory perspective, specialArgs is dynamic scoping while imports is lexical scoping.

**Detection**:
```bash
# Find specialArgs usage beyond standard (config, lib, pkgs, inputs)
rg '\{ [^}]*\b(?!config|lib|pkgs|inputs|options|modulesPath|system)\w+,' modules/

# Find specialArgs declarations
rg 'specialArgs\s*='
```

**Exceptions**: specialArgs is appropriate for:
- Passing flake inputs to modules (standard pattern)
- Injecting system or pkgs at evaluation boundaries
- Passing values that genuinely are "global context" for all modules

**Fix strategy**: Convert specialArgs to explicit module options or imports.

---

### 4. Option type correctness

**Severity**: LOW (style, not semantics)

**Principle**: Options should use appropriate types, not stringly-typed escape hatches.

**Intuitive**: If an option is really a boolean, declare it as `types.bool`, not `types.str`.
Types provide runtime validation (catching configuration errors early) and documentation (showing users what values are valid).
Stringly-typed options bypass these safety mechanisms.

**Computational check**:
```nix
# CORRECT (typed)
options.custom.feature.enable = lib.mkOption {
  type = lib.types.bool;
  default = false;
  description = "Enable custom feature";
};

# AVOID (stringly-typed boolean)
options.custom.feature.enable = lib.mkOption {
  type = lib.types.str;
  default = "false";
  description = "Enable custom feature (true/false)";
};

# CORRECT (structured type)
options.custom.service.config = lib.mkOption {
  type = lib.types.submodule {
    options = {
      host = lib.mkOption { type = lib.types.str; };
      port = lib.mkOption { type = lib.types.port; };
    };
  };
};

# AVOID (unstructured attrset)
options.custom.service.config = lib.mkOption {
  type = lib.types.attrs;
  description = "Service configuration (host, port, etc.)";
};
```

**Formal basis**: Types constrain the configuration lattice structure.
The value space $\llbracket \tau \rrbracket$ of a type $\tau$ defines which values can participate in the merge algebra $(\mathcal{M}_\tau, \sqcup_\tau)$.
Using `types.attrs` or `types.str` as escape hatches collapses type safety by allowing arbitrary values into the lattice without validation.
Type constructors (listOf, attrsOf, submodule) are functors $\mathbf{Type} \to \mathbf{Type}$ that preserve lattice structure compositionally.

**Detection**:
```bash
# Find string types that might be booleans
rg 'type\s*=\s*types\.str.*enable' modules/

# Find unstructured attrs types
rg 'type\s*=\s*types\.attrs' modules/
```

**Benefits of proper typing**:
1. Runtime validation catches configuration errors before deployment
2. Documentation generation shows exact schema
3. Merge semantics are well-defined (e.g., lists concatenate, bools must match)
4. Type checking enables static analysis tools

**Fix strategy**:
- Use `types.bool` for boolean options
- Use `types.enum` for string options with fixed set of values
- Use `types.submodule` for structured configuration
- Use `types.listOf`, `types.attrsOf` with element types, not bare lists/attrs

---

### 5. Merge semantics awareness

**Severity**: MEDIUM (can cause unexpected behavior)

**Principle**: Use mkMerge/mkOverride/mkIf intentionally, not accidentally.

**Intuitive**: When multiple modules define the same option, the module system needs to know how to combine them.
`mkMerge` explicitly says "I'm providing multiple definitions to combine".
`mkOverride` says "my definition has priority P".
`mkIf` says "only include my definition if condition is true".
Using these without understanding the semantics can lead to definitions mysteriously disappearing or conflicting.

**Computational check**:
```nix
# CORRECT (explicit merge)
{ lib, ... }: {
  environment.systemPackages = lib.mkMerge [
    [ pkgs.git pkgs.vim ]
    [ pkgs.htop ]
  ];
}

# UNNECESSARY (mkMerge for single definition)
{ lib, ... }: {
  environment.systemPackages = lib.mkMerge [
    [ pkgs.git pkgs.vim pkgs.htop ]
  ];
}
# mkMerge not needed for single list

# CORRECT (priority override)
{ lib, ... }: {
  services.openssh.enable = lib.mkDefault true;
}
# Other modules can override this default

# INCORRECT (force without reason)
{ lib, ... }: {
  services.openssh.enable = lib.mkForce true;
}
# Prevents user from disabling, likely unintended

# CORRECT (conditional definition)
{ config, lib, ... }: {
  services.nginx.enable = lib.mkIf config.services.web.enable true;
}

# INCORRECT (plain if expression)
{ config, lib, ... }: {
  services.nginx.enable = if config.services.web.enable then true else false;
}
# This always defines nginx.enable (to true or false)
# mkIf false removes the definition entirely
```

**Formal basis**: Merging implements a join-semilattice with priority stratification.
The merge operation $\sqcup_\tau : \llbracket \tau \rrbracket \times \llbracket \tau \rrbracket \to \llbracket \tau \rrbracket$ is type-dependent.
Priority filtering creates a lexicographic ordering $(p, v) \leq (p', v')$ iff $p \geq p'$ and ($p > p'$ or $v \leq v'$), where lower numeric priority wins.
Conditional merging (mkIf) extends the lattice with bottom element $\bot_{\text{undef}}$ representing "not defined", with $\bot_{\text{undef}} \sqcup v = v$.

**Priority values**:
- mkOptionDefault: 1500 (option's built-in default)
- mkDefault: 1000 (module default, user can override)
- No modifier: 100 (user value)
- mkForce: 50 (override everything)

**Detection**:
```bash
# Find mkForce usage (review for justification)
rg 'mkForce' modules/

# Find mkOverride with explicit priorities (verify intention)
rg 'mkOverride' modules/

# Find mkIf conditions (verify they can reference config)
rg 'mkIf' modules/
```

**Common mistakes**:
1. Using `mkMerge` for single definition (harmless but unnecessary)
2. Using `mkForce` to "fix" merge conflicts without understanding root cause
3. Using plain `if` expressions instead of `mkIf` for conditional definitions
4. Not using `mkDefault` for module defaults, causing override conflicts

**Fix strategy**:
- Use `mkDefault` for all module-provided defaults that users should be able to override
- Use `mkForce` only when you explicitly want to prevent overrides (document why)
- Use `mkIf` for conditional definitions (better than plain if expressions)
- Use `mkMerge` when combining multiple definition sources in same module

---

## Audit checklist

For each module file, verify:

- [ ] **Deferred module export**: Export is function `{ config, ... }: { ... }` or static attrset without config references
- [ ] **No circular dependencies**: No strict cycles in config references (build succeeds without infinite recursion)
- [ ] **Imports are explicit**: Dependencies come from imports, not specialArgs (except standard: config, lib, pkgs, inputs)
- [ ] **Option types are appropriate**: Use specific types (bool, enum, submodule) not generic escape hatches (str, attrs)
- [ ] **Merge operations are intentional**: mkDefault/mkForce/mkIf are used with understanding, not cargo-culted

## Anti-patterns

### Anti-pattern 1: Immediate module export with config reference

**Violation**:
```nix
# modules/services/foo.nix
{ config, ... }:
{
  flake.modules.nixos.foo = {
    # This doesn't work - config not available at assignment time
    services.foo.enable = config.services.bar.enable;
  };
}
```

**Fix**:
```nix
# modules/services/foo.nix
{ config, ... }:
{
  flake.modules.nixos.foo = { config, ... }: {
    # Now config is available - this is the inner config (nixos config)
    services.foo.enable = config.services.bar.enable;
  };
}
```

**Why**: The outer config is the flake-parts config (contains flake.modules namespace).
The inner config is the nixos/darwin/home-manager config (contains services, programs, etc.).
Immediate attrsets can't reference the inner config because it doesn't exist until module evaluation.

---

### Anti-pattern 2: specialArgs for module dependencies

**Violation**:
```nix
# In machine config
nixosSystem {
  specialArgs = {
    sharedServices = import ../shared-services.nix;
  };
  modules = [
    ({ sharedServices, ... }: {
      imports = sharedServices.requiredModules;
      services.foo = sharedServices.fooConfig;
    })
  ];
}
```

**Fix**:
```nix
# In modules/nixos/shared-services.nix
{ config, ... }:
{
  flake.modules.nixos.shared-services = { config, lib, ... }: {
    options.services.foo = lib.mkOption { ... };
    config.services.foo = { ... };
  };
}

# In machine config
nixosSystem {
  modules = [
    ({ config, ... }: {
      imports = [ config.flake.modules.nixos.shared-services ];
    })
  ];
}
```

**Why**: Explicit imports make dependencies visible and enable better tooling (dependency graphs, dead code detection, documentation).
specialArgs creates hidden global context that's hard to track.

---

### Anti-pattern 3: Stringly-typed booleans

**Violation**:
```nix
options.custom.feature.enable = lib.mkOption {
  type = lib.types.str;
  default = "false";
  description = "Enable feature (true or false)";
};

config = lib.mkIf (config.custom.feature.enable == "true") {
  services.foo.enable = true;
};
```

**Fix**:
```nix
options.custom.feature.enable = lib.mkOption {
  type = lib.types.bool;
  default = false;
  description = "Enable feature";
};

config = lib.mkIf config.custom.feature.enable {
  services.foo.enable = true;
};
```

**Why**: Proper types provide runtime validation (catches typos like "ture"), clearer documentation, and eliminate string comparison logic.

---

### Anti-pattern 4: Unnecessary mkForce

**Violation**:
```nix
# modules/base.nix
{ lib, ... }: {
  services.openssh.enable = lib.mkDefault true;
}

# modules/hardening.nix
{ lib, ... }: {
  # This prevents users from disabling ssh if they want
  services.openssh.enable = lib.mkForce true;
}
```

**Fix**:
```nix
# modules/base.nix
{ lib, ... }: {
  services.openssh.enable = lib.mkDefault true;
}

# modules/hardening.nix
{ ... }: {
  # Let the default stand, but add hardening config
  services.openssh.settings = {
    PasswordAuthentication = false;
    PermitRootLogin = "no";
  };
}
```

**Why**: mkForce creates an override that can't be overridden (priority 50 beats user configs at priority 100).
Only use when you genuinely want to prevent overrides (e.g., security policy enforcement), and document why.

---

### Anti-pattern 5: Plain if instead of mkIf

**Violation**:
```nix
{ config, ... }: {
  services.nginx.enable =
    if config.services.web.enable
    then true
    else false;
}
```

**Problem**: This always defines `services.nginx.enable` (to either true or false).
If another module also defines it, you get a merge conflict.

**Fix**:
```nix
{ config, lib, ... }: {
  services.nginx.enable = lib.mkIf config.services.web.enable true;
}
```

**Why**: `mkIf false` removes the definition entirely (contributes $\bot_{\text{undef}}$ to merge), allowing other modules' definitions to stand.
Plain `if` expressions always produce a value, which participates in merging.

---

## Validation approach

### Static analysis

Automated checks for common violations:

```bash
# 1. Find immediate attrset exports (manual review needed)
rg 'flake\.modules\.[^=]+ = \{' --glob '*.nix' --glob '!*.md'

# 2. Find non-standard specialArgs usage
rg '\{ [^}]*\b(?!config|lib|pkgs|inputs|options|modulesPath|system)\w+,' modules/

# 3. Find stringly-typed enable options
rg 'enable.*type\s*=\s*types\.str' modules/

# 4. Find mkForce usage (manual review for justification)
rg 'mkForce' modules/

# 5. Find unstructured attrs types
rg 'type\s*=\s*types\.attrs' modules/
```

### Build testing

Runtime checks via Nix evaluation:

```bash
# Check for fixpoint failures (infinite recursion)
nix flake check

# Build all configurations
nix build .#darwinConfigurations.stibnite.system
nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel

# Evaluate specific options (catches type errors)
nix eval .#nixosConfigurations.cinnabar.config.services.openssh.enable
```

### Review checklist

Manual inspection for semantic issues:

1. **Module structure**
   - [ ] Exports use deferred function syntax
   - [ ] No config references outside function bodies
   - [ ] Imports list is at module top level

2. **Dependencies**
   - [ ] All dependencies are explicit via imports
   - [ ] specialArgs usage limited to standard arguments
   - [ ] No hidden global context

3. **Options**
   - [ ] Types are specific and appropriate
   - [ ] Descriptions are clear and accurate
   - [ ] Defaults use mkDefault or mkOptionDefault

4. **Merging**
   - [ ] mkDefault used for overridable module defaults
   - [ ] mkForce used only when necessary (with comment explaining why)
   - [ ] mkIf used for conditional definitions
   - [ ] mkMerge used intentionally for multiple sources

5. **Fixpoint safety**
   - [ ] No strict circular dependencies
   - [ ] Conditional logic uses mkIf, not plain if
   - [ ] Base cases established for recursive references

### Documentation validation

Check that modules are self-documenting:

```bash
# Generate documentation to verify types are clear
nix build .#nixosConfigurations.cinnabar.config.system.build.manual

# Check for missing descriptions
rg 'mkOption' modules/ -A 5 | rg -v 'description\s*='
```

## Severity levels

### HIGH (breaks fixpoint semantics)

Violations that cause evaluation failures or incorrect behavior:
- Criterion 1: Immediate module exports with config references
- Criterion 2: Circular dependencies causing infinite recursion

**Action**: Fix immediately before merging.

### MEDIUM (maintainability, unexpected behavior)

Violations that work but cause confusion or surprising results:
- Criterion 3: Implicit specialArgs dependencies
- Criterion 5: Unintentional merge semantics (mkForce without reason, plain if instead of mkIf)

**Action**: Fix during code review or refactoring.

### LOW (style, documentation)

Violations that are technically correct but suboptimal:
- Criterion 4: Stringly-typed options

**Action**: Fix when touching related code, not necessarily immediately.

## Summary

Algebraic purity criteria ensure Nix configurations respect the module system's mathematical foundations:

1. **Deferred evaluation** preserves Kleisli category morphisms
2. **Fixpoint safety** ensures Scott-continuous functions converge
3. **Explicit imports** maintain categorical composition and referential transparency
4. **Type correctness** constrains configuration lattices appropriately
5. **Merge awareness** uses join-semilattice operations intentionally

These criteria are not arbitrary style preferences—they reflect the domain-theoretic semantics that make the module system reliable and compositional.
Violations risk breaking the algebraic properties that enable independent module reasoning and predictable merge behavior.

Use the audit checklist and validation approach to verify configurations meet these criteria, prioritizing HIGH severity violations that break evaluation over LOW severity style issues.
