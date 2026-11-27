# nix-unit cases for flake.lib.sharedReferenceTreeTransportGaps
# (shared-reference-tree.nix), which the NixOS, darwin and darwin Omnigent
# assertions use to fail evaluation when a participant's git could use a
# transport beneath the shared root.
#
# The participant is given the two includes repository-acquisition.nix declares
# on darwin, one per root form, and then one change each. An include whose
# condition can hold beneath the root must set neither protocol.<name>.allow nor
# a protocol.allow other than never; an include given only as a path, and one
# under a directory that neither encloses the root nor lies beneath it, are not
# judged.
{ config, ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    let
      check = config.flake.lib.mkEvalCheck pkgs {
        name = "shared-reference-tree";
        testFile = pkgs.writeText "shared-reference-tree.tests.nix" ''
          let
            lib = import ${pkgs.path}/lib;
            gaps = (import ${./shared-reference-tree.nix} { inherit lib; }).flake.lib.sharedReferenceTreeTransportGaps;
            roots = [ "/var/lib/ghq" "/private/var/lib/ghq" ];
            refusing = map (form: {
              condition = "gitdir:''${form}/";
              contents = {
                filter.lfs.required = false;
                protocol.allow = "never";
              };
            }) roots;
            with' = includes: settings: gaps roots { includes = refusing ++ includes; inherit settings; };
          in
          {
            testDeclared = {
              expr = with' [ ] { };
              expected = [ ];
            };
            testSettingsNamedKey = {
              expr = with' [ ] { protocol.https.allow = "always"; };
              expected = [ "its settings set protocol.https.allow" ];
            };
            testSettingsAllowAlways = {
              expr = with' [ ] { protocol.allow = "always"; };
              expected = [ ];
            };
            testUnconditionalIncludeNamedKey = {
              expr = with' [ { contents.protocol.https.allow = "always"; } ] { };
              expected = [ "include 3 (unconditional) sets protocol.https.allow" ];
            };
            testSecondIncludeUnderRoot = {
              expr = with' [
                {
                  condition = "gitdir:/var/lib/ghq/";
                  contents.protocol.https.allow = "always";
                }
              ] { };
              expected = [ "include 3 (gitdir:/var/lib/ghq/) sets protocol.https.allow" ];
            };
            testBroaderGitdirAllowAlways = {
              expr = with' [
                {
                  condition = "gitdir:/var/";
                  contents.protocol.allow = "always";
                }
              ] { };
              expected = [ "include 3 (gitdir:/var/) sets protocol.allow to always" ];
            };
            testNarrowerGitdirNamedKey = {
              expr = with' [
                {
                  condition = "gitdir/i:/PRIVATE/var/lib/ghq/github.com/";
                  contents.protocol.file.allow = "always";
                }
              ] { };
              expected = [ "include 3 (gitdir/i:/PRIVATE/var/lib/ghq/github.com/) sets protocol.file.allow" ];
            };
            testGlobGitdirNamedKey = {
              expr = with' [
                {
                  condition = "gitdir:**/ghq/";
                  contents.protocol.file.allow = "always";
                }
              ] { };
              expected = [ "include 3 (gitdir:**/ghq/) sets protocol.file.allow" ];
            };
            testUnrelatedGitdir = {
              expr = with' [
                {
                  condition = "gitdir:/Users/someone/projects/";
                  contents.protocol.https.allow = "always";
                }
              ] { };
              expected = [ ];
            };
            testPathInclude = {
              expr = with' [ { path = "/etc/some.inc"; } ] { };
              expected = [ ];
            };
            testMissingForm = {
              expr = gaps roots {
                includes = lib.take 1 refusing;
                settings = { };
              };
              expected = [ "no include under gitdir:/private/var/lib/ghq/ sets protocol.allow to never" ];
            };
          }
        '';
      };
    in
    {
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # not yet run on nixbot
        eval-shared-reference-tree = {
          class = "medium";
          measured = false;
        };
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") { eval-shared-reference-tree = check; };
    };
}
