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
      # Rename graphite-cli binary from `gt` to `grt`
      #
      # Conflict: upstream graphite-cli uses `gt` which collides with gastown.
      # gastown (multi-agent orchestration framework) natively uses `gt` for its CLI.
      # This rename frees `gt` for gastown while keeping graphite-cli accessible as `grt`.
      #
      # Pattern: stackit-cli style postInstall rename with completion regeneration
      graphite-cli = prev.graphite-cli.overrideAttrs (oldAttrs: {
        postInstall = prev.lib.optionalString (prev.stdenv.buildPlatform.canExecute prev.stdenv.hostPlatform) ''
          # Rename binary: gt -> grt
          mv $out/bin/gt $out/bin/grt

          # Regenerate shell completions for renamed binary
          installShellCompletion --cmd grt \
            --bash <($out/bin/grt completion) \
            --fish <(GT_PAGER= $out/bin/grt fish) \
            --zsh <(ZSH_NAME=zsh $out/bin/grt completion)

          # Fix zsh completion directive to reference renamed binary
          # Pattern: cobra-cli style completion metadata patching
          substituteInPlace $out/share/zsh/site-functions/_grt \
            --replace-fail '#compdef gt' '#compdef grt'
        '';

        meta = oldAttrs.meta // {
          mainProgram = "grt";
        };
      });
    })
  ];
}
