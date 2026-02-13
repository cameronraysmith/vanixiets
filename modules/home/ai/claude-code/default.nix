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
        programs.claude-code = {
          enable = true;
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
            forceLoginMethod = "claudeai";
            theme = "dark";
            autoCompactEnabled = false;
            spinnerTipsEnabled = false;
            cleanupPeriodDays = 1100;
            includeCoAuthoredBy = false;
            enableAllProjectMcpServers = false;
            enabledPlugins = {
              "feature-dev@claude-plugins-official" = true;
              "frontend-design@claude-plugins-official" = true;
            };
            alwaysThinkingEnabled = true;

            env = {
              ANTHROPIC_DEFAULT_HAIKU_MODEL = "claude-sonnet-4-5-20250929";
              ANTHROPIC_DEFAULT_OPUS_MODEL = "claude-opus-4-6";
              ANTHROPIC_DEFAULT_SONNET_MODEL = "claude-opus-4-6";
              ASTRO_TELEMETRY_DISABLED = "1";
              CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR = "1";
              CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY = "1";
              CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
              CLAUDE_CODE_SUBAGENT_MODEL = "claude-opus-4-6";
              DISABLE_BUG_COMMAND = "1";
              DISABLE_ERROR_REPORTING = "1";
              DISABLE_TELEMETRY = "1";
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

            permissions = {
              defaultMode = "acceptEdits";
              # only enforced from managed-settings.json, included here as intent marker
              disableBypassPermissionsMode = "disable";
              additionalDirectories = [ "~/projects" ];
              allow = [
                # Basics
                "Bash(cat:*)"
                "Bash(echo:*)"
                "Bash(fd:*)"
                "Bash(find:*)"
                "Bash(grep:*)"
                "Bash(head:*)"
                "Bash(ls:*)"
                "Bash(mkdir:*)"
                "Bash(pwd)"
                "Bash(rg:*)"
                "Bash(tail:*)"
                "Bash(pgrep:*)"
                "Bash(ps:*)"
                "Bash(sed:*)"
                "Bash(sort:*)"
                "Bash(tree:*)"
                "Bash(wc:*)"
                "Bash(which:*)"
                # Git operations
                # "Bash(git:*)"
                "Bash(git add:*)"
                "Bash(git branch:*)"
                "Bash(git checkout:*)"
                "Bash(git commit:*)"
                "Bash(git config:*)"
                "Bash(git diff:*)"
                "Bash(git log:*)"
                "Bash(git ls-files:*)"
                "Bash(git ls-remote:*)"
                "Bash(git merge:*)"
                "Bash(git rebase:*)"
                "Bash(git remote:*)"
                "Bash(git rev-parse:*)"
                "Bash(git show:*)"
                "Bash(git stash:*)"
                "Bash(git status:*)"
                "Bash(git subtree:*)"
                "Bash(git tag:*)"
                "Bash(git worktree:*)"
                # GitHub CLI
                "Bash(gh:*)"
                # Nix operations
                "Bash(nix build:*)"
                "Bash(nix develop:*)"
                "Bash(nix flake:*)"
                # Development tools
                "Bash(jq:*)"
                "Bash(latexmk:*)"
                "Bash(nvidia-smi:*)"
                "Bash(test:*)"
                "Bash(typst:*)"
                # Web tools
                "WebFetch"
                "WebSearch"
                # Allow all reads and searches; deny rules still block .env and sops age keys
                "Read"
                "Grep"
                "Glob"
                # mcps
                "mcp__*"
              ];
              deny = [
                "Bash(sudo:*)"
                "Bash(gh pr create:*)"
                "Bash(gh pr comment:*)"
                "Bash(gh issue create:*)"
                "Bash(gh issue comment:*)"
                "Bash(gh repo delete:*)"
                "Bash(rm -rf:*)"
                "Read(.env*)"
                "Read(~/.config/sops/age/**)"
                "Bash(nix run *)"
              ];
              ask = [
                "Bash(git push:*)"
              ];
            };
          };
        };

        home.shellAliases = {
          ccds = "claude";
          ccglm = "claude-glm";
          cccb = "claude-cerebras";
        };

        # symlink .local/bin to satisfy claude doctor
        home.file.".local/bin/claude".source =
          config.lib.file.mkOutOfStoreSymlink "${config.programs.claude-code.finalPackage}/bin/claude";
      };
  };
}
