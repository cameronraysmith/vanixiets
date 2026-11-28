# Claude Code hooks configuration, shared by the `ai` aggregate and the
# `claude-sandbox` profile. Each command is the store path of a hook packaged by
# `flake.lib.claudeCodeHooks` (modules/home/tools/hooks), so a hook runs in a
# profile that does not put the hooks on PATH, such as a cloud session's.
{ config, ... }:
let
  hookPackages = config.flake.lib.claudeCodeHooks;
in
{
  flake.modules = {
    homeManager.ai-claude-code.imports = [ config.flake.modules.homeManager.claude-code-hooks ];

    homeManager.claude-code-hooks =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        hooks = hookPackages pkgs;
        command = name: lib.getExe hooks.${name};

        # A command Claude Code resolves through PATH fails with "command not
        # found" wherever the hook is not on PATH, and nothing else notices.
        commands = lib.concatMap (lib.concatMap (group: map (hook: hook.command) group.hooks)) (
          lib.attrValues config.programs.claude-code.settings.hooks
        );
        bareCommands = lib.filter (c: !lib.hasPrefix "${builtins.storeDir}/" c) commands;
      in
      {
        key = "vanixiets/claude-code-hooks-home-module";

        assertions = [
          {
            assertion = bareCommands == [ ];
            message = "programs.claude-code.settings.hooks must call every hook by store path; bare commands: ${lib.concatStringsSep ", " bareCommands}";
          }
        ];

        programs.claude-code.settings.hooks = {
          PreToolUse = [
            {
              matcher = "Bash";
              hooks = [
                {
                  type = "command";
                  command = command "redirect-rm-to-rip";
                }
                {
                  type = "command";
                  command = command "gate-mutating-http";
                }
                {
                  type = "command";
                  command = command "gate-dangerous-commands";
                }
                {
                  type = "command";
                  command = command "gate-git-worktree";
                }
              ];
            }
            {
              matcher = "Edit|Write|MultiEdit";
              hooks = [
                {
                  type = "command";
                  command = command "enforce-branch-before-edit";
                }
              ];
            }
            {
              matcher = "Edit|Write|MultiEdit";
              hooks = [
                {
                  type = "command";
                  command = command "verify-diamond-before-edit";
                }
              ];
            }
            {
              # Subagent dispatch surfaces as tool_name "Agent". Across
              # ~/.claude/projects transcripts, the last tool_use block named
              # "Task" is dated 2026-02-28 and blocks named "Agent" run from
              # that day onward.
              matcher = "Agent";
              hooks = [
                {
                  type = "command";
                  command = command "gate-worktree-surfaces";
                }
              ];
            }
            {
              matcher = "EnterWorktree";
              hooks = [
                {
                  type = "command";
                  command = command "gate-worktree-surfaces";
                }
              ];
            }
          ];

          WorktreeCreate = [
            {
              hooks = [
                {
                  type = "command";
                  command = command "jj-worktree-create";
                }
              ];
            }
          ];

          WorktreeRemove = [
            {
              hooks = [
                {
                  type = "command";
                  command = command "jj-worktree-remove";
                }
              ];
            }
          ];

          SessionStart = [
            {
              hooks = [
                {
                  type = "command";
                  command = command "session-start";
                }
              ];
            }
          ];

          UserPromptSubmit = [
            {
              hooks = [
                {
                  type = "command";
                  command = command "clarify-vague-request";
                }
              ];
            }
          ];

          Notification = [
            {
              matcher = "permission_prompt";
              hooks = [
                {
                  type = "command";
                  command = command "notify-permission-prompt";
                  async = true;
                }
              ];
            }
          ];
        };
      };
  };
}
