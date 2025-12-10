# Canonical URLs for module system documentation

This document maps canonical URLs and source references for the Nix module system, covering core concepts like evalModules, deferredModule, submodules, and option types.

## Official documentation

| Concept | Primary URL | Description |
|---------|------------|-------------|
| Module system overview | https://nix.dev/tutorials/module-system/ | Introduction to the module system as a Nix language library for declaring attribute sets across multiple expressions with type constraints and automatic merging |
| A basic module | https://nix.dev/tutorials/module-system/a-basic-module/ | Tutorial covering module basics: declaring options with mkOption, defining values under config, and evaluating with lib.evalModules |
| Deep dive | https://nix.dev/tutorials/module-system/deep-dive.html | Comprehensive tutorial building a Google Maps API wrapper, covering evalModules, submodules, type checking, option dependencies, and advanced types |
| evalModules reference | https://nixos.org/manual/nixpkgs/unstable/#module-system-lib-evalModules | Official nixpkgs manual reference for lib.evalModules function (note: full content may require navigating to Module System section) |
| Option types reference | https://nixos.org/manual/nixos/stable/#sec-option-types-basic | NixOS manual covering basic option types available under lib.types |
| mkOption reference | https://nixos.org/manual/nixpkgs/stable/#function-library-lib.options.mkOption | Official nixpkgs manual reference for lib.mkOption function |

## Source code references

| Primitive | File | Line | GitHub permalink |
|-----------|------|------|------------------|
| evalModules | lib/modules.nix | 84 | https://github.com/NixOS/nixpkgs/blob/master/lib/modules.nix#L84 |
| deferredModule | lib/types.nix | 1138 | https://github.com/NixOS/nixpkgs/blob/master/lib/types.nix#L1138 |
| deferredModuleWith | lib/types.nix | 1143 | https://github.com/NixOS/nixpkgs/blob/master/lib/types.nix#L1143 |
| mkOption | lib/options.nix | 139 | https://github.com/NixOS/nixpkgs/blob/master/lib/options.nix#L139 |
| mkMerge | lib/modules.nix | 1478 | https://github.com/NixOS/nixpkgs/blob/master/lib/modules.nix#L1478 |

Note: Line numbers reference nixpkgs commit 677fbe97984e (December 2025).
For stable references, use GitHub permalinks with full commit hashes.

## Cross-reference matrix

Shows which documentation sources cover key module system concepts:

| Concept | nix.dev basic | nix.dev deep-dive | nixos.org/nixos | nixos.org/nixpkgs | Source |
|---------|---------------|-------------------|-----------------|-------------------|--------|
| Module structure | yes | yes | yes | partial | yes |
| evalModules | yes | yes | partial | reference | yes |
| mkOption | yes | yes | yes | reference | yes |
| mkMerge | no | partial | yes | partial | yes |
| submodule type | no | yes | yes | partial | yes |
| deferredModule | no | no | limited | no | yes |
| Type checking | yes | yes | yes | yes | yes |
| attrsOf type | no | yes | yes | partial | yes |
| listOf type | yes | yes | yes | partial | yes |
| either/enum types | no | yes | yes | partial | yes |
| strMatching type | no | yes | yes | partial | yes |

## Recommended citation order

For each concept, the preferred documentation to cite in order of comprehensiveness:

### Core module system primitives
1. **evalModules**: nix.dev basic module tutorial → nix.dev deep-dive → nixpkgs source (lib/modules.nix)
2. **mkOption**: nix.dev basic module tutorial → nixpkgs manual reference → nixpkgs source (lib/options.nix)
3. **mkMerge**: nixos.org manual → nixpkgs source (lib/modules.nix)

### Type system
1. **submodule**: nix.dev deep-dive (sections 2.13, 2.15) → nixos.org manual → nixpkgs source (lib/types.nix)
2. **deferredModule**: nixpkgs source code with inline comments (lib/types.nix:1138-1147) → limited nixos.org manual references
3. **Basic types** (str, int, bool, listOf, attrsOf): nix.dev tutorials → nixos.org manual → nixpkgs source
4. **Advanced types** (either, enum, strMatching, ints.between): nix.dev deep-dive → nixos.org manual → nixpkgs source

### Module composition
1. **imports**: nix.dev deep-dive (section 2.12) → nixos.org manual → nixpkgs source
2. **Option dependencies**: nix.dev deep-dive (section 2.9) → nixpkgs source
3. **Conditional definitions** (mkIf): nix.dev deep-dive (section 2.10) → nixos.org manual → nixpkgs source
4. **Priority system** (mkDefault, mkForce): nix.dev deep-dive (section 2.20) → nixos.org manual → nixpkgs source

## Local references

For offline development, local copies of key documentation sources:

| Resource | Local path |
|----------|-----------|
| nix.dev source | ~/projects/nix-workspace/nix.dev/source/ |
| Module system tutorials | ~/projects/nix-workspace/nix.dev/source/tutorials/module-system/ |
| nixpkgs lib source | ~/projects/nix-workspace/nixpkgs/lib/ |
| modules.nix | ~/projects/nix-workspace/nixpkgs/lib/modules.nix |
| types.nix | ~/projects/nix-workspace/nixpkgs/lib/types.nix |
| options.nix | ~/projects/nix-workspace/nixpkgs/lib/options.nix |

## Verification notes

All URLs verified as of 2025-12-10:
- nix.dev/tutorials/module-system/ paths confirmed accessible
- nixos.org/manual references confirmed (full content may require section navigation)
- GitHub permalinks use master branch; for stable references, replace with full commit SHA
- Local nixpkgs tracking nixpkgs-unstable branch at commit 677fbe97984e
