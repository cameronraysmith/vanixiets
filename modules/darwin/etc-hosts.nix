# /etc/hosts entries on darwin, the nix-darwin counterpart of NixOS's
# `networking.hosts`.
#
# nix-darwin at our pin (ff0e21a4) declares no hosts option and leaves
# /etc/hosts to macOS: its networking activation only moves a leftover
# /etc/hosts.before-nix-darwin back (modules/networking/default.nix:205-208).
# A symlink into /etc/static, which `environment.etc.hosts` would make, is
# also the wrong shape: mDNSResponder watches the file it opened, and
# activation changes only where /etc/static points, so no event reaches it.
#
# `vanixiets.hosts` therefore maps an address to its names with the type of
# NixOS's option, and activation splices those lines into the real
# /etc/hosts between marker lines (flake.lib.etcHostsSplice), the way
# krebs/kartei keeps retiolum's names on Macs (modules/retiolum/darwin.nix at
# 06e8a4e). Lines outside the markers are never touched; an empty set removes
# the block. It runs at the end of nix-darwin's networking activation, after
# that restore.
{ config, ... }:
let
  inherit (config.flake.lib) etcHostsSplice;
in
{
  flake.modules.darwin.base-etc-hosts =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      entries = lib.filterAttrs (_: names: names != [ ]) config.vanixiets.hosts;
      block = pkgs.writeText "etc-hosts-block" (
        lib.concatStrings (
          lib.mapAttrsToList (address: names: "${address} ${lib.concatStringsSep " " names}\n") entries
        )
      );
    in
    {
      options.vanixiets.hosts = lib.mkOption {
        type = lib.types.attrsOf (lib.types.listOf lib.types.str);
        default = { };
        example = {
          "fd09:836d:82f8:3d7d:6e96:5884:ed58:9f7e" = [ "cinnabar.vanixiets.internal" ];
        };
        description = ''
          Addresses and the names /etc/hosts maps to each, kept in a marked
          block of /etc/hosts on activation; lines outside the block are left
          alone, and an empty set removes the block.
        '';
      };

      config.system.activationScripts.networking.text = lib.mkAfter ''
        echo "updating the vanixiets block of /etc/hosts..." >&2
        ${lib.getExe (etcHostsSplice pkgs)} /private/etc/hosts ${block} \
          || echo "warning: /etc/hosts was left unchanged" >&2
      '';
    };
}
