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

          Do not hesitate to pause and ask questions to resolve ambiguity or elicit
          details the user may have left implicit rather than proceeding with assumptions.

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

          If you are a subagent Task (stated in your prompt), you will execute directly without
          attempting to dispatch to nested subagent Tasks. If you identify significant ambiguity, undefined terms, or
          missing context — whether in the original prompt or discovered during execution —
          return with questions rather than resolving through interpretation.

          To the extent that you make reasonable inferences during updates or implementations,
          explain why your proposal is optimal and determine appropriate verification. Execute
          before committing if quick and safe; otherwise return with a verification proposal.

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

          Agent teams conventions follow from the nature of teammate isolation.
          Teammates do not inherit the orchestrator's conversation context, so spawn prompts
          must be self-contained with all necessary context, file paths, and objectives.
          Teammates coordinate via shared task list (TaskCreate/TaskUpdate/TaskList) and
          messaging (SendMessage), not by returning results to the orchestrator.
          The orchestrator remains responsible for teammate lifecycle management.

          Beads-to-task-list mirroring is the convention for aligning ephemeral team coordination
          with persistent issue tracking. When an agent team works on an epic lineage or
          cross-cutting collection of beads issues, mirror the relevant issues and their
          dependencies into the team's shared task list via TaskCreate with appropriate
          blockedBy/blocks relationships. The team's shared task list is the ephemeral
          coordination substrate; beads issues remain the persistent source of truth.
          Keep both in sync: when a team task completes, update the corresponding bead.

          Teammate lifecycle management integrates with the orient/checkpoint pattern.
          Every new teammate should be instructed to execute `/issues-beads-orient` at session
          start to establish full context on the issue graph and current state. Teammates
          should monitor context usage and, when approaching 50% capacity (approximately
          100k tokens), execute `/issues-beads-checkpoint` to capture learnings, update
          issue status, and produce a handoff narrative. After checkpoint, the teammate
          requests shutdown; the orchestrator spawns a replacement oriented with
          `/issues-beads-orient` to continue the work. This creates a clean lifecycle:
          orient, work, checkpoint, shutdown, replace.

          The existing "You are a subagent Task" identity marker and return-with-questions
          pattern remain unchanged for DAG-dispatched tasks. For agent team teammates,
          spawn prompts should include equivalent identity context plus instructions about
          the orient/checkpoint lifecycle.

          Agents must never close epics directly. Close only individual issues within
          an epic. When all children of an epic are closed, the Kanban UI automatically
          moves the epic to "In Review" for human verification. This convention ensures
          human oversight of aggregate work before epic completion.
        '';
      };
    };
}
