# omp (oh-my-pi), a coding agent, as a member of the homeManager.ai aggregate.
#
# oh-my-pi is a fork of pi and does ship a home-manager module, exported from
# its own flake as homeManagerModules.omp. This file deliberately does not
# import it, which is the opposite of what hunk and worktrunk do with theirs.
#
# That module carries three options. Two of them, enable and package, are the
# declarations below, and the third is the reason to decline it: its `settings`
# writes ~/.omp/agent/config.yml as a read-only store symlink, while omp's
# settings singleton persists to that same file in the background
# (packages/coding-agent/src/config/settings.ts). Its own option description
# concedes the result -- changes made from inside omp "replace it but revert on
# the next home-manager switch". The activation below takes the other route
# this repository has twice chosen instead, merging rather than installing, so
# that setupVersion and anything else omp owns survives a switch.
#
# If upstream's module later grows options worth having, adopting it is
# deleting these declarations and adding one imports line; the cost of waiting
# is that migration, against an input carried from now until then.
#
# Two files are nix-owned, both at user scope, and omp writes both at runtime:
# config.yml from the /settings, /model, and /theme screens, and WATCHDOG.yml
# whole from the /advisor editor (src/modes/components/advisor-config.ts). The
# merge shape and its retract limitation are documented in merge-config.sh.
# WATCHDOG.yml is discovered at ${configDir}/WATCHDOG.yml and combined with any
# project-level roster rather than overridden by it (src/advisor/watchdog.ts
# collectConfigCandidates), so what is declared here is the fleet-wide baseline.
#
# Nothing else is written. omp resolves .omp, .claude, .codex, and .gemini as
# configuration bases at both user and project level and scans each for
# commands, agents, and skills (packages/coding-agent/src/config.ts), so the
# skills delivered to ~/.claude/skills reach it with nothing declared. It does
# not inherit ~/.pi/agent as a configuration root the way atomic does; only the
# LSP loader consults ~/.pi/agent/lsp.* (src/lsp/config.ts), so
# aiAgentSettings.piOnlyExtensions has no bearing on it.
#
# LSP servers are not declared here either. omp auto-detects them from its
# 54-entry registry (src/lsp/defaults.json) by requiring a root marker in the
# project and a resolvable binary, so the roster follows whatever PATH omp is
# launched with. Pinning it would mean an lsp.yml, which unlike config.yml omp
# only ever reads, so it would not need this merge.
{ ... }:
let
  content =
    {
      pkgs,
      lib,
      config,
      flake,
      ...
    }:
    let
      cfg = config.programs.omp;
      yamlFormat = pkgs.formats.yaml { };
      mergeConfig = pkgs.writeShellApplication {
        name = "omp-merge-config";
        runtimeInputs = [ pkgs.yq-go ];
        text = builtins.readFile ./merge-config.sh;
      };
    in
    {
      options.programs.omp = {
        enable = lib.mkEnableOption "omp, a coding agent forked from pi with an IDE, LSP, and DAP surface wired in";

        package = lib.mkOption {
          type = lib.types.package;
          default = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.omp;
          defaultText = lib.literalExpression "inputs.llm-agents.packages.\${pkgs.stdenv.hostPlatform.system}.omp";
          description = ''
            The omp package to install. Sourced from the llm-agents input rather
            than oh-my-pi's own flake, whose module defaults its package option to
            that flake's build: llm-agents is covered by the numtide cache this
            fleet already substitutes from (lib/caches.nix), so a version bump
            arrives as a substitution instead of a source build.
          '';
        };

        configDir = lib.mkOption {
          type = lib.types.str;
          default = "${config.home.homeDirectory}/.omp/agent";
          description = "Directory omp reads its configuration and runtime state from.";
        };

        settings = lib.mkOption {
          type = yamlFormat.type;
          default = { };
          description = ''
            Nix-owned subset of {file}`config.yml`. Each declared key wins on
            activation; every key omp writes and nix does not declare, setupVersion
            among them, survives untouched.
          '';
        };

        watchdog = lib.mkOption {
          type = yamlFormat.type;
          default = { };
          description = ''
            Nix-owned subset of {file}`WATCHDOG.yml`, the advisor roster the
            {command}`/advisor` editor reads and rewrites.

            `advisors` is a sequence, and sequences are replaced rather than merged,
            so this states the roster outright. Disable one entry with
            `enabled = false` rather than removing it: merge-config.sh cannot retract
            a key, and a dropped advisor would otherwise persist from the last
            activation that declared it.
          '';
        };
      };

      config = {
        programs.omp = {
          enable = lib.mkDefault true;

          settings = {
            # omp kept pi's key name and semantics for this one
            # (src/config/settings-schema.ts), so the fleet-wide default reaches a
            # third pi-lineage agent from the same expression.
            hideThinkingBlock = lib.mkDefault config.aiAgentSettings.hideThinkingBlock;
            symbolPreset = lib.mkDefault "nerd";
            # Named for omp's own theme registry rather than the catppuccin flavor
            # aiAgentSettings.theme carries, which pi and atomic resolve against a
            # vendored theme file; the two are not interchangeable strings.
            theme.dark = lib.mkDefault "dark-catppuccin";

            # 180000 rather than upstream's 30000: a clone's first export has to
            # realise the flake devshell, 7.4s here against a populated nix store
            # and minutes when the closure must be built, and overrunning the
            # budget runs the command without the devshell rather than failing.
            # direnv is pinned at its own default so a change to that default
            # shows up as a diff here.
            bash = {
              direnv = lib.mkDefault "auto";

              direnvLoadTimeoutMs = lib.mkDefault 180000;
            };
            # Roles are assigned by what consumes them (src/config/model-roles.ts
            # names the nine built-ins; the greps below locate each consumer),
            # which is how this stays comparable to the atomic and claude-code
            # splits without pretending the three agents share a role vocabulary.
            #
            # Fable 5.1 orchestrates and plans; Opus 5 does delegated work; the
            # OpenAI family reviews, so a review never shares a family with the
            # session that produced the work. Both Anthropic roles run at medium
            # for the same reason they do in atomic and claude-code.
            modelRoles = {
              # The session model.
              default = lib.mkDefault "anthropic/claude-fable-5-1:medium";
              # Plan mode (src/modes/interactive-mode.ts resolveRoleModelWithThinking).
              plan = lib.mkDefault "anthropic/claude-fable-5-1:medium";
              # The bundled `task` subagent carries model "@task"
              # (src/task/agents.ts), so this is the delegated-worker model.
              task = lib.mkDefault "anthropic/claude-opus-5:medium";
              # The `reviewer` agent carries model "@slow"
              # (src/prompts/agents/reviewer.md), and advisor reuses the slow
              # chain without inheriting the primary. Astra rather than Sol: the
              # two tie on DeepSWE pass@1, but Astra takes the fewest steps of
              # any catalog row and leads document reasoning, and atomic's
              # builtins already review on it.
              slow = lib.mkDefault "openai-codex/gpt-6-astra:xhigh";
              advisor = lib.mkDefault "openai-codex/gpt-6-astra:xhigh";
              # smol drives both `scout` and `sonic`, one exploratory and one
              # strictly mechanical, so it stays cheap; scout is raised on its
              # own through task.agentModelOverrides below.
              # smol = lib.mkDefault "openrouter/moonshotai/kimi-k3:high";
              smol = lib.mkDefault "zai/glm-5.3:high";
              vision = lib.mkDefault "openrouter/google/gemini-3.7-flash:high";
              commit = lib.mkDefault "openai-codex/gpt-5.6-luna:medium";
              # Titles, the unexpected-stop classifier, and mnemopi fact
              # extraction, which resolve ["tiny", "smol"] in that order.
              tiny = lib.mkDefault "openai-codex/gpt-5.6-luna:medium";
            };

            # The per-agent analog of atomic's subagents.agentOverrides. `scout`
            # is omp's read-only research agent, so it takes the same model as
            # atomic's codebase-* agents rather than sonic's mechanical tier.
            task.agentModelOverrides = {
              scout = lib.mkDefault "anthropic/claude-opus-5:medium";
            };

            # omp's priority.json fallback chains predate Astra and still head
            # the slow chain with Sol, so an Astra failure would fall through a
            # chain that never names it. State the next hop for the three roles
            # this file pins.
            retry.fallbackChains = {
              default = lib.mkDefault [ "anthropic/claude-opus-5" ];
              slow = lib.mkDefault [ "openai-codex/gpt-5.6-sol" ];
              advisor = lib.mkDefault [ "openai-codex/gpt-5.6-sol" ];
            };

            # Fable requests blocked by Anthropic's safety classifier retry on
            # Opus 4.8 server-side. Off upstream; worth having now that the
            # session model is a Fable.
            providers.anthropic.serverSideFallback = lib.mkDefault true;
            # Mnemopi is omp's local memory backend: a SQLite store the agent
            # opens in-process (src/mnemopi/state.ts hands the Mnemopi library a
            # dbPath and a bank), with no service, no token and no network hop
            # on either the retain or the recall path. Only backend and scoping
            # change behaviour; the rest restate the schema defaults omp carries
            # at 18.0.3 (the mnemopi.* block of src/config/settings-schema.ts),
            # declared so an upstream default change surfaces as a diff here
            # rather than as a silent shift in what the fleet retains.
            #
            # dbPath and bank are omitted rather than restated, because both
            # default to undefined and what matters is what they resolve to:
            # dbPath becomes ~/.omp/agent/memories/mnemopi/mnemopi.db
            # (src/mnemopi/config.ts), and under the scoping chosen below bank
            # resolves to the single shared bank `default`.
            memory.backend = lib.mkDefault "mnemopi";
            mnemopi = {
              # The one deviation from upstream, which defaults to per-project.
              #
              # Two facts rule per-project out. Its bank name embeds
              # Bun.hash(path.resolve(cwd)) (src/mnemopi/config.ts
              # projectBankSegment), so every disposable worktree of a
              # repository is a bank of its own whose memories die with the
              # checkout, and this fleet works out of pooled worktrees.
              # per-project-tagged does not rescue it: despite sharing a name
              # with the hindsight key this replaces it is not one bank with
              # project tags, it writes the per-project bank and reads the shared
              # one alongside it, and nothing writes that shared bank, so it
              # stays empty. `global` is the only mode that accumulates one
              # corpus across repositories, which is what the hindsight setup
              # bought by leaving bankId unset. Provenance survives the move:
              # retained rows carry metadata.cwd (src/mnemopi/state.ts), though
              # recall does not filter on it, so recall is fleet-wide and
              # noisier than a per-project bank would be.
              scoping = lib.mkDefault "global";

              # Recall injects before the first model turn; retain fires once
              # every fourth user turn, counted in src/mnemopi/state.ts against
              # retainEveryNTurns, and again when the session is disposed.
              autoRecall = lib.mkDefault true;
              autoRetain = lib.mkDefault true;
              retainEveryNTurns = lib.mkDefault 4;
              recallLimit = lib.mkDefault 8;
              recallContextTurns = lib.mkDefault 3;
              recallMaxQueryChars = lib.mkDefault 4000;
              injectionTokenLimit = lib.mkDefault 5000;
              debug = lib.mkDefault false;

              # Off upstream and left off. Polyphonic recall is a four-voice
              # fusion, enhanced recall a tiered result cache, proactive linking
              # an episodic-graph write on retain; none of the three calls a
              # model, so what they cost is latency and recall noise rather than
              # tokens. Declared false so enabling one is a deliberate diff.
              polyphonicRecall = lib.mkDefault false;
              enhancedRecall = lib.mkDefault false;
              proactiveLinking = lib.mkDefault false;

              # The model question, settled here rather than inherited.
              #
              # Fact extraction is the only mnemopi operation that reaches a
              # model at 18.0.3: consolidation is deterministic and says so
              # (beam/consolidate.ts returns llm_used: 0), and recall, linking
              # and entity extraction are index and regex work. `smol` mode
              # resolves the first role that has a model out of the ordered pair
              # ["tiny", "smol"] (src/mnemopi/backend.ts
              # resolveMnemopiProviderOptions), so on this host it lands on
              # tiny, gpt-5.6-luna above, and the backend keeps only the model
              # and drops the :medium thinking suffix. That is one small
              # completion per four user turns against the openai-codex
              # subscription, and it fails open: with no role resolved or no
              # credential, extraction degrades to a heuristic and the
              # transcript is retained regardless.
              llmMode = lib.mkDefault "smol";

              # Embedding is local ONNX inference rather than a provider call:
              # the `en` variant selects BAAI/bge-base-en-v1.5 run through
              # fastembed in a subprocess (src/mnemopi/embed-worker.ts), so
              # recall costs no tokens and needs no key. Neither the runtime nor
              # the weights are in omp's closure; first use bun-installs
              # fastembed and downloads the model into ~/.omp/cache, once per
              # host, and failure there degrades recall to FTS rather than
              # disabling memory. noEmbeddings makes that FTS-only outright.
              embeddingVariant = lib.mkDefault "en";
              noEmbeddings = lib.mkDefault false;
            };
          };

          watchdog = {
            instructions = lib.mkDefault "Shared review baseline for all advisors.";
            advisors = lib.mkDefault [
              {
                name = "Watchdog";
                model = "openai-codex/gpt-6-astra:xhigh";
                instructions = "Continuous duty: wrong-direction detection, missing constraints, hallucinated APIs, plan/todo drift. Prefer concern over nit.";
              }
              {
                name = "Fable";
                model = "anthropic/claude-fable-5-1:xhigh";
                instructions = "Deep-review duty: architectural soundness, subtle correctness, cross-module invariants. Invoked deliberately; be thorough.";
                enabled = false;
              }
            ];
          };
        };

        home.packages = lib.mkIf cfg.enable [ cfg.package ];

        home.activation.ompMergeConfig = lib.mkIf cfg.enable (
          let
            merge =
              declared: target: "$DRY_RUN_CMD ${lib.getExe mergeConfig} ${declared} ${cfg.configDir}/${target}";
          in
          lib.hm.dag.entryAfter [ "writeBoundary" ] (
            lib.concatStringsSep "\n" (
              lib.optional (cfg.settings != { }) (
                merge (yamlFormat.generate "omp-config.yml" cfg.settings) "config.yml"
              )
              ++ lib.optional (cfg.watchdog != { }) (
                merge (yamlFormat.generate "omp-watchdog.yml" cfg.watchdog) "WATCHDOG.yml"
              )
            )
          )
        );
      };
    };
in
{
  flake.modules.homeManager.ai = content;
  flake.modules.homeManager.omp = content;
}
