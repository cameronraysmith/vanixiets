# Claude Code CLI configuration with MCP servers and ccstatusline
# Pattern A: flake.modules (plural) with homeManager.ai aggregate
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
        # Note: mcp-servers.nix, wrappers.nix, and ccstatusline-settings.nix are separate
        # Pattern A modules that merge into homeManager.ai aggregate via import-tree

        # Integrated llm-agents flake input for claude-code package
        # Pattern A (flake context access): package override from external flake input
        programs.claude-code = {
          enable = true;
          package = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;

          # symlink commands and agents directory trees
          commandsDir = ./commands;
          agentsDir = ./agents;

          # https://schemastore.org/claude-code-settings.json
          settings = {
            # Enable ccstatusline (package now available via pkgs-by-name)
            statusLine = {
              type = "command";
              command = "${pkgs.ccstatusline}/bin/ccstatusline";
              padding = 0;
            };

            theme = "dark";
            autoCompactEnabled = false;
            spinnerTipsEnabled = false;
            cleanupPeriodDays = 1100;
            includeCoAuthoredBy = false;
            enableAllProjectMcpServers = false;
            alwaysThinkingEnabled = true;

            permissions = {
              defaultMode = "acceptEdits";
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
                "Bash(git reset:*)"
                "Bash(git rev-parse:*)"
                "Bash(git show:*)"
                "Bash(git stash:*)"
                "Bash(git status:*)"
                "Bash(git tag:*)"
                # GitHub CLI
                "Bash(gh:*)"
                # Nix operations
                "Bash(nix build:*)"
                "Bash(nix develop:*)"
                "Bash(nix flake:*)"
                "Bash(nix run:*)"
                # Development tools
                "Bash(jq:*)"
                "Bash(test:*)"
                # mcps
                "mcp__*"
              ];
              deny = [
                "Bash(sudo:*)"
                "Bash(rm -rf:*)"
              ];
              ask = [ ];
            };

            # hooks = {
            #   PostToolUse = [
            #     {
            #       matcher = "Edit|MultiEdit|Write";
            #       hooks = [
            #         {
            #           type = "command";
            #           command = ''
            #             file_path=$(echo "$CLAUDE_TOOL_INPUT" | jq -r '.file_path // .files[0].file_path // empty')
            #             if [ -n "$file_path" ] && [[ "$file_path" == *.nix ]]; then
            #               nix fmt "$file_path" 2>/dev/null || true
            #             fi
            #           '';
            #         }
            #       ];
            #     }
            #   ];
            # };
          };
        };

        home.shellAliases = {
          ccds = "claude --dangerously-skip-permissions";

          # Optional sandboxed variants (landrun-nix, Linux only)
          # Note: landrun uses Landlock LSM which is not available on Darwin/macOS
        }
        // lib.optionalAttrs pkgs.stdenv.isLinux {
          claude-safe = "nix run .#claude-sandboxed --";
          ccds-safe = "nix run .#ccds-sandboxed --";
        };

        # symlink .local/bin to satisfy claude doctor
        home.file.".local/bin/claude".source =
          config.lib.file.mkOutOfStoreSymlink "${config.programs.claude-code.finalPackage}/bin/claude";
      };
  };
}
