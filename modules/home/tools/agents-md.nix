# AI agent documentation generation
# Generates ~/.claude/CLAUDE.md, ~/.codex/AGENTS.md, ~/.factory/AGENTS.md,
# ~/.gemini/GEMINI.md, ~/.hermes/SOUL.md, ~/.config/crush/CRUSH.md, and
# ~/.config/opencode/AGENTS.md (plus pi via programs.pi-coding-agent.context)
# from shared configuration with references to preference documents
{ ... }:
let
  content =
    { lib, ... }:
    let
      # Strip an *.instructions.md fragment's leading YAML frontmatter block
      # (delimited by a "---" line immediately at the start of the file and
      # the next "---" line) before concatenation, since apm's own compiler
      # elides frontmatter and this generator must reproduce that behavior
      # without depending on apm. Fails loudly, via `throw`, rather than
      # silently emitting frontmatter when a fragment lacks the expected
      # delimiters.
      stripFrontmatter =
        path:
        let
          content = builtins.readFile path;
          parts = lib.splitString "\n---\n" content;
        in
        if lib.length parts < 2 || !(lib.hasPrefix "---\n" (builtins.head parts)) then
          throw "agents-md: ${toString path} is missing the expected leading '---' YAML frontmatter block"
        else
          lib.removePrefix "\n" (lib.concatStringsSep "\n---\n" (lib.tail parts));

      instructionsOf = pkg: ../ai/plugins/${pkg}/.apm/instructions;

      # Explicit, reviewable order: tier (core, then vcs, then vcs-jj), then
      # filename within each tier. Directory globbing would make composition
      # order implicit and adding a fragment a silent accident rather than a
      # deliberate, reviewable act.
      fragments =
        map (f: instructionsOf "agent-context-core" + "/${f}") [
          "010-context-composition.instructions.md"
          "020-session-protocol.instructions.md"
          "030-development-guidelines.instructions.md"
          "040-temporal-provenance-awareness.instructions.md"
          "050-operating-principles.instructions.md"
          "060-communication.instructions.md"
          "070-compositional-architecture-and-type-discipline.instructions.md"
          "080-code-comments.instructions.md"
          "090-scope-discipline.instructions.md"
          "100-orchestrator-mode.instructions.md"
          "110-long-running-commands.instructions.md"
          "120-subagent-dispatch-contract.instructions.md"
          "130-orchestrators-do-not-edit-files-inline.instructions.md"
          "140-agent-teams.instructions.md"
        ]
        ++ map (f: instructionsOf "agent-context-vcs" + "/${f}") [
          "010-dispatch-unit-and-version-control-mode.instructions.md"
          "020-commit-behavior-override.instructions.md"
          "030-stacked-landing-protocol.instructions.md"
        ]
        ++ map (f: instructionsOf "agent-context-vcs-jj" + "/${f}") [
          "010-dispatch-protocol-jj-mode.instructions.md"
          "020-making-changes-in-jj-managed-or-colocated-repos.instructions.md"
          "030-working-copy-hazards.instructions.md"
          "040-worktree-interop-and-external-frameworks.instructions.md"
        ];
    in
    {
      # Two harness hazards worth recording here rather than fixing: omp
      # resolves exactly one user-level context file by provider priority,
      # and ~/.omp/agent/AGENTS.md at priority 100 would outrank
      # ~/.claude/CLAUDE.md at priority 80, so adding an ~/.omp/agent/
      # destination would silently shadow this file rather than add a
      # fourth surface. Omp's containment de-duplication also drops the
      # user-level file entirely when a project file's full paragraph
      # sequence contains it, so a project-level context file must never
      # be a superset of this one.
      programs.agents-md = {
        enable = lib.mkDefault true;
        settings.body = lib.concatMapStringsSep "\n" stripFrontmatter fragments;
      };
    };
in
{
  flake.modules.homeManager.tools = content;
  flake.modules.homeManager.agent-context = content;
}
