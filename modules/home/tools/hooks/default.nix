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

      # Hosts where mutating HTTP requests (POST, PUT, etc.) are auto-approved
      # by gate-mutating-http without prompting. Matched as hostnames in URLs
      # with or without scheme prefix (e.g. both https://ntfy.zt/topic and
      # ntfy.zt/topic are recognized).
      trustedHttpMutationHosts = [
        "ntfy.zt"
      ];

      trustedHostsPattern =
        if trustedHttpMutationHosts == [ ] then
          ""
        else
          let
            escaped = map (h: builtins.replaceStrings [ "." ] [ "\\." ] h) trustedHttpMutationHosts;
            alternation = builtins.concatStringsSep "|" escaped;
          in
          "(https?://|[[:space:]])(${alternation})(/|:|[[:space:]]|$)";

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

      notify-permission-wait = pkgs.writeShellApplication {
        name = "notify-permission-wait";
        runtimeInputs = with pkgs; [
          curl
          git
          coreutils
        ];
        text = builtins.readFile ./notify-permission-wait.sh;
      };

      gate-mutating-http = pkgs.writeShellApplication {
        name = "gate-mutating-http";
        runtimeInputs = [
          notify-permission-wait
          pkgs.jq
          pkgs.gnugrep
        ];
        text = builtins.replaceStrings [ "@trustedHostsPattern@" ] [ trustedHostsPattern ] (
          builtins.readFile ./gate-mutating-http.sh
        );
      };

      gate-dangerous-commands = pkgs.writeShellApplication {
        name = "gate-dangerous-commands";
        runtimeInputs = [
          notify-permission-wait
          pkgs.jq
          pkgs.gnugrep
        ];
        text = builtins.readFile ./gate-dangerous-commands.sh;
      };

      gate-issue-close = pkgs.writeShellApplication {
        name = "gate-issue-close";
        runtimeInputs = with pkgs; [
          beads
          curl
          git
          jq
          gnused
          gnugrep
          bash
          coreutils
        ];
        text = builtins.readFile ./gate-issue-close.sh;
      };

      notify-escalation = pkgs.writeShellApplication {
        name = "notify-escalation";
        runtimeInputs = with pkgs; [
          beads
          curl
          git
          jq
          gnused
          gnugrep
          coreutils
        ];
        text = builtins.readFile ./notify-escalation.sh;
      };

      bulk-signal-init = pkgs.writeShellApplication {
        name = "bulk-signal-init";
        runtimeInputs = with pkgs; [
          beads
          jq
          coreutils
          gnugrep
        ];
        text = builtins.readFile ./bulk-signal-init.sh;
      };

      notify-permission-prompt = pkgs.writeShellApplication {
        name = "notify-permission-prompt";
        runtimeInputs = with pkgs; [
          curl
          git
          jq
          coreutils
        ];
        text = builtins.readFile ./notify-permission-prompt.sh;
      };

      notify-epic-completion = pkgs.writeShellApplication {
        name = "notify-epic-completion";
        runtimeInputs = with pkgs; [
          beads
          curl
          git
          jq
          coreutils
          gnugrep
          gnused
        ];
        text = builtins.readFile ./notify-epic-completion.sh;
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
        notify-permission-wait
        gate-mutating-http
        gate-dangerous-commands
        gate-issue-close
        notify-escalation
        bulk-signal-init
        notify-permission-prompt
        notify-epic-completion
      ];
    };
}
