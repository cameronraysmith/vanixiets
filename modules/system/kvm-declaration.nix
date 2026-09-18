# Per-host declaration of whether the machine can run KVM-accelerated builds.
#
# NixOS advertises "kvm" in nix.settings.system-features unconditionally
# (nixos/modules/config/nix.nix, defaultSystemFeatures), which is right on real
# hardware and wrong on every cloud VM in this fleet: those have no /dev/kvm and
# no nested virtualisation, so the scheduler routes a kvm-requiring derivation to
# a host that then fails it. Evaluation cannot inspect the target machine's
# device nodes without breaking purity, so this is a declaration the operator
# makes and keeps true, never a detection. Verify on the machine with
# `test -c /dev/kvm`.
#
# declaredKvm.present has no default: a host importing this module must state the
# claim, so an absent claim is an evaluation error rather than an inherited one.
#
# The assignment forces the whole feature list, because removing one element from
# a merged list is not expressible otherwise: nixpkgs both declares the option
# with a default and defines it in config, precisely so other modules can add to
# it. Any such addition on the host is therefore discarded by the force and has
# to come back through extraFeatures.
{ lib, ... }:
{
  flake.modules.nixos.kvm-declaration =
    {
      config,
      options,
      ...
    }:
    let
      cfg = config.declaredKvm;
      nixosDefault = (options.nix.settings.type.getSubOptions [ ]).system-features.default;
    in
    {
      options.declaredKvm = {
        present = lib.mkOption {
          type = lib.types.bool;
          example = false;
          description = ''
            Whether this machine exposes `/dev/kvm` to the nix daemon. `true`
            keeps `kvm` in `nix.settings.system-features`, `false` removes it.
            This is an operator claim about the machine, not something evaluation
            can observe.
          '';
        };

        extraFeatures = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = lib.literalExpression "config.programs.nix-required-mounts.allowedPatterns.nvidia-gpu.onFeatures";
          description = ''
            Features another module on this host contributes to
            `nix.settings.system-features`, restated here because this module
            forces that list. Prefer referencing the contributing module's own
            option over literal strings, so the value cannot drift from it.
            Features added through `nix.settings.extra-system-features` are a
            separate nix.conf key and need no entry here.
          '';
        };
      };

      config.nix.settings.system-features = lib.mkForce (
        lib.unique (
          (if cfg.present then lib.unique (nixosDefault ++ [ "kvm" ]) else lib.remove "kvm" nixosDefault)
          ++ cfg.extraFeatures
        )
      );
    };
}
