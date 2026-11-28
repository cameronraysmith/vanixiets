# flake.lib.sourceContextObligations: no sops file and no home-manager file
# source may name the flake's own source tree.
#
# `inputs.self + "/some/file"` is a string whose context is the whole flake
# source, so every derivation built from it, and every host carrying one,
# changes on every commit, including commits that change no file any
# configuration reads. A path literal (`./some/file`) or `builtins.path` copies
# only that file and stays stable across unrelated commits.
#
# The obligation is a module assertion: on every NixOS and darwin host, over
# the host's own sops options and those of each home-manager user it embeds;
# and on every standalone home built by flake.lib.mkHome and on the darwin
# omnigent worker homes. The nixos-<host>, darwin-<host> and home-manager-<user>
# checks, which evaluate each toplevel, fail on it, and so does a deploy. It
# reads values the toplevel already forces, adding no evaluation.
#
# It covers the consumer classes that have carried the source into a closure:
# sops.defaultSopsFile, sops.secrets.<n>.sopsFile, and home.file,
# xdg.configFile and xdg.dataFile sources. It is not a proof that nothing else
# does; two commits that differ in an unread file yielding identical toplevel
# drvPaths is the end-to-end evidence.
{ self, lib, ... }:
let
  source = builtins.unsafeDiscardStringContext self.outPath;

  carriesSource =
    value:
    let
      forced = builtins.tryEval value;
    in
    forced.success
    && builtins.isString forced.value
    && builtins.hasContext forced.value
    && builtins.getContext forced.value ? ${source};

  candidates =
    cfg:
    let
      sops = cfg.sops or { };
      files =
        option:
        lib.mapAttrsToList (name: file: {
          path = "${option}.${lib.strings.escapeNixIdentifier name}.source";
          value = file.source;
        }) (lib.attrByPath (lib.splitString "." option) { } cfg);
    in
    lib.optional (sops ? defaultSopsFile) {
      path = "sops.defaultSopsFile";
      value = sops.defaultSopsFile;
    }
    ++ lib.mapAttrsToList (name: secret: {
      path = "sops.secrets.${lib.strings.escapeNixIdentifier name}.sopsFile";
      value = secret.sopsFile;
    }) (sops.secrets or { })
    ++ lib.concatMap files [
      "home.file"
      "xdg.configFile"
      "xdg.dataFile"
    ];

  # `scope` prefixes each option path, e.g. "home-manager.users.cameron.".
  failures =
    scope: cfg:
    map (
      c:
      "${scope}${c.path} names the flake source (${source}) in its string context, so it changes on every commit; reference the file by path literal or builtins.path, not inputs.self"
    ) (lib.filter (c: carriesSource c.value) (candidates cfg));

  toAssertions = map (message: {
    assertion = false;
    inherit message;
  });

  hostModule =
    { config, ... }:
    {
      assertions = toAssertions (
        failures "" config
        ++ lib.concatLists (
          lib.mapAttrsToList (
            user: home: failures "home-manager.users.${lib.strings.escapeNixIdentifier user}." home
          ) (config.home-manager.users or { })
        )
      );
    };

  homeModule =
    { config, ... }:
    {
      assertions = toAssertions (failures "" config);
    };
in
{
  flake.lib.sourceContextObligations = {
    inherit failures homeModule;
  };
  flake.modules.nixos.base-source-context-obligations.imports = [ hostModule ];
  flake.modules.darwin.base.imports = [ hostModule ];
}
