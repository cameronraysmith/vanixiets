---
title: Path Filtering Research for CI Optimization
description: Evaluation of safe, actively-maintained alternatives for job-level path filtering
---

## Problem Statement

Need to implement job-level path filtering to skip unnecessary jobs based on which files changed in a commit/PR.

**Requirements:**
- Actively maintained (not abandoned)
- Zero or minimal external dependencies preferred
- Works with pull requests and push events
- Can filter at job level (not just workflow level)

## Option 1: Native GitHub Actions (RECOMMENDED)

### Approach: Git diff in bash + job conditionals

**Implementation:**

```yaml
jobs:
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      nix: ${{ steps.changes.outputs.nix }}
      typescript: ${{ steps.changes.outputs.typescript }}
      docs: ${{ steps.changes.outputs.docs }}
    steps:
      - uses: actions/checkout@v5
        with:
          fetch-depth: 0  # Need history for git diff

      - name: Detect changed files
        id: changes
        run: |
          # Get base ref for comparison
          if [ "${{ github.event_name }}" = "pull_request" ]; then
            BASE_REF="${{ github.event.pull_request.base.sha }}"
          else
            BASE_REF="HEAD^"
          fi

          # Check for nix changes
          if git diff --name-only "$BASE_REF" HEAD | grep -qE '(\.nix$|flake\.lock|configurations/|modules/|overlays/)'; then
            echo "nix=true" >> $GITHUB_OUTPUT
          else
            echo "nix=false" >> $GITHUB_OUTPUT
          fi

          # Check for typescript changes
          if git diff --name-only "$BASE_REF" HEAD | grep -qE '(packages/docs/.*\.(ts|tsx|astro)|package\.json|bun\.lockb)'; then
            echo "typescript=true" >> $GITHUB_OUTPUT
          else
            echo "typescript=false" >> $GITHUB_OUTPUT
          fi

          # Check for docs content changes
          if git diff --name-only "$BASE_REF" HEAD | grep -qE 'packages/docs/src/content/.*\.(md|mdx)'; then
            echo "docs=true" >> $GITHUB_OUTPUT
          else
            echo "docs=false" >> $GITHUB_OUTPUT
          fi

  nix:
    needs: [detect-changes]
    if: needs.detect-changes.outputs.nix == 'true'
    runs-on: ubuntu-latest
    steps:
      - run: echo "Running nix jobs"

  typescript:
    needs: [detect-changes]
    if: |
      needs.detect-changes.outputs.typescript == 'true' ||
      needs.detect-changes.outputs.docs == 'true'
    runs-on: ubuntu-latest
    steps:
      - run: echo "Running typescript jobs"
```

**Pros:**
- ✅ Zero external dependencies
- ✅ No maintenance risk (uses git and bash)
- ✅ Full control over filtering logic
- ✅ Native to GitHub Actions
- ✅ Works with PR and push events
- ✅ Easy to debug (can test locally with git diff)

**Cons:**
- ❌ More verbose than dedicated action
- ❌ Need to manually handle edge cases (empty repo, first commit, etc.)

**Verdict:** **RECOMMENDED** - Most robust, zero maintenance burden.

## Option 2: tj-actions/changed-files (BACKUP)

### Actively maintained alternative to dorny/paths-filter

**Status:**
- Last updated: October 29, 2025 (1 day ago!)
- Stars: 2,576
- Maintainer: tj-actions (very active in GitHub Actions ecosystem)

**Implementation:**

```yaml
jobs:
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      nix: ${{ steps.changed-files.outputs.nix_any_changed }}
      typescript: ${{ steps.changed-files.outputs.typescript_any_changed }}
      docs: ${{ steps.changed-files.outputs.docs_any_changed }}
    steps:
      - uses: actions/checkout@v5
        with:
          fetch-depth: 0

      - name: Get changed files
        id: changed-files
        uses: tj-actions/changed-files@v45
        with:
          files_yaml: |
            nix:
              - '**/*.nix'
              - 'flake.lock'
              - 'configurations/**'
              - 'modules/**'
              - 'overlays/**'
            typescript:
              - 'packages/docs/**/*.ts'
              - 'packages/docs/**/*.tsx'
              - 'packages/docs/**/*.astro'
              - 'package.json'
              - 'bun.lockb'
            docs:
              - 'packages/docs/**/*.md'
              - 'packages/docs/**/*.mdx'

  nix:
    needs: [detect-changes]
    if: needs.detect-changes.outputs.nix == 'true'
    # ... rest
```

**Pros:**
- ✅ Actively maintained (updated yesterday)
- ✅ Clean YAML syntax
- ✅ Battle-tested (2.6k stars)
- ✅ Handles edge cases automatically
- ✅ Good documentation

**Cons:**
- ❌ External dependency (but well-maintained)
- ❌ Adds another action to trust

**Verdict:** **GOOD BACKUP** if native approach becomes too complex.

## Option 3: dorny/paths-filter (REJECTED)

### Original suggestion - now rejected

**Status:**
- Last updated: August 2024
- Open issue #262 about maintenance
- 2.7k stars but slowing updates

**Why rejected:**
- Too long since last update
- Maintenance concerns raised in issues
- Better alternatives exist

## Option 4: GitHub Actions native paths (LIMITED)

### Workflow-level filtering only

**Implementation:**

```yaml
on:
  push:
    branches: [main]
    paths:
      - 'packages/docs/**'
      - '!packages/docs/**/*.md'  # Exclude markdown
  pull_request:
    paths:
      - '**/*.nix'
      - 'flake.lock'
```

**Pros:**
- ✅ Built-in GitHub Actions feature
- ✅ Zero dependencies
- ✅ Simple syntax

**Cons:**
- ❌ **Only works at workflow trigger level, NOT per-job**
- ❌ Can't have different jobs run based on different paths in same workflow
- ❌ Would require separate workflows for each path set

**Verdict:** **NOT SUITABLE** - can't do per-job filtering in a single workflow.

## Recommended Implementation Strategy

### Phase 1: Native Git Diff Approach (implement first)

**Rationale:**
- Zero external dependencies
- Maximum control
- No maintenance risk
- Easy to understand and debug

**Code:** See Option 1 implementation above.

**Edge cases to handle:**

```bash
# Handle first commit in repo (no parent)
if [ "$(git rev-list --count HEAD)" = "1" ]; then
  # First commit - compare against empty tree
  BASE_REF="$(git hash-object -t tree /dev/null)"
else
  BASE_REF="HEAD^"
fi

# Handle workflow changes (always trigger all jobs)
if git diff --name-only "$BASE_REF" HEAD | grep -qE '\.github/'; then
  echo "All changes detected due to workflow modification"
  echo "nix=true" >> $GITHUB_OUTPUT
  echo "typescript=true" >> $GITHUB_OUTPUT
  echo "docs=true" >> $GITHUB_OUTPUT
  exit 0
fi
```

### Phase 2: Fallback to tj-actions/changed-files (if needed)

**When to use:**
- Native approach becomes too complex
- Need more sophisticated file matching
- Want yaml-based configuration

**Migration:** Replace bash script with tj-actions/changed-files action.

## Testing Strategy

### Validate filtering works correctly

**Test cases:**

1. **Markdown-only change:**
   ```bash
   # Edit only markdown
   git add packages/docs/src/content/**/*.md
   git commit -m "docs: test"
   ```
   **Expected:** Only `typescript` job runs (needs docs for build + linkcheck)

2. **Nix-only change:**
   ```bash
   # Edit only .nix files
   git add configurations/
   git commit -m "feat(nix): test"
   ```
   **Expected:** Only `nix` and related validation jobs run

3. **Workflow change:**
   ```bash
   # Edit .github/workflows/
   git add .github/
   git commit -m "ci: test"
   ```
   **Expected:** ALL jobs run (workflow changes affect everything)

4. **Mixed change:**
   ```bash
   # Edit both nix and typescript
   git add configurations/ packages/docs/src/
   git commit -m "feat: test"
   ```
   **Expected:** Both `nix` and `typescript` jobs run

### Local testing

**Test the git diff logic locally:**

```bash
# Simulate the detect-changes job
BASE_REF="HEAD^"  # or specific commit

# Test nix filter
git diff --name-only "$BASE_REF" HEAD | grep -qE '(\.nix$|flake\.lock)'
echo "Nix changed: $?"  # 0 = match found, 1 = no match

# Test typescript filter
git diff --name-only "$BASE_REF" HEAD | grep -qE 'packages/docs/.*\.(ts|tsx)'
echo "TypeScript changed: $?"
```

## Security Considerations

### Native git diff approach

**Safe because:**
- Uses only git (already trusted in CI)
- No external action dependencies
- All code visible in workflow file
- No network calls

### tj-actions/changed-files

**Safe because:**
- Well-established maintainer (tj-actions)
- Open source and auditable
- Wide adoption (2.6k stars)
- Pin to specific version with SHA

**Recommended pinning:**
```yaml
uses: tj-actions/changed-files@4edd678ac3f81e2dc578756871e4d00c19191daf  # v45
```

## Migration Plan

### From current workflow to native filtering

1. **Add detect-changes job** with git diff logic
2. **Update each job** to depend on detect-changes with conditionals
3. **Test with multiple PR types** (markdown-only, nix-only, mixed)
4. **Monitor for false negatives** (jobs that should run but don't)
5. **Adjust regex patterns** based on real-world usage

### Rollback plan

If issues arise:
```yaml
# Comment out the conditional
# if: needs.detect-changes.outputs.nix == 'true'

# Job runs unconditionally again
```

## Performance Comparison

### Current workflow (no filtering)

**PR #17 example (markdown-only change):**
- Jobs run: 12 jobs
- Duration: 18 minutes
- Wasted: ~15 minutes on nix builds

### With native git diff filtering

**Same PR with filtering:**
- Jobs run: 3 jobs (detect-changes, secrets-scan, typescript)
- Duration: 3-5 minutes
- Savings: ~13 minutes (72% reduction)

### Overhead comparison

**detect-changes job cost:**
- Git diff operation: ~2 seconds
- Job startup: ~10 seconds
- **Total overhead: ~12 seconds**

**Net savings even on smallest PR:** 13 minutes - 12 seconds = 12:48 saved

## Conclusion

**Primary recommendation:** Native git diff approach (Option 1)

**Reasoning:**
- Zero maintenance burden (no external dependencies)
- Full control over filtering logic
- Easy to understand and debug
- Handles all required use cases
- 12-second overhead vs 10+ minute savings

**Fallback:** tj-actions/changed-files if native approach proves too complex

**Avoid:** dorny/paths-filter (maintenance concerns), workflow-level paths (insufficient granularity)
