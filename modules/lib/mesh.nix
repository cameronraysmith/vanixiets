# Mesh addressing: every prefix and address is a pure function of a name.
# The prefix is a ULA /64 from sha256("tincr-" + instance); a member's address
# is that prefix plus the first 64 bits of sha256(name), each hextet kept as
# four hex digits so the invitation hook's shell slicing yields the same string.
{ config, ... }:
let
  sha256 = builtins.hashString "sha256";
  hextetsAt = hex: offsets: map (offset: builtins.substring offset 4 hex) offsets;

  networkOf =
    instance:
    let
      hash = sha256 "tincr-${instance}";
    in
    builtins.concatStringsSep ":" (
      [ "fd${builtins.substring 0 2 hash}" ]
      ++ hextetsAt hash [
        2
        6
        10
      ]
    );

  instance = config.flake.lib.fleet.label;
in
{
  flake.lib.mesh = {
    inherit instance;
    prefixOf = instance: "${networkOf instance}::/64";
    addressOf =
      instance: name:
      builtins.concatStringsSep ":" (
        [ (networkOf instance) ]
        ++ hextetsAt (sha256 name) [
          0
          4
          8
          12
        ]
      );
    port = 655;
    crypto = "default";
    resolvers = [
      "cinnabar"
      "magnetite"
    ];
    interface = {
      nixos = "tinc-${instance}";
      darwin = "utun10";
    };
  };
}
