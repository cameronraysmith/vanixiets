{ inputs, ... }:
{
  imports = [
    inputs.flake-parts.flakeModules.modules # Enable flake.modules merging
    # Note: clan-core imported in modules/clan/core.nix
    # Note: nix-unit invoked directly via flake.lib.mkEvalCheck rather than
    #       through inputs.nix-unit.modules.flake.default — see
    #       modules/lib/mk-eval-check.nix for rationale.
  ];
}
