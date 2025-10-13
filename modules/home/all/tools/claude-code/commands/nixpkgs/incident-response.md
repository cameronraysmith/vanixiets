Nixpkgs breakage incident after flake update.

Error from: [nix flake check / darwin-rebuild switch / nix build ...]
```
[paste error output here]
```

Follow @docs/notes/nixpkgs-incident-response.md workflow:
1. Read the incident response guide and hotfixes architecture docs
2. Identify broken package(s) from error
3. Check upstream status:
   - GitHub nixpkgs issues/PRs for this package
   - Hydra build status (https://hydra.nixos.org/job/nixpkgs/trunk/PACKAGE.SYSTEM)
4. Assess scope (single package? multiple? platform-specific?)
5. Recommend strategy (stable fallback / upstream patch / override)
6. Draft implementation with rationale

Present findings in structured format:
- Package(s) affected
- Root cause
- Upstream status summary (links to issues/PRs/hydra)
- Recommended strategy with why
- Implementation plan (which file to edit, exact changes)

Wait for my approval before implementing.
