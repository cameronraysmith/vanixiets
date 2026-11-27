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
# With modules/system/secrets.nix (a host's generators, through
# `vanixiets.secrets`) this file is the secret seam. Outside the two, only
# the files in the `expected` list of
# modules/checks/secrets-seam-confinement.nix spell clan vars or the committed
# layout, each for the reason given there.
#
# Exempt from the committed-layout clause, deliberately: the independent
# judge in modules/checks/sops-correspondence.nix, the literal fixtures of
# modules/checks/fleet-deployer-obligations.nix,
# modules/home/ai/omnigent/credentials.nix (it builds the committed
# ciphertext's path from the backend's rel_dir on purpose, to check what
# sops-nix installs) and modules/checks/langfuse-query.nix (encrypted files
# interpolated on purpose). modules/checks/commit-signing-key.nix spells a
# delivered key path (/run/secrets/vars/shared/…) in a fixture home, not the
# committed layout.
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
