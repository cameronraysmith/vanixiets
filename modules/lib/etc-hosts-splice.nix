# flake.lib.etcHostsSplice pkgs: the `etc-hosts-splice <hosts file> <block
# file>` command that modules/darwin/etc-hosts.nix runs on activation to keep
# a generated block in /etc/hosts. The behaviour and its marker lines live in
# etc-hosts-splice.sh; checks.x86_64-linux.etc-hosts-splice runs it against
# fixture files.
{ ... }:
{
  flake.lib.etcHostsSplice =
    pkgs:
    pkgs.writeShellApplication {
      name = "etc-hosts-splice";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.diffutils
        pkgs.gawk
      ];
      text = builtins.readFile ./etc-hosts-splice.sh;
    };
}
