# OpenSpec schema bundles

This directory holds every OpenSpec schema bundle this repository maintains.
Each is delivered user-global to `~/.local/share/openspec/schemas/<name>/`, the same collection every other repository resolves from, by the `programs.openspec.schemaDirs` option in `../../default.nix`.
Adding a bundle means creating a directory here and adding its name to that option's list.

Both bundles originated upstream and have since diverged substantially under our maintenance.
They are ours to edit.
This repository is a dendritic flake-parts configuration composed with `import-tree`: every `.nix` file under `modules/` must be a valid flake-parts module, and each is discovered and activated by virtue of existing.
A directory of non-nix payload files that those modules read and deliver is therefore an asset directory relative to that architecture, not a leftover from the bundle's vendored origin.
An earlier revision of this file described its contents as vendored third-party bundles pinned to an upstream commit; that was inaccurate.
The refresh script `modules/apps/openspec-refresh-vendored-artifacts.sh` does not touch this tree.

There is deliberately no project-tier override anywhere in this repository.
An earlier arrangement symlinked a bundle into `openspec/schemas/` so edits took effect without activation, which had the effect of making this repository resolve a schema state no other repository had.
A schema edit now takes effect on the next activation, the same latency every consumer has.

## superpowers-bridge

Forked from `github.com/JiangWay/openspec-schemas` (the `superpowers-bridge/` bundle within it), whose head is `f5d4040`, "docs(superpowers-bridge): bump OpenSpec baseline to 1.4.1", 2026-06-10.
A local reference copy of upstream is at `~/ghq/github.com/JiangWay/openspec-schemas`.

The fork does not track upstream and has diverged by +79 / −29 lines in `schema.yaml` against upstream head, plus seven of nine templates and `templates/adopters/CLAUDE.md.fragment.md`.
Re-deriving is a deliberate three-way merge, never a copy.

Our changes, as distinct from upstream's content: CLI-resolved artifact paths replace hardcoded repo-local ones throughout, so instructions read `artifactPaths.tasks.existingOutputPaths`, `artifactPaths.specs.existingOutputPaths`, and `artifactPaths.brainstorm` from `openspec status --change <name> --json`; and the `actionContext.mode == "workspace-planning"` precondition guards on the apply, verify, and retrospective entry points, which are ours rather than upstream's.

Those guards are dead on OpenSpec 1.10.0, where `ActionContext.mode` is the single literal `"repo-local"` — the guard is unreachable and degrades to always-proceed.
They are retained here because this bundle is frozen (below); the WRSPM fork removes them.

The two Traditional-Chinese localization files, `README.zh-TW.md` and `templates/adopters/CLAUDE.md.fragment.zh-TW.md`, are absent from this copy.
Neither is consumed by the CLI, which reads only `schema.yaml` and `templates/*.md`.

This bundle requires the superpowers Claude plugin: it invokes `superpowers:`-namespaced skills — brainstorming, writing-plans, using-git-worktrees, subagent-driven-development, finishing-a-development-branch — and stops if they are absent.

### Status: frozen reference

Not the target for new work; `superpowers-bridge-wrspm` supersedes it.

It nevertheless stays delivered, and must.
A change records its schema in its own `.openspec.yaml` at creation and is never repinned, so withdrawing this bundle would strand every change already pinned to `superpowers-bridge` with an unresolvable schema and no diagnostic beyond the `schema=` attribute of `openspec instructions` output.
One in-flight change is so pinned as of 2026-11-27: `validate-harborize-instrument`.

Fix it only where an in-flight change pinned to it is actually blocked; carry anything forward-looking into the WRSPM fork instead.

## superpowers-bridge-wrspm

A fork of `superpowers-bridge` adding a WRSPM stratum layer.
Its ancestry is therefore two forks deep, and upstream is a reference rather than a merge base.

The reason to fork rather than edit the parent in place is the schema pin, discovered after the fact: editing the parent would have retroactively changed the governing schema under every change already pinned to it.
Forking leaves those changes on the bundle they were authored against.

### What it adds

A per-capability stratum tag in the `proposal` artifact — `world`, `interface`, or `behavioral` — carried as part of the existing proposal-to-specs contract.

Stratum-conditional vocabulary rules in the `specs` artifact.
Behavioral deltas use world vocabulary and resolve every content noun against a designation table.
World deltas state indicative assumptions whose scenarios are violation and monitoring conditions, which is obstacle analysis expressed in the native Requirement-and-Scenario grammar.
Interface deltas mention only shared phenomena and state their trust boundary.

A non-blocking section 8 in the `verify` artifact: designation lint, discharge coherence, and an alphabet check, each warn-and-record in the spirit of the existing section 7.
These are agent-executed. `openspec validate` checks markdown structure and delta well-formedness only, and checks no vocabulary grounding, alphabet discipline, or entailment — section 8 is not validation and must not be reported as such.

Satisfaction-projection regeneration in the apply phase's archive step, writing `packages/docs/src/content/docs/development/traceability/satisfaction.md` from the post-sync corpus, rebuilt wholesale rather than patched.
It deliberately does not live under `openspec/`: artifact outputs are confined to their change directory by path assertion, and the only sanctioned corpus writers are the archive merge and the sync skill, both delta-mediated and scoped to `openspec/specs/`.

### What it changes for maintenance reasons

The three dead `workspace-planning` guards inherited from the parent are removed.

The per-task `— verify:` convention and the closing `## Integration Verification` group were adopted from upstream OpenSpec 1.10.0's own tasks template, which the parent had not tracked.

The declared OpenSpec baseline moved from 1.4.1 to 1.10.0.

## Known upstream defects at this baseline

`rules` keyed to the `tasks` artifact are silently dropped: `openspec instructions tasks --json` carries no `rules` key while sibling artifacts carry theirs, and no warning is emitted.
`tasks` is the artifact the apply phase `tracks:`, which is the likely cause.
Task-level guidance must therefore live in a schema's own `tasks` instruction or in a project's `context`; do not add `rules.tasks`, because it would look live and be inert.

A change pins its schema in `.openspec.yaml` at creation. Renaming the schema in `openspec/config.yaml` does not repin existing changes, and the mismatch is reported nowhere except the `schema=` attribute of `openspec instructions` output.

`openspec schema fork` fails against a read-only source tree, preserving mode 444 on its staging copy and then failing to write it with `EACCES`. It also renames the result, so it would not shadow the original.
