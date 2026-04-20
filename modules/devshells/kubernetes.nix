{
  perSystem =
    { pkgs, ... }:
    {
      # Minimal shell for kubernetes CI (k3d integration tests)
      devShells.kubernetes = pkgs.mkShell {
        packages = [
          pkgs.git
          pkgs.just
          pkgs.k3d
          pkgs.ctlptl
          pkgs.kubectl
          pkgs.kluctl
          pkgs.sops
          pkgs.age
          pkgs.rsync
          pkgs.kyverno-chainsaw
        ];

        passthru.meta.description = "Minimal environment for k3d integration tests";
      };
    };
}
