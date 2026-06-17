# Claude Code CLI configuration with MCP servers and ccstatusline
{ ... }:
{
  flake.modules = {
    homeManager.ai =
      {
        pkgs,
        config,
        lib,
        flake,
        ...
      }:
      {
        options.programs.claude-code.mutableSettings = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Use mutable copies instead of immutable nix store symlinks for settings.json files. Enables Claude Code to edit settings at runtime (e.g. /voice toggle) at the cost of nix-declared state being overwritten between activations.";
        };

        config = {
          programs.claude-code = {
            enable = true;
            mutableSettings = true;
            # package = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
            package = flake.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;

            # symlink agents directory tree (skills managed by skills/default.nix)
            agentsDir = ./agents;

            # https://schemastore.org/claude-code-settings.json
            settings = {
              # Enable ccstatusline (from llm-agents flake input)
              statusLine = {
                type = "command";
                command = "${
                  flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.ccstatusline
                }/bin/ccstatusline";
                padding = 0;
              };

              model = "opus";
              effortLevel = "high";
              ultracode = true;
              forceLoginMethod = "claudeai";
              theme = "dark";
              autoCompactEnabled = false;
              autoDreamEnabled = true;
              spinnerTipsEnabled = false;
              cleanupPeriodDays = 1100;
              includeCoAuthoredBy = false;
              enableAllProjectMcpServers = false;
              extraKnownMarketplaces = {
                # reserved Anthropic marketplace name: github source mandated; upstream has no tags so no pin anchor exists (CC marketplace refs are branch/tag only, not shas)
                claude-plugins-official = {
                  source = {
                    source = "github";
                    repo = "anthropics/claude-plugins-official";
                  };
                };
                cognee = {
                  source = {
                    source = "directory";
                    path = "${pkgs.agent-plugins-cognee}";
                  };
                };
                cloudflare = {
                  source = {
                    source = "directory";
                    path = "${pkgs.agent-plugins-cloudflare}";
                  };
                };
                dagster = {
                  source = {
                    source = "directory";
                    path = "${pkgs.agent-plugins-dagster-skills}";
                  };
                };
                duckdb-skills = {
                  source = {
                    source = "directory";
                    path = "${pkgs.agent-plugins-duckdb-skills}";
                  };
                };
                huggingface-skills = {
                  source = {
                    source = "directory";
                    path = "${pkgs.agent-plugins-huggingface-skills}";
                  };
                };
                # reserved Anthropic marketplace name: github source mandated; pinned to latest upstream tag (CC marketplace refs are branch/tag only, not shas)
                life-sciences = {
                  source = {
                    source = "github";
                    repo = "anthropics/life-sciences";
                    ref = "v1.1.1";
                  };
                };
                ouroboros = {
                  source = {
                    source = "directory";
                    path = "${pkgs.agent-plugins-ouroboros}";
                  };
                };
                superpowers-dev = {
                  source = {
                    source = "directory";
                    path = "${pkgs.agent-plugins-superpowers}";
                  };
                };
              };
              enabledPlugins = {
                # claude-plugins-official
                "agent-sdk-dev@claude-plugins-official" = false;
                "claude-md-management@claude-plugins-official" = true;
                "code-review@claude-plugins-official" = true;
                "code-simplifier@claude-plugins-official" = true;
                "explanatory-output-style@claude-plugins-official" = false;
                "feature-dev@claude-plugins-official" = false;
                "figma@claude-plugins-official" = false;
                "frontend-design@claude-plugins-official" = false;
                "hookify@claude-plugins-official" = true;
                "huggingface-skills@claude-plugins-official" = false; # monolithic bundle replaced by fine-grained huggingface-skills pins; remote MCP already registered via sops template mcp-huggingface
                "learning-output-style@claude-plugins-official" = false;
                # Linear plugin disabled in favor of the `linear-cli` binary + linear-* skills.
                # It bundles an MCP server exposed as mcp__plugin_linear_linear__* tools.
                # Re-enable the Linear MCP plugin by flipping false -> true.
                "linear@claude-plugins-official" = false;
                "playground@claude-plugins-official" = false;
                "plugin-dev@claude-plugins-official" = true;
                "posthog@claude-plugins-official" = false;
                "sentry@claude-plugins-official" = false;
                "skill-creator@claude-plugins-official" = true;
                "superpowers@claude-plugins-official" = false; # migrated to pinned superpowers-dev marketplace (obra/superpowers @ v5.1.0)
                # cognee
                "cognee-memory@cognee" = true;
                # cloudflare
                "cloudflare@cloudflare" = true;
                # dagster
                "dagster-expert@dagster" = true;
                "dignified-python@dagster" = false;
                # duckdb-skills
                "duckdb-skills@duckdb-skills" = true;
                # huggingface-skills
                "hf-cli@huggingface-skills" = true;
                "huggingface-datasets@huggingface-skills" = true;
                # life-sciences
                "10x-genomics@life-sciences" = false;
                "biorender@life-sciences" = false;
                "biorxiv@life-sciences" = false;
                "chembl@life-sciences" = false;
                "clinical-trial-protocol@life-sciences" = false;
                "clinical-trials@life-sciences" = false;
                # ouroboros
                "ouroboros@ouroboros" = true;
                # superpowers-dev
                "superpowers@superpowers-dev" = true;
              };
              voiceEnabled = true;
              remoteControlAtStartup = true;
              alwaysThinkingEnabled = true;

              env = {
                ANTHROPIC_DEFAULT_HAIKU_MODEL = "claude-sonnet-4-6";
                ANTHROPIC_DEFAULT_OPUS_MODEL = "claude-opus-4-8";
                ANTHROPIC_DEFAULT_SONNET_MODEL = "claude-opus-4-8";
                ASTRO_TELEMETRY_DISABLED = "1";
                CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR = "0";
                CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY = "1";
                CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
                CLAUDE_CODE_SUBAGENT_MODEL = "claude-opus-4-8";
                DISABLE_BUG_COMMAND = "1";
                # Disabled: also suppresses feature-flag evaluation (upstream bug).
                # https://github.com/anthropics/claude-code/issues/33119#issuecomment-4052694908
                # DISABLE_ERROR_REPORTING = "1";
                # DISABLE_TELEMETRY = "1";
                MAX_MCP_OUTPUT_TOKENS = "40000";
                TMPDIR = "/tmp/claude";
                TMPPREFIX = "/tmp/claude/zsh";
                UV_NO_SYNC = "1";
              };
              teammateMode = "tmux";

              sandbox = {
                enabled = false;
                autoAllowBashIfSandboxed = true;
                allowUnsandboxedCommands = false;
                excludedCommands = [
                  "atuin:*"
                  "bd:*"
                  "gh:*"
                  "git:*"
                  "nix:*"
                  "pbcopy:*"
                  "pbpaste:*"
                  "prek:*"
                ];
                network = {
                  allowedDomains = [
                    "hydra.nixos.org"
                    "github.com"
                    "*.githubusercontent.com"
                    "api.github.com"
                  ];
                  # does not work as of 2026-02-08 (ref mirkolenz-nixos)
                  allowUnixSockets = [
                    "/nix/var/nix/daemon-socket/socket"
                    "${config.home.homeDirectory}/Library/Containers/com.bitwarden.desktop/Data/.bitwarden-ssh-agent.sock"
                  ];
                  allowLocalBinding = true;
                };
              };

              # Suppress the "Enable auto mode?" confirmation dialog on session start.
              # Set by the CLI when the user clicks "Yes, and make it my default mode";
              # declaring it here keeps activation idempotent across home-manager rebuilds.
              skipAutoPermissionPrompt = true;

              # Disable the bg-session worktree-isolation guard fleet-wide.
              # Claude Code reads worktree.bgIsolation from the merged settings hierarchy
              # (user < project < local < managed), so the user-global ~/.claude/settings.json
              # value applies across all repos; a per-repo .claude/settings.json may re-enable
              # it with worktree.bgIsolation = "worktree".
              worktree.bgIsolation = "none";

              # Branch isolation worktrees from the current local HEAD rather than
              # from origin/<default-branch>. In jj-managed repos the WorktreeCreate
              # hook (jj-worktree-create) intercepts creation regardless, so this
              # governs only the pure-git fallback path.
              worktree.baseRef = "head";

              permissions = {
                defaultMode = "auto";
                # only enforced from managed-settings.json, included here as intent marker
                # disableBypassPermissionsMode = "disable";
                additionalDirectories = [ "~/projects" ];
                allow = [
                  # Blanket Bash allow; dangerous commands gated via deny/ask lists.
                  # Replaces per-command opt-in which couldn't handle shell constructs
                  # like env var prefixes, command substitution, or pipes.
                  "Bash"
                  # --- Legacy per-command Bash patterns (retained for reference) ---
                  # # Basics
                  # "Bash(cat:*)"
                  # "Bash(echo:*)"
                  # "Bash(fd:*)"
                  # "Bash(find:*)"
                  # "Bash(grep:*)"
                  # "Bash(head:*)"
                  # "Bash(ls:*)"
                  # "Bash(mkdir:*)"
                  # "Bash(pwd)"
                  # "Bash(rg:*)"
                  # "Bash(tail:*)"
                  # "Bash(pgrep:*)"
                  # "Bash(ps:*)"
                  # "Bash(sed:*)"
                  # "Bash(sort:*)"
                  # "Bash(tree:*)"
                  # "Bash(wc:*)"
                  # "Bash(which:*)"
                  # # Git operations
                  # "Bash(git:*)"
                  # "Bash(git add:*)"
                  # "Bash(git branch:*)"
                  # "Bash(git checkout:*)"
                  # "Bash(git commit:*)"
                  # "Bash(git config:*)"
                  # "Bash(git diff:*)"
                  # "Bash(git log:*)"
                  # "Bash(git ls-files:*)"
                  # "Bash(git ls-remote:*)"
                  # "Bash(git merge:*)"
                  # "Bash(git rebase:*)"
                  # "Bash(git remote:*)"
                  # "Bash(git rev-parse:*)"
                  # "Bash(git show:*)"
                  # "Bash(git stash:*)"
                  # "Bash(git status:*)"
                  # "Bash(git subtree:*)"
                  # "Bash(git tag:*)"
                  # "Bash(git worktree:*)"
                  # # GitHub CLI
                  # "Bash(gh:*)"
                  # # Nix operations
                  # "Bash(nix build:*)"
                  # "Bash(nix develop:*)"
                  # "Bash(nix flake:*)"
                  # # Development tools
                  # "Bash(jq:*)"
                  # "Bash(latexmk:*)"
                  # "Bash(nvidia-smi:*)"
                  # "Bash(test:*)"
                  # "Bash(typst:*)"
                  # # Shell utilities
                  # "Bash(atuin:*)"
                  # "Bash(pbcopy:*)"
                  # "Bash(pbpaste:*)"
                  # Web tools
                  "WebFetch"
                  "WebSearch"
                  # Allow all reads and searches; deny rules still block .env and sops age keys
                  "Read"
                  "Grep"
                  "Glob"
                  # MCP tools are governed by defaultMode = "auto" (classifier-
                  # gated). A blanket `mcp__*` allow is no longer valid: allow
                  # rules permit a glob only in the tool position after a
                  # literal mcp__<server>__ prefix (deny/ask allow it anywhere).
                ];
                deny = [
                  # rm is handled by redirect-rm-to-rip PreToolUse hook
                  "Bash(rm *)"
                  # Secrets
                  "Read(.env*)"
                  "Read(~/.config/sops/age/**)"
                ];
                # --- Static ask list (superseded by PreToolUse hooks) ---
                # Blanket "Bash" in allow overrides static ask patterns due to
                # evaluation order (deny -> allow -> ask in practice, despite docs
                # stating deny -> ask -> allow). Hooks run before the permission
                # system and are not affected by this ordering issue.
                # Enforcement is in: gate-dangerous-commands, gate-mutating-http
                # Retained as documentation of gated command categories.
                ask = [
                  # # Privilege escalation
                  # "Bash(sudo *)"
                  # # Git: push and destructive operations
                  # "Bash(git push *)"
                  # "Bash(git reset --hard*)"
                  # "Bash(git clean *)"
                  # "Bash(git checkout .)"
                  # "Bash(git checkout -- .)"
                  # "Bash(git restore .)"
                  # "Bash(git restore --staged .)"
                  # "Bash(git branch -D *)"
                  # "Bash(git stash drop*)"
                  # "Bash(git stash clear*)"
                  # # GitHub CLI: mutating operations
                  # "Bash(gh api *)"
                  # "Bash(gh pr create *)"
                  # "Bash(gh pr comment *)"
                  # "Bash(gh pr merge *)"
                  # "Bash(gh pr close *)"
                  # "Bash(gh pr edit *)"
                  # "Bash(gh pr review *)"
                  # "Bash(gh issue create *)"
                  # "Bash(gh issue comment *)"
                  # "Bash(gh issue close *)"
                  # "Bash(gh issue edit *)"
                  # "Bash(gh repo create *)"
                  # "Bash(gh repo delete *)"
                  # "Bash(gh repo rename *)"
                  # "Bash(gh release create *)"
                  # "Bash(gh release delete *)"
                  # "Bash(gh workflow run *)"
                  # "Bash(gh gist create *)"
                  # # Nix: arbitrary code execution
                  # "Bash(nix run *)"
                  # "Bash(nix shell *)"
                  # # Infrastructure mutation
                  # "Bash(tofu apply*)"
                  # "Bash(tofu destroy*)"
                  # "Bash(terraform apply*)"
                  # "Bash(terraform destroy*)"
                  # "Bash(kubectl apply *)"
                  # "Bash(kubectl create *)"
                  # "Bash(kubectl delete *)"
                  # "Bash(kubectl exec *)"
                  # "Bash(helm install *)"
                  # "Bash(helm upgrade *)"
                  # "Bash(helm uninstall *)"
                  # # Remote access
                  # "Bash(ssh *)"
                  # "Bash(scp *)"
                  # "Bash(rsync *)"
                  # # Container publishing
                  # "Bash(docker push *)"
                  # "Bash(podman push *)"
                  # # Process management
                  # "Bash(kill *)"
                  # "Bash(killall *)"
                  # "Bash(pkill *)"
                  # # HTTP: mutating requests (gate-mutating-http hook handles)
                  # "Bash(curl *)"
                  # "Bash(wget *)"
                  # # Destructive find/xargs patterns
                  # "Bash(find *-delete*)"
                  # "Bash(find *-exec*rm *)"
                  # "Bash(xargs rm*)"
                  # "Bash(xargs *rm*)"
                  # # Raw writes and secure deletion
                  # "Bash(dd *)"
                  # "Bash(truncate *)"
                  # "Bash(shred *)"
                ];
              };
            };
          };

          # Mutable settings: copy instead of symlink so Claude Code can write at runtime.
          # Each home-manager activation overwrites with declared state.
          #
          # Override the upstream programs.claude-code module's home.file declaration.
          # Upstream uses the absolute path key `${cfg.configDir}/settings.json` (where
          # cfg.configDir defaults to `/home/cameron/.claude` for this user), NOT the
          # relative `.claude/settings.json`. Targeting the relative path was a no-op
          # bug that let home-manager continue managing the file as a symlink while
          # our activation script also tried to install it, producing
          # checkLinkTargets backup-conflict errors at deploy time.
          #
          # With enable=mkForce false on the correct absolute-path key, the upstream
          # symlink isn't built into home-files; checkLinkTargets doesn't iterate
          # over settings.json; the activation script below becomes the sole source
          # of truth, supporting runtime mutation by claude-code itself.
          home.file."${config.programs.claude-code.configDir}/settings.json".enable =
            lib.mkIf config.programs.claude-code.mutableSettings (lib.mkForce false);

          home.activation.claudeCodeMutableSettings = lib.mkIf config.programs.claude-code.mutableSettings (
            let
              jsonFormat = pkgs.formats.json { };
              settingsFile = jsonFormat.generate "claude-code-settings.json" (
                config.programs.claude-code.settings
                // {
                  "$schema" = "https://json.schemastore.org/claude-code-settings.json";
                }
              );
            in
            lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              $DRY_RUN_CMD install -Dm644 ${settingsFile} $HOME/.claude/settings.json
            ''
          );

          home.shellAliases = {
            ccds = "claude --permission-mode auto";
            ccglm = "claude-glm";
            cccb = "claude-cerebras";
          };

          # symlink .local/bin to satisfy claude doctor
          home.file.".local/bin/claude".source =
            config.lib.file.mkOutOfStoreSymlink "${config.programs.claude-code.finalPackage}/bin/claude";
        };
      };
  };
}
