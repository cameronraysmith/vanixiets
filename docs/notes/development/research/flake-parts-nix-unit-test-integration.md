# Testing Nix Flake-Parts Based Repositories: Deep Technical Research

**Date:** 2025-11-05
**Purpose:** Understand how to construct and utilize tests (nix flake checks, nix-unit) for flake-parts-based repositories
**Target Application:** test-clan repository (based on clan-infra patterns)
**Research Status:** In Progress

---

## Executive Summary

[TO BE COMPLETED - Summary of key findings and recommended patterns]

---

## 1. Research Objectives

### Primary Goal

Understand how to construct and utilize tests in flake-parts-based repositories to enable:
1. Identifying reasonable and useful test cases worth testing in Nix
2. Writing correct nix flake check outputs
3. Creating test files that validate flake properties
4. Writing nix-unit tests that integrate with flake-parts module system

### Core Challenge

Testing flake-parts-based repositories is highly non-trivial due to:
- Complex module evaluation order
- Lazy evaluation semantics
- Circular dependency risks when tests need access to complete flake outputs
- perSystem output transposition to flake-level outputs

### Target Repository Context

- **Primary:** `~/projects/nix-workspace/test-clan`
- **Base patterns:** `~/projects/nix-workspace/clan-infra`
- **Available source code:**
  - `~/projects/nix-workspace/flake-parts/` (complete source)
  - `~/projects/nix-workspace/nix-unit/` (complete source)

### Failed Implementation Analysis

Branch `phase-0-tests` in test-clan contains preserved attempts that failed due to insufficient understanding of flake-parts architecture.

---

## 2. Flake-Parts Module System Architecture

### 2.1 Module System Overview

flake-parts provides a module system for organizing Nix flakes into composable, per-system configurations.
The core innovation is the `perSystem` abstraction that transposes system-specific definitions into flake outputs.

**Key Components:**
- `perSystem` module: Defines per-system configuration (`perSystem.nix`)
- `transposition` system: Bidirectional mapping between `perSystem.<attr>` and `flake.<attr>.<system>` (`transposition.nix`)
- `mkTransposedPerSystemModule`: Helper for creating options that exist in both contexts (`lib.nix`)
- `withSystem`: Escape hatch for accessing perSystem context from flake level (`withSystem.nix`)

**Source References:**
- `/Users/crs58/projects/nix-workspace/flake-parts/modules/perSystem.nix`
- `/Users/crs58/projects/nix-workspace/flake-parts/modules/transposition.nix`
- `/Users/crs58/projects/nix-workspace/flake-parts/lib.nix`

### 2.2 perSystem Module Deep Dive

**Location:** `~/projects/nix-workspace/flake-parts/modules/perSystem.nix`

The perSystem module creates a per-system evaluation context with these characteristics:

**Module Arguments Available in perSystem:**
- `config`: perSystem module config (NOT top-level flake config)
- `pkgs`: nixpkgs for the current system
- `system`: current system string (e.g., "x86_64-linux")
- `self'`: system-specific outputs from the flake itself (via `perInput`)
- `inputs'`: system-specific outputs from flake inputs (via `perInput`)
- `lib`: nixpkgs lib

**Module Arguments NOT Available in perSystem:**
These throw custom error messages if accessed (lines 123-127):
- `self`: Top-level flake (use `self'` instead for system-specific access)
- `inputs`: Top-level inputs (use `inputs'` instead)
- `getSystem`, `withSystem`, `moduleWithSystem`: Top-level module arguments

**Critical Constraint:**
```nix
# From perSystem.nix line 138
apply = modules: system:
  (lib.evalModules {
    inherit modules;
    prefix = [ "perSystem" system ];
    specialArgs = { inherit system; };
    class = "perSystem";
  }).config;
```

perSystem modules are evaluated PER SYSTEM as a SEPARATE module evaluation.
This evaluation happens BEFORE the complete flake outputs are assembled.

**Accessing Top-Level Config from perSystem:**
The error messages show the pattern (lines 31-40):
```nix
top@{ config, lib, self, ... }: {
  perSystem = { config, self', ... }: {
    # in scope here:
    #  - self (from top)
    #  - self' (from perSystem)
    #  - config (perSystem config)
    #  - top.config (flake-level config via top@ pattern)
  };
}
```

### 2.3 Module Evaluation Order and Lazy Evaluation Semantics

**Evaluation Flow:**
1. Top-level flake module evaluation starts
2. For each system in `systems`, perSystem is evaluated independently
3. perSystem evaluations produce per-system configs
4. Transposition system collects perSystem outputs into flake-level outputs
5. Complete flake outputs are assembled

**Key from perSystem.nix lines 148-149:**
```nix
config = {
  allSystems = genAttrs config.systems config.perSystem;
  # ...
};
```

`allSystems` maps each system to its perSystem evaluation result.

**Lazy Evaluation:**
flake-parts uses lazy attribute sets (`types.lazyAttrsOf`) extensively to avoid infinite recursion.
The `checks` module (line 14) uses `types.lazyAttrsOf types.package` which means checks are not evaluated until accessed.

**Transposition Mechanism (from transposition.nix lines 99-110):**
```nix
config = {
  flake =
    lib.mapAttrs
      (attrName: attrConfig:
        mapAttrs
          (system: v: v.${attrName} or (abort "..."))
          config.allSystems
      )
      config.transposition;
  # ...
};
```

For each registered transposition (like `checks`), it:
1. Takes `config.allSystems` (map of system → perSystem config)
2. For each system, extracts `perSystemConfig.${attrName}`
3. Creates `flake.${attrName}.${system}` from that value

### 2.4 Circular Dependency Prevention Patterns

**The Circular Dependency Problem:**

When defining checks in perSystem that need access to complete flake outputs:
```nix
perSystem = { config, ... }: {
  checks.my-test = import ./test.nix {
    # ❌ CIRCULAR: config.flake is the RESULT of perSystem evaluation
    self = config.flake;
    # ❌ CIRCULAR: inputs.self is what we're currently building
    self = inputs.self;
  };
};
```

**Why This Fails:**
1. perSystem evaluation must complete to produce flake outputs
2. `config.flake` is the assembled result of all perSystem evaluations
3. Accessing `config.flake` from within perSystem creates infinite recursion
4. `inputs.self` refers to the flake being evaluated, same problem

**Available Patterns to Avoid Circularity:**

**Pattern 1: Use `self'` for system-specific access**
```nix
perSystem = { config, self', ... }: {
  checks.my-test = import ./test.nix {
    # ✅ OK: self' provides access to THIS system's outputs
    inherit (self') packages apps;
  };
};
```

**Pattern 2: Use top-level module with `top@` pattern**
```nix
top@{ config, lib, ... }: {
  perSystem = { config, ... }: {
    checks.my-test = import ./test.nix {
      # ✅ OK: top.config.flake is accessible via outer scope
      flakeOutputs = top.config.flake;
    };
  };
}
```

**Pattern 3: Use `withSystem` at flake level**
```nix
{ withSystem, ... }: {
  systems = [ "x86_64-linux" ];
  perSystem = { ... }: {
    # Regular perSystem stuff
  };
  flake.checks = {
    x86_64-linux = withSystem "x86_64-linux" ({ config, ... }): {
      # ✅ OK: Running at flake level, full access to flake outputs
      my-test = import ./test.nix {
        inherit config; # Has access to perSystem config
        flake = config.flake; # Would have access if needed
      };
    };
  };
}
```

**Pattern 4: Define checks at flake level directly**
```nix
{
  perSystem = { ... }: {
    # Regular perSystem stuff
  };
  flake.checks.x86_64-linux.my-test = pkgs.runCommand "test" {} "...";
}
```

**The Core Principle:**
Tests that need access to complete flake outputs MUST be defined at the flake level (not in perSystem), or use `withSystem` to access perSystem context FROM the flake level.

---

## 3. Nix-Unit Test Framework Integration

### 3.1 Nix-Unit Design and Architecture

[TO BE RESEARCHED - Study ~/projects/nix-workspace/nix-unit]

### 3.2 Nix-Unit Test Structure

[TO BE RESEARCHED]

Key questions:
- expr/expected pattern vs pkgs.runCommand wrapper?
- Test module structure and interfaces?
- How do nix-unit tests integrate with flake checks?

### 3.3 Best Practices from nix-unit/tests/

[TO BE RESEARCHED - Analyze nix-unit's own test examples]

---

## 4. Working Reference Implementations

### 4.1 Flake-Parts Projects with Test Suites

[TO BE RESEARCHED - Search for working examples]

### 4.2 Terranix FlakeModule Analysis

[TO BE RESEARCHED - How does terranix expose perSystem.terranix outputs?]

test-clan uses terranix, so understanding its flakeModule is critical.

### 4.3 Proven Patterns for Test Check Integration

[TO BE RESEARCHED]

---

## 5. Failed Attempt Forensics: phase-0-tests Branch

### 5.1 Commit Analysis (f0aa5e9 through f405a6a)

[TO BE RESEARCHED - Review test-clan phase-0-tests branch]

### 5.2 What Was Attempted and Why Each Failed

#### Attempt 1: Using config.flake in perSystem
[TO BE ANALYZED]
- What was tried?
- Why did it fail?
- What constraint was discovered?

#### Attempt 2: Using inputs.self
[TO BE ANALYZED]

#### Attempt 3: Post-hoc flake merging
[TO BE ANALYZED]

### 5.3 Architectural Constraints Discovered

[TO BE SYNTHESIZED from failure analysis]

---

## 6. Correct Implementation Pattern

### 6.1 The RIGHT Way to Define Checks Needing Flake Output Access

[TO BE DOCUMENTED - working code patterns with explanations]

### 6.2 Module Structure and File Organization

[TO BE DOCUMENTED]

### 6.3 Integration Points

[TO BE DOCUMENTED]

### 6.4 Pitfalls to Avoid (Learned from phase-0-tests)

[TO BE DOCUMENTED]

---

## 7. What's Worth Testing in Nix Flake-Parts Repositories

### 7.1 Test Categories

[TO BE DOCUMENTED]

Categories to consider:
- Unit tests for individual Nix functions
- Integration tests for module interactions
- Property tests for flake outputs (types, structure)
- Smoke tests for builds/deployments
- Regression tests

### 7.2 Test-Clan Specific Test Cases

[TO BE IDENTIFIED based on repository analysis]

---

## 8. Implementation Guide for test-clan

### 8.1 Recommended Test Structure

[TO BE DOCUMENTED]

### 8.2 Working Code Examples

[TO BE PROVIDED - actual working code, not pseudo-code]

### 8.3 Validation Criteria

[TO BE DOCUMENTED]

How to verify tests actually run and work correctly?

---

## 9. References and Source Analysis

### 9.1 Flake-Parts Source Code References

[TO BE POPULATED with file:line references]

### 9.2 Nix-Unit Source Code References

[TO BE POPULATED]

### 9.3 Working Examples Found

[TO BE POPULATED]

---

## 10. Validation and Next Steps

### 10.1 Validation Checklist

[TO BE CREATED]

Steps to verify the implementation pattern works:
- [ ] Tests can be defined without circular dependencies
- [ ] Tests have access to necessary flake outputs
- [ ] `nix flake check` runs tests successfully
- [ ] nix-unit tests integrate correctly
- [ ] Tests are maintainable and clear

### 10.2 Story 1.6 Revision Requirements

[TO BE DOCUMENTED]

What needs to change in Story 1.6 based on this research?

---

## Research Methodology

1. **Source Code Analysis:** Direct analysis of flake-parts and nix-unit source code
2. **Failed Attempt Forensics:** Detailed review of phase-0-tests branch commits
3. **Working Example Discovery:** Search for proven patterns in the ecosystem
4. **Pattern Synthesis:** Combine findings into correct implementation approach
5. **Validation:** Verify patterns work for test-clan's specific structure

---

**Document Status:** Initial Structure Created - Research In Progress
**Last Updated:** 2025-11-05
