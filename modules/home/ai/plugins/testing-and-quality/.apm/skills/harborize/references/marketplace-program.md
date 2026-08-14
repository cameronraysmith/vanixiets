# Marketplace validation program (vanixiets) — state and plan

Context for any session picking this up fresh. The instrument (this skill) and
the program below were developed and test-run against the apm marketplace at
github.com/cameronraysmith/vanixiets (ghq canonical path). Consume plugins via
apm CLI (>=0.28.0; portable form
'cameronraysmith/vanixiets/modules/home/ai/plugins/<group>#main') and evaluate
DEPLOYED trees.

## Census (scripts/census.py, run against modules/home/ai/plugins)
18 plugins, 128 skills; 26 command-style (disable-model-invocation);
54 env-coupled (~/... references); ~15 decidable-contract vs ~113
subjective/preferences (keyword heuristic — floor, not verdict).
Top seams: git-history-cleanup:jj-history-cleanup 0.39 cross-plugin;
preferences-programming-languages internally hottest (0.35–0.44 pairs);
meta-load-cc-docs:meta-load-prompting-docs 0.40. Full records:
census.json (regenerate any time; pure static, CI-safe).

## Cells (the model x harness grid)
claude-code+claude-opus-5 (CLAUDE_FORCE_OAUTH=1 + CLAUDE_CODE_OAUTH_TOKEN);
codex+gpt-5.6-sol and codex+gpt-5.6-luna (CODEX_FORCE_AUTH_JSON=1, shared
ChatGPT quota — serialize); pi+gpt-5.6-luna (OPENAI_API_KEY, cheap screening
cell — debug and screen here first).

## Stages
1. Static hardening (100%, ~free): grow census.py into a linter — YAML-parse
   frontmatter, description quality per trigger methodology, env-coupling
   remediation list (54 skills), progressive-disclosure structure. Fix before
   measuring.
2. Selection layer (100%, description-only): everything-on triggering
   simulation over all 128 descriptions; adjudicate the 16 flagged
   competition pairs. Embedding overlap > lexical Jaccard here.
3. Stratified dynamic eval: decidable stratum -> full packages, 4 cells.
   Subjective stratum -> refactor-toward-decidability (companion checkers;
   conventions are lintable), judge-grade only the irreducible remainder,
   sampled, with agreement gates. Plugin-level lattice: 18 units, marginals +
   everything-on = 20 conditions, screen on pi-luna (~500-700 runs), promote
   finalists to full grid. Second differences: census-flagged pairs only.
4. Refactor loop: merge near-duplicates (jj cluster; git-vs-jj -> one skill
   parameterized by VCS), split 16-skill plugins (<=3-focused-modules
   finding), delete negative-marginal skills, description-optimize
   survivors. Rerun only affected packages, paired vs prior version.
   Design goal: E approximately modular over the plugin partition —
   orthogonal trigger surfaces, near-zero interactions except designed
   synergies. Compendium property == cheap-validation property.
5. Institutionalize: packages as marketplace CI (extend
   apm-marketplace-validate; buildbot-nix runs decidable stratum per PR;
   full grid per model release; publish versioned benchmark results).

## Completed (iteration 1-2)
Three validated packages under harborize-workspace/iteration-1 (also in
harborize-iteration-1.zip): eval-1 process-compose-init (oracle passed own
verifier 7/7 locally; audits clean), eval-2 jj-cluster (9-condition design,
108-run manifest, materializer bake-in guard verified), eval-3 cross-plugin
nix x jj (full factorial n=2, 48 runs). Fixes applied: invocation-mode
intake, plugin-aware materializer, fixture-generation and exact-set-verifier
guidance.

## First actions in a fresh (Claude Code) session
1. GATE: harbor tasks check + oracle 5x in containers for all three
   packages (Docker available there; was not in the drafting sandbox).
   Fix eval-2/eval-3 fixtures if oracle flakes (heredoc hazard noted).
2. Add skill modes: `lint` (stage 1) and `selection-sim` (stage 2).
3. Draft the companion-checker pattern against one live preferences skill
   (e.g., preferences-python-development) before committing across ~113.
4. Description optimization for harborize itself via skill-creator's
   run_loop (`claude -p` available in Claude Code; was not in drafting env).
5. Subagents now available: parallel test-case runs + blind comparison per
   skill-creator's full workflow.
