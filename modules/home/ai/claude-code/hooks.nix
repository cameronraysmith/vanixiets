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
        };
      };
  };
}
