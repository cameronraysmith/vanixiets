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

      enforce-branch-before-edit = pkgs.writeShellApplication {
        name = "enforce-branch-before-edit";
        runtimeInputs = with pkgs; [
          git
          jq
        ];
        text = builtins.readFile ./enforce-branch-before-edit.sh;
      };

      enforce-sequential-dispatch = pkgs.writeShellApplication {
        name = "enforce-sequential-dispatch";
        runtimeInputs = with pkgs; [
          beads
          jq
          git
          gnused
          gnugrep
        ];
        text = builtins.readFile ./enforce-sequential-dispatch.sh;
      };

      session-start = pkgs.writeShellApplication {
        name = "session-start";
        runtimeInputs = with pkgs; [
          git
          gh
          jq
          beads
          coreutils
        ];
        text = builtins.readFile ./session-start.sh;
      };

      clarify-vague-request = pkgs.writeShellApplication {
        name = "clarify-vague-request";
        runtimeInputs = with pkgs; [
          jq
        ];
        text = builtins.readFile ./clarify-vague-request.sh;
      };

      validate-completion = pkgs.writeShellApplication {
        name = "validate-completion";
        runtimeInputs = with pkgs; [
          git
          beads
          jq
          coreutils
          gnugrep
        ];
        text = builtins.readFile ./validate-completion.sh;
      };

      redirect-rm-to-rip = pkgs.writeShellApplication {
        name = "redirect-rm-to-rip";
        runtimeInputs = with pkgs; [
          jq
          gnugrep
        ];
        text = builtins.readFile ./redirect-rm-to-rip.sh;
      };

      gate-mutating-http = pkgs.writeShellApplication {
        name = "gate-mutating-http";
        runtimeInputs = with pkgs; [
          jq
          gnugrep
        ];
        text = builtins.readFile ./gate-mutating-http.sh;
      };
    in
    {
      home.packages = [
        validate-epic-close
        log-dispatch-prompt
        memory-capture
        nudge-claude-md-update
        enforce-branch-before-edit
        enforce-sequential-dispatch
        session-start
        clarify-vague-request
        validate-completion
        redirect-rm-to-rip
        gate-mutating-http
      ];
    };
}
