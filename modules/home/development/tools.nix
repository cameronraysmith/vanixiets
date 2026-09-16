{ config, ... }:
{
  flake.modules.homeManager.development =
    { pkgs, ... }:
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
    in
    {
      imports = [
        config.flake.modules.homeManager.ghq
        config.flake.modules.homeManager.engineering-tools
      ];
      home.packages = with pkgs; [
        act
        bazelisk
        bazel-buildtools
        buf
        smithy-cli
        clipboard-jh
        dvcWithOptionalRemotes
        forgejo-cli
        git-filter-repo
        git-machete
        git-revise
        git-xet
        gitmux
        d2
        graphviz
        mkcert
        linear-cli
        plantuml-c4
        tea
        tree-sitter
      ];
    };
}
