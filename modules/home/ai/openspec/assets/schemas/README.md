# Vendored OpenSpec schema bundles

This directory holds vendored third-party OpenSpec schema bundles that are delivered user-global through the crs58 home-manager module.
Each bundle is a self-contained schema directory that the OpenSpec CLI selects per change.

## superpowers-bridge

The `superpowers-bridge` bundle is vendored from github.com/JiangWay/openspec-schemas (the `superpowers-bridge/` bundle within that repository).
It is pinned to commit 0366ed5; no git tag is pushed upstream despite the bundle's `VERSION` file reading 1.0.0.
The bundle is baselined against OpenSpec 1.4.1 and the superpowers plugin v5.1.0, which matches this repository's environment.

The two `*.zh-TW.md` Traditional-Chinese localization files (`README.zh-TW.md` and `templates/adopters/CLAUDE.md.fragment.zh-TW.md`) were excluded from the vendored copy.
They are not consumed by the OpenSpec CLI, which reads only `schema.yaml` and `templates/*.md`.

This bundle requires the superpowers Claude plugin to be installed.
It invokes `superpowers:`-namespaced skills (brainstorming, writing-plans, using-git-worktrees, subagent-driven-development, finishing-a-development-branch) and stops if they are absent.
It is additive governance layered on top of the plugin, not a replacement for it.

### Delivery and selection

The bundle is delivered user-global to `~/.local/share/openspec/schemas/superpowers-bridge/` via the crs58 home-manager module.
It is selected per change with `openspec new --schema superpowers-bridge`.
Each project still needs `openspec init` first.

### Refresh

To refresh the vendored copy from the local source, run:

```
cp -R ~/projects/planning-workspace/openspec-schemas-superpowers-bridge/superpowers-bridge/. modules/home/ai/openspec/assets/schemas/superpowers-bridge/ && find modules/home/ai/openspec/assets/schemas/superpowers-bridge -name '*.zh-TW.md' -delete
```
