{
  description = "claude-sandbox probe v1: measures the cloud sandbox from inside its setup script";

  # Only channels.nixos.org: github: inputs are refused by the sandbox's GitHub gate.
  inputs.nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";

  outputs =
    { self, nixpkgs }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      probe = pkgs.writeShellApplication {
        name = "claude-sandbox-probe";
        runtimeInputs = [ pkgs.coreutils ];
        text = builtins.readFile ./probe.sh;
      };
    in
    {
      packages.x86_64-linux.default = probe;
      apps.x86_64-linux.default = {
        type = "app";
        program = "${probe}/bin/claude-sandbox-probe";
      };
    };
}
