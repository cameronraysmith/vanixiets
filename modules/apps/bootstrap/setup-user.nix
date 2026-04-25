# Flake app: generate the user's age key for sops-nix secrets (first-time user setup; idempotent on re-run).
#
# Idempotent: if ~/.config/sops/age/keys.txt exists, re-prints the public key and exits 0 without regenerating.
{ ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      apps.setup-user = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "setup-user";
            runtimeInputs = [
              pkgs.coreutils
              # `age` provides age-keygen directly, avoiding a nested
              # `nix shell nixpkgs#age` invocation (cleaner dependency
              # closure than the Makefile's approach).
              pkgs.age
            ];
            text = builtins.readFile ./setup-user.sh;
          }
        );
      };
    };
}
