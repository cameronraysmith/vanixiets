# exportAs: one module exported under several flake.modules names with one
# identity (compose-hosts-from-cohesive-aspects design D7).
#
# flake-parts gives a flake.modules value no `key` (extras/modules.nix,
# "TODO: set key?"), so the module system keys an unkeyed import by the path
# it was reached on, and one value imported from two parents, say from the
# `terminal` aggregate and directly as `jq`, is applied twice. exportAs keys
# the module `vanixiets/<key>`, which makes the module system apply it once
# however many of its names a configuration imports.
#
#   flake.modules.homeManager = config.flake.lib.exportAs {
#     key = "jq";
#     names = [ "terminal" "jq" ];
#     module = { ... }: { programs.jq.enable = true; };
#   };
#
# The key is added to the module itself, not by wrapping it in a parent
# `{ key; imports = [ module ]; }`: the module system collects imports
# breadth first (builtins.genericClosure in nixpkgs lib/modules.nix
# filterModules), so one more level of nesting would move the module's
# definitions behind those of its new cousins and reorder every list option
# it extends. A function module is therefore wrapped in a function with the
# same arguments whose result carries the key, which the module system reads
# from the applied module as it does from an attrset module. A parameterised
# module's key carries its parameter, `<name>?<param>=<value>`
# (`git?full=true`), so two parameter values stay two modules.
{ lib, ... }:
{
  flake.lib.exportAs =
    {
      key,
      names,
      module,
    }:
    let
      withKey = m: m // { key = "vanixiets/${key}"; };
      keyed =
        if lib.isFunction module then
          lib.setFunctionArgs (args: withKey (module args)) (lib.functionArgs module)
        else
          withKey module;
    in
    lib.genAttrs names (_: keyed);
}
