# AI agent documentation generation
# Generates unified CLAUDE.md, AGENTS.md, GEMINI.md, CRUSH.md, OPENCODE.md
# from shared configuration with references to preference documents
{ ... }:
{
  flake.modules.homeManager.tools =
    { config, ... }:
    let
      # Base path for preference documents (without @ prefix)
      # The @ prefix must be added when referencing to enable auto-loading
      prefsPath = "${config.home.homeDirectory}/.claude/commands/preferences";
      commandsPath = "${config.home.homeDirectory}/.claude/commands";
    in
    {
      # https://github.com/mirkolenz/nixos/blob/0911e2e/home/options/agents-md.nix#L22-L31
      #
      # Auto-loading requires @ prefix on full paths in generated CLAUDE.md
      programs.agents-md = {
        enable = true;
        settings.body = ''
          # Development Guidelines

          If one of the following applies to a given task or topic, proactively read
          the corresponding document, without pausing to ask if you should, to ensure
          you are aware of our ideal guidelines and conventions:

          - style and conventions: @${prefsPath}/style-and-conventions.md
          - git version control: @${prefsPath}/git-version-control.md
          - git history cleanup: ${prefsPath}/git-history-cleanup.md
          - jj version control: ${commandsPath}/jj/jj-summary.md
          - jj workflow (full): ${commandsPath}/jj/jj-workflow.md
          - documentation: ${prefsPath}/documentation.md
          - change management: ${prefsPath}/change-management.md
          - issue tracking: ${commandsPath}/issues/beads.md
          - architectural patterns: ${prefsPath}/architectural-patterns.md
          - functional domain modeling (DDD, types, aggregates): ${prefsPath}/domain-modeling.md
          - event sourcing (event replay, state reconstruction, CQRS): ${prefsPath}/event-sourcing.md
          - event catalog tooling (EventCatalog, schema documentation): ${prefsPath}/event-catalog-tooling.md
          - qlerify to eventcatalog (transformation workflow): ${prefsPath}/event-catalog-qlerify.md
          - event modeling (Event Modeling, Qlerify, D2 diagrams): ${prefsPath}/event-modeling.md
          - discovery process: ${prefsPath}/discovery-process.md
          - collaborative modeling (EventStorming, Domain Storytelling): ${prefsPath}/collaborative-modeling.md
          - strategic domain analysis (Core/Supporting/Generic classification): ${prefsPath}/strategic-domain-analysis.md
          - bounded context design (context mapping, integration, ACL): ${prefsPath}/bounded-context-design.md
          - functional reactive programming (FRP foundations, arrows, presheaves): ${prefsPath}/functional-reactive-programming.md
          - theoretical foundations (category theory, type theory): ${prefsPath}/theoretical-foundations.md
          - algebraic laws (functor/monad laws, property-based testing): ${prefsPath}/algebraic-laws.md
          - smart constructors and validation patterns: see domain-modeling.md
          - error handling and workflow composition (Result types, railway-oriented): ${prefsPath}/railway-oriented-programming.md
          - data modeling (database schemas, normalization, ER diagrams): ${prefsPath}/data-modeling.md
          - json querying (duckdb, jaq): ${prefsPath}/json-querying.md
          - schema versioning: ${prefsPath}/schema-versioning.md
          - web application deployment: ${prefsPath}/web-application-deployment.md
          - cloudflare wrangler configuration: ${prefsPath}/cloudflare-wrangler-reference.md
          - secrets management: ${prefsPath}/secrets.md
          - nix development: ${prefsPath}/nix-development.md
          - python development: ${prefsPath}/python-development.md
          - rust development: ${prefsPath}/rust-development/00-index.md
          - haskell development: ${prefsPath}/haskell-development.md
          - typescript/node.js development: ${prefsPath}/typescript-nodejs-development.md
          - react/ui development: ${prefsPath}/react-tanstack-ui-development.md
          - hypermedia/server-driven UI development: ${prefsPath}/hypermedia-development/00-index.md

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

          Treat your context as a scarce coordination resource. Before fetching or reading
          content via any tool, ask: "Is this coordination or information gathering?"
          Dispatch information gathering to subagent Tasks; only execute inline if trivially
          small AND immediately required for coordination. Ultrathink to design workflow
          DAGs, write optimal prompts, dispatch, and coordinate — do not research, explore,
          or implement substantial changes inline.

          If you are a subagent Task (stated in your prompt), execute directly without
          nested dispatch. If you identify significant ambiguity or missing context,
          return with questions rather than forcing uncertain completion.

          When dispatching Tasks, include: "You are a subagent Task; execute without
          nested dispatch but return with clarifying questions if needed."
        '';
      };
    };
}
