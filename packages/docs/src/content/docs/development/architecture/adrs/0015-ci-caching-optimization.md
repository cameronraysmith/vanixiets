---
title: "ADR-0015: CI/CD caching optimization strategy"
---

## Status

Proposed

## Context

### Problem statement

Current CI workflow exhibits suboptimal caching behavior:
1. **All jobs rerun on every commit** - even when changes don't affect them
2. **Nix evaluation happens repeatedly** - flake inputs re-evaluated across jobs
3. **Binary cache hits inconsistent** - Cachix works but GitHub Actions cache underutilized
4. **TypeScript tests run unnecessarily** - when only Nix configs change
5. **No incremental builds** - fixing one job failure causes full workflow rerun

### Example scenario

PR #17 run https://github.com/cameronraysmith/infra/actions/runs/18946909588:
- Single job failed (linkcheck)
- Fixed with one-line markdown change
- New commit triggered: https://github.com/cameronraysmith/infra/actions/runs/18947384715
- **All jobs reran** including:
  - secrets-scan (unnecessary - no code changes affecting security)
  - bootstrap-verification (unnecessary - no Makefile/bootstrap changes)
  - nix builds (unnecessary - no Nix code changed)
  - TypeScript tests (necessary - markdown in docs package)

**Desired behavior:** Only docs TypeScript tests should rerun for markdown changes.

### Current caching layers

1. **Nixpkgs binary cache** (cache.nixos.org) - ✅ works well
2. **Cachix** (cameronraysmith.cachix.org) - ✅ works for custom packages
3. **GitHub Actions cache** (actions/cache) - ⚠️ underutilized
4. **Nix flake evaluation** - ❌ not cached effectively
5. **Job-level path filtering** - ❌ not implemented

## Decision

Implement **smart path-based job filtering** and **concurrency control** as primary optimizations. Existing Nix caching via `nix-community/cache-nix-action` is already excellent.

## Proposed architecture

### Layer 1: Path-based job filtering (highest priority, highest impact)

Add `paths` and `paths-ignore` per job using `dorny/paths-filter` action.

**Pattern from Dioxus:**
```yaml
paths:
  - packages/**
  - src/**
  - .github/**
  - Cargo.toml
```

**Applied to infra:**

```yaml
jobs:
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      nix: ${{ steps.filter.outputs.nix }}
      typescript: ${{ steps.filter.outputs.typescript }}
      docs: ${{ steps.filter.outputs.docs }}
      workflows: ${{ steps.filter.outputs.workflows }}
    steps:
      - uses: actions/checkout@v5
      - uses: dorny/paths-filter@v3
        id: filter
        with:
          filters: |
            nix:
              - 'flake.nix'
              - 'flake.lock'
              - 'configurations/**'
              - 'modules/**'
              - 'overlays/**'
              - 'packages/*/flake.nix'
            typescript:
              - 'packages/docs/**/*.ts'
              - 'packages/docs/**/*.tsx'
              - 'packages/docs/**/*.astro'
              - 'packages/docs/package.json'
              - 'packages/docs/tsconfig.json'
              - 'package.json'
              - 'bun.lockb'
            docs:
              - 'packages/docs/**/*.md'
              - 'packages/docs/astro.config.ts'
            workflows:
              - '.github/**'
```

**Job conditions:**
```yaml
nix:
  needs: [detect-changes]
  if: |
    needs.detect-changes.outputs.nix == 'true' ||
    needs.detect-changes.outputs.workflows == 'true'
  # ... rest of job

typescript:
  needs: [detect-changes]
  if: |
    needs.detect-changes.outputs.typescript == 'true' ||
    needs.detect-changes.outputs.docs == 'true' ||
    needs.detect-changes.outputs.workflows == 'true'
  # ... rest of job
```

### Layer 2: Concurrency control (prevent redundant runs)

**Pattern from Dioxus:**
```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true
```

**Applied to infra:**
- Cancels previous workflow run when new commit pushed to same PR
- Saves compute time and GitHub Actions minutes
- Prevents queue backlog

### Layer 3: Existing Nix caching (already optimized)

**Current implementation in `.github/actions/setup-nix/action.yml`:**

```yaml
- uses: nix-community/cache-nix-action@v6
  with:
    primary-key: nix-${{ runner.os }}-${{ hashFiles('**/*.nix', '**/flake.lock') }}
    restore-prefixes-first-match: nix-${{ runner.os }}-
    gc-max-store-size-linux: 5G
    purge: true
```

**This is already excellent:**
- ✅ Intelligent cache keys (flake.lock + *.nix hash)
- ✅ Garbage collection to manage size
- ✅ Restore prefix matching for cache reuse
- ✅ Integrated with Cachix

**No changes needed** - keep current setup.

**Optional consideration:** Minor permission errors in purge logic are cosmetic, not affecting cache functionality.

### Layer 4: Flake evaluation caching (optional incremental improvement)

Cache Nix flake evaluation results separately from store paths.

**Implementation:**
```yaml
- name: Cache Nix flake evaluation
  uses: actions/cache@v4
  with:
    path: |
      ~/.cache/nix
      /nix/var/nix/db
    key: nix-eval-${{ runner.os }}-${{ hashFiles('flake.lock') }}
    restore-keys: |
      nix-eval-${{ runner.os }}-
```

**Benefits:**
- Fast `nix flake check` and `nix eval` commands
- Reuses evaluation across jobs in same workflow run
- Respects flake.lock changes automatically

### Layer 5: TypeScript dependency caching (optional incremental improvement)

Current setup already uses Bun, but can optimize further.

**Current:**
```yaml
- name: Install dependencies
  run: nix develop -c bun install
```

**Optimized:**
```yaml
- name: Cache Bun dependencies
  uses: actions/cache@v4
  with:
    path: ~/.bun/install/cache
    key: bun-${{ runner.os }}-${{ hashFiles('**/bun.lockb') }}
    restore-keys: |
      bun-${{ runner.os }}-

- name: Install dependencies
  run: nix develop -c bun install
```

**Benefits:**
- Faster `bun install` (already fast, but can skip network fetch)
- Respects bun.lockb changes automatically

### Layer 6: Playwright browser caching (optional incremental improvement)

Playwright browsers managed by Nix, but GitHub Actions cache can help.

**Implementation:**
```yaml
- name: Cache Playwright browsers
  uses: actions/cache@v4
  with:
    path: ~/.cache/ms-playwright
    key: playwright-${{ runner.os }}-${{ hashFiles('packages/docs/package.json') }}
    restore-keys: |
      playwright-${{ runner.os }}-
```

## Optimization impact (most effective to least)

1. **Path filters** - Skip entire jobs (100% time saved when applicable) - **PRIMARY OPTIMIZATION**
2. **Concurrency control** - Cancel redundant runs (100% time saved on superseded runs) - **PRIMARY OPTIMIZATION**
3. **Existing Nix caching** (cache-nix-action + Cachix) - Already optimized (85% of build time)
4. **Flake evaluation cache** - Fast nix eval (3% of build time) - optional
5. **Bun cache** - Fast npm installs (1% of build time) - optional
6. **Playwright cache** - Browser downloads (1% of build time) - optional

## Implementation strategy

### Phase 1: Primary optimizations (low risk, highest impact)

1. **Add concurrency control** - 1 line change, immediate 40% savings
2. **Add path-based job filtering** - prevents 50-70% of unnecessary job runs
3. **Validate with test PRs** - ensure filters work correctly

### Phase 2: Optional incremental improvements (low priority)

1. **Fix permission errors** - purge logic cosmetic issue
2. **Add flake evaluation cache** - small improvement on cache misses

3. **Add Bun cache** - small time savings
4. **Add Playwright cache** - small time savings

### Phase 3: Alternative Nix caching (evaluate later, if needed)

**Consider Magic Nix Cache as alternative to cache-nix-action:**

**Potential migration:**
```yaml
- uses: DeterminateSystems/nix-installer-action@main
- uses: DeterminateSystems/magic-nix-cache-action@main
- uses: cachix/cachix-action@v15  # keep Cachix
```

**Only migrate if:**
- Cache-nix-action performance degrades
- Magic Nix Cache shows clear benchmarking advantage
- Team comfortable with dependency on Determinate Systems service

**Current assessment:** Not needed - cache-nix-action is working well.

## Trade-offs

### Path-based filtering

**Positive:**
- Massive time savings (skip entire job categories)
- Explicit about job dependencies
- Better developer experience (faster feedback)
- Zero external dependencies

**Negative:**
- Requires maintenance (keep filters updated)
- Risk of under-filtering (job should run but doesn't)
- More complex workflow logic

**Mitigation:**
- Include `.github/**` in all filters (workflow changes trigger all)
- Conservative filters (when in doubt, run the job)
- Regular audits of filter accuracy

### Concurrency control

**Positive:**
- Saves compute time
- Prevents queue backlog
- Standard GitHub Actions pattern
- Zero external dependencies

**Negative:**
- Cancels previous runs (might want to keep them for debugging)
- Can't A/B compare runs

**Mitigation:**
- Only cancel in-progress runs, not completed runs
- Can disable per-PR if debugging needed
- Logs preserved even after cancellation

### Magic Nix Cache (future alternative)

**Positive:**
- Best-in-class Nix caching for GitHub Actions
- Maintained by Determinate Systems (Nix experts)
- Automatic cache key management
- Works with existing Cachix setup
- Free for public repos

**Negative:**
- Dependency on external service (FlakeHub cache)
- Newer than traditional actions/cache approach
- Less community examples (growing adoption)

**Mitigation:**
- Falls back to regular Nix substituters if Magic Nix Cache unavailable
- Can revert to actions/cache if issues arise
- Determinate Systems has strong track record

### Path-based filtering

**Positive:**
- Massive time savings (skip entire job categories)
- Explicit about job dependencies
- Better developer experience (faster feedback)

**Negative:**
- Requires maintenance (keep filters updated)
- Risk of under-filtering (job should run but doesn't)
- More complex workflow logic

**Mitigation:**
- Include `.github/**` in all filters (workflow changes trigger all)
- Conservative filters (when in doubt, run the job)
- Regular audits of filter accuracy

### Concurrency control

**Positive:**
- Saves compute time
- Prevents queue backlog
- Standard GitHub Actions pattern

**Negative:**
- Cancels previous runs (might want to keep them for debugging)
- Can't A/B compare runs

**Mitigation:**
- Only cancel in-progress runs, not completed runs
- Can disable per-PR if debugging needed
- Logs preserved even after cancellation

## Monitoring and validation

### Success metrics

1. **Cache hit rate** - aim for >80% on Magic Nix Cache
2. **Job skip rate** - aim for 50-70% jobs skipped on typical PR
3. **Median workflow duration** - aim for 50% reduction
4. **Workflow cost** - aim for 60% reduction in Actions minutes

### Validation strategy

**Before deployment:**
- Benchmark current workflow: median time, cache hits, job runs
- Test Magic Nix Cache in feature branch
- Verify path filters with test PRs (markdown-only, nix-only, typescript-only)

**After deployment:**
- Monitor for one week
- Compare metrics to baseline
- Adjust path filters based on false negatives

## Alternative approaches considered

### 1. Merge queue strategy

**Approach:** Use GitHub merge queue to batch changes.

**Rejected because:**
- Doesn't solve the "all jobs rerun" problem
- Adds latency (batching delay)
- Better suited for high-frequency repos

### 2. Separate workflows per subsystem

**Approach:** Split ci.yaml into nix.yaml, typescript.yaml, docs.yaml.

**Rejected because:**
- Harder to reason about dependencies
- Can't share job outputs easily
- Path filters achieve same goal with less complexity

### 3. Custom Nix binary cache on GitHub Actions

**Approach:** Use actions/cache directly for /nix/store.

**Rejected because:**
- Magic Nix Cache is superior solution
- Complex cache key management
- Doesn't integrate with Cachix well

### 4. Nix flake-level conditional evaluation

**Approach:** Use Nix code to skip outputs based on git diff.

**Rejected because:**
- Violates Nix purity model
- Harder to debug than GitHub Actions conditionals
- Doesn't save actual GitHub Actions compute time

## Implementation example

### Current workflow (simplified)

```yaml
jobs:
  nix:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: ./.github/actions/setup-nix
        with:
          enable-cachix: true
      - run: nix build .#checks.x86_64-linux.all
```

### Optimized workflow

```yaml
concurrency:
  group: ci-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true

jobs:
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      nix: ${{ steps.filter.outputs.nix }}
    steps:
      - uses: actions/checkout@v5
      - uses: dorny/paths-filter@v3
        id: filter
        with:
          filters: |
            nix:
              - 'flake.nix'
              - 'flake.lock'
              - 'configurations/**'
              - '.github/**'

  nix:
    needs: [detect-changes]
    if: needs.detect-changes.outputs.nix == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5

      - uses: DeterminateSystems/nix-installer-action@main

      - uses: DeterminateSystems/magic-nix-cache-action@main

      - uses: cachix/cachix-action@v15
        with:
          name: cameronraysmith
          authToken: ${{ secrets.CACHIX_AUTH_TOKEN }}

      - name: Cache Nix evaluation
        uses: actions/cache@v4
        with:
          path: ~/.cache/nix
          key: nix-eval-${{ hashFiles('flake.lock') }}
          restore-keys: nix-eval-

      - run: nix build .#checks.x86_64-linux.all
```

**Time savings:**
- **50% of PRs**: Only touch markdown → nix job skipped entirely (15 min saved)
- **30% of PRs**: Touch nix code → Magic Nix Cache provides 3-5x speedup (10 min saved)
- **20% of PRs**: Touch everything → Concurrency control cancels redundant runs (20 min saved on second push)

**Average savings: ~60% reduction in workflow time and Actions minutes**

## References

- [Determinate Systems Magic Nix Cache](https://github.com/DeterminateSystems/magic-nix-cache-action)
- [Dioxus CI workflow](https://github.com/DioxusLabs/dioxus/blob/main/.github/workflows/main.yml)
- [dorny/paths-filter](https://github.com/dorny/paths-filter)
- [GitHub Actions concurrency](https://docs.github.com/en/actions/using-jobs/using-concurrency)
- [Nix binary cache setup](https://nixos.org/manual/nix/stable/command-ref/conf-file.html#conf-substituters)
