---
title: CI Caching Implementation Guide
description: Step-by-step guide to implement ADR-0015 caching optimizations
---

This guide provides concrete implementation steps for [ADR-0015: CI/CD caching optimization](/development/architecture/adrs/0015-ci-caching-optimization/).

## Primary optimizations (implement first, highest impact)

### 1. Add concurrency control (1-minute change, 40% savings)

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

**Priority:** **HIGHEST** - implement immediately.

### 2. Add path-based job filtering (30-minute change, 50-70% job skip rate)

**File:** `.github/workflows/ci.yaml`

**Add new job at the beginning:**
```yaml
jobs:
  # NEW JOB: Detect which subsystems changed (native git diff approach)
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      nix-code: ${{ steps.changes.outputs.nix-code }}
      typescript: ${{ steps.changes.outputs.typescript }}
      docs-content: ${{ steps.changes.outputs.docs-content }}
      bootstrap: ${{ steps.changes.outputs.bootstrap }}
    steps:
      - uses: actions/checkout@v5
        with:
          fetch-depth: 0  # Need history for git diff

      - name: Detect changed files
        id: changes
        run: |
          # Determine base ref for comparison
          if [ "${{ github.event_name }}" = "pull_request" ]; then
            BASE_REF="${{ github.event.pull_request.base.sha }}"
          else
            BASE_REF="HEAD^"
          fi

          # Workflow changes trigger everything
          if git diff --name-only "$BASE_REF" HEAD | grep -qE '\.github/'; then
            echo "nix-code=true" >> $GITHUB_OUTPUT
            echo "typescript=true" >> $GITHUB_OUTPUT
            echo "docs-content=true" >> $GITHUB_OUTPUT
            echo "bootstrap=true" >> $GITHUB_OUTPUT
            exit 0
          fi

          # Check for nix changes
          if git diff --name-only "$BASE_REF" HEAD | grep -qE '(\.nix$|flake\.lock|configurations/|modules/|overlays/|justfile)'; then
            echo "nix-code=true" >> $GITHUB_OUTPUT
          else
            echo "nix-code=false" >> $GITHUB_OUTPUT
          fi

          # Check for typescript changes
          if git diff --name-only "$BASE_REF" HEAD | grep -qE '(packages/docs/.*\.(ts|tsx|astro|test\.ts)|.*\.config\.(ts|js)|package\.json|bun\.lockb)'; then
            echo "typescript=true" >> $GITHUB_OUTPUT
          else
            echo "typescript=false" >> $GITHUB_OUTPUT
          fi

          # Check for docs content changes
          if git diff --name-only "$BASE_REF" HEAD | grep -qE 'packages/docs/.*\.(md|mdx)'; then
            echo "docs-content=true" >> $GITHUB_OUTPUT
          else
            echo "docs-content=false" >> $GITHUB_OUTPUT
          fi

          # Check for bootstrap changes
          if git diff --name-only "$BASE_REF" HEAD | grep -qE '(Makefile|\.envrc)'; then
            echo "bootstrap=true" >> $GITHUB_OUTPUT
          else
            echo "bootstrap=false" >> $GITHUB_OUTPUT
          fi

  # Existing jobs remain, but add conditions...
```

**Alternative: tj-actions/changed-files (if native becomes too complex):**

See [Path Filtering Research](/notes/development/path-filtering-research/) for details on actively-maintained alternative.

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

**Priority:** **HIGHEST** - implement immediately after concurrency control.

## Existing Nix caching (no changes needed)

### Current setup is already excellent

**Your `.github/actions/setup-nix/action.yml` already uses:**

```yaml
- uses: nix-community/cache-nix-action@v6
  with:
    primary-key: nix-${{ runner.os }}-${{ hashFiles('**/*.nix', '**/flake.lock') }}
    restore-prefixes-first-match: nix-${{ runner.os }}-
    gc-max-store-size-linux: 5G
    purge: true
```

**This provides:**
- ✅ Intelligent cache keys based on flake.lock + *.nix files
- ✅ Automatic garbage collection
- ✅ Cache restore with prefix matching
- ✅ Integration with Cachix

**No changes needed** - your Nix caching is already well-optimized.

**The permission errors you see** (`HttpError: Resource not accessible by integration`) are from the purge logic trying to delete old caches. This is cosmetic and doesn't affect cache functionality.

## Optional incremental improvements (low priority)

### 3. Fix cache purge permission errors (optional)

**Issue:** Permission errors when purging old caches.

**Fix in `.github/actions/setup-nix/action.yml`:**
```yaml
purge: true          # Change to false if errors are problematic
purge-created: 0
purge-last-accessed: 0
```

**Impact:** Cosmetic - errors don't affect caching functionality.

**Priority:** Low - only if errors are annoying in logs.

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

**Priority:** Low - minimal time savings.

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

**Priority:** Low - minimal time savings.

## Future alternative: Magic Nix Cache (evaluate later)

### Consider only if cache-nix-action performance degrades

**What it is:**
- Alternative to `nix-community/cache-nix-action`
- Provided by Determinate Systems
- Automatic GitHub Actions cache integration

**When to consider:**
- Cache-nix-action performance degrades over time
- Clear benchmarking shows advantage
- Team comfortable with external service dependency

**How to test:**
```yaml
# Replace in one job first
- uses: DeterminateSystems/nix-installer-action@main
- uses: DeterminateSystems/magic-nix-cache-action@main
- uses: cachix/cachix-action@v15  # keep Cachix
```

**Current assessment:** **Not needed** - your cache-nix-action setup is working well.

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

### Phase 2: Performance baseline

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
- Concurrency control: Redundant runs cancelled
- Cache hit rates: Already good with cache-nix-action

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

### Revert cache purge changes:
```yaml
# In .github/actions/setup-nix/action.yml, restore:
purge: true  # from false back to true
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
   - Check nix-community/cache-nix-action logs
   - Target: >80% (already achieving this)

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
- Duration: 20 minutes (full workflow)
- All jobs run even if only one Nix config changed

**After optimization:**
- Duration: Same 20 minutes (but fewer jobs run)
- Jobs run: Only nix-related validation + build
- Savings: TypeScript jobs skipped (~5 minutes)

### Scenario: Mixed PR (Nix + TypeScript)

**Before optimization:**
- Duration: 25 minutes
- Two commits → 50 minutes total (both runs full)

**After optimization:**
- Duration: 25 minutes (first), cancelled (second via concurrency control)
- Savings: 25 minutes - second run doesn't complete, first run result is what matters

## Next steps (prioritized)

### Immediate (do now)

1. **Add concurrency control** - 1 line change, huge impact
2. **Add path-based filtering** - 30 minutes of work
3. **Test with multiple PR types** - validate filters

### Short-term (within 1 week)

4. **Monitor metrics** - track job skip rate and workflow duration
5. **Adjust filters** - if false negatives occur

### Optional (only if needed)

6. **Fix purge permission errors** - if logs are annoying
7. **Evaluate Magic Nix Cache** - only if cache-nix-action degrades

**Estimated total time:** 1-2 hours
**Expected payoff:** 60% reduction in CI time, paying back after ~5 PRs

## Resources

- [ADR-0015: CI caching optimization](/development/architecture/adrs/0015-ci-caching-optimization/)
- [dorny/paths-filter](https://github.com/dorny/paths-filter)
- [GitHub Actions concurrency](https://docs.github.com/en/actions/using-jobs/using-concurrency)
- [nix-community/cache-nix-action](https://github.com/nix-community/cache-nix-action) (current implementation)
