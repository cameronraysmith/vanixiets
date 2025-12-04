---
title: "ADR-0002: Use generic just recipes"
---

## Prefer Generic Over Specific

When designing justfile recipes, prefer generic parameterized recipes over specific convenience wrappers unless there's a compelling reason.

---

## The Anti-Pattern

### Bad: Hardcoded Convenience Wrappers

```just
# Don't do this - adds no value
cache-bitwarden-linux: (cache-linux-package "bitwarden-cli")
cache-rust-analyzer-linux: (cache-linux-package "rust-analyzer")
cache-neovim-linux: (cache-linux-package "neovim")
```

**Problems**:
1. **Hardcoding**: Defeats the purpose of having a generic recipe
2. **Redundancy**: No functionality added, just shorter name
3. **Maintenance**: More recipes to update when logic changes
4. **Discoverability**: Obscures the generic pattern
5. **Documentation drift**: Can get out of sync with actual needs

### Good: Generic Recipe + Documentation

```just
# Cache a package for Linux architectures and push to cachix
[group('CI/CD')]
cache-linux-package package:
    # ... implementation ...
```

**Usage documented in README or comments**:
```bash
# Cache custom packages for Linux
just cache-linux-package bitwarden-cli
just cache-linux-package rust-analyzer
just cache-linux-package neovim
```

**Benefits**:
1. **Flexibility**: Works for any package
2. **Clear pattern**: Shows the generic approach
3. **Less maintenance**: One recipe to maintain
4. **Self-documenting**: Parameters show what's needed
5. **Discoverable**: `just --list` shows generic capability

---

## When Wrappers ARE Justified

### Criteria for Creating a Convenience Wrapper

Create a wrapper ONLY when it provides real value:

#### 1. Complex Multi-Step Workflow

**Example**: `cache-rosetta-builder`
```just
cache-rosetta-builder:
    # 1. Build VM image
    # 2. Push to cachix
    # 3. Pin for persistence
    # 4. Update system configuration
    # 5. Verify cache availability
```

**Why justified**: Combines multiple operations with complex logic that users shouldn't have to remember.

#### 2. Multiple Related Parameters

**Example**: `build-multiarch container`
```just
build-multiarch container:
    @just build-container {{ container }} aarch64-linux
    @just build-container {{ container }} x86_64-linux
```

**Why justified**: Encapsulates the common pattern of "build for all Linux architectures" with correct parameter ordering.

#### 3. Part of Documented User Workflow

**Example**: `cache-darwin-system`
```just
cache-darwin-system:
    # Complex workflow specific to darwin system caching
    # - Build system closure
    # - Handle system-specific paths
    # - Update activation scripts
```

**Why justified**: Users following documentation expect this as a known operation, and it has system-specific logic.

---

## Design Pattern: Generic + Examples

### Pattern Structure

```just
# Generic recipe with clear parameter names
[group('category')]
generic-operation param1 param2:
    #!/usr/bin/env bash
    # Implementation using {{ param1 }} and {{ param2 }}
    echo "Operating on {{ param1 }} with {{ param2 }}"
```

### Documentation in Comments or README

```just
# Examples:
#   just generic-operation foo bar
#   just generic-operation baz qux
#
# Common use cases:
#   Development: just generic-operation dev debug
#   Production:  just generic-operation prod release
```

---

## Real-World Examples from This Repo

### Good: Generic Recipes

#### cache-linux-package
```just
cache-linux-package package:
    # Builds for aarch64-linux and x86_64-linux
    # Pushes to cachix with dependencies
    # Handles verification and pinning
```

**Usage**:
```bash
just cache-linux-package bitwarden-cli
just cache-linux-package <any-package>
```

#### update-package
```just
update-package package="ccstatusline":
    # Generic package updater
    # Works with any package that has updateScript
    # Note: claude-code-bin now from nix-ai-tools, auto-updates daily
```

**Usage**:
```bash
just update-package                    # default
just update-package bitwarden-cli      # specific
```

#### build-container
```just
build-container container arch=_native_linux_arch:
    # Generic container builder
    # Auto-detects arch or takes explicit value
```

**Usage**:
```bash
just build-container myapp                # native arch
just build-container myapp aarch64-linux  # specific arch
```

### Good: Justified Wrappers

#### cache-rosetta-builder
```just
cache-rosetta-builder:
    # Multi-step complex workflow
    # 1. Build VM with specific config
    # 2. Push with specific paths
    # 3. Pin with specific name
    # 4. Verify and report status
```

**Justified because**: Complex multi-step operation with rosetta-specific logic.

#### build-multiarch
```just
build-multiarch container:
    @just build-container {{ container }} aarch64-linux
    @just build-container {{ container }} x86_64-linux
```

**Justified because**: Common pattern (both architectures) with correct parameter ordering.

### Bad: Removed Wrappers

#### cache-bitwarden-linux (REMOVED)
```just
# REMOVED - was just: cache-linux-package "bitwarden-cli"
# Use generic recipe instead: just cache-linux-package bitwarden-cli
```

**Why removed**: Added no functionality, just hardcoded parameter.

---

## Migration Guide

### Removing Unnecessary Wrappers

**Step 1**: Identify candidates
```bash
# Find single-line wrappers
rg '^[a-z-]+:.*\([a-z-]+ "[^"]+"\)$' justfile
```

**Step 2**: Check if used in production
```bash
# Search codebase
rg "just wrapper-name" .github/ scripts/ README.md

# If only in docs, safe to update
rg "just wrapper-name" docs/
```

**Step 3**: Update documentation
```diff
- just cache-bitwarden-linux
+ just cache-linux-package bitwarden-cli
```

**Step 4**: Remove wrapper
```diff
- [group('CI/CD')]
- cache-bitwarden-linux: (cache-linux-package "bitwarden-cli")
```

**Step 5**: Add usage comment
```just
# Cache packages for Linux (example: just cache-linux-package bitwarden-cli)
[group('CI/CD')]
cache-linux-package package:
```

---

## Documentation Strategy

### In justfile Comments

```just
# Generic recipe for X (see examples below)
#
# Examples:
#   just recipe-name foo
#   just recipe-name bar
#
# Common packages:
#   bitwarden-cli - password manager
#   rust-analyzer - LSP server
#   neovim        - text editor
[group('category')]
recipe-name param:
    # implementation
```

### In README

Create a "Common Recipes" section:

```markdown
## Common CI/CD Operations

### Caching Packages for Linux

```bash
# Generic recipe works for any package
just cache-linux-package <package-name>

# Examples
just cache-linux-package bitwarden-cli
just cache-linux-package rust-analyzer
```

### Building Containers

```bash
# Single architecture
just build-container myapp aarch64-linux

# All Linux architectures (wrapper provided)
just build-multiarch myapp
```
```

---

## Benefits of This Approach

### 1. Maintainability
- Change generic recipe → all uses benefit
- No need to update multiple wrappers
- Single source of truth for logic

### 2. Discoverability
- `just --list` shows patterns, not specific instances
- Users learn the generic approach
- Easier to understand capabilities

### 3. Flexibility
- Works for current and future packages
- No need to add wrapper for each new use case
- Adapts to evolving requirements

### 4. Consistency
- Same pattern across all operations
- Predictable parameter ordering
- Clear naming conventions

### 5. Documentation
- Examples show usage patterns
- Comments explain parameters
- README provides context

---

## Decision Framework

When considering a new recipe, ask:

```
┌─ Is this a generic operation? ─────────────────────────────────┐
│                                                                  │
│  YES → Create generic recipe with parameters                    │
│        Add usage examples in comments                           │
│                                                                  │
│  NO  → Is it complex multi-step?                               │
│        │                                                        │
│        ├─ YES → Wrapper justified                              │
│        │        Document why it's special                      │
│        │                                                        │
│        └─ NO  → Use generic recipe                             │
│               Add example to docs                              │
└──────────────────────────────────────────────────────────────────┘
```

---

## Examples of Good Judgment Calls

### Cache Rosetta Builder → Wrapper ●
- **Complex**: Multi-step build + push + pin + config update
- **Justified**: Too complex to expect users to remember all steps

### Cache Any Package → Generic ●
- **Simple**: One parameter, straightforward operation
- **Not Justified**: Users can easily remember `just cache-linux-package <name>`

### Build Multiarch → Wrapper ●
- **Pattern**: Common to build both architectures
- **Justified**: Saves remembering architecture names and order

### Cache Specific Package → No Wrapper ●
- **Hardcoding**: Just passes parameter to generic recipe
- **Not Justified**: No complexity reduction, just shorter name

---

## Enforcement

### Code Review Checklist

When adding/reviewing justfile recipes:

- [ ] Is this a generic operation?
- [ ] If yes, does it accept parameters?
- [ ] If no, is the complexity justified?
- [ ] Are usage examples provided?
- [ ] Is it documented in README?
- [ ] Does it follow naming conventions?
- [ ] Would future users understand the pattern?

### Periodic Cleanup

Quarterly review:
1. Find single-line wrappers
2. Check if they're used in production
3. Update docs to use generic recipes
4. Remove unjustified wrappers

---

## Summary

**Principle**: Prefer generic parameterized recipes over specific convenience wrappers.

**Exception**: Complex multi-step operations that provide real value.

**Result**: Maintainable, discoverable, flexible justfile that scales with your needs.

**This repo's decision**: Removed `cache-bitwarden-linux` in favor of `cache-linux-package bitwarden-cli` following this principle.
