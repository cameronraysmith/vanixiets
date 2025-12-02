---
title: CI Caching Troubleshooting Guide
description: Diagnose and resolve issues with content-addressed CI caching
---

## Common Issues

### Cache Not Working (Jobs Always Running)

**Symptoms:**
- Jobs run on every commit despite no relevant changes
- `should-run` output always `true`

**Diagnosis:**

```bash
# Check composite action logs in GitHub Actions UI
# Look for "Cache hit" vs "No cache found" messages
```

**Common causes:**

1. **Check name mismatch**
   - Logs show: "Check name validation failed"
   - Solution: Verify check-name parameter matches GitHub's format
   - Template: `job-{hash}` or `job-{hash} (param1, param2)`

2. **Path filters too narrow**
   - Logs show: "No relevant changes detected"
   - Solution: Review path-filters regex, ensure captures all dependencies
   - Example: Missing transitive dependencies

3. **GitHub Checks API failure**
   - Logs show: "API query failed after 3 attempts"
   - Solution: Wait and retry, check GitHub status page
   - Temporary issue: Jobs run as failsafe

**Resolution steps:**

```bash
# 1. Check recent workflow runs
gh run list --workflow=ci.yaml --limit=5

# 2. View specific run logs
gh run view <run-id> --log

# 3. Search for cache decision logs
gh run view <run-id> --log | grep "should-run"

# 4. Force run to test
gh workflow run ci.yaml -f force_run=true
```

### Jobs Skipped When They Should Run

**Symptoms:**
- Changes made but job skipped
- Test failures not caught until later

**Diagnosis:**

```bash
# Check if check run exists from previous commit
gh api repos/$OWNER/$REPO/commits/$SHA/check-runs \
  --jq '.check_runs[] | select(.name | contains("job-name"))'
```

**Common causes:**

1. **Stale check from force-push**
   - Old check run still present after force-push
   - Solution: Wait 24 hours (automatic expiration)
   - Workaround: Use force_run=true parameter

2. **Path filters too broad**
   - Filters don't detect relevant changes
   - Solution: Make filters more precise
   - Example: `\.nix$` misses `.nix.example` files

3. **Workflow definition changed**
   - Config hash changed, check name different
   - Solution: This should auto-invalidate (check implementation)

**Resolution steps:**

```bash
# 1. Force run specific job
gh workflow run ci.yaml -f job=job-name -f force_run=true

# 2. Check path filters match changed files
git diff --name-only HEAD~1 | grep -E 'your-filter-regex'

# 3. Verify check name format
# Look in GitHub UI: Actions → Workflow Run → Check names
```

### Rate Limit Errors

**Symptoms:**
- Logs show: "GitHub API rate limit exceeded"
- Multiple workflows failing simultaneously

**Diagnosis:**

```bash
# Check rate limit status
gh api rate_limit
```

**Solution:**

1. **Wait for reset:**
   ```bash
   # Check reset time (shown in error logs)
   # Rate limit resets: [timestamp]
   ```

2. **Reduce workflow frequency:**
   - Combine multiple small commits
   - Use draft PRs for work-in-progress
   - Disable workflow on WIP branches

3. **Temporary workaround:**
   ```bash
   # Use workflow_dispatch with selective jobs
   gh workflow run ci.yaml -f job=specific-job
   ```

### Production Deployment with Stale Results

**Symptoms:**
- Production release succeeded but builds were cached
- Tests didn't actually run

**Expected behavior:**
- Main branch: All jobs forced to run fresh
- Production releases: Always use force_run=true

**Diagnosis:**

```bash
# Check if production job dependency was skipped
gh run view <run-id> --log | grep "typescript.*skipped"
gh run view <run-id> --log | grep "nix.*skipped"
```

**This should never happen** after Agent 2 implementation:
- Main branch forces fresh builds
- Production requires success (not skipped)

**If it happens:**

```bash
# 1. Check force-run parameter
grep "force-run" .github/workflows/ci.yaml

# 2. Verify job conditions
grep -A5 "production-release-packages" .github/workflows/ci.yaml

# 3. Immediately force fresh build
gh workflow run ci.yaml -f force_run=true
```

## Debugging Techniques

### View Cache Decision Process

```bash
# Get workflow run logs
gh run view <run-id> --log > run.log

# Search for cache decision steps
grep "=== Execution Decision ===" run.log -A10

# Search for validation steps
grep "=== Check Name Validation ===" run.log -A10

# Search for API calls
grep "Querying execution history" run.log -A5
```

### Verify Check Name Format

```bash
# List all checks for a commit
gh api repos/$OWNER/$REPO/commits/$SHA/check-runs \
  --jq '.check_runs[].name' | sort

# Compare with expected format
# Expected: job-{8-hex-chars} (params)
# Example: nix-a1b2c3d4 (packages, x86_64-linux)
```

### Test Composite Action Locally

```bash
# Run test workflow
gh workflow run test-composite-actions.yaml

# View results
gh run list --workflow=test-composite-actions.yaml --limit=1
gh run view <run-id> --log
```

### Check Configuration Hash

```bash
# Hash should change when workflow/action changes
git log --oneline -1 .github/workflows/ci.yaml
git log --oneline -1 .github/actions/cached-ci-job/action.yaml

# Check name should include hash
gh run view <run-id> --log | grep "Resolved check name"
```

## Emergency Procedures

### Disable Caching Globally

If caching is causing critical issues:

```bash
# Edit composite action
git checkout -b disable-cache

# In .github/actions/cached-ci-job/action.yaml
# Change decide step to always return:
echo "should-run=true" >> $GITHUB_OUTPUT

# Commit and push
git commit -am "temp: disable CI caching"
git push -u origin disable-cache

# Create emergency PR
gh pr create --title "EMERGENCY: Disable CI caching" --body "Debugging cache issue"
```

### Force All Jobs to Run

```bash
# For specific PR
gh workflow run ci.yaml -f force_run=true

# For main branch (production)
git checkout main
git commit --allow-empty -m "force: trigger fresh builds"
git push
```

## Prevention

### Before Changing Workflows

1. **Test in PR first:**
   ```bash
   # Make changes in feature branch
   # Push and observe cache behavior
   # Verify check names in GitHub UI
   ```

2. **Use test workflow:**
   ```bash
   gh workflow run test-composite-actions.yaml --ref feature-branch
   ```

3. **Monitor first few runs:**
   - Check for validation failures
   - Verify cache hits/misses as expected
   - Review new check name formats

### Regular Audits

```bash
# Monthly review of cache effectiveness
gh run list --workflow=ci.yaml --limit=50 --json conclusion,name,durationMs

# Check for anomalies
# - Duration spikes (cache not working)
# - All jobs completing too fast (over-caching)
```

## Getting Help

If troubleshooting doesn't resolve the issue:

1. **Check documentation:** Review ADR-0016 for architecture details
2. **Review recent changes:** `git log --oneline .github/actions/cached-ci-job/`
3. **File an issue:** Include workflow run URL and relevant logs
4. **Emergency contact:** Disable caching as interim solution

## Additional Resources

- [ADR-0016: Per-job content-addressed caching](/development/architecture/adrs/0016-per-job-content-addressed-caching/)
- [GitHub Checks API documentation](https://docs.github.com/en/rest/checks/runs)
- [tj-actions/changed-files documentation](https://github.com/tj-actions/changed-files)
