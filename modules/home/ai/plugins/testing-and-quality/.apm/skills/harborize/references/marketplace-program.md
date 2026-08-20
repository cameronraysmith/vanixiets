# Marketplace validation program (vanixiets) — state and plan

Context for any session picking this up fresh.
The instrument, meaning this skill, and the program below were developed against the apm marketplace at github.com/cameronraysmith/vanixiets (ghq canonical path).
Consume plugins through the apm CLI (>= 0.28.0; portable form `cameronraysmith/vanixiets/modules/home/ai/plugins/<group>#main`).

Instrument versions are tracked from now on.
`0.1.0` is the as-authored baseline already committed; `0.2.0` is the repair round that produced the current text.
Evaluation results are indexed by the instrument version that produced them, so cross-version comparisons stay honest, and the instrument is not modified while an evaluation is being authored — revisions happen between rounds.

## Two subjects, one census

The deployed tree is the evaluation subject.
It is what a harness actually reads: 172 skill directories under `~/.claude/skills`, flat, one directory per skill, with no plugin directories and no `.apm/` paths, produced by composing the apm packages plus a few unmanaged skills.
A hermetic run can census the compose output instead, which differs from the delivered tree by any skill installed outside the composition.

The first-party source tree is the refactor subject.
It is `modules/home/ai/plugins/<group>/.apm/skills/`, 18 plugins and 129 skills.
Refactor edits land there; measurements are taken on the deployed field.

The deployed field is about a third larger than the first-party source field, 172 skills against 129, because 43 of the deployed skills belong to no first-party plugin and the census records them under the `<external>` sentinel.
Those skills compete for the same trigger surface as the first-party ones.
A stage-2 selection-competition simulation run over the first-party descriptions alone understates interference by that margin, so it must run over the deployed field.

Units follow from this.
The unit of ablation is the skill; a plugin unit is derived as the union of its member skills' folders through the skill-to-plugin membership map the census emits, because a flat tree has no plugin directory to point at.
See `references/lattice-design.md` for the lattice and `scripts/materialize_conditions.py --membership` for the mechanism.

Counts and rankings in this file are a snapshot, and every one of them was reproduced against the current tree when this text was last revised.
The skill bundles a source census at `census.json`, whose `provenance` block records the root, layout, revision and script version it was taken at, and which doubles as the `--membership-from` input the deployed census needs.
Re-run `scripts/census.py` against both roots and read the numbers from its output rather than quoting them from here.

The source tree gives 26 command-style skills (`disable-model-invocation`), 54 env-coupled skills (`~/...` references), and a decidable-versus-subjective split of 27 to 102.
The deployed tree gives 39, 57, and 36 to 136.
An earlier run reported the source split as 15 to 113; that figure is superseded and must not be carried forward.
It came from a description parser that silently emptied 24 of the 128 descriptions it read, and an empty description falls to the subjective side of the keyword heuristic by default.
Both current runs report zero empty descriptions.
The split remains a heuristic floor either way, not a verdict on any individual skill.

Top seams by lexical Jaccard over description tokens, identical across both subjects at the head of the ranking: `preferences-python-development`:`preferences-typescript-nodejs-development` at 0.44 intra-plugin, `meta-load-cc-docs`:`meta-load-prompting-docs` at 0.40 intra-plugin, `jj-history-cleanup`:`preferences-git-history-cleanup` at 0.39 cross-plugin.
The deployed run adds `grill-me`:`grill-with-docs` at 0.42 among the external skills, which the source run cannot see.
The census is pure static analysis and is safe to run in CI.

## Cells (the model x harness grid)

claude-code + claude-opus-5 (`CLAUDE_FORCE_OAUTH=1` plus `CLAUDE_CODE_OAUTH_TOKEN`); codex + gpt-5.6-sol and codex + gpt-5.6-luna (`CODEX_FORCE_AUTH_JSON=1`, shared ChatGPT quota, serialize them); pi + gpt-5.6-luna (`OPENAI_API_KEY`).

The pi cell is the only one with no subscription path.
Pi's OAuth escape hatch is gated on the model's provider being anthropic, so an OpenAI model falls through to the providers table and bills `OPENAI_API_KEY` per call.
Every figure quoted for that cell is metered spend.

All budget figures across all cells are costed at metered API rates regardless.
Subscription-authenticated cells are for interactive exploration and are never used for a run batch whose numbers are reported.
See the budget section of `references/lattice-design.md` for the reasoning and for the requirement that a per-run cost come from a calibration batch before any budget table is presented.

## Stages

1. Static hardening (100 percent coverage, near-free): grow `census.py` into a linter — frontmatter validity, description quality per trigger methodology, env-coupling remediation list, progressive-disclosure structure. Keep it dependency-free so it can run inside a hermetic derivation. Fix before measuring. A `lint` skill mode does not exist yet.
2. Selection layer (100 percent coverage, description-only): everything-on triggering simulation over the deployed descriptions, adjudicating the competition pairs the census ranks. Embedding overlap beats lexical Jaccard here. A `selection-sim` skill mode does not exist yet.
3. Stratified dynamic eval: the decidable stratum becomes full packages across four cells; the subjective stratum is first refactored toward decidability with companion checkers, since conventions are lintable, and only the irreducible remainder is judge-graded, subject to the judge gate below. Plugin-level lattice over the 18 derived first-party units: marginals plus everything-on is 20 conditions. Second differences on census-ranked pairs only. Whether the 43 external deployed skills form a 19th unit or a fixed background present in every condition is undecided, and the two choices give different lattices and different everything-on conditions.
4. Refactor loop: merge near-duplicates (the jj cluster; git-versus-jj becomes one skill parameterized by VCS), split the 16-skill plugins, delete negative-marginal skills, description-optimize the survivors. Rerun only affected packages, paired against the prior version. The design goal is that E is approximately modular over the plugin partition — orthogonal trigger surfaces, near-zero interactions except designed synergies — because the compendium property and the cheap-validation property are the same property.
5. Institutionalize: packages become marketplace CI (extend apm-marketplace-validate; buildbot-nix runs the decidable stratum per PR; the full grid per model release; publish versioned benchmark results).

The screening cost for stage 3 has to be re-derived rather than carried forward.
The figure of roughly 500 to 700 runs was scoped to the pi cell, which is entirely metered, and its task count was never stated: 20 conditions at k=3 on one cell is 60 runs per task, so that figure implies 8 to 12 tasks.
Choose the task count deliberately, multiply by a measured per-run cost, and present the result.

## Judge gate

Reduce a contract to a mechanical check wherever a mechanical check exists.
Exactly one judge-validation package is a hard gate before any judge-based stratum enters a budget.

The gate is warranted by how little the surrounding ecosystem leans on judges.
All 87 tasks shipped in SkillsBench declare `verifier.type: test-script`; none uses a judge verifier.
The acceptance bar adopted here for a judge criterion is a human-labeled validation set of roughly 6 to 12 submissions spanning pass, fail, partial, borderline, plausible-but-wrong and polished-but-unsupported, plus demonstrated agreement with the human labels and stability across runs.

If the gate fails, the subjective stratum falls back to structural proxies.
A structural proxy asks whether the produced artifact exhibits the convention, checkable by grep or AST, rather than asking for a judgment of quality.

## Iteration-1 packages (reference only)

Three packages exist under `~/Downloads/harbor-skill/harborize-workspace/iteration-1/`: eval-1 process-compose-init, eval-2 jj-cluster (9-condition design, 108-run manifest), eval-3 cross-plugin nix x jj (full factorial n=2, 48 runs).
They are reference artifacts and are to be regenerated under the repaired instrument.
None met the oracle inhabitation invariant, so none is validated.
None carries the README the review gate routes its evidence through.
Two ship an `environment/mkfixture.sh`, which the fixture-generation rule forbids.
Eval-1's separate-mode verifier cannot run as configured, because separate mode never uploads `tests/` and the declared stock verifier image does not already own `/tests/test.sh`.
Cite them for shape, not for results.

## Open decisions

Whether the `lint` and `selection-sim` skill modes come before or after a companion-checker pattern drafted against one live preferences skill is open.
It was put to the user as a fork and never answered, so it is not an inherited sequence.

Whether the external deployed skills are an ablation unit or a fixed background is open, as noted under stage 3.

## First actions in a fresh session

1. Gate each regenerated package on the oracle passing its verifier 5 out of 5 in containers under both runners. `harbor tasks check` and `harbor task check` are removed and exit 1 unconditionally; `harbor check` is a different instrument, an LLM rubric review that spawns a full metered job and whose exit code ignores rubric failures, so it is not a drop-in substitute in cost or semantics. `bench tasks check` remains and validates the BenchFlow head.
2. Draft the companion-checker pattern against one live preferences skill (for example `preferences-python-development`) before committing to it across the subjective stratum.
3. Description optimization for harborize itself through skill-creator's run loop.
4. Use parallel subagents for test-case runs and blind comparison, per skill-creator's full workflow.
