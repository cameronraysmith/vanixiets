# Per-package build modifications
#
# Flake-parts module exporting override overlays via list concatenation
#
# This file contains per-package overrideAttrs customizations:
# - Binary renaming for conflict resolution
# - Test disabling
# - Build flag modifications
# - Patch applications
#
{ ... }:
{
  flake.nixpkgsOverlays = [
    (final: prev: {
      # pygame: SDL2 surface flag tests fail on Python 3.13
      # Upstream: https://github.com/libsdl-org/SDL/issues/14424
      # Failing: test_fill_rle, test_make_surface__subclassed_surface
      # TODO: Remove when nixpkgs skip-rle-tests.patch covers these tests
      # Date added: 2026-01-24
      python3 = prev.python3.override {
        packageOverrides = pyFinal: pyPrev: {
          pygame = pyPrev.pygame.overrideAttrs {
            doCheck = false;
            doInstallCheck = false;
          };
        };
      };
      python3Packages = final.python3.pkgs;

      # mactop: Test fails in Nix sandbox environment
      # Issue: TestHeadlessIntegration tries to mkdir /homeless-shelter (sandbox $HOME)
      # Symptom: mkdir /homeless-shelter: read-only file system
      # Reference: https://github.com/metaspartan/mactop/issues (upstream test issue)
      # TODO: Remove when upstream fixes test to use temp directory
      # Date added: 2026-01-10
      mactop = prev.mactop.overrideAttrs (old: {
        doCheck = false;
      });
      # Rename graphite-cli binary from `gt` to `gph`
      #
      # Conflict: upstream graphite-cli uses `gt` which collides with gastown.
      # gastown (multi-agent orchestration framework) natively uses `gt` for its CLI.
      # This rename frees `gt` for gastown while keeping graphite-cli accessible as `gph`.
      #
      # Note: `grt` was considered but conflicts with existing shell alias for git-root.
      #
      # Pattern: stackit-cli style postInstall rename with completion regeneration
      graphite-cli = prev.graphite-cli.overrideAttrs (oldAttrs: {
        postInstall = prev.lib.optionalString (prev.stdenv.buildPlatform.canExecute prev.stdenv.hostPlatform) ''
          # Rename binary: gt -> gph
          mv $out/bin/gt $out/bin/gph

          # Regenerate shell completions for renamed binary
          installShellCompletion --cmd gph \
            --bash <($out/bin/gph completion) \
            --fish <(GT_PAGER= $out/bin/gph fish) \
            --zsh <(ZSH_NAME=zsh $out/bin/gph completion)

          # Fix zsh completion directive to reference renamed binary
          # Pattern: cobra-cli style completion metadata patching
          substituteInPlace $out/share/zsh/site-functions/_gph \
            --replace-fail '#compdef gt' '#compdef gph'
        '';

        meta = oldAttrs.meta // {
          mainProgram = "gph";
        };
      });
    })
  ];
}
