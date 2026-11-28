# Where each aspect and part is defined is read by evaluation: the _file of
# each definition in the flake's modules output, which the deferred-module
# merge sets to "<file>, via option <loc>". Files are named relative to this
# flake's source; a file outside it keeps its absolute path, so it is never
# an aspect's list file or a part's one file and is reported.
{ self, lib, ... }:
let
  aspects = [
    {
      class = "nixos";
      aspect = "base";
      prefix = "base-";
      file = "modules/nixos/base.nix";
      parts = self.lib.nixosBaseParts;
      exempt = [ ];
    }
  ];
  # Parts stated in several files on purpose, with exactly those files.
  multiFile = { };
  sourcePrefix = toString self + "/";
  # The files an aspect or part is defined in, each once: a file whose
  # definition is a lib.mkMerge still counts as one file.
  definitionFiles =
    m:
    lib.unique (
      lib.sort lib.lessThan (
        map (d: lib.removePrefix sourcePrefix (builtins.head (lib.splitString ", via option" d._file)))
          (builtins.head (m { }).imports).imports
      )
    );
  violations =
    {
      class,
      aspect,
      prefix,
      file,
      parts,
      exempt,
    }:
    let
      foreign = builtins.filter (f: f != file) (definitionFiles self.modules.${class}.${aspect});
      partSites = lib.concatMap (
        n:
        let
          got = definitionFiles self.modules.${class}.${n};
          want = multiFile.${class}.${n} or null;
        in
        if !(self.modules.${class} ? ${n}) then
          [ "${class}.${n}: listed but defined nowhere" ]
        else if want != null then
          lib.optional (
            got != lib.sort lib.lessThan want
          ) "${class}.${n}: defined in ${toString got}, not exactly ${toString want}"
        else
          lib.optional (builtins.length got != 1) "${class}.${n}: defined in ${toString got}, not one file"
      ) parts;
      unlisted = builtins.filter (
        n: lib.hasPrefix prefix n && !(builtins.elem n parts) && !(builtins.elem n exempt)
      ) (builtins.attrNames self.modules.${class});
    in
    map (f: "${class}.${aspect}: defined in ${f}, not only in ${file}") foreign
    ++ partSites
    ++ map (n: "${class}.${n}: in no ${aspect} list") unlisted;
in
{
  perSystem =
    { pkgs, system, ... }:
    {
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        structure-aspect-parts = {
          class = "small";
          measured = false;
        };
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        structure-aspect-parts = self.lib.mkStructuralCheck pkgs {
          name = "aspect-parts";
          actual = lib.concatMap violations aspects;
          expected = [ ];
        };
      };
    };
}
