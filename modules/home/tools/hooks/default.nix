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

      # Prepended to the hooks that resolve repository context. Shell has no
      # import, and these are single-file writeShellApplication derivations, so
      # sharing means textual composition at build time.
      repoContextLib = builtins.readFile ./lib-repo-context.sh;

      # Each consumer of repoContextLib calls a subset of its helpers, so
      # shellcheck reports the remainder as uninvoked (SC2329) in every
      # composed script. writeShellApplication fails the build on any finding.
      repoContextShellChecks = [ "SC2329" ];

      enforce-branch-before-edit = pkgs.writeShellApplication {
        name = "enforce-branch-before-edit";
        runtimeInputs = with pkgs; [
          git
          jq
        ];
        excludeShellChecks = repoContextShellChecks;
        text = repoContextLib + builtins.readFile ./enforce-branch-before-edit.sh;
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
          ntfy-send
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
          git
          coreutils
        ];
        excludeShellChecks = repoContextShellChecks;
        text = repoContextLib + builtins.readFile ./gate-worktree-surfaces.sh;
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
          git
          coreutils
        ];
        excludeShellChecks = repoContextShellChecks;
        text = repoContextLib + builtins.readFile ./gate-git-worktree.sh;
      };

      verify-diamond-before-edit = pkgs.writeShellApplication {
        name = "verify-diamond-before-edit";
        runtimeInputs = with pkgs; [
          jujutsu
          git
          coreutils
          gnused
          gnugrep
        ];
        excludeShellChecks = repoContextShellChecks;
        text = repoContextLib + builtins.readFile ./verify-diamond-before-edit.sh;
      };

      gate-dangerous-commands = pkgs.writeShellApplication {
        name = "gate-dangerous-commands";
        runtimeInputs = [
          notify-permission-wait
          pkgs.ntfy-send
          pkgs.jq
          pkgs.gnugrep
        ];
        text = builtins.readFile ./gate-dangerous-commands.sh;
      };

      notify-permission-prompt = pkgs.writeShellApplication {
        name = "notify-permission-prompt";
        runtimeInputs = with pkgs; [
          ntfy-send
          git
          jq
          coreutils
        ];
        text = builtins.readFile ./notify-permission-prompt.sh;
      };
    in
    {
      home.packages = [
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
