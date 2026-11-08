{
  perSystem =
    {
      lib,
      pkgs,
      inputs',
      config,
      self',
      ...
    }:
    let
      # Match the home-manager python environment from modules/home/languages/python.nix.
      # duckdb resolves to nixpkgs' python3Packages.duckdb. The local
      # duckdb/python-duckdb pair that used to shadow it on machines now lives
      # in pkgs/disabled/ (see pkgs/disabled/README.md), so nixpkgs is the only
      # source here and on machines alike.
      python = pkgs.python3.withPackages (
        ps: with ps; [
          duckdb
          huggingface-hub
          pip
          trafilatura
        ]
      );
    in
    {
      devShells.default = pkgs.mkShell {
        inputsFrom = [
          config.pre-commit.devShell
        ];

        # Regenerates the repo-root AGENTS.md/CLAUDE.md from the
        # agent-context-* apm fragments whenever their inputs changed, so a
        # fresh clone or jj workspace gets them on first entry and a
        # fragment edit reaches them on the next one. The unchanged case
        # must exec nothing: the compile wrapper's runtimeInputs (apm, git,
        # yq-go, coreutils, findutils) exec roughly 20 non-Apple binaries
        # even just to hash the inputs, and each exec of non-Apple code on
        # macOS triggers a syspolicyd Gatekeeper adjudication -- paying that
        # cost on every shell entry and direnv reload, across every
        # worktree, contributed to a syspolicyd lockup. So the prefilter
        # below uses only bash builtins (globs, `-nt`, `read`) and execs the
        # compiler only when an output is missing or a symlink, the digest
        # stamp is missing, the recorded compile key (compiler store path
        # plus tier) differs, or apm.yml or a fragment (or its directory,
        # which catches removals) is newer than the stamp. The compiler's
        # `--if-stale` then decides on a content hash, and touches the stamp
        # when the hash still matches, so a jj rewrite that only moved
        # mtimes costs one exec, not one per entry. Stamp and key live in
        # the git-ignored .agents/. `--auto` picks the repository tier vs
        # every tier from the user-level context file, the same test the
        # prefilter uses for the key. The repo root is found by walking up
        # from $PWD to apm.yml beside .git, so entry from a subdirectory
        # works. The `if !` guard means a compile failure only warns, since
        # a missing or stale AGENTS.md degrades an agent session but must
        # not block a human terminal or direnv.
        shellHook = ''
          _vanixiets_agents_context() {
            local root=$PWD tool=${lib.getExe config.packages.apm-context-compile}
            while [[ ! ( -f $root/apm.yml && -e $root/.git ) ]]; do
              [[ $root == / ]] && return 0
              root=''${root%/*}
              [[ -n $root ]] || root=/
            done
            local stamp=$root/.agents/.context-inputs-sha256 tier=full key= stale=0 f
            [[ -e $HOME/.claude/CLAUDE.md ]] && tier=default
            [[ -r $root/.agents/.context-compile-key ]] && read -r key <"$root/.agents/.context-compile-key"
            if [[ ! -f $stamp || $key != "$tool $tier" ]]; then
              stale=1
            else
              for f in "$root/AGENTS.md" "$root/CLAUDE.md"; do
                [[ -f $f && ! -L $f ]] || stale=1
              done
              for f in "$root/apm.yml" "$root"/modules/home/ai/plugins/agent-context-*/.apm/instructions{,/*.instructions.md}; do
                if [[ $f -nt $stamp ]]; then
                  stale=1
                  break
                fi
              done
            fi
            ((stale)) || return 0
            if ! "$tool" --auto --if-stale; then
              echo "apm-context-compile: failed; AGENTS.md/CLAUDE.md may be stale or missing (run 'just agents-context' to see why)" >&2
            fi
          }
          _vanixiets_agents_context
          unset -f _vanixiets_agents_context

          # git-hooks.nix (via inputsFrom, whose shellHook runs first) writes
          # core.hooksPath relative to the checkout it installs from, so a value
          # written from the primary checkout resolves to nothing in a linked
          # worktree or colocated jj workspace, whose `.git` is a file, and git
          # there silently runs no hooks. The absolute common-dir path names the
          # same directory from every checkout. mergify's hooks mint the
          # Change-Id trailer for git-native commits; jj commits get theirs from
          # templates.commit_trailers and run no git hooks.
          if git_common_dir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
            git config --local core.hooksPath "$git_common_dir/hooks"
            if ! ${lib.getExe self'.packages.mergify-cli-bin} stack setup >/dev/null; then
              echo "mergify stack setup: failed; git commits will lack a Change-Id trailer" >&2
            fi
          fi
        ''
        + lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
          # WPE WebKit aborts with "Could not create EGL display: no supported
          # platform available" wherever there is no DRM device -- headless
          # servers, containers, and the nix build sandbox alike -- because
          # playwright-web-flake ships no software EGL vendor. Point libglvnd at
          # mesa's llvmpipe vendor, but only when /dev/dri is absent, so a
          # workstation keeps its hardware driver. The hermetic check sets the
          # same two variables unconditionally (pkgs/by-name/vanixiets-docs).
          if [[ ! -d /dev/dri ]]; then
            export __EGL_VENDOR_LIBRARY_FILENAMES="${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json"
            export LD_LIBRARY_PATH="${
              lib.makeLibraryPath [ pkgs.mesa ]
            }''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
          fi
          # The fork drops webkit revisionOverrides, so playwright resolves the
          # linux webkit directory under the ubuntu-24.04 name.
          export PLAYWRIGHT_HOST_PLATFORM_OVERRIDE="ubuntu-24.04"
        '';

        # The playwright-web-flake default devShell is intentionally not inherited;
        # select the browser set explicitly. Use the full flake set (chromium,
        # firefox, webkit) on both platforms: the fork carries a side-by-side
        # darwin webkit layout whose newest base build is macOS-26 (rev 2388,
        # matching playwright 1.65.0) alongside a macOS-14 fallback, plus the
        # Linux webkit builds, so the all-browser local `just docs-test` passes.
        # The hermetic e2e check in pkgs/by-name/vanixiets-docs/package.nix now
        # uses this same browser set on both platforms; the nixpkgs-chromium
        # wrapper it used to carry was removed after a differential experiment
        # disproved the Chrome-for-Testing sandbox-crash premise behind it.
        PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
        PLAYWRIGHT_BROWSERS_PATH = "${inputs'.playwright-web-flake.packages.playwright-driver.browsers}";

        packages = [
          # Match the fleet client (modules/system/nix-package.nix) rather than
          # nixpkgs' default 2.34.8, which nix-fast-build and
          # nix-prefetch-github otherwise put on PATH ahead of
          # /run/current-system/sw/bin inside the project directory.
          pkgs.nixVersions.nix_2_35
          python
          inputs'.clan-core.packages.default
          inputs'.nix2container.packages.skopeo-nix2container
          pkgs.just
          pkgs.nh
          pkgs.omnix
          pkgs.nix-output-monitor
          self'.packages.nix-fast-build
          pkgs.nix-update
          pkgs.nix-prefetch-github
          self'.packages.uncomment-bin
          # Tools required by Makefile verify target
          pkgs.age
          pkgs.ssh-to-age
          pkgs.sops
          # Identity administration; version tracks the kanidm server on magnetite
          pkgs.kanidm_1_11
          # Kubernetes cluster management
          pkgs.clusterctl
          pkgs.kluctl
          pkgs.k3d
          pkgs.ctlptl
          pkgs.kyverno-chainsaw
          pkgs.rsync # nixidy-sync manifest deployment
          # Tools required by TypeScript packages CI
          pkgs.bun
          inputs'.bun2nix.packages.default
          pkgs.nodejs_24 # semantic-release >= 24.10.0
          pkgs.fuc
          pkgs.rip2
          # Language detection
          pkgs.github-linguist
          # Document typesetting
          pkgs.typstWithPackages
          pkgs.svgo
          # The skills apm deploys into .agents/skills/ shell out to these CLIs.
          # Home-manager supplies them on a fleet machine and nowhere else, so
          # on a CI runner, an agent sandbox, or a fresh checkout a skill loads
          # and then dies on its first command. duckdb here is the CLI; the
          # python binding above is a separate output.
          pkgs.jujutsu
          self'.packages.ghq-shared
          pkgs.jaq
          pkgs.duckdb
          self'.packages.linear-cli
          self'.packages.mergify-cli-bin
          self'.packages.playwright-cli
          inputs'.llm-agents.packages.openspec
          # Supplies both `renovate` and `renovate-config-validator`. The
          # validator is what `checks.renovate-config` runs in the sandbox;
          # having it on PATH lets an edit to .github/renovate.json be checked
          # in a second rather than through a nix build. `renovate` itself is
          # here for `just renovate`, which previews the bot's decisions
          # against the working tree via the local platform.
          pkgs.renovate
        ];

        passthru.meta.description = "Development environment with clan CLI and build tools";
      };
    };
}
