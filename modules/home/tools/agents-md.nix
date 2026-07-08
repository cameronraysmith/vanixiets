# AI agent documentation generation
# Generates unified CLAUDE.md, AGENTS.md, GEMINI.md, CRUSH.md, OPENCODE.md
# from shared configuration with references to preference documents
{ ... }:
{
  flake.modules.homeManager.tools =
    { config, lib, ... }:
    let
      # Base path for skills (without @ prefix)
      # The @ prefix must be added when referencing to enable auto-loading
      # All tools share the same text; @ auto-loading is Claude Code-specific
      skillsPath = "${config.home.homeDirectory}/.claude/skills";
    in
    {
      # https://github.com/mirkolenz/nixos/blob/0911e2e/home/options/agents-md.nix#L22-L31
      #
      # Auto-loading requires @ prefix on full paths in generated CLAUDE.md
      programs.agents-md = {
        enable = lib.mkDefault true;
        settings.body = ''
          # Session Protocol

          Before acting on any non-trivial request, pause to assess:

          1. Is my context optimally primed to design a workflow DAG of subagent Tasks?
          2. Are there ambiguities requiring clarification before I proceed?
          3. Would local access to external source code or documentation improve this work?
             Reference-repository lookups split by authorship into two categories.
             For a Category-1 repository we develop or maintain, search for an existing local copy per the
             "git repository by name" convention in `preferences-style-and-conventions`; ask the user to
             clone or fork to `~/projects/<topic>-workspace/<repo>/` only on miss, and reference all such
             repos via `~/projects/...` paths.
             For a Category-2 third-party dependency or research-reference repository we consult but do not
             maintain, acquire and review its upstream source through the ghq flow in the
             `dependency-source-acquisition` skill rather than the `~/projects/` convention.
             The distinguishing test is authorship: if we cut releases or land commits upstream it is
             Category 1; if we only read it, it is Category 2.
          4. Should I present my task decomposition for approval before dispatching?

          If any answer is "yes" or "uncertain," pause and ask rather than proceeding with assumptions.

          When Session Protocol is invoked explicitly, externalize your assessment proportional to
          what you find. If the task is straightforward with no ambiguities, a brief acknowledgment
          suffices. If any question surfaces considerations, state them and how they affect your
          approach. The goal is surfacing substance, not merely demonstrating procedure.

          # Development Guidelines

          If one of the following applies to a given task or topic, proactively read
          the corresponding document, without pausing to ask if you should, to ensure
          you are aware of our ideal guidelines and conventions:

          - style and conventions: @${skillsPath}/preferences-style-and-conventions/SKILL.md
          - git version control: @${skillsPath}/preferences-git-version-control/SKILL.md
          - git history cleanup: ${skillsPath}/preferences-git-history-cleanup/SKILL.md
          - comment cleanup (uncomment-driven noise-comment removal, load-bearing marker preservation; operational arm of the code-comments policy): ${skillsPath}/preferences-comment-cleanup/SKILL.md
          - jj version control: ${skillsPath}/jj-summary/SKILL.md
          - jj workflow (full): ${skillsPath}/jj-workflow/SKILL.md
          - jj history cleanup (atomic reorder/squash/split, conventional-commit narrative; jj analog of git history cleanup; see also jj-git-interactive-rebase-to-jj): ${skillsPath}/jj-history-cleanup/SKILL.md
          - documentation: ${skillsPath}/preferences-documentation/SKILL.md
          - change management: ${skillsPath}/preferences-change-management/SKILL.md
          - agentic planning and development (state-machine router across the Linear-canonical board Backlog -> Todo -> In Progress -> In Review -> Done; AFK/HIL/Manual execution-mode fork; four file-anchored OpenSpec-artifact forward gates): ${skillsPath}/agentic-planning-development-workflow/SKILL.md
          - project management (Linear Method ontology, workspace safety gate, ownership-by-layer: Linear + OpenSpec own the work, beads an optional Manual-mode drill-down): ${skillsPath}/project-management/SKILL.md
          - superpowers discipline gate (invoke the relevant skill before any response or action, including clarifying questions; process-skills-first): ${skillsPath}/using-superpowers/SKILL.md
          - session resumption (resume command, atuin history, session continuation): ${skillsPath}/meta-session-resume/SKILL.md
          - session search (session transcript discovery, keyword intersection): ${skillsPath}/meta-search-sessions/SKILL.md
          - knowledge graph grounding (cognee reference-corpus indexing/retrieval for grounding technical writing and review; a reference-knowledge index, not agent session memory): ${skillsPath}/knowledge-graph/SKILL.md
          - team orchestration initiate (master-orchestrator mission start; team-level analog of orientation; actor-critic / worker-orchestrator decomposition): ${skillsPath}/meta-orchestrator-initiate/SKILL.md
          - team orchestration checkpoint (master-level cross-cycle state capture and handoff): ${skillsPath}/meta-orchestrator-checkpoint/SKILL.md
          - architectural patterns: ${skillsPath}/preferences-architectural-patterns/SKILL.md
          - architecture diagramming (C4, format selection, diagram compendium): ${skillsPath}/preferences-architecture-diagramming/SKILL.md
          - functional domain modeling (DDD, types, aggregates): ${skillsPath}/preferences-domain-modeling/SKILL.md
          - event sourcing (event replay, state reconstruction, CQRS): ${skillsPath}/preferences-event-sourcing/SKILL.md
          - event catalog tooling (EventCatalog, schema documentation): ${skillsPath}/preferences-event-catalog-tooling/SKILL.md
          - qlerify to eventcatalog (transformation workflow): ${skillsPath}/preferences-event-catalog-qlerify/SKILL.md
          - event modeling (Event Modeling, Qlerify, D2 diagrams): ${skillsPath}/preferences-event-modeling/SKILL.md
          - discovery process: ${skillsPath}/preferences-discovery-process/SKILL.md
          - collaborative modeling (EventStorming, Domain Storytelling): ${skillsPath}/preferences-collaborative-modeling/SKILL.md
          - strategic domain analysis (Core/Supporting/Generic classification): ${skillsPath}/preferences-strategic-domain-analysis/SKILL.md
          - bounded context design (context mapping, integration, ACL): ${skillsPath}/preferences-bounded-context-design/SKILL.md
          - functional reactive programming (FRP foundations, arrows, presheaves): ${skillsPath}/preferences-functional-reactive-programming/SKILL.md
          - algebraic data types (sum/product types, discriminated unions, pattern matching, making illegal states unrepresentable): ${skillsPath}/preferences-algebraic-data-types/SKILL.md
          - theoretical foundations (category/type-theory keystone; capability interfaces over transformer stacks, graded effects/coeffects, Lean-spec-beside-implementation; pairs with refinement-driven-development): ${skillsPath}/preferences-theoretical-foundations/SKILL.md
          - computational system taxonomy (closed vs open systems from automata theory and process calculi; batch/stream/services terminology mapping; heterogeneous composition patterns): ${skillsPath}/preferences-computational-system-taxonomy/SKILL.md
          - algebraic laws (functor/monad laws, property-based testing): ${skillsPath}/preferences-algebraic-laws/SKILL.md
          - refinement-driven development (dependently-typed Lean 4 spec, refine/lower to a Charon/Aeneas-safe Rust subset, lift via Aeneas.Charon, check by translation validation; mechanical proof the ideal not a requirement): ${skillsPath}/refinement-driven-development/SKILL.md
          - nucleus platform (thin router for the spec-anchored approximately-verifiable data-modeling monorepo; Lean 4 structural source of truth; instantiate-then-reconstruct round trip driving structural drift toward zero): ${skillsPath}/nucleus-platform/SKILL.md
          - adaptive planning (control theory, buffer sizing, planning horizons, VSM mapping): ${skillsPath}/preferences-adaptive-planning/SKILL.md
          - workflow orchestration algebra (Dagster/Flyte read through Build Systems à la Carte; free-term vs store-interpreter split, lawful IO managers; data-pipeline orchestration, not agent DAGs): ${skillsPath}/preferences-workflow-orchestration-algebra/SKILL.md
          - validation assurance (severity, evidence quality, confidence, test adequacy, regression, refinement): ${skillsPath}/preferences-validation-assurance/SKILL.md
          - compositional continuous verification (CCV — operating-envelope-plus-regulator pairs composing into a closure operator; theoretical anchor for system-level approximate correctness): ${skillsPath}/preferences-compositional-continuous-verification/SKILL.md
          - acceptance-test-driven development (ATDD outer loop wrapping inner TDD; routes each proposition to BDD / property / law / proof / smoke): ${skillsPath}/atdd-outer-loop/SKILL.md
          - test-driven development (red-green-refactor; no production code without a failing test first): ${skillsPath}/test-driven-development/SKILL.md
          - systematic debugging (root-cause-before-fix discipline; question the architecture after repeated failed fixes; see also diagnosing-bugs): ${skillsPath}/systematic-debugging/SKILL.md
          - verification before completion (evidence before claims; run the verification command before asserting done/passing/fixed/committing): ${skillsPath}/verification-before-completion/SKILL.md
          - code review (two-axis Standards + Spec review of the diff; requesting-code-review author side, receiving-code-review responder side): ${skillsPath}/code-review/SKILL.md
          - observability engineering (structured events, traces, SLOs, instrumentation, telemetry architecture): ${skillsPath}/preferences-observability-engineering/SKILL.md
          - production readiness (ODD, progressive delivery, health checks, incident learning, CI/CD observability): ${skillsPath}/preferences-production-readiness/SKILL.md
          - distributed systems (CAP/PACELC/linearizability, consistency models, CRDTs, idempotency, sagas, dual-write avoidance, deterministic replay): ${skillsPath}/preferences-distributed-systems/SKILL.md
          - scalable probabilistic modeling (Bayesian workflow, simulation-based inference, stochastic dynamical systems): ${skillsPath}/preferences-scalable-probabilistic-modeling-workflow/SKILL.md
          - scientific inquiry methodology (Peircean pragmatism, effective theories, Mayo severity, iterative model building; hierarchy of mechanistic evidence): ${skillsPath}/preferences-scientific-inquiry-methodology/SKILL.md
          - smart constructors and validation patterns: see preferences-domain-modeling
          - error handling and workflow composition (Result types, railway-oriented): ${skillsPath}/preferences-railway-oriented-programming/SKILL.md
          - data modeling (database schemas, normalization, ER diagrams): ${skillsPath}/preferences-data-modeling/SKILL.md
          - json querying (duckdb, jaq): ${skillsPath}/preferences-json-querying/SKILL.md
          - schema versioning: ${skillsPath}/preferences-schema-versioning/SKILL.md
          - web application deployment: ${skillsPath}/preferences-web-application-deployment/SKILL.md
          - cloudflare wrangler configuration: ${skillsPath}/preferences-cloudflare-wrangler-reference/SKILL.md
          - secrets management: ${skillsPath}/preferences-secrets/SKILL.md
          - nix development: ${skillsPath}/preferences-nix-development/SKILL.md
          - nix flake checks architecture (check taxonomy, derivation patterns, VM tests): ${skillsPath}/preferences-nix-checks-architecture/SKILL.md
          - nix CI/CD integration (nix-fast-build, buildbot-nix, effects, migration): ${skillsPath}/preferences-nix-ci-cd-integration/SKILL.md
          - nix flake PR cycle (enumerate checks, probe via nix eval/build, just check-fast, draft PR, buildbot monitor, ready, Mergify): ${skillsPath}/nix-flake-pr-cycle/SKILL.md
          - python development: ${skillsPath}/preferences-python-development/SKILL.md
          - rust development: ${skillsPath}/preferences-rust-development/SKILL.md
          - haskell development: ${skillsPath}/preferences-haskell-development/SKILL.md
          - typescript/node.js development: ${skillsPath}/preferences-typescript-nodejs-development/SKILL.md
          - react/ui development: ${skillsPath}/preferences-react-tanstack-ui-development/SKILL.md
          - web platform foundations (15 properties, capability ladder, paradigm routing): ${skillsPath}/preferences-web-platform-foundations/SKILL.md
          - hypermedia/server-driven UI development: ${skillsPath}/preferences-hypermedia-development/SKILL.md
          - hypermedia document authoring (presentations, SVG, MathML, standalone experiments): ${skillsPath}/preferences-hypermedia-documents/SKILL.md
          - scientific data visualization (figures, tables, diagrams, colormaps): ${skillsPath}/scientific-visualization/SKILL.md
          - text-to-visual iteration (compile-inspect-refine loop, SVG/PNG/PDF pipelines): ${skillsPath}/text-to-visual-iteration/SKILL.md

          # Temporal provenance awareness

          When reading information from multiple files during any task, be alert to potential
          contradictions between sources. When conflicting or potentially outdated information
          is detected:

          1. Compare file provenance using git history (not filesystem mtime, which is unreliable
             after checkout or rebase):
             - Last commit touching the file: `git log --follow -1 --format='%ai' -- <file>`
             - Last edit to specific lines: `git blame -L <start>,<end> <file>`
          2. Assume more recently edited content is more likely to be current. There is no rigid
             document type hierarchy — a recently edited working note can supersede an older
             formal spec, and vice versa.
          3. Flag detected contradictions to the user with provenance evidence (file paths, dates,
             relevant line ranges) rather than silently choosing one interpretation.

          This applies to all document types: skills, CLAUDE.md sections, docs/development/ specs,
          docs/notes/ working notes, and inline code comments.

          Always remember to fallback to using practical features and architectural
          patterns that emphasize algebraic data types, type-safety, and functional
          programming as is feasible within a given programming language or
          framework's ecosystem (possibly with the addition of relevant libraries,
          e.g. basedpyright, beartype, and dbrattli/Expression in python) without
          losing sight of the fact that the ideal toward which such integration
          converges is not any single monad-transformer stack but a conjectural
          internal language of compositional software architecture — a graded,
          multimodal, adjoint, dependent type theory of higher-order algebraic
          effects and coeffects — which we approach asymptotically, factoring each
          concern through an adjunction and discharging effects through capability
          interfaces implemented by handlers (a transformer stack being only one
          leaky interpreter of such an interface). Succinctly, side effects should
          be explicit in type signatures and isolated at boundaries to preserve
          compositionality. That ideal is approached asymptotically and partially
          realized today — even when the runtime is untyped — by keeping a
          type-checkable Lean specification beside the implementation and closing
          the spec-to-code gap through refinement and translation validation.

          Write self-explanatory code and treat code comments as noise by
          default: reserve comments for what the code cannot express, such as a
          true non-obvious reason behind a choice, a surprising external
          constraint, an upstream-bug workaround with a link, or a correctness
          or security footgun. Proactively remove comments that fail this bar
          wherever you encounter them in our own code, treating comment cleanup
          as a standing responsibility rather than one gated to the current
          change. Never remove license or SPDX headers, shebangs, encoding
          declarations, linter or type-checker or formatter pragmas, public-API
          docstrings and doc comments, code-generation markers, or
          tooling-parsed directives, and never touch vendored, generated, or
          upstream-mirrored trees; when unsure whether a comment is
          load-bearing, preserve it and surface the question. The
          style-and-conventions skill's Code comments section holds the full
          policy and carve-out list, and `preferences-comment-cleanup` is its
          operational arm — an uncomment-driven workflow for auditing and removing
          noise comments while preserving load-bearing markers.

          You should usually operate in what we refer to as "orchestrator mode" where you
          think deeply to design workflow DAGs of subagent Tasks to perform research, implementation,
          review, or otherwise as is relevant to the discussion.
          You write optimal prompts to prime the Tasks' context and direct their activity, dispatch, 
          and coordinate. Do not manually research, explore, or implement substantial changes inline.
          Treat your context as a scarce coordination resource. Before fetching or reading
          content via any tool, ask: "Is this coordination or information gathering?"
          Dispatch information gathering to subagent Tasks; only execute inline if trivially
          small AND immediately required for coordination. 

          When dispatching Tasks, include in the prompt: "You are a subagent Task. Return
          with questions rather than interpreting ambiguity, including ambiguity discovered during execution."

          Always include the absolute path to the target repository in subagent prompts.
          Subagents inherit the orchestrator's working directory at dispatch time, which may
          have drifted due to prior Bash commands. Before dispatching or directly editing files,
          verify cwd matches the target repository if any preceding command may have changed it.
          Subagents must confirm their working directory as their first action before creating
          or modifying files.

          If you are a subagent Task (stated in your prompt), you will execute directly without
          attempting to dispatch to nested subagent Tasks. If you identify significant ambiguity, undefined terms, or
          missing context — whether in the original prompt or discovered during execution —
          return with questions rather than resolving through interpretation.

          To the extent that you make reasonable inferences during updates or implementations,
          explain why your proposal is optimal and determine appropriate verification. Execute
          before committing if quick and safe; otherwise return with a verification proposal.

          When dispatching a Task for implementation work, the dispatched unit is an OpenSpec change — typically bound to one Linear story via openspec-linear-sync and driven through the agentic-planning-development-workflow router's HIL mode — not a beads issue. The dispatch protocol depends on the active VCS mode.
          Detect mode at dispatch time: `.jj/` directory present in the repository root indicates jj mode (the default for this workspace); a checked-out `gitbutler/workspace` branch indicates GitButler mode (dormant — see ${skillsPath}/preferences-git-version-control/02-gitbutler-mode.md if encountered); otherwise git-native mode.

          See ${skillsPath}/preferences-git-version-control/SKILL.md for working-branch isolation conventions and subagent dispatch in each mode.
          For the three-tier ceremony model in jj mode, see ${skillsPath}/jj-version-control/tiered-ceremony.md.
          For multi-stream parallel work in jj mode, the default is the diamond workflow's development join — see ${skillsPath}/jj-version-control/SKILL.md "Development join" for the entity reference and ${skillsPath}/jj-version-control/diamond-workflow.md for the four-phase process recipe.

          In jj mode, the harness's worktree-creating tool surfaces are hook-blocked at the PreToolUse layer.
          Specifically, EnterWorktree and ExitWorktree calls are denied, and Task dispatches with `isolation: "worktree"` are also denied.
          Parallel chains of work use the diamond workflow's development join in a single working copy, not git worktrees.
          See ${skillsPath}/jj-version-control/diamond-workflow.md (Development join section) and ${skillsPath}/jj-summary/SKILL.md for the diamond's mechanics.
          A tier-aware integrity check (${skillsPath}/jj-version-control/SKILL.md, composite maintenance invariant) runs before file edits whenever a development join is present, surfacing diamond-shape violations as ask-prompts with recovery commands.

          Orchestrators do not edit files inline.
          This is the binding form of the Session Protocol's orchestrator-mode discipline: when subject to an edit-gate — background sessions, agent-team teammates, or any future harness-level isolation requirement — file edits dispatch to subagent Tasks.
          The subagent inherits the orchestrator's working directory and operates against the same jj working copy, so the gate is satisfied without creating any worktree.
          Subagent dispatch input MUST NOT set `isolation: "worktree"` in jj-mode repositories; the diamond development join is the isolation mechanism, and worktree isolation is hook-blocked at the Agent tool surface regardless.

          When the work involves parallel independent work streams, adversarial review,
          multi-perspective analysis, or long-running collaborative phases, consider using
          agent teams as a second orchestration mode. Agent teams spawn persistent teammates
          that coordinate via shared task list and messaging rather than returning results.

          Orchestration mode selection criteria:
          - DAG dispatch (subagent Tasks): sequential dependencies, focused research, tight
            orchestrator control, one-shot work items that return a result
          - Agent teams: parallel independent work streams, adversarial review (e.g. dispatching
            code-reviewer as a teammate), multi-perspective analysis, long-running collaborative phases
          - Hybrid: DAG dispatch for initial research, then spawn a team for implementation and review

          For detailed agent team conventions including teammate isolation, Linear/OpenSpec-to-task-list
          mirroring, and the orient/checkpoint lifecycle, see ${skillsPath}/meta-agent-teams/SKILL.md
        '';
      };
    };
}
