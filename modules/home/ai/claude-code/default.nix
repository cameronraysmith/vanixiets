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
              CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
              CLAUDE_CODE_SUBAGENT_MODEL = "opus";
              UV_NO_SYNC = "1";
              TMPDIR = "/tmp/claude";
              TMPPREFIX = "/tmp/claude/zsh";
              ASTRO_TELEMETRY_DISABLED = "1";
            };
            teammateMode = "tmux";

            sandbox = {
              enabled = true;
              autoAllowBashIfSandboxed = true;
              allowUnsandboxedCommands = false;
              excludedCommands = [
                "docker"
                "nix"
              ];
              network = {
                allowedDomains = [
                  "hydra.nixos.org"
                  "github.com"
                  "*.githubusercontent.com"
                ];
                # does not work as of 2026-02-08 (ref mirkolenz-nixos)
                allowUnixSockets = [ "/nix/var/nix/daemon-socket/socket" ];
                allowLocalBinding = true;
              };
            };

            permissions = {
              defaultMode = "acceptEdits";
              # only enforced from managed-settings.json, included here as intent marker
              disableBypassPermissionsMode = "disable";
              additionalDirectories = [
                "~/projects"
                "/nix/store"
              ];
              allow = [
                # Basics
                "Bash(cat:*)"
                "Bash(echo:*)"
                "Bash(find:*)"
                "Bash(grep:*)"
                "Bash(head:*)"
                "Bash(ls:*)"
                "Bash(mkdir:*)"
                "Bash(pwd)"
                "Bash(tail:*)"
                "Bash(which:*)"
                # Git operations
                "Bash(git add:*)"
                "Bash(git branch:*)"
                "Bash(git checkout:*)"
                "Bash(git commit:*)"
                "Bash(git config:*)"
                "Bash(git diff:*)"
                "Bash(git log:*)"
                "Bash(git push)"
                "Bash(git rebase:*)"
                "Bash(git reset:*)"
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
                "Bash(test:*)"
                # Web tools
                "WebFetch"
                "WebSearch"
                # Allow all reads and searches; deny rules still block .env, secrets, sops keys
                "Read"
                "Grep"
                "Glob"
                # mcps
                "mcp__*"
              ];
              deny = [
                "Bash(sudo:*)"
                "Bash(rm -rf:*)"
                "Read(.env*)"
                "Read(*secret*)"
                "Read(~/.config/sops/age/**)"
                "Bash(nix run *)"
              ];
              ask = [ ];
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
