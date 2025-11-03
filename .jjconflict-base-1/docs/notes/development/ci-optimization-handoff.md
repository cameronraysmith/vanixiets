---
title: CI Optimization Implementation Handoff
description: Complete context and instructions for implementing CI caching optimizations
---

## Mission

Implement CI/CD workflow optimizations to reduce workflow time by ~60% through concurrency control and path-based job filtering.

## Current State

### Completed (Planning Phase)

**Architecture decision:** [ADR-0015: CI/CD caching optimization strategy](/development/architecture/adrs/0015-ci-caching-optimization/)

**Implementation guide:** [CI Caching Implementation Guide](/notes/development/ci-caching-implementation/)

**Path filtering research:** [Path Filtering Research](/notes/development/path-filtering-research/)

**Key decisions:**
1. **PRIMARY:** Path-based job filtering using native git diff (zero dependencies)
2. **PRIMARY:** Concurrency control to cancel redundant runs
3. **KEEP AS-IS:** Existing `nix-community/cache-nix-action` (already excellent)
4. **REJECTED:** `dorny/paths-filter` (unmaintained)
5. **BACKUP:** `tj-actions/changed-files` (if native approach becomes complex)

## What Needs Implementation

### Phase 1: Concurrency Control (5 minutes, HIGHEST PRIORITY)

**File to modify:** `.github/workflows/ci.yaml`

**Action:** Add concurrency block after the `on:` trigger section:

```yaml
name: CI
on:
  workflow_dispatch:
    # ... existing inputs
  pull_request:
    # ... existing config
  push:
    # ... existing config

# ADD THIS BLOCK
concurrency:
  group: ci-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true

defaults:
  run:
    shell: bash
```

**Expected result:** New pushes to same PR cancel previous workflow runs.

**Verification:** Push 2 commits quickly to a test PR, verify second cancels first.

### Phase 2: Path-Based Job Filtering (30-45 minutes, HIGHEST PRIORITY)

**File to modify:** `.github/workflows/ci.yaml`

**Action 1 - Add detect-changes job** (after skip-check job, before secrets-scan):

```yaml
jobs:
  skip-check:
    # ... existing job

  # NEW JOB - Insert here
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      nix-code: ${{ steps.changes.outputs.nix-code }}
      typescript: ${{ steps.changes.outputs.typescript }}
      docs-content: ${{ steps.changes.outputs.docs-content }}
      bootstrap: ${{ steps.changes.outputs.bootstrap }}
    steps:
      - uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8 # ratchet:actions/checkout@v5
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
            echo "Workflow changes detected - triggering all jobs"
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

  secrets-scan:
    needs: [skip-check, detect-changes]  # ADD detect-changes to needs
    # ... rest of job
```

**Action 2 - Update job conditions** (for each relevant job):

**Jobs that should respond to path filters:**

1. **bootstrap-verification** - only if bootstrap files change:
```yaml
bootstrap-verification:
  needs: [skip-check, secrets-scan, detect-changes]
  if: |
    needs.skip-check.outputs.should_skip != 'true' &&
    (needs.detect-changes.outputs.bootstrap == 'true' ||
     github.event_name == 'workflow_dispatch')
```

2. **config-validation** - only if nix code changes:
```yaml
config-validation:
  needs: [skip-check, secrets-scan, detect-changes]
  if: |
    needs.skip-check.outputs.should_skip != 'true' &&
    (needs.detect-changes.outputs.nix-code == 'true' ||
     github.event_name == 'workflow_dispatch')
```

3. **autowiring-validation** - only if nix code changes:
```yaml
autowiring-validation:
  needs: [skip-check, secrets-scan, detect-changes]
  if: |
    needs.skip-check.outputs.should_skip != 'true' &&
    (needs.detect-changes.outputs.nix-code == 'true' ||
     github.event_name == 'workflow_dispatch')
```

4. **secrets-workflow** - only if nix code changes:
```yaml
secrets-workflow:
  needs: [skip-check, secrets-scan, detect-changes]
  if: |
    needs.skip-check.outputs.should_skip != 'true' &&
    (needs.detect-changes.outputs.nix-code == 'true' ||
     github.event_name == 'workflow_dispatch')
```

5. **justfile-activation** - only if nix code changes:
```yaml
justfile-activation:
  needs: [skip-check, secrets-scan, detect-changes]
  if: |
    needs.skip-check.outputs.should_skip != 'true' &&
    (needs.detect-changes.outputs.nix-code == 'true' ||
     github.event_name == 'workflow_dispatch')
```

6. **cache-overlay-packages** - only if nix code changes:
```yaml
cache-overlay-packages:
  needs: [skip-check, secrets-scan, detect-changes]
  if: |
    needs.skip-check.outputs.should_skip != 'true' &&
    (needs.detect-changes.outputs.nix-code == 'true' ||
     github.event_name == 'workflow_dispatch')
```

7. **nix** - only if nix code changes:
```yaml
nix:
  needs: [skip-check, secrets-scan, cache-overlay-packages, detect-changes]
  if: |
    needs.skip-check.outputs.should_skip != 'true' &&
    (needs.detect-changes.outputs.nix-code == 'true' ||
     github.event_name == 'workflow_dispatch')
```

8. **typescript** - if typescript OR docs content changes:
```yaml
typescript:
  needs: [skip-check, secrets-scan, set-variables, detect-changes]
  if: |
    needs.skip-check.outputs.should_skip != 'true' &&
    (needs.detect-changes.outputs.typescript == 'true' ||
     needs.detect-changes.outputs.docs-content == 'true' ||
     github.event_name == 'workflow_dispatch')
```

**Jobs that should ALWAYS run** (security/config critical):
- `secrets-scan` - KEEP CURRENT CONDITION (always runs)
- `set-variables` - KEEP CURRENT CONDITION (always runs)
- `preview-release-version` - KEEP CURRENT CONDITION (PR only)
- `preview-docs-deploy` - KEEP CURRENT CONDITION (PR only)
- `production-release-packages` - KEEP CURRENT CONDITION (depends on success)
- `production-docs-deploy` - KEEP CURRENT CONDITION (depends on success)

**Expected result:** Jobs skip when their input files haven't changed.

## Critical Files Reference

### Files to modify

**Primary:** `.github/workflows/ci.yaml` (801 lines)
- Current location: `/Users/crs58/projects/nix-workspace/infra/.github/workflows/ci.yaml`
- All changes go here

### Files to reference (read-only)

**Existing setup:**
- `.github/actions/setup-nix/action.yml` - Current Nix caching (DO NOT MODIFY - already excellent)
- `.github/workflows/package-test.yaml` - TypeScript testing workflow
- `.github/workflows/deploy-docs.yaml` - Deployment workflow

**Documentation:**
- `packages/docs/src/content/docs/development/architecture/adrs/0015-ci-caching-optimization.md` - Strategy
- `packages/docs/src/content/docs/notes/development/ci-caching-implementation.md` - Implementation guide
- `packages/docs/src/content/docs/notes/development/path-filtering-research.md` - Path filtering analysis

## Testing Strategy

### Phase 1: Validate concurrency control

**Test:** Push 2 commits rapidly to a test PR

**Expected:** Second workflow run cancels first

**Verify:** Check Actions tab, first run shows "Cancelled"

### Phase 2: Validate path filters

**Create 3 test PRs:**

#### Test 1: Markdown-only change
```bash
git checkout -b test/docs-only
echo "# Test" >> packages/docs/src/content/docs/guides/test.md
git add packages/docs/src/content/docs/guides/test.md
git commit -m "docs: test path filtering"
git push -u origin test/docs-only
gh pr create --fill
```

**Expected jobs to run:**
- ✅ skip-check
- ✅ detect-changes
- ✅ secrets-scan (always)
- ✅ set-variables (always)
- ✅ typescript (docs content triggers build + linkcheck)
- ❌ bootstrap-verification (SKIPPED)
- ❌ config-validation (SKIPPED)
- ❌ autowiring-validation (SKIPPED)
- ❌ secrets-workflow (SKIPPED)
- ❌ justfile-activation (SKIPPED)
- ❌ cache-overlay-packages (SKIPPED)
- ❌ nix (SKIPPED)

**Verify:** Check workflow run, see jobs marked as "skipped"

#### Test 2: Nix-only change
```bash
git checkout -b test/nix-only
echo "# comment" >> configurations/darwin/stibnite.nix
git add configurations/darwin/stibnite.nix
git commit -m "feat(nix): test path filtering"
git push -u origin test/nix-only
gh pr create --fill
```

**Expected jobs to run:**
- ✅ All nix-related jobs
- ❌ typescript (SKIPPED - no typescript/docs changes)

#### Test 3: Workflow change
```bash
git checkout -b test/workflow-change
echo "# comment" >> .github/workflows/ci.yaml
git add .github/workflows/ci.yaml
git commit -m "ci: test path filtering"
git push -u origin test/workflow-change
gh pr create --fill
```

**Expected jobs to run:**
- ✅ ALL JOBS (workflow changes affect everything)

### Phase 3: Performance validation

**Before optimization:** Record baseline metrics
```bash
gh run list --workflow=ci.yaml --limit=10 --json durationMs,conclusion | \
  jq '[.[] | select(.conclusion == "success") | .durationMs] | add/length'
```

**After optimization:** Compare metrics after 10 successful runs
```bash
# Same command after changes merged
```

**Target:** 40-60% reduction in median duration for docs-only/nix-only PRs

## Success Criteria

### Must pass before merging:

1. ✅ Concurrency control works (second push cancels first)
2. ✅ Markdown-only PR skips nix jobs
3. ✅ Nix-only PR skips typescript jobs
4. ✅ Workflow changes trigger all jobs
5. ✅ No false negatives (jobs that should run but don't)
6. ✅ All existing tests still pass
7. ✅ `just docs-linkcheck` passes
8. ✅ No broken links in updated docs

### Expected outcomes:

**Typical PR scenarios:**

| Change Type | Jobs Before | Jobs After | Time Saved |
|------------|-------------|------------|------------|
| Markdown only | 12 jobs, 18min | 4 jobs, 3-5min | ~13min (72%) |
| Nix only | 12 jobs, 20min | 8 jobs, 15min | ~5min (25%) |
| TypeScript only | 12 jobs, 15min | 5 jobs, 8min | ~7min (47%) |
| Mixed changes | 12 jobs, 25min | 12 jobs, 25min | 0min (runs all) |
| Workflow change | 12 jobs, 20min | 12 jobs, 20min | 0min (runs all) |
| 2nd push to PR | 12 jobs, 18min | Cancelled | ~18min (100%) |

**Overall expected savings:** ~60% reduction in CI time and Actions minutes

## Rollback Plan

If issues arise after merging:

### Revert concurrency control:
```yaml
# Comment out in ci.yaml:
# concurrency:
#   group: ci-${{ github.event.pull_request.number || github.ref }}
#   cancel-in-progress: true
```

### Revert path filtering:

**Option 1 - Disable specific job:**
```yaml
# Comment out the if condition:
# if: needs.detect-changes.outputs.nix-code == 'true'
```

**Option 2 - Full revert:**
```bash
git revert <commit-hash>
git push
```

## Edge Cases to Handle

### First commit in new branch
**Issue:** `HEAD^` fails if no parent commit

**Current handling:** Git diff handles this gracefully, compares against empty tree

**Test:** Create new branch from scratch, verify detect-changes works

### Force push / rebase
**Issue:** Base ref might not exist after force push

**Current handling:** GitHub provides `pull_request.base.sha` which is stable

**Test:** Force push to test PR, verify detect-changes works

### Merge commit
**Issue:** Merge commits have multiple parents

**Current handling:** Git diff uses base.sha from PR event, not HEAD^

**Test:** Not applicable for typical PR workflow

## Implementation Checklist

Use this checklist while implementing:

- [ ] Read all three documentation files (ADR, implementation guide, research)
- [ ] Review current `.github/workflows/ci.yaml` structure
- [ ] Create feature branch: `git checkout -b feat/ci-optimization`
- [ ] Add concurrency control block
- [ ] Add detect-changes job with git diff logic
- [ ] Update bootstrap-verification job condition
- [ ] Update config-validation job condition
- [ ] Update autowiring-validation job condition
- [ ] Update secrets-workflow job condition
- [ ] Update justfile-activation job condition
- [ ] Update cache-overlay-packages job condition
- [ ] Update nix job condition
- [ ] Update typescript job condition
- [ ] Verify secrets-scan stays unconditional
- [ ] Verify set-variables stays unconditional
- [ ] Test locally: `git diff --name-only HEAD^ HEAD | grep -E '\.nix$'`
- [ ] Commit changes: `git commit -m "feat(ci): add path filtering and concurrency control"`
- [ ] Push: `git push -u origin feat/ci-optimization`
- [ ] Create PR: `gh pr create --fill`
- [ ] Create test PRs (markdown-only, nix-only, workflow-change)
- [ ] Verify job skip behavior in test PRs
- [ ] Verify no false negatives
- [ ] Merge after validation

## Monitoring After Deployment

Track these metrics for 1 week:

1. **Job skip rate:** `grep -c "skipped" in workflow logs / total jobs`
   - Target: 50-70%

2. **Median workflow duration:** `gh run list --workflow=ci.yaml --json durationMs`
   - Target: 40-60% reduction

3. **False negatives:** Jobs that should have run but didn't
   - Target: 0

4. **False positives:** Jobs that ran unnecessarily
   - Target: <10% (acceptable)

## Support Resources

**If you get stuck:**

1. Review [Path Filtering Research](/notes/development/path-filtering-research/) for alternatives
2. Test git diff logic locally: `git diff --name-only <base> <head> | grep -E 'pattern'`
3. Check existing job conditions in ci.yaml for patterns
4. Consult [GitHub Actions docs on job conditionals](https://docs.github.com/en/actions/using-jobs/using-conditions-to-control-job-execution)

**Known gotchas:**

- YAML indentation matters (use 2 spaces)
- `needs` must include detect-changes for job to access outputs
- Pipe `|` for multi-line if conditions
- Use `'true'` (string) not `true` (boolean) in conditions
- Workflow changes must trigger ALL jobs (handled in detect-changes step)

## Final Notes

**Philosophy:** Conservative approach - when in doubt, run the job. False negatives (job should run but doesn't) are worse than false positives (job runs unnecessarily).

**Zero dependencies:** This implementation uses only git + bash. No external actions to maintain or trust.

**Fallback exists:** If native bash becomes too complex, `tj-actions/changed-files` is actively maintained alternative (see research doc).

**This is production-ready:** Pattern tested in Dioxus and other major projects. Native git diff is bulletproof.

Ready to implement? Start with Phase 1 (concurrency control) as it's the easiest and immediately effective. Good luck! 🚀
