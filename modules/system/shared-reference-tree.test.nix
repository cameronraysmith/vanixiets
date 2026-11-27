# nix-unit cases for flake.lib.sharedReferenceTreeTransportGaps
# (shared-reference-tree.nix), which the NixOS, darwin and darwin Omnigent
# assertions use to fail evaluation when a participant's git could use a
# transport beneath the shared root.
#
# The participant is a Home Manager configuration whose ghq-shared module
# declares both darwin forms of the root and the link <home>/ghq, its home
# /home/someone unless a case names another, with the two includes
# repository-acquisition.nix declares, and then one change each.
# An include whose condition can hold for a repository reached by a root form or
# by the link must set neither protocol.<name>.allow nor a protocol.allow other
# than never, in any case of the section and variable names and in every shape
# Home Manager writes; an include given only as a path, and one under a
# directory that neither encloses nor lies beneath any of those paths, in any
# letter case of either, are not judged. The settings are read as one attribute
# set, as a list of them, and as programs.git.iniContent; a configuration with
# no programs.git lacks every include it must have.
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
            participant =
              {
                includes ? [ ],
                settings ? { },
                iniContent ? { },
                declared ? refusing,
                homeDirectory ? "/home/someone",
                link ? "''${homeDirectory}/ghq",
              }:
              gaps roots {
                home = { inherit homeDirectory; };
                programs.ghq-shared = {
                  forms = roots;
                  inherit link;
                };
                programs.git = {
                  includes = declared ++ includes;
                  inherit settings iniContent;
                };
              };
            under = condition: contents: { includes = [ { inherit condition contents; } ]; };
            onDarwin = args: { homeDirectory = "/Users/crs58"; } // args;
            file = { protocol.file.allow = "always"; };
            https = { protocol.https.allow = "always"; };
          in
          {
            testDeclared = {
              expr = participant { };
              expected = [ ];
            };
            testSettingsNamedKey = {
              expr = participant { settings = https; };
              expected = [ "a settings entry sets protocol.https.allow" ];
            };
            testSettingsAllowAlways = {
              expr = participant { settings.protocol.allow = "always"; };
              expected = [ ];
            };
            testSettingsSectionCase = {
              expr = participant { settings.Protocol.https.allow = "always"; };
              expected = [ "a settings entry sets protocol.https.allow" ];
            };
            testSettingsList = {
              expr = participant { settings = [ { core.editor = "vi"; } https ]; };
              expected = [ "a settings entry sets protocol.https.allow" ];
            };
            testIniContent = {
              expr = participant { iniContent.protocol.file.allow = "always"; };
              expected = [ "a settings entry sets protocol.file.allow" ];
            };
            testUnconditionalIncludeNamedKey = {
              expr = participant { includes = [ { contents = https; } ]; };
              expected = [ "include 3 (unconditional) sets protocol.https.allow" ];
            };
            testSecondIncludeUnderRoot = {
              expr = participant (under "gitdir:/var/lib/ghq/" https);
              expected = [ "include 3 (gitdir:/var/lib/ghq/) sets protocol.https.allow" ];
            };
            testBroaderGitdirAllowAlways = {
              expr = participant (under "gitdir:/var/" { protocol.allow = "always"; });
              expected = [ "include 3 (gitdir:/var/) sets protocol.allow to always" ];
            };
            testNarrowerGitdirNamedKey = {
              expr = participant (under "gitdir/i:/PRIVATE/var/lib/ghq/github.com/" { protocol.file.allow = "always"; });
              expected = [ "include 3 (gitdir/i:/PRIVATE/var/lib/ghq/github.com/) sets protocol.file.allow" ];
            };
            testGlobGitdirNamedKey = {
              expr = participant (under "gitdir:**/ghq/" { protocol.file.allow = "always"; });
              expected = [ "include 3 (gitdir:**/ghq/) sets protocol.file.allow" ];
            };
            testLinkGitdir = {
              expr = participant (under "gitdir:/home/someone/ghq/" { protocol.file.allow = "always"; });
              expected = [ "include 3 (gitdir:/home/someone/ghq/) sets protocol.file.allow" ];
            };
            testHomeGitdir = {
              expr = participant (under "gitdir:/home/someone/" { protocol.file.allow = "always"; });
              expected = [ "include 3 (gitdir:/home/someone/) sets protocol.file.allow" ];
            };
            testTildeGitdir = {
              expr = participant (under "gitdir:~/" { protocol.file.allow = "always"; });
              expected = [ "include 3 (gitdir:~/) sets protocol.file.allow" ];
            };
            testUnrelatedGitdir = {
              expr = participant (under "gitdir:/home/someone/projects/" https);
              expected = [ ];
            };
            testUnrelatedTildeGitdir = {
              expr = participant (under "gitdir:~/projects/" https);
              expected = [ ];
            };
            testCaseLinkGitdir = {
              expr = participant (onDarwin (under "gitdir:/Users/crs58/GHQ/" file));
              expected = [ "include 3 (gitdir:/Users/crs58/GHQ/) sets protocol.file.allow" ];
            };
            testCaseHomeGitdir = {
              expr = participant (onDarwin (under "gitdir:/USERS/crs58/" file));
              expected = [ "include 3 (gitdir:/USERS/crs58/) sets protocol.file.allow" ];
            };
            testCaseRootGitdir = {
              expr = participant (under "gitdir:/private/VAR/lib/ghq/" file);
              expected = [ "include 3 (gitdir:/private/VAR/lib/ghq/) sets protocol.file.allow" ];
            };
            testCaseTildeGitdir = {
              expr = participant (onDarwin (under "gitdir:~/GHQ/" file));
              expected = [ "include 3 (gitdir:~/GHQ/) sets protocol.file.allow" ];
            };
            testHomeDirectoryCase = {
              expr = participant ({ homeDirectory = "/Users/CRS58"; } // under "gitdir:/Users/crs58/" file);
              expected = [ "include 3 (gitdir:/Users/crs58/) sets protocol.file.allow" ];
            };
            testLinkCase = {
              expr = participant (onDarwin { link = "/Users/crs58/GHQ"; } // under "gitdir:/Users/crs58/ghq/" file);
              expected = [ "include 3 (gitdir:/Users/crs58/ghq/) sets protocol.file.allow" ];
            };
            testCaseUnrelatedGitdir = {
              expr = participant (onDarwin (under "gitdir:/USERS/crs58/Projects/" https));
              expected = [ ];
            };
            testIncludeSectionCase = {
              expr = participant { includes = [ { contents.Protocol.https.allow = "always"; } ]; };
              expected = [ "include 3 (unconditional) sets protocol.https.allow" ];
            };
            testIncludeVariableCase = {
              expr = participant { includes = [ { contents.PROTOCOL.Allow = "always"; } ]; };
              expected = [ "include 3 (unconditional) sets protocol.allow to always" ];
            };
            testIncludeDottedSection = {
              expr = participant { includes = [ { contents."protocol.https".allow = "always"; } ]; };
              expected = [ "include 3 (unconditional) sets protocol.https.allow" ];
            };
            testIncludeQuotedSection = {
              expr = participant { includes = [ { contents."protocol \"https\"".allow = "always"; } ]; };
              expected = [ "include 3 (unconditional) sets protocol.https.allow" ];
            };
            testIncludeUnreadable = {
              expr = participant { includes = [ { contents.protocol = "always"; } ]; };
              expected = [ "include 3 (unconditional) sets protocol, which this check cannot read as a git setting" ];
            };
            testPathInclude = {
              expr = participant { includes = [ { path = "/etc/some.inc"; } ]; };
              expected = [ ];
            };
            testMissingForm = {
              expr = participant { declared = lib.take 1 refusing; };
              expected = [ "no include under gitdir:/private/var/lib/ghq/ sets protocol.allow to never" ];
            };
            testNoGit = {
              expr = gaps roots {
                home.homeDirectory = "/home/someone";
                programs = { };
              };
              expected = map (form: "no include under gitdir:''${form}/ sets protocol.allow to never") roots;
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
