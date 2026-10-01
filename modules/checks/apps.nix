# Realization check for every flake app on the current system.
#
# `nix flake check` evaluates apps, but nixbot builds only checks.<system>, so
# an app that fails to evaluate reaches main without any check going red. That
# happened: an app referenced a pkgs/by-name package through the perSystem
# `pkgs`, which does not carry flake.overlays.default, and the first sandbox
# build was where it surfaced.
#
# One derivation rather than one per app: the programs are the whole content, so
# a per-app split would multiply derivations without isolating anything a
# failing build message does not already name.
{ ... }:
{
  perSystem =
    { self', pkgs, ... }:
    {
      # Referencing each program in the environment puts it in this derivation's
      # build closure, so evaluating the check forces every app's expression and
      # building it realizes every app's program.
      checks.apps-build =
        pkgs.runCommand "apps-build"
          {
            # The k8s-deploy-* programs need import-from-derivation to evaluate;
            # IFD-free reintroduction is part of the cryolite programme.
            programs = builtins.attrValues (
              builtins.mapAttrs (_: app: app.program) (
                removeAttrs self'.apps [
                  "k8s-deploy-local"
                  "k8s-deploy-local-k3d"
                  "k8s-deploy-local-k3d-foundation"
                  "k8s-deploy-local-k3d-infrastructure"
                ]
              )
            );
            passthru.meta.description = "Every flake app on this system evaluates and its program realizes";
          }
          ''
            status=0
            for program in $programs; do
              if [ ! -x "$program" ]; then
                printf 'app program is not executable: %s\n' "$program" >&2
                status=1
              fi
            done
            if [ "$status" -ne 0 ]; then
              exit 1
            fi
            printf '%s\n' $programs > "$out"
          '';
    };
}
