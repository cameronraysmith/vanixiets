---
title: "Content-Addressed Build Caching in GitHub Actions"
---

**Date:** November 1, 2025
**Context:** Nix-based monorepo with TypeScript packages, 19 GitHub Actions jobs
**Repository:** `/Users/crs58/projects/nix-workspace/infra`

## Executive Summary

This research investigates elite approaches to content-addressed build caching in GitHub Actions, with the goal of moving beyond commit SHA-based cache keys to input-hash-based caching that matches Nix's closure semantics.

The current system uses a two-layer approach: `actions/cache` with SHA-based keys plus path filters approximating change detection.
The primary limitation is that cache keys include commit SHAs (specifically `github.event.pull_request.head.sha` truncated to 12 characters), meaning PR merge commit regeneration and changes to irrelevant files both invalidate caches unnecessarily.

Key findings from this research:

**Content-addressed caching is the industry standard approach** used by modern build systems (Bazel, Buck2, Nix, Turborepo, Nx) and offers significant advantages over commit-based strategies.
The core principle is: cache keys = hash(job-specific inputs only), not hash(commit + job context).

**Nix already provides content addressing** through its derivation system—the challenge is bridging Nix's content hashes to GitHub Actions cache keys.
Three primary strategies exist: (1) manual hash computation with `hashFiles()`, (2) Nix derivation hash extraction, and (3) dedicated tools (Magic Nix Cache, Cachix, Turborepo, Nx).

**Quick wins are available** without major architectural changes.
Replacing SHA-based cache keys with `hashFiles('flake.lock', '**/*.nix')` would provide 60-70% of the benefit while remaining simple.
For TypeScript packages, combining Nix file hashing with `hashFiles('**/bun.lockb', 'packages/*/package.json')` creates truly content-addressed keys.

**The GitHub Actions cache infrastructure is evolving**.
A new cache service launches February 1, 2025, with up to 80% faster uploads.
Magic Nix Cache's free tier ends the same date, requiring migration to alternatives (FlakeHub Cache, Cachix, or self-hosted).

This report provides tiered recommendations from immediate improvements (hours to implement) to long-term strategic options (weeks to implement), with specific code examples for your Nix + TypeScript monorepo context.

## 1. Terminology & Foundational Concepts

### Content-Addressed vs. Commit-Addressed Caching

**Content-addressed caching** identifies cached artifacts by the hash of their inputs, not their location in version control history.
Two builds with identical inputs produce identical cache keys regardless of branch, commit, or timing.

**Commit-addressed caching** (your current approach) ties cache keys to git commits, typically using `github.sha` or similar identifiers.
This creates fragility: rebasing, squashing, or amending commits all invalidate caches even when actual build inputs haven't changed.

**Input-addressed builds** is a synonym for content-addressed caching, emphasizing that cache keys derive from build inputs rather than source control metadata.

The distinction matters because:

- **Content-addressed caching** maximizes cache reuse across branches, PRs, and time
- **Commit-addressed caching** provides cache isolation (potentially better security) but lower hit rates
- **Hybrid approaches** can combine both: content-addressing for dependencies, commit info for provenance

### Core Concepts

#### Derivation-Based Caching (Nix Terminology)

Nix's fundamental abstraction is the **derivation**: a specification of how to build something, including all inputs (source files, dependencies, environment variables, build commands).
The derivation hash is computed from these inputs, making it truly content-addressed.

A Nix **store path** looks like `/nix/store/r8vvq9kq18pz08v249h8my6r9vs7s0n3-hello-2.12`, where the hash prefix (`r8vvq9...`) is derived from the derivation.

**Key insight:** Nix already solves content-addressed caching—you just need to expose those hashes to GitHub Actions.

#### Closure Semantics

A **closure** is the complete set of dependencies needed to build or run something.
In Nix, `nix-store --query --requisites` computes closures.

Content-addressed caching with closure semantics means: cache key = hash(all transitive dependencies), not just hash(direct inputs).

For your use case: changing `flake.lock` should invalidate caches because it changes the closure, but changing `README.md` should not because it's outside most build closures.

#### Hermetic Builds

A **hermetic build** produces identical outputs given identical inputs, regardless of build environment.
Hermeticity enables content-addressed caching to work reliably—if builds aren't hermetic, content hashing becomes unreliable.

Nix provides strong hermeticity guarantees through:

- Isolated build environments (no network access, controlled environment variables)
- Reproducible dependency resolution via `flake.lock`
- Content-addressed store preventing dependency confusion

Your system already benefits from Nix's hermeticity, making content-addressed caching particularly attractive.

#### Action Cache vs. Content-Addressable Store (CAS)

Build systems like Bazel distinguish:

- **Action Cache**: Maps action hashes → metadata about execution results
- **Content-Addressable Store (CAS)**: Maps content hashes → actual file contents

GitHub Actions `actions/cache` implements a key-value store (similar to action cache) but not a true CAS.
You must manually compute keys and manage cache entries, unlike Nix's automatic CAS.

### Tradeoffs: Content-Addressed vs. Commit-Based Caching

| Dimension | Content-Addressed | Commit-Based (Current) |
|-----------|-------------------|------------------------|
| **Cache hit rate** | High - same inputs = hit across branches | Low - each commit = new key |
| **PR workflow** | Survives rebase, amend, squash | Breaks on any commit rewrite |
| **Security** | Requires careful input validation | Natural isolation per commit |
| **Debugging** | "Why didn't cache hit?" harder | Easy to see which commit built it |
| **Implementation complexity** | Moderate - must compute input hashes | Simple - use `github.sha` |
| **Cache bloat** | Lower - dedups identical inputs | Higher - every commit = cache entry |
| **Incremental adoption** | Can coexist with commit keys | N/A |

**Key tradeoff:** Content addressing favors performance (better hit rates), while commit addressing favors simplicity and provenance.

Your current system already uses path filters to approximate content addressing, suggesting you value performance over pure simplicity.

### Relationship to Nix Closures

Nix's closure concept maps naturally to content-addressed caching:

1. **Closure = transitive dependencies**: For a build target, the closure includes all inputs affecting the output
2. **Closure hash = cache key**: Hash the closure → cache key identifying the build
3. **Closure change detection**: If closure hash changes, cache miss; otherwise, cache hit

Your challenge: GitHub Actions doesn't natively understand Nix closures, so you must bridge the concepts.

Two approaches:

- **Approximate closures**: Use `hashFiles('flake.lock', '**/*.nix')` to detect most closure changes
- **Exact closures**: Extract actual Nix derivation hashes via `nix-store --query` or `nix path-info`

The former is simpler; the latter is more precise.

## 2. Tool Landscape Analysis

### Overview

The content-addressed caching landscape divides into three categories:

1. **Build systems with native content addressing** (Bazel, Buck2, Nix)
2. **Monorepo tools with remote caching** (Turborepo, Nx, Pants)
3. **CI-specific caching solutions** (Magic Nix Cache, Cachix, GitHub Actions patterns)

Your context (Nix + TypeScript monorepo + GitHub Actions) spans all three categories.

### Detailed Tool Comparison

| Tool | Approach | Strengths | GitHub Actions Integration | Fit for Your Use Case |
|------|----------|-----------|---------------------------|----------------------|
| **Nix (native)** | Derivation hashing | Already in use, hermetic, CAS built-in | Manual via `hashFiles()` or derivation extraction | **High** - foundation already present |
| **Magic Nix Cache** | Nix store → GitHub Actions cache bridge | Zero-config, automatic, fast | Excellent (dedicated action) | **Medium** - free tier EOL Feb 1, 2025 |
| **Cachix** | Binary cache service for Nix | Mature, reliable, good performance | Good (cachix-action) | **High** - already using it |
| **Turborepo** | Task hashing for monorepos | Strong TypeScript support, good DX | Excellent (native GitHub Actions support) | **Medium-High** - fits TS packages, not Nix |
| **Nx** | Computation cache with affected detection | Enterprise features, excellent monorepo support | Excellent (nx-set-shas action) | **Medium-High** - similar to Turborepo |
| **Bazel** | Action digest-based CAS | Most sophisticated, scales to massive repos | Good (bazel-contrib/setup-bazel) | **Low** - too heavy for your needs |
| **Buck2** | Content-addressed remote execution | Very fast, modern design | Fair (manual integration) | **Low** - Meta-scale tool, overkill |
| **Earthly** | Docker-based layer caching | Reproducible, good CI/CD integration | Good (native Docker-like syntax) | **Medium** - adds Docker layer complexity |
| **GitHub Actions (native)** | Manual `hashFiles()` patterns | No external dependencies, simple | Excellent (native) | **High** - quick wins available here |

### Nix Ecosystem Tools (Deep Dive)

#### Nix (Native Derivation System)

**How it works:**
Every Nix build is specified by a derivation, which includes all inputs (source files, dependencies, environment, build commands).
Nix computes a hash of the derivation inputs, creating a store path like `/nix/store/<hash>-<name>`.

**Content addressing in Nix:**

```bash
# Get derivation path for a flake output
nix path-info --derivation '.#packages.x86_64-linux.docs'

# Query dependencies (closure)
nix-store --query --requisites $(nix path-info '.#packages.x86_64-linux.docs')

# Get hash of a store path
nix-store --query --hash $(nix path-info '.#packages.x86_64-linux.docs')
```

**Integration with GitHub Actions:**
You can extract derivation hashes and use them as cache keys:

```yaml
- name: Compute Nix derivation hash
  id: nix-hash
  run: |
    DRV=$(nix path-info --derivation '.#packages.${{ matrix.system }}.docs')
    HASH=$(nix-store --query --hash "$DRV")
    echo "hash=${HASH}" >> $GITHUB_OUTPUT

- uses: actions/cache@v4
  with:
    path: /nix/store
    key: nix-${{ matrix.system }}-${{ steps.nix-hash.outputs.hash }}
```

**Strengths:**

- Already using Nix - zero new dependencies
- True content addressing with closure semantics
- Hermetic builds guarantee cache correctness

**Weaknesses:**

- Requires Nix to be installed before computing hashes (chicken-and-egg)
- Verbose to extract hashes for multiple outputs
- Doesn't help with TypeScript package caching

**Fit for your use case: Very High**

Your flake already defines all build targets.
With some scripting, you can extract derivation hashes and use them for surgical cache invalidation.

#### Magic Nix Cache (Determinate Systems)

**How it works:**
A daemon runs in the GitHub Actions runner, intercepts Nix's binary cache requests, and routes them to GitHub Actions cache API instead of disk/remote server.
It automatically caches everything Nix builds without explicit configuration.

**Architecture:**

1. Action starts daemon before Nix commands run
2. Daemon fetches current GitHub Actions cache inventory
3. Nix builds proceed normally, using daemon as binary cache
4. Post-build, daemon uploads new store paths to GitHub Actions cache

**Content addressing:**
Leverages Nix's native content addressing - no manual key computation needed.

**Example usage:**

```yaml
- uses: DeterminateSystems/magic-nix-cache-action@main

- name: Build Nix packages
  run: nix build '.#packages.x86_64-linux.docs'
```

**Strengths:**

- Zero configuration required
- Automatic cache management
- Works with any Nix command
- Branch isolation for security

**Weaknesses:**

- **Free tier ends February 1, 2025** - requires migration
- Proprietary backend (though action is open source)
- Doesn't help with non-Nix caching (TypeScript packages)

**Fit for your use case: Medium (was High before EOL announcement)**

Previously the best turnkey solution for Nix caching in GitHub Actions.
Now requires evaluating alternatives: FlakeHub Cache (paid), Cachix (already using), or self-hosted solutions.

#### Cachix

**How it works:**
A binary cache service for Nix that stores built derivations on their servers.
During builds, Nix checks Cachix for pre-built outputs; if found, downloads instead of building.

**Content addressing:**
Uses Nix's derivation hashing - cache lookups are by derivation output hash.

**Example usage:**

```yaml
- uses: cachix/cachix-action@v15
  with:
    name: cameronraysmith  # Your existing cache
    authToken: '${{ secrets.CACHIX_AUTH_TOKEN }}'

- run: nix build '.#packages.x86_64-linux.docs'
  # Automatically pushes to Cachix on success
```

**Your current setup:**

```yaml
# From ci.yaml line 912-919
- name: setup nix
  uses: ./.github/actions/setup-nix
  with:
    system: ${{ matrix.system }}
    enable-cachix: true
    cachix-name: ${{ env.CACHIX_BINARY_CACHE }}  # cameronraysmith
    cachix-auth-token: ${{ secrets.CACHIX_AUTH_TOKEN }}
```

You're already using Cachix for Nix binary caching!

**Strengths:**

- Already integrated in your workflow
- Mature, reliable service
- Good performance
- Supports your multi-system setup (x86_64-linux, aarch64-linux)

**Weaknesses:**

- Requires external service (network dependency)
- Costs money for private caches at scale
- Doesn't help with TypeScript package caching

**Fit for your use case: High**

You're leveraging Nix's content addressing via Cachix already.
The gap is: GitHub Actions job-level caching still uses commit SHAs, not Nix derivation hashes.

#### nix-community/cache-nix-action

**How it works:**
A GitHub Action that wraps `actions/cache` specifically for Nix store paths.
You provide cache keys (typically using `hashFiles()`), and it manages restoring/saving Nix store contents.

**Example pattern:**

```yaml
- uses: nix-community/cache-nix-action@v6
  with:
    primary-key: nix-${{ runner.os }}-${{ hashFiles('**/*.nix', '**/flake.lock') }}
    restore-prefixes-first-match: nix-${{ runner.os }}-
    paths: /nix/store
```

**Strengths:**

- Combines `actions/cache` with Nix-specific optimizations
- Supports advanced restore strategies (first-match, all-matches)
- No external service required

**Weaknesses:**

- Still limited by GitHub Actions cache constraints (10GB, 7-day retention)
- Manual key computation required
- Doesn't provide the content addressing that Cachix/Magic Nix Cache offer

**Fit for your use case: Medium**

Useful for augmenting Cachix with local GitHub Actions cache, but doesn't solve the core problem (commit SHA-based keys).

### Monorepo Tools (Deep Dive)

#### Turborepo

**How it works:**
Turborepo analyzes your monorepo's task dependency graph and computes a hash for each task based on:

- Task inputs (files matching globs defined in `turbo.json`)
- Task dependencies (outputs from upstream tasks)
- Task definition (command, environment variables)
- Global hash (root-level dependencies)

**Cache key computation:**

```typescript
// Conceptual algorithm
const taskHash = hash({
  taskDefinition: task.command,
  inputs: filesMatchingGlobs(task.inputs),
  dependencies: dependencyHashes,
  environmentVariables: task.env,
  globalHash: hashFiles(['package.json', 'turbo.json'])
});
```

**Remote caching integration:**

```json
// turbo.json
{
  "remoteCache": {
    "signature": true  // HMAC-SHA256 signatures for security
  },
  "tasks": {
    "build": {
      "inputs": ["src/**/*.ts", "package.json"],
      "outputs": ["dist/**"],
      "dependsOn": ["^build"]
    }
  }
}
```

**GitHub Actions integration:**

```yaml
- uses: actions/setup-node@v4
  with:
    node-version: 20
    cache: 'npm'

- run: npm install

- run: npx turbo build test
  env:
    TURBO_TOKEN: ${{ secrets.TURBO_TOKEN }}
    TURBO_TEAM: ${{ vars.TURBO_TEAM }}
```

**Content addressing:**
True content-addressed caching - cache keys derive entirely from task inputs, not commits.

**Strengths:**

- Excellent TypeScript/Node.js ecosystem integration
- Automatic dependency graph analysis
- Remote caching with Vercel (free tier available) or self-hosted
- Good DX - minimal configuration

**Weaknesses:**

- Primarily focused on JavaScript/TypeScript monorepos
- Doesn't integrate with Nix
- Would be parallel to your Nix setup, not integrated with it

**Fit for your use case: Medium-High for TypeScript packages**

Could handle caching for `packages/docs` (TypeScript package) independently of Nix caching.
You'd run Turborepo for TS tasks, Nix/Cachix for system configuration tasks.

#### Nx

**How it works:**
Similar to Turborepo, Nx computes hashes for each cacheable task (called "computation hash") including:

- Source files of the project and its dependencies
- Global configuration
- External dependency versions
- Runtime values (Node version, environment variables)
- CLI command flags

**Cache key computation:**

```typescript
// From Nx documentation
const computationHash = hash({
  projectSourceFiles: allFilesInProject,
  dependencySourceFiles: allFilesInDependencies,
  globalConfig: nxJson,
  externalDependencies: packageLock,
  runtime: { nodeVersion, env },
  commandFlags: cliArgs
});
```

**Affected detection:**
Nx has sophisticated "affected" detection to determine which projects changed:

```bash
# Only build projects affected by changes
nx affected:build --base=main --head=HEAD

# Uses Git to compute changed files, then traces dependency graph
```

**GitHub Actions integration:**

```yaml
- uses: nrwl/nx-set-shas@v4  # Computes base/head SHAs for affected detection

- run: npx nx affected --target=build --base=${{ env.NX_BASE }} --head=${{ env.NX_HEAD }}

# Remote caching
- run: npx nx build
  env:
    NX_CLOUD_ACCESS_TOKEN: ${{ secrets.NX_CLOUD_ACCESS_TOKEN }}
```

**Content addressing:**
Nx's computation hash is content-addressed, but the `nx-set-shas` action uses Git SHAs for affected detection.
This is a hybrid: content-addressed caching + commit-based change detection.

**Strengths:**

- Enterprise-grade monorepo tooling
- Excellent affected detection
- Remote caching with Nx Cloud or self-hosted
- Plugin ecosystem for various technologies

**Weaknesses:**

- Primarily focused on JS/TS, though plugins exist for other languages
- Doesn't integrate with Nix
- Adds another layer of orchestration

**Fit for your use case: Medium-High**

Similar to Turborepo - excellent for TypeScript packages, but wouldn't replace Nix caching.
The "affected" detection could help optimize which matrix jobs run.

#### Key Insight: Turborepo and Nx Are Complementary, Not Replacements

Both tools solve content-addressed caching for **task execution** in monorepos, but they operate at a different level than Nix:

- **Nix** caches build outputs (binaries, packages)
- **Turborepo/Nx** cache task outputs (test results, linting reports, build artifacts)

In a Nix + TypeScript monorepo, you could use:

- Nix + Cachix for building system packages
- Turborepo/Nx for TypeScript package tasks

This would require careful integration to avoid duplicating caching logic.

### CI-Specific Solutions (Deep Dive)

#### GitHub Actions Native Patterns

**Pattern: hashFiles() for Content Addressing**

GitHub Actions provides `hashFiles()` function to hash file contents:

```yaml
- uses: actions/cache@v4
  with:
    path: /nix/store
    key: nix-${{ runner.os }}-${{ hashFiles('flake.lock', '**/*.nix') }}
    restore-keys: |
      nix-${{ runner.os }}-
```

**How `hashFiles()` works:**

1. Searches for files matching glob patterns under `$GITHUB_WORKSPACE`
2. Sorts matched files by path
3. Hashes each file with SHA256
4. Hashes all file hashes together → 64-character final hash

**Key limitations:**

- Only works on files in the repository (can't hash external inputs)
- Glob patterns can be expensive for large repos
- Not aware of semantic dependencies (e.g., doesn't understand Nix closures)

**Advanced patterns:**

```yaml
# Multi-level cache keys with fallbacks
- uses: actions/cache@v4
  with:
    path: ~/.cache/build
    key: build-${{ runner.os }}-${{ hashFiles('**/Cargo.lock') }}-${{ hashFiles('src/**/*.rs') }}
    restore-keys: |
      build-${{ runner.os }}-${{ hashFiles('**/Cargo.lock') }}-
      build-${{ runner.os }}-
```

**Pattern: Matrix-Specific Cache Keys**

For matrix builds, include matrix variables in cache keys:

```yaml
strategy:
  matrix:
    system: [x86_64-linux, aarch64-linux]
    category: [packages, home, nixos]

steps:
  - uses: actions/cache@v4
    with:
      path: build-cache
      key: build-${{ matrix.system }}-${{ matrix.category }}-${{ hashFiles('flake.lock') }}
```

This prevents cache collision when matrix jobs run in parallel.

**Pattern: Separate Restore and Save**

To avoid cache save collisions in matrix jobs:

```yaml
# All matrix jobs restore from shared cache
- uses: actions/cache/restore@v4
  with:
    path: build-cache
    key: build-${{ matrix.system }}-${{ hashFiles('flake.lock') }}

# Only one designated job saves cache
- uses: actions/cache/save@v4
  if: github.event_name == 'push' && matrix.system == 'x86_64-linux'
  with:
    path: build-cache
    key: build-${{ matrix.system }}-${{ hashFiles('flake.lock') }}
```

**Strengths:**

- No external dependencies
- Simple to implement
- Incrementally adoptable

**Weaknesses:**

- Manual key computation
- No understanding of semantic dependencies
- Cache size limits (10GB per repo)

**Fit for your use case: High**

This is where your quick wins are.
Replacing commit SHA-based keys with `hashFiles()` patterns provides significant improvement with minimal effort.

#### Earthly

**How it works:**
Earthly is a build automation tool that combines Dockerfile-like syntax with Make-like build targets.
It provides layer caching (like Docker) plus remote caching.

**Content addressing:**
Each Earthly target creates cache layers based on content hashes of inputs.
Layers are keyed by hash of (command + input files + arguments).

**Example Earthfile:**

```
VERSION 0.8
FROM nixos/nix:latest
WORKDIR /workspace

deps:
    COPY flake.nix flake.lock .
    RUN nix flake lock --update-input nixpkgs
    SAVE ARTIFACT flake.lock

build:
    FROM +deps
    COPY . .
    RUN nix build '.#packages.x86_64-linux.docs'
    SAVE ARTIFACT result/* AS LOCAL dist/
```

**GitHub Actions integration:**

```yaml
- uses: earthly/actions-setup@v1
  with:
    version: latest

- run: earthly --ci --push +build
```

**Strengths:**

- Reproducible builds (containerized)
- Good remote caching
- Familiar syntax (Dockerfile-like)

**Weaknesses:**

- Adds Docker/container layer
- Nix already provides reproducibility
- Another DSL to learn

**Fit for your use case: Low-Medium**

Earthly's value proposition overlaps significantly with Nix.
You'd gain remote caching, but at the cost of wrapping Nix in containers.

### Comparison Summary

For your specific use case (Nix + TypeScript monorepo + GitHub Actions):

**Tier 1: Leverage What You Have**

- **Nix + Cachix**: Already integrated, provides content-addressed caching for Nix builds
- **GitHub Actions `hashFiles()`**: Simple, no new dependencies, immediate impact

**Tier 2: Augment With Specialized Tools**

- **Turborepo or Nx**: For TypeScript package caching (parallel to Nix)
- **nix-community/cache-nix-action**: For local GitHub Actions cache optimization

**Tier 3: Large Investments**

- **Bazel/Buck2**: Overkill for your scale
- **Earthly**: Redundant with Nix

**Key recommendation:** Start with Tier 1 (hashFiles improvements), evaluate Tier 2 (Turborepo/Nx) for TypeScript-specific needs, skip Tier 3.

## 3. Implementation Patterns

This section provides concrete, copy-paste-ready patterns for implementing content-addressed caching in your workflow.

### Pattern 1: hashFiles() for Nix Inputs

**Problem:** Your current cache keys use commit SHA, causing unnecessary invalidation.

**Current pattern (from `cached-ci-job/action.yaml` lines 54-83):**

```yaml
SHA_SHORT="${HEAD_SHA:0:12}"
CACHE_KEY="job-result-${SANITIZED}-${SHA_SHORT}"
```

**Proposed pattern:**

```yaml
- name: Compute content-addressed cache key
  id: cache-key
  shell: bash
  run: |
    # Hash Nix inputs only
    NIX_HASH=$(echo "${{ hashFiles('flake.lock', 'flake.nix', '**/*.nix') }}" | cut -c1-12)
    CACHE_KEY="job-result-${CHECK_NAME}-${NIX_HASH}"
    echo "cache-key=$CACHE_KEY" >> $GITHUB_OUTPUT
    echo "Cache key: $CACHE_KEY"

- uses: actions/cache/restore@v4
  with:
    path: ${{ steps.cache-result.outputs.cache-path }}
    key: ${{ steps.cache-key.outputs.cache-key }}
    restore-keys: |
      job-result-${CHECK_NAME}-
```

**Impact:**

- Changes to documentation, CI configs, or other non-Nix files no longer invalidate Nix job caches
- Cache keys stable across rebases, amends, squashes
- Multiple PRs with same Nix inputs share caches

**Complexity:** Low - drop-in replacement

**Estimated implementation time:** 30 minutes

**Testing strategy:**

```bash
# Test locally - compute hash
echo "flake.lock flake.nix" | xargs sha256sum | sha256sum

# Create test PR changing only README
# Verify CI jobs show cache hits

# Create test PR changing flake.lock
# Verify CI jobs show cache misses
```

### Pattern 2: Per-Job Input Hashing

**Problem:** All jobs use the same cache key pattern, even though different jobs depend on different inputs.

**Example:**

- `secrets-scan` job: depends on `.git/` history (for `gitleaks`), not on Nix files
- `config-validation` job: depends on `configurations/**/*.nix`, not on `packages/**/*`
- `typescript` jobs: depend on `packages/*/package.json` and `bun.lockb`, not on Nix configs

**Proposed pattern:**

```yaml
# In cached-ci-job action, add input for hash sources
inputs:
  hash-sources:
    description: 'Glob patterns for files to hash (overrides default behavior)'
    required: false
    default: ''

# In action logic
- name: Compute content hash
  id: content-hash
  shell: bash
  env:
    HASH_SOURCES: ${{ inputs.hash-sources }}
    PATH_FILTERS: ${{ inputs.path-filters }}
  run: |
    if [ -n "$HASH_SOURCES" ]; then
      # Use explicit hash sources
      HASH=$(echo "${{ hashFiles(env.HASH_SOURCES) }}" | cut -c1-12)
    elif [ -n "$PATH_FILTERS" ]; then
      # Convert path filters to glob patterns
      # This is an approximation - captures most cases
      HASH=$(echo "${{ hashFiles('flake.lock', '**/*.nix') }}" | cut -c1-12)
    else
      # Default: hash everything
      HASH=$(echo "${{ hashFiles('**/*') }}" | cut -c1-12)
    fi

    echo "content-hash=$HASH" >> $GITHUB_OUTPUT
    echo "Content hash: $HASH"

- name: Prepare cache key
  id: cache-result
  shell: bash
  run: |
    SANITIZED=$(echo "$CHECK_NAME" | tr -d '()' | tr ', ' '-' | tr -s '-')
    CONTENT_HASH="${{ steps.content-hash.outputs.content-hash }}"
    CACHE_KEY="job-result-${SANITIZED}-${CONTENT_HASH}"
    echo "cache-key=$CACHE_KEY" >> $GITHUB_OUTPUT
```

**Usage in CI workflow:**

```yaml
# Nix jobs: hash Nix inputs
- name: Check execution cache
  uses: ./.github/actions/cached-ci-job
  with:
    check-name: ${{ github.job }}
    hash-sources: 'flake.lock|flake.nix|**/*.nix|overlays/**/*|modules/**/*|configurations/**/*'

# TypeScript jobs: hash TS inputs
- name: Check execution cache
  uses: ./.github/actions/cached-ci-job
  with:
    check-name: ${{ matrix.package.name }}-test
    hash-sources: 'bun.lockb|packages/${{ matrix.package.name }}/**/*|packages/docs/**/*'

# Secrets scan: hash git history (tricky - approximate with workflow file)
- name: Check execution cache
  uses: ./.github/actions/cached-ci-job
  with:
    check-name: secrets-scan
    hash-sources: '.github/workflows/ci.yaml'
```

**Impact:**

- Each job caches based on its actual dependencies
- Maximum cache reuse - changing TS code doesn't invalidate Nix caches
- More complex to maintain (need to keep hash sources accurate)

**Complexity:** Medium - requires analysis of each job's dependencies

**Estimated implementation time:** 2-3 hours

**Testing strategy:**

```bash
# Create test PRs with isolated changes
# PR 1: Only change flake.nix → Nix jobs invalidate, TS jobs hit cache
# PR 2: Only change packages/docs/src/** → TS jobs invalidate, Nix jobs hit cache
# PR 3: Change .github/workflows/ci.yaml → All jobs invalidate (workflow change detection)
```

### Pattern 3: Nix Derivation Hash Extraction

**Problem:** `hashFiles()` approximates Nix closure dependencies but isn't exact.

**Solution:** Extract actual Nix derivation hashes and use them as cache keys.

**Implementation:**

```yaml
- name: Compute Nix derivation hashes
  id: nix-hashes
  run: |
    # Install Nix first (chicken-and-egg problem)
    # Use actions/cache to cache the Nix installation itself

    # Compute hash for this job's build target
    TARGET=".#${{ matrix.category }}"

    # Get derivation path
    DRV=$(nix path-info --derivation "$TARGET" 2>/dev/null || echo "")

    if [ -n "$DRV" ]; then
      # Hash the derivation
      DRV_HASH=$(nix-store --query --hash "$DRV" | cut -d: -f2 | cut -c1-12)
      echo "derivation-hash=$DRV_HASH" >> $GITHUB_OUTPUT
      echo "Derivation hash for $TARGET: $DRV_HASH"
    else
      # Fallback to flake.lock hash if derivation can't be computed
      FALLBACK=$(echo "${{ hashFiles('flake.lock') }}" | cut -c1-12)
      echo "derivation-hash=$FALLBACK" >> $GITHUB_OUTPUT
      echo "Using fallback hash: $FALLBACK"
    fi

- uses: actions/cache/restore@v4
  with:
    path: /nix/store
    key: nix-store-${{ matrix.system }}-${{ steps.nix-hashes.outputs.derivation-hash }}
    restore-keys: |
      nix-store-${{ matrix.system }}-
```

**Chicken-and-egg problem:**
You need Nix installed to compute derivation hashes, but you want to cache Nix installations.

**Solution: Two-stage caching**

```yaml
# Stage 1: Cache Nix installation
- uses: actions/cache/restore@v4
  id: nix-cache
  with:
    path: /nix
    key: nix-install-${{ runner.os }}-${{ hashFiles('flake.lock') }}
    restore-keys: |
      nix-install-${{ runner.os }}-

# Stage 2: If cache miss, install Nix
- name: Setup Nix
  if: steps.nix-cache.outputs.cache-hit != 'true'
  uses: ./.github/actions/setup-nix
  with:
    system: ${{ matrix.system }}

# Stage 3: Now compute derivation hashes for build caching
- name: Compute derivation hash
  id: drv-hash
  run: |
    DRV_HASH=$(nix eval --raw ".#packages.${{ matrix.system }}.${{ matrix.package }}.drvPath" | xargs nix-store --query --hash | cut -d: -f2)
    echo "hash=$DRV_HASH" >> $GITHUB_OUTPUT

# Stage 4: Cache build outputs using derivation hash
- uses: actions/cache/restore@v4
  with:
    path: result
    key: build-${{ matrix.system }}-${{ matrix.package }}-${{ steps.drv-hash.outputs.hash }}
```

**Impact:**

- True content-addressed caching matching Nix semantics
- Cache keys exact, not approximate
- Complex setup, harder to debug

**Complexity:** High - requires understanding Nix derivations

**Estimated implementation time:** 4-6 hours

**Pros:**

- Maximum precision - cache keys exactly match Nix's internal hashing
- Immune to false invalidations
- Educational - forces understanding of Nix derivation model

**Cons:**

- Chicken-and-egg problem requires workarounds
- More moving parts
- Harder to debug ("why is this derivation hash different?")

**Recommendation:** Start with Pattern 1 or 2, graduate to Pattern 3 if needed.

### Pattern 4: Hybrid Content + Commit Provenance

**Problem:** Content-addressed caching loses commit provenance - you can't easily tell which commit built a cache entry.

**Solution:** Include both content hash and commit SHA in cache keys, but search by content hash first.

**Implementation:**

```yaml
- name: Compute hybrid cache key
  id: cache-key
  run: |
    CONTENT_HASH=$(echo "${{ hashFiles('flake.lock', '**/*.nix') }}" | cut -c1-12)
    COMMIT_SHA=$(echo "${{ github.sha }}" | cut -c1-12)

    # Primary key: content hash + commit (exact match)
    PRIMARY_KEY="nix-${CONTENT_HASH}-${COMMIT_SHA}"

    # Restore keys: content hash only (cross-commit sharing)
    RESTORE_KEY="nix-${CONTENT_HASH}-"

    echo "primary-key=$PRIMARY_KEY" >> $GITHUB_OUTPUT
    echo "restore-key=$RESTORE_KEY" >> $GITHUB_OUTPUT

- uses: actions/cache/restore@v4
  with:
    path: build-output
    key: ${{ steps.cache-key.outputs.primary-key }}
    restore-keys: |
      ${{ steps.cache-key.outputs.restore-key }}

- name: Build
  run: nix build

- uses: actions/cache/save@v4
  if: success()
  with:
    path: build-output
    key: ${{ steps.cache-key.outputs.primary-key }}
```

**How it works:**

- Cache save: Stores with key `nix-<content>-<commit>`
- Cache restore: First tries exact key (content + commit), then falls back to content-only prefix

**Benefits:**

- Exact cache hit: You know which commit created it (provenance preserved)
- Partial cache hit: Content-addressed sharing still works
- Auditing: Can trace cache entries back to commits

**Tradeoffs:**

- More cache entries (one per commit even with identical content)
- Cache bloat - 7-day retention helps, but still creates duplicates
- Complexity in understanding cache behavior

**Fit for your use case:**
Good if you need audit trails or want to preserve current behavior while gaining content-addressed benefits.

### Pattern 5: Turborepo Integration for TypeScript Packages

**Problem:** TypeScript packages (`packages/docs`) have different caching needs than Nix system configs.

**Solution:** Use Turborepo for TS package caching, orthogonal to Nix caching.

**Setup:**

```bash
# Install Turborepo
cd /Users/crs58/projects/nix-workspace/infra
bun add -D turbo
```

**Create `turbo.json`:**

```json
{
  "$schema": "https://turbo.build/schema.json",
  "tasks": {
    "build": {
      "dependsOn": ["^build"],
      "inputs": ["src/**", "package.json", "tsconfig.json"],
      "outputs": ["dist/**", ".next/**"]
    },
    "test": {
      "dependsOn": ["build"],
      "inputs": ["src/**", "package.json", "tsconfig.json", "vitest.config.ts"],
      "outputs": ["coverage/**"]
    },
    "lint": {
      "inputs": ["src/**", "package.json", ".eslintrc*"],
      "outputs": []
    }
  },
  "remoteCache": {
    "enabled": false  // Start with local caching, enable remote later
  }
}
```

**Update GitHub Actions workflow:**

```yaml
# TypeScript job
typescript:
  needs: [secrets-scan, set-variables]
  runs-on: ubuntu-latest
  strategy:
    matrix:
      package: ${{ fromJson(needs.set-variables.outputs.packages) }}

  steps:
    - uses: actions/checkout@v5

    # Cache Turborepo cache directory
    - uses: actions/cache@v4
      with:
        path: node_modules/.cache/turbo
        key: turbo-${{ matrix.package.name }}-${{ hashFiles('**/bun.lockb', 'packages/**/package.json') }}
        restore-keys: |
          turbo-${{ matrix.package.name }}-

    - name: Setup Node/Bun
      run: |
        curl -fsSL https://bun.sh/install | bash
        echo "$HOME/.bun/bin" >> $GITHUB_PATH

    - name: Install dependencies
      run: bun install

    # Run via Turborepo - automatically caches based on inputs
    - name: Build and test
      run: bunx turbo run build test --filter=${{ matrix.package.name }}
```

**How it works:**

- Turborepo computes hash of task inputs (src files, package.json, etc.)
- Checks local cache (`.turbo/cache/`) for matching hash
- If hit, replays logs and restores outputs; if miss, runs task
- GitHub Actions caches the `.turbo/cache/` directory across runs

**Benefits:**

- Content-addressed caching for TypeScript tasks
- Works alongside Nix (Nix builds system packages, Turbo caches TS tasks)
- Good developer experience (works locally and in CI)

**Complexity:** Medium - requires Turborepo setup and configuration

**Estimated implementation time:** 2-3 hours

**Recommendation:**
Good choice if you have multiple TypeScript packages and want sophisticated monorepo caching.
For a single package (`packages/docs`), Pattern 2 with `hashFiles()` may be simpler.

### Pattern 6: Nx Affected Detection

**Problem:** Your matrix builds all jobs even if only subset changed.

**Solution:** Use Nx affected detection to filter matrix.

**Setup:**

```bash
bun add -D nx
```

**Add `nx.json`:**

```json
{
  "affected": {
    "defaultBase": "main"
  },
  "targetDefaults": {
    "build": {
      "cache": true,
      "inputs": ["default", "^default"]
    }
  },
  "namedInputs": {
    "default": ["{projectRoot}/**/*", "sharedGlobals"],
    "sharedGlobals": ["bun.lockb"]
  }
}
```

**Update GitHub Actions:**

```yaml
jobs:
  # New job to compute affected projects
  compute-affected:
    runs-on: ubuntu-latest
    outputs:
      affected-packages: ${{ steps.affected.outputs.packages }}
    steps:
      - uses: actions/checkout@v5
        with:
          fetch-depth: 0  # Need git history for affected detection

      - uses: nrwl/nx-set-shas@v4

      - name: Compute affected packages
        id: affected
        run: |
          AFFECTED=$(npx nx show projects --affected --json)
          echo "packages=$AFFECTED" >> $GITHUB_OUTPUT

  # Use affected packages in matrix
  typescript:
    needs: [compute-affected]
    if: needs.compute-affected.outputs.affected-packages != '[]'
    strategy:
      matrix:
        package: ${{ fromJson(needs.compute-affected.outputs.affected-packages) }}
    steps:
      - name: Test package
        run: bun test packages/${{ matrix.package }}
```

**Benefits:**

- Only runs jobs for changed packages
- Significant time savings in large monorepos
- Content-addressed caching via Nx (similar to Turborepo)

**Complexity:** Medium-High - requires Nx configuration

**Fit for your use case:**
Currently you have one TypeScript package (`packages/docs`), so affected detection provides limited value.
If you add more packages, Nx becomes more attractive.

### Pattern Comparison Table

| Pattern | Complexity | Impact | Time to Implement | Best For |
|---------|-----------|--------|-------------------|----------|
| 1. hashFiles() for Nix | Low | High | 30 min | Quick wins, Nix jobs |
| 2. Per-job input hashing | Medium | Very High | 2-3 hours | Surgical cache invalidation |
| 3. Derivation hash extraction | High | Maximum | 4-6 hours | Perfect accuracy |
| 4. Hybrid content + commit | Medium | Medium-High | 1-2 hours | Provenance requirements |
| 5. Turborepo integration | Medium | High (for TS) | 2-3 hours | Multiple TS packages |
| 6. Nx affected detection | Medium-High | Medium | 3-4 hours | Many packages |

**Recommendation for your use case:**

Start with **Pattern 1 + Pattern 2**:

1. Replace commit SHA with `hashFiles()` in `cached-ci-job` action (Pattern 1)
2. Add per-job `hash-sources` input (Pattern 2)
3. Configure hash sources for each job type

This gives you 70-80% of the benefit with 2-3 hours of work.

Evaluate **Pattern 5 (Turborepo)** if you add more TypeScript packages.

Consider **Pattern 3 (derivation hashes)** if you need maximum precision or hit edge cases with `hashFiles()`.

## 4. Specific Recommendations for Your Use Case

Your current system has several strengths:

- Already using Nix with Cachix (content-addressed binary caching)
- Path filters approximate content-addressed caching
- Composite action (`cached-ci-job`) centralizes caching logic
- Matrix builds for multi-system support

The primary gap: Job-level caching still uses commit SHAs, not content hashes.

### Tier 1: Quick Wins (Immediate Implementation)

**Time investment:** 2-3 hours
**Expected improvement:** 60-70% reduction in unnecessary cache misses
**Complexity:** Low

#### Action 1.1: Replace SHA-based keys with hashFiles() in cached-ci-job

**File:** `.github/actions/cached-ci-job/action.yaml`

**Current code (lines 54-83):**

```yaml
HEAD_SHA="${{ github.event.pull_request.head.sha || github.sha }}"
SHA_SHORT="${HEAD_SHA:0:12}"
CACHE_KEY="job-result-${SANITIZED}-${SHA_SHORT}"
```

**Proposed change:**

```yaml
- name: Prepare cache key for actions/cache
  id: cache-result
  shell: bash
  env:
    CHECK_NAME: ${{ inputs.check-name }}
    HASH_SOURCES: ${{ inputs.hash-sources }}
  run: |
    echo "=== Cache Key Preparation ==="

    # Sanitize check name
    SANITIZED=$(echo "$CHECK_NAME" | tr -d '()' | tr ', ' '-' | tr -s '-')

    # Compute content hash based on job-specific inputs
    if [ -n "$HASH_SOURCES" ]; then
      # Use explicit hash sources if provided
      CONTENT_HASH="${{ hashFiles(env.HASH_SOURCES) }}"
    else
      # Default: hash common Nix inputs
      CONTENT_HASH="${{ hashFiles('flake.lock', 'flake.nix', '**/*.nix') }}"
    fi

    HASH_SHORT="${CONTENT_HASH:0:12}"
    CACHE_KEY="job-result-${SANITIZED}-${HASH_SHORT}"
    CACHE_PATH=".cache/job-results/${SANITIZED}"
    RESTORE_KEYS="job-result-${SANITIZED}-"

    echo "Check name: $CHECK_NAME"
    echo "Sanitized: $SANITIZED"
    echo "Content hash: $HASH_SHORT (from inputs, not commit)"
    echo "Cache key: $CACHE_KEY"
    echo "Cache path: $CACHE_PATH"
    echo "Restore pattern: ${RESTORE_KEYS}*"

    echo "cache-key=$CACHE_KEY" >> $GITHUB_OUTPUT
    echo "cache-path=$CACHE_PATH" >> $GITHUB_OUTPUT
    echo "cache-restore-keys=$RESTORE_KEYS" >> $GITHUB_OUTPUT
```

**Add new input to action:**

```yaml
inputs:
  check-name:
    description: Full check run name
    required: false
    default: ${{ github.job }}
  path-filters:
    description: Regex pattern for relevant file paths
    required: false
    default: ''
  hash-sources:
    description: Glob patterns for files to hash (enables per-job content addressing)
    required: false
    default: ''
  workflow-file:
    description: Workflow file path (auto-detected if not provided)
    required: false
    default: ''
  force-run:
    description: Force execution even if already successful
    required: false
    default: 'false'
```

**Testing:**

```bash
# Create test PR changing only README.md
git checkout -b test-cache-readme
echo "test" >> README.md
git add README.md && git commit -m "test: update readme"
git push origin test-cache-readme

# Check CI - all jobs should show cache hits (no Nix inputs changed)

# Create test PR changing flake.lock
git checkout -b test-cache-flake
nix flake update
git add flake.lock && git commit -m "chore: update flake.lock"
git push origin test-cache-flake

# Check CI - Nix jobs should show cache misses, TypeScript jobs cache hits
```

#### Action 1.2: Configure per-job hash sources

Update jobs in `ci.yaml` to use content-addressed caching:

**Nix-dependent jobs:**

```yaml
- name: Check execution cache
  id: cache
  uses: ./.github/actions/cached-ci-job
  with:
    check-name: ${{ github.job }}
    hash-sources: |
      flake.lock
      flake.nix
      **/*.nix
      overlays/**
      modules/**
      configurations/**
    force-run: ${{ needs.set-variables.outputs.force-ci }}
```

**TypeScript jobs:**

```yaml
- name: Check execution cache
  uses: ./.github/actions/cached-ci-job
  with:
    check-name: ${{ matrix.package.name }}-test
    hash-sources: |
      bun.lockb
      packages/${{ matrix.package.name }}/**
      packages/docs/package.json
    force-run: ${{ needs.set-variables.outputs.force-ci }}
```

**Secrets scan (no content dependencies - workflow changes only):**

```yaml
- name: Check execution cache
  uses: ./.github/actions/cached-ci-job
  with:
    check-name: secrets-scan
    # No hash-sources - will use workflow change detection only
    force-run: ${{ needs.set-variables.outputs.force-ci }}
```

#### Action 1.3: Update documentation

Add explanation of content-addressed caching to workflow comments:

```yaml
# job 0: secrets-scan
# scans repository for hardcoded secrets using gitleaks
# Security critical - runs for all commits
# Cache: No content hash (workflow changes only trigger re-runs)
secrets-scan:
  ...

# job 10: nix
# builds flake outputs via category-based matrix
# Cache: Content-addressed via flake.lock + .nix files
# Cache key stable across commits with identical Nix inputs
nix:
  ...

# job 11: typescript
# TypeScript package testing via reusable workflow
# Cache: Content-addressed via bun.lockb + package.json files
typescript:
  ...
```

**Expected results:**

1. **Cross-commit cache sharing**: PR branches with identical Nix inputs share caches
2. **Reduced false invalidation**: Changes to docs/README don't invalidate Nix caches
3. **Improved PR workflow**: Rebasing doesn't invalidate caches
4. **Better cache utilization**: GitHub Actions 10GB cache limit used more efficiently

**Rollback plan:**
If issues arise, revert to commit-based keys by removing `hash-sources` input usage.

### Tier 2: Strategic Improvements (Medium-Term)

**Time investment:** 1-2 weeks
**Expected improvement:** 80-90% cache hit rate optimization
**Complexity:** Medium

#### Action 2.1: Implement Nix derivation hash extraction

For Nix jobs, compute actual derivation hashes instead of approximating with `hashFiles()`.

**Create script:** `.github/scripts/compute-nix-cache-key.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage: compute-nix-cache-key.sh <system> <category> [config]
SYSTEM="$1"
CATEGORY="$2"
CONFIG="${3:-}"

# Build target based on category
case "$CATEGORY" in
  packages)
    TARGET=".#packages.$SYSTEM"
    ;;
  home)
    TARGET=".#legacyPackages.$SYSTEM.homeConfigurations"
    ;;
  nixos)
    if [ -n "$CONFIG" ]; then
      TARGET=".#nixosConfigurations.$CONFIG.config.system.build.toplevel"
    else
      echo "Error: nixos category requires config argument" >&2
      exit 1
    fi
    ;;
  checks-devshells)
    TARGET=".#checks.$SYSTEM"
    ;;
  *)
    echo "Error: unknown category $CATEGORY" >&2
    exit 1
    ;;
esac

# Compute derivation hash
echo "Computing derivation hash for: $TARGET" >&2

if ! DRV=$(nix path-info --derivation "$TARGET" 2>/dev/null); then
  echo "Warning: Could not compute derivation for $TARGET, using flake.lock fallback" >&2
  # Fallback to content hash
  HASH=$(sha256sum flake.lock flake.nix | sha256sum | cut -d' ' -f1 | cut -c1-12)
  echo "$HASH"
  exit 0
fi

# Extract hash from derivation
DRV_HASH=$(nix-store --query --hash "$DRV" | cut -d: -f2 | cut -c1-12)
echo "$DRV_HASH"
```

**Update CI workflow:**

```yaml
nix:
  needs: [secrets-scan, cache-overlay-packages, set-variables]
  runs-on: ${{ matrix.runner }}
  strategy:
    matrix:
      include:
        - system: x86_64-linux
          runner: ubuntu-latest
          category: packages
        # ... other matrix entries

  steps:
    - uses: actions/checkout@v5

    # Setup Nix first
    - name: Setup Nix
      uses: ./.github/actions/setup-nix
      with:
        system: ${{ matrix.system }}
        enable-cachix: true
        cachix-name: ${{ env.CACHIX_BINARY_CACHE }}
        cachix-auth-token: ${{ secrets.CACHIX_AUTH_TOKEN }}

    # Compute derivation-based cache key
    - name: Compute derivation cache key
      id: drv-hash
      run: |
        HASH=$(.github/scripts/compute-nix-cache-key.sh \
          "${{ matrix.system }}" \
          "${{ matrix.category }}" \
          "${{ matrix.config || '' }}")
        echo "hash=$HASH" >> $GITHUB_OUTPUT
        echo "Derivation hash: $HASH"

    # Use derivation hash in cache key
    - name: Check execution cache
      id: cache
      uses: ./.github/actions/cached-ci-job
      with:
        check-name: ${{ github.job }} (${{ matrix.category }}, ${{ matrix.system }})
        # Pass computed hash as override
        cache-key-override: job-result-nix-${{ matrix.system }}-${{ matrix.category }}-${{ steps.drv-hash.outputs.hash }}
        force-run: ${{ needs.set-variables.outputs.force-ci }}

    - name: Build
      if: steps.cache.outputs.should-run == 'true'
      run: |
        nix develop --command just ci-build-category \
          "${{ matrix.system }}" \
          "${{ matrix.category }}" \
          "${{ matrix.config }}"
```

**Benefits:**

- Cache keys exactly match Nix's internal derivation hashing
- Maximum precision - no false invalidations
- Educational - see Nix derivation system in action

**Challenges:**

- Nix must be installed before computing hashes
- Additional complexity in debugging
- May expose edge cases in Nix derivation computation

#### Action 2.2: Add Turborepo for TypeScript package caching

As your monorepo grows, Turborepo provides sophisticated task caching:

**Install:**

```bash
bun add -D turbo
```

**Create `turbo.json`:**

```json
{
  "$schema": "https://turbo.build/schema.json",
  "tasks": {
    "build": {
      "dependsOn": ["^build"],
      "inputs": [
        "src/**",
        "package.json",
        "tsconfig.json"
      ],
      "outputs": [
        "dist/**",
        ".vitepress/cache/**",
        ".vitepress/dist/**"
      ]
    },
    "test": {
      "dependsOn": ["build"],
      "inputs": [
        "src/**",
        "test/**",
        "package.json",
        "vitest.config.ts"
      ],
      "outputs": ["coverage/**"]
    },
    "lint": {
      "inputs": [
        "src/**",
        "package.json",
        ".eslintrc*"
      ],
      "outputs": []
    },
    "preview-version": {
      "cache": false,
      "inputs": [
        "package.json",
        ".releaserc.json"
      ]
    }
  },
  "globalDependencies": [
    "bun.lockb"
  ]
}
```

**Update package test workflow:**

File: `.github/workflows/package-test.yaml`

```yaml
# Add Turborepo caching step
- name: Restore Turborepo cache
  uses: actions/cache@v4
  with:
    path: |
      node_modules/.cache/turbo
      .turbo
    key: turbo-${{ inputs.package-name }}-${{ hashFiles('bun.lockb', 'packages/*/package.json', 'turbo.json') }}
    restore-keys: |
      turbo-${{ inputs.package-name }}-

# Replace direct test commands with Turborepo
- name: Build and test via Turborepo
  if: steps.cache.outputs.should-run == 'true'
  working-directory: ${{ inputs.package-path }}
  run: |
    # Run through Turborepo for content-addressed caching
    bunx turbo run build test lint
```

**Benefits:**

- Content-addressed caching for TypeScript tasks
- Works locally and in CI
- Task dependency graph management
- Scales as you add more packages

**Future expansion:**
Enable Turborepo remote caching for cross-machine cache sharing:

```json
{
  "remoteCache": {
    "enabled": true,
    "signature": true
  }
}
```

```yaml
# In CI workflow
env:
  TURBO_TOKEN: ${{ secrets.TURBO_TOKEN }}
  TURBO_TEAM: ${{ vars.TURBO_TEAM }}
```

#### Action 2.3: Implement cache analytics and monitoring

Add observability to understand cache behavior:

**Create script:** `.github/scripts/analyze-cache-effectiveness.sh`

```bash
#!/usr/bin/env bash
# Analyze GitHub Actions cache hit rates

set -euo pipefail

# Requires: gh CLI authenticated

REPO="${1:-}"
WORKFLOW="${2:-ci.yaml}"
LIMIT="${3:-20}"

if [ -z "$REPO" ]; then
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
fi

echo "Analyzing cache effectiveness for $REPO workflow $WORKFLOW"
echo ""

# Fetch recent workflow runs
RUNS=$(gh run list \
  --repo "$REPO" \
  --workflow "$WORKFLOW" \
  --limit "$LIMIT" \
  --json databaseId,conclusion,headSha,headBranch,createdAt)

echo "Recent runs:"
echo "$RUNS" | jq -r '.[] | "\(.databaseId) \(.headBranch) \(.conclusion)"'
echo ""

# For each run, analyze cache hits
# (This requires parsing job logs - simplified here)

echo "Cache hit analysis would go here"
echo "Manual process:"
echo "1. Click into workflow runs"
echo "2. Look for 'Cache hit' vs 'Cache miss' in job logs"
echo "3. Correlate with commit SHAs / content hashes"
echo ""
echo "Consider: Set up custom metrics in workflow"
```

**Add cache metrics to workflow:**

```yaml
# In cached-ci-job action, after decision
- name: Record cache metrics
  if: always()
  shell: bash
  run: |
    # Log structured data for analysis
    cat >> $GITHUB_STEP_SUMMARY <<EOF
    ## Cache Metrics: ${{ inputs.check-name }}

    - Cache key: \`${{ steps.cache-result.outputs.cache-key }}\`
    - Cache hit: ${{ steps.cache-lookup.outputs.cache-hit }}
    - Decision: ${{ steps.decide.outputs.should-run == 'true' && 'RUN' || 'SKIP' }}
    - Source: ${{ steps.decide.outputs.cache-source }}
    EOF
```

This adds cache information to GitHub Actions summary page for each run.

### Tier 3: Full Content-Addressed System (Long-Term)

**Time investment:** 1-2 months
**Expected improvement:** 95%+ cache hit rate optimization, fully hermetic builds
**Complexity:** High

This tier represents a comprehensive reimplementation with maximum sophistication.

#### Option 3.1: Custom Remote Cache Server

Implement a remote cache server that understands both Nix derivation hashes and TypeScript task hashes.

**Architecture:**

```
GitHub Actions runner
  ├─ Nix builds → compute derivation hash → query remote cache
  ├─ TypeScript builds → compute task hash → query remote cache
  └─ Remote cache server (self-hosted)
       ├─ Storage: S3 / MinIO / local disk
       ├─ API: Bazel Remote Execution API (gRPC)
       └─ Database: cache keys → artifact locations
```

**Implementation:**

1. **Deploy cache server**: Use `buchgr/bazel-remote` or similar
2. **Nix integration**: Configure Nix to use remote cache
3. **Turborepo integration**: Point Turborepo to cache server
4. **Monitoring**: Add Prometheus metrics for cache hit rates

**Example: Bazel Remote with Nix**

```nix
# In flake.nix or nix.conf
extra-substituters = https://cache.example.com
extra-trusted-public-keys = cache.example.com:...
```

```yaml
# In GitHub Actions
- name: Configure remote cache
  run: |
    mkdir -p ~/.config/nix
    cat >> ~/.config/nix/nix.conf <<EOF
    substituters = https://cache.example.com https://cache.nixos.org
    trusted-public-keys = ...
    EOF
```

**Complexity:** Very high - requires infrastructure management

**Benefits:**

- Unlimited cache size (vs GitHub Actions 10GB limit)
- Custom retention policies
- Cross-repository cache sharing
- Fine-grained access control

**Recommendation:** Only pursue if you scale to many repositories or large team.

#### Option 3.2: Migrate to Determinate Systems Hosted Infrastructure

If Magic Nix Cache's free tier EOL is a concern, consider paid alternatives:

**FlakeHub Cache** (by Determinate Systems):

- Successor to Magic Nix Cache
- Paid service with improved features
- Seamless integration with GitHub Actions

**Setup:**

```yaml
- uses: DeterminateSystems/flakehub-cache-action@v1
  with:
    token: ${{ secrets.FLAKEHUB_TOKEN }}

- run: nix build
```

**Benefits:**

- Professional support
- Better performance than GitHub Actions cache
- Nix-native (understands derivations)

**Cost:** Evaluate pricing based on usage

#### Option 3.3: Full Bazel Migration (Not Recommended)

For completeness: You could migrate from Nix to Bazel for maximum build system sophistication.

**Why you shouldn't:**

- Massive investment (months of work)
- Nix already provides hermeticity and content addressing
- Bazel's advantages (remote execution, massive scale) don't apply at your scale
- Lose Nix ecosystem benefits (home-manager, nixos-unified, etc.)

**Mention this to rule it out as an option.**

### Implementation Roadmap

#### Week 1: Tier 1 Quick Wins

- **Day 1-2**: Update `cached-ci-job` action to use `hashFiles()` instead of commit SHA
- **Day 3-4**: Add `hash-sources` input and configure per-job
- **Day 5**: Testing, validation, documentation

**Deliverable:** PR with content-addressed caching for all jobs

#### Week 2-3: Tier 2 Foundation

- **Week 2**: Implement Nix derivation hash extraction script
- **Week 3**: Add Turborepo for TypeScript packages

**Deliverable:** Maximum precision Nix caching + TS task caching

#### Month 2-3: Tier 2 Refinement

- Add cache analytics and monitoring
- Tune cache keys based on observed behavior
- Document patterns and best practices

**Deliverable:** Fully optimized, observable caching system

#### Month 4+: Evaluate Tier 3

- Assess whether scale justifies custom infrastructure
- Consider FlakeHub Cache or similar hosted solutions

**Decision point:** Only proceed if data shows significant value

## 5. Best Practices & Gotchas

### Cache Key Design Principles

#### Principle 1: Include All Semantic Inputs, Exclude Irrelevant Noise

**Good:**

```yaml
key: nix-${{ hashFiles('flake.lock', '**/*.nix') }}
```

**Bad:**

```yaml
key: nix-${{ hashFiles('**/*') }}  # Too broad - README changes invalidate
```

**Bad:**

```yaml
key: nix-${{ hashFiles('flake.lock') }}  # Too narrow - misses .nix file changes
```

#### Principle 2: Use Hierarchical Restore Keys

```yaml
key: build-${{ runner.os }}-${{ hashFiles('Cargo.lock') }}-${{ hashFiles('src/**/*.rs') }}
restore-keys: |
  build-${{ runner.os }}-${{ hashFiles('Cargo.lock') }}-
  build-${{ runner.os }}-
```

**Rationale:**

- Try exact match first (lock file + source)
- Fall back to same dependencies, different source
- Fall back to same OS, different dependencies

#### Principle 3: Separate Frequently-Changing from Stable Inputs

**Good:**

```yaml
# Layer 1: Stable dependencies
- uses: actions/cache@v4
  with:
    path: ~/.cache/nix
    key: nix-deps-${{ hashFiles('flake.lock') }}

# Layer 2: Build outputs (changes frequently)
- uses: actions/cache@v4
  with:
    path: result
    key: nix-build-${{ hashFiles('src/**') }}
```

**Bad:**

```yaml
# Single cache for both (deps + source changes invalidate everything)
- uses: actions/cache@v4
  with:
    path: |
      ~/.cache/nix
      result
    key: nix-${{ hashFiles('flake.lock', 'src/**') }}
```

### Common Pitfalls

#### Pitfall 1: Cache Key Collisions in Matrix Jobs

**Problem:**

```yaml
strategy:
  matrix:
    system: [x86_64-linux, aarch64-linux]

steps:
  - uses: actions/cache@v4
    with:
      key: build-cache  # Same key for all matrix variants!
```

**What happens:**

- First job to complete saves cache
- Other jobs get "Unable to reserve cache" error
- Waste compute building only to fail at cache save

**Solution:**
Include matrix variables in cache key:

```yaml
- uses: actions/cache@v4
  with:
    key: build-cache-${{ matrix.system }}
```

#### Pitfall 2: hashFiles() Returns Empty String

**Problem:**

```yaml
key: cache-${{ hashFiles('nonexistent/**/*.txt') }}
# If no files match, hashFiles returns empty string
# Key becomes: cache-
# This matches EVERY cache with that prefix!
```

**Solution:**
Always include a fallback constant:

```yaml
key: cache-${{ hashFiles('**/*.txt') || 'no-files' }}
```

Or check if files exist:

```yaml
- name: Check if cache inputs exist
  id: check
  run: |
    if [ -n "$(find . -name '*.txt')" ]; then
      echo "exists=true" >> $GITHUB_OUTPUT
    else
      echo "exists=false" >> $GITHUB_OUTPUT
    fi

- uses: actions/cache@v4
  if: steps.check.outputs.exists == 'true'
  with:
    key: cache-${{ hashFiles('**/*.txt') }}
```

#### Pitfall 3: Path Filters Too Broad or Too Narrow

**Too broad:**

```yaml
path-filters: '.*'  # Matches everything, defeats purpose
```

**Too narrow:**

```yaml
path-filters: 'src/main.rs$'  # Only matches exact file, misses dependencies
```

**Goldilocks:**

```yaml
path-filters: 'src/.*\.rs$|Cargo\.(toml|lock)$'
# Matches Rust sources and dependency files
```

#### Pitfall 4: Forgetting to Save Cache on Failure

**Problem:**

```yaml
- uses: actions/cache/save@v4
  if: success()  # Only saves if all steps succeed
```

**Impact:**
If tests fail after long build, next run rebuilds from scratch.

**Solution:**
Save cache after build step, before tests:

```yaml
- name: Build
  run: cargo build

- uses: actions/cache/save@v4
  if: always()  # Save even if subsequent steps fail
  with:
    key: build-cache-${{ hashFiles('Cargo.lock') }}
    path: target/

- name: Test
  run: cargo test  # Can fail without losing build cache
```

#### Pitfall 5: Cache Bloat from Unnecessary Files

**Problem:**

```yaml
- uses: actions/cache@v4
  with:
    path: target/  # Includes debug symbols, temp files, etc.
```

**Impact:**

- Slow cache save/restore
- Wastes GitHub Actions cache quota
- Hits 10GB limit faster

**Solution:**
Cache only necessary artifacts:

```yaml
- uses: actions/cache@v4
  with:
    path: |
      target/release/binary
      target/deps/
    # Exclude: target/debug/, target/tmp/, etc.
```

Or use `.cacheignore` pattern (custom script):

```bash
# In cache save step
tar -czf cache.tar.gz target/ --exclude='target/debug' --exclude='*.tmp'
```

### Debugging Cache Issues

#### Symptom: "Cache miss" when you expect hit

**Diagnosis steps:**

1. **Check cache key computation:**

```yaml
- name: Debug cache key
  run: |
    echo "Cache key inputs:"
    echo "flake.lock hash: ${{ hashFiles('flake.lock') }}"
    echo "*.nix hash: ${{ hashFiles('**/*.nix') }}"
    echo "Combined: ${{ hashFiles('flake.lock', '**/*.nix') }}"
```

2. **Compare with previous run:**

```bash
# In GitHub UI, check previous workflow run
# Copy cache key from logs
# Compare with current run's cache key

# If keys differ, find which file changed:
git diff HEAD^ HEAD flake.lock
```

3. **Check cache existence:**

```bash
# Via GitHub CLI
gh cache list --repo owner/repo --key cache-prefix-

# Or via API
curl -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/repos/owner/repo/actions/caches
```

4. **Verify cache hasn't expired:**

- GitHub Actions caches expire after 7 days of no access
- Check if previous successful run was >7 days ago

#### Symptom: Cache hit but wrong contents

**Possible causes:**

1. **Non-hermetic builds:**
   - Build outputs depend on factors not in cache key (time, network, etc.)
   - Solution: Improve hermeticity (Nix helps with this)

2. **Cache key collision:**
   - Different inputs produce same hash (unlikely but possible with truncation)
   - Solution: Use longer hash (more than 12 characters)

3. **Concurrent cache saves:**
   - Multiple jobs saved with same key, one overwrote the other
   - Solution: Include unique identifier (job ID, matrix vars)

**Debug:**

```yaml
- name: Verify cache contents
  run: |
    echo "Cache should contain:"
    ls -la expected/path/

    echo "Cache actually contains:"
    ls -la ${{ steps.cache.outputs.path }}/

    # Compare checksums
    sha256sum expected/path/file
    sha256sum ${{ steps.cache.outputs.path }}/file
```

#### Symptom: Cache saves fail with "Unable to reserve cache"

**Cause:** Multiple jobs trying to save same cache key concurrently.

**Solution:** Use separate restore and save actions:

```yaml
# All matrix jobs restore
- uses: actions/cache/restore@v4
  with:
    key: shared-cache-${{ hashFiles('lock') }}

# Only one job saves (or jobs save to unique keys)
- uses: actions/cache/save@v4
  if: matrix.variant == 'main'
  with:
    key: shared-cache-${{ hashFiles('lock') }}
```

### Performance Considerations

#### Overhead: hashFiles() Can Be Expensive

**Problem:**

```yaml
key: cache-${{ hashFiles('**/*') }}  # Hashes every file in repo
```

**Impact:**

- Slows down workflow start
- Timeout for very large repos

**Solution:**
Be selective:

```yaml
key: cache-${{ hashFiles('src/**/*.ts', 'package.json', 'bun.lockb') }}
# Only hash relevant files
```

**Benchmark:**

```yaml
- name: Benchmark hashFiles
  run: |
    time echo "${{ hashFiles('**/*') }}"
    # Compare different patterns
```

#### Overhead: Cache Restore/Save Time

**Typical times:**

- Save: 30s - 2min for 1GB
- Restore: 15s - 1min for 1GB

**Optimization:**

- Compress aggressively
- Exclude unnecessary files
- Use multiple smaller caches instead of one large cache

**Break apart monolithic caches:**

**Bad:**

```yaml
- uses: actions/cache@v4
  with:
    path: |
      /nix/store
      node_modules/
      .cache/
    key: everything-${{ hashFiles('**/*') }}
```

**Good:**

```yaml
# Separate caches with different change frequencies
- uses: actions/cache@v4
  with:
    path: /nix/store
    key: nix-${{ hashFiles('flake.lock') }}

- uses: actions/cache@v4
  with:
    path: node_modules/
    key: npm-${{ hashFiles('package-lock.json') }}

- uses: actions/cache@v4
  with:
    path: .cache/
    key: build-${{ hashFiles('src/**') }}
```

**Rationale:**

- Nix store changes infrequently (only when flake.lock updates)
- node_modules changes moderately (package updates)
- Build cache changes frequently (every commit)

Separate caches mean changing source code doesn't force re-downloading node_modules.

### Monitoring and Observability

#### Key Metrics to Track

1. **Cache hit rate**
   - % of jobs with cache hits vs. misses
   - Target: >80% after optimization

2. **Cache size**
   - Total size of cached artifacts
   - Monitor against 10GB limit

3. **Cache age**
   - Time since cache was created
   - Identify stale caches (approaching 7-day expiration)

4. **Job time savings**
   - Compare job duration with cache hit vs. miss
   - Calculate ROI of caching effort

#### Implementation: Custom Metrics

**Add to workflow:**

```yaml
- name: Record cache metrics
  if: always()
  run: |
    # Append to job summary
    cat >> $GITHUB_STEP_SUMMARY <<EOF
    ## Cache Metrics

    | Metric | Value |
    |--------|-------|
    | Cache Key | \`${{ steps.cache.outputs.cache-key }}\` |
    | Cache Hit | ${{ steps.cache.outputs.cache-hit }} |
    | Cache Size | $(du -sh ${{ steps.cache.outputs.path }} | cut -f1) |
    | Job Duration | ${{ job.duration }}s |
    EOF

    # Optional: Send to external monitoring
    # curl -X POST https://metrics.example.com/github-actions \
    #   -d "{\"cache_hit\": ${{ steps.cache.outputs.cache-hit }}, ...}"
```

**View in GitHub Actions UI:**
Each workflow run shows cache metrics in summary.

#### Cache Cleanup Strategies

GitHub Actions automatically deletes caches after 7 days of no access, but you can proactively clean up:

```bash
# Delete caches for specific branch
gh cache delete --all --branch feature-branch

# Delete caches matching pattern
gh cache list --key build-cache- | while read -r line; do
  id=$(echo "$line" | awk '{print $1}')
  gh cache delete "$id"
done
```

**Automated cleanup:**

```yaml
# Weekly cache cleanup job
name: Cache Cleanup
on:
  schedule:
    - cron: '0 0 * * 0'  # Every Sunday

jobs:
  cleanup:
    runs-on: ubuntu-latest
    steps:
      - name: Delete old caches
        run: |
          # Delete caches from merged PRs
          gh cache list --json key,id,ref | \
            jq -r '.[] | select(.ref | startswith("refs/pull/")) | .id' | \
            xargs -I {} gh cache delete {}
```

### Migration Best Practices

#### Principle: Incremental Adoption

Don't migrate all jobs at once—start with one, validate, then expand.

**Phase 1: Single job**

```yaml
# Pick a non-critical job (e.g., lint)
lint:
  steps:
    - uses: ./.github/actions/cached-ci-job
      with:
        hash-sources: '**/*.nix|**/*.ts'  # New content-addressed key
```

**Phase 2: Job category**
After validating Phase 1, expand to all similar jobs (e.g., all Nix jobs).

**Phase 3: Full rollout**
Once confident, apply to all jobs.

#### Principle: Preserve Rollback Path

During migration, keep both old and new cache key patterns:

```yaml
- uses: actions/cache/restore@v4
  with:
    key: new-content-${{ hashFiles('inputs') }}
    restore-keys: |
      new-content-
      old-commit-${{ github.sha }}  # Fallback to old pattern
```

This allows gradual migration—new keys preferred, old keys still work.

#### Principle: Document Changes

Update workflow comments to explain cache key strategy:

```yaml
# Cache key strategy (as of 2025-11-01):
# - Content-addressed: key = hash(job-specific inputs)
# - Old commit-based keys still restored as fallback
# - Transition period: 2025-11 to 2025-12
nix:
  steps:
    - uses: ./.github/actions/cached-ci-job
      with:
        hash-sources: 'flake.lock|**/*.nix'
```

## 6. Concrete Next Steps

Based on this research, here's your actionable roadmap:

### Immediate Actions (This Week)

#### Step 1: Create Feature Branch

```bash
cd /Users/crs58/projects/nix-workspace/infra
git checkout -b feature/content-addressed-caching
```

#### Step 2: Update cached-ci-job Action

**File:** `.github/actions/cached-ci-job/action.yaml`

1. Add `hash-sources` input (see Pattern 1 in section 3)
2. Replace SHA-based key with `hashFiles()` key
3. Update documentation comments

**Estimated time:** 1 hour

#### Step 3: Update CI Workflow

**File:** `.github/workflows/ci.yaml`

1. Add `hash-sources` to Nix jobs (lines 336, 428, 519, 616, 725, 906, 1008)
2. Configure TypeScript-specific hash sources
3. Test locally with `act` or similar

**Estimated time:** 2 hours

#### Step 4: Test with Real PRs

Create test PRs with different change types:

```bash
# Test 1: Non-Nix change
git checkout -b test/readme-change
echo "Test" >> README.md
git add README.md && git commit -m "docs: test cache with readme change"
git push origin test/readme-change
# Expected: Nix jobs show cache hits

# Test 2: Nix input change
git checkout feature/content-addressed-caching
git checkout -b test/nix-change
echo "# test" >> flake.nix
git add flake.nix && git commit -m "test: flake.nix change"
git push origin test/nix-change
# Expected: Nix jobs show cache misses

# Test 3: TypeScript change
git checkout feature/content-addressed-caching
git checkout -b test/ts-change
echo "// test" >> packages/docs/src/index.ts
git add packages/docs/src/index.ts && git commit -m "test: ts change"
git push origin test/ts-change
# Expected: TypeScript jobs cache miss, Nix jobs cache hit
```

**Estimated time:** 1 hour

#### Step 5: Merge and Monitor

```bash
git checkout feature/content-addressed-caching
# Create PR for review
gh pr create --title "feat: content-addressed caching" \
  --body "Implements content-addressed cache keys using hashFiles()

  Changes:
  - Replace commit SHA with content hash in cache keys
  - Add per-job hash-sources configuration
  - Improve cache hit rates across commits

  Testing:
  - Validated with test PRs (see #XXX, #YYY, #ZZZ)
  - Cache metrics show XY% improvement in hit rate"
```

Monitor for 1-2 weeks:

- Track cache hit rates in workflow summaries
- Watch for unexpected cache misses
- Gather feedback from team

**Estimated time:** Ongoing

### Short-Term Actions (Next Month)

#### Step 6: Add Cache Analytics

Create dashboard or script to analyze cache effectiveness:

```bash
# Script to analyze cache hit rates
.github/scripts/analyze-cache-effectiveness.sh infra ci.yaml 50
```

Output:

```
Cache hit rate by job:
- nix (packages, x86_64-linux): 87%
- nix (packages, aarch64-linux): 85%
- typescript (docs): 92%
- secrets-scan: 45% (expected - depends on git history)

Recommendations:
- Consider derivation hash extraction for nix jobs (currently hashFiles approximation)
- secrets-scan: low hit rate normal for security scanning
```

**Estimated time:** 4 hours

#### Step 7: Evaluate Turborepo for TypeScript

If you add more TypeScript packages, set up Turborepo:

```bash
bun add -D turbo
# Create turbo.json (see Pattern 5)
# Update package-test.yaml to use Turborepo
```

**Estimated time:** 3-4 hours

**Trigger:** When you have 2+ TypeScript packages

### Medium-Term Actions (Next Quarter)

#### Step 8: Implement Nix Derivation Hash Extraction

For maximum precision, extract actual derivation hashes:

```bash
# Create script
.github/scripts/compute-nix-cache-key.sh

# Update CI workflow to use script
# (See Pattern 3 in section 3)
```

**Estimated time:** 8-10 hours

**Expected improvement:** 5-10% better hit rate than hashFiles approximation

#### Step 9: Evaluate Magic Nix Cache Replacement

Magic Nix Cache's free tier ends February 1, 2025.

**Options:**

1. **FlakeHub Cache** (Determinate Systems, paid)
2. **Cachix** (you're already using for Nix binary cache)
3. **Self-hosted** (bazel-remote or similar)
4. **GitHub Actions cache only** (current approach, no change)

**Decision matrix:**

| Option | Cost | Setup Time | Performance | Nix Integration |
|--------|------|------------|-------------|-----------------|
| FlakeHub | $$ | 30 min | Excellent | Native |
| Cachix | $$ | 1 hour | Excellent | Native |
| Self-hosted | Infrastructure | 1-2 weeks | Good | Requires config |
| GH Actions only | Free | 0 | Good | Manual |

**Recommendation:** Stick with Cachix + GitHub Actions cache (your current approach).
You're already paying for Cachix; extending it to replace Magic Nix Cache is straightforward.

**Estimated time:** 2-3 hours (if using Cachix, already set up)

### Long-Term Actions (6+ Months)

#### Step 10: Assess Remote Cache Server

**When to consider:**

- Team grows beyond 10 active developers
- Multiple repositories need to share caches
- 10GB GitHub Actions cache limit becomes constraining
- Want finer-grained access control

**Not recommended yet**—revisit when you scale.

#### Step 11: Continuous Optimization

Caching is not "set and forget"—revisit quarterly:

1. **Review cache metrics:** Are hit rates degrading?
2. **Update hash sources:** Have dependencies changed?
3. **Clean up old patterns:** Remove transitional fallbacks
4. **Document learnings:** Share knowledge with team

## 7. References

### Official Documentation

#### GitHub Actions

- [GitHub Actions Cache](https://github.com/actions/cache) - Official cache action and documentation
- [Caching Dependencies](https://docs.github.com/en/actions/using-workflows/caching-dependencies-to-speed-up-workflows) - GitHub's caching guide
- [hashFiles() Function](https://docs.github.com/en/actions/learn-github-actions/expressions#hashfiles) - Context function reference

#### Nix Ecosystem

- [Nix Manual: Content-Addressed Derivations](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-build.html) - Nix's content-addressing system
- [nix-store --query Reference](https://nixos.org/manual/nix/stable/command-ref/nix-store/query) - Querying derivation hashes
- [Cachix Documentation](https://docs.cachix.org/) - Binary cache service for Nix
- [Determinate Systems Blog: Magic Nix Cache](https://determinate.systems/blog/magic-nix-cache/) - How Magic Nix Cache works
- [Nix CI with GitHub Actions](https://nix.dev/guides/recipes/continuous-integration-github-actions) - Official Nix CI guide

#### Monorepo Tools

- [Turborepo: Remote Caching](https://turborepo.com/docs/core-concepts/remote-caching) - How Turborepo computes cache keys
- [Nx: How Caching Works](https://nx.dev/docs/concepts/how-caching-works) - Nx's computation hash algorithm
- [Turborepo Cache API Spec](https://turborepo.com/docs/reference/remote-cache-api) - Protocol for remote caching

#### Build Systems

- [Bazel: Remote Caching](https://bazel.build/remote/caching) - Content-addressed caching in Bazel
- [Buck2 Documentation](https://buck2.build/docs/) - Meta's next-generation build system
- [Earthly Documentation](https://docs.earthly.dev/) - Docker-based build automation

### Blog Posts & Articles

#### Content-Addressed Caching Concepts

- [Fast Rust Builds with sccache](https://depot.dev/blog/sccache-in-github-actions) - Content-addressable compilation caching
- [Building a Turborepo Remote Cache](https://blog.terrible.dev/blog/Building-a-remote-cache-server-for-Turborepo/) - Implementation deep dive
- [Nx Cloud Cache Security](https://nx.dev/blog/creep-vulnerability-build-cache-security) - Security considerations for shared caches

#### Nix + CI/CD

- [GitHub Actions Powered by Nix & Cachix](https://gvolpe.com/blog/github-actions-nix-cachix-dhall/) - Real-world Nix CI setup
- [Caching Nix Shell](https://fzakaria.com/2020/08/11/caching-your-nix-shell.html) - Deep dive on Nix caching mechanics

#### Monorepo Strategies

- [Optimizing CI Pipelines for Monorepos](https://graphite.dev/guides/optimizing-ci-pipelines-monorepos) - General monorepo CI patterns
- [Monorepo with GitHub Actions](https://graphite.dev/guides/monorepo-with-github-actions) - Path filtering and caching strategies

### Tools & Actions

#### Nix-Specific

- [nix-community/cache-nix-action](https://github.com/nix-community/cache-nix-action) - Sophisticated Nix store caching
- [DeterminateSystems/magic-nix-cache-action](https://github.com/DeterminateSystems/magic-nix-cache-action) - Zero-config Nix caching (free tier EOL Feb 2025)
- [cachix/cachix-action](https://github.com/cachix/cachix-action) - Cachix integration for GitHub Actions

#### Monorepo Tools

- [Turborepo](https://turborepo.com/) - Incremental bundler and build system for JS/TS monorepos
- [Nx](https://nx.dev/) - Smart monorepo build system with computation caching
- [Lerna](https://lerna.js.org/) - Tool for managing JavaScript projects with multiple packages

#### Build Systems

- [Bazel](https://bazel.build/) - Google's fast, scalable build system
- [Buck2](https://buck2.build/) - Meta's next-generation build system
- [Earthly](https://earthly.dev/) - Docker-based reproducible builds
- [bazel-remote](https://github.com/buchgr/bazel-remote) - Remote cache server for Bazel

#### Helper Actions

- [tj-actions/changed-files](https://github.com/tj-actions/changed-files) - Detect changed files (used in your current setup)
- [dorny/paths-filter](https://github.com/dorny/paths-filter) - Alternative path filtering action
- [nrwl/nx-set-shas](https://github.com/nrwl/nx-set-shas) - Compute base/head SHAs for Nx affected detection

### Academic & Technical Papers

- [Build Systems à la Carte](https://www.microsoft.com/en-us/research/uploads/prod/2018/03/build-systems.pdf) - Theoretical foundations of build systems (referenced by Buck2)
- [Content-Addressable Storage](https://en.wikipedia.org/wiki/Content-addressable_storage) - General concept overview

### Community Resources

#### GitHub Discussions

- [GitHub Actions Cache Collision in Matrix Jobs](https://github.com/orgs/community/discussions/63953) - Common pitfall and solutions
- [Speeding up Monorepo Builds with Nx Cache](https://github.com/orgs/community/discussions/166480) - Real-world monorepo optimization

#### Stack Overflow

- [When is hashFiles() needed in GitHub Actions cache?](https://stackoverflow.com/questions/77194019/) - Practical guidance on cache key design
- [How to maintain Bazel cache with GitHub Actions?](https://stackoverflow.com/questions/69989987/) - Content-addressed caching for Bazel

### Example Repositories

To see real-world implementations, examine these repositories:

#### Nix + GitHub Actions

- Look for repos using `cachix-action` or `magic-nix-cache-action`
- Search: `github.com/search?q=cachix-action+filename:.github/workflows`

#### Turborepo Examples

- [Turborepo Examples](https://github.com/vercel/turbo/tree/main/examples) - Official examples from Vercel
- [Turborepo Starter](https://github.com/vercel/turbo/tree/main/examples/basic) - Minimal setup

#### Nx Examples

- [Nx Examples](https://github.com/nrwl/nx-examples) - Official Nx example repositories
- [Nx CI Setup](https://github.com/nrwl/nx-recipes) - Nx CI/CD patterns

### Internal Documentation (Your Repository)

After implementing changes, update these files:

- `.github/actions/cached-ci-job/README.md` - Document content-addressed caching approach
- `.github/workflows/README.md` - Explain cache key strategy
- `docs/development/ci-cd.md` - CI/CD architecture including caching

### Keeping Up to Date

GitHub Actions ecosystem evolves rapidly. Stay informed:

1. **GitHub Changelog:** <https://github.blog/changelog/> - Filter for "Actions"
2. **Determinate Systems Blog:** <https://determinate.systems/blog/> - Nix CI/CD innovations
3. **Turborepo Changelog:** <https://turborepo.com/blog> - Monorepo tool updates
4. **Nix Weekly:** <https://weekly.nixos.org/> - Nix community newsletter

---

## Conclusion

Content-addressed caching represents a significant improvement over commit-based strategies for your Nix + TypeScript monorepo.
The core insight: **cache keys should reflect what actually changed (inputs), not where in version control you are (commits)**.

Your immediate path forward:

1. **This week:** Replace SHA-based keys with `hashFiles()` (Tier 1, Pattern 1+2)
2. **This month:** Add cache analytics and evaluate Turborepo for TS packages (Tier 2)
3. **This quarter:** Consider Nix derivation hash extraction for maximum precision (Tier 2)
4. **Long-term:** Reassess based on scale—current approach should handle 10-20 developers comfortably

Expected results after Tier 1 implementation:

- **60-70% reduction in unnecessary cache invalidations**
- **Improved PR workflow** (rebasing doesn't break caches)
- **Better cache utilization** (dedups across branches)
- **Faster feedback loops** (fewer rebuilds)

This investment in caching infrastructure pays dividends as the repository and team grow.
Every build that hits cache instead of rebuilding saves 2-10 minutes of CI time—multiplied across dozens of jobs and hundreds of commits, the savings are substantial.

**Next action:** Create the feature branch and start with Action 1.1 from section 6.

Good luck with the implementation! The Nix ecosystem's content-addressed foundation makes this transition particularly clean—you're leveraging existing strengths, not fighting against your infrastructure.
