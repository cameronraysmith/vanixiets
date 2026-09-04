{ ... }:
{
  flake.modules.homeManager.development =
    {
      pkgs,
      lib,
      flake,
      ...
    }:
    let
      dvcWithOptionalRemotes = pkgs.dvc.override {
        enableGoogle = true;
        enableAWS = true;
        enableAzure = true;
        enableSSH = true;
      };
      # gitmux wrapper: in jj-colocated repos, redirect gitmux's git calls onto a reused
      # per-repo shadow index so `git diff --shortstat` never rewrites .git/index and races
      # jj's colocated export. Fixed reused path overwritten via reflink-clone => no rm/trap/mktemp.
      gitmux = pkgs.writeShellApplication {
        name = "gitmux";
        runtimeInputs = [
          pkgs.git
          pkgs.coreutils
        ];
        text = ''
          # gitmux's last positional arg is the pane's cwd.
          repo="''${*: -1}"
          [ -n "$repo" ] || repo="$PWD"
          top="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null || true)"
          gitdir="$(git -C "$repo" rev-parse --absolute-git-dir 2>/dev/null || true)"
          if [ -n "$top" ] && [ -d "$top/.jj" ] && [ -n "$gitdir" ] && [ -f "$gitdir/index" ]; then
            # jj-colocated: isolate gitmux's index writes onto a reused shadow copy.
            shadow="$gitdir/index.gitmux"
            cp --reflink=auto "$gitdir/index" "$shadow" 2>/dev/null || cp "$gitdir/index" "$shadow"
            exec env GIT_INDEX_FILE="$shadow" ${pkgs.gitmux}/bin/gitmux "$@"
          fi
          exec ${pkgs.gitmux}/bin/gitmux "$@"
        '';
      };
      # coderabbit-cli = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.coderabbit-cli;
      # crush = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.crush;
      apm = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.apm;
      cursor-agent = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.cursor-agent;
      # opencode: disabled - bun node_modules cleanup fails during build
      droid = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.droid;
      gemini-cli = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.gemini-cli;
    in
    {
      home.packages =
        with pkgs;
        [
          act
          bazelisk
          bazel-buildtools
          buf
          smithy-cli
          claude-monitor
          clipboard-jh
          dvcWithOptionalRemotes
          forgejo-cli
          ghq
          git-filter-repo
          git-machete
          git-revise
          git-xet
          gitmux
          d2
          graphviz
          jc
          jqp
          jjui
          just
          mkcert
          # from llm-agents
          apm
          cursor-agent
          droid
          gemini-cli
          # from pkgs/by-name
          golem-binary
          hindsight
          linear-cli
          ouroboros
          uncomment-bin
          #------
          plantuml-c4
          ratchet
          shellcheck
          tea
          tmate
          tree-sitter
          jaq
          yq
        ]
        # backlog-md disabled: auto-patchelf fails on rosetta-builder (elftools issue)
        # ++ lib.optionals (pkgs.stdenv.hostPlatform.system == "x86_64-linux") [
        #   flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.backlog-md
        # ]
        # claudebox requires bubblewrap which is Linux-only
        ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
          flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claudebox
        ];
    };
}
