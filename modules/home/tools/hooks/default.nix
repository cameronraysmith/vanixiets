# Hook scripts packaged as writeShellApplication derivations.
# These end up on PATH so that programs.claude-code.settings.hooks
# can reference them by bare command name.
{ ... }:
{
  flake.modules.homeManager.tools =
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
        text = builtins.readFile ./validate-epic-close.sh;
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
        text = builtins.readFile ./log-dispatch-prompt.sh;
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
        text = builtins.readFile ./memory-capture.sh;
      };

      nudge-claude-md-update = pkgs.writeShellApplication {
        name = "nudge-claude-md-update";
        runtimeInputs = with pkgs; [
          git
          gnused
          gnugrep
          coreutils
        ];
        text = builtins.readFile ./nudge-claude-md-update.sh;
      };
    in
    {
      home.packages = [
        validate-epic-close
        log-dispatch-prompt
        memory-capture
        nudge-claude-md-update
      ];
    };
}
