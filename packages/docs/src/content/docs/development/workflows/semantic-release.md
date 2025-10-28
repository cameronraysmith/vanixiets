---
title: Semantic Release Version Preview Tool
---

## Prompt for implementation

You are a development tooling engineer specializing in semantic versioning automation for monorepo and polyrepo workflows.

Your task is to create a local development command that previews semantic-release version bumps before merging branches.

### Current workspace context

<workspace>
- Primary target: `~/projects/nix-workspace/nix-config/` (beta branch)
- Reference implementations:
  - `~/projects/nix-workspace/typescript-nix-template/`
  - `~/projects/nix-workspace/python-nix-template/`
- Additional resources:
  - `~/projects/semantic-release-monorepo` (library source)
  - `~/projects/semantic-release` (tool source)
</workspace>

<current_state>
nix-config already has:
- package.json with bun@1.1.38 as packageManager
- Existing script: `"test-release": "semantic-release --dry-run --no-ci"`
- semantic-release-monorepo configuration
- justfile with CI/CD recipes
- Support for main branch (production) and beta branch (prerelease)
</current_state>

<ci_patterns>
Python template workflow (`.github/workflows/package-release.yaml`):
- Line 151: `yarn workspace ${{ inputs.package-name }} test-release -b ${{ inputs.checkout-ref }}`
- Uses cycjimmy/semantic-release-action with dry_run parameter

TypeScript template workflow (`.github/workflows/release.yaml`):
- Lines 64-71: `bunx semantic-release --dry-run`
- Direct invocation in package directory
</ci_patterns>

<branch_config>
nix-config package.json includes:
```json
"branches": [
  {
    "name": "main"
  }
]
```

python-nix-template includes beta prerelease:
```json
"branches": [
  {
    "name": "main"
  },
  {
    "name": "beta",
    "prerelease": true
  }
]
```
</branch_config>

### Problem statement

The existing `test-release` script runs semantic-release dry-run in the current git context, but doesn't answer the question: "What version would I get if I merged this branch to main right now?"

<requirements>
You need to create a tool that:
1. Determines the version bump that would occur when merging current branch to the default branch
2. Works correctly with both single-repo and monorepo configurations
3. Handles prerelease branches (beta) and production branches (main)
4. Can be invoked via a just recipe for consistency with existing workflows
</requirements>

### Investigation phase

<investigation_tasks>
1. Examine the existing CI workflows to understand version-checking patterns:
   - Read `~/projects/nix-workspace/python-nix-template/.github/workflows/package-release.yaml`
   - Read `~/projects/nix-workspace/typescript-nix-template/.github/workflows/release.yaml`
   - Note how they handle branch parameters and dry-run modes

2. Understand semantic-release branch configuration:
   - Compare nix-config's package.json with both templates
   - Note differences in branch configuration (main only vs main+beta)
   - Identify monorepo-specific settings (extends: "semantic-release-monorepo")

3. Test the current behavior:
   - Run existing `bun run test-release` in nix-config
   - Document what output it produces
   - Identify what information is missing for the preview use case
</investigation_tasks>

### Implementation phase

<implementation_tasks>
1. Create enhanced bun script in package.json:
   - Name: `preview-version` (distinct from `test-release`)
   - Accept optional branch parameter (default: repository default branch)
   - Use semantic-release dry-run mode with appropriate flags
   - Parse and display the version that would be created
   - Handle monorepo workspace context if applicable

2. Add just recipe:
   - Name: `preview-version` or similar
   - Group: `[group('CI/CD')]` to match existing pattern
   - Invoke the bun script with appropriate environment
   - Accept optional branch parameter
   - Provide clear documentation comment

3. Ensure generalization:
   - Solution should work in nix-config without modifications
   - Should be portable to typescript-nix-template with minimal changes
   - Document what would be needed for python-nix-template (bun integration)
</implementation_tasks>

### Success criteria

<success_criteria>
The solution is complete when:

1. Running `just preview-version` in nix-config on the beta branch shows what version tag would be created if merged to main
2. The output clearly distinguishes between "current branch version" and "version after merge to main"
3. The command runs in under 10 seconds (dry-run should be fast)
4. The implementation uses bun for performance (not yarn/npm)
5. Documentation explains:
   - What the command does
   - How it differs from `test-release`
   - How to use it before creating PRs
   - How to adapt it for other repositories
</success_criteria>

### Constraints

<constraints>
- Use bun for script execution (packageManager is bun@1.1.38)
- Follow existing justfile patterns and grouping conventions
- Do not modify semantic-release configuration (branches, plugins, etc.)
- The tool should be read-only (no git operations that modify state)
- Respect the user's preference guidelines from ~/.claude/commands/preferences/
</constraints>

### Deliverables

<deliverables>
Provide the following in your response:

1. **Analysis summary** (2-3 paragraphs):
   - How CI workflows currently check versions
   - Key differences between current test-release and desired preview-version
   - Technical approach for branch comparison

2. **Implementation**:
   - Updated package.json with new script
   - New just recipe with documentation
   - Any helper scripts if needed

3. **Usage documentation** (markdown format):
   - Command syntax and examples
   - Expected output format
   - Troubleshooting common issues
   - Adaptation guide for typescript-nix-template and python-nix-template

4. **Testing verification**:
   - Commands to verify the implementation works
   - Expected output for the beta branch scenario
   - Edge cases to test (no commits since last tag, breaking changes, etc.)
</deliverables>

### Execution approach

Begin by reading the CI workflow files to understand the current implementation patterns, then proceed with your analysis and implementation.

Work systematically through the investigation phase before starting implementation to ensure you understand the existing patterns and can create a solution that fits naturally into the existing tooling ecosystem.
