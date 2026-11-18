# nix-unit cases for guard.nix over manifest texts; wired by modules/checks/apm-guard.nix.
{ lib }:
let
  guardFor =
    manifests:
    import ./guard.nix { inherit lib; } {
      apmVersion = "0.36.0";
      inherit manifests;
    };
  sha = "22f0b463e7a5e579904dd6211a520321035526f7";
  sha2 = "b36e0829c6d0140e93cfef2ca599b1b07d4a7797";
  wrap =
    body:
    "name: p\nversion: 0.0.0\ndependencies:\n  apm:\n${body}  mcp: []\ndevDependencies:\n  apm:\n    - x/y#main\n";
  digestOf = body: (guardFor { p = wrap body; }).digest;
in
{
  testStringAndObjectForms = {
    expr =
      map
        (d: {
          inherit (d)
            plugin
            repo
            path
            ref
            ;
        })
        (guardFor {
          p = wrap (
            "    # comment\n"
            + "\n"
            + "    - obra/superpowers/skills/brainstorming#${sha}  # trailing\n"
            + "    - git: srid/agency\n"
            + "      path: .apm/skills/hickey\n"
            + "      ref: ${sha}\n"
            + "    - ./local\n"
            + "    - ../sibling\n"
            + "    - theclaymethod/unslop#${sha}\n"
          );
        }).remoteDeps;
    expected = [
      {
        plugin = "p";
        repo = "obra/superpowers";
        path = "skills/brainstorming";
        ref = sha;
      }
      {
        plugin = "p";
        repo = "srid/agency";
        path = ".apm/skills/hickey";
        ref = sha;
      }
      {
        plugin = "p";
        repo = "theclaymethod/unslop";
        path = null;
        ref = sha;
      }
    ];
  };

  testObjectFormKeepsOtherKeys = {
    expr =
      map (d: d.skills)
        (guardFor {
          p = wrap "    - git: a/b\n      ref: ${sha}\n      skills: [x, y]\n";
        }).remoteDeps;
    expected = [ "[x, y]" ];
  };

  testRefsByRepo = {
    expr =
      (guardFor {
        p = wrap "    - a/b#${sha2}\n    - a/b/sub#${sha}\n    - c/d#${sha}\n";
        q = wrap "    - a/b#${sha}\n";
      }).refsByRepo;
    expected = {
      "a/b" = [
        sha
        sha2
      ];
      "c/d" = [ sha ];
    };
  };

  testBranchRefThrows = {
    expr = digestOf "    - theclaymethod/unslop#main\n";
    expectedError = {
      type = "ThrownError";
      msg = "p/apm\\.yml: remote dep 'theclaymethod/unslop' ref 'main' is not a full 40-char commit SHA";
    };
  };

  testShortShaThrows = {
    expr = digestOf "    - git: a/b\n      ref: 22f0b46\n";
    expectedError = {
      type = "ThrownError";
      msg = "p/apm\\.yml: remote dep 'a/b' ref '22f0b46' is not a full 40-char commit SHA";
    };
  };

  testFlowMappingThrows = {
    expr = digestOf "    - {git: a/b, ref: ${sha}}\n";
    expectedError = {
      type = "ThrownError";
      msg = "p/apm\\.yml: unrecognised dependencies\\.apm line: '    - \\{git: a/b";
    };
  };

  testQuotedValueThrows = {
    expr = digestOf "    - \"a/b#${sha}\"\n";
    expectedError = {
      type = "ThrownError";
      msg = "p/apm\\.yml: unrecognised dependencies\\.apm line: '    - \"a/b#";
    };
  };

  testMixedSuperpowersRefsThrow = {
    expr = digestOf "    - obra/superpowers/skills/a#${sha}\n    - obra/superpowers/skills/b#${sha2}\n";
    expectedError = {
      type = "ThrownError";
      msg = "p/apm\\.yml: 'obra/superpowers' has more than one ref";
    };
  };

  testMixedRefsAcrossManifestsThrow = {
    expr =
      (guardFor {
        p = wrap "    - srid/agency/.apm/skills/a#${sha}\n";
        q = wrap "    - srid/agency/.apm/skills/b#${sha2}\n";
      }).digest;
    expectedError = {
      type = "ThrownError";
      msg = "'srid/agency' has more than one ref";
    };
  };

  testWholeSuperpowersThrows = {
    expr = digestOf "    - obra/superpowers#${sha}\n";
    expectedError = {
      type = "ThrownError";
      msg = "p/apm\\.yml: 'obra/superpowers' must be declared per skill-directory path";
    };
  };

  testAgencyPathShapeThrows = {
    expr = digestOf "    - srid/agency/skills/hickey#${sha}\n";
    expectedError = {
      type = "ThrownError";
      msg = "p/apm\\.yml: 'srid/agency/skills/hickey' is not exactly one skill directory";
    };
  };

  testCommentsAndOrderDoNotChangeDigest = {
    expr =
      digestOf "    - a/b#${sha}\n    - c/d#${sha}\n"
      == digestOf "    # x\n    - c/d#${sha}\n    - a/b#${sha}  # y\n";
    expected = true;
  };

  testSkillsKeyChangesDigest = {
    expr =
      digestOf "    - git: a/b\n      ref: ${sha}\n      skills: [x]\n"
      == digestOf "    - git: a/b\n      ref: ${sha}\n      skills: [x, y]\n";
    expected = false;
  };

  testRefChangesDigest = {
    expr = digestOf "    - a/b#${sha}\n" == digestOf "    - a/b#${sha2}\n";
    expected = false;
  };

  testDeclaringPluginChangesDigest = {
    expr =
      (guardFor { p = wrap "    - a/b#${sha}\n"; }).digest
      == (guardFor { q = wrap "    - a/b#${sha}\n"; }).digest;
    expected = false;
  };

  testApmVersionChangesDigest = {
    expr =
      digestOf "    - a/b#${sha}\n" == (import ./guard.nix { inherit lib; } {
        apmVersion = "0.35.1";
        manifests.p = wrap "    - a/b#${sha}\n";
      }).digest;
    expected = false;
  };

  testDigestIs32Hex = {
    expr = builtins.match "[0-9a-f]{32}" (digestOf "    - a/b#${sha}\n") != null;
    expected = true;
  };
}
