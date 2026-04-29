# Join Zerotier network and calculate deterministic IPv6 address.
# Network ID lives in a let-binding so it can be inlined into help output;
# preamble exports NETWORK_ID for the sidecar to consume.
{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "zerotier-join";
          runtimeInputs = [ ];
          text = ''
            export NETWORK_ID=db4344343b14b903
            ${builtins.readFile ./zerotier-join.sh}
          '';
          meta.description = "Join Zerotier network and report calculated IPv6 address";
        })
      ];
    };
}
