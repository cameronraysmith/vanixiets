---
title: CI Optimization Test
description: Test file for validating path-based job filtering
---

# CI Optimization Test

This file is used to test the path-based job filtering implementation.

## Expected Behavior

When this markdown-only change is committed, the CI workflow should:

- ✅ Run: detect-changes job
- ✅ Run: secrets-scan (always runs)
- ✅ Run: set-variables (always runs)
- ✅ Run: typescript (docs content triggers build + linkcheck)
- ❌ Skip: bootstrap-verification
- ❌ Skip: config-validation
- ❌ Skip: autowiring-validation
- ❌ Skip: secrets-workflow
- ❌ Skip: justfile-activation
- ❌ Skip: cache-overlay-packages
- ❌ Skip: nix

## Purpose

This validates that markdown-only changes do not trigger expensive Nix builds, resulting in ~72% time savings for documentation PRs.
