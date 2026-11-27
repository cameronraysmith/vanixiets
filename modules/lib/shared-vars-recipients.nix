# flake.lib.sharedVarsObligations: every shared clan var a host's
# configuration deploys as a secret must list that host as a recipient under
# vars/shared/<generator>/<file>/machines/<host>. A host deploying a shared
# secret it cannot decrypt activates halfway: sops-install-secrets fails
# ("0 successful groups required, got 0") after the new generation is linked,
# as rosegold did at main cd1ab0e when it entered the otel-collector role
# without being a recipient of the shared ntfy-alerter token (CAM-113 F58).
#
# The obligation is a module assertion on every NixOS and darwin host, so the
# nixos-<host> and darwin-<host> checks, which build each toplevel, fail on
# it, and so does a deploy, before anything is activated. It reads the secret
# backend's generator tree and the committed vars tree, adding no evaluation.
# checks.x86_64-linux.shared-vars-obligations runs the judge over fixtures.
# This lives beside the machine configurations rather than in
# sops-correspondence, which judges the legacy sops tree's public keys and
# evaluates no host.
{ self, lib, ... }:
let
  # Each deployed secret file of a shared generator, as "<generator>/<file>",
  # for which `isRecipient` is false.
  missing =
    { generators, isRecipient }:
    lib.concatLists (
      lib.mapAttrsToList (
        gen: g:
        lib.optionals (g.share or false) (
          lib.concatMap (
            file:
            let
              f = g.files.${file};
            in
            lib.optional ((f.secret or true) && (f.deploy or true) && !(isRecipient gen file)) "${gen}/${file}"
          ) (builtins.attrNames (g.files or { }))
        )
      ) generators
    );

  sharedVarsObligations = {
    inherit missing;
    failures =
      name: hostConfig:
      map
        (
          v:
          let
            parts = lib.splitString "/" v;
          in
          "${name} deploys shared secret ${v} but is not under ${
            self.lib.vars.relPath {
              generator = lib.head parts;
              file = lib.concatStringsSep "/" (lib.tail parts);
            }
          }/machines"
        )
        (missing {
          generators = self.lib.secretsBackend.generatorsOf hostConfig;
          isRecipient =
            gen: file:
            self.lib.vars.isRecipient {
              generator = gen;
              inherit file;
            } { machine = name; };
        });
  };

  assertionsModule =
    { config, ... }:
    {
      assertions = map (message: {
        assertion = false;
        inherit message;
      }) (sharedVarsObligations.failures config.clan.core.settings.machine.name config);
    };
in
{
  flake.lib = {
    inherit sharedVarsObligations;
  };
  flake.modules.nixos.base.imports = [ assertionsModule ];
  flake.modules.darwin.base.imports = [ assertionsModule ];
}
