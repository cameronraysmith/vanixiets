# Archived overlay packages

These packages were in the legacy `overlays/packages/` directory in infra but were not migrated to test-clan during Epic 1.
They are archived here for reintegration when stibnite-specific configuration is migrated in Epic 2.

## Packages

- `atuin-format/` - Custom atuin format script (nushell)
- `starship-jj.nix` - Starship prompt with jujutsu integration

## Migration target

These should be migrated to `pkgs/by-name/` following the drupol flat pattern when needed.

## Already migrated (not archived)

The following packages were already migrated to the dendritic structure in test-clan:

- `ccstatusline` → `pkgs/by-name/ccstatusline/`
- `markdown-tree-parser` → `modules/nixpkgs/overlays/markdown-tree-parser.nix`

## Reference

- Story 2.3: Wholesale migration from test-clan to infra
- Story 2.6: Stibnite config migration (will need these packages)
