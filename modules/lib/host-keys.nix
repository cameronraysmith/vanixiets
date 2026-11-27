# flake.lib.hostKeys: every fleet host's pinned SSH host key, the one source
# of modules/system/ssh-known-hosts.nix. The NixOS keys are the committed
# public files of clan's sshd `openssh` generator, read through
# flake.lib.vars untrimmed, exactly as clan's `.value` reads them (world
# assumptions A320, A321), so each ends in " \n"; the darwin keys are
# flake.lib.darwinHostKeys (modules/lib/darwin-host-keys.nix). No host's
# configuration is read to build it.
#
# The NixOS hosts are the flake.fleet.hosts entries whose class is nixos;
# deriving them from the vars tree instead would silently add any machine
# that gains an `openssh` directory.
#
# flake.lib.hostKeyObligations: each NixOS host asserts that its own
# generated public key equals its hostKeys entry, so a regenerated but
# uncommitted or moved key fails that host's build (the nixos-<host> check and
# any deploy) rather than drifting out of known_hosts. It reads only the
# host's own configuration. checks.x86_64-linux.host-key-obligations runs the
# judge over fixtures.
{ config, lib, ... }:
let
  inherit (config.flake.lib) vars darwinHostKeys;

  nixosKeyHosts = lib.attrNames (lib.filterAttrs (_: h: h.class == "nixos") config.flake.fleet.hosts);

  hostKeys =
    lib.genAttrs nixosKeyHosts (
      machine:
      vars.public {
        inherit machine;
        generator = "openssh";
        file = "ssh.id_ed25519.pub";
      }
    )
    // darwinHostKeys;

  hostKeyObligations.failures =
    name: hostConfig:
    let
      generators = hostConfig.clan.core.vars.generators or { };
      generated = generators.openssh.files."ssh.id_ed25519.pub".value or null;
    in
    lib.optional (hostKeys ? ${name} && generators ? openssh && generated != hostKeys.${name})
      "${name}'s generated openssh public key is not flake.lib.hostKeys.${name}; commit vars/per-machine/${name}/openssh/ssh.id_ed25519.pub";

  assertionsModule =
    { config, ... }:
    {
      assertions = map (message: {
        assertion = false;
        inherit message;
      }) (hostKeyObligations.failures config.clan.core.settings.machine.name config);
    };
in
{
  flake.lib = {
    inherit hostKeys hostKeyObligations;
  };
  flake.modules.nixos.base.imports = [ assertionsModule ];
}
