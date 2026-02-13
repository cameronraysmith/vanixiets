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
              CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR = "0";
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
                # mcps
                "mcp__*"
              ];
              deny = [
                # rm is handled by redirect-rm-to-rip PreToolUse hook
                "Bash(rm *)"
                # Secrets
                "Read(.env*)"
                "Read(~/.config/sops/age/**)"
              ];
              ask = [
                # Privilege escalation
                "Bash(sudo:*)"
                # Git: push and destructive operations
                "Bash(git push:*)"
                "Bash(git reset --hard*)"
                "Bash(git clean *)"
                "Bash(git checkout .)"
                "Bash(git checkout -- .)"
                "Bash(git restore .)"
                "Bash(git restore --staged .)"
                "Bash(git branch -D *)"
                "Bash(git stash drop*)"
                "Bash(git stash clear*)"
                # GitHub CLI: mutating operations
                "Bash(gh api *)"
                "Bash(gh pr create:*)"
                "Bash(gh pr comment:*)"
                "Bash(gh pr merge:*)"
                "Bash(gh pr close:*)"
                "Bash(gh pr edit:*)"
                "Bash(gh pr review:*)"
                "Bash(gh issue create:*)"
                "Bash(gh issue comment:*)"
                "Bash(gh issue close:*)"
                "Bash(gh issue edit:*)"
                "Bash(gh repo create:*)"
                "Bash(gh repo delete:*)"
                "Bash(gh repo rename:*)"
                "Bash(gh release create:*)"
                "Bash(gh release delete:*)"
                "Bash(gh workflow run:*)"
                "Bash(gh gist create:*)"
                # Nix: arbitrary code execution
                "Bash(nix run *)"
                "Bash(nix shell *)"
                # Infrastructure mutation
                "Bash(tofu apply*)"
                "Bash(tofu destroy*)"
                "Bash(terraform apply*)"
                "Bash(terraform destroy*)"
                "Bash(kubectl apply *)"
                "Bash(kubectl create *)"
                "Bash(kubectl delete *)"
                "Bash(kubectl exec *)"
                "Bash(helm install *)"
                "Bash(helm upgrade *)"
                "Bash(helm uninstall *)"
                # Remote access
                "Bash(ssh *)"
                "Bash(scp *)"
                "Bash(rsync *)"
                # Container publishing
                "Bash(docker push *)"
                "Bash(podman push *)"
                # Process management
                "Bash(kill *)"
                "Bash(killall *)"
                "Bash(pkill *)"
                # HTTP: mutating requests (gate-mutating-http hook auto-approves safe GETs)
                # Does not cover httpie (http/https) or xh; add if these enter the workflow
                "Bash(curl *)"
                "Bash(wget *)"
                # Destructive find/xargs patterns (bypass rm deny via -exec/xargs)
                "Bash(find *-delete*)"
                "Bash(find *-exec*rm *)"
                "Bash(xargs rm*)"
                "Bash(xargs *rm*)"
                # Raw writes and secure deletion
                "Bash(dd *)"
                "Bash(truncate *)"
                "Bash(shred *)"
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
