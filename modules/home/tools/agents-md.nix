# AI agent documentation generation
# Generates unified CLAUDE.md, AGENTS.md, GEMINI.md, CRUSH.md, OPENCODE.md
# from shared configuration with references to preference documents
{ ... }:
{
  flake.modules.homeManager.tools =
    { config, ... }:
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
        enable = true;
        settings.body = ''
          # Session Protocol

          Before acting on any non-trivial request, pause to assess:

          1. Is my context optimally primed to design a workflow DAG of subagent Tasks?
          2. Are there ambiguities requiring clarification before I proceed?
          3. Would local access to external source code or documentation improve this work?
             If so, ask the user to fork and clone relevant repositories to `~/projects/`
             before proceeding, and reference all repos via `~/projects/...` paths.
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
          - jj version control: ${skillsPath}/jj-summary/SKILL.md
          - jj workflow (full): ${skillsPath}/jj-workflow/SKILL.md
          - documentation: ${skillsPath}/preferences-documentation/SKILL.md
          - change management: ${skillsPath}/preferences-change-management/SKILL.md
          - issue tracking: ${skillsPath}/issues-beads/SKILL.md
          - session routing (graph diagnostics, skill selection): ${skillsPath}/session-advisor/SKILL.md
          - session orientation (context priming, signal tables): ${skillsPath}/session-orient/SKILL.md
          - session planning (task decomposition, workflow DAGs): ${skillsPath}/session-plan/SKILL.md
          - session review (progress assessment, gap analysis): ${skillsPath}/session-review/SKILL.md
          - session checkpointing (state capture, resumption): ${skillsPath}/session-checkpoint/SKILL.md
          - architectural patterns: ${skillsPath}/preferences-architectural-patterns/SKILL.md
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
          - theoretical foundations (category theory, type theory): ${skillsPath}/preferences-theoretical-foundations/SKILL.md
          - algebraic laws (functor/monad laws, property-based testing): ${skillsPath}/preferences-algebraic-laws/SKILL.md
          - adaptive planning (control theory, buffer sizing, planning horizons, VSM mapping): ${skillsPath}/preferences-adaptive-planning/SKILL.md
          - scalable probabilistic modeling (Bayesian workflow, simulation-based inference, stochastic dynamical systems): ${skillsPath}/preferences-scalable-probabilistic-modeling-workflow/SKILL.md
          - smart constructors and validation patterns: see preferences-domain-modeling
          - error handling and workflow composition (Result types, railway-oriented): ${skillsPath}/preferences-railway-oriented-programming/SKILL.md
          - data modeling (database schemas, normalization, ER diagrams): ${skillsPath}/preferences-data-modeling/SKILL.md
          - json querying (duckdb, jaq): ${skillsPath}/preferences-json-querying/SKILL.md
          - schema versioning: ${skillsPath}/preferences-schema-versioning/SKILL.md
          - web application deployment: ${skillsPath}/preferences-web-application-deployment/SKILL.md
          - cloudflare wrangler configuration: ${skillsPath}/preferences-cloudflare-wrangler-reference/SKILL.md
          - secrets management: ${skillsPath}/preferences-secrets/SKILL.md
          - nix development: ${skillsPath}/preferences-nix-development/SKILL.md
          - python development: ${skillsPath}/preferences-python-development/SKILL.md
          - rust development: ${skillsPath}/preferences-rust-development/SKILL.md
          - haskell development: ${skillsPath}/preferences-haskell-development/SKILL.md
          - typescript/node.js development: ${skillsPath}/preferences-typescript-nodejs-development/SKILL.md
          - react/ui development: ${skillsPath}/preferences-react-tanstack-ui-development/SKILL.md
          - hypermedia/server-driven UI development: ${skillsPath}/preferences-hypermedia-development/SKILL.md
          - scientific data visualization (figures, tables, diagrams, colormaps): ${skillsPath}/scientific-visualization/SKILL.md
          - text-to-visual iteration (compile-inspect-refine loop, SVG/PNG/PDF pipelines): ${skillsPath}/text-to-visual-iteration/SKILL.md

          Always remember to fallback to using practical features and architectural
          patterns that emphasize algebraic data types, type-safety, and functional
          programming as is feasible within a given programming language or
          framework's ecosystem (possibly with the addition of relevant libraries,
          e.g. basedpyright, beartype, and dbrattli/Expression in python) without
          losing sight of the fact that, in the ideal case, the integration of all
          of our codebases, regardless of language or framework, would correspond to
          an indexed monad transformer stack in the category of effects. Succinctly,
          side effects should be explicit in type signatures and isolated at
          boundaries to preserve compositionality.

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

          When dispatching a Task with a BEAD_ID for implementation work, include the target worktree path in the prompt.
          Issue-level work goes in `.worktrees/{issue-ID}-descriptor`, branching from the parent epic's branch.
          Secondary (non-focus) epics use `.worktrees/{epic-ID}-descriptor`; the focus epic is checked out in the repo root.
          The subagent creates the worktree as its first action; the orchestrator specifies the path and the start-point branch.
          Example prompt fragment: "Work in .worktrees/nix-pxj-4-deploy-validate (create via git worktree add, branching from nix-pxj-ntfy-server)."

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

          For detailed agent team conventions including teammate isolation, beads-to-task-list
          mirroring, and the orient/checkpoint lifecycle, see ${skillsPath}/meta-agent-teams/SKILL.md
        '';
      };
    };
}
