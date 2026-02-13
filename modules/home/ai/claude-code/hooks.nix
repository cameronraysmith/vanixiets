# Claude Code hooks configuration
# Hook scripts are packaged in modules/home/tools/hooks/ and available on PATH.
{ ... }:
{
  flake.modules = {
    homeManager.ai =
      { ... }:
      {
        programs.claude-code.settings.hooks = {
          PreToolUse = [
            {
              matcher = "Bash";
              hooks = [
                {
                  type = "command";
                  command = "validate-epic-close";
                }
                {
                  type = "command";
                  command = "redirect-rm-to-rip";
                }
                {
                  type = "command";
                  command = "gate-mutating-http";
                }
              ];
            }
            {
              matcher = "Edit|Write|MultiEdit";
              hooks = [
                {
                  type = "command";
                  command = "enforce-branch-before-edit";
                }
              ];
            }
            {
              matcher = "Task";
              hooks = [
                {
                  type = "command";
                  command = "enforce-sequential-dispatch";
                }
              ];
            }
          ];

          PostToolUse = [
            {
              matcher = "Task";
              hooks = [
                {
                  type = "command";
                  command = "log-dispatch-prompt";
                  async = true;
                }
              ];
            }
            {
              matcher = "Bash";
              hooks = [
                {
                  type = "command";
                  command = "memory-capture";
                  async = true;
                }
              ];
            }
          ];

          PreCompact = [
            {
              hooks = [
                {
                  type = "command";
                  command = "nudge-claude-md-update";
                }
              ];
            }
          ];

          SessionStart = [
            {
              hooks = [
                {
                  type = "command";
                  command = "session-start";
                }
              ];
            }
          ];

          UserPromptSubmit = [
            {
              hooks = [
                {
                  type = "command";
                  command = "clarify-vague-request";
                }
              ];
            }
          ];

          SubagentStop = [
            {
              hooks = [
                {
                  type = "command";
                  command = "validate-completion";
                }
              ];
            }
          ];

          TaskCompleted = [
            {
              hooks = [
                {
                  type = "command";
                  command = "validate-completion";
                }
              ];
            }
          ];
        };
      };
  };
}
