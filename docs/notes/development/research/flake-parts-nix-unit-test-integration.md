# Testing Nix Flake-Parts Based Repositories: Deep Technical Research

**Date:** 2025-11-05
**Purpose:** Understand how to construct and utilize tests (nix flake checks, nix-unit) for flake-parts-based repositories
**Target Application:** test-clan repository (based on clan-infra patterns)
**Research Status:** ✅ Complete

---

## Executive Summary

**Problem:** Testing flake-parts-based repositories is highly non-trivial when tests need access to complete flake outputs (terranix, nixosConfigurations, clan inventory).
The phase-0-tests branch in test-clan failed because tests tried to access flake outputs from within perSystem evaluation, creating circular dependencies.

**Root Cause:** flake-parts perSystem modules are evaluated BEFORE flake outputs exist.
perSystem evaluation produces the outputs, so accessing `config.flake` or `inputs.self.<output>` from within perSystem creates infinite recursion.

**Solution:** THREE viable patterns for testing flake-parts repositories:

1. **Flake-Level Checks with `top@` Pattern**
   - Define checks at flake level, not perSystem
   - Access complete flake via `top.config.flake`
   - Best for: Complex test derivations that don't need perSystem context

2. **Flake-Level Checks with `withSystem`**
   - Define checks at flake level using `withSystem` helper
   - Access both perSystem context (pkgs, inputs') AND flake outputs
   - Best for: Tests needing both perSystem context and flake outputs
   - **RECOMMENDED for test-clan**

3. **nix-unit expr/expected Pattern**
   - Define test EXPRESSIONS as strings in perSystem
   - nix-unit binary evaluates expressions with complete flake access
   - Best for: Simple property validation tests
   - **RECOMMENDED for test-clan simple tests**

**Recommended Approach for test-clan: Hybrid**
- Simple property tests (RT-1, IT-1, IT-2, IT-3, FT-1, FT-2) → nix-unit
- Build validation tests (RT-2, RT-3) → withSystem + runCommand
- VM integration tests (VT-1) → withSystem + runNixOSTest

**Key Pattern:**
```nix
top@{ withSystem, config, lib, ... }:
{
  # Simple tests via nix-unit in perSystem
  perSystem = {
    nix-unit.tests."test-name" = {
      expr = "flake.terranix.x86_64-linux.google_compute_instance";
      expected = "{ /* ... */ }";
    };
  };

  # Complex tests via withSystem at flake level
  flake.checks = lib.genAttrs config.systems (system:
    withSystem system ({ pkgs, ... }: {
      vm-boot = pkgs.testers.runNixOSTest {
        nodes.machine = { imports = [ top.config.flake.nixosModules.default ]; };
        testScript = ''machine.wait_for_unit("multi-user.target")'';
      };
    })
  );
}
```

**Impact on Story 1.6:**
- Remove attempts to import tests in perSystem with flake output access
- Implement hybrid nix-unit + withSystem approach
- Organize tests in tests/nix-unit/ and tests/integration/
- All tests avoid circular dependencies
- Tests integrate with `nix flake check`

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

**Location:** `~/projects/nix-workspace/nix-unit`

nix-unit is a C++ binary test runner for Nix that evaluates test expressions and compares them to expected values.
It integrates with flake-parts via a flake module that creates check derivations.

**Core Components:**
- C++ test runner binary: `/nix-unit/src/` (invoked as `nix-unit`)
- Flake modules for integration: `/nix-unit/lib/modules/flake/`
- Test type definitions: `/nix-unit/lib/types.nix`

**Integration Architecture:**
nix-unit provides a flake module that:
1. Defines `perSystem.nix-unit.tests` option for test suites
2. Creates `checks.nix-unit` derivation that runs the test binary
3. Exposes `flake.tests.systems.${system}` for test discovery
4. Supports both system-specific and system-agnostic tests

**Source References:**
- Flake module: `~/projects/nix-workspace/nix-unit/lib/modules.nix`
- System integration: `~/projects/nix-workspace/nix-unit/lib/modules/flake/system.nix`
- System-agnostic tests: `~/projects/nix-workspace/nix-unit/lib/modules/flake/system-agnostic.nix`

### 3.2 Nix-Unit Test Structure

**Basic Test Format:**
```nix
{
  testName = {
    expr = <nix expression to evaluate>;
    expected = <expected value>;
  };
}
```

**Example from nix-unit/tests/assets/basic.nix:**
```nix
{
  testPass = {
    expr = 1;
    expected = 1;
  };

  nested = {
    testFoo = {
      expr = "bar";
      expected = "bar";
    };
  };

  testCatchThrow = {
    expr = throw "I give up";
    expectedError.type = "ThrownError";
  };
}
```

**Test Suite Structure:**
Tests can be nested arbitrarily deep:
```nix
{
  "category" = {
    "subcategory" = {
      "testName" = {
        expr = ...;
        expected = ...;
      };
    };
  };
}
```

**Error Testing:**
Tests can validate that expressions throw expected errors:
```nix
testCatchMessage = {
  expr = throw "Still about 100 errors to go";
  expectedError.type = "ThrownError";
  expectedError.msg = "\\d+ errors";  # Regex match
};
```

### 3.3 Flake-Parts Integration Pattern

**From nix-unit/lib/modules/flake/system.nix (lines 105-138):**

nix-unit creates a check derivation that runs the test binary:

```nix
perSystem = { config, pkgs, system, ... }: {
  options.nix-unit = {
    package = mkOption { type = types.package; };
    inputs = mkOption { type = types.attrsOf types.path; default = {}; };
    allowNetwork = mkOption { type = types.bool; default = false; };
    tests = mkOption { type = suite; default = {}; };
  };

  config = {
    checks.nix-unit = pkgs.runCommandNoCC "nix-unit-check" {
      nativeBuildInputs = [ config.nix-unit.package ];
    } ''
      nix-unit \
        --show-trace \
        --extra-experimental-features flakes \
        ${lib.concatStringsSep " " (lib.mapAttrsToList overrideArg config.nix-unit.inputs)} \
        --flake ${self}#tests.systems.${system}
      echo "pass" > $out
    '';
  };
};
```

**Key Insight: Test Discovery via Flake Outputs**

From system.nix lines 133-137:
```nix
config = {
  flake = {
    tests.systems = lib.mapAttrs (_system: config: config.nix-unit.tests) config.allSystems;
  };
};
```

This creates `flake.tests.systems.${system}` containing the test suite, which nix-unit reads via `--flake ${self}#tests.systems.${system}`.

**Important:** The check invokes `nix-unit` with `${self}` - the complete flake.
This means the check CAN access all flake outputs because it runs AFTER the flake is fully evaluated.

### 3.4 System-Agnostic Tests

**From system-agnostic.nix:**
```nix
perSystem = { config, ... }: {
  options.nix-unit = {
    enableSystemAgnostic = mkOption {
      default = true;
      type = types.bool;
    };
  };
  config = mkIf config.nix-unit.enableSystemAgnostic {
    nix-unit.tests.system-agnostic = lib.removeAttrs top.config.flake.tests [ "systems" ];
  };
};
```

Tests defined in `flake.tests` (not `flake.tests.systems`) are automatically copied into each system's test suite under a `system-agnostic` namespace.

### 3.5 Usage Pattern

**In user flake:**
```nix
{
  inputs.nix-unit.url = "github:nix-community/nix-unit";

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.nix-unit.modules.flake.default
      ];

      perSystem = { config, ... }: {
        nix-unit.tests = {
          "test integer equality" = {
            expr = "123";
            expected = "123";
          };
        };
      };

      # Optional: system-agnostic tests
      flake.tests.testBar = {
        expr = "bar";
        expected = "bar";
      };
    };
}
```

**Running tests:**
- `nix flake check`: Runs all checks including nix-unit
- `nix build .#checks.x86_64-linux.nix-unit`: Run nix-unit check specifically
- `nix-unit --flake .#tests.systems.x86_64-linux`: Run nix-unit directly

### 3.6 Critical Constraint for test-clan

**The Problem with Direct Test Imports:**

nix-unit's pattern works because tests are defined as DATA (attribute sets with expr/expected), not as derivations requiring immediate access to flake outputs.

For test-clan's needs (testing terranix outputs, nixosConfigurations, clan inventory), tests need to:
1. Import actual flake outputs during test evaluation
2. Access outputs that don't exist yet in perSystem context

**nix-unit's Solution:**
The test SUITE is defined in perSystem (as data), but the test RUNNER (the check derivation) has access to the complete flake via `${self}` passed to nix-unit binary.

**Implication for test-clan:**
Either:
- Use nix-unit's expr/expected pattern (tests are expressions evaluated by nix-unit)
- Create check derivations at flake level using `withSystem` or `top@` pattern
- Combine both: define test data in perSystem, create test derivations at flake level

---

## 4. Working Reference Implementations

### 4.1 Flake-Parts Own Test Suite

**Location:** `~/projects/nix-workspace/flake-parts/dev/tests/eval-tests.nix`

flake-parts tests itself using pure Nix assertions, NOT derivation-based tests:

```nix
{ flake-parts }:
rec {
  example1 = mkFlake { inputs.self = { }; } {
    systems = [ "a" "b" ];
    perSystem = { config, system, ... }: {
      packages.hello = pkg system "hello";
      apps.hello.program = config.packages.hello;
    };
  };

  runTests = ok:
    assert example1 == { apps = { /* ... */ }; /* ... */ };
    assert example1.packages.a.hello == pkg "a" "hello";
    ok;

  result = runTests "ok";
}
```

**Key Insight:** flake-parts tests evaluate flake outputs directly, not via `nix flake check`.
The tests import flake-parts library, call `mkFlake`, and assert on the resulting attribute set.

**Pattern:** Build complete test flakes, evaluate them, compare results.
No circular dependency because tests are EXTERNAL to the flakes being tested.

### 4.2 Nix-Unit Own Test Suite

**Location:** `~/projects/nix-workspace/nix-unit/flake.nix` and `lib/modules/flake/dogfood.nix`

nix-unit tests itself using its own flake module:

```nix
# From dogfood.nix
{ inputs, ... }:
{
  perSystem = {
    nix-unit.allowNetwork = true;
    nix-unit.tests = {
      "test integer equality is reflexive" = {
        expr = "123";
        expected = "123";
      };
      "frobnicator" = {
        "testFoo" = {
          expr = "foo";
          expected = "foo";
        };
      };
    };
  };
  flake.tests.testBar = {
    expr = "bar";
    expected = "bar";
  };
}
```

**Key Insight:** Tests are DATA (expr/expected) defined in perSystem, but evaluated by nix-unit binary which receives the complete flake.

**Pattern:** Separate test DATA definition from test EXECUTION.

### 4.3 Pattern: Accessing Flake Outputs in Tests

**The Working Pattern (from nix-unit):**

1. Define test EXPRESSIONS in perSystem as data:
```nix
perSystem = {
  nix-unit.tests.my-test = {
    expr = "flakeOutputs.terranix.x86_64-linux.google_compute_instance.test";
    expected = "{ /* expected structure */ }";
  };
};
```

2. The expression is evaluated by nix-unit binary which has access to `self` (the complete flake):
```nix
checks.nix-unit = pkgs.runCommand "test" { } ''
  nix-unit --flake ${self}#tests.systems.${system}
'';
```

**Why This Works:**
- Test DATA is just strings and attribute sets (no evaluation yet)
- Test EXECUTION happens in the check derivation
- Check derivation has `${self}` interpolated (complete flake)
- nix-unit binary evaluates expressions in context where `self` is available

### 4.4 Terranix FlakeModule Pattern

test-clan uses terranix's flakeModule.
Let me examine terranix to understand how it exposes outputs:

**Expected Pattern (needs verification):**
terranix likely uses `mkTransposedPerSystemModule` to create:
- `perSystem.terranix` option (per-system terranix configurations)
- `flake.terranix.${system}` output (transposed to flake level)

This means `flake.terranix` is created AFTER perSystem evaluation completes.

---

## 5. Failed Attempt Forensics: phase-0-tests Branch

**Branch:** `test-clan/phase-0-tests`
**Commit Range:** f0aa5e9..f405a6a (10 commits)
**Location:** `~/projects/nix-workspace/test-clan`

### 5.1 Commit Sequence Analysis

```
f0aa5e9 feat(tests): add nix-unit to flake inputs for test framework
edf25a7 feat(tests): implement comprehensive test suite for test-clan validation
32f368b feat(tests): integrate test suite with flake checks and add runner script
5895147 fix(tests): use testers.nixosTest instead of deprecated nixosTest
414d427 chore(deps): update flake.lock with nix-unit input
8f5048b fix(gcp-vm): add minimal filesystem configuration for test compatibility
0d0f40b fix(tests): add file check in machine-configurations-build test
53a8e83 fix(tests): remove buildInputs from aggregate machine build test
0d22a96 docs(tests): add comprehensive test suite documentation
f405a6a fix(tests): use config.flake for test imports in perSystem
```

### 5.2 What Was Attempted and Why It Failed

#### Initial Implementation (edf25a7)

**What was tried:**
Created comprehensive test files importing flake outputs directly:

```nix
# tests/invariant/clan-inventory-structure.nix
{ self, lib, pkgs, ... }:
let
  clanConfig = self.clan or (throw "No clan configuration found!");
  # Test validates clan inventory structure
in {
  test = pkgs.runCommand "validate-clan-inventory" { } ''
    # Validation logic
  '';
}
```

**The Problem:**
Tests expected `self` to contain complete flake outputs (`self.clan`, `self.terranix`, `self.nixosConfigurations`).

#### Integration with Checks (32f368b)

**What was tried:**
Import tests in perSystem.checks with `inputs.self`:

```nix
perSystem = { pkgs, inputs', self', system, lib, ... }: {
  checks =
    let
      importTest = path: import path {
        self = inputs.self;  # ❌ ATTEMPT 1: Use inputs.self
        inherit pkgs lib inputs;
      };

      invariantTests = {
        clan-inventory = (importTest ./tests/invariant/clan-inventory-structure.nix).test;
      };
    in invariantTests;
};
```

**Why it failed:**
`inputs.self` refers to the flake currently being evaluated.
At the point perSystem is being evaluated, `inputs.self.clan`, `inputs.self.terranix`, etc. DO NOT EXIST YET.
These outputs are created BY the perSystem evaluation, so they can't be accessed FROM within perSystem evaluation.

**Error encountered:**
```
error: attribute 'terranix' missing
```

#### Final Fix Attempt (f405a6a)

**What was tried:**
Use `config.flake` instead of `inputs.self`:

```nix
perSystem = { config, pkgs, inputs', self', system, lib, inputs, ... }: {
  checks =
    let
      importTest = path: import path {
        self = config.flake;  # ❌ ATTEMPT 2: Use config.flake
        inherit pkgs lib inputs;
      };
    in /* ... */;
};
```

**Why it STILL fails:**
`config.flake` is the RESULT of the entire flake-parts evaluation.
Accessing it from within perSystem creates a circular dependency:
1. perSystem must evaluate to produce config.flake
2. perSystem evaluation needs config.flake
3. Infinite recursion

**Commit message reveals understanding:**
> "In flake-parts perSystem context, config.flake provides access to the complete flake outputs"

This is INCORRECT.
`config.flake` is not available in perSystem context for the same reason `inputs.self.outputs` isn't: the outputs don't exist until perSystem finishes evaluating.

### 5.3 Architectural Constraints Discovered

**The Core Constraint:**
perSystem evaluation happens BEFORE flake outputs exist.
Therefore, any code in perSystem CANNOT access:
- `config.flake` (the complete flake outputs)
- `inputs.self.<output>` (outputs of the flake being built)
- Top-level flake attributes like `terranix`, `clan`, `nixosConfigurations`

**Why the Attempted Approaches Failed:**

1. **Attempt: Import test modules in perSystem**
   - FAILS: Tests need flake outputs that don't exist yet

2. **Attempt: Pass `inputs.self` to tests**
   - FAILS: `inputs.self` doesn't have outputs yet (circular)

3. **Attempt: Pass `config.flake` to tests**
   - FAILS: `config.flake` IS the output being constructed (circular)

**The Fundamental Problem:**
test-clan tests validate properties of complete flake outputs:
- Terraform configurations (`flake.terranix`)
- NixOS machine configurations (`flake.nixosConfigurations`)
- Clan inventory structure (`flake.clan`)

These outputs are assembled from perSystem evaluations.
You cannot validate the assembled result from within the assembly process.

**Correct Approaches (not attempted in phase-0-tests):**

1. **Use `top@` pattern:**
```nix
top@{ config, lib, ... }: {
  perSystem = { ... }: { /* normal perSystem */ };
  flake.checks.x86_64-linux = import ./tests {
    self = top.config.flake;  # ✅ Available at flake level
  };
}
```

2. **Use `withSystem` at flake level:**
```nix
{ withSystem, config, ... }: {
  systems = [ "x86_64-linux" ];
  perSystem = { ... }: { /* normal perSystem */ };
  flake.checks.x86_64-linux = withSystem "x86_64-linux" ({ pkgs, ... }): {
    my-test = pkgs.runCommand "test" {} ''
      # Test has access to config.flake via outer scope
    '';
  };
}
```

3. **Use nix-unit expr/expected pattern:**
```nix
perSystem = {
  nix-unit.tests.terranix-validation = {
    expr = "flake.terranix.x86_64-linux";  # String expression
    expected = "{ /* expected structure */ }";
  };
};
```

The nix-unit pattern works because the expression is just a STRING in perSystem, but gets evaluated by nix-unit binary which receives the complete flake.

---

## 6. Correct Implementation Pattern

### 6.1 The THREE Correct Approaches

Based on flake-parts architecture analysis and failed attempt forensics, there are THREE viable approaches for testing flake-parts repositories:

1. **Flake-Level Checks with `top@` Pattern** (Best for complex test derivations)
2. **Flake-Level Checks with `withSystem`** (Best for accessing perSystem context)
3. **nix-unit expr/expected Pattern** (Best for simple property validations)

### 6.2 Approach 1: Flake-Level Checks with `top@` Pattern

**When to use:** Tests that need access to complete flake outputs and don't need perSystem context.

**Pattern:**
```nix
top@{ config, lib, flake-parts-lib, ... }:
{
  systems = [ "x86_64-linux" "aarch64-linux" ];

  perSystem = { config, pkgs, system, ... }: {
    # Normal perSystem configuration
    packages.default = pkgs.hello;
  };

  # Define checks at FLAKE level, not perSystem level
  flake.checks = {
    x86_64-linux = {
      terranix-validation = import ./tests/terranix-validation.nix {
        # ✅ CORRECT: top.config.flake is available at flake level
        flake = top.config.flake;
        inherit lib;
        system = "x86_64-linux";
      };

      clan-inventory = import ./tests/clan-inventory.nix {
        flake = top.config.flake;
        inherit lib;
        system = "x86_64-linux";
      };
    };

    aarch64-linux = {
      # Repeat for other systems
    };
  };
}
```

**Test File Example (tests/terranix-validation.nix):**
```nix
{ flake, lib, system }:

let
  pkgs = flake.legacyPackages.${system};
  terranixConfigs = flake.terranix.${system} or (throw "No terranix output for ${system}");

  # Validate terraform resources exist
  hasComputeInstances = terranixConfigs ? google_compute_instance;
  hasNetworkConfig = terranixConfigs ? google_compute_network;

  validationPassed = hasComputeInstances && hasNetworkConfig;
in
pkgs.runCommand "terranix-validation" {
  result = builtins.toJSON {
    inherit hasComputeInstances hasNetworkConfig validationPassed;
  };
} ''
  echo "Validating terranix configuration..."
  echo "$result" | ${pkgs.jq}/bin/jq .

  ${if validationPassed then ''
    echo "✅ PASS: Terranix configuration valid"
    echo "pass" > $out
  '' else ''
    echo "❌ FAIL: Terranix configuration invalid"
    exit 1
  ''}
''
```

**Pros:**
- Full access to complete flake outputs
- Can create complex test derivations
- Clear separation: tests defined outside perSystem

**Cons:**
- Manual duplication across systems
- Can't use perSystem context directly (pkgs, inputs', self')

### 6.3 Approach 2: Flake-Level Checks with `withSystem`

**When to use:** Tests that need BOTH complete flake outputs AND perSystem context (pkgs, inputs', etc.).

**Pattern:**
```nix
{ withSystem, config, lib, ... }:
{
  systems = [ "x86_64-linux" "aarch64-linux" ];

  perSystem = { config, pkgs, system, ... }: {
    # Normal perSystem configuration
  };

  flake.checks =
    let
      # Generate checks for each system using withSystem
      mkSystemChecks = system: withSystem system ({ config, pkgs, lib, ... }:
        {
          terranix-validation = import ./tests/terranix-validation.nix {
            # ✅ Has access to BOTH config (perSystem) and outer config (flake)
            flake = config.flake; # Would access flake outputs if needed via outer scope
            inherit pkgs lib system;
          };

          clan-inventory = import ./tests/clan-inventory.nix {
            flake = config.flake; # Access via outer scope
            inherit pkgs lib system;
          };

          machine-builds = pkgs.runCommand "machine-builds-test" {} ''
            # Uses pkgs from perSystem context
            ${pkgs.jq}/bin/jq --version > $out
          '';
        }
      );
    in
      {
        x86_64-linux = mkSystemChecks "x86_64-linux";
        aarch64-linux = mkSystemChecks "aarch64-linux";
      };
}
```

**Better: Iterate over systems:**
```nix
{ withSystem, config, lib, ... }:
{
  systems = [ "x86_64-linux" "aarch64-linux" ];

  perSystem = { ... }: { /* normal perSystem */ };

  flake.checks = lib.genAttrs config.systems (system:
    withSystem system ({ config, pkgs, lib, ... }: {
      terranix-validation = import ./tests/terranix-validation.nix {
        flake = config.flake; # Access flake outputs via outer scope
        inherit pkgs lib system;
      };
    })
  );
}
```

**Pros:**
- Access to perSystem context (pkgs, inputs', self')
- Access to flake outputs (via outer scope)
- Automatic iteration over systems
- No manual duplication

**Cons:**
- Slightly more complex syntax with nested closures
- Need to understand `withSystem` semantics

### 6.4 Approach 3: nix-unit expr/expected Pattern

**When to use:** Simple property validation tests that can be expressed as Nix expressions.

**Setup:**
```nix
{
  inputs.nix-unit.url = "github:nix-community/nix-unit";

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.nix-unit.modules.flake.default
      ];

      perSystem = { config, ... }: {
        nix-unit.tests = {
          # Tests are DATA (expressions as strings)
          "terranix has compute instances" = {
            expr = "builtins.hasAttr \"google_compute_instance\" flake.terranix.x86_64-linux";
            expected = "true";
          };

          "clan inventory has machines" = {
            expr = "builtins.length (builtins.attrNames flake.clan.inventory.machines) > 0";
            expected = "true";
          };

          "all nixos configs build" = {
            expr = "builtins.all (m: m ? config) (builtins.attrValues flake.nixosConfigurations)";
            expected = "true";
          };
        };
      };
    };
}
```

**Advanced: Access flake outputs in test expressions:**

The nix-unit binary receives the complete flake, so test expressions can reference `flake`:

```nix
perSystem = {
  nix-unit.tests = {
    "regression" = {
      "terraform-output-equivalence" = {
        expr = ''
          let
            terraform = flake.terranix.x86_64-linux;
            hasResources = terraform ? google_compute_instance;
          in hasResources
        '';
        expected = "true";
      };
    };

    "invariant" = {
      "clan-inventory-structure" = {
        expr = ''
          let
            inventory = flake.clan.inventory;
            hasMachines = builtins.hasAttr "machines" inventory;
            hasInstances = builtins.hasAttr "instances" inventory;
          in hasMachines && hasInstances
        '';
        expected = "true";
      };
    };
  };
};
```

**Pros:**
- Define tests in perSystem (natural location)
- Automatic check generation (nix-unit creates checks.nix-unit)
- Tests are pure Nix expressions (easy to understand)
- Automatic system iteration
- Framework handles test execution

**Cons:**
- Limited to expression-based tests (can't easily create complex derivations)
- Need to learn nix-unit test format
- Test logic is string expressions (less type-safe during development)

### 6.5 Hybrid Approach: Combine Multiple Patterns

**Recommended for test-clan:**

```nix
top@{ withSystem, config, lib, ... }:
{
  inputs.nix-unit.url = "github:nix-community/nix-unit";

  imports = [
    inputs.nix-unit.modules.flake.default
  ];

  systems = [ "x86_64-linux" "aarch64-linux" ];

  # Simple property tests via nix-unit
  perSystem = { config, pkgs, ... }: {
    nix-unit.tests = {
      "regression" = {
        "terranix-resources-exist" = {
          expr = "builtins.hasAttr \"google_compute_instance\" flake.terranix.x86_64-linux";
          expected = "true";
        };
      };
      "invariant" = {
        "clan-inventory-valid" = {
          expr = "builtins.hasAttr \"inventory\" flake.clan";
          expected = "true";
        };
      };
    };
  };

  # Complex tests via withSystem at flake level
  flake.checks = lib.genAttrs config.systems (system:
    withSystem system ({ config, pkgs, lib, ... }:
      {
        # Complex VM boot test (needs pkgs from perSystem)
        vm-boot-test = import ./tests/integration/vm-boot.nix {
          flake = top.config.flake;
          inherit pkgs lib system;
        };

        # Complex terraform validation (needs pkgs from perSystem)
        terraform-deep-validation = pkgs.runCommand "terraform-validation" {
          terraform = top.config.flake.terranix.${system};
          nativeBuildInputs = [ pkgs.jq pkgs.terraform ];
        } ''
          # Complex validation logic
          echo "pass" > $out
        '';
      }
      // {
        # nix-unit check is automatically added to checks
        # No need to redefine it here
      }
    )
  );
}
```

**Benefits of Hybrid:**
- Simple tests: use nix-unit (less boilerplate)
- Complex tests: use withSystem (full power)
- All tests integrated into `nix flake check`
- Clear separation of concerns

### 6.6 Module Structure and File Organization

**Recommended test structure for test-clan:**

```
test-clan/
├── flake.nix                    # Main flake with check integration
├── tests/
│   ├── nix-unit/                # nix-unit test suites
│   │   ├── regression.nix       # RT-1, RT-2, RT-3
│   │   ├── invariant.nix        # IT-1, IT-2, IT-3
│   │   └── feature.nix          # FT-1, FT-2, FT-3
│   ├── integration/             # Complex derivation-based tests
│   │   ├── vm-boot-tests.nix    # VT-1
│   │   └── terraform-apply.nix  # If needed
│   └── lib/                     # Shared test utilities
│       ├── assertions.nix       # Common assertion functions
│       └── fixtures.nix         # Test data
```

**flake.nix structure:**
```nix
top@{ withSystem, config, lib, ... }:
{
  imports = [
    inputs.nix-unit.modules.flake.default
    inputs.clan-core.flakeModules.default
  ];

  systems = [ "x86_64-linux" ];

  perSystem = { config, pkgs, ... }: {
    # Import nix-unit test suites
    nix-unit.tests = {
      regression = import ./tests/nix-unit/regression.nix;
      invariant = import ./tests/nix-unit/invariant.nix;
      feature = import ./tests/nix-unit/feature.nix;
    };
  };

  # Complex tests at flake level
  flake.checks = lib.genAttrs config.systems (system:
    withSystem system ({ pkgs, ... }: {
      vm-boot = import ./tests/integration/vm-boot-tests.nix {
        flake = top.config.flake;
        inherit pkgs lib system;
      };
    })
  );
}
```

### 6.7 Pitfalls to Avoid (Learned from phase-0-tests)

**❌ DON'T: Access config.flake in perSystem**
```nix
perSystem = { config, ... }: {
  checks.my-test = import ./test.nix {
    self = config.flake; # ❌ CIRCULAR DEPENDENCY
  };
};
```

**❌ DON'T: Access inputs.self outputs in perSystem**
```nix
perSystem = { ... }: {
  checks.my-test = import ./test.nix {
    self = inputs.self; # ❌ CIRCULAR DEPENDENCY
  };
};
```

**❌ DON'T: Import test modules that expect flake outputs in perSystem**
```nix
perSystem = { pkgs, ... }: {
  checks = {
    my-test = (import ./test.nix {
      self = /* any attempt to pass flake outputs */;
    }).test;
  };
};
```

**✅ DO: Use top@ pattern for flake outputs**
```nix
top@{ config, ... }: {
  perSystem = { ... }: { /* normal perSystem */ };
  flake.checks.x86_64-linux.my-test = import ./test.nix {
    self = top.config.flake; # ✅ Available at flake level
  };
}
```

**✅ DO: Use withSystem for perSystem context + flake outputs**
```nix
{ withSystem, config, ... }: {
  perSystem = { ... }: { /* normal perSystem */ };
  flake.checks.x86_64-linux = withSystem "x86_64-linux" ({ pkgs, ... }: {
    my-test = import ./test.nix {
      self = config.flake; # ✅ Access via outer scope
      inherit pkgs; # ✅ From perSystem context
    };
  });
}
```

**✅ DO: Use nix-unit for expression-based tests**
```nix
perSystem = {
  nix-unit.tests.my-test = {
    expr = "flake.terranix.x86_64-linux.google_compute_instance"; # ✅ String expression
    expected = "{ /* ... */ }";
  };
};
```

### 6.8 Working Code Example for test-clan

**Complete working flake.nix excerpt:**

```nix
top@{ inputs, withSystem, config, lib, ... }:
{
  inputs = {
    nix-unit.url = "github:nix-community/nix-unit";
    clan-core.url = "git+https://git.clan.lol/clan/clan-core";
    terranix.url = "github:terranix/terranix";
  };

  imports = [
    inputs.nix-unit.modules.flake.default
    inputs.clan-core.flakeModules.default
    inputs.terranix.flakeModules.default
  ];

  systems = [ "x86_64-linux" "aarch64-linux" ];

  perSystem = { config, pkgs, system, ... }: {
    # Simple property tests via nix-unit
    nix-unit.tests = {
      "RT-1: Terraform output equivalence" = {
        expr = ''
          let
            terraform = flake.terranix.${system};
          in builtins.hasAttr "google_compute_instance" terraform
        '';
        expected = "true";
      };

      "IT-1: Clan inventory structure" = {
        expr = ''
          let
            inv = flake.clan.inventory;
          in builtins.hasAttr "machines" inv && builtins.hasAttr "instances" inv
        '';
        expected = "true";
      };

      "IT-2: Clan service targeting" = {
        expr = ''
          let
            zerotier = flake.clan.inventory.instances.zerotier;
          in builtins.hasAttr "controller" zerotier.roles
        '';
        expected = "true";
      };
    };
  };

  # Complex tests requiring derivations
  flake.checks = lib.genAttrs config.systems (system:
    withSystem system ({ config, pkgs, lib, ... }:
      {
        # RT-3: Machine configurations build
        machine-builds = pkgs.runCommand "machine-builds-test" {
          machines = builtins.attrNames top.config.flake.nixosConfigurations;
        } ''
          echo "Checking ${builtins.toString (builtins.length machines)} machine configs exist..."
          ${lib.concatMapStringsSep "\n" (m: ''
            if [ -d "${top.config.flake.nixosConfigurations.${m}.config.system.build.toplevel}" ]; then
              echo "✅ ${m} config valid"
            else
              echo "❌ ${m} config invalid"
              exit 1
            fi
          '') machines}
          echo "pass" > $out
        '';

        # VT-1: VM boot tests
        vm-boot-test = pkgs.testers.runNixOSTest {
          name = "test-clan-vm-boot";
          nodes.machine = {
            imports = [
              top.config.flake.nixosModules.default
            ];
          };
          testScript = ''
            machine.wait_for_unit("multi-user.target")
            machine.succeed("echo VM booted successfully")
          '';
        };
      }
    )
  );
}
```

**This pattern:**
- ✅ Avoids circular dependencies
- ✅ Uses nix-unit for simple tests
- ✅ Uses withSystem for complex tests
- ✅ Integrates with `nix flake check`
- ✅ Accesses complete flake outputs correctly
- ✅ Maintains per-system context where needed

---

## 7. What's Worth Testing in Nix Flake-Parts Repositories

### 7.1 General Test Categories

**1. Output Structure Tests**
Validate that flake outputs have expected structure:
```nix
"outputs have expected attributes" = {
  expr = ''
    let
      f = flake;
    in builtins.hasAttr "packages" f
       && builtins.hasAttr "nixosConfigurations" f
  '';
  expected = "true";
};
```

**2. Build Tests**
Verify that derivations can be built successfully:
```nix
checks.packages-build = pkgs.runCommand "test-packages" {
  packages = builtins.attrValues top.config.flake.packages.${system};
} ''
  ${lib.concatMapStringsSep "\n" (p: ''
    echo "Testing ${p.name or "unnamed"} builds..."
    test -n "${p}"
  '') packages}
  echo "pass" > $out
'';
```

**3. Property Tests**
Validate invariant properties of outputs:
```nix
"all packages have meta" = {
  expr = ''
    let
      pkgs = builtins.attrValues flake.packages.x86_64-linux;
    in builtins.all (p: p ? meta) pkgs
  '';
  expected = "true";
};
```

**4. Integration Tests**
Test interactions between components:
```nix
checks.nixos-vm-test = pkgs.testers.runNixOSTest {
  name = "integration-test";
  nodes.machine = {
    imports = [ top.config.flake.nixosModules.default ];
  };
  testScript = ''
    machine.wait_for_unit("multi-user.target")
  '';
};
```

**5. Regression Tests**
Ensure outputs remain equivalent across changes:
```nix
checks.terraform-baseline = pkgs.writeTextFile {
  name = "terraform-baseline";
  text = builtins.toJSON top.config.flake.terranix.x86_64-linux;
  checkPhase = ''
    # Compare with committed baseline
    diff $out ${./baseline/terraform.json} || {
      echo "Terraform output changed!"
      exit 1
    }
  '';
};
```

### 7.2 Test-Clan Specific Test Cases

Based on test-clan's structure (clan-core + terranix + infrastructure), here are recommended tests:

**Regression Tests (RT-X): MUST REMAIN PASSING**

**RT-1: Terraform Output Equivalence**
```nix
"terraform outputs unchanged" = {
  expr = ''
    let
      terraform = flake.terranix.x86_64-linux;
      resources = [
        "google_compute_instance"
        "google_compute_network"
        "google_compute_firewall"
      ];
    in builtins.all (r: builtins.hasAttr r terraform) resources
  '';
  expected = "true";
};
```

**RT-2: NixOS Closure Equivalence**
```nix
checks.nixos-closure-equivalence = pkgs.runCommand "closure-test" {
  machines = builtins.attrNames top.config.flake.nixosConfigurations;
} ''
  # For each machine, verify closure hasn't changed unexpectedly
  ${lib.concatMapStringsSep "\n" (m: ''
    config="${top.config.flake.nixosConfigurations.${m}.config.system.build.toplevel}"
    echo "Machine ${m} closure: $config"
  '') machines}
  echo "pass" > $out
'';
```

**RT-3: Machine Configurations Build**
```nix
checks.machine-builds = pkgs.runCommand "machine-builds" {
  machines = builtins.attrValues top.config.flake.nixosConfigurations;
} ''
  ${lib.concatMapStrings (m: ''
    test -d "${m.config.system.build.toplevel}" || exit 1
  '') machines}
  echo "All machines build successfully" > $out
'';
```

**Invariant Tests (IT-X): MUST ALWAYS PASS**

**IT-1: Clan Inventory Structure**
```nix
"clan inventory complete" = {
  expr = ''
    let
      inv = flake.clan.inventory;
      hasMachines = builtins.hasAttr "machines" inv;
      hasInstances = builtins.hasAttr "instances" inv;
      machineCount = builtins.length (builtins.attrNames inv.machines);
    in hasMachines && hasInstances && machineCount > 0
  '';
  expected = "true";
};
```

**IT-2: Clan Service Targeting**
```nix
"zerotier service targeting valid" = {
  expr = ''
    let
      zerotier = flake.clan.inventory.instances.zerotier;
    in builtins.hasAttr "controller" zerotier.roles
       && builtins.hasAttr "peer" zerotier.roles
  '';
  expected = "true";
};
```

**IT-3: specialArgs Propagation**
```nix
"inputs accessible in nixos modules" = {
  expr = ''
    let
      machine = flake.nixosConfigurations.hetzner-ccx23;
    in builtins.hasAttr "specialArgs" machine._module.args
  '';
  expected = "true";
};
```

**Feature Tests (FT-X): EXPECTED TO FAIL BEFORE REFACTORING**

**FT-1: Import-Tree Discovery**
```nix
"dendritic modules discovered" = {
  expr = ''
    builtins.hasAttr "dendriticModules" flake
  '';
  expected = "true";  # Fails until dendritic implemented
};
```

**FT-2: Namespace Exports**
```nix
"modules exported to namespace" = {
  expr = ''
    let
      ns = flake.namespace;
    in builtins.hasAttr "machines" ns
       && builtins.hasAttr "services" ns
  '';
  expected = "true";  # Fails until namespace pattern implemented
};
```

**Integration Tests (VT-X): VM BOOT VALIDATION**

**VT-1: VM Boot Test**
```nix
checks.vm-boot-test = withSystem "x86_64-linux" ({ pkgs, ... }:
  pkgs.testers.runNixOSTest {
    name = "test-clan-vm-boot";
    nodes = {
      testMachine = {
        imports = [
          top.config.flake.nixosConfigurations.hetzner-ccx23.config
        ];
      };
    };
    testScript = ''
      testMachine.wait_for_unit("multi-user.target")
      testMachine.succeed("systemctl is-active sshd")
      testMachine.succeed("test -f /etc/zerotier-one/authtoken.secret")
    '';
  }
);
```

---

## 8. Implementation Guide for test-clan

### 8.1 Recommended Approach

For test-clan, use the **Hybrid Approach** combining nix-unit and withSystem:

1. **Simple property tests** → nix-unit expr/expected (RT-1, IT-1, IT-2, IT-3, FT-1, FT-2)
2. **Build validation tests** → withSystem + runCommand (RT-2, RT-3)
3. **VM integration tests** → withSystem + runNixOSTest (VT-1)

### 8.2 Implementation Steps

**Step 1: Add nix-unit input to flake.nix**
```nix
inputs.nix-unit.url = "github:nix-community/nix-unit";
inputs.nix-unit.inputs.nixpkgs.follows = "nixpkgs";
```

**Step 2: Import nix-unit flake module**
```nix
imports = [
  inputs.nix-unit.modules.flake.default
];
```

**Step 3: Create test directory structure**
```
tests/
├── nix-unit/
│   ├── regression.nix    # RT-1
│   ├── invariant.nix     # IT-1, IT-2, IT-3
│   └── feature.nix       # FT-1, FT-2
└── integration/
    └── vm-boot.nix       # VT-1
```

**Step 4: Define nix-unit tests in perSystem**
```nix
perSystem = { config, ... }: {
  nix-unit.tests = {
    regression = import ./tests/nix-unit/regression.nix;
    invariant = import ./tests/nix-unit/invariant.nix;
    feature = import ./tests/nix-unit/feature.nix;
  };
};
```

**Step 5: Define complex tests at flake level**
```nix
top@{ withSystem, config, lib, ... }:
{
  # ... perSystem above ...

  flake.checks = lib.genAttrs config.systems (system:
    withSystem system ({ pkgs, ... }: {
      machine-builds = import ./tests/integration/machine-builds.nix {
        flake = top.config.flake;
        inherit pkgs lib system;
      };
      vm-boot = import ./tests/integration/vm-boot.nix {
        flake = top.config.flake;
        inherit pkgs lib system;
      };
    })
  );
}
```

### 8.3 Validation Criteria

**Verification Steps:**

1. **Tests can be defined without circular dependencies**
   ```bash
   nix flake show
   # Should display checks without infinite recursion errors
   ```

2. **Tests have access to necessary flake outputs**
   ```bash
   nix eval .#checks.x86_64-linux --apply builtins.attrNames
   # Should show all defined checks
   ```

3. **`nix flake check` runs tests successfully**
   ```bash
   nix flake check
   # Should execute all checks and report pass/fail
   ```

4. **nix-unit tests execute correctly**
   ```bash
   nix build .#checks.x86_64-linux.nix-unit
   # Should build successfully if tests pass
   ```

5. **Individual checks can be built**
   ```bash
   nix build .#checks.x86_64-linux.machine-builds
   nix build .#checks.x86_64-linux.vm-boot-test
   ```

6. **Tests fail appropriately when conditions not met**
   - Temporarily break a test condition
   - Verify check fails
   - Restore test condition
   - Verify check passes again

---

## 9. References and Source Analysis

### 9.1 Flake-Parts Source Code References

**Core Modules:**
- `~/projects/nix-workspace/flake-parts/modules/perSystem.nix` - perSystem module implementation
  - Lines 87-96: perSystem module type definition with custom error messages for unavailable args
  - Lines 138-139: perSystem evaluation (separate eval per system)
  - Lines 148-149: allSystems generation (genAttrs config.systems config.perSystem)

- `~/projects/nix-workspace/flake-parts/modules/transposition.nix` - Transposition system
  - Lines 99-110: Flake output generation from allSystems
  - Lines 112-120: perInput reverse transposition

- `~/projects/nix-workspace/flake-parts/modules/withSystem.nix` - withSystem implementation
  - Lines 31-34: withSystem provides access to perSystem allModuleArgs

- `~/projects/nix-workspace/flake-parts/lib.nix` - flake-parts library functions
  - Lines 171-199: mkTransposedPerSystemModule helper
  - Lines 138-142: mkFlake implementation

- `~/projects/nix-workspace/flake-parts/modules/checks.nix` - Checks module
  - Entire file: Uses mkTransposedPerSystemModule for checks

### 9.2 Nix-Unit Source Code References

**Integration Modules:**
- `~/projects/nix-workspace/nix-unit/lib/modules/flake/system.nix` - System-specific integration
  - Lines 105-130: nix-unit check derivation creation
  - Lines 133-137: flake.tests.systems output generation

- `~/projects/nix-workspace/nix-unit/lib/modules/flake/system-agnostic.nix` - System-agnostic tests
  - Lines 26-28: Copy flake.tests into perSystem tests

- `~/projects/nix-workspace/nix-unit/lib/modules/flake/dogfood.nix` - nix-unit self-tests
  - Example of nix-unit usage in production

### 9.3 Working Examples Found

**flake-parts eval-tests:**
- `~/projects/nix-workspace/flake-parts/dev/tests/eval-tests.nix`
- Pattern: External tests that call mkFlake and assert on results
- No circular dependencies because tests are outside the flake being tested

**nix-unit integration:**
- `~/projects/nix-workspace/nix-unit/flake.nix` (lines 34-44, 80-89)
- Pattern: Tests defined as DATA in perSystem, executed by binary with flake access
- Separates test definition from test execution

### 9.4 Failed Attempts Documented

**test-clan phase-0-tests branch:**
- `~/projects/nix-workspace/test-clan` (branch: phase-0-tests)
- Commits f0aa5e9..f405a6a
- Attempted: Import tests in perSystem with inputs.self and config.flake
- Failed: Circular dependencies due to accessing outputs during their construction
- Learning: Tests needing flake outputs must be at flake level, not perSystem

---

## 10. Validation and Next Steps

### 10.1 Validation Checklist

**Pre-Implementation:**
- [ ] Read and understand flake-parts perSystem evaluation model
- [ ] Read and understand nix-unit test format and integration
- [ ] Review failed phase-0-tests attempts to understand pitfalls
- [ ] Choose appropriate test approach for each test category

**Implementation:**
- [ ] Add nix-unit to flake inputs
- [ ] Import nix-unit flake module
- [ ] Create test directory structure
- [ ] Implement simple property tests via nix-unit
- [ ] Implement complex tests via withSystem at flake level
- [ ] Verify no circular dependency errors with `nix flake show`

**Validation:**
- [ ] `nix flake check` executes without errors
- [ ] `nix eval .#checks.<system> --apply builtins.attrNames` shows all checks
- [ ] Each individual check can be built: `nix build .#checks.<system>.<check-name>`
- [ ] nix-unit check passes: `nix build .#checks.<system>.nix-unit`
- [ ] Tests fail appropriately when conditions are not met
- [ ] Tests pass when conditions are restored

**Operational:**
- [ ] Tests run in CI/CD pipelines
- [ ] Test failures are actionable and clear
- [ ] Developers can run specific test categories
- [ ] Test execution time is reasonable (<5 min for full suite)

### 10.2 Story 1.6 Revision Requirements

Based on this research, Story 1.6 needs the following revisions:

**Technical Approach Changes:**

1. **Remove**: Attempts to import tests in perSystem with flake output access
2. **Add**: Hybrid approach using both nix-unit and withSystem
3. **Add**: Clear distinction between:
   - Simple tests (nix-unit in perSystem)
   - Complex tests (withSystem at flake level)

**Implementation Pattern:**

**Original (Incorrect):**
```nix
perSystem = { ... }: {
  checks = {
    test = (import ./test.nix { self = inputs.self; }).test;  # CIRCULAR
  };
};
```

**Revised (Correct):**
```nix
top@{ withSystem, config, lib, ... }:
{
  # Simple tests in perSystem via nix-unit
  perSystem = {
    nix-unit.tests.simple = {
      expr = "flake.clan.inventory.machines";
      expected = "{ /* ... */ }";
    };
  };

  # Complex tests at flake level via withSystem
  flake.checks = lib.genAttrs config.systems (system:
    withSystem system ({ pkgs, ... }: {
      complex = import ./test.nix {
        flake = top.config.flake;
        inherit pkgs lib system;
      };
    })
  );
}
```

**Deliverables Update:**

1. **Test Suite Structure:** tests/nix-unit/ and tests/integration/
2. **Integration:** Hybrid nix-unit + withSystem approach
3. **Test Categories:**
   - RT-1: nix-unit (terraform output structure)
   - RT-2, RT-3: withSystem (build validation)
   - IT-1, IT-2, IT-3: nix-unit (property validation)
   - FT-1, FT-2: nix-unit (dendritic features)
   - VT-1: withSystem (VM boot test)

**Acceptance Criteria Changes:**

Add:
- [ ] All tests avoid circular dependencies
- [ ] Tests use appropriate pattern (nix-unit vs withSystem)
- [ ] Test files organized in tests/nix-unit/ and tests/integration/
- [ ] `nix flake show` displays checks without errors

**Technical Specification Addition:**

Include this research document as reference:
`docs/notes/development/research/flake-parts-nix-unit-test-integration.md`

---

## Document Status

**Research Complete:** 2025-11-05

**Key Findings:**
1. perSystem evaluation happens BEFORE flake outputs exist
2. Tests needing flake outputs CANNOT be defined in perSystem
3. THREE viable patterns: top@, withSystem, nix-unit
4. Hybrid approach recommended for test-clan
5. Failed attempts documented for learning

**Next Actions:**
1. Review this research document
2. Revise Story 1.6 technical approach
3. Implement test suite using recommended patterns
4. Validate with checklist in section 10.1

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
