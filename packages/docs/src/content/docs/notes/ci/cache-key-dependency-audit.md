---
title: Cache Key Dependency Audit
---

# Cache Key Dependency Audit

**Date**: 2025-11-01
**Status**: Analysis Complete
**Issue**: Missing critical .github dependencies in cache key computation

## Executive Summary

The composite action `cached-ci-job` currently auto-includes the workflow file from `GITHUB_WORKFLOW_REF` but **critically misses including itself** in the cache key computation.
This is a **critical bug** because changes to the cache key computation logic (in `cached-ci-job/action.yaml`) don't invalidate existing caches, leading to incorrect cache hits.

**Recommendation**: Implement Option A (auto-include critical dependencies) to fix this immediately.

## Current Auto-Inclusion Behavior

### Lines 50-58 of `cached-ci-job/action.yaml`

```yaml
# Get workflow file path (automatically included in hash)
WORKFLOW_FILE=$(echo "$GITHUB_WORKFLOW_REF" | sed 's|^[^/]*/[^/]*/||' | sed 's|@.*||')
echo "Workflow file: $WORKFLOW_FILE"

# Combine user sources + workflow file
if [ -n "$HASH_SOURCES" ]; then
  ALL_SOURCES="$HASH_SOURCES $WORKFLOW_FILE"
else
  # If no sources specified, use workflow file only
  ALL_SOURCES="$WORKFLOW_FILE"
fi
```

### GITHUB_WORKFLOW_REF Format

According to GitHub documentation, `GITHUB_WORKFLOW_REF` has the format:
```
owner/repo/.github/workflows/workflow-file.yaml@refs/heads/branch
```

After the sed transformations:
- Remove prefix: `owner/repo/` → `.github/workflows/workflow-file.yaml@refs/heads/branch`
- Remove suffix: `@refs/heads/branch` → `.github/workflows/workflow-file.yaml`

### What Gets Included for Different Job Types

#### 1. Direct Jobs in ci.yaml (e.g., nix, bootstrap-verification)

**GITHUB_WORKFLOW_REF contains**: `.github/workflows/ci.yaml`
**Currently includes**:
- ci.yaml
- User-specified hash-sources (e.g., `flake.nix flake.lock`)

**Used composite actions**:
- `.github/actions/cached-ci-job/action.yaml` ❌ NOT included
- `.github/actions/setup-nix/action.yml` ❌ NOT included

**Missing**: Both composite actions

#### 2. Reusable Workflow Calls (e.g., typescript → package-test.yaml)

**GITHUB_WORKFLOW_REF contains**: `.github/workflows/ci.yaml` (the CALLER workflow)
**Currently includes**:
- ci.yaml (caller workflow)
- User-specified hash-sources

**Used files**:
- `.github/workflows/package-test.yaml` ❌ NOT included (the actual reusable workflow)
- `.github/actions/cached-ci-job/action.yaml` ❌ NOT included
- `.github/actions/setup-nix/action.yml` ❌ NOT included

**Missing**: The reusable workflow file itself and both composite actions

#### 3. Jobs Within Reusable Workflows (e.g., test job inside package-test.yaml)

**GITHUB_WORKFLOW_REF contains**: `.github/workflows/package-test.yaml` (the executing workflow)
**Currently includes**:
- package-test.yaml
- User-specified hash-sources

**Used composite actions**:
- `.github/actions/cached-ci-job/action.yaml` ❌ NOT included
- `.github/actions/setup-nix/action.yml` ❌ NOT included

**Missing**: Both composite actions

## Critical Dependency Analysis

### The cached-ci-job Action is CRITICAL

The `cached-ci-job/action.yaml` file contains the cache key computation logic itself.
If this file changes, the way cache keys are computed changes.
**ALL jobs should invalidate when this file changes**, otherwise you can get stale caches based on old computation logic.

**Examples of changes that would require cache invalidation**:
- Changing the hash algorithm (line 124: `sha256sum | cut -c1-12`)
- Changing how files are discovered (lines 101-112: glob expansion logic)
- Changing which files are excluded (lines 104-108: notes directory exclusion)
- Changing how multiple file hashes are combined (line 79: concatenation)

**Current Bug Impact**:
- If you modify `cached-ci-job/action.yaml` to fix a bug in cache key computation
- All existing caches would still be used (cache keys computed with old logic)
- Jobs would incorrectly hit caches that should have been invalidated

### The setup-nix Action is Less Critical

The `setup-nix/action.yml` affects the build environment but doesn't affect:
- Job outputs
- Test results
- Build artifacts

Changes to setup-nix typically affect:
- How Nix is installed
- Cache restoration strategies
- Garbage collection settings

**Assessment**: Not critical for cache key computation, but jobs should include it in hash-sources if the Nix setup significantly affects their outputs.

## Proposed Solutions

### Option A: Auto-Include Critical Dependencies (RECOMMENDED)

**Implementation**:
```yaml
# Always include:
# 1. The workflow file (current behavior)
# 2. The cached-ci-job action (critical - computes the key)
# 3. Any explicitly specified hash-sources

WORKFLOW_FILE=$(echo "$GITHUB_WORKFLOW_REF" | sed 's|^[^/]*/[^/]*/||' | sed 's|@.*||')
CACHE_ACTION=".github/actions/cached-ci-job/action.yaml"

if [ -n "$HASH_SOURCES" ]; then
  ALL_SOURCES="$HASH_SOURCES $WORKFLOW_FILE $CACHE_ACTION"
else
  # If no sources specified, use workflow file + cache action
  ALL_SOURCES="$WORKFLOW_FILE $CACHE_ACTION"
fi
```

**Advantages**:
- Fixes the critical bug (cache key computation changes invalidate caches)
- Minimal changes to existing code
- No changes needed to calling jobs
- Maintains current workflow file auto-inclusion
- Clear and understandable behavior

**Disadvantages**:
- All existing caches will invalidate immediately (but this is GOOD - see below)

### Option B: Include All .github Files

**Implementation**:
```yaml
# Hash entire .github directory
if [ -n "$HASH_SOURCES" ]; then
  ALL_SOURCES="$HASH_SOURCES .github/**/*"
else
  ALL_SOURCES=".github/**/*"
fi
```

**Advantages**:
- Comprehensive - never miss a dependency
- Simple to understand

**Disadvantages**:
- Overly broad - invalidates caches for unrelated changes
- Changes to workflows that don't affect a job will invalidate its cache
- Changes to actions not used by a job will invalidate its cache
- May cause excessive cache misses

### Option C: Explicit Specification

**Implementation**: No changes to composite action. Update all jobs to include composite actions in hash-sources.

**Example**:
```yaml
- name: Check execution cache
  uses: ./.github/actions/cached-ci-job
  with:
    check-name: ${{ github.job }}
    hash-sources: |
      flake.nix
      flake.lock
      .github/actions/cached-ci-job/action.yaml
      .github/actions/setup-nix/action.yml
```

**Advantages**:
- Maximum control for each job
- Can tailor dependencies precisely

**Disadvantages**:
- Requires updating ~15+ job call sites
- Easy to forget when adding new jobs
- Maintenance burden
- The critical dependency (cached-ci-job) should ALWAYS be included

## Impact Assessment

### Cache Invalidation After Fix

When we implement Option A:
- **All existing caches will invalidate** (cache keys will change because we're adding a new file to the hash)
- This happens immediately on first run after the fix

**This is GOOD because**:
1. It's a one-time event (subsequent runs will build new caches correctly)
2. All previous caches were potentially incorrect (computed without considering changes to the cache computation logic itself)
3. Going forward, changes to `cached-ci-job` will correctly invalidate all caches
4. We get a clean slate with correct cache key computation

### Performance Impact

**First run after fix**:
- All jobs will have cache misses (expected)
- Build times will be longer (normal for cold cache)
- Subsequent runs will use properly computed caches

**Ongoing impact**:
- Minimal - only when `cached-ci-job/action.yaml` actually changes
- This is correct behavior (cache should invalidate when computation logic changes)

## Verification Plan

After implementing Option A:

### 1. Verify cached-ci-job is Included

Test with a simple job:
```bash
# Look for log output showing cache action in ALL_SOURCES
# Expected: "Hash sources: flake.nix flake.lock .github/workflows/ci.yaml .github/actions/cached-ci-job/action.yaml"
```

### 2. Verify Workflow File Still Auto-Included

For direct jobs in ci.yaml:
```bash
# Expected in logs: ".github/workflows/ci.yaml" in ALL_SOURCES
```

For reusable workflow jobs:
```bash
# Expected in logs: ".github/workflows/package-test.yaml" in ALL_SOURCES
```

### 3. Verify Hash-Sources Patterns Work

Test glob patterns still expand correctly:
```bash
# Job with hash-sources: 'modules/**/*.nix'
# Expected: Multiple module files in hash computation
```

### 4. Verify Cache Invalidation Works

Test that changes to cached-ci-job invalidate caches:
1. Note current cache key for a job
2. Make a whitespace-only change to `cached-ci-job/action.yaml`
3. Run job again
4. Verify cache key changed and cache miss occurred

## Related Files

### Composite Actions
- `/Users/crs58/projects/nix-workspace/infra/.github/actions/cached-ci-job/action.yaml` (lines 45-62)
- `/Users/crs58/projects/nix-workspace/infra/.github/actions/setup-nix/action.yml`

### Workflows Using cached-ci-job
- `/Users/crs58/projects/nix-workspace/infra/.github/workflows/ci.yaml` (15+ jobs)
- `/Users/crs58/projects/nix-workspace/infra/.github/workflows/package-test.yaml` (line 76)
- `/Users/crs58/projects/nix-workspace/infra/.github/workflows/deploy-docs.yaml` (line 73)
- `/Users/crs58/projects/nix-workspace/infra/.github/workflows/package-release.yaml` (line 110)

### Jobs by Type

**Direct jobs in ci.yaml** (use cached-ci-job directly):
1. secrets-scan (line 92)
2. preview-release-version (line 238)
3. bootstrap-verification (line 337)
4. config-validation (line 425)
5. autowiring-validation (line 516)
6. secrets-workflow (line 613)
7. justfile-activation (line 722)
8. cache-overlay-packages (line 906)
9. nix (line 1009)

**Reusable workflow calls** (cached-ci-job called in reusable workflow):
1. typescript → package-test.yaml (ci.yaml line 1076)
2. preview-docs-deploy → deploy-docs.yaml (ci.yaml line 311)
3. production-release-packages → package-release.yaml (ci.yaml line 1105)
4. production-docs-deploy → deploy-docs.yaml (ci.yaml line 1129)

**Total**: 13+ distinct cache usage sites

## Recommendation

**Implement Option A immediately**.

The critical bug where `cached-ci-job/action.yaml` isn't included in its own cache key computation must be fixed.
Auto-including it ensures all future changes to cache computation logic correctly invalidate existing caches.

The one-time cache invalidation is expected and beneficial - it gives us a clean slate with correct cache key computation going forward.
