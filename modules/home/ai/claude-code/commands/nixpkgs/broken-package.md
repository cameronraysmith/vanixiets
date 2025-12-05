Triage a broken nixpkg after flake update.

Error from: [nix flake check / darwin-rebuild switch / nix build ...]
```
$ARGUMENTS
```

## Quick reference

| Scenario | Strategy | File |
|----------|----------|------|
| Single package broken | Stable fallback | modules/nixpkgs/overlays/hotfixes.nix |
| Tests fail only | Build modification | modules/nixpkgs/overlays/overrides.nix |
| Fix exists in PR | Upstream patch | modules/nixpkgs/overlays/channels.nix |
| Multiple packages broken | Flake.lock rollback | flake.lock |

## Context to load

Read these files to understand current state and patterns:

Documentation:
@packages/docs/src/content/docs/guides/handling-broken-packages.md

Current overlays (see existing patterns):
@modules/nixpkgs/overlays/hotfixes.nix
@modules/nixpkgs/overlays/channels.nix
@modules/nixpkgs/overlays/overrides.nix

Architecture (if needed):
@packages/docs/src/content/docs/development/architecture/adrs/0017-dendritic-overlay-patterns.md

## Workflow

1. Identify broken package(s) from error output
2. Check upstream status:
   - Hydra: https://hydra.nixos.org/job/nixpkgs/trunk/PACKAGE.SYSTEM
   - GitHub: search nixpkgs issues/PRs for this package
3. Assess scope (single package? multiple? platform-specific?)
4. Match scenario to strategy using quick reference above
5. Draft implementation following patterns in existing overlay files

## Output format

Present findings:
- **Package(s)**: name and system(s) affected
- **Root cause**: why it's broken (compiler issue, test failure, dependency)
- **Upstream status**: links to hydra/issues/PRs
- **Recommended strategy**: A/B/C/D with rationale
- **Implementation**: exact code change with file path

Wait for approval before implementing.
