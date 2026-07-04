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

      session-start = pkgs.writeShellApplication {
        name = "session-start";
        runtimeInputs = with pkgs; [
          git
          gh
          jq
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

      gate-worktree-surfaces = pkgs.writeShellApplication {
        name = "gate-worktree-surfaces";
        runtimeInputs = with pkgs; [
          jq
          coreutils
        ];
        text = builtins.readFile ./gate-worktree-surfaces.sh;
      };

      jj-worktree-create = pkgs.writeShellApplication {
        name = "jj-worktree-create";
        runtimeInputs = with pkgs; [
          jq
          jujutsu
          git
          coreutils
        ];
        text = builtins.readFile ./jj-worktree-create.sh;
      };

      jj-worktree-remove = pkgs.writeShellApplication {
        name = "jj-worktree-remove";
        runtimeInputs = with pkgs; [
          jq
          jujutsu
          git
          coreutils
        ];
        text = builtins.readFile ./jj-worktree-remove.sh;
      };

      gate-git-worktree = pkgs.writeShellApplication {
        name = "gate-git-worktree";
        runtimeInputs = with pkgs; [
          jq
          gnugrep
          coreutils
        ];
        text = builtins.readFile ./gate-git-worktree.sh;
      };

      verify-diamond-before-edit = pkgs.writeShellApplication {
        name = "verify-diamond-before-edit";
        runtimeInputs = with pkgs; [
          jujutsu
          coreutils
          gnused
          gnugrep
        ];
        text = builtins.readFile ./verify-diamond-before-edit.sh;
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
    in
    {
      home.packages = [
        memory-capture
        nudge-claude-md-update
        enforce-branch-before-edit
        session-start
        clarify-vague-request
        redirect-rm-to-rip
        notify-permission-wait
        gate-mutating-http
        gate-worktree-surfaces
        jj-worktree-create
        jj-worktree-remove
        gate-git-worktree
        verify-diamond-before-edit
        gate-dangerous-commands
        notify-permission-prompt
      ];
    };
}
