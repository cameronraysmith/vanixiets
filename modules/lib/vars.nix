# flake.lib.vars: the one reading of clan's committed vars layout (clan-core
# nixosModules/clanCore/vars/public/in_repo.nix:14-21; world assumption A320).
# A public file's value is the untrimmed contents of <relPath>/value; a
# secret's encrypted contents are <relPath>/secret, and its recipients are
# <relPath>/{machines,groups,users}/<name>. A generator's files sit under
# vars/shared/ when it is shared and vars/per-machine/<machine>/ otherwise.
#
# `path` returns a path value at the repository root, so interpolating it
# copies one file to the store, as the path literals it replaces did; a
# "${self}/…" string would refer into the whole flake source instead. Callers
# keep their own read primitive (readFile, fileContents, trim, hashFile,
# readDir) and their path-or-string kind.
#
# Exempt, deliberately: the independent judge in
# modules/checks/sops-correspondence.nix, the literal fixtures of
# modules/checks/fleet-deployer-obligations.nix,
# modules/home/ai/omnigent/credentials.nix (clan's rel_dir) and
# modules/checks/langfuse-query.nix (encrypted files interpolated on purpose).
{ lib, ... }:
let
  relPath =
    {
      generator,
      file,
      machine ? null,
    }:
    if machine == null then
      "vars/shared/${generator}/${file}"
    else
      "vars/per-machine/${machine}/${generator}/${file}";

  path = args: ../.. + "/${relPath args}";

  public = args: builtins.readFile (path args + "/value");

  exists =
    {
      secret ? true,
      ...
    }@args:
    builtins.pathExists (
      path (removeAttrs args [ "secret" ]) + (if secret then "/secret" else "/value")
    );

  isRecipient =
    args:
    {
      machine ? null,
      group ? null,
      user ? null,
    }:
    let
      named = lib.filter (s: s.name != null) [
        {
          dir = "machines";
          name = machine;
        }
        {
          dir = "groups";
          name = group;
        }
        {
          dir = "users";
          name = user;
        }
      ];
      sub = lib.head named;
    in
    assert lib.assertMsg (
      lib.length named == 1
    ) "flake.lib.vars.isRecipient: name exactly one of machine, group, user";
    builtins.pathExists (path args + "/${sub.dir}/${sub.name}");
in
{
  flake.lib.vars = {
    inherit
      relPath
      path
      public
      exists
      isRecipient
      ;
  };
}
