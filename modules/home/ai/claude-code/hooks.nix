# Claude Code hooks configuration
# Wraps hook scripts with writeShellApplication for nix store paths
# and wires them into programs.claude-code.settings.hooks.
{ ... }:
{
  flake.modules = {
    homeManager.ai =
      {
        pkgs,
        flake,
        ...
      }:
      let
        beads = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.beads;

        validate-epic-close = pkgs.writeShellApplication {
          name = "validate-epic-close";
          runtimeInputs = with pkgs; [
            beads
            gh
            git
            jq
            gnused
            gnugrep
          ];
          text = builtins.readFile ./hooks/validate-epic-close.sh;
        };

        log-dispatch-prompt = pkgs.writeShellApplication {
          name = "log-dispatch-prompt";
          runtimeInputs = with pkgs; [
            beads
            jq
            git
            gnugrep
            gnused
          ];
          text = builtins.readFile ./hooks/log-dispatch-prompt.sh;
        };

        memory-capture = pkgs.writeShellApplication {
          name = "memory-capture";
          runtimeInputs = with pkgs; [
            jq
            coreutils
            git
            gnused
            gnugrep
          ];
          text = builtins.readFile ./hooks/memory-capture.sh;
        };

        nudge-claude-md-update = pkgs.writeShellApplication {
          name = "nudge-claude-md-update";
          runtimeInputs = with pkgs; [
            git
            gnused
            gnugrep
            coreutils
          ];
          text = builtins.readFile ./hooks/nudge-claude-md-update.sh;
        };
      in
      {
        programs.claude-code.settings.hooks = {
          PreToolUse = [
            {
              matcher = "Bash";
              hooks = [
                {
                  type = "command";
                  command = "${validate-epic-close}/bin/validate-epic-close";
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
                  command = "${log-dispatch-prompt}/bin/log-dispatch-prompt";
                  async = true;
                }
              ];
            }
            {
              matcher = "Bash";
              hooks = [
                {
                  type = "command";
                  command = "${memory-capture}/bin/memory-capture";
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
                  command = "${nudge-claude-md-update}/bin/nudge-claude-md-update";
                }
              ];
            }
          ];
        };
      };
  };
}
