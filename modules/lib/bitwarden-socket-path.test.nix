# nix-unit invariants for flake.lib.bitwardenSocketPath
# (modules/lib/bitwarden-socket-path.nix).
#
# Pure two-branch function returning a platform-specific path string.
# The Darwin branch encodes a vendor-imposed sandbox path that is not
# discoverable from the surrounding code; a silent flip would produce a
# functional-looking but never-connecting SSH agent socket.
{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks.eval-bitwarden-socket-path = config.flake.lib.mkEvalCheck pkgs {
        name = "bitwarden-socket-path";
        testFile = pkgs.writeText "bitwarden-socket-path.tests.nix" ''
          let
            bitwardenSocketPath =
              (import ${./bitwarden-socket-path.nix} { }).flake.lib.bitwardenSocketPath;
          in
          {
            testDarwinUsesContainerSandboxPath = {
              expr = bitwardenSocketPath {
                homeDirectory = "/Users/example";
                isDarwin = true;
              };
              expected = "/Users/example/Library/Containers/com.bitwarden.desktop/Data/.bitwarden-ssh-agent.sock";
            };

            testLinuxUsesHomeRootPath = {
              expr = bitwardenSocketPath {
                homeDirectory = "/home/example";
                isDarwin = false;
              };
              expected = "/home/example/.bitwarden-ssh-agent.sock";
            };
          }
        '';
      };
    };
}
