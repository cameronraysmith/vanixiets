---
title: CI Caching Implementation Guide
description: Step-by-step guide to implement ADR-0015 caching optimizations
---

This guide provides concrete implementation steps for [ADR-0015: CI/CD caching optimization](/development/architecture/adrs/0015-ci-caching-optimization/).

## Quick wins (implement first)

### 1. Add concurrency control

**File:** `.github/workflows/ci.yaml`

**Change:**
```yaml
name: CI
on:
  # ... existing triggers

# ADD THIS - cancels previous runs on new commit to same PR/branch
concurrency:
  group: ci-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true

defaults:
  # ... existing defaults
```

**Impact:** Saves 10-20 minutes per additional push to PR.

**Risk:** None - standard GitHub Actions pattern.

### 2. Add path-based job filtering

**File:** `.github/workflows/ci.yaml`

**Add new job at the beginning:**
```yaml
jobs:
  # NEW JOB: Detect which subsystems changed
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      nix-code: ${{ steps.filter.outputs.nix-code }}
      typescript: ${{ steps.filter.outputs.typescript }}
      docs-content: ${{ steps.filter.outputs.docs-content }}
      workflows: ${{ steps.filter.outputs.workflows }}
      bootstrap: ${{ steps.filter.outputs.bootstrap }}
    steps:
      - uses: actions/checkout@v5

      - uses: dorny/paths-filter@v3
        id: filter
        with:
          filters: |
            # Nix configuration changes
            nix-code:
              - 'flake.nix'
              - 'flake.lock'
              - 'configurations/**'
              - 'modules/**'
              - 'overlays/**'
              - 'packages/*/flake.nix'
              - 'justfile'

            # TypeScript source changes
            typescript:
              - 'packages/docs/src/**/*.ts'
              - 'packages/docs/src/**/*.tsx'
              - 'packages/docs/src/**/*.astro'
              - 'packages/docs/**/*.test.ts'
              - 'packages/docs/playwright.config.ts'
              - 'packages/docs/vitest.config.ts'
              - 'packages/docs/package.json'
              - 'packages/docs/tsconfig.json'
              - 'package.json'
              - 'bun.lockb'

            # Documentation content changes (markdown only)
            docs-content:
              - 'packages/docs/src/content/**/*.md'
              - 'packages/docs/src/content/**/*.mdx'
              - 'packages/docs/astro.config.ts'

            # Workflow changes (trigger everything)
            workflows:
              - '.github/**'

            # Bootstrap/setup changes
            bootstrap:
              - 'Makefile'
              - '.envrc'

  # Existing jobs remain, but add conditions...
```

**Update each job with appropriate conditions:**

```yaml
  bootstrap-verification:
    needs: [skip-check, secrets-scan, detect-changes]
    if: |
      needs.skip-check.outputs.should_skip != 'true' &&
      (needs.detect-changes.outputs.bootstrap == 'true' ||
       needs.detect-changes.outputs.workflows == 'true' ||
       github.event_name == 'workflow_dispatch')
    # ... rest of job

  config-validation:
    needs: [skip-check, secrets-scan, detect-changes]
    if: |
      needs.skip-check.outputs.should_skip != 'true' &&
      (needs.detect-changes.outputs.nix-code == 'true' ||
       needs.detect-changes.outputs.workflows == 'true' ||
       github.event_name == 'workflow_dispatch')
    # ... rest of job

  autowiring-validation:
    needs: [skip-check, secrets-scan, detect-changes]
    if: |
      needs.skip-check.outputs.should_skip != 'true' &&
      (needs.detect-changes.outputs.nix-code == 'true' ||
       needs.detect-changes.outputs.workflows == 'true' ||
       github.event_name == 'workflow_dispatch')
    # ... rest of job

  nix:
    needs: [skip-check, secrets-scan, cache-overlay-packages, detect-changes]
    if: |
      needs.skip-check.outputs.should_skip != 'true' &&
      (needs.detect-changes.outputs.nix-code == 'true' ||
       needs.detect-changes.outputs.workflows == 'true' ||
       github.event_name == 'workflow_dispatch')
    # ... rest of job

  typescript:
    needs: [skip-check, secrets-scan, set-variables, detect-changes]
    if: |
      needs.skip-check.outputs.should_skip != 'true' &&
      (needs.detect-changes.outputs.typescript == 'true' ||
       needs.detect-changes.outputs.docs-content == 'true' ||
       needs.detect-changes.outputs.workflows == 'true' ||
       github.event_name == 'workflow_dispatch')
    # ... rest of job
```

**Impact:**
- Markdown-only PRs: Skip nix jobs (save 15-20 min)
- Nix-only PRs: Skip TypeScript tests (save 3-5 min)
- Both run on workflow changes or manual dispatch

**Risk:** Low - conservative filters, workflow changes trigger all jobs.

## High-impact optimization (requires testing)

### 3. Migrate to Magic Nix Cache

**Current:** `.github/actions/setup-nix/action.yaml`

**Replace with simpler approach:**

**File:** `.github/workflows/ci.yaml` (in each job's steps)

**Before:**
```yaml
steps:
  - name: Setup Nix
    uses: ./.github/actions/setup-nix
    with:
      system: x86_64-linux
      enable-cachix: true
      cachix-name: ${{ env.CACHIX_BINARY_CACHE }}
      cachix-auth-token: ${{ secrets.CACHIX_AUTH_TOKEN }}
```

**After:**
```yaml
steps:
  - uses: DeterminateSystems/nix-installer-action@main
    with:
      source-url: https://install.determinate.systems/nix

  - uses: DeterminateSystems/magic-nix-cache-action@main

  - uses: cachix/cachix-action@v15
    with:
      name: cameronraysmith
      authToken: ${{ secrets.CACHIX_AUTH_TOKEN }}
```

**Migration strategy:**

1. **Test in feature branch first**
2. **Migrate one job** (start with `secrets-scan` - simple, fast)
3. **Monitor cache hit rates** in Actions logs
4. **Gradually migrate other jobs** if successful
5. **Keep custom action** as fallback until fully migrated

**Benefits:**
- 3-5x faster Nix builds on cache hits
- Automatic cache key management (based on flake.lock hash)
- No more manual cache purging (current setup has permission errors)
- Better upstream cache coordination

**Monitoring:**

Check Actions logs for Magic Nix Cache metrics:
```
Magic Nix Cache: cache hit rate: 87%
Magic Nix Cache: saved 2.3 GB from cache
Magic Nix Cache: 127 store paths restored
```

## Fine-grained optimizations

### 4. Add Bun dependency caching

**File:** `.github/workflows/package-test.yaml` and similar

**Add before `bun install`:**
```yaml
- name: Cache Bun dependencies
  uses: actions/cache@v4
  with:
    path: |
      ~/.bun/install/cache
      node_modules
    key: bun-${{ runner.os }}-${{ hashFiles('**/bun.lockb') }}
    restore-keys: |
      bun-${{ runner.os }}-

- name: Install dependencies
  run: nix develop -c bun install
```

**Impact:** 10-30 seconds saved per TypeScript job.

### 5. Add flake evaluation caching

**Add to jobs that run `nix eval` or `nix flake check`:**

```yaml
- name: Cache Nix flake evaluation
  uses: actions/cache@v4
  with:
    path: |
      ~/.cache/nix
      /nix/var/nix/db/db.sqlite
    key: nix-eval-${{ runner.os }}-${{ hashFiles('flake.lock') }}
    restore-keys: |
      nix-eval-${{ runner.os }}-

- name: Run flake checks
  run: nix flake check --impure
```

**Impact:** 30-60 seconds saved on flake checks.

## Testing strategy

### Phase 1: Validate filters

**Create test PRs:**

1. **Markdown-only PR:**
   ```bash
   git checkout -b test/docs-only
   # Edit only markdown files
   git commit -m "docs: test path filters"
   git push
   ```
   **Expected:** Only `typescript` job runs (for docs build + linkcheck)
   **Not run:** `nix`, `bootstrap-verification`, `config-validation`, etc.

2. **Nix-only PR:**
   ```bash
   git checkout -b test/nix-only
   # Edit only .nix files
   git commit -m "feat(nix): test path filters"
   git push
   ```
   **Expected:** `nix` and related validation jobs run
   **Not run:** `typescript` job

3. **Workflow-change PR:**
   ```bash
   git checkout -b test/workflow-change
   # Edit .github/workflows/ci.yaml
   git commit -m "ci: test path filters"
   git push
   ```
   **Expected:** ALL jobs run (workflow changes affect everything)

### Phase 2: Validate Magic Nix Cache

**Create test branch:**
```bash
git checkout -b test/magic-nix-cache
```

**Migrate one job:**
- Start with `secrets-scan` (simplest, least risky)
- Replace setup-nix with Magic Nix Cache
- Run workflow, check logs for cache metrics

**Success criteria:**
- Job completes successfully
- Cache hit rate >70% on second run
- No permission errors in cache operations

**If successful:**
- Migrate more jobs gradually
- Monitor for regressions

### Phase 3: Performance baseline

**Before optimization:**
```bash
# Collect metrics from last 10 workflow runs
gh run list --workflow=ci.yaml --limit=10 --json durationMs,conclusion
```

**After optimization:**
```bash
# Compare metrics after 10 runs with optimizations
gh run list --workflow=ci.yaml --limit=10 --json durationMs,conclusion
```

**Expected improvements:**
- 50-70% of runs: Jobs skipped via path filters
- Remaining runs: 30-50% faster via Magic Nix Cache
- No failed cache operations (current permission errors eliminated)

## Rollback plan

If issues arise:

### Revert concurrency control:
```yaml
# Comment out or remove concurrency block
# concurrency:
#   group: ci-${{ github.event.pull_request.number || github.ref }}
#   cancel-in-progress: true
```

### Revert path filters:
```yaml
# Change job conditions from:
if: needs.detect-changes.outputs.nix-code == 'true'

# Back to:
if: needs.skip-check.outputs.should_skip != 'true'
```

### Revert Magic Nix Cache:
```yaml
# Replace:
- uses: DeterminateSystems/nix-installer-action@main
- uses: DeterminateSystems/magic-nix-cache-action@main

# With:
- uses: ./.github/actions/setup-nix
  with:
    # ... existing config
```

## Monitoring dashboard

Track these metrics weekly:

1. **Workflow duration**
   - Median: `gh run list --workflow=ci.yaml --limit=100 --json durationMs`
   - P95: Same query, calculate 95th percentile

2. **Job skip rate**
   - Count: `grep "skipped" in workflow logs`
   - Target: 50-70% of jobs skipped on typical PR

3. **Cache hit rate**
   - Magic Nix Cache: Check logs for "cache hit rate: X%"
   - Target: >80%

4. **Actions minutes consumed**
   - GitHub Actions usage page
   - Compare month-over-month

5. **Developer feedback**
   - PR iteration time (time between push and green checkmark)
   - Target: <5 minutes for docs-only changes, <10 minutes for code changes

## Expected outcomes

### Scenario: Markdown-only PR (example: PR #17)

**Before optimization:**
- Duration: 18 minutes
- Jobs run: 12 jobs
- Wasted compute: nix builds (15 min)

**After optimization:**
- Duration: 3 minutes
- Jobs run: 3 jobs (secrets-scan, set-variables, typescript)
- Savings: 15 minutes, 9 jobs skipped

### Scenario: Nix-only PR

**Before optimization:**
- Duration: 20 minutes (first run), 20 minutes (subsequent runs)
- Cache hit rate: ~60%

**After optimization:**
- Duration: 20 minutes (first run), 8 minutes (subsequent runs with Magic Nix Cache)
- Cache hit rate: ~85%
- Savings: 12 minutes on cache hits

### Scenario: Mixed PR (Nix + TypeScript)

**Before optimization:**
- Duration: 25 minutes
- Two commits → 50 minutes total (both runs full)

**After optimization:**
- Duration: 25 minutes (first), 10 minutes (second with cancellation + cache)
- Savings: 15 minutes via concurrency control

## Next steps

1. **Review ADR-0015** - understand full strategy
2. **Implement quick wins** - concurrency + path filters (low risk)
3. **Test in feature branch** - validate filters work correctly
4. **Migrate to Magic Nix Cache** - start with one job, expand gradually
5. **Monitor metrics** - track improvements over 2 weeks
6. **Document learnings** - update this guide with actual results
7. **Consider ADR acceptance** - if successful, mark ADR-0015 as "Accepted"

## Resources

- [ADR-0015: CI caching optimization](/development/architecture/adrs/0015-ci-caching-optimization/)
- [Magic Nix Cache docs](https://github.com/DeterminateSystems/magic-nix-cache-action)
- [dorny/paths-filter](https://github.com/dorny/paths-filter)
- [GitHub Actions concurrency](https://docs.github.com/en/actions/using-jobs/using-concurrency)
