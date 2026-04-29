# Home-manager activationPackage build-realization checks.
#
# Wires each homeConfigurations."<user>@<system>" activationPackage as a flake
# check, closing the silently-no-op build gap reported in bead nix-144.4. The
# activationPackage is the already-built derivation that `home-manager switch`
# activates, so binding it as a check following ironstar's package-as-check
# idiom (modules/rust.nix:249-251) exercises the full home closure per system.
#
# Systems: aarch64-darwin, aarch64-linux, x86_64-linux
# Users: crs58, raquel
#
# Closes: nix-144.4
{ self, lib, ... }:
{
  perSystem =
    { system, ... }:
    let
      users = [
        "crs58"
        "raquel"
      ];
    in
    {
      checks = lib.listToAttrs (
        map (user: {
          name = "vanixiets-home-${user}";
          value = self.homeConfigurations."${user}@${system}".activationPackage;
        }) users
      );
    };
}
